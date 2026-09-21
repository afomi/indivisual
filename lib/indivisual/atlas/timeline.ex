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

  # Every activity should be a mark you can see, so the cap is set where the
  # demo fixture's busiest moment (12 events at one timestamp) fits whole. It was
  # 6, which hid 6 of 26 — and an event picked from the list could have no mark
  # at all. A cap still exists so one very busy day cannot make the band
  # arbitrarily tall; past it, `:pin` guarantees the selected event is drawn.
  @default_lanes 12

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

  Options:

    * `:lanes` — the lane cap (default #{@default_lanes})
    * `:pin` — an `event_id` that must be drawn. If it would fall past the cap it
      takes the top lane at its spot and the mark it displaces is counted in
      `overflow` instead, so the selected event is never the one left out.
  """
  def build(events, opts \\ [])

  def build([], _opts) do
    %{marks: [], overflow: 0, lanes: 0, from: nil, to: nil, span_days: 0}
  end

  def build(events, opts) do
    lane_cap = Keyword.get(opts, :lanes, @default_lanes)
    pin = Keyword.get(opts, :pin)

    # Ids the filters leave in. Marks outside this set are still drawn, dimmed:
    # rebuilding the band from only what survives a filter rescales the span
    # and the lane count, so every remaining mark jumps to a new place. The
    # record does not change when a source is switched off, so neither should
    # the band.
    read = opts |> Keyword.get(:read) |> read_set()

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

        cond do
          lane >= lane_cap and event.event_id == pin and lane_cap > 0 ->
            # Take the top lane at this spot; what was there is counted instead.
            top = lane_cap - 1
            kept = Enum.reject(acc, fn m -> m.lane == top and abs(m.x - x) < 0.5 end)

            mark = %{
              event: event,
              event_id: event.event_id,
              read: read == nil or MapSet.member?(read, event.event_id),
              x: Float.round(x, 3),
              lane: top,
              time: time
            }

            {[mark | kept], over + 1, max(max_lane, top)}

          lane >= lane_cap ->
            {acc, over + 1, max_lane}

          true ->
            mark = %{
              event: event,
              event_id: event.event_id,
              read: read == nil or MapSet.member?(read, event.event_id),
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

  # Measured against a ~900px bar: 6px dots stay distinct down to ~10px apart.
  @default_max_dots 90

  @doc """
  Dots for the range bar: one per event, placed by ORDINAL position.

  The range bar's handles snap to event 1, 2, 3…, so its dots sit on that same
  axis — a dot is exactly where a handle lands on it. This is deliberately not
  the real-time axis `build/2` uses: dots in real time would drift away from the
  handles that select them, and the bar would show one thing and do another.

  **Packing.** One dot per event holds until the bar runs out of room. Past
  `:max` dots, consecutive events are packed into equal runs, each drawn as one
  dot carrying its `count` — so nothing is hidden, only grouped, and the counts
  always sum to the number of events.

  Returns a list of `%{x:, count:, first:, last:, indexes:}` where `x` is a
  0.0–1.0 fraction along the bar (the run's midpoint) and `indexes` are the
  events the dot stands for.

  Options: `:max` (default #{@default_max_dots}).
  """
  def ordinal_dots(events, opts \\ []) do
    for run <- runs(length(events), opts), do: dot(run.x, run.indexes)
  end

  @doc """
  The same dots, fanned out into one lane per `key_fun.(event)` — per source,
  say. Every lane shares the combined bar's axis and its packing runs, so a
  lane's dot sits directly under the combined dot it came out of, and the lanes
  always sum back to `ordinal_dots/2`. A key with no events in a run simply has
  no dot there.

  Returns `%{key => [dot]}`. Options as `ordinal_dots/2`.
  """
  def ordinal_lanes(events, key_fun, opts \\ []) do
    keys = events |> Enum.map(key_fun) |> List.to_tuple()

    for run <- runs(length(events), opts),
        {key, indexes} <- Enum.group_by(run.indexes, &elem(keys, &1)),
        reduce: %{} do
      lanes -> Map.update(lanes, key, [dot(run.x, indexes)], &(&1 ++ [dot(run.x, indexes)]))
    end
  end

  defp dot(x, indexes) do
    %{
      x: x,
      count: length(indexes),
      first: List.first(indexes),
      last: List.last(indexes),
      indexes: indexes
    }
  end

  # Consecutive index runs and where each sits along the bar.
  defp runs(0, _opts), do: []

  defp runs(total, opts) do
    max_dots = opts |> Keyword.get(:max, @default_max_dots) |> max(1)
    last_index = total - 1

    0..last_index
    |> Enum.chunk_every(ceil(total / max_dots))
    |> Enum.map(fn indexes ->
      # A lone event has no extent; centre it rather than dividing by zero.
      x =
        if last_index == 0,
          do: 0.5,
          else: (List.first(indexes) + List.last(indexes)) / 2 / last_index

      %{x: Float.round(x, 4), indexes: indexes}
    end)
  end

  # As many ticks as a thin band can label without the labels colliding.
  @max_ticks 8

  # Calendar steps, finest first. The first one that fits @max_ticks wins, so
  # the axis re-grains itself as the window changes: a two-year window reads in
  # quarters, a two-month window in weeks, a two-day window in hours.
  @steps [
    {:hour, 1},
    {:hour, 6},
    {:day, 1},
    {:day, 7},
    {:month, 1},
    {:month, 3},
    {:month, 6},
    {:month, 12},
    {:month, 24},
    {:month, 60},
    {:month, 120},
    {:month, 300},
    {:month, 1200}
  ]

  # Interior ticks this close (in % of the band) to an end would print over the
  # end's own label. Measured: an end label is ~8% of a 900px band, an interior
  # one ~5%, and the end label at 100 is right-aligned.
  @edge_clearance_start 10.0
  @edge_clearance_end 86.0

  defp read_set(nil), do: nil
  defp read_set(%MapSet{} = set), do: set
  defp read_set(events) when is_list(events), do: MapSet.new(events, & &1.event_id)

  @doc """
  Tick marks for the band, as `%{x:, label:, edge:}`, at a grain chosen from
  the span.

  **The ends are always labelled with the exact extent** (`edge: :start` /
  `:end`). Interior ticks fall on calendar boundaries, so on their own the last
  one can sit months before the last event — a band ending 19 Sep 2026 would
  read "… Jul 2026" and look like it stops in July. The edge labels are what
  make the axis say the range it actually covers; an interior tick that would
  collide with one gives way to it.

  The band rescales to whatever window is being read, so its axis has to as
  well: fixed quarterly ticks label a two-year span well and a six-week span
  not at all. The step is the finest calendar unit that still fits
  #{@max_ticks} labels, and the label says as much as that grain needs —
  a year, a month, a day, or a time.

  A window with no extent (one instant) gets a single tick naming that day, at
  the centre where `build/2` puts its marks — a band with events on it should
  never have a blank axis.
  """
  def ticks(%{from: nil}), do: []

  def ticks(%{from: from, to: to}) do
    span = DateTime.diff(to, from, :second)

    if span <= 0 do
      [%{x: 50.0, label: Calendar.strftime(from, "%b %-d, %Y"), edge: :only}]
    else
      step = Enum.find(@steps, List.last(@steps), &(span / step_seconds(&1) <= @max_ticks))

      interior =
        from
        |> boundaries(to, step)
        |> Enum.map(fn dt ->
          %{
            x: Float.round(DateTime.diff(dt, from, :second) / span * 100.0, 3),
            label: tick_label(dt, step),
            edge: nil
          }
        end)
        |> Enum.filter(&(&1.x > @edge_clearance_start and &1.x < @edge_clearance_end))

      [%{x: 0.0, label: edge_label(from, step), edge: :start}] ++
        interior ++ [%{x: 100.0, label: edge_label(to, step), edge: :end}]
    end
  end

  defp step_seconds({:hour, n}), do: n * 3_600
  defp step_seconds({:day, n}), do: n * 86_400
  # Mean month; only used to pick a grain, never to place a tick.
  defp step_seconds({:month, n}), do: n * 2_629_800

  # Calendar-aligned instants from the first boundary at or before `from`.
  defp boundaries(from, to, {:hour, n}) do
    start = %{
      from
      | hour: from.hour - rem(from.hour, n),
        minute: 0,
        second: 0,
        microsecond: {0, 0}
    }

    start
    |> Stream.iterate(&DateTime.add(&1, n * 3_600, :second))
    |> Enum.take_while(&(DateTime.compare(&1, to) != :gt))
  end

  defp boundaries(from, to, {:day, n}) do
    date = DateTime.to_date(from)
    # Weeks start on Monday, so weekly ticks land on the same days in any window.
    start = if n == 7, do: Date.beginning_of_week(date), else: date

    start
    |> Stream.iterate(&Date.add(&1, n))
    |> Stream.map(&midnight/1)
    |> Enum.take_while(&(DateTime.compare(&1, to) != :gt))
  end

  defp boundaries(from, to, {:month, n}) do
    first = from |> DateTime.to_date() |> Date.beginning_of_month()
    # Months since year 0, floored to the step: quarters fall on Jan/Apr/Jul/Oct
    # and multi-year steps on round years, whatever the window.
    index = first.year * 12 + first.month - 1
    index = index - rem(index, n)

    index
    |> Stream.iterate(&(&1 + n))
    |> Stream.map(&(Date.new!(div(&1, 12), rem(&1, 12) + 1, 1) |> midnight()))
    |> Enum.take_while(&(DateTime.compare(&1, to) != :gt))
  end

  defp midnight(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  # An end names the exact moment the band reaches, whatever the interior grain:
  # to the day, or to the minute once the whole band is within days.
  defp edge_label(dt, {:hour, _}), do: Calendar.strftime(dt, "%b %-d %H:%M")
  defp edge_label(dt, _step), do: Calendar.strftime(dt, "%b %-d, %Y")

  defp tick_label(dt, {:hour, _}), do: Calendar.strftime(dt, "%b %-d %H:%M")
  defp tick_label(dt, {:day, _}), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp tick_label(dt, {:month, n}) when n >= 12, do: Calendar.strftime(dt, "%Y")
  defp tick_label(dt, {:month, _}), do: Calendar.strftime(dt, "%b %Y")
end
