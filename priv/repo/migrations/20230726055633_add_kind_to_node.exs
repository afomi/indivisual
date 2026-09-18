defmodule Indivisual.Repo.Migrations.AddKindToNode do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :kind, :string
    end
  end
end
