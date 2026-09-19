defmodule Indivisual.Semantic do
  @moduledoc """
  Context for semantic axes over embedding space — FC2.7–FC2.11.
  Port of cdcs_ex's Analysis.SemanticAxes, adapted to Nodes.

  An axis is defined by two poles, each anchored with example phrases.
  `compute_axis_vector/1` embeds the anchors and stores the L2-normalized
  difference of the pole centroids, plus quality metrics. `embed_nodes/1`
  embeds node text; `score_nodes/1` projects embedded nodes onto an axis.
  """

  import Ecto.Query, warn: false

  alias Indivisual.Repo
  alias Indivisual.Embeddings
  alias Indivisual.Semantic.Axis
  alias Indivisual.Semantic.NodeAxisScore
  alias Indivisual.Semantic.NodeEmbedding
  alias Indivisual.Semantic.VectorMath
  alias Indivisual.Visual.Node

  # ── Axis CRUD ─────────────────────────────────────────────────────────────

  def list_axes(opts \\ []) do
    query = from a in Axis, order_by: [asc: a.name]

    query =
      if Keyword.get(opts, :computed_only, false) do
        from a in query, where: not is_nil(a.axis_vector)
      else
        query
      end

    Repo.all(query)
  end

  def get_axis!(id), do: Repo.get!(Axis, id)

  def get_axis_by_name(name), do: Repo.get_by(Axis, name: name)

  def create_axis(attrs) do
    %Axis{}
    |> Axis.changeset(attrs)
    |> Repo.insert()
  end

  def update_axis(%Axis{} = axis, attrs) do
    axis
    |> Axis.changeset(attrs)
    |> Repo.update()
  end

  def delete_axis(%Axis{} = axis), do: Repo.delete(axis)

  # ── Axis vector computation ───────────────────────────────────────────────

  @doc """
  Embeds the axis's anchor phrases and stores the axis vector plus quality
  metrics (pole_separation: cosine of pole centroids, lower is better;
  positive_spread / negative_spread: mean anchor distance from centroid).

  Returns `{:ok, axis}` with a non-nil `axis_vector`, or `{:error, reason}`
  (`:unavailable` when the embedding backend is down).
  """
  def compute_axis_vector(%Axis{} = axis) do
    pos = axis.positive_examples || []
    neg = axis.negative_examples || []

    with :ok <- validate_examples(pos, neg),
         {:ok, vectors} <- Embeddings.embed(pos ++ neg) do
      {pos_vectors, neg_vectors} = Enum.split(vectors, length(pos))

      pos_centroid = VectorMath.centroid(pos_vectors)
      neg_centroid = VectorMath.centroid(neg_vectors)

      direction =
        pos_centroid
        |> VectorMath.subtract(neg_centroid)
        |> VectorMath.normalize()

      metadata = %{
        "pole_separation" => VectorMath.cosine_similarity(pos_centroid, neg_centroid),
        "positive_spread" => spread(pos_vectors, pos_centroid),
        "negative_spread" => spread(neg_vectors, neg_centroid),
        "computed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      axis
      |> Axis.compute_changeset(direction, Embeddings.model(), metadata)
      |> Repo.update()
    end
  end

  defp validate_examples(pos, neg) when length(pos) >= 2 and length(neg) >= 2, do: :ok
  defp validate_examples(_, _), do: {:error, "each pole needs at least 2 anchor phrases"}

  defp spread(vectors, centroid) do
    vectors
    |> Enum.map(&VectorMath.euclidean_distance(&1, centroid))
    |> Enum.sum()
    |> Kernel./(length(vectors))
  end

  # ── Node embeddings ───────────────────────────────────────────────────────

  # Metadata keys that are identity/reference, not semantic content — they
  # must not leak into embedding text (a city name in every record's text
  # makes clusters segregate by city token instead of subject matter).
  @non_semantic_metadata_keys ~w(website logo url image city code_ref chapter sketch_id)

  @doc """
  The text a node is embedded from: name, description, and scalar/list
  metadata values (identity/reference keys excluded — see
  `@non_semantic_metadata_keys`).
  """
  def node_text(%Node{} = node) do
    meta_values =
      (node.metadata || %{})
      |> Enum.reject(fn {k, _v} -> k in @non_semantic_metadata_keys end)
      |> Enum.flat_map(fn
        {_k, v} when is_binary(v) -> [v]
        {_k, v} when is_list(v) -> Enum.filter(v, &is_binary/1)
        _ -> []
      end)

    [node.name, node.description | meta_values]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
  end

  @doc """
  Embeds a single node and persists `embedding` + `embedded_at`.
  """
  def embed_node(%Node{} = node) do
    case Embeddings.embed([node_text(node)]) do
      {:ok, [vector]} ->
        node
        |> Ecto.Changeset.change(
          embedding: vector,
          embedded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Embeds all nodes in a space missing an embedding (or all, with
  `force: true`), in batches (`batch_size`, default 100 — use smaller batches
  with long texts so one request stays inside `timeout`).
  Returns `{:ok, %{embedded: n, failed: n}}`.
  """
  def embed_nodes(space, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    batch_size = Keyword.get(opts, :batch_size, 100)
    embed_opts = Keyword.take(opts, [:timeout])

    query = from n in Node, where: n.space_id == ^space.id

    query =
      if force do
        query
      else
        from n in query, where: is_nil(n.embedding)
      end

    nodes = Repo.all(query)

    results =
      nodes
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(&embed_batch(&1, embed_opts))

    {:ok,
     %{
       embedded: Enum.count(results, &(&1 == :ok)),
       failed: Enum.count(results, &(&1 == :error))
     }}
  end

  defp embed_batch(batch, embed_opts) do
    case Embeddings.embed(Enum.map(batch, &node_text/1), embed_opts) do
      {:ok, vectors} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        batch
        |> Enum.zip(vectors)
        |> Enum.map(fn {node, vector} ->
          node
          |> Ecto.Changeset.change(embedding: vector, embedded_at: now)
          |> Repo.update()
          |> elem(0)
        end)

      {:error, _reason} ->
        Enum.map(batch, fn _ -> :error end)
    end
  end

  # ── Multi-model triangulation (FC2.20) ────────────────────────────────────
  #
  # The single-model pipeline above uses `nodes.embedding` and the axis's
  # primary `axis_vector`. The functions below survey the SAME nodes and the
  # SAME axes under additional embedding models: embeddings go to
  # `node_embeddings` (one row per node+model), axis vectors to
  # `Axis.variants`, scores to `node_axis_scores` keyed by model. Raw spaces
  # across models are incomparable (different dims/bases); anchored-axis
  # scores are each model's own cosine projection onto the same named axis,
  # which makes cross-model comparison meaningful.

  @doc """
  Embeds a space's nodes under a specific model into `node_embeddings`.
  Skips nodes already embedded under that model unless `force: true`.
  Returns `{:ok, %{embedded: n, failed: n}}`.
  """
  def embed_space_with_model(space, model, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    batch_size = Keyword.get(opts, :batch_size, 100)
    embed_opts = opts |> Keyword.take([:timeout]) |> Keyword.put(:model, model)

    already =
      from(e in NodeEmbedding,
        join: n in Node,
        on: n.id == e.node_id,
        where: n.space_id == ^space.id and e.model == ^model,
        select: e.node_id
      )
      |> Repo.all()
      |> MapSet.new()

    nodes =
      space
      |> Indivisual.Spaces.list_nodes_for_space()
      |> Enum.reject(&(not force and MapSet.member?(already, &1.id)))

    results =
      nodes
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(&embed_model_batch(&1, embed_opts, model))

    {:ok,
     %{
       embedded: Enum.count(results, &(&1 == :ok)),
       failed: Enum.count(results, &(&1 == :error))
     }}
  end

  defp embed_model_batch(batch, embed_opts, model) do
    case Embeddings.embed(Enum.map(batch, &node_text/1), embed_opts) do
      {:ok, vectors} -> store_node_embeddings(batch, vectors, model)
      {:error, _reason} -> Enum.map(batch, fn _ -> :error end)
    end
  end

  defp store_node_embeddings(batch, vectors, model) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      batch
      |> Enum.zip(vectors)
      |> Enum.map(fn {node, vector} ->
        %{
          node_id: node.id,
          model: model,
          embedding: vector,
          embedded_at: now,
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }
      end)

    Repo.insert_all(NodeEmbedding, rows,
      on_conflict: {:replace, [:embedding, :embedded_at]},
      conflict_target: [:node_id, :model]
    )

    Enum.map(batch, fn _ -> :ok end)
  end

  @doc """
  Computes this axis's vector under a specific model and stores it as a
  variant (`axis.variants[model]`), leaving the primary vector untouched.
  """
  def compute_axis_variant(%Axis{} = axis, model, opts \\ []) do
    pos = axis.positive_examples || []
    neg = axis.negative_examples || []
    embed_opts = opts |> Keyword.take([:timeout]) |> Keyword.put(:model, model)

    with :ok <- validate_examples(pos, neg),
         {:ok, vectors} <- Embeddings.embed(pos ++ neg, embed_opts) do
      {pos_vectors, neg_vectors} = Enum.split(vectors, length(pos))
      pos_centroid = VectorMath.centroid(pos_vectors)
      neg_centroid = VectorMath.centroid(neg_vectors)

      variant = %{
        "axis_vector" =>
          pos_centroid |> VectorMath.subtract(neg_centroid) |> VectorMath.normalize(),
        "metadata" => %{
          "pole_separation" => VectorMath.cosine_similarity(pos_centroid, neg_centroid),
          "positive_spread" => spread(pos_vectors, pos_centroid),
          "negative_spread" => spread(neg_vectors, neg_centroid),
          "computed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      axis
      |> Ecto.Changeset.change(variants: Map.put(axis.variants || %{}, model, variant))
      |> Repo.update()
    end
  end

  @doc """
  The axis's vector as surveyed by a given model: the primary vector when the
  model matches, else the stored variant. Returns nil when uncomputed.
  """
  def axis_vector_for(%Axis{} = axis, model) do
    cond do
      axis.model == model and axis.axis_vector != nil -> axis.axis_vector
      variant = get_in(axis.variants || %{}, [model, "axis_vector"]) -> variant
      true -> nil
    end
  end

  @doc """
  Scores a space's nodes on an axis using a specific model's embeddings
  (from `node_embeddings`) and that model's axis vector. Returns
  `{:ok, %{scored: n, skipped: n}}` or `{:error, reason}`.
  """
  def score_nodes_with_model(%Axis{} = axis, model, opts \\ []) do
    case axis_vector_for(axis, model) do
      nil ->
        {:error, "axis #{axis.name} has no vector for model #{model}"}

      vector ->
        space_id = Keyword.get(opts, :space_id)

        query =
          from(e in NodeEmbedding,
            join: n in Node,
            on: n.id == e.node_id,
            where: e.model == ^model,
            select: {e.node_id, e.embedding}
          )

        query =
          if space_id, do: from([e, n] in query, where: n.space_id == ^space_id), else: query

        embedded = Repo.all(query)
        upsert_scores(axis, model, vector, embedded)
        {:ok, %{scored: length(embedded), skipped: 0}}
    end
  end

  @doc """
  Fits and stores a topic model for a (space, model) pair from its stored
  `node_embeddings` (FC2.21). Returns `{:ok, %TopicModel{}}` or
  `{:error, :no_embeddings}`.
  """
  def fit_topic_model(space, model, k) do
    embeddings =
      from(e in Indivisual.Semantic.NodeEmbedding,
        join: n in Node,
        on: n.id == e.node_id,
        where: n.space_id == ^space.id and e.model == ^model,
        select: {e.node_id, e.embedding}
      )
      |> Repo.all()
      |> Map.new()

    if map_size(embeddings) == 0 do
      {:error, :no_embeddings}
    else
      nodes = Indivisual.Spaces.list_nodes_for_space(space)
      texts = Map.new(nodes, &{&1.id, node_text(&1)})

      # City/identity names must not become topic labels.
      identity_stopwords =
        nodes
        |> Enum.map(& &1.metadata["city"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      result = Indivisual.Semantic.Topics.fit(embeddings, texts, k, stopwords: identity_stopwords)

      placements =
        Map.new(result.placements, fn {node_id, pos} ->
          {to_string(node_id), %{"topic" => result.assignments[node_id], "pos" => pos}}
        end)

      topics =
        Map.new(result.topics, fn {cluster, info} ->
          {to_string(cluster),
           %{"label" => info.label, "terms" => info.terms, "size" => info.size}}
        end)

      attrs = %{model: model, k: k, topics: topics, placements: placements, space_id: space.id}

      record =
        case Repo.get_by(Indivisual.Semantic.TopicModel, space_id: space.id, model: model) do
          nil -> struct(Indivisual.Semantic.TopicModel, attrs)
          existing -> Ecto.Changeset.change(existing, Map.drop(attrs, [:space_id]))
        end

      case record do
        %Ecto.Changeset{} = changeset -> Repo.update(changeset)
        struct -> Repo.insert(struct)
      end
    end
  end

  @doc "Stored topic models for a space, newest first: one per embedding model."
  def topic_models_for_space(space) do
    Repo.all(
      from t in Indivisual.Semantic.TopicModel,
        where: t.space_id == ^space.id,
        order_by: [asc: t.model]
    )
  end

  @doc "Distinct models with stored scores for a space's nodes."
  def score_models_for_space(space) do
    from(s in NodeAxisScore,
      join: n in Node,
      on: n.id == s.node_id,
      where: n.space_id == ^space.id,
      distinct: true,
      select: s.model
    )
    |> Repo.all()
    |> Enum.sort()
  end

  # ── Scoring ───────────────────────────────────────────────────────────────

  @doc """
  Projects every embedded node in the axis's dimensionality onto the axis and
  upserts `node_axis_scores`. Pure math over stored vectors — no embedding
  backend needed. Returns `{:ok, %{scored: n, skipped: n}}` where skipped
  counts nodes without an embedding.
  """
  def score_nodes(axis, opts \\ [])

  def score_nodes(%Axis{axis_vector: nil}, _opts), do: {:error, "axis vector not computed"}

  def score_nodes(%Axis{} = axis, opts) do
    space_id = Keyword.get(opts, :space_id)

    query = from n in Node, select: {n.id, n.embedding}
    query = if space_id, do: from(n in query, where: n.space_id == ^space_id), else: query

    {embedded, missing} =
      query
      |> Repo.all()
      |> Enum.split_with(fn {_id, embedding} -> not is_nil(embedding) end)

    upsert_scores(axis, axis.model, axis.axis_vector, embedded)
    {:ok, %{scored: length(embedded), skipped: length(missing)}}
  end

  defp upsert_scores(axis, model, axis_vector, embedded_pairs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(embedded_pairs, fn {node_id, embedding} ->
        %{
          node_id: node_id,
          semantic_axis_id: axis.id,
          score: VectorMath.dot_product(embedding, axis_vector),
          model: model,
          inserted_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(NodeAxisScore, chunk,
        on_conflict: {:replace, [:score, :inserted_at]},
        conflict_target: [:node_id, :semantic_axis_id, :model]
      )
    end)
  end

  @doc """
  Scores for one axis over the given node ids, shaped for
  `Indivisual.Projections.Axis.resolve/3`: `{axis, %{node_id => score}}`.
  Filters to one model (default: the axis's primary model) so multi-model
  score rows don't mix.
  """
  def axis_scores(axis_id, node_ids, model \\ nil) do
    axis = get_axis!(axis_id)
    model = model || axis.model

    scores =
      from(s in NodeAxisScore,
        where: s.semantic_axis_id == ^axis_id and s.node_id in ^node_ids and s.model == ^model,
        select: {s.node_id, s.score}
      )
      |> Repo.all()
      |> Map.new()

    {axis, scores}
  end

  @doc """
  All axis scores for a space's nodes, keyed by model:
  `%{node_id => %{model => %{axis_id => score}}}`.
  Used by views that plot several axes at once (e.g. /topo).
  """
  def node_scores_for_space(space) do
    from(s in NodeAxisScore,
      join: n in Node,
      on: n.id == s.node_id,
      where: n.space_id == ^space.id,
      select: {s.node_id, s.model, s.semantic_axis_id, s.score}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {node_id, rows} ->
      by_model =
        rows
        |> Enum.group_by(&elem(&1, 1), fn {_n, _m, axis_id, score} -> {axis_id, score} end)
        |> Map.new(fn {model, pairs} -> {model, Map.new(pairs)} end)

      {node_id, by_model}
    end)
  end

  @doc "Count of scores stored for an axis."
  def score_count(%Axis{id: id}) do
    Repo.aggregate(from(s in NodeAxisScore, where: s.semantic_axis_id == ^id), :count)
  end
end
