defmodule Indivisual.Space do
  use Ecto.Schema
  import Ecto.Changeset

  schema "spaces" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "draft"

    has_many :nodes, Indivisual.Visual.Node
    has_many :edges, Indivisual.Visual.Link
    has_many :projections, Indivisual.Projection

    timestamps()
  end

  @doc false
  def changeset(space, attrs) do
    space
    |> cast(attrs, [:name, :slug, :status])
    |> validate_required([:name, :slug])
    |> validate_inclusion(:status, ~w(draft published archived))
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""

        slug =
          name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
