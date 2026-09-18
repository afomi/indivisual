defmodule Indivisual.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links) do
      add :name, :string
      add :description, :string
      add :from_id, :integer
      add :to_id, :integer

      timestamps()
    end
  end
end
