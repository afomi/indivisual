defmodule Indivisual.Atlas.SceneTest do
  @moduledoc """
  The scene folds the timeline, the map and the graph into layouts of one set of
  points. These pin what makes that honest: every layout places the same nodes,
  x and y are always the 2D space and z is always time, and a point
  a layout cannot place goes to the shelf and is counted — never invented.
  """
  use Indivisual.DataCase, async: true

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Geo
  alias Indivisual.Atlas.Scene
  alias Indivisual.Atlas.Topology

  defp scene do
    events = Feed.events(Feed, [])
    entities = Topology.entities(events)
    {events, entities, Scene.build(events, entities, Topology.relationships(events))}
  end

  defp events_of(scene), do: Enum.filter(scene.nodes, &(&1.kind == "event"))
  defp entities_of(scene), do: Enum.filter(scene.nodes, &(&1.kind == "entity"))
  defp layout_ids, do: Enum.map(Scene.layouts(), & &1.id)

  test "every activity and every entity is a point, in every layout" do
    {events, entities, scene} = scene()

    assert length(events_of(scene)) == length(events)
    assert length(entities_of(scene)) == map_size(entities)

    for node <- scene.nodes, layout <- layout_ids() do
      assert [x, y, z] = node.pos[layout]
      assert Enum.all?([x, y, z], &(is_float(&1) and abs(&1) <= 1.5)), "#{node.id} in #{layout}"
      assert is_boolean(node.placed[layout])
    end
  end

  test "is a pure function of what it is handed" do
    events = Feed.events(Feed, [])
    entities = Topology.entities(events)
    rels = Topology.relationships(events)

    assert Scene.build(events, entities, rels) == Scene.build(events, entities, rels)
  end

  test "nothing in, nothing out" do
    assert %{nodes: [], links: []} = Scene.build([], %{}, [])
  end

  describe "the convention: x and y are space, z is time" do
    # The layouts with a time axis. The Map has none: it folds z flat.
    @data_layouts ~w(timeline moment space graph)
    # Time runs OUT of the screen where events rise off a back plane, and INTO it
    # in a moment, which is stood in: the past near you, the future ahead.
    @toward_viewer ~w(timeline space graph)

    test "in every data layout an event's z is when it happened, and only that" do
      {_, _, scene} = scene()

      for node <- events_of(scene), layout <- @data_layouts do
        sign = if layout in @toward_viewer, do: 1, else: -1
        assert_in_delta Enum.at(node.pos[layout], 2), sign * (node.time * 2 - 1), 0.001
      end
    end

    test "off a back plane, later is nearer" do
      {_, _, scene} = scene()
      nodes = events_of(scene)

      for layout <- @toward_viewer, a <- nodes, b <- nodes, a.time < b.time do
        assert Enum.at(a.pos[layout], 2) < Enum.at(b.pos[layout], 2)
      end
    end

    test "in a moment the past is near and the future is far" do
      {_, _, scene} = scene()
      nodes = events_of(scene)

      for a <- nodes, b <- nodes, a.time < b.time do
        # Greater z is nearer the viewer.
        assert Enum.at(a.pos["moment"], 2) > Enum.at(b.pos["moment"], 2)
      end
    end

    test "entities persist, so they rest on a plane behind the earliest event" do
      {_, _, scene} = scene()
      earliest = scene |> events_of() |> Enum.map(&Enum.at(&1.pos["space"], 2)) |> Enum.min()

      for node <- entities_of(scene), layout <- ~w(space graph) do
        assert Enum.at(node.pos[layout], 2) < earliest
      end
    end

    test "every layout's frame is the same box, flat along the axis it does not use" do
      {_, _, scene} = scene()

      assert scene.frames["space"].size == [2.0, 2.0, 2.0]
      assert scene.frames["timeline"].size == [0.0, 2.0, 2.0]

      for layout <- ~w(moment map graph) do
        assert scene.frames[layout].size == [2.0, 2.0, 0.0]
      end

      assert (Map.keys(scene.frames) -- ["custom"]) |> Enum.sort() == Enum.sort(layout_ids())
    end
  end

  describe "timeline: along time, seen from the side" do
    test "everything folds onto the plane x = 0" do
      {_, _, scene} = scene()

      assert Enum.all?(scene.nodes, &(hd(&1.pos["timeline"]) == 0.0))
    end

    test "time spans the whole axis" do
      {_, _, scene} = scene()
      zs = scene |> events_of() |> Enum.map(&Enum.at(&1.pos["timeline"], 2))

      assert_in_delta Enum.min(zs), -1.0, 0.001
      assert_in_delta Enum.max(zs), 1.0, 0.001
    end

    test "a time domain rules the axis, so a filter never moves a point" do
      events = Feed.events(Feed, [])
      entities = Topology.entities(events)
      rels = Topology.relationships(events)
      ms = &DateTime.to_unix(Indivisual.Atlas.Event.effective_time(&1), :millisecond)

      domain = %{
        from: events |> Enum.map(ms) |> Enum.min(),
        to: events |> Enum.map(ms) |> Enum.max()
      }

      whole = Scene.build(events, entities, rels, time_domain: domain)
      # A filtered view: only the middle of the record.
      some = Enum.slice(events, 5..9)

      part =
        Scene.build(some, Topology.entities(some), Topology.relationships(some),
          time_domain: domain
        )

      z = fn scene, id ->
        scene.nodes
        |> Enum.find(&(&1.kind == "event" and &1.id == id))
        |> then(&Enum.at(&1.pos["timeline"], 2))
      end

      for event <- some do
        assert_in_delta z.(part, event.event_id), z.(whole, event.event_id), 0.0001
      end

      # The axis is the record's, not the filtered events' own.
      assert part.span == domain
      assert whole.span == domain
    end

    test "without a domain the axis is the events' own span, as before" do
      # The first and last of the record: two moments, so there is a span to fill.
      all = Feed.events(Feed, [])
      some = [List.first(all), List.last(all)]
      scene = Scene.build(some, Topology.entities(some), Topology.relationships(some))

      zs =
        scene.nodes
        |> Enum.filter(&(&1.kind == "event"))
        |> Enum.map(&Enum.at(&1.pos["timeline"], 2))

      assert_in_delta Enum.min(zs), -1.0, 0.001
      assert_in_delta Enum.max(zs), 1.0, 0.001
    end

    test "a domain that does not contain the events is widened to hold them" do
      events = Feed.events(Feed, [])
      scene = Scene.build(events, Topology.entities(events), [], time_domain: %{from: 0, to: 1})

      zs =
        scene.nodes
        |> Enum.filter(&(&1.kind == "event"))
        |> Enum.map(&Enum.at(&1.pos["timeline"], 2))

      assert Enum.all?(zs, &(&1 >= -1.0001 and &1 <= 1.0001)), "no point may leave the axis"
    end

    test "events at one moment stack rather than overlap" do
      {_, _, scene} = scene()
      spots = Enum.map(events_of(scene), &tl(&1.pos["timeline"]))

      assert spots == Enum.uniq(spots)
    end

    test "entities hang below the axis, events above it" do
      {_, _, scene} = scene()

      assert Enum.all?(events_of(scene), &(Enum.at(&1.pos["timeline"], 1) > 0))
      assert Enum.all?(entities_of(scene), &(Enum.at(&1.pos["timeline"], 1) < 0))
    end
  end

  describe "moment: a slice across time" do
    defp at_moment(id) do
      events = Feed.events(Feed, [])
      entities = Topology.entities(events)
      Scene.build(events, entities, Topology.relationships(events), moment: id)
    end

    test "cuts at the chosen event's instant; the latest, when none is chosen" do
      events = Feed.events(Feed, [])
      first = List.first(events).event_id

      chosen = at_moment(first)
      assert Enum.find(events_of(chosen), &(&1.id == first)).in_slice

      {_, _, default} = scene()
      latest = Enum.max_by(events_of(default), & &1.time)
      assert latest.in_slice
      assert at_moment("nope") == default
    end

    test "the plane moves to the moment; the events stay where they are" do
      events = Feed.events(Feed, [])
      early = at_moment(List.first(events).event_id)
      late = at_moment(List.last(events).event_id)

      # An early moment's plane is near the viewer; a late one's is far.
      assert Enum.at(early.frames["moment"].center, 2) > Enum.at(late.frames["moment"].center, 2)

      positions = fn scene -> Map.new(events_of(scene), &{&1.id, &1.pos["moment"]}) end
      assert positions.(early) == positions.(late)
    end

    test "what happened then lies in the plane; the rest is behind it or in front" do
      events = Feed.events(Feed, [])
      mid = Enum.at(events, div(length(events), 2)).event_id
      scene = at_moment(mid)
      plane = Enum.at(scene.frames["moment"].center, 2)
      moment = Enum.find(events_of(scene), &(&1.id == mid)).time

      for node <- events_of(scene) do
        z = Enum.at(node.pos["moment"], 2)

        cond do
          node.in_slice -> assert_in_delta z, plane, 0.05
          # The past is on the viewer's side of the plane; the future beyond it.
          node.time < moment -> assert z > plane
          true -> assert z < plane
        end
      end
    end

    test "the entity columns stand in the plane, along its foot" do
      {_, _, scene} = scene()
      plane = Enum.at(scene.frames["moment"].center, 2)
      feet = Enum.map(entities_of(scene), & &1.pos["moment"])

      assert Enum.all?(feet, fn [_x, y, z] -> y < -0.8 and z == plane end)
      xs = Enum.map(feet, &hd/1)
      assert xs == Enum.uniq(xs)
    end

    test "is a different view from the timeline, not the same picture turned" do
      {_, _, scene} = scene()

      # Both put an event at the same z. The timeline folds x away; the moment
      # spreads it by entity — so what shares an instant separates sideways.
      in_slice = Enum.filter(events_of(scene), & &1.in_slice)
      assert length(in_slice) > 1

      assert in_slice |> Enum.map(&hd(&1.pos["timeline"])) |> Enum.uniq() == [0.0]
      assert in_slice |> Enum.map(&hd(&1.pos["moment"])) |> Enum.uniq() |> length() > 1
    end

    test "nothing in the plane overlaps" do
      {_, _, scene} = scene()
      spots = for n <- events_of(scene), n.in_slice, do: n.pos["moment"]

      assert spots == Enum.uniq(spots)
    end
  end

  describe "map: x is longitude, y is latitude" do
    test "located entities are where Geo puts them, north up" do
      {_, entities, scene} = scene()
      located = entities |> Geo.project() |> Map.fetch!(:points) |> MapSet.new(& &1.ref)

      for node <- entities_of(scene) do
        assert node.placed["map"] == MapSet.member?(located, node.id)
      end
    end

    test "Web Mercator: the projection map tiles are cut in" do
      assert Scene.mercator(0, 0) == {0.5, 0.5}
      assert_in_delta elem(Scene.mercator(0, -180), 0), 0.0, 1.0e-9
      # ~85.0511°N is the top edge of the square world.
      assert_in_delta elem(Scene.mercator(85.0511287798, 0), 1), 0.0, 1.0e-6
      # y runs southward, the tile convention.
      assert elem(Scene.mercator(10, 0), 1) < elem(Scene.mercator(-10, 0), 1)
    end

    test "one scale serves both axes, so the ground is not stretched" do
      # A degree of latitude is longer than a degree of longitude on a Mercator
      # map away from the equator — by 1/cos(lat). A chart-style layout that
      # normalised each axis on its own would erase that, and no tile would fit.
      entities = %{
        "place:a" => entity("place:a", 38.0, -122.0),
        "place:b" => entity("place:b", 39.0, -121.0)
      }

      %{nodes: nodes} = Scene.build([], entities, [])
      [[ax, ay, _], [bx, by, _]] = nodes |> Enum.sort_by(& &1.id) |> Enum.map(& &1.pos["map"])

      assert_in_delta (by - ay) / (bx - ax), 1 / :math.cos(38.5 * :math.pi() / 180), 0.01
    end

    test "the ground shown is a square the client can tile, holding every place" do
      {_, entities, scene} = scene()
      %{cx: cx, cy: cy, half: half} = scene.map

      assert half > 0

      for {_ref, entity} <- entities, {lat, lng} <- [Geo.coords(entity)] do
        {wx, wy} = Scene.mercator(lat, lng)
        assert abs(wx - cx) <= half and abs(wy - cy) <= half
      end

      # And every placed entity is inside the frame.
      for node <- entities_of(scene), node.placed["map"] do
        [x, y, _] = node.pos["map"]
        assert abs(x) <= 1.0 and abs(y) <= 1.0
      end
    end

    test "one place still gets a patch of ground; none gets no map at all" do
      one = %{"place:a" => entity("place:a", 38.35, -121.98)}
      assert %{half: half} = Scene.build([], one, []).map
      assert half > 0
      assert [%{pos: %{"map" => [x, y, _]}}] = Scene.build([], one, []).nodes
      assert {x, y} == {0.0, 0.0}

      assert Scene.build([], %{}, []).map == nil
    end

    test "east is to the right and north is up" do
      entities = %{
        "place:sw" => entity("place:sw", 38.0, -122.0),
        "place:ne" => entity("place:ne", 39.0, -121.0)
      }

      %{nodes: nodes} = Scene.build([], entities, [])
      [ne, sw] = Enum.sort_by(nodes, & &1.id)

      assert hd(ne.pos["map"]) > hd(sw.pos["map"])
      assert Enum.at(ne.pos["map"], 1) > Enum.at(sw.pos["map"], 1)
    end

    test "an event sits AT the places it touches, fanned out just round them" do
      {_, _, scene} = scene()
      by_key = Map.new(scene.nodes, &{"#{&1.kind}:#{&1.id}", &1})

      for event <- events_of(scene), event.placed["map"] do
        anchors =
          for link <- scene.links,
              link.kind == "touches",
              link.from == "event:#{event.id}",
              entity = by_key[link.to],
              entity.placed["map"],
              do: entity.pos["map"]

        assert anchors != []
        [x, y, _] = event.pos["map"]
        cx = anchors |> Enum.map(&Enum.at(&1, 0)) |> mean()
        cy = anchors |> Enum.map(&Enum.at(&1, 1)) |> mean()

        # Off the spot, so the place stays visible — but plainly at it.
        distance = :math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        assert distance > 0.0
        assert distance < 0.35
      end
    end

    test "seen from above, no two events at a place hide each other" do
      {_, _, scene} = scene()

      spots = for e <- events_of(scene), e.placed["map"], do: Enum.take(e.pos["map"], 2)
      assert length(spots) > 1
      assert spots == Enum.uniq(spots)
    end

    test "they fan out in the order they happened" do
      {_, _, scene} = scene()
      by_key = Map.new(scene.nodes, &{"#{&1.kind}:#{&1.id}", &1})

      # Events that stand over exactly one and the same place.
      one_place =
        for e <- events_of(scene), e.placed["map"] do
          places =
            for l <- scene.links,
                l.kind == "touches" and l.from == "event:#{e.id}",
                by_key[l.to].placed["map"],
                do: l.to

          {places, e}
        end

      {_place, group} =
        one_place
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.filter(fn {places, es} -> length(places) == 1 and length(es) > 1 end)
        |> List.first({nil, []})

      if group != [] do
        [place_key] =
          group
          |> hd()
          |> then(fn e ->
            for l <- scene.links,
                l.kind == "touches",
                l.from == "event:#{e.id}",
                by_key[l.to].placed["map"],
                do: l.to
          end)

        [px, py, _] = by_key[place_key].pos["map"]

        radii =
          group
          |> Enum.sort_by(& &1.time)
          |> Enum.map(fn e ->
            [x, y, _] = e.pos["map"]
            :math.sqrt((x - px) ** 2 + (y - py) ** 2)
          end)

        assert radii == Enum.sort(radii)
      end
    end

    test "what has no location goes to the shelf and is counted, never invented" do
      {_, entities, scene} = scene()
      unlocated = Geo.project(entities).unlocated_count

      assert unlocated > 0, "the fixture should have unlocated entities for this to mean anything"
      assert scene.shortfall["map"].entities == unlocated

      shelved = Enum.reject(scene.nodes, & &1.placed["map"])
      assert length(shelved) == scene.shortfall["map"].entities + scene.shortfall["map"].events
      # The shelf is below the map, which spans -1..1.
      assert Enum.all?(shelved, &(Enum.at(&1.pos["map"], 1) < -1.0))
    end
  end

  describe "spacetime: the map, with time as the third axis" do
    test "the Map is that same ground with no time axis: everything in one plane" do
      {_, _, scene} = scene()

      assert Enum.all?(entities_of(scene), &(Enum.at(&1.pos["map"], 2) == 0.0))
      assert scene |> events_of() |> Enum.map(&Enum.at(&1.pos["map"], 2)) |> Enum.uniq() == [0.01]
      assert Scene.layout("map").dims == ~w(lng lat none)
      assert Scene.layout("space").dims == ~w(lng lat time)
    end

    test "entities stand where the map puts them" do
      {_, _, scene} = scene()

      for node <- entities_of(scene) do
        assert Enum.take(node.pos["space"], 2) == Enum.take(node.pos["map"], 2)
        assert node.placed["space"] == node.placed["map"]
      end
    end

    test "an event stands straight over its places, at the height of when — no fan needed" do
      {_, _, scene} = scene()
      by_key = Map.new(scene.nodes, &{"#{&1.kind}:#{&1.id}", &1})

      for event <- events_of(scene), event.placed["space"] do
        anchors =
          for l <- scene.links,
              l.kind == "touches" and l.from == "event:#{event.id}",
              by_key[l.to].placed["space"],
              do: by_key[l.to].pos["space"]

        [x, y, z] = event.pos["space"]
        assert_in_delta x, anchors |> Enum.map(&Enum.at(&1, 0)) |> mean(), 0.001
        assert_in_delta y, anchors |> Enum.map(&Enum.at(&1, 1)) |> mean(), 0.001
        assert_in_delta z, event.time * 2 - 1, 0.001
      end
    end
  end

  describe "graph: x and y are semantic axes" do
    @semantic [
      %{id: "sem:1", name: "Reach", says: "local ↔ regional", semantic: true},
      %{id: "sem:2", name: "Stage", says: "plan ↔ built", semantic: true},
      %{id: "sem:3", name: "Ledger", says: "cost ↔ benefit", semantic: true}
    ]

    defp scored do
      events = Feed.events(Feed, [])
      entities = Topology.entities(events)

      # Every event but the last is scored, so there is something left unplaced.
      scores =
        events
        |> Enum.drop(-1)
        |> Enum.with_index()
        |> Map.new(fn {event, i} ->
          {event.event_id,
           %{"sem:1" => i / length(events) * 2 - 1, "sem:2" => 0.5, "sem:3" => -0.5}}
        end)

      {events,
       Scene.build(events, entities, Topology.relationships(events),
         semantic: %{dims: @semantic, scores: scores}
       ), scores}
    end

    test "the Graph takes the first two semantic axes there are, and time" do
      assert Scene.layout("graph", @semantic).dims == ["sem:1", "sem:2", "time"]
      # With fewer axes than it needs, it folds what it cannot fill.
      assert Scene.layout("graph", Enum.take(@semantic, 1)).dims == ["sem:1", "none", "time"]
      assert Scene.layout("graph", []).dims == ["none", "none", "time"]
    end

    test "every semantic axis is a dimension any axis can carry" do
      ids = @semantic |> Scene.dimensions() |> Enum.map(& &1.id)

      assert "sem:3" in ids
      assert List.last(ids) == "none"
      assert Scene.parse_axes("sem:3,truth,time", @semantic) == ["sem:3", "truth", "time"]
      # Unknown without the axes to vouch for it.
      assert Scene.parse_axes("sem:3,truth,time") == nil
    end

    test "an event sits where its text scores, at its own time" do
      {_, scene, scores} = scored()

      for node <- events_of(scene), node.placed["graph"] do
        [x, y, z] = node.pos["graph"]
        assert_in_delta x, scores[node.id]["sem:1"], 0.001
        assert_in_delta y, scores[node.id]["sem:2"], 0.001
        assert_in_delta z, node.time * 2 - 1, 0.001
      end
    end

    test "an entity reads as the events that touch it do, and rests on the back plane" do
      {_, scene, _} = scored()

      for node <- entities_of(scene), node.placed["graph"] do
        [_x, y, z] = node.pos["graph"]
        assert_in_delta y, 0.5, 0.001
        assert z < -1.0
      end
    end

    test "what has not been scored is shelved and counted, never placed by guess" do
      {events, scene, _} = scored()
      unscored = List.last(events).event_id

      refute Enum.find(events_of(scene), &(&1.id == unscored)).placed["graph"]
      assert scene.shortfall["graph"].events >= 1
    end

    test "with axes but no scores yet, the Graph shelves everything rather than guessing" do
      events = Feed.events(Feed, [])
      entities = Topology.entities(events)

      unscored = Scene.build(events, entities, [], semantic: %{dims: @semantic, scores: %{}})

      assert Enum.all?(events_of(unscored), &(not &1.placed["graph"]))
      assert unscored.shortfall["graph"].events == length(events)
    end
  end

  describe "axes a reader chooses" do
    defp custom(axes) do
      events = Feed.events(Feed, [])
      entities = Topology.entities(events)
      Scene.build(events, entities, Topology.relationships(events), axes: axes)
    end

    test "a layout is only a choice of three dimensions, and the presets say theirs" do
      ids = MapSet.new(Scene.dimensions(), & &1.id)

      for layout <- Scene.layouts() do
        assert [_, _, _] = layout.dims
        assert Enum.all?(layout.dims, &MapSet.member?(ids, &1)), layout.id
      end

      # The convention, as data: where there is a time axis, it is z. Only the
      # Map has none — it folds z flat.
      for layout <- Scene.layouts() do
        expected = if layout.id == "map", do: "none", else: "time"
        assert List.last(layout.dims) == expected, layout.id
      end
    end

    test "an assignment parses only if it is three known dimensions" do
      assert Scene.parse_axes("lng,lat,time") == ~w(lng lat time)
      assert Scene.parse_axes(~w(source truth none)) == ~w(source truth none)
      assert Scene.parse_axes("lng,lat") == nil
      assert Scene.parse_axes("lng,lat,nope") == nil
      assert Scene.parse_axes(nil) == nil
    end

    test "a preset's own three dimensions ARE that preset" do
      for layout <- Scene.layouts(), do: assert(Scene.layout_for(layout.dims) == layout.id)
      assert Scene.layout_for(~w(source truth time)) == "custom"
    end

    test "with no choice made there is no custom layout" do
      {_, _, scene} = scene()
      refute Enum.any?(scene.nodes, &Map.has_key?(&1.pos, "custom"))
      refute Map.has_key?(scene.shortfall, "custom")
    end

    test "every point is placed by exactly the dimensions chosen" do
      scene = custom(~w(source truth time))

      for node <- events_of(scene) do
        [_x, _y, z] = node.pos["custom"]
        assert node.placed["custom"]
        assert_in_delta z, node.time * 2 - 1, 0.001
      end

      # Events from one source share an x; events of one truth state share a y.
      by_x = scene |> events_of() |> Enum.group_by(&hd(&1.pos["custom"]))
      assert map_size(by_x) > 1
    end

    test "choosing the map's dimensions by hand lands on the map's places" do
      scene = custom(~w(lng lat none))

      for node <- entities_of(scene), node.placed["map"] do
        [mx, my, _] = node.pos["map"]
        [cx, cy, cz] = node.pos["custom"]
        assert_in_delta cx, mx, 0.001
        assert_in_delta cy, my, 0.001
        assert cz == 0.0
      end
    end

    test "a folded axis is flat, in the points and in the frame" do
      scene = custom(~w(none stack time))

      assert Enum.all?(scene.nodes, &(hd(&1.pos["custom"]) == 0.0))
      assert scene.frames["custom"].size == [0.0, 2.0, 2.0]
    end

    test "a point without a chosen dimension is shelved on that axis, and counted" do
      scene = custom(~w(lng lat time))
      shelved = Enum.reject(scene.nodes, & &1.placed["custom"])

      assert shelved != []

      assert length(shelved) ==
               scene.shortfall["custom"].entities + scene.shortfall["custom"].events

      assert Enum.all?(shelved, fn n -> Enum.any?(n.pos["custom"], &(&1 < -1.0)) end)
    end
  end

  describe "links" do
    test "relationships join entities; touches join an event to what it affects" do
      {events, entities, scene} = scene()
      keys = MapSet.new(scene.nodes, &"#{&1.kind}:#{&1.id}")

      assert Enum.all?(
               scene.links,
               &(MapSet.member?(keys, &1.from) and MapSet.member?(keys, &1.to))
             )

      rels = Enum.filter(scene.links, &(&1.kind == "relationship"))
      assert length(rels) == length(Topology.relationships(events))
      assert Enum.any?(scene.links, &(&1.kind == "touches"))
      assert map_size(entities) > 0
    end
  end

  describe "layouts" do
    test "nothing is a placeholder any more; the Graph alone is a model's reading" do
      assert for(%{id: id, basis: :placeholder} <- Scene.layouts(), do: id) == []
      assert for(%{id: id, basis: :semantic} <- Scene.layouts(), do: id) == ["graph"]
    end

    test "Spacetime leads the switch" do
      assert hd(Scene.layouts()).id == "space"
      assert hd(Scene.layouts()).name == "Spacetime"
    end

    test "an unknown id falls back to the default" do
      assert Scene.layout("nope").id == Scene.default_layout()
    end
  end

  defp mean(numbers), do: Enum.sum(numbers) / length(numbers)

  defp entity(ref, lat, lng) do
    %{
      ref: ref,
      label: ref,
      kind: "place",
      geo: %{"lat" => lat, "lng" => lng},
      registered: true,
      event_ids: [],
      truth_state: "observed"
    }
  end
end
