defmodule Indivisual.Atlas.Semantics do
  @moduledoc """
  Where an event sits on a **semantic axis**: the meaning-based dimensions the
  Spacetime scene's Graph mode is built from, and any mode can put on an axis.

  A semantic axis (`Indivisual.Semantic.Axis`) is two poles, each anchored by
  example phrases — "terse ↔ verbose", "plan ↔ built". Its vector is the
  direction from one pole's phrases to the other's in embedding space. An event
  is scored by embedding its text and projecting it onto that direction. Axes are
  rows anyone can add, so the dimensions are **customizable**: a new axis is a
  new entry in the x / y / z dropdowns.

  ## Derived, disposable, and never in the record

  Scores are a machine's reading of an event's text. They are computed from the
  stream and can be thrown away; they are not events, and nothing here appends
  one (`CLAUDE.md`: machine output never enters the stream). Embeddings are
  cached in ETS, keyed by the model and the event's content — losing them costs
  one re-embedding.

  ## The app works without a backend

  Embedding needs the configured backend (`Indivisual.Embeddings`, local Ollama
  by default). Without it nothing is scored: `scores/2` returns what it has —
  possibly nothing — and `status/0` says why, so a view can report "semantic
  scores unavailable" instead of failing or inventing positions. Embedding runs
  in a task, off whoever asked: a reader never waits on a model.
  """

  use GenServer

  require Logger

  alias Indivisual.Atlas.Event
  alias Indivisual.Embeddings
  alias Indivisual.Semantic.Axis
  alias Indivisual.Semantic.VectorMath

  @table :atlas_semantics
  @topic "atlas:semantics"
  # How long to leave an unreachable backend alone before trying it again.
  @retry_after_ms 60_000

  # ── client ───────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Subscribes the caller to `{:atlas_semantics, :updated}`, sent when new scores exist."
  def subscribe, do: Phoenix.PubSub.subscribe(Indivisual.PubSub, @topic)

  @doc """
  Asks for `events` to be embedded, if any are not yet. Returns at once; when the
  work lands, subscribers hear `{:atlas_semantics, :updated}`.
  """
  def warm(events, server \\ __MODULE__) when is_list(events) do
    GenServer.cast(server, {:warm, events})
  end

  @doc "`:idle`, `:computing`, or `{:error, reason}` — why there may be no scores."
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "The id a semantic axis has as a scene dimension."
  def dimension_id(%Axis{id: id}), do: "sem:#{id}"

  @doc """
  The axes as scene dimensions: `%{id:, name:, says:}`, where `says` reads from
  the negative pole to the positive one, the way the axis runs.
  """
  def dimensions(axes) do
    for %Axis{} = axis <- axes, usable?(axis) do
      %{
        id: dimension_id(axis),
        name: axis.name,
        says: "#{axis.negative_pole} ↔ #{axis.positive_pole}",
        semantic: true
      }
    end
  end

  @doc """
  Scores for `events` on `axes`: `%{event_id => %{dimension_id => -1.0..1.0}}`.

  Only events already embedded appear, and only axes computed with the current
  embedding model (a vector from another model lives in another space). Each
  axis is scaled by the largest magnitude among these events, so 0 stays neutral
  and the sign keeps its meaning — towards one pole or the other — while the
  spread fills the axis. Pure, given the cache.
  """
  def scores(events, axes) do
    axes = Enum.filter(axes, &usable?/1)

    raw =
      for event <- events, vector = cached(event), into: %{} do
        unit = VectorMath.normalize(vector)

        {event.event_id,
         Map.new(axes, fn axis ->
           {dimension_id(axis), VectorMath.dot_product(unit, axis.axis_vector)}
         end)}
      end

    scale =
      Map.new(axes, fn axis ->
        id = dimension_id(axis)
        {id, raw |> Map.values() |> Enum.map(&abs(&1[id])) |> Enum.max(fn -> 0.0 end)}
      end)

    Map.new(raw, fn {event_id, by_axis} ->
      {event_id,
       Map.new(by_axis, fn {id, value} ->
         {id, if(scale[id] > 0, do: Float.round(value / scale[id], 4), else: 0.0)}
       end)}
    end)
  end

  @doc "The text an event is read by: what it says, not its ids or its plumbing."
  def text(%Event{} = event) do
    payload = event.payload || %{}

    [
      Event.title(event),
      payload["summary"],
      payload["body"],
      get_in(payload, ["entity", "label"]),
      event.event_type |> to_string() |> String.replace(~r/[._]/, " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(". ")
  end

  # An axis can score only once its vector is computed, and only against
  # embeddings from the same model.
  defp usable?(%Axis{axis_vector: [_ | _], model: model}), do: model == Embeddings.model()
  defp usable?(_), do: false

  defp cached(event) do
    case :ets.lookup(@table, key(event)) do
      [{_key, vector}] -> vector
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  # By content, so an event re-read from its adapter after a restart — or the
  # same text under another id — is not embedded twice.
  defp key(event), do: {Embeddings.model(), :erlang.phash2(text(event))}

  # ── server ───────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{status: :idle, task: nil, failed_at: nil}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_cast({:warm, events}, state) do
    missing = Enum.filter(events, &is_nil(cached(&1)))

    cond do
      missing == [] -> {:noreply, state}
      # One batch at a time; whoever asks next will find what this one leaves.
      state.task -> {:noreply, state}
      backing_off?(state) -> {:noreply, state}
      true -> {:noreply, %{state | status: :computing, task: embed(missing)}}
    end
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, pairs} ->
        :ets.insert(@table, pairs)
        Phoenix.PubSub.broadcast(Indivisual.PubSub, @topic, {:atlas_semantics, :updated})
        {:noreply, %{state | status: :idle, task: nil, failed_at: nil}}

      {:error, reason} ->
        Logger.info("Atlas semantics: embedding unavailable (#{inspect(reason)})")
        Phoenix.PubSub.broadcast(Indivisual.PubSub, @topic, {:atlas_semantics, :updated})
        {:noreply, %{state | status: {:error, reason}, task: nil, failed_at: now()}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply, %{state | status: {:error, reason}, task: nil, failed_at: now()}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp embed(events) do
    Task.Supervisor.async_nolink(Indivisual.TaskSupervisor, fn ->
      with {:ok, vectors} <- Embeddings.embed(Enum.map(events, &text/1)) do
        {:ok, Enum.zip_with(events, vectors, &{key(&1), &2})}
      end
    end)
  end

  defp backing_off?(%{failed_at: nil}), do: false
  defp backing_off?(%{failed_at: at}), do: now() - at < @retry_after_ms

  defp now, do: System.monotonic_time(:millisecond)
end
