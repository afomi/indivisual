defmodule Indivisual.Atlas.Projections do
  @moduledoc """
  Named, reproducible Atlas projections (CQRS read models).

  A projection is a pure function of the event list plus explicit options. The same
  events and options always produce the same read model; a projection never mutates
  or reinterprets source events. A lens (source filter, selected event window,
  focused entity) changes what is read, not what was recorded.

  | Projection   | Question it answers |
  |--------------|---------------------|
  | `activity`   | What changed, in source order, and who/what did it affect? |
  | `entity`     | What events, relationships, sources, and unresolved items surround this entity? |
  | `topology`   | Which entities are connected by the selected event window or source filter? |
  | `provenance` | What is observed directly, reported by a source, proposed, adopted, or delivered? |

  Every read model carries `:entities`, `:relationships`, and `:positions` so the same
  canvas can render any projection, plus projection-specific fields.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Topology

  @definitions [
    %{
      id: "activity",
      name: "Activity",
      question: "What changed, in source order, and who or what did it affect?"
    },
    %{
      id: "entity",
      name: "Entity context",
      question: "What events, relationships, sources, and unresolved items surround this entity?"
    },
    %{
      id: "topology",
      name: "Topology",
      question: "Which entities are connected by the selected event window or source filter?"
    },
    %{
      id: "provenance",
      name: "Provenance",
      question:
        "What is observed directly, reported by a source, proposed, adopted, or delivered?"
    }
  ]

  @unsettled ~w(reported proposed)

  @doc "All projection definitions."
  def list, do: @definitions

  @doc "A projection definition by id, or nil."
  def get(id), do: Enum.find(@definitions, &(&1.id == id))

  @doc "The default projection id."
  def default_id, do: "activity"

  @doc """
  Materializes projection `id` over `events` (already filtered by source and window
  as the caller wishes).

  Options:

    * `:entity` — focused entity ref (used by `entity`; ignored otherwise)
    * `:until`  — selected event id; `topology` narrows to the window up to it

  Returns a read model map with at least `:projection`, `:entities`, `:relationships`,
  `:positions`, and `:event_count`.
  """
  def materialize(id, events, opts \\ [])

  def materialize("activity", events, _opts) do
    entities = Topology.entities(events)
    relationships = Topology.relationships(events)

    items =
      Enum.map(events, fn event ->
        %{
          event: event,
          affected: Event.affected_refs(event),
          annotation: Event.annotation?(event)
        }
      end)

    base("activity", entities, relationships, events)
    |> Map.put(:items, items)
  end

  def materialize("entity", events, opts) do
    all_entities = Topology.entities(events)
    all_relationships = Topology.relationships(events)
    ref = opts[:entity]

    if is_nil(ref) or not Map.has_key?(all_entities, ref) do
      base("entity", all_entities, all_relationships, events)
      |> Map.merge(%{entity: nil, events: [], sources: [], unresolved: []})
    else
      relationships = Topology.relationships_for(all_relationships, ref)
      keep = MapSet.new([ref | Topology.neighbors(all_relationships, ref)])
      entities = Map.filter(all_entities, fn {r, _} -> MapSet.member?(keep, r) end)
      touching = Enum.filter(events, &(ref in Event.affected_refs(&1)))

      base("entity", entities, relationships, events)
      |> Map.merge(%{
        entity: Map.fetch!(all_entities, ref),
        events: touching,
        sources: touching |> Enum.map(& &1.source_id) |> Enum.uniq(),
        unresolved: Enum.filter(touching, &(&1.truth_state in @unsettled))
      })
    end
  end

  def materialize("topology", events, opts) do
    window =
      case opts[:until] do
        nil ->
          events

        until ->
          case Enum.find_index(events, &(&1.event_id == until)) do
            nil -> events
            idx -> Enum.take(events, idx + 1)
          end
      end

    relationships = Topology.relationships(window)
    entities = Topology.entities(window)
    connected = relationships |> Enum.flat_map(&[&1.from, &1.to]) |> MapSet.new()
    entities = Map.filter(entities, fn {ref, _} -> MapSet.member?(connected, ref) end)

    base("topology", entities, relationships, events)
    |> Map.put(:window_size, length(window))
  end

  def materialize("provenance", events, _opts) do
    entities = Topology.entities(events)
    relationships = Topology.relationships(events)

    groups =
      Enum.map(Event.truth_states(), fn state ->
        %{truth_state: state, events: Enum.filter(events, &(&1.truth_state == state))}
      end)

    counts = Map.new(groups, fn %{truth_state: s, events: es} -> {s, length(es)} end)

    base("provenance", entities, relationships, events)
    |> Map.merge(%{groups: groups, counts: counts})
  end

  def materialize(_unknown, events, opts), do: materialize(default_id(), events, opts)

  defp base(id, entities, relationships, events) do
    %{
      projection: id,
      entities: entities,
      relationships: relationships,
      positions: Topology.layout(entities),
      event_count: length(events)
    }
  end
end
