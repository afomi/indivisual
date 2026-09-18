defmodule Indivisual.Repo.Migrations.AddSpaceIdToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :space_id, references(:spaces, on_delete: :delete_all)
    end

    create index(:nodes, [:space_id])
  end
end
