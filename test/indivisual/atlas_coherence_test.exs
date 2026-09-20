defmodule Indivisual.Atlas.CoherenceTest do
  @moduledoc """
  A chain names what kind of link each relationship is, and reports which
  expected links the record does not contain. The gaps are the point: an
  absence is only meaningful because the chain encodes an obligation.
  """
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Coherence
  alias Indivisual.Atlas.Feed

  setup do
    %{events: Feed.events(Feed, [])}
  end

  test "reads the fixture as a complete chain", %{events: events} do
    result = Coherence.materialize("civic", events)

    assert result.present == result.expected
    assert result.gaps == []
  end

  test "every link names its kind-pair and carries both entities", %{events: events} do
    %{links: links} = Coherence.materialize("civic", events)

    for link <- links do
      assert link.label =~ "→"
      assert link.from.label
      assert link.to.label
      assert link.relationship.relationship
    end
  end

  test "links are existing relationships, never invented", %{events: events} do
    %{links: links} = Coherence.materialize("civic", events)
    asserted = Indivisual.Atlas.Topology.relationships(events)

    for link <- links do
      assert link.relationship in asserted,
             "a chain must only surface relationships the record already asserts"
    end
  end

  test "missing links are reported as gaps", %{events: events} do
    # A thin slice cannot satisfy the chain.
    %{gaps: gaps, present: present} = Coherence.materialize("civic", Enum.take(events, 8))

    assert present == 0
    assert length(gaps) == 5
    assert Enum.all?(gaps, & &1.step.label)
    # Each gap says WHICH kind of absence it is.
    assert Enum.all?(gaps, &(&1.reason in [:unlinked, :vocabulary, :absent]))
    assert Enum.all?(gaps, &(&1.explanation != ""))
  end

  test "an empty record is all gaps, not an error" do
    result = Coherence.materialize("civic", [])

    assert result.present == 0
    assert length(result.gaps) == result.expected
  end

  test "an unknown chain id falls back to the default" do
    assert Coherence.get("nonsense").id == Coherence.default_id()
  end

  test "every declared chain materializes without error", %{events: events} do
    for chain <- Coherence.chains() do
      result = Coherence.materialize(chain.id, events)
      assert result.expected == length(chain.steps)
      assert result.present + length(result.gaps) == result.expected
    end
  end
end
