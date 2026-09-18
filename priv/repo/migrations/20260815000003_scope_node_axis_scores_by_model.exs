defmodule Indivisual.Repo.Migrations.ScopeNodeAxisScoresByModel do
  use Ecto.Migration

  def change do
    drop unique_index(:node_axis_scores, [:node_id, :semantic_axis_id])
    create unique_index(:node_axis_scores, [:node_id, :semantic_axis_id, :model])
  end
end
