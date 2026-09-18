defmodule Indivisual.Semantic.NodeEmbedding do
  @moduledoc """
  A node's embedding under one specific model (FC2.20). The `nodes.embedding`
  column remains the default-model cache used by the single-model pipeline;
  this table holds one row per (node, model) for multi-model triangulation —
  comparing how different models place the same records.
  """

  use Ecto.Schema

  schema "node_embeddings" do
    field :model, :string
    field :embedding, {:array, :float}
    field :embedded_at, :utc_datetime

    belongs_to :node, Indivisual.Visual.Node

    timestamps(updated_at: false)
  end
end
