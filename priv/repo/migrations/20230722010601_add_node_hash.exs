defmodule Indivisual.Repo.Migrations.AddNodeHash do

  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :hash, :string
    end

  end
end
