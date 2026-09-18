defmodule Indivisual.Semantic.Topics do
  @moduledoc """
  Topic modeling over stored embeddings (FC2.21) — the "neighborhood atlas":
  unsupervised structure, so like records land near each other regardless of
  which city they come from.

  Pure, deterministic math over `%{id => vector}` maps — no ML deps:

    - `kmeans/3` — cosine k-means with farthest-point initialization seeded
      from the smallest id (same input → same clusters).
    - `pca_3d/1` — 3D PCA via the Gram-matrix trick (n×n instead of d×d, so
      4096-dim embeddings over a few hundred records stay cheap), power
      iteration with deflation. Output scaled to [-1, 1] per dimension.
    - `label_topics/2` — BERTopic-style c-TF-IDF over record texts: terms
      frequent within a cluster and rare across clusters.
    - `fit/3` — the pipeline: cluster + project + label.

  This is a diagram, not a map (see TOPOLOGICAL_EMBEDDING_SPACES.md):
  neighborhoods are meaningful, absolute coordinates are not. Topics found
  here are candidates for promotion into named semantic axes.
  """

  alias Indivisual.Semantic.VectorMath

  @max_iterations 30
  @power_iterations 60
  @label_terms 4

  @stopwords ~w(
    the and for with that this shall from are was were been being have has had
    not any all may will can such which who whom whose when where how what
    other than then them they their there these those its it's per each every
    within without into onto upon under over between before after during
    section chapter title article municipal code city ordinance ordinances
    provisions provision pursuant thereof herein hereby including means
  )

  # ── Public pipeline ───────────────────────────────────────────────────────

  @doc """
  Clusters, projects, and labels. `texts` is `%{id => String.t()}`.
  Options: `:stopwords` — extra label stopwords (e.g. city names).
  Returns `%{assignments: %{id => cluster}, placements: %{id => [x, y, z]},
  topics: %{cluster => %{label: String.t(), terms: [String.t()], size: n}}}`.
  """
  def fit(embeddings, texts, k, opts \\ []) do
    %{assignments: assignments} = kmeans(embeddings, k)
    placements = pca_3d(embeddings)
    labels = label_topics(assignments, texts, Keyword.get(opts, :stopwords, []))

    topics =
      assignments
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Map.new(fn {cluster, ids} ->
        info = Map.get(labels, cluster, %{label: "topic #{cluster}", terms: []})
        {cluster, %{label: info.label, terms: info.terms, size: length(ids)}}
      end)

    %{assignments: assignments, placements: placements, topics: topics}
  end

  # ── k-means (cosine) ──────────────────────────────────────────────────────

  @doc """
  Deterministic cosine k-means. Returns `%{assignments: %{id => cluster},
  centroids: [vector]}`. k is capped at the number of records.
  """
  def kmeans(embeddings, k) do
    ids = embeddings |> Map.keys() |> Enum.sort()
    k = min(k, length(ids))
    vectors = Map.new(embeddings, fn {id, v} -> {id, VectorMath.normalize(v)} end)

    centroids = init_centroids(ids, vectors, k)
    iterate(ids, vectors, centroids, %{}, @max_iterations)
  end

  # Farthest-point init: start from the smallest id, then repeatedly take the
  # record least similar to its nearest chosen centroid.
  defp init_centroids(ids, vectors, k) do
    first = vectors[hd(ids)]

    Enum.reduce(2..k//1, [first], fn _n, chosen ->
      {_similarity, farthest} =
        ids
        |> Enum.map(fn id ->
          nearest = chosen |> Enum.map(&VectorMath.dot_product(vectors[id], &1)) |> Enum.max()
          {nearest, id}
        end)
        |> Enum.min_by(fn {similarity, id} -> {similarity, id} end)

      chosen ++ [vectors[farthest]]
    end)
  end

  defp iterate(ids, vectors, centroids, previous, iterations_left) do
    assignments =
      Map.new(ids, fn id ->
        {_similarity, cluster} =
          centroids
          |> Enum.with_index()
          |> Enum.map(fn {centroid, index} ->
            {VectorMath.dot_product(vectors[id], centroid), index}
          end)
          |> Enum.max_by(fn {similarity, index} -> {similarity, -index} end)

        {id, cluster}
      end)

    if assignments == previous or iterations_left <= 0 do
      %{assignments: assignments, centroids: centroids}
    else
      next_centroids =
        centroids
        |> Enum.with_index()
        |> Enum.map(fn {old, index} -> recenter(old, index, assignments, vectors) end)

      iterate(ids, vectors, next_centroids, assignments, iterations_left - 1)
    end
  end

  defp recenter(old_centroid, index, assignments, vectors) do
    members = for {id, ^index} <- assignments, do: vectors[id]

    case members do
      [] -> old_centroid
      _ -> members |> VectorMath.centroid() |> VectorMath.normalize()
    end
  end

  # ── 3D PCA via the Gram matrix ───────────────────────────────────────────

  @doc """
  Projects embeddings to 3D, each dimension scaled to [-1, 1].
  Uses the n×n Gram matrix of centered vectors; principal directions come
  from its eigenvectors (power iteration + deflation), so cost scales with
  record count, not embedding dimensionality.
  """
  def pca_3d(embeddings) when map_size(embeddings) < 3 do
    Map.new(embeddings, fn {id, _v} -> {id, [0.0, 0.0, 0.0]} end)
  end

  def pca_3d(embeddings) do
    ids = embeddings |> Map.keys() |> Enum.sort()
    n = length(ids)
    mean = ids |> Enum.map(&embeddings[&1]) |> VectorMath.centroid()
    centered = Enum.map(ids, fn id -> VectorMath.subtract(embeddings[id], mean) end)

    gram =
      for row <- centered do
        for column <- centered, do: VectorMath.dot_product(row, column)
      end

    {components, _residual} =
      Enum.reduce(1..3, {[], gram}, fn seed, {found, matrix} ->
        eigenvector = power_iteration(matrix, n, seed)
        eigenvalue = VectorMath.dot_product(eigenvector, multiply(matrix, eigenvector))
        {found ++ [scale(eigenvector, :math.sqrt(max(eigenvalue, 0.0)))], deflate(matrix, eigenvector, eigenvalue)}
      end)

    coordinates =
      Enum.map(0..(n - 1), fn row ->
        Enum.map(components, fn component -> Enum.at(component, row) end)
      end)

    normalized = normalize_dimensions(coordinates)
    ids |> Enum.zip(normalized) |> Map.new()
  end

  defp power_iteration(matrix, n, seed) do
    # Deterministic start vector; varies with the deflation round so
    # successive components don't start identically.
    start = Enum.map(1..n, fn i -> :math.sin(seed * 100.0 + i * 1.7) end)

    Enum.reduce(1..@power_iterations, VectorMath.normalize(start), fn _i, v ->
      matrix |> multiply(v) |> VectorMath.normalize()
    end)
  end

  defp multiply(matrix, vector) do
    Enum.map(matrix, fn row -> VectorMath.dot_product(row, vector) end)
  end

  defp deflate(matrix, eigenvector, eigenvalue) do
    matrix
    |> Enum.with_index()
    |> Enum.map(fn {row, i} ->
      vi = Enum.at(eigenvector, i)

      row
      |> Enum.with_index()
      |> Enum.map(fn {value, j} -> value - eigenvalue * vi * Enum.at(eigenvector, j) end)
    end)
  end

  defp scale(vector, factor), do: Enum.map(vector, &(&1 * factor))

  defp normalize_dimensions(coordinates) do
    ranges =
      Enum.map(0..2, fn dim ->
        values = Enum.map(coordinates, &Enum.at(&1, dim))
        {Enum.min(values), Enum.max(values)}
      end)

    Enum.map(coordinates, fn point ->
      point |> Enum.zip(ranges) |> Enum.map(&rescale_dimension/1)
    end)
  end

  defp rescale_dimension({value, {min, max}}) do
    if max - min < 1.0e-12, do: 0.0, else: (value - min) / (max - min) * 2 - 1
  end

  # ── c-TF-IDF topic labels ────────────────────────────────────────────────

  @doc """
  Labels each cluster with the terms most distinctive for it:
  `%{cluster => %{label: "a · b · c", terms: [...]}}`.
  `extra_stopwords` adds corpus-specific exclusions (e.g. city names).
  """
  def label_topics(assignments, texts, extra_stopwords \\ []) do
    excluded = MapSet.new(@stopwords ++ Enum.map(extra_stopwords, &String.downcase/1))

    cluster_tokens =
      assignments
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Map.new(fn {cluster, ids} ->
        tokens =
          ids
          |> Enum.flat_map(&tokenize(Map.get(texts, &1, ""), excluded))
          |> Enum.frequencies()

        {cluster, tokens}
      end)

    n_clusters = max(map_size(cluster_tokens), 1)

    document_frequency =
      cluster_tokens
      |> Enum.flat_map(fn {_c, tokens} -> Map.keys(tokens) end)
      |> Enum.frequencies()

    Map.new(cluster_tokens, fn {cluster, tokens} ->
      total = tokens |> Map.values() |> Enum.sum() |> max(1)

      terms =
        tokens
        |> Enum.map(fn {term, count} ->
          idf = :math.log(1 + n_clusters / document_frequency[term])
          {term, count / total * idf}
        end)
        |> Enum.sort_by(fn {term, score} -> {-score, term} end)
        |> Enum.take(@label_terms)
        |> Enum.map(&elem(&1, 0))

      {cluster, %{label: Enum.join(terms, " · "), terms: terms}}
    end)
  end

  defp tokenize(text, excluded) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.filter(fn token -> String.length(token) > 2 and not MapSet.member?(excluded, token) end)
  end
end
