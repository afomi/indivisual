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
    * `actor`        — optional ref of the public actor who did it
    * `object`       — one or more refs of the entities it affects
    * `payload`      — normalized attributes
    * `provenance`   — canonical URI, transaction id, document reference, hash, signature, etc.
    * `truth_state`  — one of #{inspect(~w(observed reported proposed adopted delivered superseded))}
    * `raw`          — the original source payload, kept verbatim

  ## Standards alignment

  Where ActivityStreams 2.0 has an exact word, the field uses it, so an event reads
  as an AS2 Activity without a mapping layer: `actor` and `object` are the AS2
  properties of the same name, and a payload relationship is an AS2 `Relationship`
  (`subject`, `relationship`, `object`). `object` is multi-valued, as AS2 allows; Atlas
  does not yet split `target` or `location` out of it, so every affected ref rides there.

  The remaining fields are the event-sourcing envelope, which AS2 has no vocabulary
  for, and keep their own names. `STANDARDS.md` holds the full table.

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
          actor: String.t() | nil,
          object: [String.t()],
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
            actor: nil,
            object: [],
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
      actor: attrs["actor"],
      object: List.wrap(attrs["object"]),
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

  @doc "Every entity reference this event touches: objects plus the actor, deduplicated in order."
  def affected_refs(%__MODULE__{object: objects, actor: actor}) do
    (objects ++ List.wrap(actor)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  @doc """
  Whether an event reads as a **noun** or a **verb**.

  A noun event says that something EXISTS: it registers an entity (a plan, a
  park, a commission) and carries `payload["entity"]`. A verb event says that
  something HAPPENED — to a thing, or between things: a plan was adopted, a
  payment made, a relationship asserted, a question asked. The stream holds
  both, and they are different kinds of reading: nouns are the cast, verbs are
  the plot.

  This is a fact about the event's shape (does it carry the `thing` facet —
  `docs/VIEWS.md`), not a judgement, so it is derived and never stored.
  """
  def part_of_speech(%__MODULE__{payload: %{"entity" => %{"ref" => ref}}}) when is_binary(ref),
    do: "noun"

  def part_of_speech(%__MODULE__{}), do: "verb"

  @doc "The parts of speech, in the order a filter lists them."
  def parts_of_speech, do: ~w(verb noun)

  @doc "True when the event is a user annotation rather than a source fact."
  def annotation?(%__MODULE__{event_type: type}) when is_binary(type),
    do: String.starts_with?(type, @annotation_prefix)

  def annotation?(_), do: false

  @doc "Prefix shared by all annotation event types."
  def annotation_prefix, do: @annotation_prefix

  @doc """
  The relationship asserted by this event, if any, as `%{subject, relationship, object}` —
  the shape of an ActivityStreams `Relationship`: `subject` `relationship` `object`.
  """
  def relationship(%__MODULE__{
        payload: %{
          "relationship" => %{
            "subject" => subject,
            "relationship" => relationship,
            "object" => object
          }
        }
      })
      when is_binary(subject) and is_binary(relationship) and is_binary(object),
      do: %{subject: subject, relationship: relationship, object: object}

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
    |> require_object(event)
    |> require_relationship_shape(event)
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

  # The store keeps `sequence` as 32-bit integers. An envelope it cannot hold is
  # invalid HERE, with a message, rather than at the database with an exception.
  defp require_sequence(errors, %{sequence: sequence}) when is_list(sequence) do
    if Enum.all?(sequence, &(&1 in -2_147_483_648..2_147_483_647)),
      do: errors,
      else: [{:sequence, "each part must fit a 32-bit integer"} | errors]
  end

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

  defp require_object(errors, %{object: [_ | _] = refs}) do
    if Enum.all?(refs, &is_binary/1),
      do: errors,
      else: [{:object, "must be strings"} | errors]
  end

  defp require_object(errors, _),
    do: [{:object, "must name at least one affected entity"} | errors]

  # A payload that says "relationship" but is not shaped like one would otherwise
  # be read as asserting nothing, and the link would vanish without a trace.
  defp require_relationship_shape(errors, %{payload: %{"relationship" => _}} = event) do
    if relationship(event),
      do: errors,
      else: [{:payload, "relationship must name a subject, relationship, and object"} | errors]
  end

  defp require_relationship_shape(errors, _), do: errors

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
