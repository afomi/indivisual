defmodule Indivisual.Repo.Migrations.CreateSemanticAxes do
  use Ecto.Migration

  def change do
    create table(:semantic_axes) do
      add :name, :string, null: false
      add :positive_pole, :string, null: false
      add :negative_pole, :string, null: false
      add :positive_examples, {:array, :text}, default: [], null: false
      add :negative_examples, {:array, :text}, default: [], null: false
      add :axis_vector, {:array, :float}
      add :model, :string
      add :is_active, :boolean, default: true, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:semantic_axes, [:name])
  end
end
