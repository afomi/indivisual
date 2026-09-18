defmodule Indivisual.Projection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projections" do
    field :name, :string
    field :filter_config, :map, default: %{}
    field :layout, :map, default: %{}

    belongs_to :space, Indivisual.Space

    timestamps()
  end

  @doc false
  def changeset(projection, attrs) do
    projection
    |> cast(attrs, [:name, :filter_config, :layout, :space_id])
    |> validate_required([:name, :space_id])
    |> normalize_layout()
    |> unique_constraint([:space_id, :name])
  end

  defp normalize_layout(changeset) do
    case fetch_change(changeset, :layout) do
      {:ok, layout} ->
        case Indivisual.Projections.Axis.normalize(layout) do
          {:ok, normalized} -> put_change(changeset, :layout, normalized)
          {:error, reason} -> add_error(changeset, :layout, reason)
        end

      :error ->
        changeset
    end
  end
end
