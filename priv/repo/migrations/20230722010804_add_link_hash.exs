defmodule Indivisual.Repo.Migrations.AddLinkHash do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :from_hash, :string
      add :to_hash, :string
    end
  end
end
