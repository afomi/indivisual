defmodule IndivisualWeb.AtlasActivitySourcesTest do
  @moduledoc """
  The compact source checklist on the activity list. It drives the same filter
  as the source nav but reads the opposite way — checked means included — so
  these guard the places the two readings could drift apart.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas

  defp source_ids, do: Atlas.sources() |> Map.keys() |> Enum.sort()

  defp checkbox(id), do: "#atlas-activity-source-#{id}"

  test "sits on the activity list, above the events it filters", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-activity-sources")

    {sources_at, _} = :binary.match(html, ~s(id="atlas-activity-sources"))
    {list_at, _} = :binary.match(html, ~s(id="atlas-activity"))
    {canvas_at, _} = :binary.match(html, ~s(id="atlas-canvas"))

    assert sources_at < list_at
    assert list_at < canvas_at
  end

  test "with no filter every source is checked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    for id <- source_ids() do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end

    refute has_element?(view, "#atlas-activity-sources-all")
  end

  test "unchecking one source leaves the rest", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")
    [first | rest] = source_ids()

    view |> element(checkbox(first)) |> render_click()

    assert has_element?(view, ~s(#{checkbox(first)}[aria-checked="false"]))

    for id <- rest do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end

    refute has_element?(view, ~s(#atlas-activity [data-source="#{first}"]))
  end

  test "re-checking the last unchecked source returns to no filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")
    [first | _] = source_ids()

    view |> element(checkbox(first)) |> render_click()
    assert has_element?(view, "#atlas-activity-sources-all")

    view |> element(checkbox(first)) |> render_click()

    refute has_element?(view, "#atlas-activity-sources-all")

    for id <- source_ids() do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end
  end

  test "the last checked source cannot be unchecked", %{conn: conn} do
    [only | _] = source_ids()
    {:ok, view, _html} = live(conn, ~p"/atlas?sources=#{only}")

    assert has_element?(view, ~s(#{checkbox(only)}[aria-disabled="true"]))

    view |> element(checkbox(only)) |> render_click()

    assert has_element?(view, ~s(#{checkbox(only)}[aria-checked="true"]))
  end

  test "all resets the filter from the checklist", %{conn: conn} do
    [only | _] = source_ids()
    {:ok, view, _html} = live(conn, ~p"/atlas?sources=#{only}")

    view |> element("#atlas-activity-sources-all") |> render_click()

    for id <- source_ids() do
      assert has_element?(view, ~s(#{checkbox(id)}[aria-checked="true"]))
    end
  end
end
