defmodule Indivisual.AtlasMAPTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Capture
  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.MAP

  defp event(line \\ "met Jane Doe at Carroll Way yesterday 3pm") do
    {:ok, draft} = Capture.parse(line, now: ~U[2026-09-20 17:30:00Z])
    {:ok, events} = Capture.to_events(draft, "Afomi", now: ~U[2026-09-20 17:30:00Z])
    events |> List.last() |> Event.new!()
  end

  test "`app` and `type` lead, and the type carries a version" do
    assert [{"app", "indivisual"}, {"type", "log_v1"} | _] = MAP.pairs(event())
  end

  test "every other key follows in sorted order, so the same event is the same bytes" do
    [_, _ | rest] = MAP.pairs(event())
    keys = Enum.map(rest, &elem(&1, 0))

    assert keys == Enum.sort(keys)
    assert MAP.pushes(event()) == MAP.pushes(event())
  end

  test "who, did what, to what, when — as strings" do
    pairs = Map.new(MAP.pairs(event()))

    assert pairs["actor"] == "person:afomi"
    assert pairs["verb"] == "met"
    assert pairs["object"] == "person:jane-doe,place:carroll-way"
    assert pairs["timestamp"] == Integer.to_string(DateTime.to_unix(~U[2026-09-19 15:00:00Z]))
    assert pairs["data_hash"] =~ ~r/^[0-9a-f]{64}$/
  end

  test "what a person wrote never goes on chain: refs, a time and a hash only" do
    flat = event() |> MAP.pushes() |> Enum.join(" ")

    refute flat =~ "yesterday"
    refute flat =~ "Jane Doe"
  end

  test "absent fields are omitted, never written empty" do
    refute Enum.any?(MAP.pairs(event()), fn {_key, value} -> value in [nil, ""] end)
  end

  test "the pushdata list is MAP's: prefix, SET, then key-value pairs" do
    [prefix, action | rest] = MAP.pushes(event())

    assert prefix == MAP.prefix()
    assert action == "SET"
    assert rem(length(rest), 2) == 0
  end

  test "hex is the wallet's `data` argument: one lowercase hex string per push" do
    hex = MAP.hex(event())

    assert length(hex) == length(MAP.pushes(event()))
    assert Enum.all?(hex, &(&1 =~ ~r/^[0-9a-f]+$/))
    assert hex |> hd() |> Base.decode16!(case: :lower) == MAP.prefix()
  end

  test "it is small: a few hundred bytes" do
    assert MAP.byte_size(event()) in 150..500
  end
end
