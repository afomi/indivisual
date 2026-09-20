defmodule Indivisual.Repo.Migrations.RenameAtlasEventRefsToAs2 do
  use Ecto.Migration

  # Aligns the two ref columns with their ActivityStreams 2.0 property names
  # (see STANDARDS.md). A column rename, so no atlas_events row is rewritten.
  def change do
    rename table(:atlas_events), :actor_ref, to: :actor
    rename table(:atlas_events), :subject_refs, to: :object
  end
end
