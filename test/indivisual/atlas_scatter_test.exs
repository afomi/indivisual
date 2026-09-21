defmodule Indivisual.AtlasScatterTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Scatter

  defp event(id) do
    Event.new!(%{
      "event_id" => id,
      "source_id" => "test",
      "stream_id" => "test",
      "sequence" => [1],
      "event_type" => "test.thing.happened",
      "observed_at" => "2026-01-01T00:00:00Z",
      "object" => ["thing:one"],
      "provenance" => %{"uri" => "https://example.test/#{id}"}
    })
  end

  describe "a reader looks at the volume" do
    test "every event in view has exactly one point, in event order" do
      events = Enum.map(~w(evt:a evt:b evt:c), &event/1)

      assert Enum.map(Scatter.build(events).points, & &1.id) == ~w(evt:a evt:b evt:c)
    end

    test "every point sits inside the volume" do
      points = 1..200 |> Enum.map(&event("evt:#{&1}")) |> Scatter.build() |> Map.fetch!(:points)

      for p <- points, c <- [p.x, p.y, p.z] do
        assert c >= -1.0 and c <= 1.0
      end
    end

    test "a point does not move between reads, or when events are appended" do
      before = Scatter.build([event("evt:a")]).points
      later = Scatter.build([event("evt:a"), event("evt:b")]).points

      assert hd(before) == hd(later)
      assert Scatter.position("evt:a") == Scatter.position("evt:a")
    end

    test "different events land in different places" do
      places = 1..200 |> Enum.map(&Scatter.position("evt:#{&1}")) |> Enum.uniq()

      assert length(places) == 200
    end

    test "there are three axes, each an opposition between two named poles" do
      axes = Scatter.axes()

      assert Enum.map(axes, & &1.id) == ~w(x y z)

      for axis <- axes do
        assert is_binary(axis.negative) and axis.negative != ""
        assert is_binary(axis.positive) and axis.positive != ""
        assert axis.negative != axis.positive
      end
    end

    test "the read model admits its positions mean nothing yet" do
      assert Scatter.build([]).basis == :placeholder
      assert Scatter.build([]).points == []
    end
  end
end
