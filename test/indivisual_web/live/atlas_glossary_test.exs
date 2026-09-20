defmodule IndivisualWeb.AtlasGlossaryTest do
  @moduledoc """
  Event cards are dense with exact vocabulary — `content_hash`, `seq 0.5`,
  `truth state` — which is precise for whoever built it and opaque on first
  read. Every field label explains itself, and these guard that the
  explanations stay reachable and complete.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Glossary

  # Labels rendered on the selected-event card.
  @card_terms ~w(truth_state occurred observed source stream affects provenance event_id)

  describe "the glossary itself" do
    test "every term has a summary and a reason for being on screen" do
      for slug <- Glossary.slugs() do
        term = Glossary.get(slug)

        assert term.label != "", "#{slug} has no label"
        assert term.summary != "", "#{slug} has no summary"
        assert term.why != "", "#{slug} has no 'why'"
      end
    end

    test "every label shown on the event card is defined" do
      for slug <- @card_terms do
        assert Glossary.defined?(slug), "the card shows #{slug} but nothing defines it"
      end
    end

    test "an unknown term is nil rather than an error" do
      refute Glossary.defined?("not_a_real_term")
      assert is_nil(Glossary.get("not_a_real_term"))
    end
  end

  describe "explaining a field" do
    setup %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      %{view: view}
    end

    test "each card label is an explainable button", %{view: view} do
      for slug <- @card_terms do
        assert has_element?(view, ~s(button[phx-value-term="#{slug}"])),
               "expected #{slug} to be explainable"
      end
    end

    test "clicking one opens a dialog with its meaning", %{view: view} do
      view |> element(~s(button[phx-value-term="provenance"])) |> render_click()

      assert has_element?(view, ~s(#atlas-explain-modal [role="dialog"]))
    end

    test "the explanation states what it is and why it is shown", %{view: view} do
      view |> element(~s(button[phx-value-term="observed"])) |> render_click()

      term = Glossary.get("observed")
      html = render(view)

      assert html =~ term.summary
      assert html =~ term.why
    end

    test "closing dismisses it", %{view: view} do
      view |> element(~s(button[phx-value-term="stream"])) |> render_click()
      assert has_element?(view, "#atlas-explain-modal")

      view |> element("#atlas-explain-close") |> render_click()
      refute has_element?(view, "#atlas-explain-modal")
    end

    test "Escape dismisses it", %{view: view} do
      view |> element(~s(button[phx-value-term="provenance"])) |> render_click()

      view |> element("#atlas-explain-modal") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#atlas-explain-modal")
    end

    test "explaining does not change the shareable URL", %{view: view} do
      view |> element(~s(button[phx-value-term="event_id"])) |> render_click()

      assert has_element?(view, "#atlas-explain-modal")
      refute_patched(view, ~p"/atlas?explain=event_id")
    end

    test "truth state links onward to the full legend", %{view: view} do
      view |> element(~s(button[phx-value-term="truth_state"])) |> render_click()

      assert render(view) =~ "See all six truth states"
    end
  end
end
