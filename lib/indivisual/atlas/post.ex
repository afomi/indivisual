defmodule Indivisual.Atlas.Post do
  @moduledoc """
  Something a person writes into the record. One object, two subclasses:

    * a **note** — a plain post, about nothing in particular (or about the
      entities it mentions). The basic social-media post.
    * an **annotation** — a note written ABOUT another event. Everything a note
      has, plus what it answers and a kind (observation, question, correction,
      source) that says what sort of claim it is.

  In ActivityStreams terms both are a `Note`; an annotation is a `Note` with
  `inReplyTo` (`STANDARDS.md`). They share an author, a body, a source, and the
  rule that matters: **writing one appends an event and changes nothing else.**
  So they share a form, a sequence counter and this module, and differ only in
  what `build/3` is handed.

  Truth state follows `EVENT_UI.md`: a person's post is a claim by a person, so
  it is `reported` — never `observed` by default. Only an annotation of kind
  `observation` says "I saw this", and that stays the annotation's business.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Extract
  alias Indivisual.Atlas.Sources.Annotations

  @note_type "atlas.post.added"

  @doc "The subclasses, as the composer offers them."
  def types, do: ~w(note annotation)

  @doc "Event type of a plain note."
  def note_type, do: @note_type

  @doc "True for anything a person wrote into the record: a note or an annotation."
  def post?(%Event{event_type: @note_type}), do: true
  def post?(%Event{} = event), do: Event.annotation?(event)
  def post?(_), do: false

  @doc """
  Builds a post event.

  `attrs` needs `"body"` and `"author"`. Options:

    * `:about` — an `Event`. Present: the post is an **annotation** of it and
      `attrs["kind"]` applies (see `Annotations.build/4`). Absent: a **note**.
    * `:mentions` — entity refs a note is about, e.g. the entity in focus when
      it was written. A note that mentions nothing is about itself (`note:N`),
      which is what an ActivityStreams `Create` of a `Note` says too.

  `sequence` is the feed's shared post counter, so posts of both kinds order
  deterministically even when written in the same instant.
  """
  def build(attrs, sequence, opts \\ []) do
    case Keyword.get(opts, :about) do
      %Event{} = about -> Annotations.build(about, attrs, sequence, now(opts))
      nil -> note(attrs, sequence, Keyword.get(opts, :mentions, []), now(opts))
    end
  end

  defp now(opts), do: Keyword.get(opts, :now, DateTime.utc_now())

  @doc false
  def mentions_payload([]), do: %{}
  def mentions_payload(list), do: %{"mentions" => list, "mentions_rule" => Extract.rule()}

  defp note(attrs, sequence, mentions, now) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    author = attrs["author"] |> to_string() |> String.trim()
    body = attrs["body"] |> to_string() |> String.trim()
    mentions = mentions |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.uniq()

    cond do
      body == "" ->
        {:error, [{:body, "can't be blank"}]}

      author == "" ->
        {:error, [{:author, "can't be blank"}]}

      true ->
        id = note_id(author, body, now)

        Event.new(%{
          "event_id" => id,
          "source_id" => Annotations.source_id(),
          "stream_id" => "posts:#{author}",
          "sequence" => [sequence],
          "event_type" => @note_type,
          "occurred_at" => now,
          "observed_at" => now,
          "actor" => "person:#{author}",
          "object" => if(mentions == [], do: [id], else: mentions),
          "payload" =>
            Map.merge(
              %{"title" => title(body), "body" => body, "kind" => "note"},
              # What the note was read as, with the rule that read it — shown to
              # the writer before they published (`Indivisual.Atlas.Extract`).
              attrs["mentions"] |> Extract.sanitize() |> mentions_payload()
            ),
          "provenance" => %{"author" => author, "recorded_by" => "indivisual"},
          "truth_state" => "reported"
        })
    end
  end

  # The id names the THING, and a thing is a noun: a note, by someone, on a day.
  # "Posting" is the verb, and the verb is the event type (`atlas.post.added`).
  # It used to be `post:<n>`, where n was the Feed's running counter — a verb for
  # a prefix, and a number that said where the note fell in one process's memory
  # rather than what it was. The last segment is a fingerprint of the content, so
  # the id is the same wherever the note is rebuilt and never collides with
  # another. Order within the author's feed is `sequence`'s job, not the id's.
  defp note_id(author, body, %DateTime{} = now) do
    fingerprint =
      %{"author" => author, "body" => body, "at" => now}
      |> Event.content_hash()
      |> binary_part(0, 8)

    "note:#{author}:#{Date.to_iso8601(DateTime.to_date(now))}:#{fingerprint}"
  end

  # A note has no title of its own; its first line stands in for one.
  defp title(body) do
    line = body |> String.split("\n", parts: 2) |> hd() |> String.trim()
    if String.length(line) > 72, do: String.slice(line, 0, 71) <> "…", else: line
  end
end
