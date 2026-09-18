defmodule Indivisual.Projections.Schema do
  @moduledoc """
  Infers which node properties are plottable as axes — FC2.2.

  Port of sketch-data's `analyzeNodeProperties` / `generateSuggestions`,
  improved to sample ALL nodes (not just the first) so sparse metadata
  still surfaces.
  """

  # Top-level fields worth offering as axes, with their inherent types.
  @typed_fields [
    {"kind", "string"},
    {"heading", "number"},
    {"magnitude", "number"},
    {"z", "number"},
    {"inserted_at", "date"}
  ]

  @doc """
  Returns plottable properties across the given nodes:

      [%{property: "metadata.org_type", type: "string", coverage: 0.8}, ...]

  Types: "number" | "string" | "date" | "boolean" | "array".
  Properties with zero coverage are omitted.
  """
  def analyze([]), do: []

  def analyze(nodes) do
    total = length(nodes)

    top_level =
      for {name, type} <- @typed_fields,
          coverage = coverage(nodes, &Map.get(&1, String.to_existing_atom(name))),
          coverage > 0 do
        %{property: name, type: type, coverage: coverage}
      end

    metadata_keys =
      nodes
      |> Enum.flat_map(fn n -> Map.keys(n.metadata || %{}) end)
      |> Enum.uniq()
      |> Enum.sort()

    metadata =
      for key <- metadata_keys do
        values =
          nodes
          |> Enum.map(fn n -> Map.get(n.metadata || %{}, key) end)
          |> Enum.reject(&is_nil/1)

        %{
          property: "metadata." <> key,
          type: infer_type(values),
          coverage: length(values) / total
        }
      end

    top_level ++ metadata
  end

  @doc """
  Proposes ready-to-save axes layouts from the analyzed schema:
  scatter for numeric pairs, timeseries for date x numeric,
  distribution for numeric x categorical.

      [%{name: "Heading vs Magnitude", layout: %{"kind" => "axes", ...}}, ...]
  """
  def suggest(schema) do
    numbers = Enum.filter(schema, &(&1.type == "number"))
    strings = Enum.filter(schema, &(&1.type == "string"))
    dates = Enum.filter(schema, &(&1.type == "date"))

    scatters =
      for {a, i} <- Enum.with_index(numbers),
          {b, j} <- Enum.with_index(numbers),
          i < j do
        suggestion("#{label(a)} vs #{label(b)}", axis(a, "linear"), axis(b, "linear"))
      end

    timeseries =
      for d <- dates, n <- numbers do
        suggestion("#{label(n)} over time", axis(d, "time"), axis(n, "linear"))
      end

    distributions =
      for n <- numbers, s <- strings do
        suggestion("#{label(n)} by #{label(s)}", axis(n, "linear"), axis(s, "ordinal", 16))
      end

    scatters ++ timeseries ++ distributions
  end

  defp suggestion(name, x_axis, y_axis) do
    %{
      name: name,
      layout: %{
        "kind" => "axes",
        "x_axis" => x_axis,
        "y_axis" => y_axis,
        "drag_enabled" => false,
        "show_axes" => true
      }
    }
  end

  defp axis(prop, scale, jitter \\ 0) do
    %{
      "property" => prop.property,
      "scale" => scale,
      "jitter" => jitter,
      "label" => label(prop)
    }
  end

  defp label(%{property: "metadata." <> key}), do: key
  defp label(%{property: property}), do: property

  defp coverage(nodes, getter) do
    Enum.count(nodes, &(not is_nil(getter.(&1)))) / length(nodes)
  end

  defp infer_type(values) do
    cond do
      values == [] -> "string"
      Enum.all?(values, &is_list/1) -> "array"
      Enum.all?(values, &is_boolean/1) -> "boolean"
      Enum.all?(values, &numberish?/1) -> "number"
      Enum.all?(values, &dateish?/1) -> "date"
      true -> "string"
    end
  end

  defp numberish?(v) when is_number(v), do: true
  defp numberish?(v) when is_binary(v), do: match?({_, ""}, Float.parse(v))
  defp numberish?(_), do: false

  defp dateish?(v) when is_binary(v) do
    match?({:ok, _}, Date.from_iso8601(v)) or match?({:ok, _, _}, DateTime.from_iso8601(v))
  end

  defp dateish?(_), do: false
end
