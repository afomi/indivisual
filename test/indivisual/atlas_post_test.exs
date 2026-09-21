defmodule Indivisual.Atlas.PostTest do
  @moduledoc """
  A post is one object with two subclasses — a note, and an annotation (a note
  about another event). These pin what they share and the one thing that tells
  them apart, so a composer can treat them as the same kind of thing.
  """
  use Indivisual.DataCase, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Post
  alias Indivisual.Atlas.Sources.Annotations

  @attrs %{"author" => "ryan", "body" => "The trail reopened this morning.\nSaw it myself."}

  defp about, do: Feed |> Feed.events([]) |> List.first()

  describe "a note" do
    test "is its own event, by a person, from the people's source" do
      now = ~U[2026-09-20 12:00:00Z]
      assert {:ok, %Event{} = event} = Post.build(@attrs, 7, now: now)

      # Named as a thing — a note, by whom, on what day, with a fingerprint of
      # its content — not as "post" + the Feed's counter. The verb is the type.
      assert event.event_id =~ ~r/\Anote:ryan:2026-09-20:[0-9a-f]{8}\z/
      assert {:ok, %Event{event_id: same}} = Post.build(@attrs, 99, now: now)
      assert same == event.event_id, "the id is the content's, not the counter's"
      assert event.sequence == [7], "order in the feed is the sequence's job"
      assert event.event_type == Post.note_type()
      assert event.source_id == Annotations.source_id()
      assert event.actor == "person:ryan"
      assert event.payload["body"] =~ "Saw it myself."
      assert event.provenance["author"] == "ryan"
    end

    test "its first line stands in for a title" do
      {:ok, event} = Post.build(@attrs, 1)
      assert Event.title(event) == "The trail reopened this morning."

      {:ok, long} = Post.build(%{@attrs | "body" => String.duplicate("word ", 40)}, 2)
      assert String.length(Event.title(long)) <= 72
      assert String.ends_with?(Event.title(long), "…")
    end

    test "is a claim by a person: reported, never observed by default" do
      {:ok, event} = Post.build(@attrs, 1)
      assert event.truth_state == "reported"
    end

    test "is about what it mentions; mentioning nothing, it is about itself" do
      {:ok, alone} = Post.build(@attrs, 3)
      assert alone.object == [alone.event_id]

      {:ok, mentioning} = Post.build(@attrs, 4, mentions: ["plan:eltsp", "plan:eltsp"])
      assert mentioning.object == ["plan:eltsp"]
    end

    test "needs a body and an author" do
      assert {:error, [{:body, _}]} = Post.build(%{@attrs | "body" => "  "}, 1)
      assert {:error, [{:author, _}]} = Post.build(%{@attrs | "author" => ""}, 1)
    end
  end

  describe "an annotation" do
    test "is a note with something it answers" do
      about = about()
      {:ok, event} = Post.build(Map.put(@attrs, "kind", "question"), 5, about: about)

      assert Event.annotation?(event)
      assert event.payload["about_event_id"] == about.event_id
      assert event.source_id == Annotations.source_id()
      assert event.actor == "person:ryan"
      # It is about whatever the event it answers is about.
      assert event.object == Event.affected_refs(about)
    end

    test "is exactly what the annotations adapter builds" do
      about = about()
      now = ~U[2026-09-20 12:00:00Z]
      attrs = Map.put(@attrs, "kind", "correction")

      assert Post.build(attrs, 5, about: about, now: now) ==
               Annotations.build(about, attrs, 5, now)
    end
  end

  describe "what they share" do
    test "both are posts; a source event is not" do
      {:ok, note} = Post.build(@attrs, 1)
      {:ok, annotation} = Post.build(@attrs, 2, about: about())

      assert Post.post?(note)
      assert Post.post?(annotation)
      refute Post.post?(about())

      # Only one of them answers something.
      refute Event.annotation?(note)
    end

    test "one counter orders them, whichever kind they are" do
      {:ok, a} = Post.build(@attrs, 1)
      {:ok, b} = Post.build(@attrs, 2, about: about())

      assert a.sequence == [1] and b.sequence == [2]
    end
  end
end
