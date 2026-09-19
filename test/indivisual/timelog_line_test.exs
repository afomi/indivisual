defmodule Indivisual.Timelog.LineTest do
  @moduledoc """
  The line is the capture interface, so these pin the shapes people actually
  write — including the ones that must NOT be over-parsed. A line that loses
  what someone typed is worse than one that mis-files it.
  """
  use ExUnit.Case, async: true

  alias Indivisual.Timelog.Line

  # Fixed "now" so the same line parses identically at any hour.
  @now ~U[2026-09-19 14:00:00Z]

  defp parse(line, notes \\ nil), do: Line.parse(line, @now, notes)

  describe "the user's own format" do
    test "worked on X from a to b" do
      {:ok, p} = parse("worked on trail easement 9-10:30")

      assert p.kind == "work"
      assert p.title == "trail easement"
      assert p.valid_from == ~U[2026-09-19 09:00:00Z]
      assert p.valid_to == ~U[2026-09-19 10:30:00Z]
    end

    test "notes ride along as text, unparsed" do
      {:ok, p} = parse("worked on easement 9-10:30", "met with planning dept")
      assert p.notes == "met with planning dept"
    end

    test "blank notes become nil rather than an empty string" do
      {:ok, p} = parse("ran 5k", "   ")
      assert is_nil(p.notes)
    end
  end

  describe "verbs" do
    test "maps to kinds" do
      for {line, kind} <- [
            {"read Seeing Like a State", "reading"},
            {"ran 5k", "exercise"},
            {"walked the dog", "exercise"},
            {"worked on the plan", "work"},
            {"wrote a memo", "work"},
            {"attended the hearing", "event"},
            {"went to city hall", "event"}
          ] do
        {:ok, p} = parse(line)
        assert p.kind == kind, "#{line} should be #{kind}, got #{p.kind}"
      end
    end

    test "'worked on' beats 'worked' — longest phrase wins" do
      {:ok, p} = parse("worked on the trail")
      assert p.title == "trail"
      refute p.title =~ "on"
    end

    test "an unknown verb keeps the whole line rather than dropping it" do
      {:ok, p} = parse("frobnicated the widget")

      assert p.kind == "work"
      assert p.title == "frobnicated the widget"
      assert is_nil(p.verb)
    end
  end

  describe "clock ranges" do
    test "bare hours" do
      {:ok, p} = parse("worked on x 9-10")
      assert p.valid_from == ~U[2026-09-19 09:00:00Z]
      assert p.valid_to == ~U[2026-09-19 10:00:00Z]
    end

    test "am/pm" do
      {:ok, p} = parse("worked on x 9am-5pm")
      assert p.valid_from == ~U[2026-09-19 09:00:00Z]
      assert p.valid_to == ~U[2026-09-19 17:00:00Z]
    end

    test "'to' reads like the written form" do
      {:ok, p} = parse("worked on x 9:15 to 11:45")
      assert p.valid_from == ~U[2026-09-19 09:15:00Z]
      assert p.valid_to == ~U[2026-09-19 11:45:00Z]
    end

    test "a bare start inherits the end's meridiem" do
      # "2-3pm" is a one-hour afternoon meeting, not thirteen hours from 02:00.
      {:ok, p} = parse("met with planning dept 2-3pm")

      assert p.valid_from == ~U[2026-09-19 14:00:00Z]
      assert p.valid_to == ~U[2026-09-19 15:00:00Z]
      assert DateTime.diff(p.valid_to, p.valid_from, :second) == 3600
    end

    test "an explicit start meridiem is not overridden" do
      {:ok, p} = parse("worked on x 11am-2pm")
      assert p.valid_from == ~U[2026-09-19 11:00:00Z]
      assert p.valid_to == ~U[2026-09-19 14:00:00Z]
    end

    test "a range crossing midnight lands on the next day" do
      {:ok, p} = parse("worked on x 11pm-1am")
      assert p.valid_from == ~U[2026-09-19 23:00:00Z]
      assert p.valid_to == ~U[2026-09-20 01:00:00Z]
    end

    test "12am is midnight and 12pm is noon" do
      {:ok, a} = parse("worked on x 12am-1am")
      assert a.valid_from == ~U[2026-09-19 00:00:00Z]

      {:ok, b} = parse("worked on x 12pm-1pm")
      assert b.valid_from == ~U[2026-09-19 12:00:00Z]
    end

    test "an impossible clock time is left as title text, not invented" do
      {:ok, p} = parse("worked on x 99-100")
      assert p.title =~ "99"
      assert is_nil(p.valid_to)
    end
  end

  describe "durations" do
    test "a duration ends now and backdates the start" do
      {:ok, p} = parse("read Seeing Like a State 45m")

      assert p.title == "Seeing Like a State"
      assert p.valid_to == @now
      assert p.valid_from == ~U[2026-09-19 13:15:00Z]
    end

    test "hours and compound hours" do
      {:ok, a} = parse("worked on x 2h")
      assert a.valid_from == ~U[2026-09-19 12:00:00Z]

      {:ok, b} = parse("worked on x 1h30")
      assert b.valid_from == ~U[2026-09-19 12:30:00Z]
    end
  end

  describe "open-ended by default" do
    test "no time means it starts now and stays open" do
      {:ok, p} = parse("ran 5k")

      assert p.valid_from == @now
      assert is_nil(p.valid_to), "an entry with no stated end is still running"
    end
  end

  describe "titles that must not be mangled" do
    test "a number in the title is not mistaken for a time" do
      {:ok, p} = parse("ran 5k")
      assert p.title == "5k"
    end

    test "a title containing a year survives" do
      {:ok, p} = parse("read 1984")
      assert p.title == "1984"
      assert is_nil(p.valid_to)
    end

    test "a blank line is an error, not an empty entry" do
      assert Line.parse("   ", @now) == {:error, :blank}
      assert Line.parse("", @now) == {:error, :blank}
    end
  end

  describe "determinism" do
    test "the same line parses identically regardless of wall clock" do
      {:ok, a} = Line.parse("worked on x 9-10:30", ~U[2026-09-19 23:59:00Z])
      {:ok, b} = Line.parse("worked on x 9-10:30", ~U[2026-09-19 00:01:00Z])

      assert a.valid_from == b.valid_from
      assert a.valid_to == b.valid_to
    end
  end
end
