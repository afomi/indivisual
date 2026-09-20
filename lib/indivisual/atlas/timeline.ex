defmodule Indivisual.Atlas.Timeline do
  @moduledoc """
  Positions events on a horizontal band by when they actually happened.

  The scrubber alone is ordinal — event 1, 2, 3 — which spaces a two-year gap
  the same as two minutes apart. Marks are temporal: the horizontal position is
  real time, so a gap in the record looks like a gap.

  **Collisions stack rather than compress.** Measured against the demo fixture,
  26 events fall on 8 distinct days: 12 share one timestamp. No horizontal
  scale fixes that — piecewise and square-root scales were tried and still
  collapsed 26 marks into 7-10 positions — because the events genuinely happen
  at the same moment. So time stays honest on the x-axis and simultaneity is
  shown by stacking on the y-axis, where it reads as what it is: a burst.

  Lanes are capped so one busy day cannot make the band arbitrarily tall; the
  overflow is reported rather than silently dropped.
  """

  alias Indivisual.Atlas.Event

  # Measured on the demo fixture: 6 lanes shows 20 of 26 marks at a band height
  # that still reads as a band. More lanes hide less but stop being horizontal.
  @default_lanes 6

  @type mark :: %{
          event: Event.t(),
          event_id: String.t(),
          x: float(),
          lane: non_neg_integer(),
          time: DateTime.t()
        }

  @doc """
  Builds marks for `events`.

  Returns `%{marks:, overflow:, lanes:, from:, to:, span_days:}`.
  `x` is a percentage (0.0–100.0) across the band; `lane` is the stacking row.
  `overflow` counts events beyond the lane cap at a shared position.

  Options: `:lanes` (default #{@default_lanes}).
  """
  def build(events, opts \\ [])

  def build([], _opts) do
    %{marks: [], overflow: 0, lanes: 0, from: nil, to: nil, span_days: 0}
  end

  def build(events, opts) do
    lane_cap = Keyword.get(opts, :lanes, @default_lanes)

    timed = Enum.map(events, fn e -> {e, Event.effective_time(e)} end)

    {_, first} = Enum.min_by(timed, fn {_, t} -> DateTime.to_unix(t) end)
    {_, last} = Enum.max_by(timed, fn {_, t} -> DateTime.to_unix(t) end)

    span = max(DateTime.diff(last, first, :second), 1)

    # A single instant has no extent; centre it rather than dividing by zero.
    single? = DateTime.compare(first, last) == :eq

    {marks, overflow, max_lane} =
      timed
      |> Enum.sort_by(fn {_, t} -> DateTime.to_unix(t) end)
      |> Enum.reduce({[], 0, 0}, fn {event, time}, {acc, over, max_lane} ->
        x =
          if single? do
            50.0
          else
            DateTime.diff(time, first, :second) / span * 100.0
          end

        # Stack against marks already placed at (visually) the same spot.
        lane = Enum.count(acc, fn m -> abs(m.x - x) < 0.5 end)

        if lane >= lane_cap do
          {acc, over + 1, max_lane}
        else
          mark = %{
            event: event,
            event_id: event.event_id,
            x: Float.round(x, 3),
            lane: lane,
            time: time
          }

          {[mark | acc], over, max(max_lane, lane)}
        end
      end)

    %{
      marks: Enum.reverse(marks),
      overflow: overflow,
      lanes: max_lane + 1,
      from: first,
      to: last,
      span_days: div(DateTime.diff(last, first, :second), 86_400)
    }
  end

  @doc """
  Tick marks for the band: one per distinct month in the span, as
  `%{x:, label:}`. Kept sparse — a dense axis on a thin band is noise.
  """
  def ticks(%{from: nil}), do: []

  def ticks(%{from: from, to: to}) do
    span = max(DateTime.diff(to, from, :second), 1)

    from
    |> months_between(to)
    |> Enum.map(fn date ->
      {:ok, dt} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")

      %{
        x: Float.round(DateTime.diff(dt, from, :second) / span * 100.0, 3),
        label: Calendar.strftime(date, "%b %Y")
      }
    end)
    |> Enum.filter(&(&1.x >= 0 and &1.x <= 100))
  end

  # Quarter starts, so a multi-year span does not produce thirty labels.
  defp months_between(from, to) do
    start = from |> DateTime.to_date() |> Date.beginning_of_month()
    stop = DateTime.to_date(to)

    Stream.iterate(start, fn d -> d |> Date.add(32) |> Date.beginning_of_month() end)
    |> Enum.take_while(&(Date.compare(&1, stop) != :gt))
    |> Enum.filter(&(rem(&1.month - 1, 3) == 0))
  end
end
