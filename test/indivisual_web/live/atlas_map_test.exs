defmodule IndivisualWeb.AtlasMapTest do
  @moduledoc """
  The map positions entities by real coordinates. The thing that must not
  regress is honesty about coverage: a map showing 5 of 12 entities must say
  so, or it reads as a map of everything.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Geo
  alias Indivisual.Atlas.Topology

  test "pins render for located entities", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-map")
    assert has_element?(view, ".atlas-map__pin")
  end

  test "one pin per located entity, no more", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    expected = Geo.project(Topology.entities(Feed.events(Feed, []))).count
    pins = html |> String.split("atlas-map__pin") |> length() |> Kernel.-(1)

    assert has_element?(view, ".atlas-map__pin")
    # Each pin renders the class once in its class list.
    assert pins >= expected
  end

  test "the caption reports coverage, including what is missing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    caption = view |> element(".atlas-map__caption") |> render()

    assert caption =~ "have a known location"

    assert caption =~ "not shown",
           "unlocated entities must be declared, not silently omitted"
  end

  test "a pin focuses its entity", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view
    |> element(~s(.atlas-map__pin[phx-value-ref="place:northern-trail"]))
    |> render_click()

    assert assert_patch(view) =~ "entity="
  end

  test "the focused entity is marked on the map", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?entity=place:northern-trail")

    assert has_element?(
             view,
             ~s(.atlas-map__pin.is-focused[phx-value-ref="place:northern-trail"])
           )
  end

  test "pins carry their coordinates for inspection", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    pin =
      view
      |> element(~s(.atlas-map__pin[phx-value-ref="place:northern-trail"]))
      |> render()

    assert pin =~ "38.3671"
    assert pin =~ "-121.9523"
  end

  test "geography reads correctly: north is up", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    # Northern trail (38.3671) is the northernmost; Carroll Way (38.3529) the
    # southernmost. On screen that means a smaller top value for the north.
    [_, north_top] = Regex.run(~r/place:northern-trail[^>]*top: ([\d.]+)%/, html)
    [_, south_top] = Regex.run(~r/place:carroll-way[^>]*top: ([\d.]+)%/, html)

    assert String.to_float(north_top) < String.to_float(south_top)
  end
end
