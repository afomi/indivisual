defmodule Indivisual.Atlas.Scatter do
  @moduledoc """
  View model for the 3D scatter on `/atlas`: one point per event, in a volume
  spanned by three axes, each an opposition between two poles.

  **Positions and axes are placeholders.** A point is placed by a hash of its
  `event_id`, not by anything the event says, and the axes are a fixed set that
  nothing scores against. The read model says so (`basis: :placeholder`) and the
  view must repeat it: a point's place means nothing yet, and a reader should
  never be left to infer that it does.

  The shape is the contract, and it is what will stay when the placement becomes
  real: `build/1` is the one function to replace. Hashing rather than `:rand`
  keeps it a pure function of the events, like every other Atlas view model —
  the same event lands in the same place on every read, reload, and machine, and
  a live append never moves the points already there.
  """

  alias Indivisual.Atlas.Event

  @axes [
    %{id: "x", negative: "Local", positive: "Regional"},
    %{id: "y", negative: "Plan", positive: "Built"},
    %{id: "z", negative: "Cost", positive: "Benefit"}
  ]

  @type point :: %{id: String.t(), x: float(), y: float(), z: float()}

  @doc "The three axes, each `%{id, negative, positive}`. Hard-coded for now."
  def axes, do: @axes

  @doc """
  Builds the scatter for `events`.

  Returns `%{basis: :placeholder, axes: [...], points: [point]}`, with points in
  event order and every coordinate in `-1.0..1.0`.
  """
  def build(events) do
    %{
      basis: :placeholder,
      axes: @axes,
      points:
        Enum.map(events, fn %Event{event_id: id} ->
          {x, y, z} = position(id)
          %{id: id, x: x, y: y, z: z}
        end)
    }
  end

  @doc "A stable point in the unit cube for an id: three 16-bit words of its SHA-256."
  def position(id) when is_binary(id) do
    <<x::16, y::16, z::16, _::binary>> = :crypto.hash(:sha256, id)
    {unit(x), unit(y), unit(z)}
  end

  defp unit(word), do: Float.round(word / 65_535 * 2 - 1, 4)
end
