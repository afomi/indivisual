defmodule IndivisualWeb.AtlasLegendTest do
  @moduledoc """
  Truth states moved from a permanent rail column into a modal behind an info
  button. What matters: every state is still documented, the dialog can be
  opened and dismissed, and it stays out of the shareable URL — a legend is
  reference material, not part of a view someone would send to someone else.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas

  test "the legend is behind a button, not in the rail", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-legend-open")
    refute has_element?(view, "#atlas-legend"), "the legend should be closed by default"
  end

  test "the button sits on the truth-state filter it explains", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    refute has_element?(view, "#atlas-projection-nav #atlas-legend-open")
    # The key to the states lives with the filter on them, in the sticky controls.
    assert has_element?(view, "#atlas-controls #atlas-activity-truth #atlas-legend-open")
  end

  test "opening shows a dialog documenting every truth state", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-legend-open") |> render_click()

    assert has_element?(view, ~s(#atlas-legend-modal [role="dialog"][aria-modal="true"]))

    html = render(view)

    for state <- Atlas.truth_states() do
      assert html =~ state, "expected the legend to document #{state}"
    end
  end

  test "every state carries a description, not just a name", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")
    view |> element("#atlas-legend-open") |> render_click()

    for state <- Atlas.truth_states() do
      desc = IndivisualWeb.AtlasLive.truth_description(state)
      assert desc != "", "#{state} has no description"
      assert render(view) =~ desc
    end
  end

  test "the close button dismisses it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-legend-open") |> render_click()
    assert has_element?(view, "#atlas-legend-modal")

    view |> element("#atlas-legend-close") |> render_click()
    refute has_element?(view, "#atlas-legend-modal")
  end

  test "Escape dismisses it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-legend-open") |> render_click()
    assert has_element?(view, "#atlas-legend-modal")

    view |> element("#atlas-legend-modal") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#atlas-legend-modal")
  end

  test "opening the legend does not change the shareable URL", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-legend-open") |> render_click()

    refute_patched(view, ~p"/atlas?legend=1")
    assert has_element?(view, "#atlas-legend-modal")
  end
end
