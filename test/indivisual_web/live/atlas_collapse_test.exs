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
      assert hidden?(view, "#atlas-timeline-summary")
    end

    test "collapsing folds the controls and shows a text summary", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-timeline-collapse") |> render_click()
      assert assert_patch(view) =~ "tl=0"

      assert hidden?(view, "#atlas-timeline-body")
      refute hidden?(view, "#atlas-timeline-summary")
      assert has_element?(view, ~s(#atlas-timeline-collapse[aria-expanded="false"]))
    end

    test "the collapsed summary still reports the filter", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?tl=0&from=0&to=1")

      summary = view |> element("#atlas-timeline-summary") |> render()
      assert summary =~ "2 of"
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

  describe "scrubber" do
    test "collapses independently of the timeline", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-scrubber-collapse") |> render_click()
      assert assert_patch(view) =~ "sc=0"

      assert hidden?(view, "#atlas-scrubber")
      # The timeline above is untouched.
      refute hidden?(view, "#atlas-timeline-body")
    end

    test "the collapsed summary still reports position", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?sc=0")

      summary = view |> element("#atlas-scrubber-summary") |> render()
      assert summary =~ "Event"
      assert summary =~ " of "
    end

    test "both can be collapsed at once", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?tl=0&sc=0")

      assert hidden?(view, "#atlas-timeline-body")
      assert hidden?(view, "#atlas-scrubber")
      refute hidden?(view, "#atlas-timeline-summary")
      refute hidden?(view, "#atlas-scrubber-summary")
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
