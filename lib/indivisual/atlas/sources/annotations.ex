defmodule Indivisual.Atlas.Sources.Annotations do
  @moduledoc """
  The source adapter for what people write into the record: notes and
  annotations, the two subclasses of `Indivisual.Atlas.Post`. One source for
  both — they have the same authors and the same standing — under the id the
  first annotations were stored with.

  Annotations are separate events with their own authorship and provenance. They never
  overwrite source events. This adapter registers the annotation source so annotation
  events can be filtered, labeled, and traced like any other source; it contributes no
  seed events of its own. `build/2` constructs an annotation event about another event.
  """

  @behaviour Indivisual.Atlas.Source

  alias Indivisual.Atlas.Event

  @source_id "indivisual-annotations"
  @kinds ~w(observation question correction source)

  @impl true
  def info do
    %{id: "annotations", label: "Session annotations", status: "in-memory"}
  end

  @impl true
  def sources do
    [
      %{
        id: @source_id,
        title: "Posts and annotations",
        publisher: "Indivisual users (this session)",
        kind: "Post",
        status: "in-memory"
      }
    ]
  end

  @impl true
  def events, do: []

  @doc "The source id annotation events carry."
  def source_id, do: @source_id

  @doc "Allowed annotation kinds."
  def kinds, do: @kinds

  @doc """
  Builds an annotation event about `about` (an `Indivisual.Atlas.Event`).

  `attrs` needs `"body"` and `"author"`; `"kind"` defaults to `"question"`.
  `sequence` is the feed's monotonic annotation counter, so annotations order
  deterministically even when written in the same instant.

  Truth state: an observation is `observed`; every other kind is `reported`, because
  an annotation is a claim by a person, not a source fact.
  """
  def build(%Event{} = about, attrs, sequence, now \\ DateTime.utc_now()) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    kind = if attrs["kind"] in @kinds, do: attrs["kind"], else: "question"
    author = attrs["author"] |> to_string() |> String.trim()
    body = attrs["body"] |> to_string() |> String.trim()

    Event.new(%{
      "event_id" => "annotation:#{about.event_id}:#{sequence}",
      "source_id" => @source_id,
      "stream_id" => "annotations:#{about.event_id}",
      "sequence" => [sequence],
      "event_type" => Event.annotation_prefix() <> "added",
      "occurred_at" => now,
      "observed_at" => now,
      "actor" => "person:#{author}",
      "object" => Event.affected_refs(about),
      "payload" =>
        Map.merge(
          %{
            "title" => "#{String.capitalize(kind)} on: #{Event.title(about)}",
            "body" => body,
            "kind" => kind,
            "about_event_id" => about.event_id
          },
          attrs["mentions"]
          |> Indivisual.Atlas.Extract.sanitize()
          |> Indivisual.Atlas.Post.mentions_payload()
        ),
      "provenance" => %{
        "author" => author,
        "about_event_id" => about.event_id,
        "about_content_hash" => about.provenance["content_hash"],
        "recorded_by" => "indivisual"
      },
      "truth_state" => if(kind == "observation", do: "observed", else: "reported")
    })
    |> validate_body(body, author)
  end

  defp validate_body({:ok, event}, body, author) do
    cond do
      body == "" -> {:error, [{:body, "can't be blank"}]}
      author == "" -> {:error, [{:author, "can't be blank"}]}
      true -> {:ok, event}
    end
  end

  defp validate_body(error, _, _), do: error
end
