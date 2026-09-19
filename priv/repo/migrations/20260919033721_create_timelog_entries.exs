defmodule Indivisual.Repo.Migrations.CreateTimelogEntries do
  use Ecto.Migration

  # A timelog entry is an INTERVAL, not a point. `valid_to IS NULL` means the
  # entry is still true — "long-showing unless a structure conveys start and end".
  # That is what lets a view ask "what was true at T" as one indexed predicate
  # instead of folding the whole history.
  #
  # One table with a `kind` discriminator + jsonb payload, following the
  # nodes.kind + nodes.metadata precedent rather than a table per log type.
  def change do
    create table(:timelog_entries) do
      # users.id is binary_id; every other FK in this app points at an integer
      # serial table, so this type annotation is required and easy to forget.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :kind, :string, null: false
      add :title, :string, null: false

      add :valid_from, :utc_datetime, null: false
      add :valid_to, :utc_datetime

      add :payload, :map, null: false, default: %{}
      add :geo, :map

      # ip / precise geolocation / device. Kept in its own column, never merged
      # into :payload, so "do not select this" is a property of the column and
      # not a convention a future query has to remember.
      add :private_metadata, :map, null: false, default: %{}

      # External id (e.g. a Google Calendar event id) when this row mirrors a
      # record owned elsewhere. Null for entries authored here.
      add :source_ref, :string

      timestamps(type: :utc_datetime)
    end

    # Serves ownership filtering and the newest-first ordering every list uses.
    #
    # Measured, not assumed: this does NOT accelerate the `at(t)` lookup. That
    # predicate ends in `valid_to IS NULL OR valid_to > t`, and the disjunction
    # defeats a b-tree, so only the user_id equality drives the scan. At the
    # sizes tested (10k entries/user) Postgres correctly prefers a sequential
    # scan anyway. Revisit with a range type or a GiST index if per-user volume
    # grows enough that it stops choosing one.
    create index(:timelog_entries, [:user_id, :valid_from])
    create index(:timelog_entries, [:user_id, :kind])

    # Open intervals are the ones a "still going?" query looks for.
    create index(:timelog_entries, [:user_id],
             where: "valid_to IS NULL",
             name: :timelog_entries_open_index
           )

    # Sync idempotency: re-running a calendar sync must not duplicate rows.
    # Partial, because source_ref is null for locally authored entries and
    # NULLs would otherwise collide under a plain unique index.
    create unique_index(:timelog_entries, [:user_id, :source_ref],
             where: "source_ref IS NOT NULL",
             name: :timelog_entries_user_source_ref_index
           )

    # An interval that ends before it starts is not a thing.
    create constraint(:timelog_entries, :timelog_entries_valid_interval,
             check: "valid_to IS NULL OR valid_to >= valid_from"
           )
  end
end
