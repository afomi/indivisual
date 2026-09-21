defmodule Indivisual.Atlas.Glossary do
  @moduledoc """
  Plain-language definitions for the vocabulary Atlas puts on screen.

  An event card shows `civic.entity.registered`, `seq 0.5`, a 64-character
  content hash and a truth state. Every one of those is precise and opaque to
  someone reading it for the first time, and the friction that causes is
  vocabulary, not volume.

  These definitions are **static on purpose**. A field label like `content_hash`
  means exactly one thing every time, so a written definition is faster, cheaper
  and more accurate than asking a model to reconstruct it. Explanation that is
  genuinely contextual — what does *this* event mean, here — is a separate
  problem and does not belong in a lookup table.

  Each term carries a one-line `summary` (what it is) and a `why` (why it is on
  the screen at all), because knowing that `observed_at` is "when Indivisual
  accepted the event" only helps once you know it is there to separate when
  something happened from when we heard about it.
  """

  @terms %{
    "truth_state" => %{
      label: "Truth state",
      summary: "How settled this claim is — from directly observed to superseded.",
      why: "It tells you how much weight to put on the event without having to chase the source."
    },
    "occurred" => %{
      label: "Occurred",
      summary: "When the event actually happened, as asserted by the source.",
      why:
        "Separate from when we heard about it, so a late-published record still sorts by its real date."
    },
    "observed" => %{
      label: "Observed",
      summary: "When Indivisual retrieved or accepted this event.",
      why:
        "A record published months after the fact is common; keeping both dates makes that visible instead of hiding it."
    },
    "source" => %{
      label: "Source",
      summary: "The publisher this event was read from.",
      why: "Every event is traceable to who asserted it — nothing here is anonymous."
    },
    "stream" => %{
      label: "Feed",
      summary:
        "The series the source published this record in — an account's posts, an RSS feed's items, a chain's transactions — and this record's place in it.",
      why:
        "A feed keeps the publisher's own order, so records stay in the sequence the source put them in even when timestamps tie, and you can walk a feed from one record to the next."
    },
    "affects" => %{
      label: "Affects",
      summary: "The entities this event is about.",
      why:
        "Following these is how you move from one event to everything else touching the same thing."
    },
    "provenance" => %{
      label: "Provenance",
      summary: "Where this came from: a document reference, a URL, and a hash of the original.",
      why: "It is what makes a claim checkable by someone who does not trust us."
    },
    "content_hash" => %{
      label: "Content hash",
      summary: "A fingerprint of the original record.",
      why:
        "If the source content ever changes, the hash changes — so silent edits cannot pass unnoticed."
    },
    "event_id" => %{
      label: "Event id",
      summary: "A stable, globally unique name for this event.",
      why: "It never changes, so a link to an event keeps working."
    },
    "event_type" => %{
      label: "Event type",
      summary: "What kind of thing happened, as a namespaced verb like civic.plan.adopted.",
      why: "The namespace says which domain it came from; the verb says what it did."
    },
    "projection" => %{
      label: "Projection",
      summary:
        "A way of reading the same events — activity, entity context, topology, or provenance.",
      why:
        "A projection changes the read model, never the source events. Switching views cannot alter the record."
    },
    "annotation" => %{
      label: "Annotation",
      summary: "A note a person added, recorded as its own event.",
      why:
        "Annotations never overwrite a source event. Yours is a separate claim with your name on it."
    }
  }

  # kind -> schema.org type. The entity kinds in use map almost one-to-one
  # onto schema.org, so a consumer that speaks that vocabulary can read these
  # records without a mapping document of ours. `goal` has no clean analogue
  # and stays unmapped rather than being forced into a near-miss.
  @schema_types %{
    "body" => "GovernmentOrganization",
    "person" => "Person",
    "place" => "Place",
    "document" => "CreativeWork",
    "policy" => "Legislation",
    "plan" => "Project",
    "money" => "MonetaryGrant"
  }

  @doc "schema.org type for an entity kind, or nil when none fits."
  def schema_type(kind), do: Map.get(@schema_types, kind)

  @doc "All terms, keyed by slug."
  def all, do: @terms

  @doc "One term, or nil when it is not defined."
  def get(slug), do: Map.get(@terms, slug)

  @doc "Whether a slug has a definition."
  def defined?(slug), do: Map.has_key?(@terms, slug)

  @doc "Slugs, sorted by their display label."
  def slugs, do: @terms |> Enum.sort_by(fn {_, t} -> t.label end) |> Enum.map(&elem(&1, 0))
end
