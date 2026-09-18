defmodule Indivisual.Repo.Migrations.CreateNodeEmbeddings do
  use Ecto.Migration

  def change do
    create table(:node_embeddings) do
      add :model, :string, null: false
      add :embedding, {:array, :float}, null: false
      add :embedded_at, :utc_datetime, null: false
      add :node_id, references(:nodes, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:node_embeddings, [:node_id, :model])
    create index(:node_embeddings, [:model])
  end
end
