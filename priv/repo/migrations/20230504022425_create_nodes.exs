defmodule Indivisual.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes) do
      add :name, :string
      add :description, :string

      timestamps()
    end
  end
end
