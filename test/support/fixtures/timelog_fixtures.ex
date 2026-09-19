defmodule Indivisual.TimelogFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Indivisual.Timelog` context.
  """

  alias Indivisual.Timelog

  def valid_entry_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      "kind" => "work",
      "title" => "wrote a plan #{System.unique_integer([:positive])}",
      "valid_from" => DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc "An entry owned by `scope`'s user. Open-ended unless attrs say otherwise."
  def entry_fixture(scope, attrs \\ %{}) do
    {:ok, entry} =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> valid_entry_attributes()
      |> then(&Timelog.create_entry(scope, &1))

    entry
  end

  @doc "A closed entry spanning `from`..`to`."
  def closed_entry_fixture(scope, from, to, attrs \\ %{}) do
    entry_fixture(scope, Map.merge(attrs, %{"valid_from" => from, "valid_to" => to}))
  end

  @doc "A DateTime `n` seconds from now, truncated to the second."
  def at(n) do
    DateTime.utc_now() |> DateTime.add(n, :second) |> DateTime.truncate(:second)
  end
end
