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
      "subject_refs" => ["thing:one"],
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

    test "lanes reports the actual depth used" do
      t = ~U[2024-01-01 00:00:00Z]
      assert %{lanes: 2} = Timeline.build([event("a", t), event("b", t)], lanes: 6)
    end
  end

  describe "ticks" do
    test "are quarterly and inside the band" do
      events = [
        event("a", ~U[2024-01-01 00:00:00Z]),
        event("b", ~U[2026-01-01 00:00:00Z])
      ]

      ticks = events |> Timeline.build() |> Timeline.ticks()

      assert length(ticks) > 0
      assert Enum.all?(ticks, &(&1.x >= 0 and &1.x <= 100))
      assert Enum.all?(ticks, &(&1.label =~ ~r/^(Jan|Apr|Jul|Oct) \d{4}$/))
    end

    test "an empty band has no ticks" do
      assert Timeline.ticks(Timeline.build([])) == []
    end
  end
end
