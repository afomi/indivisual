defmodule IndivisualWeb.AtlasMarksTest do
  @moduledoc """
  The DOM calendar band (`?band=dom`) — the fallback for the Spacetime strip that
  draws the sticky timeline by default (see atlas_scene_test.exs). Activity reads
  as a list and as marks on the timeline — the same events,
  positioned by when they happened rather than by their ordinal place. These
  cover that marks select like list rows do and follow the range.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "marks render on the timeline band", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

    assert has_element?(view, "#atlas-timeline-marks")
    assert has_element?(view, ".atlas-marks__mark")
  end

  test "the band carries time ticks, not just marks", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

    assert has_element?(view, ".atlas-marks__tick")
  end

  test "a mark selects its event, like a list row", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

    view
    |> element(~s(.atlas-marks__mark[phx-value-id="civic:eltsp:2025-06-24:council-direction"]))
    |> render_click()

    assert assert_patch(view) =~ "event="
  end

  test "the selected event is marked on the band", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

    view
    |> element(~s(.atlas-marks__mark[phx-value-id="civic:eltsp:2025-06-24:council-direction"]))
    |> render_click()

    assert_patch(view)

    assert has_element?(
             view,
             ~s(.atlas-marks__mark.is-selected[phx-value-id="civic:eltsp:2025-06-24:council-direction"])
           )
  end

  test "the activity list has no density toggle", %{conn: conn} do
    # Removed 2026-09-20: it hid one line per row and cost a URL param. An old
    # ?dense=1 link must still load, as the plain list.
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom&dense=1")

    refute has_element?(view, "#atlas-activity-toggle")
    assert has_element?(view, "#atlas-activity li[data-source]")
  end

  test "every activity in view has a mark, and so does whichever is selected", %{conn: conn} do
    alias Indivisual.Atlas.Feed
    events = Feed.events(Feed, [])

    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")
    assert count_marks(render(view)) == length(events)

    # Any row picked from the list is findable on the band.
    for event <- events do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[band: "dom", event: event.event_id]}")

      assert has_element?(
               view,
               ~s(.atlas-marks__mark.is-selected[phx-value-id="#{event.event_id}"])
             ),
             "#{event.event_id} is selected but has no mark"
    end
  end

  describe "the band holds its height" do
    test "it stays on the page when the filters leave nothing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?band=dom&entity=thing:nowhere")

      # Removing the band would make everything under it jump. The band now
      # draws the whole record whatever the filters do, so the marks are still
      # there — every one of them dimmed.
      assert has_element?(view, "#atlas-timeline-marks")
      assert has_element?(view, ".atlas-marks__mark.is-filtered")
      refute has_element?(view, ".atlas-marks__mark:not(.is-filtered)")
    end

    test "marks are inked when the filters leave them", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

      assert has_element?(view, ".atlas-marks__mark")
      refute has_element?(view, ".atlas-marks__mark.is-filtered")
    end

    test "the stylesheet keeps a 96px floor under it" do
      # Height follows the lane count, which follows the filters; the floor is
      # CSS, so this is the only place a regression would show before a browser.
      css = File.read!("assets/css/app.css")
      [rule] = Regex.run(~r/\n\.atlas-marks \{[^}]*\}/, css)

      assert rule =~ "height: max(96px,"
    end
  end

  test "narrowing the range dims marks instead of removing them", %{conn: conn} do
    # Rebuilding the band from only what survives a filter rescales its span
    # and lane count, so every remaining mark jumps. The record has not
    # changed, so the band does not either: filtered marks keep their place
    # and lose their ink.
    {:ok, view, _} = live(conn, ~p"/atlas?band=dom")
    all = view |> render() |> count_marks()

    {:ok, narrowed, html} = live(conn, ~p"/atlas?band=dom&from=0&to=2")

    assert count_marks(html) == all, "the band must keep every mark of the record"
    assert has_element?(narrowed, ".atlas-marks__mark.is-filtered")

    inked =
      html
      |> String.split("atlas-marks__mark")
      |> Enum.count(&(not String.contains?(&1, "is-filtered")))

    assert inked < all, "the narrowed window should ink fewer marks"
  end

  defp count_marks(html) do
    html |> String.split("atlas-marks__mark") |> length() |> Kernel.-(1)
  end
end
