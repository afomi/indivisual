defmodule Indivisual.Semantic.VectorMath do
  @moduledoc """
  Vector primitives over plain float lists — FC2.7.
  Ported from cdcs_ex's VectorMath. No deps, no Nx: at hundreds of nodes,
  Elixir dot products are plenty.
  """

  @doc "Dot product of two equal-length vectors. Returns 0.0 on mismatch."
  def dot_product(a, b) when length(a) == length(b) do
    Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
  end

  def dot_product(_, _), do: 0.0

  @doc "Euclidean (L2) norm."
  def magnitude(v) do
    :math.sqrt(Enum.reduce(v, 0.0, fn x, acc -> acc + x * x end))
  end

  @doc "Cosine similarity in [-1, 1]. Returns 0.0 for zero or mismatched vectors."
  def cosine_similarity(a, b) when length(a) == length(b) do
    mag = magnitude(a) * magnitude(b)
    if mag > 0, do: dot_product(a, b) / mag, else: 0.0
  end

  def cosine_similarity(_, _), do: 0.0

  @doc "L2-normalize. Zero vectors pass through unchanged."
  def normalize(v) do
    mag = magnitude(v)
    if mag > 0, do: Enum.map(v, &(&1 / mag)), else: v
  end

  @doc "Element-wise difference a - b."
  def subtract(a, b) do
    Enum.zip(a, b) |> Enum.map(fn {x, y} -> x - y end)
  end

  @doc "Element-wise mean of a non-empty list of equal-length vectors."
  def centroid([v]), do: v

  def centroid([_ | _] = vectors) do
    n = length(vectors)

    vectors
    |> Enum.zip_with(& &1)
    |> Enum.map(fn components -> Enum.sum(components) / n end)
  end

  @doc "Euclidean distance between two vectors."
  def euclidean_distance(a, b) do
    subtract(a, b) |> magnitude()
  end
end
