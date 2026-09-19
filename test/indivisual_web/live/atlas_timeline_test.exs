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
      assert has_element?(view, "#atlas-scrubber")

      # It precedes the three-column grid rather than sitting in the right rail.
      assert html =~ ~r/id="atlas-timeline".*lg:grid-cols-/s
      refute html =~ ~r/id="atlas-reader".*id="atlas-timeline"/s
    end

    test "holds both controls: a toggle and two range dials", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-all input[type=checkbox]")
      assert has_element?(view, "#atlas-timeline-from[type=range]")
      assert has_element?(view, "#atlas-timeline-to[type=range]")
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

      view |> form("#atlas-timeline-range", %{"from" => "0", "to" => "99999"}) |> render_change()

      assert assert_patch(view) =~ "to=#{total - 1}"
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

    test "no clear button when there is no range to clear", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      refute has_element?(view, "#atlas-timeline-clear")
    end
  end

  describe "scrubbing within the range" do
    test "the scrubber still selects an event", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> form("#atlas-scrubber", %{"index" => "0"}) |> render_change()

      assert assert_patch(view) =~ "event="
    end
  end
end
