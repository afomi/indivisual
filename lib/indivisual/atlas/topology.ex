defmodule Indivisual.Atlas.Topology do
  @moduledoc """
  Derives the topological read model — entities and relationships — from a list of
  Atlas events.

  Entities come from two places: explicit `*.entity.registered` events whose payload
  carries `%{"entity" => %{"ref", "label", "kind", "geo"}}`, and any `subject_refs` or
  `actor_ref` that no registration names (these get a humanized label so nothing
  referenced is invisible). Relationships come from events whose payload carries
  `%{"relationship" => %{"from", "verb", "to"}}`; each keeps the asserting event's
  source and truth state, so no inferred link is presented as a source fact.

  Geographic coordinates are optional metadata. `layout/1` places entities on a
  deterministic ring ordered by ref, so the canvas never depends on geometry.
  """

  alias Indivisual.Atlas.Event

  @type entity :: %{
          ref: String.t(),
          label: String.t(),
          kind: String.t(),
          geo: map() | nil,
          registered: boolean(),
          event_ids: [String.t()],
          truth_state: String.t() | nil
        }

  @type relationship :: %{
          from: String.t(),
          verb: String.t(),
          to: String.t(),
          event_id: String.t(),
          source_id: String.t(),
          truth_state: String.t(),
          occurred_at: DateTime.t()
        }

  @doc "Entities touched by the events, keyed by ref, in stable order of first appearance."
  def entities(events) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      acc = register(acc, event)
      Enum.reduce(Event.affected_refs(event), acc, &touch(&2, &1, event.event_id))
    end)
    |> Map.new(fn {ref, entity} ->
      {ref, %{entity | event_ids: Enum.reverse(entity.event_ids)}}
    end)
  end

  defp touch(acc, ref, event_id) do
    entity = Map.get(acc, ref, blank_entity(ref))
    Map.put(acc, ref, %{entity | event_ids: [event_id | entity.event_ids]})
  end

  @doc "Relationships asserted by the events, in event order."
  def relationships(events) do
    events
    |> Enum.map(fn event ->
      case Event.relationship(event) do
        nil ->
          nil

        rel ->
          Map.merge(rel, %{
            event_id: event.event_id,
            source_id: event.source_id,
            truth_state: event.truth_state,
            occurred_at: Event.effective_time(event)
          })
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Refs directly connected to `ref` by any relationship, in stable order."
  def neighbors(relationships, ref) do
    relationships
    |> Enum.flat_map(fn
      %{from: ^ref, to: to} -> [to]
      %{from: from, to: ^ref} -> [from]
      _ -> []
    end)
    |> Enum.uniq()
  end

  @doc "Relationships touching `ref`."
  def relationships_for(relationships, ref) do
    Enum.filter(relationships, fn r -> r.from == ref or r.to == ref end)
  end

  @doc """
  Deterministic ring layout: entities sorted by ref, placed evenly on a circle.
  Returns `%{ref => %{x: float, y: float}}` in a 800×600 viewBox.
  """
  def layout(entities, opts \\ []) do
    refs = entities |> Map.keys() |> Enum.sort()
    n = max(length(refs), 1)
    cx = Keyword.get(opts, :cx, 400.0)
    cy = Keyword.get(opts, :cy, 300.0)
    r = Keyword.get(opts, :radius, 220.0)

    refs
    |> Enum.with_index()
    |> Map.new(fn {ref, i} ->
      angle = 2 * :math.pi() * i / n - :math.pi() / 2

      {ref,
       %{
         x: Float.round(cx + r * :math.cos(angle), 1),
         y: Float.round(cy + r * :math.sin(angle), 1)
       }}
    end)
  end

  @doc "Humanizes a ref like `place:northern-trail` into `Northern trail`."
  def humanize(ref) when is_binary(ref) do
    ref
    |> String.split(":", parts: 2)
    |> List.last()
    |> String.replace(~r/[-_]+/, " ")
    |> String.capitalize()
  end

  @doc "The kind prefix of a ref (`place`, `org`, `plan`, …), or `entity` when absent."
  def kind_of(ref) when is_binary(ref) do
    case String.split(ref, ":", parts: 2) do
      [kind, _] -> kind
      _ -> "entity"
    end
  end

  defp register(acc, %Event{payload: %{"entity" => %{"ref" => ref} = entity}} = event)
       when is_binary(ref) do
    registered = %{
      ref: ref,
      label: entity["label"] || humanize(ref),
      kind: entity["kind"] || kind_of(ref),
      geo: entity["geo"],
      registered: true,
      event_ids: [],
      truth_state: event.truth_state
    }

    Map.update(acc, ref, registered, fn existing ->
      %{registered | event_ids: existing.event_ids}
    end)
  end

  defp register(acc, _event), do: acc

  defp blank_entity(ref) do
    %{
      ref: ref,
      label: humanize(ref),
      kind: kind_of(ref),
      geo: nil,
      registered: false,
      event_ids: [],
      truth_state: nil
    }
  end
end
