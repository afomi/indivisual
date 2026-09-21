defmodule IndivisualWeb.AtlasAxisBoundsTest do
  @moduledoc """
  A layout says what an axis MEANS; its poles say where it currently runs. When
  the date range moves, the frame has to move with it — an axis that reads the
  same however far the range is narrowed has stopped describing the view.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias IndivisualWeb.AtlasLive

  defp depth_rail(view) do
    view
    |> element(~s([data-axis="z"]))
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
  end

  test "the z poles name the span in view", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?scene=space")

    assert depth_rail(view) =~ "2024-04-09", "the earliest activity in view"
  end

  test "narrowing the date range moves the edges", %{conn: conn} do
    {:ok, wide, _} = live(conn, ~p"/atlas?scene=space")
    {:ok, narrow, _} = live(conn, ~p"/atlas?scene=space&from=4&to=8")

    refute depth_rail(wide) == depth_rail(narrow),
           "the frame must answer to the sliders, not read the same whatever is in view"
  end

  test "the edges follow a range set live, not only on load", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?scene=space")
    before = depth_rail(view)

    view |> form("#atlas-timeline-range", %{"from" => "4", "to" => "8"}) |> render_change()
    assert_patch(view)

    refute depth_rail(view) == before,
           "moving a slider must refresh the edges"
  end

  describe "scene_axis_bounds/2" do
    setup do
      %{events: Feed.events(Feed, [])}
    end

    test "names the first and last moment in view", %{events: events} do
      assert %{z: %{low: low, high: high}} = AtlasLive.scene_axis_bounds(events, "space")
      assert low =~ ~r/^\d{4}-\d{2}-\d{2}$/
      assert high =~ ~r/^\d{4}-\d{2}-\d{2}$/
      refute low == high
    end

    test "a one-day range says so once, rather than twice", %{events: events} do
      same_day = Enum.take(events, 3)

      assert %{z: %{low: _, high: "same day"}} = AtlasLive.scene_axis_bounds(same_day, "space")
    end

    test "a layout with no time axis gets no dates", %{events: events} do
      # The Map folds z flat: there is no axis for a span of dates to run along,
      # and stamping them on one that means something else would make the bar lie.
      assert AtlasLive.scene_axis_bounds(events, "map") == %{}
    end

    test "an empty view has no bounds to state" do
      assert AtlasLive.scene_axis_bounds([], "space") == %{}
    end
  end
end
