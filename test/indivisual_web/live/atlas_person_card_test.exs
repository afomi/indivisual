defmodule IndivisualWeb.AtlasPersonCardTest do
  @moduledoc """
  A person in focus gets a card in the reader column; every other kind keeps the
  plain heading. People mostly enter the record by writing an annotation, so the
  card is tested on exactly that: an unregistered `person:<author>`.
  """
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Topology

  @moduletag :writes_atlas_feed

  test "focusing a person shows their card, built from what they wrote", %{conn: conn} do
    [about | _] = Feed.events()

    {:ok, _} =
      Atlas.annotate(about.event_id, %{
        "kind" => "question",
        "author" => "afomi",
        "body" => "Why here?"
      })

    {:ok, _} =
      Atlas.annotate(about.event_id, %{
        "kind" => "question",
        "author" => "afomi",
        "body" => "And when?"
      })

    {:ok, view, _} = live(conn, ~p"/atlas?entity=person:afomi")

    assert has_element?(view, "#atlas-entity-context #atlas-person")
    assert has_element?(view, "#atlas-person h2#atlas-entity-context-title", "Afomi")
    assert view |> element("#atlas-person-authored") |> render() =~ "2"
    assert view |> element("#atlas-person-wrote") |> render() =~ "question"
    assert has_element?(view, "#atlas-person-unregistered")

    # The rest of the entity context is still there, under the card.
    assert has_element?(view, "#atlas-entity-context-question")
    assert has_element?(view, "#atlas-entity-context-summary")
  end

  test "any other kind keeps the plain heading", %{conn: conn} do
    ref = Feed.events() |> Topology.relationships() |> hd() |> Map.fetch!(:object)
    {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

    refute has_element?(view, "#atlas-person")
    assert has_element?(view, "h2#atlas-entity-context-title")
    assert has_element?(view, "#atlas-entity-context .atlas-record__type")
  end
end
