defmodule Indivisual.Repo.Migrations.CreateNodeAxisScores do
  use Ecto.Migration

  def change do
    create table(:node_axis_scores) do
      add :score, :float, null: false
      add :model, :string
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :semantic_axis_id, references(:semantic_axes, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:node_axis_scores, [:node_id, :semantic_axis_id])
    create index(:node_axis_scores, [:semantic_axis_id])
  end
end
