defmodule Indivisual.Explain.Cache do
  @moduledoc """
  In-memory cache of generated explanations.

  An explanation is deterministic for a given record, and the same record is
  opened by many readers, so the expensive part should happen once. Generation
  measured around 8 seconds against a local model; cached reads are immediate.

  Keyed by event id, the event's content hash, AND the model that wrote it. If a
  source record ever changes, the hash changes, so a stale explanation cannot
  outlive the text it described; and a reader who switches models gets that
  model's words, never another's served from cache.

  ETS rather than a table, deliberately. This is derived data — losing it on
  restart costs one regeneration, while persisting it would add a second write
  path to keep honest for something with no independent value.
  """

  use GenServer

  alias Indivisual.Atlas.Event

  @table :explain_cache
  # Enough to cover a working session; explanations are small.
  @max_entries 500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Cached explanation of an event by a model, or nil."
  def get(%Event{} = event, model) when is_binary(model) do
    case :ets.lookup(@table, key(event, model)) do
      [{_key, text, _at}] -> text
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Stores an explanation."
  def put(%Event{} = event, model, text) when is_binary(model) and is_binary(text) do
    :ets.insert(@table, {key(event, model), text, System.monotonic_time(:second)})
    maybe_trim()
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Number of cached explanations."
  def size do
    :ets.info(@table, :size) || 0
  rescue
    ArgumentError -> 0
  end

  @doc "Empties the cache."
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # An event's identity for caching purposes: its id plus a fingerprint of the
  # content, so a changed record never reads a stale explanation.
  defp key(%Event{event_id: id, provenance: provenance}, model) do
    {id, Map.get(provenance || %{}, "content_hash"), model}
  end

  defp maybe_trim do
    if :ets.info(@table, :size) > @max_entries do
      # Drop the oldest half rather than one at a time: trimming is rare and
      # scanning the table for every insert past the cap would not be.
      cutoff =
        @table
        |> :ets.tab2list()
        |> Enum.map(&elem(&1, 2))
        |> Enum.sort()
        |> Enum.at(div(@max_entries, 2))

      :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
