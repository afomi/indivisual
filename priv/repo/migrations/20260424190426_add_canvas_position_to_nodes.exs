defmodule Indivisual.Repo.Migrations.AddCanvasPositionToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :x, :float
      add :y, :float
    end
  end
end
