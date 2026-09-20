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

      # It precedes the three-column grid rather than sitting in the right rail.
      assert html =~ ~r/id="atlas-timeline".*lg:grid-cols-/s
      refute html =~ ~r/id="atlas-reader".*id="atlas-timeline"/s
    end

    test "holds a toggle and ONE range bar with two handles", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-all input[type=checkbox]")

      # Both handles live in the same bar, over one drawn track.
      assert has_element?(view, "#atlas-timeline-range.atlas-range__bar .atlas-range__track")
      assert has_element?(view, "#atlas-timeline-range #atlas-timeline-from[type=range]")
      assert has_element?(view, "#atlas-timeline-range #atlas-timeline-to[type=range]")
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

      view
      |> form("#atlas-timeline-range", %{"from" => "99999", "to" => "99999"})
      |> render_change()

      # Clamped to the last event; the end handle there is open (see below).
      path = assert_patch(view)
      assert path =~ "from=#{total - 1}"
      refute path =~ "to="
    end

    test "a handle resting on an end of the bar is an open bound", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      # "To the last event" would silently exclude whatever arrives next;
      # a handle at the far right means "to the present".
      view
      |> form("#atlas-timeline-range", %{"from" => "0", "to" => "#{total - 1}"})
      |> render_change()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
      assert render(view) =~ "full range"
    end

    test "open handles rest on the ends of the bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(
               view,
               ~s(#atlas-timeline-range[style*="--from: 0.0"][style*="--to: 1.0"])
             )

      assert has_element?(view, ~s(#atlas-timeline-from[aria-valuetext="from the start"]))
      assert has_element?(view, ~s(#atlas-timeline-to[aria-valuetext="to the present"]))
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

  describe "in range / out of range" do
    test "out of range shows the complement of the window", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      assert render(view) =~ "Showing 2 of #{total}"

      view |> element("#atlas-timeline-mode-out") |> render_click()

      assert assert_patch(view) =~ "out=1"
      assert render(view) =~ "Showing #{total - 2} of #{total}"
      assert has_element?(view, ~s(#atlas-timeline-mode-out[aria-checked="true"]))
      assert has_element?(view, "#atlas-timeline-range.is-outside")
    end

    test "works against an open bound", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=2&out=1")

      # Outside "event 2 → now" is just the two events before it.
      assert render(view) =~ "Showing 2 of #{total}"
    end

    test "in range switches back", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      view |> element("#atlas-timeline-mode-in") |> render_click()

      refute assert_patch(view) =~ "out="
    end

    test "with no window there is no outside: the switch is off", %{conn: conn} do
      total = total_events()
      {:ok, view, _} = live(conn, ~p"/atlas?out=1")

      assert has_element?(view, "#atlas-timeline-mode-out[disabled]")
      # A stray out=1 must not empty the page.
      assert render(view) =~ "Showing #{total} of #{total}"
    end

    test "clearing the range drops the mode with it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      view |> element("#atlas-timeline-clear") |> render_click()

      path = assert_patch(view)
      refute path =~ "out="
      refute path =~ "from="
    end

    test "dragging both handles to the ends drops the mode too", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")
      total = total_events()

      view
      |> form("#atlas-timeline-range", %{"from" => "0", "to" => "#{total - 1}"})
      |> render_change()

      refute assert_patch(view) =~ "out="
    end
  end

  describe "activity dots on the range bar" do
    defp dots(view, selector) do
      view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
    end

    test "every activity is a dot on the line", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert dots(view, "#atlas-timeline-range #atlas-timeline-dots .atlas-range__dot") ==
               total_events()
    end

    test "dots outside the window stay on the line, unread", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2")
      total = total_events()

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot") == total
      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-read") == 2
    end

    test "out of range flips which dots are read", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=2&out=1")

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-read") == total_events() - 2
    end

    test "the selected event is marked, and the dots do not select", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert dots(view, "#atlas-timeline-dots .atlas-range__dot.is-selected") == 1
      # Display only: the activity list, marks band and Prev / Next select.
      refute has_element?(view, "#atlas-timeline-dots [phx-click]")
    end
  end

  describe "fanning the bar out by source" do
    test "starts as one bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-timeline-lanes-toggle[aria-expanded="false"]))
      refute has_element?(view, "#atlas-timeline-lanes")
    end

    test "expands into one lane per source, and the dots move into them", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-timeline-lanes-toggle") |> render_click()

      assert assert_patch(view) =~ "lanes=1"

      assert dots(view, "#atlas-timeline-lanes .atlas-range__lane") ==
               map_size(Feed.sources(Feed))

      # Each activity is drawn once: in a lane, no longer on the single bar.
      assert dots(view, "#atlas-timeline-lanes .atlas-range__dot") == total_events()
      refute has_element?(view, "#atlas-timeline-dots")

      # The handles stay on the one bar.
      assert has_element?(view, "#atlas-timeline-from")
    end

    test "collapses back into the single bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1")

      view |> element("#atlas-timeline-lanes-toggle") |> render_click()

      refute assert_patch(view) =~ "lanes="
      assert dots(view, "#atlas-timeline-dots .atlas-range__dot") == total_events()
    end

    test "only the sources feeding the view get a lane", %{conn: conn} do
      [only | _] = Feed.sources(Feed) |> Map.keys() |> Enum.sort()
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1&sources=#{only}")

      assert dots(view, "#atlas-timeline-lanes .atlas-range__lane") == 1
      assert has_element?(view, "#atlas-timeline-lane-#{only}")
    end

    test "lanes respect the window like the single bar does", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?lanes=1&from=1&to=2")

      assert dots(view, "#atlas-timeline-lanes .atlas-range__dot.is-read") == 2
    end
  end
end
