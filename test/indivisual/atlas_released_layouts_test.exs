defmodule Indivisual.Atlas.ReleasedLayoutsTest do
  @moduledoc """
  Spacetime, Moment and Graph are still being worked out. They are developed
  and tested against, and never offered to a reader — so the switch must not
  draw them, the default must not open on one, and a link to one must still
  land somewhere rather than taking the page down.
  """
  # async: false — these toggle application env that other tests read.
  use ExUnit.Case, async: false

  alias Indivisual.Atlas.Scene

  setup do
    original = Application.get_env(:indivisual, :unreleased_layouts)
    on_exit(fn -> Application.put_env(:indivisual, :unreleased_layouts, original) end)
    :ok
  end

  defp as_prod(fun) do
    Application.put_env(:indivisual, :unreleased_layouts, false)
    fun.()
  end

  test "a reader is offered only the finished layouts" do
    as_prod(fn ->
      assert Enum.map(Scene.layouts(), & &1.id) == ["timeline", "map"]
    end)
  end

  test "the unfinished ones are gone from the switch, not merely disabled" do
    as_prod(fn ->
      offered = Enum.map(Scene.layouts(), & &1.id)

      for id <- ~w(space moment graph) do
        refute id in offered, "#{id} is unreleased and must not be drawn"
      end
    end)
  end

  test "the view opens on a layout that is actually offered" do
    as_prod(fn ->
      assert Scene.default_layout() in Enum.map(Scene.layouts(), & &1.id),
             "opening on a hidden layout would leave a reader unable to get back to it"
    end)
  end

  test "a link to a hidden layout lands on the default, not on nothing" do
    as_prod(fn ->
      # ?scene=graph can reach anyone; returning nil would take the page down.
      for id <- ~w(space moment graph nonsense) do
        assert %{id: "timeline"} = Scene.layout(id)
      end
    end)
  end

  test "development and tests still see all five" do
    Application.put_env(:indivisual, :unreleased_layouts, true)

    assert Enum.map(Scene.layouts(), & &1.id) ==
             ["space", "timeline", "moment", "map", "graph"]
  end

  test "all_layouts/0 is the whole set, whatever is released" do
    as_prod(fn ->
      assert length(Scene.all_layouts()) == 5
    end)
  end
end
