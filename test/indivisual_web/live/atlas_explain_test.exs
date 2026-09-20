defmodule IndivisualWeb.AtlasExplainTest do
  @moduledoc """
  "Explain this record" runs off the LiveView process so a slow model never
  blocks the page. These cover the offer, the result, and the two ways it must
  not mislead: generated prose is labelled as generated, and a result that
  arrives after the reader has moved on is dropped rather than shown against
  the wrong record.
  """
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Indivisual.Explain.Cache

  setup do
    Cache.clear()
    :ok
  end

  test "the card offers an explanation", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-explain-event")
  end

  test "asking produces an explanation of the selected record", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-explain-event") |> render_click()

    # The Fake adapter answers synchronously; the result arrives as a message.
    assert render_async(view) =~ "This record describes"
    assert has_element?(view, "#atlas-explain-result")
  end

  test "generated prose is labelled as generated", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-explain-event") |> render_click()
    html = render_async(view)

    assert html =~ "language model"
    assert html =~ "the record is the source"
  end

  test "it can be hidden again", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-explain-event") |> render_click()
    render_async(view)
    assert has_element?(view, "#atlas-explain-result")

    view |> element(~s(button[phx-click="hide_explain_event"])) |> render_click()
    refute has_element?(view, "#atlas-explain-result")
  end

  test "changing the selected record clears the explanation", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-explain-event") |> render_click()
    render_async(view)
    assert has_element?(view, "#atlas-explain-result")

    # Move to a different event.
    view |> form("#atlas-scrubber", %{"index" => "0"}) |> render_change()
    assert_patch(view)

    refute has_element?(view, "#atlas-explain-result"),
           "an explanation must not outlive the record it described"
  end

  test "a result for a record no longer selected is dropped", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    # A result arriving for some other event must not render.
    send(view.pid, {:explanation, "evt:not-the-one", {:ok, "STALE TEXT"}})

    refute render(view) =~ "STALE TEXT"
  end
end
