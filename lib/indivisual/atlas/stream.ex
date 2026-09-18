defmodule Indivisual.Atlas.Stream do
  @moduledoc """
  The canonical, append-only stream of normalized Atlas events.

  Pure data structure: events are keyed by `event_id`, appended once, never mutated,
  and always read back in the deterministic order defined by `Indivisual.Atlas.Event.sort_key/1`.
  Projections are rebuilt from `events/2`, never from mutable state.
  """

  alias Indivisual.Atlas.Event

  defstruct by_id: %{}

  @type t :: %__MODULE__{by_id: %{String.t() => Event.t()}}

  @doc "Builds a stream from a list of validated events. Duplicate ids raise."
  def new(events \\ []) do
    Enum.reduce(events, %__MODULE__{}, fn event, stream ->
      case append(stream, event) do
        {:ok, stream} -> stream
        {:error, :duplicate} -> raise ArgumentError, "duplicate event_id #{event.event_id}"
      end
    end)
  end

  @doc "Appends one event. Returns `{:error, :duplicate}` if its id is already present."
  def append(%__MODULE__{by_id: by_id} = stream, %Event{event_id: id} = event) do
    if Map.has_key?(by_id, id) do
      {:error, :duplicate}
    else
      {:ok, %{stream | by_id: Map.put(by_id, id, event)}}
    end
  end

  @doc "Fetches an event by id."
  def get(%__MODULE__{by_id: by_id}, id), do: Map.get(by_id, id)

  @doc "Number of events in the stream."
  def size(%__MODULE__{by_id: by_id}), do: map_size(by_id)

  @doc """
  All events in deterministic order.

  Options:

    * `:sources` — keep only events whose `source_id` is in the list (nil = all)
    * `:until`   — keep only events up to and including this event id (nil = all)
    * `:exclude_annotations` — drop annotation events (default false)
  """
  def events(%__MODULE__{by_id: by_id}, opts \\ []) do
    sources = opts[:sources]
    until = opts[:until]

    sorted =
      by_id
      |> Map.values()
      |> Enum.sort_by(&Event.sort_key/1)
      |> maybe_filter_sources(sources)
      |> maybe_drop_annotations(opts[:exclude_annotations])

    maybe_until(sorted, until)
  end

  defp maybe_filter_sources(events, nil), do: events
  defp maybe_filter_sources(events, []), do: events

  defp maybe_filter_sources(events, sources) do
    set = MapSet.new(sources)
    Enum.filter(events, &MapSet.member?(set, &1.source_id))
  end

  defp maybe_drop_annotations(events, true), do: Enum.reject(events, &Event.annotation?/1)
  defp maybe_drop_annotations(events, _), do: events

  defp maybe_until(events, nil), do: events

  defp maybe_until(events, until) do
    case Enum.find_index(events, &(&1.event_id == until)) do
      nil -> events
      idx -> Enum.take(events, idx + 1)
    end
  end
end
