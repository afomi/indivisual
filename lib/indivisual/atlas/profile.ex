defmodule Indivisual.Atlas.Profile do
  @moduledoc """
  View model for a **person** entity's card.

  Every field but the name is optional, because most people in the record were
  never registered: `person:afomi` exists only because someone of that name wrote
  an annotation. So the profile is built from two places, and says which:

    * what the record **shows them doing** — events they authored, events that
      mention them, when they were first and last seen. Always available.
    * what a registration **says about them** — schema.org `Person` properties
      (`jobTitle`, `affiliation`, `description`, `url`, `image`, `sameAs`), read
      from the entity's `attrs`. Present only if someone registered them.

  Nothing is invented to fill a gap. No image means initials, not a stock
  avatar; an unregistered person is labelled as known only from what they wrote.

  Links and images are kept only when they are `http(s)` URLs: these values come
  from event payloads, and a `javascript:` URL in an `href` is not a display bug.
  """

  alias Indivisual.Atlas.Event

  @type t :: %{
          ref: String.t(),
          name: String.t(),
          initials: String.t(),
          registered?: boolean(),
          job_title: String.t() | nil,
          affiliation: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          image: String.t() | nil,
          same_as: [String.t()],
          authored: non_neg_integer(),
          mentioned: non_neg_integer(),
          wrote: [{String.t(), pos_integer()}],
          first_seen: DateTime.t() | nil,
          last_seen: DateTime.t() | nil
        }

  @doc "Whether an entity gets the person card."
  def person?(%{kind: "person"}), do: true
  def person?(_), do: false

  @doc """
  Builds the profile of `entity` from the `events` that touch it.

  `events` is whatever the caller's lens admits, so the counts describe the
  current view — the same rule as every other number on the page.
  """
  def person(%{ref: ref} = entity, events) do
    attrs = Map.get(entity, :attrs, %{})
    {authored, mentioned} = Enum.split_with(events, &(&1.actor == ref))
    times = events |> Enum.map(&Event.effective_time/1) |> Enum.sort(DateTime)

    %{
      ref: ref,
      name: entity.label,
      initials: initials(entity.label),
      registered?: Map.get(entity, :registered, false),
      job_title: text(attrs["jobTitle"]),
      affiliation: text(attrs["affiliation"]),
      description: text(attrs["description"]),
      url: web_url(attrs["url"]),
      image: web_url(attrs["image"]),
      same_as: attrs["sameAs"] |> List.wrap() |> Enum.map(&web_url/1) |> Enum.reject(&is_nil/1),
      authored: length(authored),
      mentioned: length(mentioned),
      wrote: wrote(authored),
      first_seen: List.first(times),
      last_seen: List.last(times)
    }
  end

  @doc "Up to two initials, from the first and last words of a name."
  def initials(name) when is_binary(name) do
    case String.split(name, ~r/\s+/, trim: true) do
      [] ->
        "?"

      [one] ->
        one |> String.first() |> String.upcase()

      words ->
        [List.first(words), List.last(words)] |> Enum.map_join(&String.first/1) |> String.upcase()
    end
  end

  def initials(_), do: "?"

  # What kinds of thing they wrote, most frequent first: annotation kinds when
  # there is one, else the last segment of the event type.
  defp wrote(authored) do
    authored
    |> Enum.frequencies_by(fn event ->
      event.payload["kind"] || event.event_type |> String.split(".") |> List.last()
    end)
    |> Enum.sort_by(fn {kind, n} -> {-n, kind} end)
  end

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(_), do: nil

  defp web_url(value) when is_binary(value) do
    case URI.parse(String.trim(value)) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        String.trim(value)

      _ ->
        nil
    end
  end

  defp web_url(_), do: nil
end
