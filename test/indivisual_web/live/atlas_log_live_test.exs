defmodule IndivisualWeb.AtlasLogLiveTest do
  @moduledoc """
  `/atlas/log`: one line in, one activity out. The parse is shown back before
  anything is written, and what has been logged adds up on the page.
  """
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed

  @moduletag :writes_atlas_feed

  defp type(view, line, author \\ "afomi") do
    view
    |> form("#atlas-log-form", %{"capture" => %{"line" => line, "author" => author}})
    |> render_change()
  end

  defp submit(view, line, author \\ "afomi") do
    view
    |> form("#atlas-log-form", %{"capture" => %{"line" => line, "author" => author}})
    |> render_submit()
  end

  test "the page is linked from the site nav, and opens on the line", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas/log")

    assert html =~ ~s(href="/atlas/log")
    assert has_element?(view, "#atlas-log-line")
    assert has_element?(view, "#atlas-log-submit[disabled]"), "nothing to log yet"
  end

  test "a line is read back as chips before anything is written", %{conn: conn} do
    before = length(Feed.events())
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    type(view, "met Jane Doe at Carroll Way yesterday 3pm")

    assert view |> element("#atlas-log-verb") |> render() =~ "met"
    # New to the record, and already in it: said differently, drawn as their kind.
    assert has_element?(view, ~s(#atlas-log-draft [data-filter="new"] svg[data-kind="person"]))
    assert has_element?(view, ~s(#atlas-log-draft [data-filter="known"] svg[data-kind="place"]))
    assert has_element?(view, "#atlas-log-when")
    refute has_element?(view, "#atlas-log-submit[disabled]")

    assert length(Feed.events()) == before, "typing must not write"
  end

  test "logging appends the activity (and any new thing), and the page shows it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    html = submit(view, "met Jane Doe at Carroll Way yesterday 3pm")

    activity = Enum.find(Feed.events(), &(&1.event_type == "log.met"))
    assert activity.actor == "person:afomi"
    assert activity.object == ["person:jane-doe", "place:carroll-way"]
    assert Enum.any?(Feed.events(), &(&1.payload["entity"]["ref"] == "person:jane-doe"))

    assert html =~ "met Jane Doe at Carroll Way yesterday 3pm"
    assert has_element?(view, ".atlas-log__entry.is-new")
    assert view |> element("#atlas-log-summary") |> render() =~ ~r/1<\/strong>\s*activity/
    assert view |> element("#atlas-log-line") |> render() =~ ~s(value="")
  end

  test "a thing the record already has is linked to, not registered again", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    labels = fn ->
      Feed.events()
      |> Indivisual.Atlas.Topology.entities()
      |> get_in(["place:carroll-way", Access.key(:label)])
    end

    was = labels.()

    submit(view, "visited Carroll Way")

    assert labels.() == was, "logging must not relabel someone else's entity"
    refute Enum.any?(Feed.events(), &(&1.event_type == "log.entity.registered"))
  end

  test "the log is one author's: another name sees their own", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")
    submit(view, "read the staff report", "afomi")

    {:ok, other, _} = live(conn, ~p"/atlas/log")
    type(other, "", "someone-else")

    refute render(other) =~ "read the staff report"
  end

  test "a line with no verb is a note, and the page says so", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    type(view, "something happened")

    assert has_element?(view, "#atlas-log-noverb")
  end

  test "nobody logs without a name", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    type(view, "met Bo", "")

    assert has_element?(view, "#atlas-log-submit[disabled]")
  end

  test "the same activity is shown as transaction data: refs and a hash, no prose", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    type(view, "met Jane Doe at Carroll Way")
    tx = view |> element("#atlas-log-tx") |> render()

    assert tx =~ "log_v1"
    assert tx =~ "person:jane-doe,place:carroll-way"
    refute tx =~ "Jane Doe"
  end

  test "it says plainly that this prototype is public", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas/log")

    assert view |> element("#atlas-log-public") |> render() =~ "public"
  end
end
