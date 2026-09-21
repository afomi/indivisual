defmodule IndivisualWeb.AtlasReaderStepTest do
  @moduledoc """
  Prev / Next at the top of the reader column: the same steps as the timeline's
  pair, offered where the record is being read.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed

  defp selected_id(view) do
    view
    |> element("#atlas-selected-id .atlas-ref--id")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("title")
  end

  test "the buttons sit at the top of the reader, above the record", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-reader > #atlas-reader-step")

    at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end
    assert at.("atlas-reader-step") < at.("atlas-selected")
  end

  test "Next and Prev move the selection one event at a time", %{conn: conn} do
    [first, second | _] = Feed.events()
    {:ok, view, _} = live(conn, ~p"/atlas?event=#{first.event_id}")

    view |> element("#atlas-reader-next") |> render_click()
    assert selected_id(view) == [second.event_id]

    view |> element("#atlas-reader-prev") |> render_click()
    assert selected_id(view) == [first.event_id]
  end

  test "they do what the timeline's buttons do", %{conn: conn} do
    [first | _] = Feed.events()
    {:ok, by_reader, _} = live(conn, ~p"/atlas?event=#{first.event_id}")
    {:ok, by_timeline, _} = live(conn, ~p"/atlas?event=#{first.event_id}")

    by_reader |> element("#atlas-reader-next") |> render_click()
    by_timeline |> element(~s(#atlas-timeline button[phx-value-dir="next"])) |> render_click()

    assert selected_id(by_reader) == selected_id(by_timeline)
  end

  test "at either end the button is disabled, not silently inert", %{conn: conn} do
    events = Feed.events()
    {:ok, at_start, _} = live(conn, ~p"/atlas?event=#{hd(events).event_id}")
    {:ok, at_end, _} = live(conn, ~p"/atlas?event=#{List.last(events).event_id}")

    assert has_element?(at_start, "#atlas-reader-prev[disabled]")
    refute has_element?(at_start, "#atlas-reader-next[disabled]")

    assert has_element?(at_end, "#atlas-reader-next[disabled]")
    refute has_element?(at_end, "#atlas-reader-prev[disabled]")
  end
end
