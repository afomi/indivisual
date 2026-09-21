defmodule IndivisualWeb.AtlasShareTest do
  @moduledoc """
  A link to this view sits beside the Filters label, because a link to a view
  IS its filters. These cover what would silently break it: the copied address
  must be absolute (a bare path is useless outside the tab), and the hook must
  actually be attached.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the link sits beside the Filters label", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-applied .atlas-applied__action #atlas-share-copy")
  end

  test "the chips say what the link carries, so no sentence repeats them", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas?truth=observed")

    # The filters are named as chips right beside the link.
    assert has_element?(view, "#atlas-applied-truth")

    refute html =~ "Your view state:",
           "the chips already say what the link carries"
  end

  test "the copy button carries an ABSOLUTE url", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    html = view |> element("#atlas-share-copy") |> render()

    assert html =~ ~r/data-url="https?:\/\//,
           "a bare path cannot be pasted anywhere useful"

    assert html =~ "/atlas"
  end

  test "the copy button is wired to a hook", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert view |> element("#atlas-share-copy") |> render() =~ "phx-hook"
  end

  test "the shared url carries the current view state", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?connected=1&from=1&to=3")

    url = view |> element("#atlas-share-copy") |> render()

    assert url =~ "connected=1"
    assert url =~ "from=1"
    assert url =~ "to=3"
  end

  test "copying is its one action, and it says what a link is", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    refute html =~ "Share this view"
    # The same query, not the same screen: another reader gets it their way.
    refute has_element?(view, "#atlas-share-note")
    assert view |> element("#atlas-share-copy") |> render() =~ "same query, shown their way"
  end

  test "it is there whether or not a record is open", %{conn: conn} do
    for path <- [~p"/atlas", ~p"/atlas?event=none", ~p"/atlas?from=1&to=3"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#atlas-share-copy"), path
    end
  end

  test "it is a real link to this very view, so the browser's own link tools work",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?truth=observed")

    assert has_element?(view, ~s(a#atlas-share-copy[href^="http"][href*="truth=observed"]))
    # The address bar already shows the url; it is not printed a second time.
    refute has_element?(view, "#atlas-share-link")
  end
end
