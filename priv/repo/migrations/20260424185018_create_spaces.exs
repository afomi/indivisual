defmodule Indivisual.Repo.Migrations.CreateSpaces do
  use Ecto.Migration

  def change do
    create table(:spaces) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "draft"

      timestamps()
    end

    create unique_index(:spaces, [:slug])
    create index(:spaces, [:status])
    create index(:spaces, [:inserted_at])
  end
end
