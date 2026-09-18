defmodule Indivisual.Repo.Migrations.AddVariantsToSemanticAxes do
  use Ecto.Migration

  def change do
    alter table(:semantic_axes) do
      # Per-model axis vectors: %{model => %{"axis_vector" => [...],
      # "metadata" => %{...}, "computed_at" => ...}}. The axis's anchors are
      # model-independent; each variant is the same axis surveyed by a
      # different embedding model (triangulation).
      add :variants, :map, default: %{}, null: false
    end
  end
end
