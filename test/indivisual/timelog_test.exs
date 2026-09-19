defmodule Indivisual.TimelogTest do
  @moduledoc """
  The timelog is the app's first user-owned data, so these cover two things:
  that intervals behave (an entry with no end is still true), and that one
  person's rows are unreachable from another person's scope.
  """
  use Indivisual.DataCase, async: true

  import Indivisual.AccountsFixtures
  import Indivisual.TimelogFixtures

  alias Indivisual.Timelog
  alias Indivisual.Timelog.Entry

  setup do
    %{scope: user_scope_fixture(), other: user_scope_fixture()}
  end

  describe "create_entry/2" do
    test "creates an entry owned by the scope's user", %{scope: scope} do
      assert {:ok, %Entry{} = entry} =
               Timelog.create_entry(scope, valid_entry_attributes())

      assert entry.user_id == scope.user.id
      assert entry.kind == "work"
    end

    test "ignores a user_id in the params", %{scope: scope, other: other} do
      # The attack this guards: hand in someone else's id and see if it sticks.
      attrs = valid_entry_attributes(%{"user_id" => other.user.id})

      assert {:ok, entry} = Timelog.create_entry(scope, attrs)
      assert entry.user_id == scope.user.id
      refute entry.user_id == other.user.id
    end

    test "requires kind, title and a start", %{scope: scope} do
      assert {:error, changeset} = Timelog.create_entry(scope, %{})
      errors = errors_on(changeset)

      assert %{kind: ["can't be blank"]} = errors
      assert %{title: ["can't be blank"]} = errors
      assert %{valid_from: ["can't be blank"]} = errors
    end

    test "rejects an unknown kind", %{scope: scope} do
      attrs = valid_entry_attributes(%{"kind" => "napping"})
      assert {:error, changeset} = Timelog.create_entry(scope, attrs)
      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects an interval that ends before it starts", %{scope: scope} do
      attrs = valid_entry_attributes(%{"valid_from" => at(0), "valid_to" => at(-60)})
      assert {:error, changeset} = Timelog.create_entry(scope, attrs)
      assert %{valid_to: ["must be at or after the start"]} = errors_on(changeset)
    end

    test "accepts each log kind", %{scope: scope} do
      for kind <- Entry.kinds() do
        attrs = valid_entry_attributes(%{"kind" => kind})
        assert {:ok, %Entry{kind: ^kind}} = Timelog.create_entry(scope, attrs)
      end
    end
  end

  describe "geo validation" do
    test "accepts coordinates in range", %{scope: scope} do
      attrs = valid_entry_attributes(%{"geo" => %{"lat" => 38.3566, "lng" => -121.955}})
      assert {:ok, entry} = Timelog.create_entry(scope, attrs)
      assert entry.geo == %{"lat" => 38.3566, "lng" => -121.955}
    end

    test "rejects out-of-range and non-numeric coordinates", %{scope: scope} do
      for geo <- [
            %{"lat" => 91.0, "lng" => 0.0},
            %{"lat" => 0.0, "lng" => 181.0},
            %{"lat" => "38.3", "lng" => -121.9},
            %{"lat" => 38.3}
          ] do
        attrs = valid_entry_attributes(%{"geo" => geo})
        assert {:error, changeset} = Timelog.create_entry(scope, attrs)
        assert Map.has_key?(errors_on(changeset), :geo), "expected #{inspect(geo)} to be rejected"
      end
    end
  end

  describe "start_entry/4 and close_entry/3" do
    test "starts open-ended, then closes", %{scope: scope} do
      assert {:ok, entry} = Timelog.start_entry(scope, "reading", "Seeing Like a State")
      assert is_nil(entry.valid_to), "a started entry stays open until closed"

      assert {:ok, closed} = Timelog.close_entry(scope, entry)
      assert closed.valid_to
      assert DateTime.compare(closed.valid_to, closed.valid_from) in [:gt, :eq]
    end

    test "refuses to close before the start", %{scope: scope} do
      {:ok, entry} = Timelog.start_entry(scope, "work", "a thing")
      assert {:error, changeset} = Timelog.close_entry(scope, entry, at(-3600))
      assert %{valid_to: ["must be at or after the start"]} = errors_on(changeset)
    end
  end

  describe "at/2 — what was true at T" do
    test "an open entry is true at every instant after it began", %{scope: scope} do
      {:ok, entry} = Timelog.start_entry(scope, "work", "ongoing", %{"valid_from" => at(-3600)})

      for offset <- [-1800, 0, 3600, 86_400] do
        ids = scope |> Timelog.at(at(offset)) |> Enum.map(& &1.id)
        assert entry.id in ids, "open entry should be true at offset #{offset}"
      end
    end

    test "an open entry is not true before it began", %{scope: scope} do
      {:ok, entry} = Timelog.start_entry(scope, "work", "later", %{"valid_from" => at(3600)})
      refute entry.id in (scope |> Timelog.at(at(0)) |> Enum.map(& &1.id))
    end

    test "a closed entry is true only inside its interval", %{scope: scope} do
      entry = closed_entry_fixture(scope, at(-3600), at(-1800))

      assert entry.id in (scope |> Timelog.at(at(-2700)) |> Enum.map(& &1.id))
      refute entry.id in (scope |> Timelog.at(at(-7200)) |> Enum.map(& &1.id))
      refute entry.id in (scope |> Timelog.at(at(0)) |> Enum.map(& &1.id))
    end

    test "the end is exclusive", %{scope: scope} do
      boundary = at(-1800)
      entry = closed_entry_fixture(scope, at(-3600), boundary)
      refute entry.id in (scope |> Timelog.at(boundary) |> Enum.map(& &1.id))
    end
  end

  describe "list_entries/2" do
    test "filters by kind", %{scope: scope} do
      reading = entry_fixture(scope, %{"kind" => "reading"})
      _work = entry_fixture(scope, %{"kind" => "work"})

      assert [found] = Timelog.list_entries(scope, kind: "reading")
      assert found.id == reading.id
    end

    test "a window includes an open entry that began before it", %{scope: scope} do
      {:ok, entry} = Timelog.start_entry(scope, "work", "long", %{"valid_from" => at(-86_400)})

      ids = scope |> Timelog.list_entries(from: at(-3600), to: at(0)) |> Enum.map(& &1.id)
      assert entry.id in ids, "an ongoing entry overlaps every later window"
    end

    test "a window excludes an entry that closed before it", %{scope: scope} do
      entry = closed_entry_fixture(scope, at(-86_400), at(-80_000))
      ids = scope |> Timelog.list_entries(from: at(-3600), to: at(0)) |> Enum.map(& &1.id)
      refute entry.id in ids
    end
  end

  describe "list_open/1" do
    test "returns only entries with no end", %{scope: scope} do
      {:ok, open} = Timelog.start_entry(scope, "work", "open")
      closed = closed_entry_fixture(scope, at(-3600), at(-1800))

      ids = scope |> Timelog.list_open() |> Enum.map(& &1.id)
      assert open.id in ids
      refute closed.id in ids
    end
  end

  describe "list_located/2" do
    test "returns only entries carrying coordinates", %{scope: scope} do
      located = entry_fixture(scope, %{"geo" => %{"lat" => 38.3566, "lng" => -121.955}})
      plain = entry_fixture(scope)

      ids = scope |> Timelog.list_located() |> Enum.map(& &1.id)
      assert located.id in ids
      refute plain.id in ids
    end
  end

  describe "scope isolation" do
    # The regression test USER_SCOPING.md asks for: user A must not reach
    # user B's rows through ANY public read.
    setup %{scope: scope, other: other} do
      mine = entry_fixture(scope, %{"geo" => %{"lat" => 1.0, "lng" => 2.0}})
      theirs = entry_fixture(other, %{"geo" => %{"lat" => 3.0, "lng" => 4.0}})
      %{mine: mine, theirs: theirs}
    end

    test "list_entries/2 returns only my rows", %{scope: scope, mine: mine, theirs: theirs} do
      ids = scope |> Timelog.list_entries() |> Enum.map(& &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end

    test "at/2 returns only my rows", %{scope: scope, mine: mine, theirs: theirs} do
      ids = scope |> Timelog.at(at(1)) |> Enum.map(& &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end

    test "list_open/1 returns only my rows", %{scope: scope, mine: mine, theirs: theirs} do
      ids = scope |> Timelog.list_open() |> Enum.map(& &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end

    test "list_located/2 returns only my rows", %{scope: scope, mine: mine, theirs: theirs} do
      ids = scope |> Timelog.list_located() |> Enum.map(& &1.id)
      assert mine.id in ids
      refute theirs.id in ids
    end

    test "get_entry/2 cannot fetch another person's entry", %{scope: scope, theirs: theirs} do
      refute Timelog.get_entry(scope, theirs.id)
    end

    test "count_entries/2 counts only my rows", %{scope: scope, other: other} do
      assert Timelog.count_entries(scope) == 1
      assert Timelog.count_entries(other) == 1
    end
  end

  describe "capture/3 — the written line" do
    test "a line becomes a structured entry", %{scope: scope} do
      {:ok, entry} =
        Timelog.capture(scope, "worked on trail easement 9-10:30", now: ~U[2026-09-19 14:00:00Z])

      assert entry.kind == "work"
      assert entry.title == "trail easement"
      assert entry.valid_from == ~U[2026-09-19 09:00:00Z]
      assert entry.valid_to == ~U[2026-09-19 10:30:00Z]
      assert entry.user_id == scope.user.id
    end

    test "the exact text typed is kept, so parsing can never lose it", %{scope: scope} do
      line = "worked on something odd 9-10:30"
      {:ok, entry} = Timelog.capture(scope, line)

      assert entry.payload["source_line"] == line
    end

    test "notes are stored as prose, unparsed", %{scope: scope} do
      {:ok, entry} =
        Timelog.capture(scope, "met with planning dept 2-3pm", notes: "trail easement, phase 2")

      assert entry.payload["notes"] == "trail easement, phase 2"
    end

    test "a line with no time stays open", %{scope: scope} do
      {:ok, entry} = Timelog.capture(scope, "reading Seeing Like a State")

      assert entry.kind == "reading"
      assert is_nil(entry.valid_to)
    end

    test "a blank line is refused", %{scope: scope} do
      assert {:error, :blank} = Timelog.capture(scope, "   ")
    end

    test "captured entries are owned and isolated", %{scope: scope, other: other} do
      {:ok, mine} = Timelog.capture(scope, "ran 5k")

      refute mine.id in (other |> Timelog.list_entries() |> Enum.map(& &1.id))
    end
  end

  describe "pubsub" do
    test "broadcasts on the owner's own topic", %{scope: scope} do
      Timelog.subscribe(scope)
      {:ok, entry} = Timelog.start_entry(scope, "work", "broadcast me")

      assert_receive {:timelog, :created, %Entry{id: id}}
      assert id == entry.id
    end

    test "the topic is per-user", %{scope: scope, other: other} do
      refute Timelog.topic(scope) == Timelog.topic(other)
    end

    test "a write does not reach another person's topic", %{scope: scope, other: other} do
      Timelog.subscribe(other)
      {:ok, _} = Timelog.start_entry(scope, "work", "not yours")

      refute_receive {:timelog, _, _}, 100
    end
  end
end
