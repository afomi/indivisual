defmodule IndivisualWeb.AtlasRecordTest do
  @moduledoc """
  The selected-record pane presents identifiers as the structured objects they
  already are. These guard the parts that would quietly regress: a 64-character
  digest must not be dumped raw, a namespaced id must keep its segments, and an
  affected entity must carry what kind of thing it is.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Glossary
  alias IndivisualWeb.AtlasLive

  describe "identifier display" do
    test "a long digest is abbreviated, never dumped in full" do
      hash = String.duplicate("a", 64)
      short = AtlasLive.abbrev(hash)

      assert String.length(short) < 30
      assert short =~ "…"
      assert String.starts_with?(short, "aaaaaaaa")
    end

    test "a short value is left alone" do
      assert AtlasLive.abbrev("Item 3A") == "Item 3A"
    end

    test "a namespaced id keeps its segments" do
      assert AtlasLive.id_segments("civic:eltsp:entity:goal-quality-of-life") ==
               ["civic", "eltsp", "entity", "goal-quality-of-life"]
    end

    test "resolvable provenance leads" do
      ordered =
        AtlasLive.provenance_order(%{
          "section" => "Item 3A",
          "content_hash" => "abc",
          "uri" => "https://example.gov/doc"
        })

      assert [{"uri", _}, {"content_hash", _}, {"section", _}] = ordered
    end
  end

  describe "the rendered record" do
    test "the digest appears abbreviated, with the full value available", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      digest = view |> element(".atlas-prov__digest") |> render()

      assert digest =~ "…", "a 64-char hash should not render in full"
      assert digest =~ ~r/title="[0-9a-f]{64}"/, "the full value must stay available"
    end

    test "the event id renders as segments, not one opaque string", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-selected-id .atlas-ref__seg")
      assert view |> element("#atlas-selected-id") |> render() =~ "civic"
    end

    test "a source URI shows its host rather than the whole URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      link = view |> element(".atlas-prov__link") |> render()
      assert link =~ "cityofvacaville.gov"
      assert link =~ ~r/title="https:\/\//
    end

    test "the record type reads as a path, not a dotted string", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ".atlas-record__type .atlas-ref__seg")
    end
  end

  describe "entities as typed objects" do
    test "kinds map to schema.org types" do
      assert Glossary.schema_type("body") == "GovernmentOrganization"
      assert Glossary.schema_type("place") == "Place"
      assert Glossary.schema_type("policy") == "Legislation"
    end

    test "a kind with no clean analogue stays unmapped rather than forced" do
      refute Glossary.schema_type("goal"),
             "goal has no schema.org equivalent; a near-miss would be worse than none"
    end

    test "affected entities carry their type in the UI", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, ".atlas-entity"),
             "affected entities should render as typed chips"
    end
  end
end
