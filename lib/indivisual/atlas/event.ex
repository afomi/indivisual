defmodule Indivisual.Atlas.Event do
  @moduledoc """
  Canonical Atlas event envelope.

  An Atlas event is one immutable fact from an append-only source stream, normalized
  into a common shape while preserving provenance. Source events, civic records,
  public-blockchain transactions, and user annotations all arrive through this envelope.

  Fields:

    * `event_id`     — stable, globally unique
    * `source_id`    — source system / publisher / chain identifier
    * `stream_id`    — source stream, account, topic, block, or collection
    * `sequence`     — source ordering key as a list of integers (e.g. `[block_height, tx_index]`)
    * `event_type`   — namespaced verb, e.g. `civic.plan.adopted` or `chain.tx.confirmed`
    * `occurred_at`  — source-asserted event time when available
    * `observed_at`  — when Indivisual retrieved or accepted the event
    * `actor_ref`    — optional public actor identifier
    * `subject_refs` — one or more affected entity identifiers
    * `payload`      — normalized attributes
    * `provenance`   — canonical URI, transaction id, document reference, hash, signature, etc.
    * `truth_state`  — one of #{inspect(~w(observed reported proposed adopted delivered superseded))}
    * `raw`          — the original source payload, kept verbatim

  Ordering is deterministic: `sort_key/1` orders by effective time (occurred_at, falling
  back to observed_at), then `sequence`, then `source_id`, `stream_id`, and `event_id`,
  so events with identical timestamps still sort the same way every time.
  """

  @truth_states ~w(observed reported proposed adopted delivered superseded)
  @annotation_prefix "atlas.annotation."

  @type t :: %__MODULE__{
          event_id: String.t(),
          source_id: String.t(),
          stream_id: String.t(),
          sequence: [integer()],
          event_type: String.t(),
          occurred_at: DateTime.t() | nil,
          observed_at: DateTime.t(),
          actor_ref: String.t() | nil,
          subject_refs: [String.t()],
          payload: map(),
          provenance: map(),
          truth_state: String.t(),
          raw: map() | nil
        }

  defstruct event_id: nil,
            source_id: nil,
            stream_id: nil,
            sequence: [],
            event_type: nil,
            occurred_at: nil,
            observed_at: nil,
            actor_ref: nil,
            subject_refs: [],
            payload: %{},
            provenance: %{},
            truth_state: "observed",
            raw: nil

  @doc "The allowed truth states, from least to most settled."
  def truth_states, do: @truth_states

  @doc """
  Builds and validates an event from a string- or atom-keyed map.

  Returns `{:ok, event}` or `{:error, [{field, message}]}`.
  """
  def new(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    event = %__MODULE__{
      event_id: attrs["event_id"],
      source_id: attrs["source_id"],
      stream_id: attrs["stream_id"],
      sequence: normalize_sequence(attrs["sequence"]),
      event_type: attrs["event_type"],
      occurred_at: parse_time(attrs["occurred_at"]),
      observed_at: parse_time(attrs["observed_at"]),
      actor_ref: attrs["actor_ref"],
      subject_refs: List.wrap(attrs["subject_refs"]),
      payload: attrs["payload"] || %{},
      provenance: normalize_provenance(attrs["provenance"]),
      truth_state: attrs["truth_state"] || "observed",
      raw: attrs["raw"]
    }

    case validate(event) do
      [] -> {:ok, event}
      errors -> {:error, errors}
    end
  end

  @doc "Like `new/1` but raises on invalid input."
  def new!(attrs) do
    case new(attrs) do
      {:ok, event} -> event
      {:error, errors} -> raise ArgumentError, "invalid Atlas event: #{inspect(errors)}"
    end
  end

  @doc """
  Deterministic ordering key. Effective time first (occurred_at, else observed_at),
  then source sequence, then source/stream/event identifiers.
  """
  def sort_key(%__MODULE__{} = event) do
    {DateTime.to_unix(effective_time(event), :microsecond), event.sequence, event.source_id,
     event.stream_id, event.event_id}
  end

  @doc "Compares two events for sorting. Returns `:lt`, `:eq`, or `:gt`."
  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    ka = sort_key(a)
    kb = sort_key(b)

    cond do
      ka < kb -> :lt
      ka > kb -> :gt
      true -> :eq
    end
  end

  @doc "The time used for ordering: `occurred_at` when the source asserts one, else `observed_at`."
  def effective_time(%__MODULE__{occurred_at: nil, observed_at: observed}), do: observed
  def effective_time(%__MODULE__{occurred_at: occurred}), do: occurred

  @doc "Every entity reference this event touches: subjects plus the actor, deduplicated in order."
  def affected_refs(%__MODULE__{subject_refs: subjects, actor_ref: actor}) do
    (subjects ++ List.wrap(actor)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  @doc "True when the event is a user annotation rather than a source fact."
  def annotation?(%__MODULE__{event_type: type}) when is_binary(type),
    do: String.starts_with?(type, @annotation_prefix)

  def annotation?(_), do: false

  @doc "Prefix shared by all annotation event types."
  def annotation_prefix, do: @annotation_prefix

  @doc "The relationship asserted by this event, if any, as `%{from, verb, to}`."
  def relationship(%__MODULE__{
        payload: %{"relationship" => %{"from" => from, "verb" => verb, "to" => to}}
      })
      when is_binary(from) and is_binary(verb) and is_binary(to),
      do: %{from: from, verb: verb, to: to}

  def relationship(_), do: nil

  @doc "Human title for the event: payload title, else a registered entity's label, else the event type."
  def title(%__MODULE__{payload: %{"title" => title}}) when is_binary(title), do: title

  def title(%__MODULE__{payload: %{"entity" => %{"label" => label}}}) when is_binary(label),
    do: "Registered: #{label}"

  def title(%__MODULE__{event_type: type}), do: type

  @doc """
  Content-addressed hash of a map, with keys sorted recursively so the same content
  always hashes the same regardless of map ordering.
  """
  def content_hash(term) do
    :crypto.hash(:sha256, canonical_json(term)) |> Base.encode16(case: :lower)
  end

  defp canonical_json(term), do: term |> canonicalize() |> Jason.encode!()

  defp canonicalize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp canonicalize(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
  defp canonicalize(other), do: other

  # --- validation ---

  defp validate(event) do
    []
    |> require_string(event, :event_id)
    |> require_string(event, :source_id)
    |> require_string(event, :stream_id)
    |> require_string(event, :event_type)
    |> require_sequence(event)
    |> require_observed_at(event)
    |> require_provenance(event)
    |> require_truth_state(event)
    |> require_subject_refs(event)
    |> Enum.reverse()
  end

  defp require_string(errors, event, field) do
    case Map.fetch!(event, field) do
      value when is_binary(value) and value != "" -> errors
      _ -> [{field, "is required"} | errors]
    end
  end

  defp require_sequence(errors, %{sequence: []}),
    do: [{:sequence, "is required for ordering"} | errors]

  defp require_sequence(errors, %{sequence: :invalid}),
    do: [{:sequence, "must be an integer or list of integers"} | errors]

  defp require_sequence(errors, _), do: errors

  defp require_observed_at(errors, %{observed_at: %DateTime{}}), do: errors

  defp require_observed_at(errors, _),
    do: [{:observed_at, "is required (when Indivisual accepted the event)"} | errors]

  defp require_provenance(errors, %{provenance: map}) when is_map(map) and map_size(map) > 0,
    do: errors

  defp require_provenance(errors, _), do: [{:provenance, "is required"} | errors]

  defp require_truth_state(errors, %{truth_state: state}) when state in @truth_states, do: errors

  defp require_truth_state(errors, _),
    do: [{:truth_state, "must be one of #{Enum.join(@truth_states, ", ")}"} | errors]

  defp require_subject_refs(errors, %{subject_refs: [_ | _] = refs}) do
    if Enum.all?(refs, &is_binary/1),
      do: errors,
      else: [{:subject_refs, "must be strings"} | errors]
  end

  defp require_subject_refs(errors, _),
    do: [{:subject_refs, "must name at least one affected entity"} | errors]

  # --- normalization helpers ---

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp normalize_sequence(nil), do: []
  defp normalize_sequence(int) when is_integer(int), do: [int]

  defp normalize_sequence(list) when is_list(list) do
    if Enum.all?(list, &is_integer/1), do: list, else: :invalid
  end

  defp normalize_sequence(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> [int]
      _ -> :invalid
    end
  end

  defp normalize_sequence(_), do: :invalid

  defp normalize_provenance(nil), do: %{}
  defp normalize_provenance(uri) when is_binary(uri) and uri != "", do: %{"uri" => uri}
  defp normalize_provenance(map) when is_map(map), do: stringify_keys(map)
  defp normalize_provenance(_), do: %{}

  defp parse_time(nil), do: nil
  defp parse_time(%DateTime{} = dt), do: dt

  defp parse_time(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp parse_time(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        case Date.from_iso8601(bin) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_time(_), do: nil
end
