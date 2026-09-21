defmodule IndivisualWeb.AtlasMapTest do
  @moduledoc """
  `AtlasComponents.map/1` — the Leaflet map — is **unmounted** (see the register
  in `IndivisualWeb.AtlasComponents`), so nothing on a page would notice it
  rotting. Leaflet renders it in the browser, so the server's job is to hand over
  correct points and tell the truth about coverage. These cover that boundary:
  the data attribute, the hook, and the caption. Pin rendering is the client's.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Geo
  alias Indivisual.Atlas.Topology
  alias IndivisualWeb.AtlasComponents
  alias IndivisualWeb.AtlasLive

  defp geo, do: Geo.project(Topology.entities(Feed.events(Feed, [])))

  defp map(assigns \\ %{}) do
    render_component(&AtlasComponents.map/1, Map.merge(%{geo: geo()}, assigns))
  end

  defp points(html) do
    [json] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#atlas-map")
      |> LazyHTML.attribute("data-points")

    Jason.decode!(json)
  end

  test "it is off the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    refute has_element?(view, "#atlas-map-wrap")
  end

  test "the map container is hooked and owns its own DOM" do
    html = map()

    assert html =~ "phx-hook"

    assert html =~ ~s(phx-update="ignore"),
           "Leaflet manages this subtree; LiveView must not patch it"
  end

  test "every located entity is handed to the map" do
    assert length(points(map())) == geo().count
  end

  test "points carry real coordinates and a label" do
    trail = Enum.find(points(map()), &(&1["ref"] == "place:northern-trail"))

    assert trail["lat"] == 38.3671
    assert trail["lng"] == -121.9523
    assert trail["label"] =~ "Northern trail"
  end

  test "the focused entity is flagged for the client" do
    focused =
      %{entity: "place:northern-trail"} |> map() |> points() |> Enum.filter(& &1["focused"])

    assert [%{"ref" => "place:northern-trail"}] = focused
  end

  test "the caption reports coverage, including what is missing" do
    html = map()

    assert html =~ "have a known location"

    assert html =~ "not shown",
           "unlocated entities must be declared, not silently omitted"
  end

  test "with nothing located it renders nothing, rather than an empty map" do
    refute map(%{geo: Geo.project(%{})}) =~ "atlas-map"
  end

  test "map_points/3 sends only what the map needs" do
    [point | _] = AtlasLive.map_points(geo(), nil, [])

    assert Map.keys(point) |> Enum.sort() ==
             [:affected, :focused, :icon, :kind, :label, :lat, :lng, :ref],
           "a full entity would carry event ids and provenance into an attribute for no purpose"
  end
end
