defmodule Indivisual.Atlas.Store do
  @moduledoc """
  Durable, append-only persistence for Atlas events accepted at runtime.

  Only events appended through the feed (annotations, live appends) are stored.
  Adapter-seeded events are rebuilt from their adapter on boot, so the store plus the
  adapters is always enough to reproduce the stream.
  """

  import Ecto.Query, warn: false

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.EventRecord
  alias Indivisual.Repo

  @doc "Inserts one event. Returns `{:ok, event}`, `{:error, :duplicate}`, or `{:error, changeset}`."
  def append(%Event{} = event) do
    case event |> EventRecord.from_event() |> Repo.insert() do
      {:ok, _record} ->
        {:ok, event}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :event_id),
          do: {:error, :duplicate},
          else: {:error, changeset}
    end
  end

  @doc "All persisted events, in insertion order (the stream re-sorts deterministically)."
  def all do
    Repo.all(from r in EventRecord, order_by: [asc: r.id]) |> Enum.map(&EventRecord.to_event/1)
  end

  @doc "Number of persisted events."
  def count, do: Repo.aggregate(EventRecord, :count)

  @doc """
  Probes the store. Returns `:ok` when the table is reachable, else `{:error, reason}`
  so the feed can report persistence status explicitly instead of failing silently.
  """
  def probe do
    count()
    :ok
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, Exception.message(error)}
  end
end
