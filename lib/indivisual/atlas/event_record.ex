defmodule Indivisual.Atlas.EventRecord do
  @moduledoc """
  Ecto row for a persisted `Indivisual.Atlas.Event`. Insert-only: the store never
  updates or deletes a row, and `event_id` is unique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Indivisual.Atlas.Event

  @fields ~w(event_id source_id stream_id sequence event_type occurred_at observed_at actor object payload provenance truth_state raw)a

  schema "atlas_events" do
    field :event_id, :string
    field :source_id, :string
    field :stream_id, :string
    field :sequence, {:array, :integer}
    field :event_type, :string
    field :occurred_at, :utc_datetime_usec
    field :observed_at, :utc_datetime_usec
    field :actor, :string
    field :object, {:array, :string}, default: []
    field :payload, :map, default: %{}
    field :provenance, :map, default: %{}
    field :truth_state, :string
    field :raw, :map

    timestamps(updated_at: false)
  end

  @doc "Changeset from a validated event."
  def from_event(%Event{} = event) do
    %__MODULE__{}
    |> cast(Map.take(Map.from_struct(event), @fields), @fields)
    |> validate_required(
      ~w(event_id source_id stream_id sequence event_type observed_at truth_state)a
    )
    |> unique_constraint(:event_id)
  end

  @doc "Rebuilds the event struct from a row."
  def to_event(%__MODULE__{} = record) do
    struct(Event, Map.take(record, @fields))
  end
end
