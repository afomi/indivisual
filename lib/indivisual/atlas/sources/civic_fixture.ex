defmodule Indivisual.Atlas.Sources.CivicFixture do
  @moduledoc """
  Seed source adapter: a civic/public-record fixture adapted from OpenSolano's Atlas
  context for the East of Leisure Town Specific Plan.

  Reads `priv/atlas/civic_fixture.json`. Demo data only; clearly labeled as a fixture.
  """

  @behaviour Indivisual.Atlas.Source

  @path "priv/atlas/civic_fixture.json"

  @impl true
  def info do
    fixture()["adapter"] |> atomize()
  end

  @impl true
  def sources do
    fixture()["sources"] |> Enum.map(&atomize/1)
  end

  @impl true
  def events do
    fixture()["events"]
  end

  defp fixture do
    :indivisual
    |> Application.app_dir(@path)
    |> File.read!()
    |> Jason.decode!()
  end

  defp atomize(map), do: Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
end
