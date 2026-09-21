defmodule Indivisual.Repo.Migrations.CreateAtlasSceneModes do
  use Ecto.Migration

  # A reader's own Spacetime modes: a name for a choice of three dimensions, one
  # per axis. View preferences, not part of the record — nothing here is an event.
  def change do
    create table(:atlas_scene_modes) do
      # users.id is binary_id; the annotation is required and easy to forget.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      # [x, y, z] dimension ids, e.g. ["source", "truth", "time"].
      add :axes, {:array, :string}, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:atlas_scene_modes, [:user_id])
    # One name, and one set of axes, per person: saving the same thing twice
    # would only make two chips that do the same.
    create unique_index(:atlas_scene_modes, [:user_id, :name])
    create unique_index(:atlas_scene_modes, [:user_id, :axes])
  end
end
