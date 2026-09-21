defmodule IndivisualWeb.AtlasLayoutTest do
  use IndivisualWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  defp at(html, id), do: html |> :binary.match(~s(id="#{id}")) |> elem(0)

  test "the timeline leads the page; no selector sits above it", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    refute has_element?(view, "#atlas-projection-nav")
    assert at(html, "atlas-timeline") < at(html, "atlas-activity")

    # Both earlier source controls are unmounted (they live on in
    # AtlasComponents); sources are filtered on the timeline's "By source" rows.
    refute has_element?(view, "#atlas-source-nav")
    refute has_element?(view, "#atlas-activity-sources")
    assert has_element?(view, "#atlas-timeline-lanes-toggle")
  end

  test "the controls are one block, apart from the columns they control", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    # Sticking is CSS on #atlas-controls; what the markup must guarantee is that
    # every control is inside it and nothing it controls is.
    assert has_element?(view, "#atlas-controls #atlas-timeline")

    refute has_element?(view, "#atlas-controls #atlas-activity")
    refute has_element?(view, "#atlas-controls #atlas-canvas")
    refute has_element?(view, "#atlas-controls #atlas-map-wrap")
  end

  test "columns render left-to-right: activity, reader, canvas", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    assert at(html, "atlas-timeline") < at(html, "atlas-activity"),
           "the timeline is full-width, above the columns"

    # The stream leads: it is the primary content of a visual tool, and the
    # record is what opening one of its rows reveals.
    assert at(html, "atlas-activity") < at(html, "atlas-reader"),
           "the activity stream should precede the event detail"

    assert at(html, "atlas-reader") < at(html, "atlas-canvas"),
           "the reader should precede the canvas"
  end

  test "the unmounted source nav's events are still handled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")
    [source_id | _] = Indivisual.Atlas.sources() |> Map.keys() |> Enum.sort()

    # AtlasComponents.source_nav emits these; nothing on the page does today,
    # so drive them directly to keep the contract alive for when it remounts.
    render_hook(view, "toggle_source", %{"id" => source_id})
    assert has_element?(view, "#atlas-timeline-lanes-count")

    render_hook(view, "clear_sources", %{})
    refute has_element?(view, "#atlas-timeline-lanes-count")
  end

  test "registered-unmounted components really are off the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    # One root id per entry in IndivisualWeb.AtlasComponents.unmounted/0. If one
    # of these appears, either remount it in the register or take it back out.
    roots = %{
      source_nav: "#atlas-source-nav",
      position_scrubber: "#atlas-scrubber-panel",
      projection_nav: "#atlas-projection-nav",
      source_checklist: "#atlas-activity-sources",
      feed_status: "#atlas-status",
      space: "#atlas-scatter-wrap",
      map: "#atlas-map-wrap",
      graph: "#atlas-graph",
      annotation_form: "#atlas-annotation-form"
    }

    for name <- IndivisualWeb.AtlasComponents.unmounted() do
      refute has_element?(view, Map.fetch!(roots, name)), "#{name} is registered as unmounted"
    end
  end

  test "column 1 is its own scrolling region, holding the whole activity list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    # `#atlas-list` is what app.css gives a height and a scroll of its own.
    assert has_element?(view, "#atlas-columns > #atlas-list #atlas-activity")
    assert has_element?(view, "#atlas-list #atlas-activity-title")
    refute has_element?(view, "#atlas-list #atlas-selected")
  end

  test "the entities in view are open by default, and the reader's to close", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    assert has_element?(view, "details#atlas-entities[open] #atlas-entity-list")
    # The client keeps `open` as the reader leaves it; a patch must not re-open it.
    assert has_element?(
             view,
             ~s(#atlas-entities[phx-mounted*="ignore_attrs"][phx-mounted*="open"])
           )
  end
end
