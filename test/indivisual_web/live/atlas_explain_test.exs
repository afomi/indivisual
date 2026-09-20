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

  test "the offer follows the record's fields and sits right above annotation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    at = fn marker -> html |> :binary.match(marker) |> elem(0) end

    assert at.(~s(class="atlas-fields")) < at.(~s(id="atlas-explain-event"))
    assert at.(~s(id="atlas-explain-event")) < at.(~s(id="atlas-annotation-form"))
  end

  test "asking produces an explanation of the selected record", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    view |> element("#atlas-explain-event") |> render_click()

    # The Fake adapter answers synchronously; the result arrives as a message.
    assert render_async(view) =~ "This record describes"
    assert has_element?(view, "#atlas-explain-result")
  end

  describe "while it is working" do
    test "the loading state announces itself to assistive tech", %{conn: conn} do
      # The Fake adapter answers immediately, so drive the assign directly to
      # see the state a real model's 3-8 seconds would show.
      {:ok, view, _} = live(conn, ~p"/atlas")

      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      html = render(view)

      assert html =~ "atlas-explain-loading"
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-busy="true")
      assert html =~ "Reading the record"
    end

    test "the wait shows a skeleton, not a bare line of text", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      assert has_element?(view, ".atlas-explain__skeleton"),
             "a multi-second wait needs to show that work is moving"
    end

    test "a slow wait can be cancelled", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      assert has_element?(view, "#atlas-explain-loading")

      view
      |> element(~s(#atlas-explain-loading button[phx-click="hide_explain_event"]))
      |> render_click()

      refute has_element?(view, "#atlas-explain-loading")
    end

    test "the trigger disables itself while working", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert view |> element("#atlas-explain-event") |> render() =~ "phx-disable-with",
             "a slow action must not look idle after it is clicked"
    end
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
    view |> element("#atlas-activity-0 button") |> render_click()
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
