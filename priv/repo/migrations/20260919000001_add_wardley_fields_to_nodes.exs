defmodule Indivisual.Repo.Migrations.AddWardleyFieldsToNodes do
  use Ecto.Migration

  # Indivisual.Visual.Node declares wardley_x / wardley_y / wardley_text, but no
  # migration ever created those columns — they were added to the schema in
  # adaptics without a matching migration, and the gap went unnoticed there
  # because that database predates the schema change.
  #
  # The effect is that ANY Ecto query selecting a Node raises
  #   ERROR 42703 (undefined_column) column n0.wardley_x does not exist
  # so /topo only appeared to work while it had zero rows to load.
  def change do
    alter table(:nodes) do
      add_if_not_exists :wardley_x, :float
      add_if_not_exists :wardley_y, :float
      add_if_not_exists :wardley_text, :string
    end
  end
end
