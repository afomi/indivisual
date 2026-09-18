defmodule Indivisual.Semantic.NodeAxisScore do
  @moduledoc """
  A node's projection onto a semantic axis (FC2.10):
  score = dot(node.embedding, axis.axis_vector), ≈ cosine in [-1, 1].
  Unique per [node, axis]; recomputes upsert in place.
  """

  use Ecto.Schema

  schema "node_axis_scores" do
    field :score, :float
    field :model, :string

    belongs_to :node, Indivisual.Visual.Node
    belongs_to :semantic_axis, Indivisual.Semantic.Axis

    timestamps(updated_at: false)
  end
end
