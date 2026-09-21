defmodule IndivisualWeb.AtlasProjectionMenuTest do
  @moduledoc """
  There is no projection menu. The four projections were all on screen at once —
  activity is the list, topology the graph, entity context the reader under a
  focus, provenance the truth filter — so the row that chose between them is
  unmounted, there is one URL, and each panel carries its projection's question.

  The one thing a projection changed that nothing else covered — Topology dropped
  unconnected entities — was a visible toggle on the graph. The graph is now
  unmounted too (`AtlasComponents.graph/1`), so that toggle is on no page: the
  host still handles `toggle_connected` and `?connected=1`, and the entity list
  under Spacetime reads the same read model the graph drew.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Projections
  alias Indivisual.Atlas.Topology
  alias IndivisualWeb.AtlasComponents

  # The entity list reads the same read model the graph drew.
  defp entities_listed(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#atlas-entity-list > li")
    |> Enum.count()
  end

  defp graph(assigns) do
    events = Feed.events()

    render_component(
      &AtlasComponents.graph/1,
      Map.merge(%{read_model: Projections.materialize("topology", events)}, assigns)
    )
  end

  defp count(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()

  describe "no mode switch" do
    test "the row is off the page, and registered as unmounted", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-projection-nav")
      refute has_element?(view, ~s(input[name="projection"]))
      assert :projection_nav in AtlasComponents.unmounted()
    end

    test "the URL has no projection in it, whatever the reader does", %{conn: conn} do
      [first | _] = Feed.events()
      {:ok, view, _} = live(conn, ~p"/atlas")

      render_hook(view, "select_event", %{"id" => first.event_id})
      refute assert_patch(view) =~ "projection"

      # The graph's toggle is unmounted; this is the event it pushes.
      render_hook(view, "toggle_connected", %{})
      refute assert_patch(view) =~ "projection"
    end

    test "each panel carries the question its projection answers", %{conn: conn} do
      ref = Feed.events() |> Topology.relationships() |> hd() |> Map.fetch!(:subject)
      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      # Topology's question sat on the graph, which is unmounted: it is asserted
      # on the component below, and is on no page until the graph (or Spacetime's
      # graph layout) carries it again.
      assert view |> element("#atlas-entity-context-question") |> render() =~
               Phoenix.HTML.html_escape(Projections.get("entity").question)
               |> Phoenix.HTML.safe_to_string(),
             "entity's question should be on its panel"
    end

    test "a panel whose controls already say what it does carries no sentence", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-activity-truth-question")
      refute has_element?(view, "#atlas-activity-question")

      # The badges name the truth states; a sentence listing them says it twice.
      refute html =~ "observed directly, reported by a source"
      refute html =~ "What changed, in source order"

      # The controls themselves are untouched.
      assert has_element?(view, "#atlas-activity-truth-observed")
      assert has_element?(view, "#atlas-activity-title")
    end
  end

  describe "connected only, in the host" do
    test "the graph and its toggle are off the page", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-graph")
      refute has_element?(view, "#atlas-graph-connected")
      assert :graph in AtlasComponents.unmounted()
    end

    test "off by default: every entity in view is listed", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert entities_listed(view) == map_size(Topology.entities(Feed.events()))
    end

    test "on: unconnected entities go", %{conn: conn} do
      connected = map_size(Projections.materialize("topology", Feed.events()).entities)
      {:ok, view, _} = live(conn, ~p"/atlas")

      render_hook(view, "toggle_connected", %{})

      assert assert_patch(view) =~ "connected=1"
      assert entities_listed(view) == connected
    end

    test "it round-trips through the URL, and off leaves the URL clean", %{conn: conn} do
      connected = map_size(Projections.materialize("topology", Feed.events()).entities)
      {:ok, view, _} = live(conn, ~p"/atlas?connected=1")
      assert entities_listed(view) == connected

      render_hook(view, "toggle_connected", %{})
      refute assert_patch(view) =~ "connected"
    end

    test "the read model is the same window as the list, not one of its own", %{conn: conn} do
      [first | _] = events = Feed.events()
      {:ok, view, _} = live(conn, ~p"/atlas?connected=1&event=#{first.event_id}")

      # Selecting the first event used to narrow the graph to that one event.
      assert entities_listed(view) ==
               map_size(Projections.materialize("topology", events).entities)
    end
  end

  describe "the unmounted graph still renders" do
    test "one node per entity, and it carries topology's question" do
      html = graph(%{})
      entities = map_size(Projections.materialize("topology", Feed.events()).entities)

      assert count(html, "#atlas-svg-entities > *") == entities

      assert html =~
               Projections.get("topology").question
               |> Phoenix.HTML.html_escape()
               |> Phoenix.HTML.safe_to_string()
    end

    test "off, the toggle is unchecked and reports nothing hidden" do
      html = graph(%{connected_only?: false})

      assert count(html, ~s(#atlas-graph-connected[aria-checked="false"])) == 1
      assert count(html, "#atlas-graph-hidden") == 0
      assert html =~ ~s(phx-click="toggle_connected")
    end

    test "on, the toggle says how many it removed" do
      html = graph(%{connected_only?: true, graph_hidden: 3})

      assert count(html, ~s(#atlas-graph-connected[aria-checked="true"])) == 1
      assert html =~ "3 hidden"
    end

    test "it admits its positions mean nothing, and has no z to speak of" do
      html = graph(%{})

      [axes] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-graph-axes")
        |> Enum.map(&LazyHTML.to_html/1)

      assert axes =~ "position means nothing"
      refute axes =~ ">z<"
    end
  end

  describe "the unmounted row still renders" do
    test "one radio per projection, the active one checked" do
      html =
        render_component(&AtlasComponents.projection_nav/1,
          projections: Projections.list(),
          projection: "topology"
        )

      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(~s(input[type="radio"][name="projection"])) |> Enum.count() ==
               4

      assert doc |> LazyHTML.query(~s(input[value="topology"][checked])) |> Enum.count() == 1
      assert html =~ ~s(phx-change="select_projection")
    end
  end
end
