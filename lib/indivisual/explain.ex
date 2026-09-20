defmodule Indivisual.Explain do
  @moduledoc """
  Plain-language explanation of one event, in its context.

  This is the half of "what does this mean?" that a lookup table cannot answer.
  `Indivisual.Atlas.Glossary` defines the vocabulary — `content_hash` means the
  same thing on every card — and those definitions stay static because a written
  one is faster and more accurate than a generated one. What is left is
  genuinely contextual: what does *this* event say, what does it touch, and what
  else in the stream refers to the same things.

  Configured like `Indivisual.Embeddings`, and for the same reason: the app must
  work fully without a backend. Adapters return `{:error, :unavailable}` rather
  than raising, and the UI offers the explanation only when one is configured.

      config :indivisual, Indivisual.Explain,
        adapter: Indivisual.Explain.Ollama,
        url: "http://localhost:11434",
        model: "qwen3:8b"

  The explanation is **ephemeral**: it is shown, not stored, and it never
  becomes an event. An append-only civic log records what people and sources
  assert; a machine paraphrase of an existing event is neither, and writing one
  into the stream would put an unattributable claim beside sourced ones.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Explain.Cache

  @callback explain(prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Whether an explanation backend is configured and enabled."
  def available?, do: Keyword.get(config(), :enabled, true) and not is_nil(adapter())

  @doc "The configured adapter module."
  def adapter, do: Keyword.get(config(), :adapter)

  @doc "The configured model name."
  def model, do: Keyword.get(config(), :model, "qwen3:8b")

  @doc "Base URL of the backend."
  def url, do: Keyword.get(config(), :url, "http://localhost:11434")

  @doc """
  Explains `event` given the surrounding `events`.

  Returns `{:ok, text}` or `{:error, reason}` — `:unavailable` when no backend
  is configured or reachable.
  """
  def explain_event(%Event{} = event, events, opts \\ []) do
    cond do
      not available?() ->
        {:error, :unavailable}

      cached = Keyword.get(opts, :cache, true) && Cache.get(event) ->
        {:ok, cached}

      true ->
        event
        |> prompt_for(events, Keyword.get(opts, :sources, %{}))
        |> adapter().explain(opts)
        |> tap(fn
          {:ok, text} -> Cache.put(event, text)
          _ -> :ok
        end)
    end
  end

  @doc "Whether an explanation for this event is already cached."
  def cached?(%Event{} = event), do: not is_nil(Cache.get(event))

  @doc """
  Builds the prompt for one event.

  Public so it can be tested without a model: the prompt is the part we control
  and the part that decides whether the answer is grounded, so it is worth
  asserting on directly.
  """
  def prompt_for(%Event{} = event, events, sources \\ %{}) do
    related = related_events(event, events)

    """
    You are explaining one record from a civic event log to someone reading it \
    for the first time. They can see the record; they do not know the jargon.

    Write 2-3 short sentences in plain language. Say what happened, who said so, \
    and what it affects.

    Use ONLY the facts written in the record below. Do not add purposes, \
    benefits, examples or background that are not stated there. If the record \
    does not say what something is for, do not say what it is for. Saying less \
    is correct; inventing context is not.

    Do not restate the field names. Do not use the words "event", "payload", or \
    "truth state" — describe what they mean instead.

    RECORD
    Type: #{event.event_type}
    Title: #{Event.title(event)}
    #{summary_line(event)}Asserted by: #{source_label(sources, event.source_id)}
    How settled: #{settledness(event.truth_state)}
    When it happened: #{stamp(event.occurred_at || event.observed_at)}
    Affects: #{Enum.join(Event.affected_refs(event), ", ")}
    #{related_block(related)}
    Explanation:\
    """
  end

  # Other events touching the same entities — the context that makes an
  # explanation more than a paraphrase.
  defp related_events(%Event{} = event, events) do
    refs = MapSet.new(Event.affected_refs(event))

    events
    |> Enum.reject(&(&1.event_id == event.event_id))
    |> Enum.filter(fn other ->
      other |> Event.affected_refs() |> Enum.any?(&MapSet.member?(refs, &1))
    end)
    |> Enum.take(5)
  end

  # The publisher's own title, not its internal id.
  defp source_label(sources, source_id) do
    case Map.get(sources || %{}, source_id) do
      %{title: title} when is_binary(title) -> title
      _ -> source_id
    end
  end

  defp related_block([]), do: ""

  defp related_block(events) do
    lines = Enum.map_join(events, "\n", fn e -> "- #{Event.title(e)} (#{e.event_type})" end)
    "\nOther records touching the same things:\n#{lines}\n"
  end

  defp summary_line(%Event{payload: %{"summary" => s}}) when is_binary(s) and s != "",
    do: "What it says: #{s}\n"

  defp summary_line(%Event{payload: %{"body" => b}}) when is_binary(b) and b != "",
    do: "What it says: #{b}\n"

  defp summary_line(_), do: ""

  # Spelled out, so the model describes the meaning rather than echoing a term
  # the reader already does not understand.
  defp settledness("observed"), do: "seen directly in a primary record"
  defp settledness("reported"), do: "asserted by a source, not independently confirmed"
  defp settledness("proposed"), do: "put forward, not yet approved"
  defp settledness("adopted"), do: "formally approved"
  defp settledness("delivered"), do: "carried out"
  defp settledness("superseded"), do: "replaced by a later record"
  defp settledness(other), do: other

  defp stamp(nil), do: "unknown"
  defp stamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %-d, %Y")

  defp config, do: Application.get_env(:indivisual, __MODULE__, [])
end
