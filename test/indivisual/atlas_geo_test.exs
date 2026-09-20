defmodule Indivisual.Atlas.GeoTest do
  @moduledoc """
  A map positions by real coordinates, which means an entity without them has
  nowhere to go. These pin that the module says so rather than inventing a
  position, and that bad coordinates are rejected before they reach a renderer.
  """
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Geo

  defp entity(kind, geo), do: %{kind: kind, label: "x", geo: geo}

  describe "coords/1" do
    test "accepts valid coordinates" do
      assert Geo.coords(entity("place", %{"lat" => 38.3566, "lng" => -121.955})) ==
               {38.3566, -121.955}
    end

    test "rejects out-of-range values" do
      refute Geo.coords(entity("place", %{"lat" => 91.0, "lng" => 0.0}))
      refute Geo.coords(entity("place", %{"lat" => 0.0, "lng" => 181.0}))
    end

    test "rejects non-numeric and incomplete values" do
      refute Geo.coords(entity("place", %{"lat" => "38", "lng" => -121.9}))
      refute Geo.coords(entity("place", %{"lat" => 38.3}))
      refute Geo.coords(entity("place", nil))
    end
  end

  describe "project/2" do
    test "separates located from unlocated entities" do
      entities = %{
        "a" => entity("place", %{"lat" => 38.0, "lng" => -122.0}),
        "b" => entity("goal", nil),
        "c" => entity("policy", nil)
      }

      result = Geo.project(entities)

      assert result.count == 1
      assert result.unlocated_count == 2
    end

    test "unlocated entities are returned, not silently dropped" do
      entities = %{"a" => entity("goal", nil)}
      %{unlocated: unlocated, points: points} = Geo.project(entities)

      assert points == []
      assert [{"a", _}] = unlocated
    end

    test "points land inside the padded view box" do
      entities = %{
        "a" => entity("place", %{"lat" => 38.0, "lng" => -122.0}),
        "b" => entity("place", %{"lat" => 39.0, "lng" => -121.0})
      }

      %{points: points} = Geo.project(entities, padding: 10)

      for p <- points do
        assert p.x >= 10 and p.x <= 90
        assert p.y >= 10 and p.y <= 90
      end
    end

    test "north is up: a higher latitude gets a smaller y" do
      entities = %{
        "south" => entity("place", %{"lat" => 38.0, "lng" => -122.0}),
        "north" => entity("place", %{"lat" => 39.0, "lng" => -122.0})
      }

      points = Geo.project(entities).points |> Map.new(&{&1.ref, &1})

      assert points["north"].y < points["south"].y
    end

    test "a single point centres rather than dividing by zero" do
      entities = %{"a" => entity("place", %{"lat" => 38.0, "lng" => -122.0})}
      %{points: [p]} = Geo.project(entities)

      assert p.x == 50.0
      assert p.y == 50.0
    end

    test "no located entities yields no bounds, not a crash" do
      assert %{points: [], bounds: nil, count: 0} = Geo.project(%{"a" => entity("goal", nil)})
    end
  end
end
