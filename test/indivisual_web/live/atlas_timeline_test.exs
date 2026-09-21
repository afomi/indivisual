defmodule IndivisualWeb.AtlasTimelineTest do
  @moduledoc """
  The timeline is the one control every projection shares, so these cover the
  parts that are easy to get subtly wrong: an open-ended bound must mean "from
  the start" / "to the present" rather than silently collapsing to a point,
  and the range must survive in the URL so a view stays shareable.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed

  defp total_events, do: length(Feed.events(Feed, []))

  describe "layout" do
    test "the timeline is its own element, outside the columns", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline")
      assert has_element?(view, "#atlas-timeline-all")
      assert has_element?(view, "#atlas-timeline-range")

      # It precedes the three-column grid rather than sitting in the right rail.
      assert html =~ ~r/id="atlas-timeline".*lg:grid-cols-/s
      refute html =~ ~r/id="atlas-reader".*id="atlas-timeline"/s
    end

    test "holds a toggle and ONE range bar with two handles", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-all input[type=checkbox]")

      # Both handles live in the same bar, over one drawn track.
      assert has_element?(view, "#atlas-timeline-range.atlas-range__bar .atlas-range__track")
      assert has_element?(view, "#atlas-timeline-range #atlas-timeline-from[type=range]")
      assert has_element?(view, "#atlas-timeline-range #atlas-timeline-to[type=range]")
    end
  end

  describe "all-events toggle" do
    test "turns on and reflects in the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-timeline-all input") |> render_click()

      assert assert_patch(view) =~ "all=1"
    end

    test "clears any existing range, so one control has one meaning", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")

      view |> element("#atlas-timeline-all input") |> render_click()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
      assert path =~ "all=1"
    end
  end

  describe "all events and the range" do
    test "the handles stay live while All events is checked", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?all=1")

      refute has_element?(view, "#atlas-timeline-from[disabled]")
      refute has_element?(view, "#atlas-timeline-to[disabled]")
    end

    test "dragging a handle unchecks All events: a filter is now applied", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?all=1")
      total = total_events()

      assert has_element?(view, "#atlas-timeline-all input[checked]")

      view |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()

      path = assert_patch(view)
      refute path =~ "all=1"
      assert path =~ "from=1"
      refute has_element?(view, "#atlas-timeline-all input[checked]")
      assert render(view) =~ "Showing 3 of #{total}"
    end

    test "dragging to the very ends sets no filter, so All events stays checked", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?all=1")
      total = total_events()

      view
      |> form("#atlas-timeline-range", %{"from" => "0", "to" => "#{total - 1}"})
      |> render_change()

      assert assert_patch(view) =~ "all=1"
    end
  end

  describe "range filtering" do
    test "narrows the events the page reads", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      total = total_events()

      view |> form("#atlas-timeline-range", %{"from" => "0", "to" => "1"}) |> render_change()
      assert_patch(view)

      assert render(view) =~ "Showing 2 of #{total}"
    end

    test "an open END means 'to the present'", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=1")

      assert render(view) =~ "Showing #{total - 1} of #{total}"
    end

    test "an open START means 'from the beginning'", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?to=1")

      assert render(view) =~ "Showing 2 of #{total}"
    end

    test "neither bound set shows the full range", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      total = total_events()

      html = render(view)
      assert html =~ "Showing #{total} of #{total}"
      assert html =~ "full range"
    end

    test "a reversed range is swapped, not rejected", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> form("#atlas-timeline-range", %{"from" => "3", "to" => "1"}) |> render_change()

      path = assert_patch(view)
      assert path =~ "from=1"
      assert path =~ "to=3"
    end

    test "an out-of-bounds bound is clamped to the stream", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      total = total_events()

      view
      |> form("#atlas-timeline-range", %{"from" => "99999", "to" => "99999"})
      |> render_change()

      # Clamped to the last event; the end handle there is open (see below).
      path = assert_patch(view)
      assert path =~ "from=#{total - 1}"
      refute path =~ "to="
    end

    test "a handle resting on an end of the bar is an open bound", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      # "To the last event" would silently exclude whatever arrives next;
      # a handle at the far right means "to the present".
      view
      |> form("#atlas-timeline-range", %{"from" => "0", "to" => "#{total - 1}"})
      |> render_change()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
      assert render(view) =~ "full range"
    end

    test "open handles rest on the ends of the bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(
               view,
               ~s(#atlas-timeline-range[style*="--from: 0.0"][style*="--to: 1.0"])
             )

      assert has_element?(view, ~s(#atlas-timeline-from[aria-valuetext="from the start"]))
      assert has_element?(view, ~s(#atlas-timeline-to[aria-valuetext="to the present"]))
    end

    test "the range round-trips through the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")

      assert has_element?(view, ~s(#atlas-timeline-from[value="1"]))
      assert has_element?(view, ~s(#atlas-timeline-to[value="2"]))
    end

    test "clear range removes both bounds", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")

      assert has_element?(view, "#atlas-timeline-clear")
      view |> element("#atlas-timeline-clear") |> render_click()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
    end

    test "clear range is present but disabled when there is no range", %{conn: conn} do
      # It stays on the page: a control that comes and goes moves everything
      # under it, and its absence is harder to read than a dimmed control.
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-clear[disabled]")
    end

    test "clear range is enabled once a range is set", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")

      assert has_element?(view, "#atlas-timeline-clear")
      refute has_element?(view, "#atlas-timeline-clear[disabled]")
    end

    test "one bound alone is still a range to clear", %{conn: conn} do
      for path <- [~p"/atlas?from=2", ~p"/atlas?to=5"] do
        {:ok, view, _} = live(conn, path)

        refute has_element?(view, "#atlas-timeline-clear[disabled]"),
               "an open-ended window is still a window"
      end
    end

    test "the fit switch names the span, not the camera", %{conn: conn} do
      # It appears only when something is filtered: with nothing filtered there
      # is no second span to offer.
      {:ok, _view, html} = live(conn, ~p"/atlas?from=1&to=4")

      assert html =~ "Date range"
      assert html =~ "Span only the dates the filters leave."
      assert html =~ "Span the whole record, first activity to last."

      refute html =~ "In focus", "a label about the camera, not the data"
      refute html =~ "Whole record"
    end

    test "clear range is the third button on the in/out row", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas?from=1&to=2")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end

      assert at.("atlas-timeline-mode-out") < at.("atlas-timeline-clear"),
             "it acts on the range, so it follows the in/out pair"

      # One row holds all three...
      assert has_element?(view, ".atlas-range__actions #atlas-timeline-mode")
      assert has_element?(view, ".atlas-range__actions #atlas-timeline-clear")

      # ...but the radiogroup holds only the two radios: clearing is an action,
      # and announcing it as a third mode would have a reader hunt for a state
      # it never has.
      refute has_element?(view, "#atlas-timeline-mode #atlas-timeline-clear")
    end
  end

  describe "in range / out of range" do
    test "out of range shows the complement of the window", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      assert render(view) =~ "Showing 2 of #{total}"

      view |> element("#atlas-timeline-mode-out") |> render_click()

      assert assert_patch(view) =~ "out=1"
      assert render(view) =~ "Showing #{total - 2} of #{total}"
      assert has_element?(view, ~s(#atlas-timeline-mode-out[aria-checked="true"]))
      assert has_element?(view, "#atlas-timeline-range.is-outside")
    end

    test "works against an open bound", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=2&out=1")

      # Outside "event 2 → now" is just the two events before it.
      assert render(view) =~ "Showing 2 of #{total}"
    end

    test "in range switches back", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      view |> element("#atlas-timeline-mode-in") |> render_click()

      refute assert_patch(view) =~ "out="
    end

    test "with no window there is no outside: the switch is off", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?out=1")

      assert has_element?(view, "#atlas-timeline-mode-out[disabled]")
      # A stray out=1 must not empty the page.
      assert render(view) =~ "Showing #{total} of #{total}"
    end

    test "clearing the range drops the mode with it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      view |> element("#atlas-timeline-clear") |> render_click()

      path = assert_patch(view)
      refute path =~ "out="
      refute path =~ "from="
    end

    test "dragging both handles to the ends drops the mode too", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")
      total = total_events()

      view
      |> form("#atlas-timeline-range", %{"from" => "0", "to" => "#{total - 1}"})
      |> render_change()

      refute assert_patch(view) =~ "out="
    end
  end

  describe "activity dots on the range bar" do
    defp dots(view, selector) do
      view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
    end

    test "every activity is a dot on the line", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert dots(view, "#atlas-timeline-range #atlas-timeline-dots .atlas-range__dot") ==
               total_events()
    end

    test "dots outside the window stay on the line, unread", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot") == total
      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-read") == 2
    end

    test "out of range flips which dots are read", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-read") == total_events() - 2
    end

    test "the selected event is marked, and the dots do not select", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-selected") == 1
      # Display only: the activity list, marks band and Prev / Next select.
      refute has_element?(view, "#atlas-timeline-dots [phx-click]")
    end
  end

  describe "dates above the handles" do
    alias Indivisual.Atlas.Event
    alias IndivisualWeb.AtlasLive

    defp feed, do: Feed.events(Feed, [])
    defp day(events, i), do: events |> Enum.at(i) |> Event.effective_time() |> AtlasLive.date()

    test "each handle carries its date, inside the bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = feed()

      assert has_element?(view, "#atlas-timeline-range #atlas-timeline-range-labels")

      assert view |> element(".atlas-range__label.is-right") |> render() =~ day(events, 0)
      assert view |> element(".atlas-range__label.is-left") |> render() =~ day(events, -1)
    end

    test "labels follow the handles", %{conn: conn} do
      events = feed()
      from = 13
      to = length(events) - 3
      {:ok, view, _} = live(conn, ~p"/atlas?from=#{from}&to=#{to}")

      html = view |> element("#atlas-timeline-range-labels") |> render()
      assert html =~ day(events, from)
      assert html =~ day(events, to)
    end

    test "an open bound is labelled, and marked as open", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=13")

      assert dots(view, ".atlas-range__label.is-open") == 1
      assert dots(view, ".atlas-range__label:not(.is-open)") == 1
    end

    test "the start runs left and the end runs right, so they never collide" do
      events = feed()
      mid = div(length(events), 2)

      assert [%{side: :left}, %{side: :right}] = AtlasLive.range_labels(events, mid, mid + 1)
    end

    test "each flips inward at its own end of the bar" do
      assert [%{side: :right, x: x0}, %{side: :left, x: x1}] =
               AtlasLive.range_labels(feed(), nil, nil)

      assert {x0, x1} == {0.0, 1.0}
    end

    test "handles too close for two labels share one, held inside the bar" do
      events = feed()

      # Both at the far left: the start label has flipped rightward, straight
      # into where the end label would print.
      assert [%{side: :center, x: x, text: text}] = AtlasLive.range_labels(events, nil, 1)
      assert x > 0.0 and x < 1.0
      assert text =~ day(events, 0)
    end

    test "one date is not written twice" do
      events = feed()
      # Indexes 1 and 2 share a day in the fixture; guard the premise.
      assert day(events, 1) == day(events, 2)

      assert [%{text: text}] = AtlasLive.range_labels(events, 1, 2)
      assert text == day(events, 1)
    end

    test "no events, no labels" do
      assert AtlasLive.range_labels([], nil, nil) == []
    end
  end

  describe "fanning the bar out by source" do
    test "starts as one bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-timeline-lanes-toggle[aria-expanded="false"]))
      refute has_element?(view, "#atlas-timeline-lanes")
    end

    test "expands into one lane per source, and the dots move into them", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-timeline-lanes-toggle") |> render_click()

      assert assert_patch(view) =~ "lanes=1"

      assert dots(view, "#atlas-timeline-lanes .atlas-range__lane") ==
               map_size(Feed.sources(Feed))

      # Each activity is drawn once: in a lane, no longer on the single bar.
      assert dots(view, "#atlas-timeline-lanes .atlas-range__dot") == total_events()
      refute has_element?(view, "#atlas-timeline-dots")

      # The handles stay on the one bar.
      assert has_element?(view, "#atlas-timeline-from")
    end

    test "collapses back into the single bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1")

      view |> element("#atlas-timeline-lanes-toggle") |> render_click()

      refute assert_patch(view) =~ "lanes="
      assert dots(view, "#atlas-timeline-dots .atlas-range__dot") == total_events()
    end

    test "folded, By source still says when sources are filtered", %{conn: conn} do
      [only | _] = Feed.sources(Feed) |> Map.keys() |> Enum.sort()

      {:ok, view, _} = live(conn, ~p"/atlas")
      refute has_element?(view, "#atlas-timeline-lanes-count")

      {:ok, view, _} = live(conn, ~p"/atlas?sources=#{only}")
      refute has_element?(view, "#atlas-timeline-lanes")

      assert view |> element("#atlas-timeline-lanes-count") |> render() =~
               "1 of #{map_size(Feed.sources(Feed))}"
    end

    test "By source sits left of the bar it fans out", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/atlas")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end

      assert at.("atlas-timeline-rangebar") < at.("atlas-timeline-lanes-toggle")
      assert at.("atlas-timeline-lanes-toggle") < at.("atlas-timeline-range")
    end

    test "each lane is headed by a Sources checkbox", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1")

      for id <- Feed.sources(Feed) |> Map.keys() do
        assert has_element?(
                 view,
                 ~s(#atlas-timeline-lane-check-#{id}[role="checkbox"][aria-checked="true"])
               )
      end
    end

    test "unchecking a lane filters the view, and the lane stays to come back by", %{conn: conn} do
      [first | _] = Feed.sources(Feed) |> Map.keys() |> Enum.sort()
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1")

      view |> element("#atlas-timeline-lane-check-#{first}") |> render_click()
      assert assert_patch(view) =~ "sources="

      assert has_element?(view, ~s(#atlas-timeline-lane-check-#{first}[aria-checked="false"]))
      refute has_element?(view, ~s(#atlas-activity [data-source="#{first}"]))

      # Its row remains, dimmed and empty: it is not feeding the axis above.
      assert has_element?(view, "#atlas-timeline-lane-#{first}.is-off")
      assert dots(view, "#atlas-timeline-lane-#{first} .atlas-range__dot") == 0

      # And the same checkbox brings it back.
      view |> element("#atlas-timeline-lane-check-#{first}") |> render_click()
      refute assert_patch(view) =~ "sources="
      refute has_element?(view, "#atlas-timeline-lane-#{first}.is-off")
    end

    test "a source filter from the URL shows on the lanes", %{conn: conn} do
      [only | _] = Feed.sources(Feed) |> Map.keys() |> Enum.sort()
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1&sources=#{only}")

      # Every source keeps a lane; only the checked one is live.
      assert dots(view, "#atlas-timeline-lanes .atlas-range__lane") ==
               map_size(Feed.sources(Feed))

      assert dots(view, "#atlas-timeline-lanes .atlas-range__lane:not(.is-off)") == 1
      refute has_element?(view, "#atlas-timeline-lane-#{only}.is-off")
      assert has_element?(view, ~s(#atlas-timeline-lane-check-#{only}[aria-disabled="true"]))
    end

    test "lanes respect the window like the single bar does", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1&from=1&to=2")

      assert dots(view, "#atlas-timeline-lanes .atlas-range__dot.is-read") == 2
    end
  end
end
