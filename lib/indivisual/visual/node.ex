defmodule Indivisual.Visual.Node do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nodes" do
    field :description, :string
    field :name, :string
    field :hash, :string
    field :kind, :string

    field :x, :float
    field :y, :float

    field :wardley_x, :float
    field :wardley_y, :float
    field :z, :float
    field :wardley_text, :string

    # Intent vector: a Node that points.
    # heading = direction in radians (atan2(dx, dz)); magnitude = force/conviction.
    # nil = a plain point (a vector of zero declared intent).
    field :heading, :float
    field :magnitude, :float

    # Embedding of node_text (name + description + metadata values);
    # written by Indivisual.Semantic, dimensionality set by the embedding model.
    field :embedding, {:array, :float}
    field :embedded_at, :utc_datetime

    # Generic attribute bag — domain-specific keys per Space type.
    # Generation Citizen org keys:
    #   website     string
    #   logo        string (URL)
    #   org_type    string
    #   values      [string]
    #   programs    [string]
    #   regions     [string]
    #   populations [string]
    field :metadata, :map, default: %{}

    belongs_to :space, Indivisual.Space

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:name, :description, :kind, :x, :y, :z, :wardley_x, :wardley_y, :wardley_text, :heading, :magnitude, :metadata, :space_id])
    |> validate_required([:name])
  end
end
