defmodule IndivisualWeb.AtlasScatterTest do
  @moduledoc """
  `AtlasComponents.space/1` — the 3D scatter — is **unmounted** (see the register
  in `IndivisualWeb.AtlasComponents`), so nothing on a page would notice it
  rotting. It is drawn by a hook, so what can be tested is the contract the hook
  is handed: one point per event, three axes, where the selection stands — and
  that the component admits the positions are placeholders.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Scatter
  alias IndivisualWeb.AtlasComponents

  defp space(events, opts \\ []) do
    render_component(&AtlasComponents.space/1, %{
      scatter: Scatter.build(events),
      events: events,
      selected: opts[:selected],
      selected_index: opts[:selected_index]
    })
  end

  defp data(html, attr) do
    [json] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#atlas-scatter")
      |> LazyHTML.attribute(attr)

    Jason.decode!(json)
  end

  test "it is off the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    refute has_element?(view, "#atlas-scatter-wrap")
  end

  test "the stage is hooked and owns its own DOM" do
    html = space(Feed.events())

    assert html =~ ~s(id="atlas-scatter")
    assert html =~ "phx-hook"
    assert html =~ ~s(phx-update="ignore")
  end

  test "there is one point for every event it is given" do
    events = Feed.events()
    points = events |> space() |> data("data-points")

    assert length(points) == length(events)

    for p <- points do
      assert is_binary(p["title"]) and p["title"] != ""
      assert p["color"] =~ ~r/^#[0-9a-f]{6}$/
      for c <- ["x", "y", "z"], do: assert(p[c] >= -1 and p[c] <= 1)
    end
  end

  test "fewer events is a smaller volume, and the heading counts them" do
    html = Feed.events() |> Enum.take(2) |> space()

    assert length(data(html, "data-points")) == 2
    assert html =~ "· 2 events"
  end

  test "three axes, each with two poles" do
    assert [%{"negative" => _, "positive" => _}, _, _] =
             Feed.events() |> space() |> data("data-axes")
  end

  test "the selected event is marked, and later ones are dimmed" do
    [first, second | _] = events = Feed.events()

    points = events |> space(selected: second, selected_index: 1) |> data("data-points")

    assert [%{"id" => id}] = Enum.filter(points, & &1["selected"])
    assert id == second.event_id

    refute Enum.find(points, &(&1["id"] == first.event_id))["future"]
    assert points |> Enum.drop(2) |> Enum.all?(& &1["future"])
  end

  test "the host still selects an event the way the hook would push it", %{conn: conn} do
    [first | _] = Feed.events()
    {:ok, view, _} = live(conn, ~p"/atlas")

    render_hook(view, "select_event", %{"id" => first.event_id})

    assert assert_patch(view) =~ "event=#{URI.encode_www_form(first.event_id)}"
  end

  test "it says the positions mean nothing yet" do
    assert Feed.events() |> space() =~ "placeholders"
  end
end
