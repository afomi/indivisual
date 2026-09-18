defmodule Indivisual.Semantic.Triangulation do
  @moduledoc """
  Cross-model comparison of embedding spaces over the same records (FC2.20).

  Two measures, both legitimate across models whose raw spaces are
  incomparable (different dimensionality and basis):

  1. **Mutual k-NN alignment** (the Platonic Representation Hypothesis
     metric, Huh et al. 2024, arXiv:2405.07987): for each record, the mean
     overlap of its k nearest neighbors under model A with those under
     model B. Basis-free — it compares neighborhood *structure*. PRH
     predicts high alignment; per-record LOW overlap marks records whose
     representation is not pinned down by shared world-structure.

  2. **Axis-score disagreement**: each model projects onto its own survey of
     the same anchored semantic axis; the per-record score delta between
     models is a directional, interpretable disagreement ("model A reads
     this chapter as more restrictive than model B does").
  """

  import Ecto.Query, warn: false

  alias Indivisual.Repo
  alias Indivisual.Semantic.NodeAxisScore
  alias Indivisual.Semantic.NodeEmbedding
  alias Indivisual.Semantic.VectorMath
  alias Indivisual.Visual.Node

  @doc """
  Mutual k-NN alignment between two embedding maps `%{id => vector}` over
  their shared ids. Returns `%{mean: float, per_record: %{id => float}, k: k,
  count: n}` — each per-record value is |kNN_A ∩ kNN_B| / k in [0, 1].
  """
  def mutual_knn_alignment(embeddings_a, embeddings_b, k \\ 10) do
    ids =
      MapSet.intersection(
        MapSet.new(Map.keys(embeddings_a)),
        MapSet.new(Map.keys(embeddings_b))
      )
      |> Enum.sort()

    k = min(k, max(length(ids) - 1, 1))

    neighbors_a = knn(ids, embeddings_a, k)
    neighbors_b = knn(ids, embeddings_b, k)

    per_record =
      Map.new(ids, fn id ->
        overlap = MapSet.intersection(neighbors_a[id], neighbors_b[id]) |> MapSet.size()
        {id, overlap / k}
      end)

    mean =
      case ids do
        [] -> 0.0
        _ -> Enum.sum(Map.values(per_record)) / length(ids)
      end

    %{mean: mean, per_record: per_record, k: k, count: length(ids)}
  end

  defp knn(ids, embeddings, k) do
    Map.new(ids, fn id ->
      nearest =
        ids
        |> Enum.reject(&(&1 == id))
        |> Enum.map(fn other ->
          {other, VectorMath.cosine_similarity(embeddings[id], embeddings[other])}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(k)
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      {id, nearest}
    end)
  end

  @doc "Embeddings for a space under one model: `%{node_id => vector}`."
  def embeddings_for_space(space, model) do
    from(e in NodeEmbedding,
      join: n in Node,
      on: n.id == e.node_id,
      where: n.space_id == ^space.id and e.model == ^model,
      select: {e.node_id, e.embedding}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Per-record score deltas between two models on one axis, sorted by absolute
  disagreement (largest first): `[%{node_id, name, score_a, score_b, delta}]`.
  """
  def axis_disagreement(space, axis, model_a, model_b) do
    scores =
      from(s in NodeAxisScore,
        join: n in Node,
        on: n.id == s.node_id,
        where:
          n.space_id == ^space.id and s.semantic_axis_id == ^axis.id and
            s.model in ^[model_a, model_b],
        select: {s.node_id, n.name, s.model, s.score}
      )
      |> Repo.all()
      |> Enum.group_by(fn {node_id, name, _m, _s} -> {node_id, name} end)

    scores
    |> Enum.flat_map(fn {{node_id, name}, rows} ->
      by_model = Map.new(rows, fn {_id, _n, model, score} -> {model, score} end)

      case {by_model[model_a], by_model[model_b]} do
        {a, b} when is_number(a) and is_number(b) ->
          [%{node_id: node_id, name: name, score_a: a, score_b: b, delta: a - b}]

        _ ->
          []
      end
    end)
    |> Enum.sort_by(&abs(&1.delta), :desc)
  end
end
