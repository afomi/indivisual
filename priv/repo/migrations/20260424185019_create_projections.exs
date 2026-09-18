defmodule Indivisual.Repo.Migrations.CreateProjections do
  use Ecto.Migration

  def change do
    create table(:projections) do
      add :name, :string, null: false
      add :filter_config, :map, default: %{}
      add :layout, :map, default: %{}
      add :space_id, references(:spaces, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:projections, [:space_id])
    create unique_index(:projections, [:space_id, :name])
  end
end
