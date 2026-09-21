defmodule IndivisualWeb.AtlasSourceFilterTest do
  @moduledoc """
  The source filter, as it is on the page: the checkboxes heading the timeline's
  "By source" rows. Checked means included — all checked is no filter, and the
  last one stays on. (The standalone checklist that used to sit in column 1 is
  unmounted; its own tests are in atlas_components_test.exs.)
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas

  defp source_ids, do: Atlas.sources() |> Map.keys() |> Enum.sort()

  defp checkbox(id), do: "#atlas-timeline-lane-check-#{id}"

  test "lives on the timeline, not in column 1", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas?lanes=1")

    assert has_element?(view, "#atlas-timeline #atlas-timeline-lanes")
    refute has_element?(view, "#atlas-filters #atlas-activity-sources")
  end

  test "with no filter every source is checked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas?lanes=1")

    for id <- source_ids() do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end

    refute has_element?(view, "#atlas-timeline-lanes-count")
  end

  test "unchecking one source leaves the rest, and removes its rows", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas?lanes=1")
    [first | rest] = source_ids()

    view |> element(checkbox(first)) |> render_click()

    assert has_element?(view, ~s(#{checkbox(first)}[aria-checked="false"]))

    for id <- rest do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end

    refute has_element?(view, ~s(#atlas-activity [data-source="#{first}"]))
  end

  test "re-checking the last unchecked source returns to no filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas?lanes=1")
    [first | _] = source_ids()

    view |> element(checkbox(first)) |> render_click()
    assert assert_patch(view) =~ "sources="

    view |> element(checkbox(first)) |> render_click()
    refute assert_patch(view) =~ "sources="

    for id <- source_ids() do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end
  end

  test "the last checked source cannot be unchecked", %{conn: conn} do
    [only | _] = source_ids()
    {:ok, view, _html} = live(conn, ~p"/atlas?lanes=1&sources=#{only}")

    assert has_element?(view, ~s(#{checkbox(only)}[aria-disabled="true"]))

    view |> element(checkbox(only)) |> render_click()

    assert has_element?(view, ~s(#{checkbox(only)}[aria-checked="true"]))
  end

  test "an emptied view can still clear the source filter", %{conn: conn} do
    [only | _] = source_ids()
    {:ok, view, _html} = live(conn, ~p"/atlas?sources=#{only}&truth=none")

    view |> element("#atlas-activity-reset") |> render_click()

    refute assert_patch(view) =~ "sources="
  end
end
