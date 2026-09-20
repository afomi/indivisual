defmodule IndivisualWeb.AtlasMapTest do
  @moduledoc """
  The map is rendered by Leaflet in the browser, so the server's job is to hand
  over correct points and tell the truth about coverage. These cover that
  boundary: the data attribute, the hook, and the caption. Pin rendering itself
  is the client's.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Geo
  alias Indivisual.Atlas.Topology
  alias IndivisualWeb.AtlasLive

  defp points(view) do
    view
    |> element("#atlas-map")
    |> render()
    |> then(&Regex.run(~r/data-points="([^"]*)"/, &1, capture: :all_but_first))
    |> hd()
    |> String.replace("&quot;", "\"")
    |> Jason.decode!()
  end

  test "the map container is hooked and owns its own DOM", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    html = view |> element("#atlas-map") |> render()

    assert html =~ "phx-hook"

    assert html =~ ~s(phx-update="ignore"),
           "Leaflet manages this subtree; LiveView must not patch it"
  end

  test "every located entity is handed to the map", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    expected = Geo.project(Topology.entities(Feed.events(Feed, []))).count
    assert length(points(view)) == expected
  end

  test "points carry real coordinates and a label", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    trail = Enum.find(points(view), &(&1["ref"] == "place:northern-trail"))

    assert trail["lat"] == 38.3671
    assert trail["lng"] == -121.9523
    assert trail["label"] =~ "Northern trail"
  end

  test "the focused entity is flagged for the client", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?entity=place:northern-trail")

    focused = Enum.filter(points(view), & &1["focused"])

    assert [%{"ref" => "place:northern-trail"}] = focused
  end

  test "the caption reports coverage, including what is missing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    caption = view |> element(".atlas-map__caption") |> render()

    assert caption =~ "have a known location"

    assert caption =~ "not shown",
           "unlocated entities must be declared, not silently omitted"
  end

  test "map_points/3 sends only what the map needs" do
    geo = Geo.project(Topology.entities(Feed.events(Feed, [])))
    [point | _] = AtlasLive.map_points(geo, nil, [])

    assert Map.keys(point) |> Enum.sort() ==
             [:affected, :focused, :label, :lat, :lng, :ref],
           "a full entity would carry event ids and provenance into an attribute for no purpose"
  end
end
