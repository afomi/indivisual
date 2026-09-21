defmodule Indivisual.Atlas.ProjectionsTest do
  @moduledoc """
  Projections are documented as pure functions of `(events, opts)`. These pin
  that contract and what each read model promises, so the view layer can be
  rearranged around them without the answers quietly changing.

  They run against the demo feed and assert structure rather than counts, so a
  richer fixture does not break them.
  """
  use Indivisual.DataCase, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Projections
  alias Indivisual.Atlas.Topology

  @unsettled ~w(reported proposed)

  defp events, do: Feed.events(Feed, [])

  # The entity with the most relationships: guaranteed to have neighbours.
  defp hub(events) do
    events
    |> Topology.relationships()
    |> Enum.flat_map(&[&1.subject, &1.object])
    |> Enum.frequencies()
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
  end

  describe "every projection" do
    test "is listed with a name and the question it answers" do
      assert Enum.map(Projections.list(), & &1.id) == ~w(activity entity topology provenance)
      assert Enum.all?(Projections.list(), &(is_binary(&1.name) and &1.question =~ "?"))
      assert Projections.get(Projections.default_id())
    end

    test "returns the shared canvas fields" do
      events = events()

      for %{id: id} <- Projections.list() do
        rm = Projections.materialize(id, events)

        assert rm.projection == id
        assert rm.event_count == length(events)
        assert is_map(rm.entities) and is_list(rm.relationships)
        # Every entity can be drawn.
        assert Map.keys(rm.positions) |> Enum.sort() == Map.keys(rm.entities) |> Enum.sort()
      end
    end

    test "is reproducible: same events and options, same read model" do
      events = events()
      opts = [entity: hub(events)]

      for %{id: id} <- Projections.list() do
        assert Projections.materialize(id, events, opts) ==
                 Projections.materialize(id, events, opts)
      end
    end

    test "no events is an empty read model, not an error" do
      for %{id: id} <- Projections.list() do
        assert %{entities: entities, relationships: [], event_count: 0} =
                 Projections.materialize(id, [])

        assert entities == %{}
      end
    end

    test "an unknown id falls back to the default" do
      events = events()

      assert Projections.materialize("nope", events) ==
               Projections.materialize(Projections.default_id(), events)
    end
  end

  describe "activity" do
    test "one item per event, in the order given" do
      events = events()
      rm = Projections.materialize("activity", events)

      assert Enum.map(rm.items, & &1.event.event_id) == Enum.map(events, & &1.event_id)

      for item <- rm.items do
        assert item.affected == Event.affected_refs(item.event)
        assert item.annotation == Event.annotation?(item.event)
      end
    end
  end

  describe "entity" do
    test "without a focus it reports none, and keeps the whole canvas" do
      events = events()
      rm = Projections.materialize("entity", events)

      assert %{entity: nil, events: [], sources: [], unresolved: []} = rm
      assert rm.entities == Topology.entities(events)
    end

    test "a ref nothing mentions is treated as no focus" do
      assert %{entity: nil} = Projections.materialize("entity", events(), entity: "thing:nowhere")
    end

    test "focused: the canvas is the entity and its neighbours" do
      events = events()
      ref = hub(events)
      rm = Projections.materialize("entity", events, entity: ref)

      neighbours = Topology.neighbors(Topology.relationships(events), ref)

      assert rm.entity.ref == ref
      assert neighbours != []
      assert Map.keys(rm.entities) |> Enum.sort() == Enum.sort(Enum.uniq([ref | neighbours]))
      assert Enum.all?(rm.relationships, &(ref in [&1.subject, &1.object]))
    end

    test "focused: events, sources and unresolved are all about that entity" do
      events = events()
      ref = hub(events)
      rm = Projections.materialize("entity", events, entity: ref)

      assert rm.events != []
      assert Enum.all?(rm.events, &(ref in Event.affected_refs(&1)))
      assert rm.sources == rm.events |> Enum.map(& &1.source_id) |> Enum.uniq()

      assert rm.unresolved == Enum.filter(rm.events, &(&1.truth_state in @unsettled))
    end
  end

  describe "topology" do
    test "keeps only entities that a relationship connects" do
      rm = Projections.materialize("topology", events())

      connected = rm.relationships |> Enum.flat_map(&[&1.subject, &1.object]) |> MapSet.new()

      assert rm.entities != %{}
      assert Enum.all?(Map.keys(rm.entities), &MapSet.member?(connected, &1))
    end

    test "reads exactly the events it is given: no hidden window", %{} do
      events = events()
      until = Enum.at(events, 3).event_id

      # `:until` used to narrow the graph to the events up to the selected one,
      # with no control and no readout. It is ignored now; a caller that wants a
      # window passes fewer events.
      assert Projections.materialize("topology", events, until: until) ==
               Projections.materialize("topology", events)

      assert Projections.materialize("topology", Enum.take(events, 4)).relationships ==
               Topology.relationships(Enum.take(events, 4))
    end
  end

  describe "provenance" do
    test "groups every event under its truth state, in order of settledness" do
      events = events()
      rm = Projections.materialize("provenance", events)

      assert Enum.map(rm.groups, & &1.truth_state) == Event.truth_states()

      for %{truth_state: state, events: grouped} <- rm.groups do
        assert Enum.all?(grouped, &(&1.truth_state == state))
        assert rm.counts[state] == length(grouped)
      end

      assert rm.counts |> Map.values() |> Enum.sum() == length(events)
    end

    test "a state nothing has reached is an empty group, not a missing one" do
      rm = Projections.materialize("provenance", [])

      assert length(rm.groups) == length(Event.truth_states())
      assert Enum.all?(rm.groups, &(&1.events == []))
    end
  end
end
