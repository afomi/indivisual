defmodule IndivisualWeb.AtlasStripTest do
  @moduledoc """
  The two caps at the ends of the sticky timeline say how much of the record
  lies outside the view. They must agree with each other: every activity held
  back belongs to exactly one side, and neither cap may claim the record ends
  while activities are in fact filtered out.
  """
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias IndivisualWeb.AtlasLive

  setup do
    all = Feed.events(Feed, [])
    %{all: all, ms: &DateTime.to_unix(Event.effective_time(&1), :millisecond)}
  end

  test "nothing filtered means nothing beyond either end", %{all: all} do
    %{beyond: beyond} = AtlasLive.strip_payload(all, all, nil)

    assert beyond.earlier == 0
    assert beyond.later == 0
  end

  test "dropping the earliest activities is reported on the EARLIER side", %{all: all} do
    # Regression: this counted 0. Twelve activities share one instant, so
    # `time < focus.from` finds none of them when the dropped ones sit at
    # exactly that instant, and the cap read "the record starts here".
    %{beyond: beyond} = AtlasLive.strip_payload(all, Enum.drop(all, 3), nil)

    assert beyond.earlier == 3
    assert beyond.later == 0
  end

  test "dropping the latest activities is reported on the LATER side", %{all: all} do
    %{beyond: beyond} = AtlasLive.strip_payload(all, Enum.drop(all, -3), nil)

    assert beyond.earlier == 0
    assert beyond.later == 3
  end

  test "a middle slice reports both sides", %{all: all} do
    %{beyond: beyond} = AtlasLive.strip_payload(all, Enum.slice(all, 3..-4//1), nil)

    assert beyond.earlier == 3
    assert beyond.later == 3
  end

  test "the two sides account for every held-back activity, exactly once", %{all: all, ms: ms} do
    reads = [
      Enum.drop(all, 3),
      Enum.drop(all, -3),
      Enum.slice(all, 3..-4//1),
      Enum.take(all, 1),
      # The hard case: a view one instant wide, shared by many activities.
      all |> Enum.filter(&(ms.(&1) == all |> Enum.map(ms) |> Enum.min())) |> Enum.take(2)
    ]

    for read <- reads do
      %{beyond: beyond} = AtlasLive.strip_payload(all, read, nil)
      held_back = length(all) - length(read)

      assert beyond.earlier + beyond.later == held_back,
             "expected the caps to sum to #{held_back}, got #{beyond.earlier} + #{beyond.later}"
    end
  end

  test "an empty read reports the whole record as beyond", %{all: all} do
    %{beyond: beyond} = AtlasLive.strip_payload(all, [], nil)

    assert beyond.earlier + beyond.later == 0,
           "with nothing read there is no span to be outside of"
  end
end
