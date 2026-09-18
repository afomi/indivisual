defmodule Indivisual.Repo.Migrations.CreateAtlasEvents do
  use Ecto.Migration

  # Append-only store for Atlas events accepted at runtime (annotations, live appends).
  # Adapter-seeded events (fixtures) are not stored; they are rebuilt from the adapter on boot.
  def change do
    create table(:atlas_events) do
      add :event_id, :string, null: false
      add :source_id, :string, null: false
      add :stream_id, :string, null: false
      add :sequence, {:array, :integer}, null: false
      add :event_type, :string, null: false
      add :occurred_at, :utc_datetime_usec
      add :observed_at, :utc_datetime_usec, null: false
      add :actor_ref, :string
      add :subject_refs, {:array, :string}, null: false, default: []
      add :payload, :map, null: false, default: %{}
      add :provenance, :map, null: false, default: %{}
      add :truth_state, :string, null: false
      add :raw, :map

      timestamps(updated_at: false)
    end

    create unique_index(:atlas_events, [:event_id])
    create index(:atlas_events, [:source_id])
    create index(:atlas_events, [:observed_at])
  end
end
