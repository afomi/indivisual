defmodule Indivisual.Repo.Migrations.AddIntentToNodes do
  use Ecto.Migration

  # A Node is a point; an intent vector is a Node that also points.
  # heading = direction (radians, atan2(dx, dz) convention); magnitude = force.
  # Both nullable: a plain point is a vector of zero declared intent.
  def change do
    alter table(:nodes) do
      add :heading, :float
      add :magnitude, :float
    end
  end
end
