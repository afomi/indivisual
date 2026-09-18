defmodule Indivisual.Repo.Migrations.NodeDescriptionText do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      remove :description
      add :description, :text
    end
  end
end
