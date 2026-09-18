defmodule Indivisual.Atlas.Source do
  @moduledoc """
  Behaviour for an Atlas event source adapter.

  An adapter is the boundary between some append-only public record (a civic fixture,
  an agenda archive, a public blockchain) and the canonical `Indivisual.Atlas.Event`
  envelope. Adding a source must not require changing the Atlas interface.

  An adapter exposes:

    * `info/0`    — the adapter itself: id, label, and ingestion status
    * `sources/0` — the publishers it speaks for (each with id, title, publisher, url, kind, status)
    * `events/0`  — raw event maps, each carrying a `source_id` from `sources/0`

  `load/1` normalizes an adapter's raw events into validated envelopes, keeping the
  raw map on each event and stamping a content hash into provenance.
  """

  alias Indivisual.Atlas.Event

  @type source_info :: %{
          required(:id) => String.t(),
          required(:title) => String.t(),
          optional(:publisher) => String.t(),
          optional(:url) => String.t(),
          optional(:kind) => String.t(),
          optional(:published) => String.t(),
          required(:status) => String.t()
        }

  @type adapter_info :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:status) => String.t(),
          optional(:note) => String.t()
        }

  @callback info() :: adapter_info()
  @callback sources() :: [source_info()]
  @callback events() :: [map()]

  @doc """
  Loads an adapter: returns `{:ok, %{info, sources, events}}` with validated events,
  or `{:error, {raw, errors}}` for the first raw event that fails normalization.
  """
  def load(adapter) when is_atom(adapter) do
    info = adapter.info()
    sources = adapter.sources()
    source_ids = MapSet.new(sources, & &1.id)

    adapter.events()
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      case normalize(raw, source_ids) do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, errors} -> {:halt, {:error, {raw, errors}}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, %{info: info, sources: sources, events: Enum.reverse(events)}}
      error -> error
    end
  end

  @doc """
  Normalizes one raw source map into an `Indivisual.Atlas.Event`, preserving the raw
  payload and stamping `provenance["content_hash"]` with a hash of the raw map.
  """
  def normalize(raw, known_source_ids \\ nil) when is_map(raw) do
    raw = Map.new(raw, fn {k, v} -> {to_string(k), v} end)

    provenance =
      raw["provenance"]
      |> provenance_map()
      |> Map.put_new("content_hash", Event.content_hash(raw))

    attrs =
      raw
      |> Map.put("provenance", provenance)
      |> Map.put("raw", raw)

    with {:ok, event} <- Event.new(attrs),
         :ok <- check_source(event, known_source_ids) do
      {:ok, event}
    end
  end

  defp provenance_map(nil), do: %{}
  defp provenance_map(uri) when is_binary(uri), do: %{"uri" => uri}
  defp provenance_map(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp provenance_map(_), do: %{}

  defp check_source(_event, nil), do: :ok

  defp check_source(%Event{source_id: id}, known) do
    if MapSet.member?(known, id),
      do: :ok,
      else: {:error, [{:source_id, "is not registered by this adapter"}]}
  end
end
