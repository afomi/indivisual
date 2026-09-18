defmodule Indivisual.Projections.Axis do
  @moduledoc """
  Axis layout specs for Projections — FC2.

  A Projection's `layout` map declares HOW nodes are positioned:

      %{}                                        # freeform (default) — nodes at their stored x/y
      %{"kind" => "freeform",
        "positions" => %{"12" => [x, y]}}        # freeform snapshot (positions per projection)
      %{"kind" => "axes",
        "x_axis" => %{"property" => "metadata.value", "scale" => "linear",
                      "jitter" => 0, "label" => "Value"},
        "y_axis" => %{"property" => "kind", "scale" => "ordinal",
                      "jitter" => 16, "label" => "Kind"},
        "drag_enabled" => false,
        "show_axes" => true}
      %{"kind" => "semantic",
        "x_axis" => %{"axis_id" => 3},
        "y_axis" => %{"axis_id" => 7}}           # semantic axes (embedding-derived scores)

  `normalize/1` validates and fills defaults so bad specs can't persist.
  `resolve/2` turns a layout + nodes into per-node axis VALUES and DOMAINS —
  viewport-independent; the client maps values to pixels, draws ticks, jitters,
  and tweens. Data axes and semantic axes resolve to the same payload shape.
  """

  @scales ~w(linear ordinal time)
  @kinds ~w(freeform axes semantic)

  # Top-level Node fields addressable as axis properties (besides metadata.*).
  @node_properties %{
    "kind" => :kind,
    "x" => :x,
    "y" => :y,
    "z" => :z,
    "heading" => :heading,
    "magnitude" => :magnitude,
    "wardley_x" => :wardley_x,
    "wardley_y" => :wardley_y,
    "inserted_at" => :inserted_at,
    "updated_at" => :updated_at
  }

  @doc "String names of addressable top-level Node fields."
  def node_properties, do: Map.keys(@node_properties)

  @doc """
  Validates and normalizes a layout map.
  Returns `{:ok, normalized}` or `{:error, reason}`.
  `%{}` and `nil` are valid and mean freeform.
  """
  def normalize(nil), do: {:ok, %{}}
  def normalize(layout) when layout == %{}, do: {:ok, %{}}

  def normalize(%{"kind" => "freeform"} = layout) do
    positions = layout["positions"] || %{}

    if is_map(positions) and Enum.all?(positions, &valid_position?/1) do
      {:ok, %{"kind" => "freeform", "positions" => positions}}
    else
      {:error, "freeform positions must map node ids to [x, y] number pairs"}
    end
  end

  def normalize(%{"kind" => "axes"} = layout) do
    with {:ok, x_axis} <- normalize_axis(layout["x_axis"]),
         {:ok, y_axis} <- normalize_axis(layout["y_axis"]) do
      {:ok,
       %{
         "kind" => "axes",
         "x_axis" => x_axis,
         "y_axis" => y_axis,
         "drag_enabled" => layout["drag_enabled"] == true,
         "show_axes" => layout["show_axes"] != false
       }}
    end
  end

  def normalize(%{"kind" => "semantic"} = layout) do
    with {:ok, x_axis} <- normalize_semantic_axis(layout["x_axis"]),
         {:ok, y_axis} <- normalize_semantic_axis(layout["y_axis"]) do
      {:ok,
       %{
         "kind" => "semantic",
         "x_axis" => x_axis,
         "y_axis" => y_axis,
         "drag_enabled" => false,
         "show_axes" => layout["show_axes"] != false
       }}
    end
  end

  def normalize(%{"kind" => kind}), do: {:error, "unknown layout kind #{inspect(kind)} — expected one of #{Enum.join(@kinds, ", ")}"}
  def normalize(_), do: {:error, "layout must be a map with a \"kind\" key (or empty for freeform)"}

  defp valid_position?({_id, [x, y]}) when is_number(x) and is_number(y), do: true
  defp valid_position?(_), do: false

  defp normalize_axis(%{"property" => property} = axis) when is_binary(property) do
    scale = axis["scale"] || "linear"
    jitter = axis["jitter"] || 0

    cond do
      not valid_property?(property) ->
        {:error, "unknown axis property #{inspect(property)}"}

      scale not in @scales ->
        {:error, "unknown scale #{inspect(scale)} — expected one of #{Enum.join(@scales, ", ")}"}

      not (is_number(jitter) and jitter >= 0) ->
        {:error, "jitter must be a non-negative number"}

      true ->
        {:ok,
         %{
           "property" => property,
           "scale" => scale,
           "jitter" => jitter,
           "label" => axis["label"] || property
         }}
    end
  end

  defp normalize_axis(_), do: {:error, "axes layout requires x_axis and y_axis maps with a \"property\""}

  defp normalize_semantic_axis(%{"axis_id" => id}) when is_integer(id), do: {:ok, %{"axis_id" => id}}
  defp normalize_semantic_axis(_), do: {:error, "semantic layout requires x_axis and y_axis maps with an integer \"axis_id\""}

  defp valid_property?("metadata." <> key), do: key != ""
  defp valid_property?(property), do: Map.has_key?(@node_properties, property)

  @doc """
  Resolves a layout against a list of nodes into the client render payload:

      %{"kind" => "axes", "drag_enabled" => false, "show_axes" => true,
        "x" => %{"label" => ..., "scale" => ..., "domain" => ..., "jitter" => ...,
                 "values" => %{"<node_id>" => value}},
        "y" => %{...}}

  Nodes lacking a value for a property are omitted from `values`
  (the client parks them dimmed at the margin).
  """
  def resolve(layout, nodes, opts \\ [])

  def resolve(layout, _nodes, _opts) when layout == %{} or is_nil(layout) do
    %{"kind" => "freeform", "drag_enabled" => true}
  end

  def resolve(%{"kind" => "freeform"} = layout, _nodes, _opts) do
    %{"kind" => "freeform", "drag_enabled" => true, "positions" => layout["positions"] || %{}}
  end

  def resolve(%{"kind" => "axes"} = layout, nodes, _opts) do
    %{
      "kind" => "axes",
      "drag_enabled" => layout["drag_enabled"] == true,
      "show_axes" => layout["show_axes"] != false,
      "x" => resolve_axis(layout["x_axis"], nodes),
      "y" => resolve_axis(layout["y_axis"], nodes)
    }
  end

  def resolve(%{"kind" => "semantic"} = layout, nodes, opts) do
    scores_fn = Keyword.get(opts, :scores_fn, &Indivisual.Semantic.axis_scores/2)

    %{
      "kind" => "semantic",
      "drag_enabled" => false,
      "show_axes" => layout["show_axes"] != false,
      "x" => resolve_semantic_axis(layout["x_axis"], nodes, scores_fn),
      "y" => resolve_semantic_axis(layout["y_axis"], nodes, scores_fn)
    }
  end

  defp resolve_axis(%{"property" => property} = axis, nodes) do
    scale = axis["scale"] || "linear"

    values =
      nodes
      |> Enum.map(fn node -> {Integer.to_string(node.id), coerce(extract(node, property), scale)} end)
      |> Enum.reject(fn {_id, v} -> is_nil(v) end)
      |> Map.new()

    %{
      "label" => axis["label"] || property,
      "scale" => scale,
      "jitter" => axis["jitter"] || 0,
      "domain" => domain(Map.values(values), scale),
      "values" => values
    }
  end

  defp resolve_semantic_axis(%{"axis_id" => axis_id}, nodes, scores_fn) do
    {axis, scores} = scores_fn.(axis_id, Enum.map(nodes, & &1.id))

    values =
      scores
      |> Enum.map(fn {node_id, score} -> {Integer.to_string(node_id), score} end)
      |> Map.new()

    %{
      "label" => axis.name,
      "negative_pole" => axis.negative_pole,
      "positive_pole" => axis.positive_pole,
      "scale" => "linear",
      "jitter" => 0,
      "domain" => semantic_domain(Map.values(values)),
      "values" => values
    }
  end

  # Real-world cosine scores occupy a narrow band of [-1, 1]; a fixed domain
  # crushes the scatter into the center. Fit the domain to the observed range
  # (padded 10%, min 0.02) so structure is visible — the pole labels still
  # mark which direction is which.
  defp semantic_domain([]), do: [-1.0, 1.0]

  defp semantic_domain(scores) do
    {min, max} = Enum.min_max(scores)
    pad = max((max - min) * 0.1, 0.02)
    [max(min - pad, -1.0), min(max + pad, 1.0)]
  end

  # ── Extraction & coercion ─────────────────────────────────────────────────

  defp extract(node, "metadata." <> key), do: Map.get(node.metadata || %{}, key)
  defp extract(node, property), do: Map.get(node, Map.fetch!(@node_properties, property))

  defp coerce(nil, _scale), do: nil

  defp coerce(value, "linear") when is_number(value), do: value

  defp coerce(value, "linear") when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp coerce(_value, "linear"), do: nil

  defp coerce(%DateTime{} = dt, "time"), do: DateTime.to_unix(dt, :millisecond)
  defp coerce(%NaiveDateTime{} = ndt, "time"), do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
  defp coerce(%Date{} = d, "time"), do: d |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix(:millisecond)

  defp coerce(value, "time") when is_binary(value) do
    cond do
      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, dt, _} = DateTime.from_iso8601(value)
        DateTime.to_unix(dt, :millisecond)

      match?({:ok, _}, Date.from_iso8601(value)) ->
        {:ok, d} = Date.from_iso8601(value)
        d |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix(:millisecond)

      true ->
        nil
    end
  end

  defp coerce(_value, "time"), do: nil

  defp coerce(value, "ordinal") when is_binary(value), do: value
  defp coerce(value, "ordinal") when is_number(value) or is_boolean(value), do: to_string(value)
  defp coerce(_value, "ordinal"), do: nil

  defp domain([], "ordinal"), do: []
  defp domain([], _scale), do: [0, 1]
  defp domain(values, "ordinal"), do: values |> Enum.uniq() |> Enum.sort()
  defp domain(values, _scale), do: [Enum.min(values), Enum.max(values)]
end
