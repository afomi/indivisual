defmodule IndivisualWeb.AtlasVoicesTest do
  @moduledoc """
  Two things can be written about a record and they are not the same kind of
  thing: a machine paraphrase, which never enters the record, and an
  annotation, which becomes an activity of it with an author. They share a
  shape so a reader learns one pattern, and differ in colour and edge so the
  difference is never a matter of reading the label.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @css File.read!("assets/css/app.css")

  describe "the two voices are distinguishable" do
    test "each has its own colour token" do
      assert @css =~ "--machine:"
      assert @css =~ "--person:"

      machine = Regex.run(~r/--machine:\s*([^;]+);/, @css, capture: :all_but_first)
      person = Regex.run(~r/--person:\s*([^;]+);/, @css, capture: :all_but_first)

      refute machine == person, "a gloss and a claim must not read the same"
    end

    test "the machine voice is dashed, because it is not the record" do
      [panel] = Regex.run(~r/\n\.atlas-explain \{[^}]*\}/, @css)
      assert panel =~ "dashed"
    end

    test "the person voice is solid, because it becomes the record" do
      [panel] = Regex.run(~r/\n\.atlas-compose \{[^}]*\}/, @css)

      refute panel =~ "dashed"
      assert panel =~ "var(--person)"
    end

    test "both voices survive a dark theme" do
      [dark] = Regex.run(~r/@media \(prefers-color-scheme: dark\) \{\s*:root \{[^}]*\}/, @css)

      assert dark =~ "--person:",
             "a light-only token would leave the button unreadable in dark mode"
    end
  end

  describe "in the page" do
    test "writing an activity carries the person voice", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-activity-new.atlas-activity__new")
    end

    test "annotating a record uses the same treatment, not a second one", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      # One visual language for authorship: the record's annotate button and
      # the list's compose button are the same control, differently placed.
      assert has_element?(view, "#atlas-selected-annotate.atlas-activity__new")
    end

    test "the machine panel keeps its own treatment", %{conn: conn} do
      # The trigger is only drawn when no explanation is in hand, and the cache
      # is shared, so assert on the panel — which is always there — rather than
      # on a button whose presence depends on test order.
      {:ok, view, _} = live(conn, ~p"/atlas")

      # The panel is collapsed until asked for; its trigger is always there.
      assert has_element?(view, "#atlas-explain-open.atlas-explain__spark-button")

      view |> element("#atlas-explain-open") |> render_click()

      assert has_element?(view, "#atlas-explain.atlas-explain")

      refute has_element?(view, "#atlas-explain .atlas-activity__new"),
             "the machine voice must not borrow the authoring voice"
    end
  end

  test "the link to this view sits beside the Filters label", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-applied .atlas-applied__action #atlas-share-copy")

    # Pushed to the end of the label's row, so the chips keep the line below.
    [action] = Regex.run(~r/\n\.atlas-applied__action \{[^}]*\}/, @css)
    assert action =~ "margin-left: auto"
  end
end
