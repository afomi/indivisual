defmodule IndivisualWeb.AtlasComponentsTest do
  @moduledoc """
  `source_nav/1` is not mounted anywhere today, so nothing else would notice it
  rotting. These keep it renderable and keep its event contract with the host
  LiveView (`toggle_source`, `clear_sources`) honest.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias IndivisualWeb.AtlasComponents

  @sources %{
    "b-source" => %{
      title: "Beta report",
      publisher: "City of Beta",
      status: "linked",
      adapter: %{status: "fixture"}
    },
    "a-source" => %{title: "Alpha export", status: "indexed", adapter: %{status: "fixture"}}
  }

  defp nav(assigns), do: render_component(&AtlasComponents.source_nav/1, assigns)

  defp doc(html), do: LazyHTML.from_fragment(html)

  defp count(html, selector), do: html |> doc() |> LazyHTML.query(selector) |> Enum.count()

  test "renders one multi-select toggle per source" do
    html = nav(%{sources: @sources})

    assert count(html, "#atlas-source-nav") == 1
    assert count(html, ~s(button[phx-click="toggle_source"][aria-pressed])) == 2
    assert count(html, ~s(input[type="radio"])) == 0
  end

  test "an empty filter presses nothing and offers no reset" do
    html = nav(%{sources: @sources, source_filter: []})

    assert count(html, ~s([aria-pressed="true"])) == 0
    assert count(html, ~s(button[phx-click="clear_sources"])) == 0
  end

  test "a filter presses its sources and offers a reset" do
    html = nav(%{sources: @sources, source_filter: ["a-source"]})

    assert count(html, ~s([phx-value-id="a-source"][aria-pressed="true"].is-active)) == 1
    assert count(html, ~s([phx-value-id="b-source"][aria-pressed="false"])) == 1
    assert count(html, ~s(button[phx-click="clear_sources"])) == 1
  end

  test "a source without a publisher still renders" do
    html = nav(%{sources: Map.take(@sources, ["a-source"])})

    assert count(html, ~s([phx-value-id="a-source"])) == 1
  end

  test "the id can be overridden so two can share a page" do
    html = nav(%{sources: @sources, id: "other-nav"})

    assert count(html, "#other-nav") == 1
    assert count(html, "#atlas-source-nav") == 0
  end

  describe "position_scrubber/1 (unmounted)" do
    defp scrubber(assigns), do: render_component(&AtlasComponents.position_scrubber/1, assigns)

    test "renders a range over the events, at the selected index" do
      html = scrubber(%{count: 5, index: 2, valuetext: "2024-04-09: Plan adopted"})

      assert count(html, ~s(form#atlas-scrubber[phx-change="scrub"])) == 1

      assert count(
               html,
               ~s(#atlas-scrubber-input[type="range"][min="0"][max="4"][value="2"][aria-valuetext="2024-04-09: Plan adopted"])
             ) == 1
    end

    test "no events is a zero-length range, not a negative one" do
      html = scrubber(%{count: 0})

      assert count(html, ~s(#atlas-scrubber-input[max="0"][value="0"])) == 1
    end

    test "folds like any accordion, and asks the host to toggle it" do
      assert count(scrubber(%{count: 3, open?: false}), "#atlas-scrubber-body[hidden]") == 1
      assert count(scrubber(%{count: 3}), "#atlas-scrubber-body[hidden]") == 0

      assert count(
               scrubber(%{count: 3}),
               ~s(#atlas-scrubber-collapse[phx-click="toggle_scrubber"])
             ) == 1
    end
  end

  describe "source_checklist/1 (unmounted)" do
    defp checklist(assigns) do
      render_component(
        &AtlasComponents.source_checklist/1,
        Map.merge(%{sources: @sources, shown: Map.keys(@sources)}, assigns)
      )
    end

    test "one checkbox per source, with its count" do
      html = checklist(%{counts: %{"a-source" => 7}})

      assert count(html, "#atlas-activity-sources") == 1
      assert count(html, ~s(button[role="checkbox"][phx-click="check_source"])) == 2

      assert count(
               html,
               ~s(#atlas-activity-source-a-source[phx-value-source="a-source"][aria-checked="true"])
             ) == 1

      n =
        html
        |> doc()
        |> LazyHTML.query("#atlas-activity-source-a-source .atlas-srcfilter__n")
        |> LazyHTML.text()

      assert String.trim(n) == "7"
    end

    test "no filter offers no reset; a filter does" do
      assert count(checklist(%{}), ~s(button[phx-click="clear_sources"])) == 0

      html = checklist(%{filter: ["a-source"], shown: ["a-source"]})
      assert count(html, ~s(#atlas-activity-sources-all[phx-click="clear_sources"])) == 1
      assert count(html, ~s(#atlas-activity-source-b-source[aria-checked="false"])) == 1
    end

    test "the last checked source is marked as staying on" do
      html = checklist(%{filter: ["a-source"], shown: ["a-source"]})

      assert count(html, ~s(#atlas-activity-source-a-source[aria-disabled="true"])) == 1
    end

    test "ids can be overridden so two can share a page" do
      html = checklist(%{id: "other", item_prefix: "other-item"})

      assert count(html, "#other") == 1
      assert count(html, "#other-item-a-source") == 1
      assert count(html, "#atlas-activity-sources") == 0
    end
  end

  describe "feed_status/1 (unmounted)" do
    defp status(assigns) do
      render_component(
        &AtlasComponents.feed_status/1,
        Map.merge(%{status: %{persistence: :ok, persisted_count: 4}, event_count: 27}, assigns)
      )
    end

    test "says where the data comes from, and how much is kept and in view" do
      html = status(%{live?: true, live_updates: 2})
      text = html |> doc() |> LazyHTML.text()

      assert count(html, "#atlas-status") == 1
      assert text =~ "Demo fixture"
      assert text =~ "live · 2 update(s) since load"
      assert text =~ "4 appended event(s) kept across restarts"

      assert html
             |> doc()
             |> LazyHTML.query("#atlas-event-count")
             |> LazyHTML.text()
             |> String.trim() == "27"
    end

    test "before the socket connects it says so" do
      assert status(%{}) |> doc() |> LazyHTML.text() =~ "connecting"
    end

    test "an unreachable store is reported, not hidden" do
      text =
        status(%{status: %{persistence: {:error, :down}, persisted_count: 0}})
        |> doc()
        |> LazyHTML.text()

      assert text =~ "unavailable"
      assert text =~ "Appends are refused"
    end
  end

  describe "the unmounted register" do
    test "names real components" do
      for name <- AtlasComponents.unmounted() do
        assert function_exported?(AtlasComponents, name, 1), "#{name}/1 is registered but gone"
      end
    end

    test "is written down in the moduledoc too" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(AtlasComponents)

      for name <- AtlasComponents.unmounted() do
        assert moduledoc =~ ~r/`#{name}\/1` \| \*\*unmounted\*\*/
      end
    end
  end

  describe "person_card/1" do
    @bare %{
      ref: "person:afomi",
      name: "Afomi",
      initials: "A",
      registered?: false,
      job_title: nil,
      affiliation: nil,
      description: nil,
      url: nil,
      image: nil,
      same_as: [],
      authored: 3,
      mentioned: 1,
      wrote: [{"question", 2}, {"observation", 1}],
      first_seen: ~U[2026-03-01 00:00:00Z],
      last_seen: ~U[2026-05-01 00:00:00Z]
    }

    defp card(profile, extra \\ %{}),
      do: render_component(&AtlasComponents.person_card/1, Map.merge(%{profile: profile}, extra))

    test "with a name alone it is a finished card: initials, counts, and an honest label" do
      html = card(@bare)

      assert html =~ "Afomi"
      assert count(html, "#atlas-person img") == 0
      assert html =~ ~r/>\s*A\s*</, "initials stand in for a photo"
      assert doc(html) |> LazyHTML.query("#atlas-person-authored") |> LazyHTML.text() =~ "3"
      assert doc(html) |> LazyHTML.query("#atlas-person-mentioned") |> LazyHTML.text() =~ "1"
      assert count(html, "#atlas-person-unregistered") == 1
      assert count(html, "#atlas-person-role") == 0
      assert count(html, "#atlas-person-links") == 0
    end

    test "a registration fills it in" do
      html =
        card(%{
          @bare
          | registered?: true,
            job_title: "Parks planner",
            affiliation: "City of Vacaville",
            description: "Leads the trails programme.",
            url: "https://example.test/jane",
            image: "https://example.test/jane.jpg",
            same_as: ["https://social.example/@jane"]
        })

      assert count(html, ~s(#atlas-person img[src="https://example.test/jane.jpg"])) == 1
      assert html =~ "Parks planner · City of Vacaville"
      assert html =~ "Leads the trails programme."
      assert count(html, ~s(#atlas-person-links a[rel="noopener noreferrer"])) == 2
      assert count(html, "#atlas-person-unregistered") == 0
    end

    test "the heading takes the id its section is labelled by" do
      html = card(@bare, %{title_id: "atlas-entity-context-title"})

      assert count(html, "h2#atlas-entity-context-title") == 1
      assert count(html, ~s(article[aria-labelledby="atlas-entity-context-title"])) == 1
    end
  end

  describe "entity_icon/1" do
    defp icon(kind), do: render_component(&AtlasComponents.entity_icon/1, kind: kind)

    test "a person is a person, a body is a group, a place is a pin, a policy is a page" do
      for kind <- ["person", "body", "place", "policy", "document", "plan"] do
        html = icon(kind)

        assert count(html, ~s(svg.atlas-kindicon[data-kind="#{kind}"][aria-hidden="true"])) == 1
        assert html =~ AtlasComponents.entity_icon_path(kind).d
      end

      # Each kind reads as itself, not as a near-neighbour.
      assert icon("person") != icon("place")
      assert icon("policy") != icon("place")
      assert icon("policy") != icon("person")

      # The written things share one icon; each still says which kind it is.
      for kind <- ["document", "plan"] do
        assert AtlasComponents.entity_icon_path(kind) ==
                 AtlasComponents.entity_icon_path("policy")

        assert icon(kind) =~ ~s(data-kind="#{kind}")
      end

      assert icon("body") != icon("person"), "one figure or several is the distinction"
    end

    test "every icon is a 20px path, so kinds sit at one size" do
      for kind <- ["person", "body", "place", "policy", "document", "plan"] do
        assert icon(kind) =~ ~s(viewBox="0 0 20 20")
      end
    end

    test "a kind with no icon draws nothing, so it can sit beside any name" do
      assert count(icon("goal"), "svg") == 0
      assert AtlasComponents.entity_icon_path("goal") == nil
    end
  end

  describe "filter_chip/1" do
    test "an entity chip draws its kind" do
      html =
        render_component(&AtlasComponents.filter_chip/1,
          id: "c",
          label: "Entity",
          value: "Carroll Way",
          kind: "place"
        )

      assert count(html, ~s(#c svg[data-kind="place"])) == 1
      assert count(html, "#c button") == 0, "no clear event: read-only"
    end
  end
end
