defmodule Indivisual.AtlasCaptureTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Capture
  alias Indivisual.Atlas.Event

  @now ~U[2026-09-20 17:30:00Z]

  @entities %{
    "place:carroll-way" => %{
      ref: "place:carroll-way",
      label: "Carroll Way alignment",
      kind: "place"
    },
    "body:parks" => %{ref: "body:parks", label: "Parks and Recreation Commission", kind: "body"}
  }

  defp parse(line, opts \\ []) do
    {:ok, draft} = Capture.parse(line, Keyword.merge([now: @now, entities: @entities], opts))
    draft
  end

  defp refs(draft), do: Enum.map(draft.objects, & &1.ref)

  describe "a line is who · did what · to what · when" do
    test "verb from the front, time from the end, things in between" do
      draft = parse("met Jane Doe at Carroll Way yesterday 3pm")

      assert draft.verb == "met"
      assert refs(draft) == ["person:jane-doe", "place:carroll-way"]
      assert draft.occurred_at == ~U[2026-09-19 15:00:00Z]
      assert draft.timed?
    end

    test "the longest verb phrase wins" do
      assert parse("met with Bo").phrase == "met with"
      assert parse("went to the park").verb == "went-to"
    end

    test "an ActivityStreams verb is recorded only where one is exact" do
      assert parse("read the staff report").as2 == "Read"
      assert parse("attended a hearing").as2 == "Join"
      assert parse("met Bo").as2 == nil
    end

    test "a blank line is nothing" do
      assert Capture.parse("   ", now: @now) == {:error, :blank}
    end
  end

  describe "time, on the caller's clock" do
    test "no time typed means now" do
      draft = parse("read the staff report")

      assert draft.occurred_at == @now
      refute draft.timed?
    end

    test "a date and a clock time, in either order" do
      assert parse("met Bo 2026-09-09 18:30").occurred_at == ~U[2026-09-09 18:30:00Z]
      assert parse("met Bo 6:30pm 2026-09-09").occurred_at == ~U[2026-09-09 18:30:00Z]
      assert parse("went to the park at 9:15am today").occurred_at == ~U[2026-09-20 09:15:00Z]
    end

    test "noon and midnight" do
      assert parse("met Bo today 12pm").occurred_at == ~U[2026-09-20 12:00:00Z]
      assert parse("met Bo today 12am").occurred_at == ~U[2026-09-20 00:00:00Z]
    end

    test "a bare number is a quantity, not a time" do
      draft = parse("ran 5")

      refute draft.timed?
      assert draft.objects == []
    end

    test "an impossible date does not crash the line" do
      assert %{occurred_at: %DateTime{}} = parse("met Bo 2026-13-40")
    end
  end

  describe "things: linked to the record, or new" do
    test "a name the record knows links to it, by label" do
      [object] = parse("attended Parks and Recreation Commission").objects

      assert object.ref == "body:parks"
      assert object.known?
    end

    test "a known label is one thing, whatever words are in it" do
      assert refs(parse("attended Parks and Recreation Commission with Jane Doe")) ==
               ["body:parks", "person:jane-doe"]
    end

    test "a name matches the ref's name too, so a line never re-mints an existing ref" do
      # The record labels it "Carroll Way alignment"; the ref is place:carroll-way.
      [_, place] = parse("met Jane Doe at Carroll Way").objects

      assert place.ref == "place:carroll-way"
      assert place.known?
      assert place.label == "Carroll Way alignment"
    end

    test "`at` is a place, `with` is a person, and `and` carries on" do
      draft = parse("walked the creek path with Jane Doe and Bo")

      assert Enum.map(draft.objects, &{&1.ref, &1.kind}) == [
               {"place:creek-path", "place"},
               {"person:jane-doe", "person"},
               {"person:bo", "person"}
             ]
    end

    test "failing a hint, the verb says what its object usually is" do
      assert [%{kind: "person"}] = parse("met Jane Doe").objects
      assert [%{kind: "document"}] = parse("read the staff report").objects
      assert [%{kind: "place"}] = parse("visited the creek").objects
    end

    test "a quantity stays in the title and is not a thing" do
      draft = parse("paid City of Vacaville 40 usd")

      assert refs(draft) == ["body:city-of-vacaville"]
      assert draft.line == "paid City of Vacaville 40 usd"
    end

    test "with no verb the line is a note: only what the record knows is an object" do
      draft = parse("something happened near Carroll Way")

      assert draft.verb == "noted"
      assert is_nil(draft.phrase)
      assert refs(draft) == ["place:carroll-way"]
    end
  end

  describe "what a draft appends" do
    test "a registration for each new thing, then the activity" do
      {:ok, events} = Capture.to_events(parse("met Jane Doe at Carroll Way"), "Afomi", now: @now)

      assert Enum.map(events, & &1["event_type"]) == ["log.entity.registered", "log.met"]
      assert hd(events)["payload"]["entity"]["ref"] == "person:jane-doe"

      activity = List.last(events)
      assert activity["actor"] == "person:afomi"
      assert activity["object"] == ["person:jane-doe", "place:carroll-way"]
      assert activity["truth_state"] == "reported"
      assert activity["payload"]["verb"] == "met"
    end

    test "every event is a valid envelope the store can hold" do
      {:ok, events} = Capture.to_events(parse("met Al, Bo and Cy yesterday"), "Afomi", now: @now)

      for attrs <- events do
        assert {:ok, %Event{sequence: sequence}} = Event.new(attrs)
        assert Enum.all?(sequence, &(&1 < 2_147_483_648)), "sequence must fit the store's int4"
      end
    end

    test "later lines sort after earlier ones" do
      # "the report" is new, so each line is a registration and then the activity.
      {:ok, first} = Capture.to_events(parse("read the report"), "Afomi", now: @now)

      {:ok, second} =
        Capture.to_events(parse("read the report"), "Afomi", now: DateTime.add(@now, 1))

      assert List.last(first)["sequence"] < hd(second)["sequence"]
      # And within one line, the noun comes before the verb that names it.
      assert hd(first)["sequence"] < List.last(first)["sequence"]
    end

    test "an activity that names nothing is about the person who did it" do
      {:ok, [activity]} = Capture.to_events(parse("ran 5k"), "Afomi", now: @now)

      assert activity["object"] == ["person:afomi"]
    end

    test "nobody logs anonymously" do
      assert {:error, [{:author, _}]} = Capture.to_events(parse("met Bo"), "  ")
    end
  end
end
