defmodule Indivisual.Repo.Migrations.RenameLinksToEdges do
  use Ecto.Migration

  def change do
    rename table(:links), to: table(:edges)

    alter table(:edges) do
      add :space_id, references(:spaces, on_delete: :delete_all)
    end

    create index(:edges, [:space_id])
    create index(:edges, [:from_id])
    create index(:edges, [:to_id])
  end
end
