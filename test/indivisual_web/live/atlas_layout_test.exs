defmodule IndivisualWeb.AtlasLayoutTest do
  use IndivisualWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  defp at(html, id), do: html |> :binary.match(~s(id="#{id}")) |> elem(0)

  test "selectors stack above the timeline, in order", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    # Projections then sources — both full-width option rows — then the
    # timeline. Sources are handled like projections, not as a sidebar list.
    assert at(html, "atlas-projection-nav") < at(html, "atlas-source-nav")
    assert at(html, "atlas-source-nav") < at(html, "atlas-timeline")
  end

  test "columns render left-to-right: reader, activity, canvas", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    assert at(html, "atlas-timeline") < at(html, "atlas-reader"),
           "the timeline is full-width, above the columns"

    # The selected event sits left of the log it was chosen from: you read the
    # record, and the list is the index beside it.
    assert at(html, "atlas-reader") < at(html, "atlas-activity"),
           "the event detail should precede the activity log"

    assert at(html, "atlas-activity") < at(html, "atlas-canvas"),
           "activity should precede the canvas"
  end

  test "sources are toggles, not a radio group — many can be active", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    # Multi-select semantics: aria-pressed buttons, never radio inputs.
    assert html =~ ~s(id="atlas-source-nav")
    assert html =~ "aria-pressed"
  end

  test "toggling a source filters, and Show all clears it", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert html =~ "All sources shown."

    # Toggle the first source off the "all" default.
    id =
      Regex.run(~r/phx-value-id="([^"]+)"[^>]*aria-pressed/, html, capture: :all_but_first) ||
        Regex.run(~r/id="atlas-source-nav".*?phx-value-id="([^"]+)"/s, html,
          capture: :all_but_first
        )

    [source_id] = id

    filtered = view |> element(~s([phx-value-id="#{source_id}"])) |> render_click()
    assert filtered =~ "Filtering to"

    cleared = view |> element(~s(button[phx-click="clear_sources"])) |> render_click()
    assert cleared =~ "All sources shown."
  end
end
