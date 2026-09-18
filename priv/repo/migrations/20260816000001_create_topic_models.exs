defmodule Indivisual.Repo.Migrations.CreateTopicModels do
  use Ecto.Migration

  def change do
    create table(:topic_models) do
      add :model, :string, null: false
      add :k, :integer, null: false
      # %{cluster => %{"label" => ..., "terms" => [...], "size" => n}}
      add :topics, :map, default: %{}, null: false
      # %{node_id => %{"topic" => cluster, "pos" => [x, y, z]}}
      add :placements, :map, default: %{}, null: false
      add :space_id, references(:spaces, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:topic_models, [:space_id, :model])
  end
end
