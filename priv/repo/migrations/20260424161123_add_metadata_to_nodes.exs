defmodule Indivisual.Repo.Migrations.AddMetadataToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :metadata, :map, default: %{}
    end
  end
end
