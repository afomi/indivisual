defmodule IndivisualWeb.AtlasExplainTest do
  @moduledoc """
  "Explain this record" runs off the LiveView process so a slow model never
  blocks the page. These cover the offer, the result, and the two ways it must
  not mislead: generated prose is labelled as generated, and a result that
  arrives after the reader has moved on is dropped rather than shown against
  the wrong record.
  """
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Indivisual.Explain.Cache

  setup do
    Cache.clear()
    :ok
  end

  # The explain panel floats over the record, opened from the ✦ at its top.
  defp open_panel(conn) do
    {:ok, view, _} = live(conn, ~p"/atlas")
    html = view |> element("#atlas-explain-open") |> render_click()
    {:ok, view, html}
  end

  test "intelligence is on offer at the top of the record, as one purple icon", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert has_element?(view, ~s(#atlas-selected #atlas-explain-open[aria-expanded="false"]))
    refute has_element?(view, "#atlas-explain")

    # Floated in the identity block, ahead of everything in it; the ✕ that
    # closes the record has its own line above.
    assert has_element?(view, "#atlas-selected-what > #atlas-explain-open")
    at = fn marker -> html |> :binary.match(marker) |> elem(0) end
    assert at.(~s(id="atlas-selected-close")) < at.(~s(id="atlas-selected-what"))
    assert at.(~s(id="atlas-explain-open")) < at.(~s(class="atlas-record__type"))

    view |> element("#atlas-explain-open") |> render_click()
    assert has_element?(view, ~s(#atlas-explain-open[aria-expanded="true"]))
    assert has_element?(view, "#atlas-explain #atlas-explain-event")

    view |> element("#atlas-explain-open") |> render_click()
    refute has_element?(view, "#atlas-explain")
  end

  test "the panel stays open from one record to the next", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)
    [first | _] = Indivisual.Atlas.Feed.events(Indivisual.Atlas.Feed, [])

    render_hook(view, "select_event", %{"id" => first.event_id})

    assert has_element?(view, "#atlas-explain #atlas-explain-event")
  end

  test "the card offers an explanation", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    assert has_element?(view, "#atlas-explain-event")
  end

  test "the card says whose voice it is: a named model, running locally", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    assert view |> element("#atlas-explain #atlas-explain-model") |> render() =~
             Indivisual.Explain.model()

    assert view |> element("#atlas-explain") |> render() =~ "Nothing is sent anywhere"
  end

  test "the record reads in four parts: what it is, what it says, about it, what it stands on",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/atlas")

    at = fn marker -> html |> :binary.match(marker) |> elem(0) end

    order = [
      # 1. identity: type, event-or-entity, and its own id
      ~s(id="atlas-selected-what"),
      ~s(id="atlas-selected-speech"),
      ~s(id="atlas-selected-id"),
      # 2. the text
      ~s(id="atlas-selected-title"),
      # 3. metadata, beginning at truth state
      "About this record",
      ~s(id="atlas-selected-truth"),
      ~s(id="atlas-selected-source"),
      # responses, then 4. the footing
      ~s(id="atlas-selected-annotate"),
      ~s(id="atlas-selected-foundation"),
      ~s(id="atlas-selected-provenance")
    ]

    assert Enum.map(order, at) == order |> Enum.map(at) |> Enum.sort()
  end

  test "asking produces an explanation of the selected record", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    view |> element("#atlas-explain-event") |> render_click()

    # The Fake adapter answers synchronously; the result arrives as a message.
    assert render_async(view) =~ "This record describes"
    assert has_element?(view, "#atlas-explain-result")
  end

  describe "while it is working" do
    test "the loading state announces itself to assistive tech", %{conn: conn} do
      # The Fake adapter answers immediately, so drive the assign directly to
      # see the state a real model's 3-8 seconds would show.
      {:ok, view, _} = open_panel(conn)

      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      html = render(view)

      assert html =~ "atlas-explain-loading"
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-busy="true")
      assert html =~ "Reading the record"
    end

    test "the wait shows a skeleton, not a bare line of text", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)
      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      assert has_element?(view, ".atlas-explain__skeleton"),
             "a multi-second wait needs to show that work is moving"
    end

    test "a slow wait can be cancelled", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)
      send(view.pid, {:force_explain_loading, "civic:eltsp:entity:plan"})

      assert has_element?(view, "#atlas-explain-loading")

      view
      |> element(~s(#atlas-explain-loading button[phx-click="hide_explain_event"]))
      |> render_click()

      refute has_element?(view, "#atlas-explain-loading")
    end

    test "the trigger disables itself while working", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      assert view |> element("#atlas-explain-event") |> render() =~ "phx-disable-with",
             "a slow action must not look idle after it is clicked"
    end
  end

  describe "choosing the model" do
    # The Fake adapter offers "fake-small" and "fake-large", and names the model
    # in its answer, so these can tell whose words are on screen.

    defp open_picker(view) do
      view |> element("#atlas-explain-model") |> render_click()
      render_async(view)
    end

    defp pick(view, model) do
      open_picker(view)
      view |> element(~s([role="option"][phx-value-model="#{model}"])) |> render_click()
    end

    test "the badge is the control: clicking it lists the local models", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      refute has_element?(view, "#atlas-explain-models")
      assert has_element?(view, ~s(button#atlas-explain-model[aria-expanded="false"]))

      open_picker(view)

      assert has_element?(view, ~s(#atlas-explain-model[aria-expanded="true"]))

      for model <- ["fake-small", "fake-large"] do
        assert has_element?(
                 view,
                 ~s(#atlas-explain-models [role="option"][phx-value-model="#{model}"])
               )
      end
    end

    test "clicking the badge again closes the list", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      open_picker(view)
      view |> element("#atlas-explain-model") |> render_click()

      refute has_element?(view, "#atlas-explain-models")
    end

    test "picking a model names it on the badge, and it writes the next explanation",
         %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      pick(view, "fake-large")

      refute has_element?(view, "#atlas-explain-models"), "choosing closes the list"
      assert view |> element("#atlas-explain-model") |> render() =~ "fake-large"

      view |> element("#atlas-explain-event") |> render_click()
      html = render_async(view)

      assert html =~ "(fake-large)", "the chosen model should have written it"

      assert view |> element("#atlas-explain-result .atlas-explain__model") |> render() =~
               "fake-large"
    end

    test "one model's words are never served as another's", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      # Same record both times: a cache keyed without the model would answer the
      # second request with the first model's text.
      for model <- ["fake-small", "fake-large"] do
        pick(view, model)
        view |> element("#atlas-explain-event") |> render_click()

        assert render_async(view) =~ "(#{model})"
      end
    end

    test "switching models clears what the previous one wrote", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      view |> element("#atlas-explain-event") |> render_click()
      render_async(view)
      assert has_element?(view, "#atlas-explain-result")

      render_hook(view, "toggle_explain_models", %{})
      render_async(view)
      render_hook(view, "select_explain_model", %{"model" => "fake-large"})

      refute has_element?(view, "#atlas-explain-result"),
             "old text must not sit under the new model's name"
    end

    test "a model the backend did not offer is refused", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      open_picker(view)
      render_hook(view, "select_explain_model", %{"model" => "not-installed:1b"})

      refute view |> element("#atlas-explain-model") |> render() =~ "not-installed"
    end

    test "a model cannot be chosen before the list has been asked for", %{conn: conn} do
      {:ok, view, _} = open_panel(conn)

      render_hook(view, "select_explain_model", %{"model" => "fake-large"})

      assert view |> element("#atlas-explain-model") |> render() =~ Indivisual.Explain.model()
    end
  end

  test "generated prose is labelled as generated", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    view |> element("#atlas-explain-event") |> render_click()
    html = render_async(view)

    assert html =~ "language model"
    assert html =~ "the record is the source"
  end

  test "it can be hidden again", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    view |> element("#atlas-explain-event") |> render_click()
    render_async(view)
    assert has_element?(view, "#atlas-explain-result")

    view |> element(~s(button[phx-click="hide_explain_event"])) |> render_click()
    refute has_element?(view, "#atlas-explain-result")
  end

  test "changing the selected record clears the explanation", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    view |> element("#atlas-explain-event") |> render_click()
    render_async(view)
    assert has_element?(view, "#atlas-explain-result")

    # Move to a different event.
    view |> element("#atlas-activity-0 button") |> render_click()
    assert_patch(view)

    refute has_element?(view, "#atlas-explain-result"),
           "an explanation must not outlive the record it described"
  end

  test "a result for a record no longer selected is dropped", %{conn: conn} do
    {:ok, view, _} = open_panel(conn)

    # A result arriving for some other event must not render.
    send(view.pid, {:explanation, "evt:not-the-one", {:ok, "STALE TEXT"}})

    refute render(view) =~ "STALE TEXT"
  end
end
