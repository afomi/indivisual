defmodule Indivisual.Repo.Migrations.AddEmbeddingToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :embedding, {:array, :float}
      add :embedded_at, :utc_datetime
    end
  end
end
