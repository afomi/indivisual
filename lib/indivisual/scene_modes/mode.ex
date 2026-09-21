defmodule Indivisual.SceneModes.Mode do
  @moduledoc """
  A saved Spacetime mode: a name for a choice of `[x, y, z]` dimensions.

  The built-in layouts (Timeline, Moment, Map, Graph, Space) are exactly this —
  explicit x, y, z mappings — so a saved mode is a reader adding one of their own.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Indivisual.Atlas.Scene
  alias Indivisual.Atlas.Semantics

  schema "atlas_scene_modes" do
    field :name, :string
    field :axes, {:array, :string}
    # Set from the scope, never cast: see `SceneModes.create/2`.
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(mode, attrs) do
    mode
    |> cast(attrs, [:name, :axes])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :axes])
    |> validate_length(:name, max: 40)
    |> validate_axes()
    # Named by index so the error lands on the field the person can change, not
    # on `user_id`, which is where a multi-column constraint puts it by default.
    |> unique_constraint(:name,
      name: :atlas_scene_modes_user_id_name_index,
      message: "is already one of your modes"
    )
    |> unique_constraint(:axes,
      name: :atlas_scene_modes_user_id_axes_index,
      message: "are already saved as one of your modes"
    )
  end

  defp validate_axes(changeset) do
    # The semantic axes there are count as dimensions too: a mode may be built
    # on them. (One that is later deleted leaves a mode that no longer parses; it
    # is then simply not offered.)
    semantic = Semantics.dimensions(Indivisual.Semantic.list_axes(computed_only: true))

    validate_change(changeset, :axes, fn :axes, axes ->
      cond do
        is_nil(Scene.parse_axes(axes, semantic)) ->
          [axes: "must be three known dimensions"]

        # A preset needs no saving: it is already in the switch, under its name.
        Scene.layout_for(axes, semantic) != "custom" ->
          [
            axes:
              "are the built-in #{Scene.layout(Scene.layout_for(axes, semantic), semantic).name} mode"
          ]

        true ->
          []
      end
    end)
  end
end
