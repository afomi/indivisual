defmodule Indivisual.Atlas.TimelineTest do
  @moduledoc """
  Marks are positioned by real time, which is the whole point — an ordinal
  scrubber spaces a two-year gap like a two-minute one. These pin the parts
  that would quietly betray that: simultaneous events must stack rather than
  overlap, and anything beyond the lane cap must be counted, never dropped
  silently.
  """
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Timeline

  defp event(id, occurred_at) do
    Event.new!(%{
      "event_id" => id,
      "source_id" => "test",
      "stream_id" => "test",
      "sequence" => [1],
      "event_type" => "civic.test",
      "occurred_at" => occurred_at,
      "observed_at" => occurred_at,
      "object" => ["thing:one"],
      "provenance" => %{"uri" => "test"},
      "truth_state" => "observed"
    })
  end

  describe "positioning" do
    test "the span's ends anchor the band" do
      events = [
        event("a", ~U[2024-01-01 00:00:00Z]),
        event("b", ~U[2026-01-01 00:00:00Z])
      ]

      %{marks: [first, last]} = Timeline.build(events)

      assert first.x == 0.0
      assert last.x == 100.0
    end

    test "position reflects real time, not sequence" do
      # Two events close together, one far away. An ordinal scale would space
      # these evenly; a temporal one must not.
      events = [
        event("a", ~U[2024-01-01 00:00:00Z]),
        event("b", ~U[2024-01-02 00:00:00Z]),
        event("c", ~U[2026-01-01 00:00:00Z])
      ]

      %{marks: [a, b, c]} = Timeline.build(events)

      assert a.x == 0.0
      assert c.x == 100.0
      assert b.x < 1.0, "a one-day gap in a two-year span must sit near the start"
    end

    test "marks come back in chronological order" do
      events = [
        event("late", ~U[2026-01-01 00:00:00Z]),
        event("early", ~U[2024-01-01 00:00:00Z]),
        event("mid", ~U[2025-01-01 00:00:00Z])
      ]

      ids = Timeline.build(events).marks |> Enum.map(& &1.event_id)
      assert ids == ["early", "mid", "late"]
    end

    test "a single event is centred rather than dividing by zero" do
      %{marks: [only], span_days: days} = Timeline.build([event("a", ~U[2024-01-01 00:00:00Z])])

      assert only.x == 50.0
      assert days == 0
    end

    test "several events at one instant all land at the centre, stacked" do
      t = ~U[2024-01-01 00:00:00Z]
      %{marks: marks} = Timeline.build([event("a", t), event("b", t), event("c", t)])

      assert Enum.all?(marks, &(&1.x == 50.0))
      assert Enum.map(marks, & &1.lane) == [0, 1, 2]
    end

    test "no events yields an empty band, not an error" do
      assert %{marks: [], lanes: 0, from: nil} = Timeline.build([])
    end
  end

  describe "stacking" do
    test "simultaneous events occupy separate lanes" do
      t = ~U[2024-06-01 00:00:00Z]

      events = [
        event("a", ~U[2024-01-01 00:00:00Z]),
        event("b", t),
        event("c", t),
        event("d", ~U[2024-12-01 00:00:00Z])
      ]

      %{marks: marks} = Timeline.build(events)
      same_spot = Enum.filter(marks, &(&1.event_id in ["b", "c"]))

      assert [l1, l2] = Enum.map(same_spot, & &1.lane)
      refute l1 == l2, "events at the same time must not draw on top of each other"
    end

    test "events beyond the lane cap are counted, not silently dropped" do
      t = ~U[2024-01-01 00:00:00Z]
      events = for i <- 1..10, do: event("e#{i}", t)

      %{marks: marks, overflow: overflow} = Timeline.build(events, lanes: 3)

      assert length(marks) == 3
      assert overflow == 7
      assert length(marks) + overflow == 10, "every event is either shown or counted"
    end

    test "a pinned event is always drawn, even past the cap" do
      t = ~U[2024-01-01 00:00:00Z]
      events = for i <- 1..10, do: event("e#{i}", t)

      %{marks: marks, overflow: overflow, lanes: lanes} =
        Timeline.build(events, lanes: 3, pin: "e9")

      assert "e9" in Enum.map(marks, & &1.event_id)
      # It displaces one mark rather than adding a lane: still 3 shown, 7 counted.
      assert length(marks) == 3
      assert overflow == 7
      assert lanes == 3
      assert marks |> Enum.map(& &1.lane) |> Enum.sort() == [0, 1, 2]
    end

    test "a pin that already fits changes nothing" do
      t = ~U[2024-01-01 00:00:00Z]
      events = for i <- 1..10, do: event("e#{i}", t)

      assert Timeline.build(events, lanes: 3, pin: "e2") == Timeline.build(events, lanes: 3)
      assert Timeline.build(events, lanes: 3, pin: "nope") == Timeline.build(events, lanes: 3)
    end

    test "the default cap holds the demo fixture's busiest moment whole" do
      t = ~U[2024-04-09 00:00:00Z]
      events = for i <- 1..12, do: event("e#{i}", t)

      assert %{overflow: 0, lanes: 12} = Timeline.build(events)
    end

    test "lanes reports the actual depth used" do
      t = ~U[2024-01-01 00:00:00Z]
      assert %{lanes: 2} = Timeline.build([event("a", t), event("b", t)], lanes: 6)
    end
  end

  describe "ordinal dots (the range bar)" do
    # Only position in the list and the lane key matter here, so plain maps do.
    defp items(sources), do: Enum.map(sources, &%{source_id: &1})

    test "one dot per event, evenly spaced end to end" do
      dots = Timeline.ordinal_dots(items(~w(a a a a a)))

      assert Enum.map(dots, & &1.x) == [0.0, 0.25, 0.5, 0.75, 1.0]
      assert Enum.all?(dots, &(&1.count == 1))
    end

    test "a dot sits exactly where a handle on that event would" do
      dots = Timeline.ordinal_dots(items(~w(a a a a)))

      # Handle fraction for index i of n is i / (n - 1).
      for {dot, i} <- Enum.with_index(dots), do: assert_in_delta(dot.x, i / 3, 0.001)
    end

    test "a lone event is centred rather than dividing by zero" do
      assert [%{x: 0.5, count: 1}] = Timeline.ordinal_dots(items(~w(a)))
    end

    test "no events, no dots" do
      assert Timeline.ordinal_dots([]) == []
      assert Timeline.ordinal_lanes([], & &1.source_id) == %{}
    end

    test "past the bar's capacity, runs pack and carry their count" do
      dots = Timeline.ordinal_dots(items(List.duplicate("a", 10)), max: 3)

      assert length(dots) <= 3
      assert Enum.map(dots, & &1.count) == [4, 4, 2]
      assert Enum.all?(dots, &(&1.x >= 0.0 and &1.x <= 1.0))
    end

    test "packing groups, never drops: counts sum to the events" do
      for n <- [1, 7, 90, 91, 1000] do
        dots = Timeline.ordinal_dots(items(List.duplicate("a", n)))
        assert dots |> Enum.map(& &1.count) |> Enum.sum() == n
        assert length(dots) <= 90
      end
    end
  end

  describe "ordinal lanes (the bar fanned out by source)" do
    test "each source gets its own lane, on the combined bar's axis" do
      events = items(~w(a b a c b))
      lanes = Timeline.ordinal_lanes(events, & &1.source_id)

      assert Map.keys(lanes) |> Enum.sort() == ~w(a b c)
      assert Enum.map(lanes["a"], & &1.x) == [0.0, 0.5]
      assert Enum.map(lanes["b"], & &1.x) == [0.25, 1.0]
      assert Enum.map(lanes["c"], & &1.x) == [0.75]
    end

    test "lanes collapse back into the single bar" do
      events = items(~w(a b a c b a a b c c a b))

      for opts <- [[], [max: 4]] do
        combined = Timeline.ordinal_dots(events, opts)
        lanes = Timeline.ordinal_lanes(events, & &1.source_id, opts)

        by_x =
          lanes
          |> Map.values()
          |> List.flatten()
          |> Enum.group_by(& &1.x, & &1.count)
          |> Map.new(fn {x, counts} -> {x, Enum.sum(counts)} end)

        assert by_x == Map.new(combined, &{&1.x, &1.count})
      end
    end

    test "a packed run splits its count between the sources in it" do
      lanes = Timeline.ordinal_lanes(items(~w(a a b a)), & &1.source_id, max: 1)

      assert [%{count: 3, indexes: [0, 1, 3]}] = lanes["a"]
      assert [%{count: 1, indexes: [2]}] = lanes["b"]
    end
  end

  describe "ticks" do
    test "are quarterly and inside the band" do
      events = [
        event("a", ~U[2024-01-01 00:00:00Z]),
        event("b", ~U[2026-01-01 00:00:00Z])
      ]

      ticks = events |> Timeline.build() |> Timeline.ticks()

      interior = Enum.filter(ticks, &is_nil(&1.edge))

      assert length(interior) > 0
      assert Enum.all?(ticks, &(&1.x >= 0 and &1.x <= 100))
      assert Enum.all?(interior, &(&1.label =~ ~r/^(Jan|Apr|Jul|Oct) \d{4}$/))
    end

    defp ticks(from, to) do
      [event("a", from), event("b", to)] |> Timeline.build() |> Timeline.ticks()
    end

    # Interior (calendar-boundary) labels only; the ends are covered separately.
    defp labels(from, to) do
      from |> ticks(to) |> Enum.filter(&is_nil(&1.edge)) |> Enum.map(& &1.label)
    end

    test "the ends name the exact extent, so the axis says the range it covers" do
      # The regression: a band ending 19 Sep 2026 whose last label was "Jul 2026"
      # read as though it stopped in July.
      ticks = ticks(~U[2024-04-09 00:00:00Z], ~U[2026-09-19 00:00:00Z])

      assert List.first(ticks) == %{x: 0.0, label: "Apr 9, 2024", edge: :start}
      assert List.last(ticks) == %{x: 100.0, label: "Sep 19, 2026", edge: :end}
    end

    test "an interior tick gives way rather than printing over an end" do
      ticks = ticks(~U[2024-04-09 00:00:00Z], ~U[2026-09-19 00:00:00Z])
      interior = Enum.filter(ticks, &is_nil(&1.edge))

      # Jul 2026 sits at ~91%, under the end label; it yields.
      refute "Jul 2026" in Enum.map(interior, & &1.label)
      assert Enum.all?(interior, &(&1.x > 10 and &1.x < 86))
    end

    test "within days, the ends go to the minute" do
      ticks = ticks(~U[2024-04-09 08:15:00Z], ~U[2024-04-09 14:40:00Z])

      assert List.first(ticks).label == "Apr 9 08:15"
      assert List.last(ticks).label == "Apr 9 14:40"
    end

    test "the grain follows the window, so narrowing the range re-labels the axis" do
      # The same axis, read at five widths.
      assert labels(~U[2000-01-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]) |> hd() =~ ~r/^\d{4}$/

      assert labels(~U[2024-01-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]) |> hd() =~
               ~r/^[A-Z][a-z]{2} \d{4}$/

      assert labels(~U[2024-04-09 00:00:00Z], ~U[2024-08-13 00:00:00Z]) == [
               "May 2024",
               "Jun 2024",
               "Jul 2024"
             ]

      assert labels(~U[2024-04-09 00:00:00Z], ~U[2024-04-14 00:00:00Z]) |> hd() == "Apr 10, 2024"
      assert labels(~U[2024-04-09 08:00:00Z], ~U[2024-04-09 14:00:00Z]) |> hd() == "Apr 9 09:00"
    end

    test "never more labels than a thin band can hold" do
      for days <- [1, 3, 10, 45, 200, 900, 5000, 40_000] do
        to = DateTime.add(~U[2024-04-09 00:00:00Z], days * 86_400, :second)
        count = length(ticks(~U[2024-04-09 00:00:00Z], to))

        assert count in 2..10, "#{days} days produced #{count} ticks"
      end
    end

    test "a window of one instant still names its day" do
      ticks = [event("a", ~U[2024-04-09 12:00:00Z])] |> Timeline.build() |> Timeline.ticks()

      assert ticks == [%{x: 50.0, label: "Apr 9, 2024", edge: :only}]
    end

    test "ticks stay inside the band at every grain" do
      for days <- [1, 10, 200, 5000] do
        to = DateTime.add(~U[2024-04-09 07:30:00Z], days * 86_400, :second)

        ticks =
          [event("a", ~U[2024-04-09 07:30:00Z]), event("b", to)]
          |> Timeline.build()
          |> Timeline.ticks()

        assert Enum.all?(ticks, &(&1.x >= 0 and &1.x <= 100))
      end
    end

    test "an empty band has no ticks" do
      assert Timeline.ticks(Timeline.build([])) == []
    end
  end
end
