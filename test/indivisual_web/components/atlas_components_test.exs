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
end
