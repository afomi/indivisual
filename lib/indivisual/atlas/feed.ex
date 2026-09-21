defmodule Indivisual.Atlas.Feed do
  @moduledoc """
  The live, in-process Atlas event feed.

  Holds the canonical `Indivisual.Atlas.Log`, loaded on start from the configured
  source adapters, and broadcasts every accepted append over `Indivisual.PubSub` on
  `"atlas:feed"` so live readers update without resetting their state.

  Configure adapters with:

      config :indivisual, Indivisual.Atlas,
        sources: [Indivisual.Atlas.Sources.CivicFixture, Indivisual.Atlas.Sources.Annotations]

  Persistence: every accepted append is written to `Indivisual.Atlas.Store` before it
  enters the log or is broadcast. On boot (and on `reset/1`) the log is rebuilt
  from the adapters plus the store, so annotations and live appends survive a restart.
  If the store is unreachable the feed still serves adapter events, reports
  `status/1` as `persistence: {:error, reason}`, and refuses appends rather than
  accepting writes it cannot keep.
  """

  require Logger

  use GenServer

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Post
  alias Indivisual.Atlas.Source
  alias Indivisual.Atlas.Sources.Annotations
  alias Indivisual.Atlas.Store
  alias Indivisual.Atlas.Log

  @topic "atlas:feed"
  @default_adapters [Indivisual.Atlas.Sources.CivicFixture, Annotations]

  # --- client ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "PubSub topic for live appends."
  def topic, do: @topic

  @doc "Subscribes the caller to live appends: it will receive `{:atlas_event, %Event{}}`."
  def subscribe, do: Phoenix.PubSub.subscribe(Indivisual.PubSub, @topic)

  @doc "The current log."
  def log(server \\ __MODULE__), do: GenServer.call(server, :log)

  @doc "All events in deterministic order (see `Indivisual.Atlas.Log.events/2` for opts)."
  def events(server \\ __MODULE__, opts \\ []), do: server |> log() |> Log.events(opts)

  @doc "One event by id."
  def get_event(server \\ __MODULE__, id), do: server |> log() |> Log.get(id)

  @doc "Loaded adapters: `[%{info, sources, event_count}]`."
  def adapters(server \\ __MODULE__), do: GenServer.call(server, :adapters)

  @doc "Union of all registered sources, keyed by source id."
  def sources(server \\ __MODULE__) do
    server
    |> adapters()
    |> Enum.flat_map(fn %{info: info, sources: sources} ->
      Enum.map(sources, &Map.put(&1, :adapter, info))
    end)
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  Validates and appends one event (a map or `%Event{}`), then broadcasts it.
  Returns `{:ok, event}` or `{:error, errors}`.
  """
  def append(server \\ __MODULE__, attrs), do: GenServer.call(server, {:append, attrs})

  @doc """
  Records an annotation about the event with id `about_id`.
  `attrs` needs `"body"` and `"author"`, optionally `"kind"`.
  """
  def annotate(server \\ __MODULE__, about_id, attrs),
    do: GenServer.call(server, {:annotate, about_id, attrs})

  @doc """
  Appends a plain note (an `Indivisual.Atlas.Post` about nothing else).
  `opts`: `:mentions`, entity refs the note is about.
  """
  def post(server \\ __MODULE__, attrs, opts \\ []),
    do: GenServer.call(server, {:post, attrs, opts})

  @doc "Rebuilds the log from the source adapters plus the persisted store."
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)

  @doc """
  Feed status: `%{persistence: :ok | {:error, reason}, persisted_count: n, adapter_count: n}`.
  """
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  # --- server ---

  @impl true
  def init(opts) do
    adapters = Keyword.get(opts, :adapters, configured_adapters())
    {:ok, load(adapters)}
  end

  @impl true
  def handle_call(:log, _from, state), do: {:reply, state.log, state}

  def handle_call(:adapters, _from, state), do: {:reply, state.adapters, state}

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       persistence: state.persistence,
       persisted_count: state.persisted_count,
       adapter_count: Enum.sum(Enum.map(state.adapters, & &1.event_count))
     }, state}
  end

  def handle_call({:append, %Event{} = event}, _from, state), do: do_append(event, state)

  def handle_call({:append, attrs}, _from, state) when is_map(attrs) do
    case Event.new(attrs) do
      {:ok, event} -> do_append(event, state)
      {:error, errors} -> {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:annotate, about_id, attrs}, _from, state) do
    case Log.get(state.log, about_id) do
      nil ->
        {:reply, {:error, [{:about_event_id, "not found"}]}, state}

      about ->
        seq = state.annotation_seq + 1

        case Annotations.build(about, attrs, seq) do
          {:ok, event} -> do_append(event, %{state | annotation_seq: seq})
          {:error, errors} -> {:reply, {:error, errors}, state}
        end
    end
  end

  # Notes share the annotations' counter: both are posts, from one source.
  def handle_call({:post, attrs, opts}, _from, state) do
    seq = state.annotation_seq + 1

    case Post.build(attrs, seq, mentions: opts[:mentions] || []) do
      {:ok, event} -> do_append(event, %{state | annotation_seq: seq})
      {:error, errors} -> {:reply, {:error, errors}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, load(state.adapter_modules)}
  end

  defp do_append(_event, %{persistence: {:error, reason}} = state) do
    {:reply, {:error, [{:persistence, "unavailable: #{reason}"}]}, state}
  end

  defp do_append(event, state) do
    with {:ok, log} <- Log.append(state.log, event),
         {:ok, _} <- persist(event) do
      Phoenix.PubSub.broadcast(Indivisual.PubSub, @topic, {:atlas_event, event})

      {:reply, {:ok, event}, %{state | log: log, persisted_count: state.persisted_count + 1}}
    else
      {:error, :duplicate} ->
        {:reply, {:error, [{:event_id, "already in the log"}]}, state}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply, {:error, [{:persistence, inspect(changeset.errors)}]}, state}

      {:error, {:persistence, reason}} ->
        {:reply, {:error, [{:persistence, "write failed: #{reason}"}]}, state}
    end
  end

  defp persist(event) do
    Store.append(event)
  rescue
    # EncodeError too: a value the column cannot hold (a sequence past int4, say)
    # is a bad EVENT, and must be refused like one. Unrescued it took the whole
    # feed down — every reader's page — for one writer's malformed append.
    error in [
      Postgrex.Error,
      DBConnection.ConnectionError,
      DBConnection.OwnershipError,
      DBConnection.EncodeError
    ] ->
      {:error, {:persistence, Exception.message(error)}}
  end

  defp load(adapter_modules) do
    loaded =
      Enum.map(adapter_modules, fn mod ->
        case Source.load(mod) do
          {:ok, result} ->
            result

          {:error, {raw, errors}} ->
            raise ArgumentError,
                  "Atlas adapter #{inspect(mod)} produced an invalid event #{inspect(raw["event_id"])}: #{inspect(errors)}"
        end
      end)

    log = loaded |> Enum.flat_map(& &1.events) |> Log.new()
    {persistence, persisted} = load_persisted()

    {log, kept} =
      Enum.reduce(persisted, {log, 0}, fn event, {log, kept} ->
        case Log.append(log, event) do
          {:ok, log} ->
            {log, kept + 1}

          {:error, :duplicate} ->
            Logger.warning(
              "Atlas feed: persisted event #{event.event_id} collides with an adapter event; adapter wins"
            )

            {log, kept}
        end
      end)

    %{
      adapter_modules: adapter_modules,
      adapters:
        Enum.map(loaded, &%{info: &1.info, sources: &1.sources, event_count: length(&1.events)}),
      log: log,
      annotation_seq: max_annotation_seq(persisted),
      persistence: persistence,
      persisted_count: kept
    }
  end

  defp load_persisted do
    case Store.probe() do
      :ok ->
        {:ok, Store.all()}

      {:error, reason} ->
        Logger.warning(
          "Atlas feed: persistence unavailable (#{reason}); serving adapter events only"
        )

        {{:error, reason}, []}
    end
  end

  defp max_annotation_seq(events) do
    events
    |> Enum.filter(&(&1.source_id == Annotations.source_id()))
    |> Enum.map(fn %Event{sequence: [seq | _]} -> seq end)
    |> Enum.max(fn -> 0 end)
  end

  defp configured_adapters do
    :indivisual
    |> Application.get_env(Indivisual.Atlas, [])
    |> Keyword.get(:sources, @default_adapters)
  end
end
