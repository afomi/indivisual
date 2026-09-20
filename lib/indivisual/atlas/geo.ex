defmodule Indivisual.Atlas.Geo do
  @moduledoc """
  Geographic positioning for entities that carry coordinates.

  `Topology.layout/1` deliberately places entities on a ring "so the canvas
  never depends on geometry" — every entity gets a position whether or not it
  has a location. A map inverts that guarantee: position IS geometry, so an
  entity without coordinates has nowhere to go.

  This module answers that honestly rather than inventing positions. Located
  entities are projected into the view; unlocated ones are returned separately
  and counted, so a map can say "9 of 12 entities have no location" instead of
  silently showing three dots and implying that is everything.

  Coordinates are validated here too. `Topology` passes `entity["geo"]` through
  untyped, so a bad latitude would otherwise reach the renderer.
  """

  @doc """
  Projects entities onto a normalized view box.

  Returns `%{points:, unlocated:, bounds:, count:, unlocated_count:}` where each
  point carries `x`/`y` as percentages (0–100, y already flipped for screen
  coordinates), plus the original ref and entity.

  A single point, or several at one spot, centres rather than dividing by zero.
  Options: `:padding` (percent inset, default 8).
  """
  def project(entities, opts \\ []) do
    padding = Keyword.get(opts, :padding, 8)

    {located, unlocated} =
      entities
      |> Enum.map(fn {ref, entity} -> {ref, entity, coords(entity)} end)
      |> Enum.split_with(fn {_, _, coords} -> coords != nil end)

    bounds = bounds(located)

    %{
      points: Enum.map(located, &point(&1, bounds, padding)),
      unlocated: Enum.map(unlocated, fn {ref, entity, _} -> {ref, entity} end),
      bounds: bounds,
      count: length(located),
      unlocated_count: length(unlocated)
    }
  end

  @doc """
  Valid `{lat, lng}` for an entity, or nil.

  Rejects out-of-range and non-numeric values rather than passing them to a
  renderer that would place them off the canvas.
  """
  def coords(%{geo: geo}) when is_map(geo), do: parse(geo)
  def coords(%{"geo" => geo}) when is_map(geo), do: parse(geo)
  def coords(_), do: nil

  defp parse(geo) do
    lat = geo["lat"] || geo[:lat]
    lng = geo["lng"] || geo[:lng]

    if is_number(lat) and is_number(lng) and lat >= -90 and lat <= 90 and
         lng >= -180 and lng <= 180 do
      {lat / 1, lng / 1}
    end
  end

  defp bounds([]), do: nil

  defp bounds(located) do
    coords = Enum.map(located, fn {_, _, c} -> c end)
    lats = Enum.map(coords, &elem(&1, 0))
    lngs = Enum.map(coords, &elem(&1, 1))

    %{
      min_lat: Enum.min(lats),
      max_lat: Enum.max(lats),
      min_lng: Enum.min(lngs),
      max_lng: Enum.max(lngs)
    }
  end

  defp point({ref, entity, {lat, lng}}, bounds, padding) do
    span = 100 - padding * 2

    %{
      ref: ref,
      entity: entity,
      lat: lat,
      lng: lng,
      x: padding + span * fraction(lng, bounds.min_lng, bounds.max_lng),
      # Latitude increases northward; screen y increases downward.
      y: padding + span * (1 - fraction(lat, bounds.min_lat, bounds.max_lat))
    }
  end

  # A zero span means every point shares this axis; centre them.
  defp fraction(_value, min, max) when min == max, do: 0.5
  defp fraction(value, min, max), do: (value - min) / (max - min)
end
