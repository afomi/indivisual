defmodule IndivisualWeb.AtlasShareTest do
  @moduledoc """
  Sharing is its own element with a copy action. These cover what would
  silently break it: the copied address must be absolute (a bare path is
  useless outside the tab), the hook must actually be attached, and the
  summary must say what the link reproduces.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "share is a distinct element, not a line of link text", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-share")
    assert has_element?(view, "#atlas-share-copy")
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
    {:ok, view, _} = live(conn, ~p"/atlas?projection=provenance&from=1&to=3")

    url = view |> element("#atlas-share-copy") |> render()

    assert url =~ "projection=provenance"
    assert url =~ "from=1"
    assert url =~ "to=3"
  end

  test "the summary says what the link reproduces", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?projection=provenance")

    summary = view |> element(".atlas-share__summary") |> render()

    assert summary =~ "Reproduces:"
    assert summary =~ "Provenance", "the projection should be named"
  end

  test "the summary names a narrowed range", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

    assert view |> element(".atlas-share__summary") |> render() =~ "time range"
  end

  test "the address stays visible for hand-copying", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-share-link")
  end
end
