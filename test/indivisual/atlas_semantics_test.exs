defmodule Indivisual.Atlas.SemanticsTest do
  @moduledoc """
  Where an event sits on a semantic axis. What must hold: scores come only from
  embeddings made with the axis's own model, 0 stays neutral, nothing is scored
  by guess, and none of it ever touches the record.
  """
  use Indivisual.DataCase, async: false

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Semantics
  alias Indivisual.Semantic

  defp events, do: Feed.events(Feed, [])

  defp axis(name, negative, positive) do
    {:ok, axis} =
      Semantic.create_axis(%{
        name: name,
        negative_pole: negative,
        positive_pole: positive,
        negative_examples: ["#{negative} one", "#{negative} two"],
        positive_examples: ["#{positive} one", "#{positive} two"]
      })

    {:ok, axis} = Semantic.compute_axis_vector(axis)
    axis
  end

  # Embedding runs in a task; this is when it has landed.
  defp warmed(events) do
    Semantics.subscribe()
    Semantics.warm(events)

    if Semantics.scores(events, [axis("Probe", "a", "b")]) |> map_size() < length(events) do
      assert_receive {:atlas_semantics, :updated}, 2_000
    end
  end

  test "an axis is a dimension: named, and said from its negative pole to its positive" do
    stage = axis("Stage", "plan", "built")

    assert [%{id: id, name: "Stage", says: "plan ↔ built", semantic: true}] =
             Semantics.dimensions([stage])

    assert id == Semantics.dimension_id(stage)
    assert id =~ ~r/^sem:\d+$/
  end

  test "an axis with no vector yet, or one from another model, is not a dimension" do
    {:ok, uncomputed} =
      Semantic.create_axis(%{name: "Raw", negative_pole: "a", positive_pole: "b"})

    other_model = %{axis("Other", "x", "y") | model: "some-other-model"}

    assert Semantics.dimensions([uncomputed, other_model]) == []

    # Nothing to score against: whatever is embedded carries no axis at all.
    by_axis =
      events() |> Semantics.scores([uncomputed, other_model]) |> Map.values() |> Enum.uniq()

    assert by_axis in [[], [%{}]]
  end

  test "every embedded event is scored on every axis, within -1..1" do
    events = events()
    warmed(events)
    axes = [axis("Stage", "plan", "built"), axis("Reach", "local", "regional")]

    scores = Semantics.scores(events, axes)

    assert map_size(scores) == length(events)

    for {_event_id, by_axis} <- scores, axis <- axes do
      value = by_axis[Semantics.dimension_id(axis)]
      assert is_float(value) and value >= -1.0 and value <= 1.0
    end
  end

  test "each axis fills its range: the furthest event sits at an end" do
    events = events()
    warmed(events)
    stage = axis("Stage", "plan", "built")
    id = Semantics.dimension_id(stage)

    magnitudes = events |> Semantics.scores([stage]) |> Map.values() |> Enum.map(&abs(&1[id]))

    assert_in_delta Enum.max(magnitudes), 1.0, 0.0001
  end

  test "it is a pure reading of the cache: same events, same axes, same scores" do
    events = events()
    warmed(events)
    axes = [axis("Stage", "plan", "built")]

    assert Semantics.scores(events, axes) == Semantics.scores(events, axes)
  end

  test "an event that has not been embedded is simply absent, never guessed" do
    stranger = %{
      hd(events())
      | event_id: "never:seen",
        payload: %{"title" => "Never embedded #{System.unique_integer()}"}
    }

    assert Semantics.scores([stranger], [axis("Stage", "plan", "built")]) == %{}
  end

  test "an event is read by what it says, not by its ids or plumbing" do
    event = Enum.find(events(), & &1.payload["title"])
    text = Semantics.text(event)

    assert text =~ event.payload["title"]
    refute text =~ event.event_id
    refute text =~ event.source_id
  end

  test "scoring appends nothing: the record is untouched" do
    before = events()
    warmed(before)
    Semantics.scores(before, [axis("Stage", "plan", "built")])

    assert events() == before
  end
end
