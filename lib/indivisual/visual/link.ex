defmodule Indivisual.Visual.Link do
  use Ecto.Schema
  import Ecto.Changeset

  schema "edges" do
    field :description, :string
    field :from_id, :integer
    field :name, :string
    field :to_id, :integer

    field :from_hash, :string
    field :to_hash, :string

    belongs_to :space, Indivisual.Space

    timestamps()
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:name, :description, :from_id, :to_id, :from_hash, :to_hash, :space_id])
    |> validate_required([:from_id, :to_id])
  end
end
