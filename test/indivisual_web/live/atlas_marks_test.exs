defmodule IndivisualWeb.AtlasMarksTest do
  @moduledoc """
  Activity can be read as a list or as marks on the timeline — the same events,
  positioned by when they happened rather than by their ordinal place. These
  cover the toggle, that marks select like list rows do, and that the choice
  rides the URL so a shared link reproduces the view.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "marks render on the timeline band", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-timeline-marks")
    assert has_element?(view, ".atlas-marks__mark")
  end

  test "the band carries time ticks, not just marks", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, ".atlas-marks__tick")
  end

  test "a mark selects its event, like a list row", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view
    |> element(~s(.atlas-marks__mark[phx-value-id="civic:eltsp:2025-06-24:council-direction"]))
    |> render_click()

    assert assert_patch(view) =~ "event="
  end

  test "the selected event is marked on the band", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view
    |> element(~s(.atlas-marks__mark[phx-value-id="civic:eltsp:2025-06-24:council-direction"]))
    |> render_click()

    assert_patch(view)

    assert has_element?(
             view,
             ~s(.atlas-marks__mark.is-selected[phx-value-id="civic:eltsp:2025-06-24:council-direction"])
           )
  end

  describe "the activity toggle" do
    test "switches between list and timeline framing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-activity-toggle[aria-pressed="false"]))

      view |> element("#atlas-activity-toggle") |> render_click()

      assert assert_patch(view) =~ "marks=1"
      assert has_element?(view, ~s(#atlas-activity-toggle[aria-pressed="true"]))
    end

    test "the choice round-trips through the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?marks=1")

      assert has_element?(view, ~s(#atlas-activity-toggle[aria-pressed="true"]))
      assert has_element?(view, ".atlas-activity--compact")
    end

    test "toggling back restores the full list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?marks=1")

      view |> element("#atlas-activity-toggle") |> render_click()

      refute assert_patch(view) =~ "marks="
      refute has_element?(view, ".atlas-activity--compact")
    end
  end

  test "narrowing the range narrows the marks", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")
    all = view |> render() |> count_marks()

    {:ok, narrowed, _} = live(conn, ~p"/atlas?from=0&to=2")
    fewer = narrowed |> render() |> count_marks()

    assert fewer < all, "the band should show the filtered window, not the whole stream"
  end

  defp count_marks(html) do
    html |> String.split("atlas-marks__mark") |> length() |> Kernel.-(1)
  end
end
