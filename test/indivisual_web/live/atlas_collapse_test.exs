defmodule IndivisualWeb.AtlasCollapseTest do
  @moduledoc """
  The timeline and scrubber each fold to a line of text. What matters is that
  collapsing hides the CONTROLS but not the STATE — a folded band still says
  what it is filtering to — and that the choice rides the URL so a shared link
  reproduces the layout.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # `hidden` is an attribute, so presence in the DOM is not visibility.
  defp hidden?(view, selector) do
    has_element?(view, "#{selector}[hidden]")
  end

  describe "timeline" do
    test "opens expanded, with its controls", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-timeline-collapse[aria-expanded="true"]))
      refute hidden?(view, "#atlas-timeline-body")
    end

    test "collapsing folds the controls and keeps the readout", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-timeline-collapse") |> render_click()
      assert assert_patch(view) =~ "tl=0"

      assert hidden?(view, "#atlas-timeline-body")
      assert has_element?(view, "#atlas-timeline-panel #atlas-timeline-readout")
      assert has_element?(view, ~s(#atlas-timeline-collapse[aria-expanded="false"]))
    end

    test "collapsed, the readout still reports the filter", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?tl=0&from=0&to=1")

      readout = view |> element("#atlas-timeline-readout") |> render()
      assert readout =~ "Showing 2 of"
    end

    test "the collapsed state round-trips through the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?tl=0")

      assert has_element?(view, ~s(#atlas-timeline-collapse[aria-expanded="false"]))
      assert hidden?(view, "#atlas-timeline-body")
    end

    test "expanding again restores the controls", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?tl=0")

      view |> element("#atlas-timeline-collapse") |> render_click()

      refute assert_patch(view) =~ "tl="
      refute hidden?(view, "#atlas-timeline-body")
    end
  end

  describe "position" do
    # The Position scrubber panel is unmounted (AtlasComponents.position_scrubber);
    # its panel tests moved to atlas_components_test.exs. What stays on the page
    # is the readout.
    test "the scrubber panel is not on the page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-scrubber-panel")
      refute has_element?(view, "#atlas-scrubber")
    end

    test "the one readout still reports position", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      position = view |> element("#atlas-timeline-position") |> render()
      assert position =~ ~r/event \d+/
      assert position =~ ~r/\d{4}-\d{2}-\d{2}/
    end

    test "count, range, and position are one readout, not three", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-readout #atlas-timeline-position")
      assert html =~ "full range"
      refute has_element?(view, "#atlas-timeline-summary")
      refute has_element?(view, "#atlas-scrubber-summary")
    end

    test "the unmounted panel's events are still handled", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      # Nothing on the page emits these today; drive them directly so the
      # contract survives until the panel is remounted.
      render_hook(view, "scrub", %{"index" => "0"})
      assert assert_patch(view) =~ "event="

      render_hook(view, "toggle_scrubber", %{})
      assert assert_patch(view) =~ "sc=0"
    end
  end

  test "the expanded default stays out of the URL", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-legend-open") |> render_click()
    html = render(view)

    refute html =~ "tl=1", "the default state should not clutter shared links"
    refute html =~ "sc=1"
  end
end
