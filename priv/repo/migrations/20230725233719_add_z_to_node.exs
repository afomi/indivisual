defmodule Indivisual.Repo.Migrations.AddZToNode do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :z, :float
    end
  end
end
