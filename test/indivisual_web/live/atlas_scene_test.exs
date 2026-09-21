defmodule IndivisualWeb.AtlasSceneTest do
  @moduledoc """
  Spacetime: one three.js scene whose layouts are the timeline, a moment, the map
  and the graph — rendered twice, as the sticky timeline strip (along time) and
  as the panel in the canvas column (which cuts across it). The canvas is the client's; what the server owes it is the right
  points, the layout in the URL, and the truth about what a layout cannot place.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Scene
  alias Indivisual.Atlas.Topology

  defp events, do: Feed.events(Feed, [])
  defp event?(id), do: Enum.any?(events(), &(&1.event_id == id))

  defp payload(view) do
    [json] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#atlas-scene")
      |> LazyHTML.attribute("data-scene")

    Jason.decode!(json)
  end

  defp layout_attr(view) do
    [layout] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#atlas-scene")
      |> LazyHTML.attribute("data-layout")

    layout
  end

  test "it is the view in the canvas column, fed through attributes", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-canvas #atlas-scene-wrap")
    assert has_element?(view, ~s(#atlas-scene[phx-hook$="Scene3D"][phx-update="ignore"]))
    # The three it folds in — space, map, graph — are unmounted; it names the column.
    refute has_element?(view, "#atlas-scatter")
    refute has_element?(view, "#atlas-map")
    refute has_element?(view, "#atlas-graph")

    assert has_element?(
             view,
             ~s(#atlas-canvas[aria-labelledby="atlas-scene-title"] #atlas-scene-title)
           )
  end

  test "what the scene cannot offer a keyboard, the entity list under it does", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(
             view,
             ~s(#atlas-canvas #atlas-entity-list button[phx-click="focus_entity"])
           )
  end

  test "every activity and every entity in view is a point", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")
    events = events()
    %{"nodes" => nodes, "links" => links} = payload(view)

    assert Enum.count(nodes, &(&1["kind"] == "event")) == length(events)
    assert Enum.count(nodes, &(&1["kind"] == "entity")) == map_size(Topology.entities(events))
    assert links != []

    for node <- nodes, %{id: layout} <- Scene.layouts() do
      assert [_, _, _] = node["pos"][layout]
    end
  end

  test "points carry what a reader needs to recognise them", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")
    %{"nodes" => nodes} = payload(view)

    event = Enum.find(nodes, &(&1["kind"] == "event"))
    assert event["color"] =~ ~r/^#[0-9a-f]{6}$/
    assert event["date"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
    assert is_binary(event["truth"])

    assert Enum.count(nodes, & &1["selected"]) == 1
  end

  describe "layouts" do
    test "the switch spans the scene it switches" do
      # These are the ways of seeing the whole stage, so they take its whole
      # width and share it evenly rather than huddling beside the title.
      css = File.read!("assets/css/app.css")

      [group] = Regex.run(~r/\.atlas-scene__head \.atlas-range__mode \{[^}]*\}/, css)
      assert group =~ "flex: 1 0 100%"

      [button] = Regex.run(~r/\.atlas-scene__head \.atlas-range__mode button \{[^}]*\}/, css)
      assert button =~ "flex: 1"
    end

    test "opens on the default, with one radio per layout", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert layout_attr(view) == Scene.default_layout()

      for %{id: id} <- Scene.layouts() do
        assert has_element?(view, ~s(#atlas-scene-layout-#{id}[role="radio"]))
      end

      assert has_element?(
               view,
               ~s(#atlas-scene-layout-#{Scene.default_layout()}[aria-checked="true"])
             )
    end

    test "switching is a transformation of the same points, and rides the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      before = payload(view)

      view |> element("#atlas-scene-layout-map") |> render_click()

      assert assert_patch(view) =~ "scene=map"
      assert layout_attr(view) == "map"
      assert has_element?(view, ~s(#atlas-scene-layout-map[aria-checked="true"]))
      # Same points, same positions on offer: only the chosen layout changed —
      # and with longitude and latitude on x and y, there is now a map under it.
      assert Map.delete(payload(view), "ground") == Map.delete(before, "ground")
      assert payload(view)["ground"] == true
      assert before["ground"] == false
    end

    test "a shared link lands on the same slice; the default stays out of the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=graph")
      assert layout_attr(view) == "graph"

      view |> element("#atlas-scene-layout-#{Scene.default_layout()}") |> render_click()
      refute assert_patch(view) =~ "scene="
    end

    test "an unknown layout falls back rather than breaking the page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=nope")

      assert layout_attr(view) == Scene.default_layout()
    end
  end

  describe "two takes on time, one component rendered twice" do
    defp attr(view, selector, name) do
      [value] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(selector)
        |> LazyHTML.attribute(name)

      value
    end

    defp strip(view), do: view |> attr("#atlas-timeline-scene", "data-scene") |> Jason.decode!()

    test "the sticky timeline is the same component, in its flat variant", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-timeline #atlas-timeline-scene[phx-hook$="Scene3D"]))
      assert attr(view, "#atlas-timeline-scene", "data-variant") == "strip"
      assert attr(view, "#atlas-scene", "data-variant") == "panel"
    end

    test "the panel opens ACROSS time, and offers ALONG time as its own mode", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-scene-layout-moment[aria-checked="true"]))
      assert has_element?(view, ~s(#atlas-scene-layout-timeline[aria-checked="false"]))

      view |> element("#atlas-scene-layout-timeline") |> render_click()

      assert assert_patch(view) =~ "scene=timeline"
      assert layout_attr(view) == "timeline"
      # The strip above is unaffected: it is always the timeline.
      assert attr(view, "#atlas-timeline-scene", "data-variant") == "strip"
    end

    test "the panel's Timeline layout lives in the same scene as the others", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=moment")
      before = payload(view)

      view |> element("#atlas-scene-layout-timeline") |> render_click()
      assert_patch(view)

      # Same stage, same points: only the layout changed, so they can travel.
      assert attr(view, "#atlas-scene", "data-variant") == "panel"
      assert layout_attr(view) == "timeline"
      assert payload(view) == before
    end

    test "the flat layouts say they do not turn; the volumes say they orbit", %{conn: conn} do
      for {layout, says} <- [{"map", "does not turn"}, {"timeline", "does not turn"}] do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: layout]}")
        assert view |> element("#atlas-scene-caption") |> render() =~ says, layout
      end

      for layout <- ~w(moment graph space) do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: layout]}")
        assert view |> element("#atlas-scene-caption") |> render() =~ "Drag to orbit", layout
      end
    end

    test "the scene's time axis is the whole record's, whatever is filtered",
         %{conn: conn} do
      times =
        Enum.map(
          events(),
          &DateTime.to_unix(Indivisual.Atlas.Event.effective_time(&1), :millisecond)
        )

      record = %{"from" => Enum.min(times), "to" => Enum.max(times)}

      for path <- [
            ~p"/atlas?scene=timeline",
            ~p"/atlas?scene=timeline&from=1&to=3",
            ~p"/atlas?scene=timeline&truth=none"
          ] do
        {:ok, view, _} = live(conn, path)

        assert payload(view)["span"] == record, path
      end
    end

    test "narrowing the range leaves each remaining point where it was", %{conn: conn} do
      z = fn view ->
        Map.new(payload(view)["nodes"], &{&1["id"], Enum.at(&1["pos"]["timeline"], 2)})
      end

      {:ok, all, _} = live(conn, ~p"/atlas?scene=timeline")
      {:ok, some, _} = live(conn, ~p"/atlas?scene=timeline&from=1&to=3")
      before = z.(all)

      for {id, at} <- z.(some), event?(id) do
        assert_in_delta at, Map.fetch!(before, id), 0.0001
      end
    end

    test "the two modes put the same events in different places", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = Enum.filter(payload(view)["nodes"], &(&1["kind"] == "event"))

      assert Enum.any?(events, &(&1["pos"]["timeline"] != &1["pos"]["moment"]))
      # Both keep time on z. The timeline folds x away; the moment spreads it.
      assert Enum.all?(events, &(hd(&1["pos"]["timeline"]) == 0.0))
      assert Enum.any?(events, &(hd(&1["pos"]["moment"]) != 0.0))

      # The same instant on z in both — read toward you in one, away in the other.
      for e <- events do
        assert_in_delta Enum.at(e["pos"]["timeline"], 2), -Enum.at(e["pos"]["moment"], 2), 0.001
      end
    end

    test "the moment follows the selection", %{conn: conn} do
      events = events()
      first = List.first(events).event_id
      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: first]}")

      in_slice = for n <- payload(view)["nodes"], n["in_slice"], do: n["id"]
      assert first in in_slice
      refute List.last(events).event_id in in_slice
    end

    test "?band=dom swaps the strip for DOM marks, and survives in the shared URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?band=dom")

      refute has_element?(view, "#atlas-timeline-scene")
      assert has_element?(view, ".atlas-marks__mark")

      view |> element("#atlas-scene-layout-map") |> render_click()
      assert assert_patch(view) =~ "band=dom"
    end
  end

  describe "the timeline rectangle" do
    test "runs from the first to the last activity of the whole record", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      times =
        Enum.map(
          events,
          &DateTime.to_unix(Indivisual.Atlas.Event.effective_time(&1), :millisecond)
        )

      assert strip(view)["extent"] == %{"from" => Enum.min(times), "to" => Enum.max(times)}
    end

    test "every activity is on it, whatever the filters; they ink or hollow it", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")
      nodes = strip(view)["nodes"]

      assert length(nodes) == length(events)
      assert Enum.count(nodes, & &1["read"]) == 3
      assert Enum.count(nodes, & &1["selected"]) == 1
    end

    test "it focuses on the span of what the filters leave", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      read = for n <- strip(view)["nodes"], n["read"], do: n["at"]
      assert strip(view)["focus"] == %{"from" => Enum.min(read), "to" => Enum.max(read)}
      assert attr(view, "#atlas-timeline-scene", "data-layout") == "focus"
      assert length(events) > 3
    end

    test "with nothing filtered out there is nothing to focus on, and no switch", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert strip(view)["focus"] == nil
      refute has_element?(view, "#atlas-timeline-scene-layouts")
    end

    test "All spans the record again, and rides the URL", %{conn: conn} do
      # The switch sits between the two ends it chooses between, in the row
      # that names them, rather than in the band's own head.
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      view |> form("#atlas-timeline-fit", %{"layout" => "all"}) |> render_change()

      assert assert_patch(view) =~ "fit=all"
      assert attr(view, "#atlas-timeline-scene", "data-layout") == "all"

      view |> form("#atlas-timeline-fit", %{"layout" => "focus"}) |> render_change()
      refute assert_patch(view) =~ "fit="
    end

    test "the switch is centred between earlier and later", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas?from=1&to=3")

      assert has_element?(view, "#atlas-timeline-beyond #atlas-timeline-fit")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end

      assert at.("atlas-timeline-beyond-start") < at.("atlas-timeline-fit")
      assert at.("atlas-timeline-fit") < at.("atlas-timeline-beyond-end")
    end

    test "with nothing filtered the switch stays, disabled", %{conn: conn} do
      # Both spans are the same record then, so the choice is moot — but a
      # switch that comes and goes moves the row's two ends under the cursor.
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-timeline-fit")
      assert has_element?(view, "#atlas-timeline-fit input[disabled]")
      assert has_element?(view, ".atlas-fit.is-moot")
    end

    test "the row keeps its three parts either way", %{conn: conn} do
      # Nothing may move under the cursor as the filters change.
      for path <- [~p"/atlas", ~p"/atlas?from=1&to=3"] do
        {:ok, view, _} = live(conn, path)

        assert has_element?(view, "#atlas-timeline-beyond-start"), path
        assert has_element?(view, "#atlas-timeline-fit"), path
        assert has_element?(view, "#atlas-timeline-beyond-end"), path
      end
    end

    test "filtering enables it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      assert has_element?(view, "#atlas-timeline-fit")
      refute has_element?(view, "#atlas-timeline-fit input[disabled]")
      refute has_element?(view, ".atlas-fit.is-moot")
    end

    test "an emptied view keeps the whole record on the band, all hollow", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none")

      assert Enum.all?(strip(view)["nodes"], &(&1["read"] == false))
      assert strip(view)["focus"] == nil
    end

    test "the ends say how much of the record lies beyond the view", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?from=13&to=14")

      beyond = strip(view)["beyond"]
      assert beyond["earlier"] > 0
      assert beyond["later"] > 0
      assert beyond["earlier"] + beyond["later"] <= length(events) - 2

      assert view |> element("#atlas-timeline-beyond-start") |> render() =~
               "#{beyond["earlier"]} earlier"

      assert view |> element("#atlas-timeline-beyond-end") |> render() =~
               "#{beyond["later"]} later"
    end

    test "an end cap lets go of the date range on its side", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=13&to=14")

      view |> element("button#atlas-timeline-beyond-start") |> render_click()

      path = assert_patch(view)
      refute path =~ "from="
      assert path =~ "to=14"
      assert strip(view)["beyond"]["earlier"] == 0
    end

    test "what other filters hold back is counted, but is not the range's to release", %{
      conn: conn
    } do
      state = events() |> List.last() |> Map.fetch!(:truth_state)
      {:ok, view, _} = live(conn, ~p"/atlas?#{[truth: state]}")

      if strip(view)["beyond"]["earlier"] > 0 do
        refute has_element?(view, "button#atlas-timeline-beyond-start")
        assert view |> element("#atlas-timeline-beyond-start") |> render() =~ "filtered out"
      end
    end

    test "at the ends of the record the caps say coverage stops, not that time does", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas")

      start = view |> element("#atlas-timeline-beyond-start.is-edge") |> render()
      finish = view |> element("#atlas-timeline-beyond-end.is-edge") |> render()

      assert start =~ "the record starts here"
      assert start =~ "would extend it"
      assert finish =~ "the record ends here"
    end

    test "the DOM band is only the fallback now", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      refute has_element?(view, "#atlas-timeline-marks")
    end
  end

  describe "the axes bar: x, y and z along the stage's bottom border" do
    defp axis(view, letter) do
      view |> element("#atlas-scene-axis-#{letter}") |> render()
    end

    defp chosen(view, letter) do
      [value] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-scene-axis-#{letter}-select option[selected]")
        |> LazyHTML.attribute("value")

      value
    end

    test "it sits under the stage, beside it — never inside the hook's DOM", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, ~s(#atlas-scene-frame > #atlas-scene[phx-update="ignore"]))
      assert has_element?(view, "#atlas-scene-frame > form#atlas-scene-axes")
      refute has_element?(view, "#atlas-scene #atlas-scene-axes")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end
      assert at.("atlas-scene") < at.("atlas-scene-axes")
      # x, y, z in that order, in one bar — no rails up the sides or over the top.
      assert at.("atlas-scene-axis-x") < at.("atlas-scene-axis-y")
      assert at.("atlas-scene-axis-y") < at.("atlas-scene-axis-z")
      refute html =~ "atlas-frame__rail"
    end

    test "each axis is a dropdown of everything an axis can carry", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")

      for letter <- ~w(x y z) do
        options =
          view
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("#atlas-scene-axis-#{letter}-select option")
          |> LazyHTML.attribute("value")

        assert Enum.sort(options) == Scene.dimensions() |> Enum.map(& &1.id) |> Enum.sort()
      end
    end

    test "the dropdowns show what the layout puts on each axis", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")

      # The Map has no time axis: z is folded flat.
      assert {chosen(view, "x"), chosen(view, "y"), chosen(view, "z")} == {"lng", "lat", "none"}

      view |> element("#atlas-scene-layout-space") |> render_click()

      # Spacetime is that map with time added.
      assert {chosen(view, "x"), chosen(view, "y"), chosen(view, "z")} == {"lng", "lat", "time"}
    end

    test "beside each dropdown: where the axis runs, or what it means", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=space")

      assert axis(view, "x") =~ "west → east"
      assert axis(view, "y") =~ "south → north"
      # z is time here, so it names the span actually in view — and still says
      # what it means, in its title.
      assert axis(view, "z") =~ ~r/\d{4}-\d{2}-\d{2} → /
      assert axis(view, "z") =~ "earlier → later"
    end

    test "time is z wherever there is a time axis", %{conn: conn} do
      for layout <- ~w(timeline moment space graph) do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: layout]}")
        assert chosen(view, "z") == "time", layout
      end
    end

    test "an axis a layout folds away says so, rather than being left out", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=timeline")

      assert chosen(view, "x") == "none"
      assert has_element?(view, "#atlas-scene-axis-x.is-unused")
      assert axis(view, "x") =~ "folded flat"
    end

    test "choosing a dimension makes the layout the reader's own, in the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")

      view
      |> form("#atlas-scene-axes", %{"axes" => %{"x" => "source", "y" => "truth", "z" => "time"}})
      |> render_change()

      path = assert_patch(view)
      assert path =~ "scene=custom"
      assert path =~ "axes=source%2Ctruth%2Ctime" or path =~ "axes=source,truth,time"

      assert {chosen(view, "x"), chosen(view, "y"), chosen(view, "z")} ==
               {"source", "truth", "time"}

      assert layout_attr(view) == "custom"
      # No preset is on: the switch shows none checked.
      refute has_element?(view, ~s(#atlas-scene-layouts [aria-checked="true"]))
      assert view |> element("#atlas-scene-caption") |> render() =~ "Your own choice of axes"

      # Every point has a place in it.
      for node <- payload(view)["nodes"], do: assert([_, _, _] = node["pos"]["custom"])
    end

    test "three dimensions that ARE a preset are that preset", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=timeline")

      view
      |> form("#atlas-scene-axes", %{"axes" => %{"x" => "lng", "y" => "lat", "z" => "none"}})
      |> render_change()

      path = assert_patch(view)
      assert path =~ "scene=map"
      refute path =~ "axes="
      assert has_element?(view, ~s(#atlas-scene-layout-map[aria-checked="true"]))

      # Add the time axis, and the map has become Spacetime.
      view
      |> form("#atlas-scene-axes", %{"axes" => %{"x" => "lng", "y" => "lat", "z" => "time"}})
      |> render_change()

      assert assert_patch(view) =~ "scene=space"
    end

    test "a custom layout round-trips, and a broken one falls back", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "truth,source,time"]}")
      assert {chosen(view, "x"), chosen(view, "y")} == {"truth", "source"}

      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "nope,nope"]}")
      assert layout_attr(view) == Scene.default_layout()
    end

    test "a custom layout shelves what it cannot place, and says so", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "lng,truth,time"]}")

      # Longitude is an axis some points do not have.
      assert view |> element("#atlas-scene-shortfall") |> render() =~ "shelf"
    end

    test "time can go on another axis, and its dates go with it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "time,truth,source"]}")

      assert axis(view, "x") =~ ~r/\d{4}-\d{2}-\d{2}/
      refute axis(view, "z") =~ ~r/\d{4}-\d{2}-\d{2}/
    end

    test "the strip has no axes bar: it is a band, not a volume", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      refute has_element?(view, "#atlas-timeline-scene-axes")
    end
  end

  describe "the Graph is about semantic axes, and they are customizable" do
    alias Indivisual.Atlas.Semantics
    alias Indivisual.Semantic

    defp semantic_axis(name, negative, positive) do
      {:ok, axis} =
        Semantic.create_axis(%{
          name: name,
          negative_pole: negative,
          positive_pole: positive,
          negative_examples: ["#{negative} one", "#{negative} two"],
          positive_examples: ["#{positive} one", "#{positive} two"]
        })

      {:ok, axis} = Semantic.compute_axis_vector(axis)
      axis
    end

    test "with no axes defined, the Graph says so rather than looking broken", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=graph")

      assert view |> element("#atlas-scene-semantic") |> render() =~
               "No semantic axes are defined yet"

      assert chosen(view, "x") == "none"
    end

    test "axes computed with another embedding model are named as the reason", %{conn: conn} do
      axis = semantic_axis("Stage", "plan", "built")

      {:ok, _} =
        axis |> Ecto.Changeset.change(model: "some-other-model") |> Indivisual.Repo.update()

      {:ok, view, _} = live(conn, ~p"/atlas?scene=graph")

      note = view |> element("#atlas-scene-semantic") |> render()
      assert note =~ "none was computed with the embedding model in use"
      assert chosen(view, "x") == "none"
    end

    test "the semantic axes there are lead the Graph, and are in every dropdown", %{conn: conn} do
      stage = semantic_axis("Stage", "plan", "built")
      reach = semantic_axis("Reach", "local", "regional")

      {:ok, view, _} = live(conn, ~p"/atlas?scene=graph")

      # Axes are listed by name: Reach, then Stage.
      assert chosen(view, "x") == Semantics.dimension_id(reach)
      assert chosen(view, "y") == Semantics.dimension_id(stage)
      assert chosen(view, "z") == "time"

      assert axis(view, "x") =~ "local ↔ regional"
      assert has_element?(view, "#atlas-scene-axis-z-select option", "Stage")
    end

    test "a semantic axis can go on any axis of any mode, and rides the URL", %{conn: conn} do
      stage = semantic_axis("Stage", "plan", "built")
      id = Semantics.dimension_id(stage)

      {:ok, view, _} = live(conn, ~p"/atlas?scene=space")

      view
      |> form("#atlas-scene-axes", %{"axes" => %{"x" => "lng", "y" => "lat", "z" => id}})
      |> render_change()

      path = assert_patch(view)
      assert path =~ "scene=custom"
      assert chosen(view, "z") == id
      # Still a map underneath: x and y are longitude and latitude.
      assert payload(view)["ground"] == true
      assert view |> element("#atlas-scene-semantic") |> render() =~ "reading"
    end

    test "a link to an axis that no longer exists falls back, rather than breaking", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "sem:999999,lat,time"]}")

      assert layout_attr(view) == Scene.default_layout()
    end

    test "the other modes make no claim about meaning", %{conn: conn} do
      for layout <- ~w(space timeline moment map) do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: layout]}")
        refute has_element?(view, "#atlas-scene-semantic"), layout
      end
    end
  end

  describe "the map is a ground that goes with the axes, not with the Map mode" do
    test "any mode with longitude on x and latitude on y stands on it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: "lng,lat,truth"]}")

      assert payload(view)["ground"] == true
      assert view |> element("#atlas-scene-attribution") |> render() =~ "OpenStreetMap"
    end

    test "the two axes swapped, or only one of them, is not a map", %{conn: conn} do
      for axes <- ["lat,lng,time", "lng,truth,time"] do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: "custom", axes: axes]}")

        assert payload(view)["ground"] == false, axes
        refute has_element?(view, "#atlas-scene-attribution")
      end
    end
  end

  describe "the map layout's ground" do
    test "the client is told which square of the world to tile", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")

      assert %{"cx" => cx, "cy" => cy, "half" => half} = payload(view)["map"]
      assert cx > 0 and cx < 1 and cy > 0 and cy < 1 and half > 0
    end

    test "the tiles are credited, and only where they are shown", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")
      assert view |> element("#atlas-scene-attribution") |> render() =~ "OpenStreetMap"

      {:ok, view, _} = live(conn, ~p"/atlas?scene=graph")
      refute has_element?(view, "#atlas-scene-attribution")
    end
  end

  describe "honesty" do
    test "the map layout says what it could not place", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")

      note = view |> element("#atlas-scene-shortfall") |> render()
      assert note =~ ~r/\d+ of \d+ entities/
      assert note =~ "shelf"
    end

    test "a layout that places everything says nothing of the kind", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=moment")

      refute has_element?(view, "#atlas-scene-shortfall")
    end

    test "no mode is a placeholder any more", %{conn: conn} do
      for layout <- ~w(space timeline moment map graph) do
        {:ok, view, _} = live(conn, ~p"/atlas?#{[scene: layout]}")
        refute view |> element("#atlas-scene-caption") |> render() =~ "Placeholder"
      end
    end
  end

  describe "it reads what the filters leave" do
    test "narrowing dims points rather than removing them", %{conn: conn} do
      # A scene that loses points on every toggle is a different picture each
      # time, and the reader has to find their place again.
      {:ok, wide, _} = live(conn, ~p"/atlas")
      {:ok, narrow, _} = live(conn, ~p"/atlas?from=1&to=3")

      events = fn view -> Enum.filter(payload(view)["nodes"], &(&1["kind"] == "event")) end

      assert length(events.(narrow)) == length(events.(wide)),
             "every activity of the record stays in the scene"

      read = Enum.count(events.(narrow), & &1["read"])
      assert read == 3, "and only what the filters leave is inked"
    end

    test "an entity nothing in view mentions is dimmed, not dropped", %{conn: conn} do
      {:ok, wide, _} = live(conn, ~p"/atlas")
      {:ok, narrow, _} = live(conn, ~p"/atlas?from=1&to=3")

      entities = fn view -> Enum.filter(payload(view)["nodes"], &(&1["kind"] == "entity")) end

      assert length(entities.(narrow)) == length(entities.(wide))

      assert Enum.any?(entities.(narrow), &(not &1["read"])),
             "an entity out of view keeps the place it always had"
    end

    test "an entity focus is marked on its point", %{conn: conn} do
      ref =
        events()
        |> Topology.relationships()
        |> List.first()
        |> Map.fetch!(:subject)

      {:ok, view, _} = live(conn, ~p"/atlas?#{[entity: ref]}")

      assert [%{"id" => ^ref}] = Enum.filter(payload(view)["nodes"], & &1["focused"])
    end

    test "an emptied view keeps the record, all of it quiet", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none")

      events = Enum.filter(payload(view)["nodes"], &(&1["kind"] == "event"))

      refute events == [], "the record is still there"
      assert Enum.all?(events, &(not &1["read"])), "and none of it reads"
    end
  end

  describe "an entity is drawn as its kind, in the same state colours everywhere" do
    test "the scene is handed the page's icon set, for the kinds in it that have one", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas")
      icons = payload(view)["icons"]

      assert Map.has_key?(icons, "place")
      assert icons["place"]["d"] == IndivisualWeb.AtlasComponents.entity_icon_path("place").d
      assert icons["place"]["rule"] == "evenodd"
      refute Map.has_key?(icons, "goal"), "a kind without an icon is not sent"
    end

    test "focused is the entity open in the reader; affected is what the open record touches",
         %{conn: conn} do
      # An event that touches at least two things: focus one, and the other must
      # read as affected-but-not-focused. (Focusing an entity narrows the list to
      # events that touch it, so the event has to be one of those.)
      event = Enum.find(events(), &(length(Indivisual.Atlas.Event.affected_refs(&1)) > 1))
      [ref, other | _] = Indivisual.Atlas.Event.affected_refs(event)

      {:ok, view, _} = live(conn, ~p"/atlas?event=#{event.event_id}&entity=#{ref}")
      entities = Enum.filter(payload(view)["nodes"], &(&1["kind"] == "entity"))
      affected = entities |> Enum.filter(& &1["affected"]) |> Enum.map(& &1["id"])

      assert [%{"id" => ^ref}] = Enum.filter(entities, & &1["focused"])
      assert ref in affected
      assert other in affected
      refute Enum.find(entities, &(&1["id"] == other))["focused"]
    end
  end
end
