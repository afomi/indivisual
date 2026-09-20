defmodule Indivisual.Atlas.Coherence do
  @moduledoc """
  Reads a set of relationships as a chain: does the record hold together?

  A chain like `strategy → policy → place → money` is an **opinion about how
  civic process ought to work** — a strategy should be backed by a policy,
  realized in a place, funded by money. That opinion is what makes an absence
  meaningful: a strategy with no funding link is not a rendering problem, it is
  a finding.

  Nothing here asserts anything new. Every link is an existing relationship
  from the event stream; this only names the KIND of link each one is and says
  which expected links are missing. That is why a chain is a view preference
  rather than a source of events: change the chain and the record does not
  change, only the question asked of it.

  ## Status: computed, not mounted

  This module works and is tested; it is deliberately NOT wired into `/atlas`.
  A chain is one person's model of how a process ought to hold together, so it
  belongs to that person rather than to the shared scene — managed in their own
  context and optionally overlaid on Atlas, not installed in it. The two chains
  below are seeds for that, not the app's opinion imposed on every reader.

  When it returns, the open question is where chains live: encoded in the URL
  (shareable, no storage, fits how the rest of this view already works), or a
  user-scoped table with `user_id IS NULL` meaning "shipped with the app", the
  way `USER_SCOPING.md` proposes for spaces.

  ## Three reasons a chain fails to close

  An unsatisfied step is only useful if you can tell which kind of absence it
  is, and `diagnose/2` separates them:

    * `:unlinked` — both kinds are present, nothing connects them. The only
      case that is evidence about the SUBJECT.
    * `:vocabulary` — the record does not use these kinds at all. Evidence
      about the LENS: the chain was written for a different corpus.
    * `:absent` — one side present, one missing. Partly coverage, partly
      vocabulary.

  Conflating them turns a modelling mistake into a false finding, which is the
  failure mode that would make the whole feature untrustworthy.
  """

  alias Indivisual.Atlas.Topology

  @chains [
    %{
      id: "civic",
      label: "Strategy → policy → place → money",
      note:
        "Explicit, source-backed relationships — not inferred narrative. Select one to inspect its context.",
      steps: [
        %{from: "goal", to: "place", label: "strategy → outcome"},
        %{from: "policy", to: "plan", label: "policy → place"},
        %{from: "place", to: "plan", label: "plan → standard"},
        %{from: "money", to: "plan", label: "money → project"},
        %{from: "place", to: "place", label: "place → delivery"}
      ]
    },
    %{
      id: "authority",
      label: "Who decided, and on what",
      note: "Which bodies acted, and what they acted on.",
      steps: [
        %{from: "body", to: "plan", label: "body → plan"},
        %{from: "body", to: "place", label: "body → place"},
        %{from: "document", to: "plan", label: "evidence → plan"}
      ]
    }
  ]

  @doc "Available chains."
  def chains, do: @chains

  @doc "One chain by id, or the default."
  def get(id) do
    Enum.find(@chains, fn c -> c.id == id end) || default()
  end

  @doc "The chain shown when none is chosen."
  def default, do: hd(@chains)

  @doc "The default chain's id."
  def default_id, do: default().id

  @doc """
  Materializes a chain against the events.

  Returns `%{chain:, links:, gaps:, present:, expected:}` where each link
  carries its step label, the relationship, and both entities. `gaps` are steps
  the record does not satisfy — the part worth reading.
  """
  def materialize(chain_id, events) do
    chain = get(chain_id)
    entities = Topology.entities(events)
    relationships = Topology.relationships(events)

    resolved =
      Enum.map(chain.steps, fn step ->
        match =
          Enum.find(relationships, fn rel ->
            kind_of(entities, rel.from) == step.from and kind_of(entities, rel.to) == step.to
          end)

        %{
          step: step,
          label: step.label,
          relationship: match,
          from: match && Map.get(entities, match.from),
          to: match && Map.get(entities, match.to)
        }
      end)

    {links, gaps} = Enum.split_with(resolved, &(&1.relationship != nil))

    diagnosed =
      Enum.map(gaps, fn %{step: step} ->
        reason = diagnose(step, entities)
        %{step: step, reason: reason, explanation: explain_gap(reason, step)}
      end)

    %{
      chain: chain,
      links: links,
      gaps: diagnosed,
      # Kinds the chain names that this record never uses: a mismatch between
      # the lens and the corpus, not a finding about the subject.
      unknown_kinds: vocabulary_gap(chain, entities),
      present: length(links),
      expected: length(chain.steps)
    }
  end

  defp kind_of(entities, ref) do
    case Map.get(entities, ref) do
      %{kind: kind} -> kind
      _ -> nil
    end
  end

  # --- diagnosing a gap ---

  @doc """
  Classifies why a step is unsatisfied. An absence is only useful if you can
  tell WHICH absence it is:

    * `:vocabulary` — the record has no entity of that kind at all. The chain
      is speaking a different language than the source, so this says nothing
      about the world.
    * `:unlinked` — both kinds are present, but nothing asserts a relationship
      between them. This is a claim about the record: the pieces exist and the
      connection is not made.
    * `:absent` — one side exists and the other does not. Partially a
      vocabulary problem, partially a coverage one.

  Only `:unlinked` is evidence about the subject. The others are evidence
  about the chain or the corpus, and conflating them turns a modelling mistake
  into a false finding.
  """
  def diagnose(step, entities) do
    kinds = entities |> Enum.map(fn {_, e} -> e.kind end) |> MapSet.new()

    from? = MapSet.member?(kinds, step.from)
    to? = MapSet.member?(kinds, step.to)

    cond do
      from? and to? -> :unlinked
      not from? and not to? -> :vocabulary
      true -> :absent
    end
  end

  @doc "Human explanation for a gap classification."
  def explain_gap(:unlinked, step),
    do: "Both kinds are present, but nothing links #{step.from} to #{step.to}."

  def explain_gap(:vocabulary, step),
    do: "This record has no #{step.from} or #{step.to} — the chain may not fit this source."

  def explain_gap(:absent, step),
    do: "Only one side of #{step.from} → #{step.to} appears in this record."

  @doc """
  Kinds the chain asks for that the record does not use at all.

  A chain built for one corpus applied to another usually fails this way, and
  the fix is to align the vocabulary rather than to conclude anything about
  the subject.
  """
  def vocabulary_gap(chain, entities) do
    present = entities |> Enum.map(fn {_, e} -> e.kind end) |> MapSet.new()

    chain.steps
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(present, &1))
  end
end
