defmodule Indivisual.Atlas.Scene do
  @moduledoc """
  One scene, several layouts: the view model for the "Spacetime" panel on `/atlas`.

  The timeline, the map and the graph each pick their own axes and draw the same
  record. This puts every activity and every entity in ONE 3D scene as a point,
  and treats each of those views as a **layout** — an assignment of a position to
  every point. Switching layout is then a dimensional transformation of the same
  points rather than a different picture, and a 2D view is a slice of the volume:

  ## The axes: x and y are space, z is time

  One convention holds across every data layout, so the scene is a spacetime and
  not five pictures: **x and y are the 2D space a layout arranges things in, and
  z is when.** Every event sits at the z of the moment it happened, whatever the
  layout; only its x and y change. Entities, which persist, rest on a plane.

  | Layout     | x, y — the 2D space                          | Seen from |
  |------------|----------------------------------------------|-----------|
  | `timeline` | x collapsed to 0; y stacks what is simultaneous | the SIDE, so z (time) runs left to right |
  | `moment`   | x is which entity; y stacks                  | the FRONT, at a plane cutting z at one moment; here time runs INTO the screen — past near, future far |
  | `space`    | x is longitude, y is latitude — the map — with time as the third axis ("Spacetime") | three-quarter, orbiting: events stand over their places at the height of when |
  | `map`      | x is longitude, y is latitude (Web Mercator, north up); z folded flat | directly ABOVE (bird's-eye): no time axis; events fan out round their place |
  | `graph`    | two SEMANTIC axes (`Atlas.Semantics`): meaning, scored from an event's text | the front: entities on the back plane, events come forward in time |

  ## Two takes on time, kept distinct

  With z fixed as time, `timeline` and `moment` are the same record seen from two
  directions — which is exactly why they are different views:

    * **`timeline` looks ALONG the time axis from the side.** Everything folds
      onto the plane x = 0: many events, each its own object, across the whole
      span. It answers "when did things happen?". The sticky band is this layout.
    * **`moment` looks AT a slice of it.** A plane cuts z at one instant (the
      selected event's). What happened then lies in the plane, spread over the
      entity it touches; the past is on the viewer's side of the plane and the
      future lies beyond it. A moment is a temporal slice — the state of things
      at a given time — so the plane moves when the selection does, and the
      events stay where they are. It answers "what was going on at once?".

  ## The honest part

  A layout can only place what carries the facet it needs (`docs/VIEWS.md`). An
  entity with no coordinates has no place on the map, and an event touching only
  such entities has none either. They are not dropped and not given invented
  coordinates: they are set on a **shelf** beside the slice with `placed: false`,
  and `shortfall` counts them, so the view can say "6 of 11 entities have no
  location" the way `Atlas.Geo` does.

  Pure, like every Atlas view model: a function of the events and entities it is
  handed, deterministic, and safe to throw away.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Geo

  @layouts [
    %{
      id: "space",
      dims: ["lng", "lat", "time"],
      name: "Spacetime",
      slice: nil,
      axes: %{x: "west → east", y: "south → north", z: "earlier → later"},
      basis: :data,
      says:
        "The map, with time added as a third axis. Entities sit where they are, on the ground; each event stands over the places it touches, at the height of when it happened. Drag to orbit."
    },
    %{
      id: "timeline",
      dims: ["none", "stack", "time"],
      name: "Timeline",
      slice: "yz",
      axes: %{x: nil, y: "at the same moment", z: "earlier → later"},
      basis: :data,
      says:
        "Along time, seen from the side. Left to right is when; events at one moment stack; entities hang below where they are first mentioned."
    },
    %{
      id: "moment",
      dims: ["entity", "stack", "time"],
      name: "Moment",
      slice: "xy",
      axes: %{x: "which entity", y: "at this moment", z: "past (near) → future (far)"},
      basis: :data,
      says:
        "A slice across time, at the selected event's moment. What happened then lies in the plane, over the entity it touches. The past is nearer you than the plane; the future lies beyond it."
    },
    %{
      id: "map",
      dims: ["lng", "lat", "none"],
      name: "Map",
      slice: "xy",
      axes: %{x: "west → east", y: "south → north", z: "earlier → later"},
      basis: :data,
      says:
        "A map, seen from directly above, north up, with no time axis: everything in view at once. Entities sit where they are; the events at a place fan out round it in the order they happened. Drag to pan, scroll to zoom."
    },
    %{
      id: "graph",
      # x and y are the first two semantic axes there are: see `layouts/1`.
      dims: [:semantic, :semantic, "time"],
      name: "Graph",
      slice: "xy",
      axes: %{x: nil, y: nil, z: "earlier → later"},
      basis: :semantic,
      says:
        "Meaning, as a graph. x and y are semantic axes — two poles each, scored from what an event's text says — so things that read alike sit together, joined by their relationships, with time coming toward you. Change the axes in the dropdowns below."
    }
  ]

  @default "moment"

  # Layouts still being worked out: complete enough to develop and test
  # against, not to put in front of a reader. Gated on its own key rather than
  # on `dev_routes`, which is about routes; config/dev.exs and config/test.exs
  # turn them on, and prod simply never does.
  @unreleased ~w(space moment graph)

  # What a reader outside development opens on and can switch between.
  @released_default "timeline"

  # How thick the `moment` slice is, as a fraction of the span in view: events
  # this close to the moment count as "at once" and lie on the plane together.
  @thickness 0.02

  # Entities persist, so they rest on a plane just behind the earliest event
  # (z runs -1..1) rather than at any one time.
  @base -1.15
  # Where the shelf for unplaceable points sits, just outside the slice.
  @shelf 1.35

  @doc """
  Layout definitions, in the order the switch shows them. `semantic` is the
  semantic dimensions there are: a layout whose axes are semantic takes them in
  order, and folds an axis flat where there is none to put on it.
  """
  def layouts(semantic \\ []) do
    ids = Enum.map(semantic, & &1.id)

    @layouts
    |> Enum.filter(&released?(&1.id))
    |> Enum.map(fn layout ->
      {dims, _left} =
        Enum.map_reduce(layout.dims, ids, fn
          :semantic, [id | rest] -> {id, rest}
          :semantic, [] -> {"none", []}
          dim, left -> {dim, left}
        end)

      %{layout | dims: dims}
    end)
  end

  @doc """
  Whether a layout is offered here. Unreleased ones appear only where
  `:unreleased_layouts` is set, so a half-finished view cannot reach a reader.
  """
  def released?(id) do
    id not in @unreleased or Application.get_env(:indivisual, :unreleased_layouts, false)
  end

  @doc "Every layout, released or not — for tests and for the docs page."
  def all_layouts, do: @layouts

  @doc """
  The layout a fresh view opens in.

  Falls back where the usual default is unreleased: opening on a layout the
  switch does not offer would leave a reader unable to get back to it.
  """
  def default_layout do
    if released?(@default), do: @default, else: @released_default
  end

  # What an axis can carry. A layout is a choice of three of these — which is all
  # the presets are — so a reader can make the choice themselves, one axis at a
  # time. `none` folds an axis flat.
  @dimensions [
    %{id: "time", name: "time", says: "earlier → later"},
    %{id: "lng", name: "longitude", says: "west → east"},
    %{id: "lat", name: "latitude", says: "south → north"},
    %{id: "entity", name: "entity", says: "which entity"},
    %{id: "stack", name: "simultaneity", says: "at the same moment"},
    %{id: "source", name: "source", says: "which source"},
    %{id: "truth", name: "truth state", says: "less → more settled"}
  ]

  @none %{id: "none", name: "— none", says: "folded flat"}

  @doc """
  Everything an axis can carry, as `%{id:, name:, says:}`: the built-in
  dimensions, then `semantic` — one per semantic axis there is
  (`Indivisual.Atlas.Semantics.dimensions/1`), which is what makes the axes
  customizable — then `none`.
  """
  def dimensions(semantic \\ []), do: @dimensions ++ semantic ++ [@none]

  @doc "A dimension by id, or nil."
  def dimension(id, semantic \\ []), do: Enum.find(dimensions(semantic), &(&1.id == id))

  @doc """
  Parses an axis assignment — `"lng,lat,time"`, or a list — into `[x, y, z]`
  dimension ids, or nil if it is not three known dimensions.
  """
  def parse_axes(axes, semantic \\ [])

  def parse_axes(axes, semantic) when is_binary(axes),
    do: axes |> String.split(",") |> parse_axes(semantic)

  def parse_axes([_, _, _] = axes, semantic) do
    if Enum.all?(axes, &dimension(&1, semantic)), do: axes
  end

  def parse_axes(_, _semantic), do: nil

  @doc """
  The layout an assignment amounts to: a preset's id when it is exactly that
  preset's axes (so choosing longitude / latitude / none IS the map, tiles and
  all), otherwise `"custom"`.
  """
  def layout_for(axes, semantic \\ []) do
    case Enum.find(layouts(semantic), &(&1.dims == axes)) do
      %{id: id} -> id
      nil -> "custom"
    end
  end

  @doc "The `[x, y, z]` dimensions a layout shows; for `\"custom\"`, the ones given."
  def axes_of(id, axes, semantic \\ [])
  def axes_of("custom", axes, semantic), do: parse_axes(axes, semantic) || layout(@default).dims
  def axes_of(id, _axes, semantic), do: layout(id, semantic).dims

  @doc "A layout definition by id, falling back to the default."
  def layout(id, semantic \\ []) do
    all = layouts(semantic)

    # A link to an unreleased layout resolves to the default rather than to
    # nothing: `?scene=graph` reaches a reader who cannot switch to it, and
    # returning nil would take the page down instead of showing them a view.
    Enum.find(all, &(&1.id == id)) ||
      Enum.find(all, &(&1.id == default_layout())) ||
      hd(all)
  end

  @doc """
  Builds the scene for `events` and the `entities` / `relationships` derived
  from them (as `Topology` returns them).

  Options:

    * `:moment` — the `event_id` whose instant the `moment` layout cuts at.
      Defaults to the latest event, which is also what an unselected view shows.
    * `:axes` — `[x, y, z]` dimension ids. Adds a `"custom"` layout placing every
      point by exactly those dimensions. A point lacking one of them (no
      location, say) goes to the shelf on that axis and is counted, as ever.
    * `:read` — the events the filters leave, when `events` is the whole record.
      Every point is still built; those outside the set carry `read: false` so
      the view can draw them quietly instead of dropping them. An entity reads
      when an activity that touches it does.

  Returns `%{nodes:, links:, frames:, shortfall:}`:

    * a node is `%{id:, kind: "event" | "entity", label:, pos: %{layout => [x, y, z]},
      placed: %{layout => boolean}}` plus `truth:` and `date:` for events and
      `entity_kind:` for entities. Coordinates are scene units, roughly `-1.4..1.4`.
    * a link is `%{from:, to:, kind: "relationship" | "touches", truth:}`, where
      `from` / `to` are `{kind, id}` node keys rendered as `"kind:id"`.
    * `frames` is `%{layout => %{center: [x, y, z], size: [x, y, z]}}`: the box the
      layout's 2D space is drawn in, flat (size 0) along the axis it does not use.
    * `span` is `%{from:, to:}` in Unix ms: the moments z = -1 and z = 1 stand for.
    * `map` is `map_view/1`: the square of ground under the `map` layout, or nil.
    * `shortfall` is `%{layout => %{entities:, events:}}`, the unplaced counts.
  """
  def build(events, entities, relationships, opts \\ []) do
    # The time axis is ruled by `:time_domain` when given — `%{from:, to:}` in
    # Unix ms, normally the first and last event of the WHOLE record — and by
    # the events in hand otherwise. With the record's span, a filter changes
    # which points are there, never where a point is: narrowing the list does
    # not re-stretch the axis under the reader, and the panel's Timeline reads
    # the same width as the sticky timeline strip above it.
    domain = time_domain(events, opts[:time_domain])
    times = times(events, domain)
    moment = moment_time(events, times, opts[:moment])
    refs = entities |> Map.keys() |> Enum.sort()

    touched = Map.new(events, fn e -> {e.event_id, Enum.filter(touches(e), &(&1 in refs))} end)

    columns = moment_columns(refs)

    # Semantic axes: which there are, and where each event sits on them. Absent
    # (no axes yet, no embedding backend) the scene still builds: nothing is
    # scored, so the layouts that need scores shelve their points and say so.
    semantic = get_in(opts, [:semantic, :dims]) || []
    scores = get_in(opts, [:semantic, :scores]) || %{}
    dims = dimension_values(events, entities, refs, touched, times, columns, semantic, scores)
    graph_axes = layout("graph", semantic).dims

    entity_pos = %{
      "space" => map_entities(entities),
      "timeline" => time_entities(refs, events, touched, times),
      "moment" => Map.new(columns, fn {ref, x} -> {ref, placed([x, -0.9, ahead(moment)])} end),
      # The map has no time axis: everything lies in the one plane.
      "map" => entities |> map_entities() |> flatten(0.0),
      # Entities take their place from the events that touch them, and rest on
      # the back plane the events come forward from.
      "graph" => refs |> custom(dims, graph_axes) |> flatten(@base)
    }

    event_pos = %{
      # Spacetime: straight over the places an event touches, at its own time —
      # turning the scene is what separates them, so no fan.
      "space" => over(events, touched, times, entity_pos["space"]),
      "timeline" => time_events(events, times),
      "moment" => moment_events(events, touched, times, columns),
      "map" => events |> over(touched, times, entity_pos["map"], fan: true) |> flatten(0.01),
      "graph" => custom(Enum.map(events, & &1.event_id), dims, graph_axes)
    }

    # A reader's own choice of axes, when they have made one.
    {entity_pos, event_pos} =
      case parse_axes(opts[:axes], semantic) do
        nil ->
          {entity_pos, event_pos}

        axes ->
          {Map.put(entity_pos, "custom", custom(refs, dims, axes)),
           Map.put(event_pos, "custom", custom(Enum.map(events, & &1.event_id), dims, axes))}
      end

    custom_axes = parse_axes(opts[:axes], semantic)

    # Which points the filters leave. Built from the WHOLE record, a filtered
    # point is drawn dimmed rather than removed: a scene that loses points on
    # every toggle is a different picture each time, and the reader has to find
    # their place again. `nil` means nothing is filtered — everything reads.
    read = read_set(opts[:read])
    read_refs = read_refs(read, events, refs)

    entity_nodes =
      for ref <- refs do
        entity = Map.fetch!(entities, ref)

        node("entity", ref, entity.label, entity_pos)
        |> Map.merge(%{
          entity_kind: entity.kind,
          read: read_refs == nil or MapSet.member?(read_refs, ref)
        })
      end

    event_nodes =
      for event <- events do
        node("event", event.event_id, Event.title(event), event_pos)
        |> Map.merge(%{
          truth: event.truth_state,
          time: Map.fetch!(times, event.event_id),
          in_slice: in_slice?(Map.fetch!(times, event.event_id), moment),
          read: read == nil or MapSet.member?(read, event.event_id)
        })
      end

    nodes = entity_nodes ++ event_nodes

    %{
      nodes: nodes,
      # The frame each layout draws its 2D space in: a box with a centre and a
      # size, flat along whichever axis the layout does not use. They are all the
      # same box at different proportions, so the client can MORPH one into the
      # next — cube to square to the timeline's side-on plane — and the axes
      # travel with the points. `moment`'s is the one that moves: it IS the
      # selected instant.
      frames: %{
        "space" => %{center: [0.0, 0.0, 0.0], size: [2.0, 2.0, 2.0]},
        "timeline" => %{center: [0.0, 0.0, 0.0], size: [0.0, 2.0, 2.0]},
        "moment" => %{center: [0.0, 0.0, Float.round(ahead(moment), 4)], size: [2.0, 2.0, 0.0]},
        "map" => %{center: [0.0, 0.0, 0.0], size: [2.0, 2.0, 0.0]},
        "graph" => %{center: [0.0, 0.0, @base], size: [2.0, 2.0, 0.0]},
        # Flat along whichever axes the reader folded away.
        "custom" => %{
          center: [0.0, 0.0, 0.0],
          size: Enum.map(custom_axes || ~w(time time time), &if(&1 == "none", do: 0.0, else: 2.0))
        }
      },
      # The ground under the `map` layout, for laying tiles on it.
      map: map_view(entities),
      # The instants z = -1 and z = 1 stand for, so a client can rule the time
      # axis with real years and months.
      span: domain,
      links: relationship_links(relationships, refs) ++ touch_links(events, touched),
      shortfall:
        Map.new(Enum.map(@layouts, & &1.id) ++ if(custom_axes, do: ["custom"], else: []), fn id ->
          unplaced = Enum.reject(nodes, & &1.placed[id])

          {id,
           %{
             entities: Enum.count(unplaced, &(&1.kind == "entity")),
             events: Enum.count(unplaced, &(&1.kind == "event"))
           }}
        end)
    }
  end

  # ── dimensions: one value per point, per thing an axis can carry ─────────
  # -1..1, or nil where the point does not have it. An event takes a spatial or
  # categorical dimension from the entities it touches (their mean); an entity
  # takes `time` from its first mention. Built on the same helpers the presets
  # use, so `lng`/`lat`/`time` by hand lands where the map puts things (minus the
  # map's fan, which is an arrangement of the preset, not a dimension).

  defp dimension_values(events, entities, refs, touched, times, columns, semantic, scores) do
    map = map_entities(entities)
    semantic_ids = Enum.map(semantic, & &1.id)

    sources =
      events |> Enum.map(& &1.source_id) |> Enum.uniq() |> Enum.sort() |> spread() |> Map.new()

    truths = Event.truth_states() |> spread() |> Map.new()

    stacks =
      events |> time_events(times) |> Map.new(fn {id, {[_, y, _], _}} -> {id, y * 2 - 1} end)

    first_seen =
      Map.new(refs, fn ref ->
        {ref,
         events
         |> Enum.filter(&(ref in Map.fetch!(touched, &1.event_id)))
         |> Enum.map(&Map.fetch!(times, &1.event_id))
         |> Enum.min(fn -> nil end)}
      end)

    axis = fn positions, index ->
      Map.new(positions, fn
        {ref, {xyz, true}} -> {ref, Enum.at(xyz, index)}
        {ref, {_xyz, false}} -> {ref, nil}
      end)
    end

    of_entities = %{
      "lng" => axis.(map, 0),
      "lat" => axis.(map, 1),
      "entity" => columns
    }

    # An event's own reading on each semantic axis; nil until it has been scored.
    semantic_of = fn event_id ->
      Map.new(semantic_ids, &{&1, get_in(scores, [event_id, &1])})
    end

    entity_dims =
      Map.new(refs, fn ref ->
        entity = Map.fetch!(entities, ref)

        # An entity reads as the events that touch it do, on average.
        touching = for e <- events, ref in Map.fetch!(touched, e.event_id), do: e.event_id

        of_events =
          Map.new(semantic_ids, fn id ->
            values = for e <- touching, v = get_in(scores, [e, id]), is_number(v), do: v
            {id, if(values == [], do: nil, else: Enum.sum(values) / length(values))}
          end)

        {ref,
         Map.merge(Map.new(of_entities, fn {dim, by_ref} -> {dim, by_ref[ref]} end), %{
           "time" => first_seen[ref] && z(first_seen[ref]),
           "stack" => -1.0,
           "source" => nil,
           "truth" => truths[entity.truth_state],
           "none" => 0.0
         })
         |> Map.merge(of_events)}
      end)

    event_dims =
      Map.new(events, fn event ->
        touching = Map.fetch!(touched, event.event_id)

        from_entities =
          Map.new(of_entities, fn {dim, by_ref} ->
            values = for ref <- touching, value = by_ref[ref], is_number(value), do: value
            {dim, if(values == [], do: nil, else: Enum.sum(values) / length(values))}
          end)

        {event.event_id,
         Map.merge(from_entities, %{
           "time" => z(Map.fetch!(times, event.event_id)),
           "stack" => stacks[event.event_id],
           "source" => sources[event.source_id],
           "truth" => truths[event.truth_state],
           "none" => 0.0
         })
         |> Map.merge(semantic_of.(event.event_id))}
      end)

    Map.merge(entity_dims, event_dims)
  end

  defp custom(ids, dims, axes) do
    Map.new(ids, fn id ->
      values = Enum.map(axes, &get_in(dims, [id, &1]))

      if Enum.all?(values, &is_number/1),
        do: {id, placed(values)},
        # On the shelf along the axis it has no value for; where it belongs on the others.
        else: {id, shelved(Enum.map(values, &(&1 || -@shelf)))}
    end)
  end

  # Sets every placed point's z, for a layout that lies in one plane.
  defp flatten(positions, z) do
    Map.new(positions, fn
      {id, {[x, y, _z], true}} -> {id, placed([x, y, z])}
      {id, {[x, y, _z], false}} -> {id, shelved([x, y, z])}
    end)
  end

  # ── shared ───────────────────────────────────────────────────────────────

  defp read_set(nil), do: nil
  defp read_set(%MapSet{} = set), do: set
  defp read_set(events) when is_list(events), do: MapSet.new(events, & &1.event_id)

  # An entity reads when any activity that touches it does. An entity nothing
  # in view mentions is still drawn, dimmed, in the place it always had.
  defp read_refs(nil, _events, _refs), do: nil

  defp read_refs(read, events, refs) do
    allowed = MapSet.new(refs)

    events
    |> Enum.filter(&MapSet.member?(read, &1.event_id))
    |> Enum.flat_map(&touches/1)
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> MapSet.new()
  end

  defp node(kind, id, label, positions) do
    per_layout = Map.new(positions, fn {layout, by_id} -> {layout, Map.fetch!(by_id, id)} end)

    %{
      id: id,
      kind: kind,
      label: label,
      pos: Map.new(per_layout, fn {layout, {xyz, _placed?}} -> {layout, xyz} end),
      placed: Map.new(per_layout, fn {layout, {_xyz, placed?}} -> {layout, placed?} end)
    }
  end

  defp placed(xyz), do: {round3(xyz), true}
  defp shelved(xyz), do: {round3(xyz), false}
  # `+ 0.0` turns a negative zero into zero: -0.0 is a float the JSON and the
  # tests would both have to special-case, for no meaning.
  defp round3(xyz), do: Enum.map(xyz, &(Float.round(&1 * 1.0, 4) + 0.0))

  # An event touches what it affects and what it relates.
  defp touches(event) do
    related =
      case Event.relationship(event) do
        %{subject: subject, object: object} -> [subject, object]
        nil -> []
      end

    Enum.uniq(Event.affected_refs(event) ++ related)
  end

  # When, as a 0..1 fraction of the span in view. One instant has no extent, so
  # it sits in the middle rather than dividing by zero.
  defp times([], _domain), do: %{}

  defp times(events, %{from: first, to: last}) do
    Map.new(events, fn event ->
      ms = DateTime.to_unix(Event.effective_time(event), :millisecond)
      {event.event_id, if(last == first, do: 0.5, else: (ms - first) / (last - first))}
    end)
  end

  # A caller's domain is used only if it actually contains the events: one that
  # did not would put points outside -1..1, off the axis it claims to describe.
  defp time_domain(events, %{from: from, to: to} = given)
       when is_integer(from) and is_integer(to) do
    case span(events) do
      nil -> given
      %{from: first, to: last} -> %{from: min(from, first), to: max(to, last)}
    end
  end

  defp time_domain(events, _none), do: span(events)

  defp centroid([]), do: nil

  defp centroid(points) do
    n = length(points)
    points |> Enum.zip_with(&(Enum.sum(&1) / n))
  end

  # Stacks points that land on (nearly) the same x: returns `{id, x, slot}` with
  # slot 0, 1, 2… in the order given, so simultaneity reads as a column.
  defp stack(ids_with_x, within \\ 0.02) do
    {placed, _} =
      Enum.map_reduce(ids_with_x, [], fn {id, x}, seen ->
        slot = Enum.count(seen, &(abs(&1 - x) < within))
        {{id, x, slot}, [x | seen]}
      end)

    placed
  end

  # First and last moment in view, as Unix milliseconds; nil with no events.
  defp span([]), do: nil

  defp span(events) do
    {from, to} =
      events
      |> Enum.map(&DateTime.to_unix(Event.effective_time(&1), :millisecond))
      |> Enum.min_max()

    %{from: from, to: to}
  end

  # When, as a z coordinate: the span in view runs -1..1, earlier to later.
  defp z(t), do: t * 2 - 1

  # The same axis, read the way a moment is stood in: the past is behind you —
  # NEAR the viewer — and the future lies ahead, FAR. `moment` runs time into the
  # screen; the layouts that stand things on a back plane (map, graph) run it out
  # of the screen toward you, because there events rise off that plane. Both are
  # time on z; the direction is the layout's, and the axes bar says which.
  defp ahead(t), do: -z(t)

  # ── moment: a slice ACROSS time ──────────────────────────────────────────

  # The instant the slice is cut at: the chosen event's, else the latest.
  defp moment_time(_events, times, id) when is_map_key(times, id), do: Map.fetch!(times, id)
  defp moment_time([], _times, _id), do: 0.5
  defp moment_time(_events, times, _id), do: times |> Map.values() |> Enum.max()

  defp in_slice?(t, moment), do: abs(t - moment) <= @thickness

  # Entities are the columns of the slice, evenly along x.
  defp moment_columns(refs), do: refs |> spread() |> Map.new(fn {ref, x} -> {ref, x * 0.92} end)

  # An event stands over the entities it touches (x), stacked with whatever else
  # shares its column and its instant (y), at its own time (z). The slice does
  # not move the events: it is a plane set among them.
  defp moment_events(events, touched, times, columns) do
    {placed, _} =
      Enum.map_reduce(events, [], fn event, seen ->
        t = Map.fetch!(times, event.event_id)
        anchors = for ref <- Map.fetch!(touched, event.event_id), do: Map.fetch!(columns, ref)
        x = if anchors == [], do: 0.0, else: Enum.sum(anchors) / length(anchors)

        slot =
          Enum.count(seen, fn {sx, st} -> abs(sx - x) < 0.06 and abs(st - t) <= @thickness end)

        {{event.event_id, placed([x, -0.62 + slot * 0.13, ahead(t)])}, [{x, t} | seen]}
      end)

    Map.new(placed)
  end

  # ── timeline: ALONG time, folded onto the plane x = 0 ────────────────────

  defp time_events(events, times) do
    events
    |> Enum.map(&{&1.event_id, z(Map.fetch!(times, &1.event_id))})
    |> stack()
    |> Map.new(fn {id, when_z, slot} -> {id, placed([0.0, 0.08 + slot * 0.1, when_z])} end)
  end

  defp time_entities(refs, events, touched, times) do
    first_mention =
      Map.new(refs, fn ref ->
        first =
          events
          |> Enum.filter(&(ref in Map.fetch!(touched, &1.event_id)))
          |> Enum.map(&Map.fetch!(times, &1.event_id))
          |> Enum.min(fn -> 0.5 end)

        {ref, z(first)}
      end)

    refs
    |> Enum.sort_by(&{Map.fetch!(first_mention, &1), &1})
    |> Enum.map(&{&1, Map.fetch!(first_mention, &1)})
    |> stack()
    |> Map.new(fn {ref, when_z, slot} -> {ref, placed([0.0, -0.22 - slot * 0.12, when_z])} end)
  end

  # ── map: x is longitude, y is latitude, in Web Mercator ─────────────────
  # The projection every slippy map's tiles are cut in, so the client can lay real
  # tiles on this plane and have a pin land on its street. One scale serves both
  # axes (the larger span sets it): stretching x and y independently, as a chart
  # would, distorts the ground and no tile would fit it.

  @doc """
  Web Mercator "world" coordinates for a latitude and longitude: both 0..1, x
  eastward from the antimeridian, y SOUTHWARD from ~85°N (the tile convention).
  """
  def mercator(lat, lng) do
    phi = lat * :math.pi() / 180
    x = (lng + 180) / 360
    y = (1 - :math.log(:math.tan(phi) + 1 / :math.cos(phi)) / :math.pi()) / 2
    {x, y}
  end

  # Half the side of the square of ground shown, in world units, when there is
  # only one place (or several at one spot) and so no span to take it from:
  # about 1.5 km at mid-latitudes.
  @lone_half 0.00002
  # Breathing room round the outermost places.
  @map_margin 1.15

  @doc """
  The square of ground the `map` layout shows, as `%{cx:, cy:, half:}` in Web
  Mercator world units — or nil when no entity has a location. The layout's
  x and y run -1..1 across it, so a client can work out which tiles cover it.
  """
  def map_view(entities) do
    located =
      for {_ref, entity} <- entities, {lat, lng} <- [Geo.coords(entity)], do: mercator(lat, lng)

    case located do
      [] ->
        nil

      points ->
        {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
        {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
        half = max(max_x - min_x, max_y - min_y) / 2 * @map_margin

        %{
          cx: (min_x + max_x) / 2,
          cy: (min_y + max_y) / 2,
          half: if(half > 0, do: half, else: @lone_half)
        }
    end
  end

  defp map_entities(entities) do
    view = map_view(entities)

    {located, unlocated} =
      entities
      |> Enum.map(fn {ref, entity} -> {ref, Geo.coords(entity)} end)
      |> Enum.split_with(fn {_ref, coords} -> coords != nil end)

    placed =
      Map.new(located, fn {ref, {lat, lng}} ->
        {wx, wy} = mercator(lat, lng)
        # World y runs southward; here north is up.
        {ref, placed([(wx - view.cx) / view.half, -(wy - view.cy) / view.half, @base])}
      end)

    shelf =
      unlocated
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
      |> spread()
      |> Map.new(fn {ref, x} -> {ref, shelved([x, -@shelf, @base])} end)

    Map.merge(placed, shelf)
  end

  # Evenly along a line, -1..1.
  defp spread([]), do: []
  defp spread([only]), do: [{only, 0.0}]

  defp spread(ids) do
    step = 2 / (length(ids) - 1)
    ids |> Enum.with_index() |> Enum.map(fn {id, i} -> {id, -1 + i * step} end)
  end

  # ── events in front of a plane of entities ───────────────────────────────
  # An event takes the x and y of the PLACED entities it touches (their centre)
  # and the z of when it happened. With nothing placed to stand over, it goes to
  # the shelf below the plane — still at its own time — rather than to an
  # invented spot.
  #
  # `fan: true` is for a plane read from directly above (the map). There, events
  # over one place would hide each other and the place itself, because time runs
  # straight at the viewer. So they fan out round the place in a small spiral, in
  # the order they happened: still plainly AT that place, and countable. It is an
  # arrangement of marks round a true position, not a claim about where.
  defp over(events, touched, times, entity_positions, opts \\ []) do
    fan? = Keyword.get(opts, :fan, false)

    {positions, _seen} =
      events
      |> Enum.sort_by(&Map.fetch!(times, &1.event_id))
      |> Enum.map_reduce(%{}, fn event, seen ->
        when_z = z(Map.fetch!(times, event.event_id))

        anchors =
          for ref <- Map.fetch!(touched, event.event_id),
              {xyz, true} <- [Map.fetch!(entity_positions, ref)],
              do: xyz

        case centroid(anchors) do
          nil ->
            {{event.event_id, shelved([when_z, -@shelf, when_z])}, seen}

          [x, y, _z] ->
            spot = {Float.round(x, 3), Float.round(y, 3)}
            k = Map.get(seen, spot, 0)
            {dx, dy} = if fan?, do: spiral(k), else: {0.0, 0.0}

            {{event.event_id, placed([x + dx, y + dy, when_z])}, Map.put(seen, spot, k + 1)}
        end
      end)

    Map.new(positions)
  end

  # The k-th seat round a place: a sunflower spiral, so any number of events
  # spread evenly without two landing on each other. The first sits just off the
  # place, so the place's own mark stays visible beneath.
  @golden_angle 2.399963229728653
  @fan_reach 0.045

  defp spiral(k) do
    r = @fan_reach * :math.sqrt(k + 1)
    {r * :math.cos(k * @golden_angle), r * :math.sin(k * @golden_angle)}
  end

  # ── links ────────────────────────────────────────────────────────────────

  defp relationship_links(relationships, refs) do
    for rel <- relationships, rel.subject in refs, rel.object in refs do
      %{
        from: "entity:#{rel.subject}",
        to: "entity:#{rel.object}",
        kind: "relationship",
        truth: rel.truth_state
      }
    end
  end

  defp touch_links(events, touched) do
    for event <- events, ref <- Map.fetch!(touched, event.event_id) do
      %{
        from: "event:#{event.event_id}",
        to: "entity:#{ref}",
        kind: "touches",
        truth: event.truth_state
      }
    end
  end
end
