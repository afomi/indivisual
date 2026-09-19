defmodule Indivisual.Semantic.Axis do
  @moduledoc """
  A semantic axis — a named direction in embedding space defined by two poles,
  each anchored by example phrases (FC2.7).

  The axis vector is the L2-normalized difference of the pole centroids;
  a node's score on the axis is the dot product of its embedding with the
  vector (≈ cosine, in [-1, 1]). `metadata` records quality metrics from
  compute time: pole_separation (cosine of the pole centroids — lower is
  better) and positive_spread / negative_spread (anchor tightness).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "semantic_axes" do
    field :name, :string
    field :positive_pole, :string
    field :negative_pole, :string
    field :positive_examples, {:array, :string}, default: []
    field :negative_examples, {:array, :string}, default: []
    field :axis_vector, {:array, :float}
    field :model, :string
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}

    # Per-model variants of this axis: the same anchors surveyed by other
    # embedding models. %{model => %{"axis_vector" => [...], "metadata" => %{...}}}
    field :variants, :map, default: %{}

    has_many :scores, Indivisual.Semantic.NodeAxisScore, foreign_key: :semantic_axis_id

    timestamps()
  end

  @doc false
  def changeset(axis, attrs) do
    axis
    |> cast(attrs, [
      :name,
      :positive_pole,
      :negative_pole,
      :positive_examples,
      :negative_examples,
      :is_active
    ])
    |> validate_required([:name, :positive_pole, :negative_pole])
    |> validate_length(:positive_examples, min: 2, message: "needs at least 2 anchor phrases")
    |> validate_length(:negative_examples, min: 2, message: "needs at least 2 anchor phrases")
    |> invalidate_vector_on_example_change(axis)
    |> unique_constraint(:name)
  end

  @doc false
  def compute_changeset(axis, axis_vector, model, metadata) do
    change(axis, axis_vector: axis_vector, model: model, metadata: metadata)
  end

  # Changing anchor phrases invalidates the computed vector and every
  # per-model variant (and with them, any scores' claim to freshness).
  defp invalidate_vector_on_example_change(changeset, axis) do
    has_vectors = not is_nil(axis.axis_vector) or map_size(axis.variants || %{}) > 0

    if has_vectors and
         (changed?(changeset, :positive_examples) or changed?(changeset, :negative_examples)) do
      changeset
      |> put_change(:axis_vector, nil)
      |> put_change(:variants, %{})
    else
      changeset
    end
  end
end
