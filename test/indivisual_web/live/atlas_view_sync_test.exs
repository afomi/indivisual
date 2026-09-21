defmodule IndivisualWeb.AtlasViewSyncTest do
  @moduledoc """
  Two tabs as one view. Tabs on the same `?v=` token keep what they READ in
  common — filters, range, selection — and keep how they SHOW it to themselves,
  which is what lets the timeline detach into its own tab and still drive the
  view. These run two LiveViews side by side, as two tabs would be.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias IndivisualWeb.AtlasLive.ViewSync

  defp events, do: Feed.events(Feed, [])

  defp rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#atlas-activity li[data-source]")
    |> Enum.count()
  end

  # A truth state some, but not all, events carry — so filtering by it shows.
  defp partial_state do
    events()
    |> Enum.frequencies_by(& &1.truth_state)
    |> Enum.find(fn {_state, n} -> n < length(events()) end)
    |> elem(0)
  end

  # The other tab has handled everything sent to it so far.
  defp settle(view), do: _ = :sys.get_state(view.pid)

  describe "ViewSync" do
    test "tokens are URL-safe, and only ours are accepted" do
      token = ViewSync.token()

      assert ViewSync.parse_token(token) == token
      assert ViewSync.parse_token("short") == nil
      assert ViewSync.parse_token("has spaces and/slashes") == nil
      assert ViewSync.parse_token(String.duplicate("a", 200)) == nil
      assert ViewSync.parse_token(nil) == nil
    end

    test "what is read is shared; how it is shown is not" do
      params = %{
        "truth" => "observed",
        "from" => "2",
        "scene" => "map",
        "pane" => "view",
        "v" => "x"
      }

      assert ViewSync.shared(params) == %{"truth" => "observed", "from" => "2"}

      assert MapSet.disjoint?(
               MapSet.new(ViewSync.shared_keys()),
               MapSet.new(ViewSync.local_keys())
             )
    end

    test "adopting another tab's state keeps this tab's own furniture" do
      own = %{"v" => "tok12345", "pane" => "timeline", "scene" => "map", "truth" => "observed"}
      theirs = %{"entity" => "plan:eltsp"}

      # Their shared state replaces ours wholesale — our old truth filter goes.
      assert ViewSync.adopt(own, theirs) == %{
               "v" => "tok12345",
               "pane" => "timeline",
               "scene" => "map",
               "entity" => "plan:eltsp"
             }
    end
  end

  describe "two tabs on one token" do
    setup %{conn: conn} do
      token = ViewSync.token()
      {:ok, a, _} = live(conn, ~p"/atlas?#{[v: token]}")
      {:ok, b, _} = live(conn, ~p"/atlas?#{[v: token]}")
      %{a: a, b: b, token: token}
    end

    test "a filter set in one narrows the other", %{a: a, b: b} do
      state = partial_state()
      all = rows(b)

      a |> element("#atlas-activity-truth-#{state}") |> render_click()
      assert_patch(a)

      assert assert_patch(b) =~ "truth="
      assert rows(b) < all
      assert rows(b) == rows(a)
    end

    test "the date range dragged in one moves the other", %{a: a, b: b} do
      a |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()

      path = assert_patch(b)
      assert path =~ "from=1"
      assert path =~ "to=3"
      assert rows(b) == 3
    end

    test "a record opened in one opens in the other", %{a: a, b: b} do
      a |> element("#atlas-activity-0 button") |> render_click()
      chosen = assert_patch(a)

      assert assert_patch(b) =~ "event="

      assert a |> element("#atlas-selected-title") |> render() ==
               b |> element("#atlas-selected-title") |> render()

      assert chosen =~ "event="
    end

    test "it goes both ways, and does not echo back and forth", %{a: a, b: b} do
      b |> form("#atlas-timeline-range", %{"from" => "2", "to" => "4"}) |> render_change()
      assert_patch(b)
      assert assert_patch(a) =~ "from=2"

      # Nothing further arrives: the change is adopted once, not bounced.
      settle(a)
      settle(b)
      refute_receive {_ref, {:patch, _topic, _}}, 50
    end

    test "how a tab shows the view stays its own: layout is not shared", %{a: a, b: b} do
      a |> element("#atlas-scene-layout-map") |> render_click()
      assert assert_patch(a) =~ "scene=map"

      settle(b)
      assert b |> element("#atlas-scene") |> render() =~ ~s(data-layout="moment")
    end

    test "every link a tab makes keeps it on the view", %{a: a, token: token} do
      a |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()

      assert assert_patch(a) =~ "v=#{token}"
    end

    test "but a shared link is a copy of the view, not a seat at it", %{a: a, token: token} do
      refute a |> element("#atlas-share-copy") |> render() =~ token
    end
  end

  test "a tab arriving late is brought up to date by one already there", %{conn: conn} do
    token = ViewSync.token()
    {:ok, a, _} = live(conn, ~p"/atlas?#{[v: token, from: 1, to: 3]}")
    {:ok, late, _} = live(conn, ~p"/atlas?#{[v: token]}")

    path = assert_patch(late)
    assert path =~ "from=1"
    assert rows(late) == 3
    assert rows(a) == 3
  end

  test "different tokens are different views", %{conn: conn} do
    {:ok, a, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token()]}")
    {:ok, other, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token()]}")
    all = rows(other)

    a |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()
    assert_patch(a)

    settle(other)
    assert rows(other) == all
  end

  test "with no token a tab is on its own, as before", %{conn: conn} do
    {:ok, a, _} = live(conn, ~p"/atlas")
    {:ok, b, _} = live(conn, ~p"/atlas")
    all = rows(b)

    a |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()
    refute assert_patch(a) =~ "v="

    settle(b)
    assert rows(b) == all
  end

  test "a token that is not one of ours is ignored", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?v=no")

    view |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()
    refute assert_patch(view) =~ "v="
  end

  describe "panes" do
    test "the whole page offers to detach its controls, as a plain link to a new tab", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      link = view |> element("#atlas-detach") |> render()
      assert link =~ "pane=timeline"
      assert link =~ "from=1"
      assert [_, token] = Regex.run(~r/v=([A-Za-z0-9_-]{8,})/, link)

      # One tab per view, not one per click: a window named after the view.
      assert link =~ ~s(target="atlas-timeline-#{token}")
    end

    test "detaching turns this tab into the view, on the token the new tab was given", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas")

      [_, token] =
        Regex.run(~r/v=([A-Za-z0-9_-]{8,})/, view |> element("#atlas-detach") |> render())

      view |> element("#atlas-detach") |> render_click()

      path = assert_patch(view)
      assert path =~ "pane=view"
      assert path =~ "v=#{token}"

      refute has_element?(view, "#atlas-controls")
      assert has_element?(view, "#atlas-columns")
      assert has_element?(view, "#atlas-reattach")
    end

    test "the timeline pane is the controls and nothing else", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "timeline"]}")

      assert has_element?(view, "#atlas-controls #atlas-timeline")
      assert has_element?(view, "#atlas-controls #atlas-activity-truth")
      refute has_element?(view, "#atlas-columns")
      # It cannot detach from itself.
      refute has_element?(view, "#atlas-detach")
    end

    test "a detached timeline drives the view tab", %{conn: conn} do
      token = ViewSync.token()
      {:ok, main, _} = live(conn, ~p"/atlas?#{[v: token, pane: "view"]}")
      {:ok, timeline, _} = live(conn, ~p"/atlas?#{[v: token, pane: "timeline"]}")

      timeline |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()

      path = assert_patch(main)
      assert path =~ "from=1"
      # Each stays the pane it was.
      assert path =~ "pane=view"
      assert rows(main) == 3
    end

    test "reattaching brings the controls back, and the timeline tab is told", %{conn: conn} do
      token = ViewSync.token()
      {:ok, main, _} = live(conn, ~p"/atlas?#{[v: token, pane: "view"]}")
      {:ok, timeline, _} = live(conn, ~p"/atlas?#{[v: token, pane: "timeline"]}")

      main |> element("#atlas-reattach") |> render_click()

      path = assert_patch(main)
      refute path =~ "pane="
      assert path =~ "v=#{token}"
      assert has_element?(main, "#atlas-controls")

      settle(timeline)
      assert timeline |> element("#atlas-pane-note") |> render() =~ "took its timeline back"
    end

    test "an unknown pane is the whole page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?pane=nope")

      assert has_element?(view, "#atlas-controls")
      assert has_element?(view, "#atlas-columns")
    end

    test "only the detached timeline drops the page chrome", %{conn: conn} do
      {:ok, timeline, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "timeline"]}")

      # `.atlas--bare` is what the stylesheet hides the masthead and footer on.
      assert has_element?(timeline, "#atlas.atlas--bare")
      refute has_element?(timeline, "#atlas-title")

      # The view tab is still the page: it has only lent its controls out.
      {:ok, view, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "view"]}")

      assert has_element?(view, "#atlas.atlas--pane")
      refute has_element?(view, "#atlas.atlas--bare")
      # …but the tagline introduces the whole page, and shows only there.
      refute has_element?(view, "#atlas-title")

      {:ok, whole, _} = live(conn, ~p"/atlas")

      refute has_element?(whole, "#atlas.atlas--pane")
      refute has_element?(whole, "#atlas.atlas--bare")
      assert has_element?(whole, "#atlas-title")
    end

    test "opening the timeline again lands in the same tab it was detached into", %{conn: conn} do
      token = ViewSync.token()
      {:ok, view, _} = live(conn, ~p"/atlas?#{[v: token, pane: "view"]}")

      assert view |> element("#atlas-detach-again") |> render() =~
               ~s(target="atlas-timeline-#{token}")
    end

    test "the view pane says so in a banner above the nav, not in the page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "view"]}")

      assert view |> element("#atlas-pane-banner #atlas-pane-note") |> render() =~
               "in another tab, and still drive this view"

      assert has_element?(view, "#atlas-pane-banner #atlas-reattach")
      assert has_element?(view, "#atlas-pane-banner #atlas-detach-again")
      refute has_element?(view, "#atlas-viewbar #atlas-pane-note")

      # Only the view pane: the whole page and the timeline pane have no banner.
      {:ok, whole, _} = live(conn, ~p"/atlas")
      refute has_element?(whole, "#atlas-pane-banner")

      {:ok, timeline, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "timeline"]}")
      refute has_element?(timeline, "#atlas-pane-banner")
      # The timeline pane has a banner of its own, in the other tone, in flow.
      assert has_element?(timeline, "#atlas-timeline-banner.bg-indigo-600 #atlas-pane-note")
      refute has_element?(timeline, "#atlas-timeline-banner.fixed")
      assert has_element?(timeline, "#atlas-timeline-banner #atlas-pane-whole")
      assert has_element?(view, "#atlas-pane-banner.bg-gray-900.fixed")
    end

    test "reattaching brings the chrome back", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[v: ViewSync.token(), pane: "view"]}")

      view |> element("#atlas-reattach") |> render_click()

      refute has_element?(view, "#atlas.atlas--pane")
      refute has_element?(view, "#atlas.atlas--bare")
      assert has_element?(view, "#atlas-title")
    end
  end
end
