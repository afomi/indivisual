defmodule IndivisualWeb.AtlasViewStateTest do
  @moduledoc """
  Three pieces of view state that used to hide behind the projection row: the
  truth-state filter (was the Provenance projection's count chips), the entity
  focus (was the Entity context projection, with no way out), and having no
  record selected at all. Each is a filter or a state, lives in the URL, and
  changes what is read — never what was recorded.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Projections
  alias Indivisual.Atlas.Topology

  defp events, do: Feed.events(Feed, [])

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
  end

  defp rows(view), do: count(view, "#atlas-activity li[data-source]")

  # A truth state some, but not all, events carry — so filtering to it is visible.
  defp partial_state(events) do
    events
    |> Enum.frequencies_by(& &1.truth_state)
    |> Enum.find(fn {_state, n} -> n < length(events) end)
    |> elem(0)
  end

  defp hub(events) do
    events
    |> Topology.relationships()
    |> Enum.flat_map(&[&1.subject, &1.object])
    |> Enum.frequencies()
    |> Enum.max_by(&elem(&1, 1))
    |> elem(0)
  end

  describe "where the filters live" do
    defp at(html, id), do: html |> :binary.match(~s(id="#{id}")) |> elem(0)

    test "truth state is in the sticky controls, beside the timeline but not in it",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-controls #atlas-activity-truth")
      # A distinct filter: when (the timeline) and how settled (this) are
      # different questions, so it is a sibling of the timeline, not a part.
      refute has_element?(view, "#atlas-timeline #atlas-activity-truth")
      refute has_element?(view, "#atlas-filters #atlas-activity-truth")
      refute has_element?(view, "#atlas-filters #atlas-activity-sources")

      assert at(html, "atlas-timeline") < at(html, "atlas-activity-truth")
      assert at(html, "atlas-activity-truth") < at(html, "atlas-activity-title")
      assert at(html, "atlas-activity-title") < at(html, "atlas-activity")
    end

    test "an entity focus shows in column 1 with the other applied filters", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas?entity=thing:nowhere")

      assert has_element?(view, "#atlas-filters #atlas-applied-entity")
      assert at(html, "atlas-applied-entity") < at(html, "atlas-activity-title")
    end
  end

  describe "applied filters, above the list they report" do
    test "with nothing applied the row is its label alone: no chips, no count", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert at(html, "atlas-applied") < at(html, "atlas-activity-title")
      refute has_element?(view, "#atlas-applied .atlas-entitychip")
      refute view |> element("#atlas-applied") |> render() =~ "none"
      refute view |> element("#atlas-applied") |> render() =~ ~r/\d+ of \d+/
    end

    test "every filter that narrows the list is named, with what it is set to", %{conn: conn} do
      events = events()
      state = partial_state(events)
      ref = hub(events)
      [source | _] = events |> Enum.map(& &1.source_id) |> Enum.uniq()

      {:ok, view, _} =
        live(
          conn,
          "/atlas?from=0&to=#{length(events) - 2}&sources=#{source}&truth=#{state}&entity=#{ref}"
        )

      assert has_element?(view, "#atlas-applied .atlas-entitychip")

      for id <- ~w(range sources truth entity) do
        assert has_element?(view, ~s(#atlas-applied-#{id}[data-filter="#{id}"])), id
      end

      assert view |> element("#atlas-applied-truth") |> render() =~ state
      assert view |> element("#atlas-applied-sources") |> render() =~ "1 of"
    end

    test "an entity is named with its kind's icon, here and on the timeline", %{conn: conn} do
      place =
        events()
        |> Topology.entities()
        |> Enum.find_value(fn {ref, e} -> e.kind == "place" && ref end)

      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{place}")

      assert has_element?(view, ~s(#atlas-applied-entity svg[data-kind="place"]))
      assert has_element?(view, ~s(#atlas-timeline-entity svg[data-kind="place"]))
      assert has_element?(view, ~s(#atlas-entity-context-title svg[data-kind="place"]))
    end

    test "each filter can be dismissed from where it is named", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none&entity=thing:nowhere")

      assert has_element?(view, "#atlas-applied-truth-clear")
      assert has_element?(view, "#atlas-applied-entity-clear")
      assert view |> element("#atlas-applied-truth") |> render() =~ "none"
    end

    test "dismissing removes that filter and leaves the others", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=observed&from=1&to=3")

      view |> element("#atlas-applied-truth-clear") |> render_click()
      path = assert_patch(view)

      refute path =~ "truth=", "the dismissed filter is gone"
      assert path =~ "from=1", "the others are untouched"
      assert path =~ "to=3"
    end

    test "a range can be dismissed", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      assert has_element?(view, "#atlas-applied-range-clear")
      view |> element("#atlas-applied-range-clear") |> render_click()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
    end

    test "it still only removes: a filter is set where it is drawn", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=observed")

      # The ✕ is the one control here. Nothing edits a filter in place, so
      # there is still one place to set each one.
      buttons =
        view |> element("#atlas-applied") |> render() |> then(&Regex.scan(~r/<button/, &1))

      clears =
        view |> element("#atlas-applied") |> render() |> then(&Regex.scan(~r/-clear"/, &1))

      assert length(buttons) == length(clears)
    end

    test "a range read from the outside says so", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3&out=1")

      assert view |> element("#atlas-applied-range") |> render() =~ "Outside"
    end

    test "what only changes how things are drawn is not a filter on the list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?connected=1")

      refute has_element?(view, "#atlas-applied .atlas-entitychip")
    end
  end

  describe "an empty list says why" do
    test "no note while there is anything to list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-activity-empty")
    end

    test "it names the filters that emptied it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none&from=1&to=3")

      note = view |> element("#atlas-activity-empty") |> render()

      assert note =~ "None of the #{length(events())} events match"
      assert note =~ "no truth state is on"
      assert note =~ "→"
    end

    test "an entity nothing mentions is named as the reason", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?entity=thing:nowhere")

      assert view |> element("#atlas-activity-empty") |> render() =~ "entity:"
    end

    test "a window with nothing outside it is named too", %{conn: conn} do
      last = length(events()) - 1
      {:ok, view, _} = live(conn, ~p"/atlas?#{[from: 0, to: last, out: 1]}")

      assert rows(view) == 0
      assert view |> element("#atlas-activity-empty") |> render() =~ "outside"
    end

    test "Clear filters brings everything back, and keeps the graph's toggle", %{conn: conn} do
      {:ok, view, _} =
        live(conn, ~p"/atlas?connected=1&truth=none&entity=thing:nowhere&from=1&to=3")

      view |> element("#atlas-activity-reset") |> render_click()

      path = assert_patch(view)
      assert path =~ "connected=1"
      refute path =~ "truth="
      refute path =~ "entity="
      refute path =~ "from="

      assert rows(view) == length(events())
      refute has_element?(view, "#atlas-activity-empty")
    end
  end

  describe "truth-state filter" do
    test "lists every state, all checked, with its count", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      counts = Enum.frequencies_by(events(), & &1.truth_state)

      for state <- Event.truth_states() do
        chip = view |> element("#atlas-activity-truth-#{state}") |> render()

        assert chip =~ ~s(aria-checked="true")

        shown =
          view
          |> element("#atlas-activity-truth-#{state} .atlas-truthfilter__n")
          |> render()
          |> String.replace(~r/<[^>]+>|\s/, "")

        assert shown == "#{Map.get(counts, state, 0)}"
      end

      refute has_element?(view, "#atlas-activity-truth-all")
    end

    test "a state nothing has reached is still listed, marked empty", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      present = events() |> Enum.map(& &1.truth_state) |> MapSet.new()

      for state <- Event.truth_states(), state not in present do
        assert has_element?(view, "#atlas-activity-truth-#{state}.is-empty")
      end
    end

    test "unchecking a state removes its events from the list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = events()
      state = partial_state(events)
      without = Enum.count(events, &(&1.truth_state != state))

      view |> element("#atlas-activity-truth-#{state}") |> render_click()

      path = assert_patch(view)
      assert path =~ "truth="
      refute path =~ state

      assert rows(view) == without
      assert has_element?(view, ~s(#atlas-activity-truth-#{state}[aria-checked="false"]))
      assert render(view) =~ "Showing #{without} of #{length(events)}"
    end

    test "round-trips through the URL, and ignores states that do not exist", %{conn: conn} do
      events = events()
      state = partial_state(events)
      {:ok, view, _} = live(conn, ~p"/atlas?#{[truth: state <> ",bogus"]}")

      assert rows(view) == Enum.count(events, &(&1.truth_state == state))
      assert has_element?(view, ~s(#atlas-activity-truth-#{state}[aria-disabled="true"]))
    end

    test "the last checked state cannot be unchecked", %{conn: conn} do
      state = partial_state(events())
      {:ok, view, _} = live(conn, ~p"/atlas?truth=#{state}")
      before = rows(view)

      view |> element("#atlas-activity-truth-#{state}") |> render_click()

      assert rows(view) == before
    end

    test "none unchecks every state, and says why the list is empty", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-activity-truth-none") |> render_click()

      assert assert_patch(view) =~ "truth=none"
      assert rows(view) == 0
      assert has_element?(view, "#atlas-activity-truth-none-note")
      assert view |> element("#atlas-activity-truth-count") |> render() =~ "0 of"

      for state <- Event.truth_states() do
        assert has_element?(view, ~s(#atlas-activity-truth-#{state}[aria-checked="false"]))
      end
    end

    test "from none, one click shows exactly one state", %{conn: conn} do
      events = events()
      state = partial_state(events)
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none")

      view |> element("#atlas-activity-truth-#{state}") |> render_click()

      assert assert_patch(view) =~ "truth=#{state}"
      assert rows(view) == Enum.count(events, &(&1.truth_state == state))
      refute has_element?(view, "#atlas-activity-truth-none-note")
    end

    test "all and none are each offered unless already the case", %{conn: conn} do
      {:ok, everything, _} = live(conn, ~p"/atlas")
      assert has_element?(everything, "#atlas-activity-truth-none")
      refute has_element?(everything, "#atlas-activity-truth-all")

      {:ok, nothing, _} = live(conn, ~p"/atlas?truth=none")
      assert has_element?(nothing, "#atlas-activity-truth-all")
      refute has_element?(nothing, "#atlas-activity-truth-none")

      {:ok, some, _} = live(conn, ~p"/atlas?truth=#{partial_state(events())}")
      assert has_element?(some, "#atlas-activity-truth-all")
      assert has_element?(some, "#atlas-activity-truth-none")
    end

    test "none keeps filtered-out events on the range bar", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none")

      assert count(view, "#atlas-timeline-dots .atlas-range__dot") == length(events())
    end

    test "all clears it", %{conn: conn} do
      state = partial_state(events())
      {:ok, view, _} = live(conn, ~p"/atlas?truth=#{state}")

      view |> element("#atlas-activity-truth-all") |> render_click()

      refute assert_patch(view) =~ "truth="
      assert rows(view) == length(events())
    end

    test "filtered-out events stay on the range bar, unread", %{conn: conn} do
      events = events()
      state = partial_state(events)
      {:ok, view, _} = live(conn, ~p"/atlas?truth=#{state}")

      assert count(view, "#atlas-timeline-dots .atlas-range__dot") == length(events)

      assert count(view, "#atlas-timeline-dots .atlas-range__dot.is-read") ==
               Enum.count(events, &(&1.truth_state == state))
    end

    test "the key to the states is still one click away", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-activity-truth #atlas-legend-open") |> render_click()

      assert has_element?(view, "#atlas-legend-close")
    end

    test "a lens does not strip an entity's identity", %{conn: conn} do
      events = events()

      # An entity whose registration is in one truth state and which is also
      # touched by an event in another: filter to the other, and the label must
      # still be the registered one, not a humanized ref.
      registry = Topology.entities(events)

      candidate =
        Enum.find_value(events, fn event ->
          Enum.find_value(Event.affected_refs(event), fn ref ->
            entity = registry[ref]

            if entity && entity.registered && entity.truth_state != event.truth_state &&
                 entity.label != Topology.humanize(ref),
               do: {ref, entity.label, event.truth_state}
          end)
        end)

      if candidate do
        {_ref, label, state} = candidate
        {:ok, view, _} = live(conn, ~p"/atlas?truth=#{state}")

        assert view |> element("#atlas-entity-list") |> render() =~ label
      end
    end
  end

  describe "the activity list is grouped by day" do
    alias IndivisualWeb.AtlasLive

    test "each day is said once, as a heading with how many happened then", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = events()
      days = AtlasLive.activity_days(events)

      assert length(days) < length(events), "the fixture has busy days; grouping should show it"

      for {day, day_rows} <- days do
        head = view |> element("#atlas-activity-day-#{day} .atlas-activity__dayhead") |> render()
        assert head =~ day
        assert head =~ ">#{length(day_rows)}<"
      end
    end

    test "grouping never reorders the list, and rows keep their place in the whole", %{conn: conn} do
      events = events()
      days = AtlasLive.activity_days(events)

      assert days |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(&elem(&1, 0)) == events

      assert days |> Enum.flat_map(&elem(&1, 1)) |> Enum.map(&elem(&1, 1)) ==
               Enum.to_list(0..(length(events) - 1))

      {:ok, view, _} = live(conn, ~p"/atlas")
      assert rows(view) == length(events)
      assert has_element?(view, "#atlas-activity-0 button")
      assert has_element?(view, "#atlas-activity-#{length(events) - 1} button")
    end

    test "a day that comes round again later in the list gets its own group" do
      a = %Event{
        event_id: "a",
        occurred_at: ~U[2024-01-01 09:00:00Z],
        observed_at: ~U[2024-01-01 09:00:00Z]
      }

      b = %Event{
        event_id: "b",
        occurred_at: ~U[2024-01-02 09:00:00Z],
        observed_at: ~U[2024-01-02 09:00:00Z]
      }

      c = %Event{
        event_id: "c",
        occurred_at: ~U[2024-01-01 17:00:00Z],
        observed_at: ~U[2024-01-01 17:00:00Z]
      }

      assert [{"2024-01-01", [_]}, {"2024-01-02", [_]}, {"2024-01-01", [_]}] =
               AtlasLive.activity_days([a, b, c])
    end

    test "a row says the time only when the source gave one" do
      assert AtlasLive.time_of_day(~U[2024-04-09 00:00:00Z]) == ""
      assert AtlasLive.time_of_day(~U[2024-04-09 14:05:00Z]) == "14:05"
    end

    test "every row still says its own date, under the day heading", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      for {event, i} <- Enum.with_index(events()) do
        assert view |> element("#atlas-activity-#{i} time") |> render() =~
                 AtlasLive.date(Event.effective_time(event))
      end
    end

    test "a day folds to its heading and count, and opens again", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")
      [{day, _} | _] = AtlasLive.activity_days(events())
      total = rows(view)

      view |> element("#atlas-activity-day-toggle-#{day}") |> render_click()

      assert has_element?(view, ~s(#atlas-activity-day-toggle-#{day}[aria-expanded="false"]))
      refute has_element?(view, "#atlas-activity-day-rows-#{day}")
      assert rows(view) < total
      assert has_element?(view, "#atlas-activity-day-#{day} .atlas-activity__daycount")

      view |> element("#atlas-activity-day-toggle-#{day}") |> render_click()
      assert rows(view) == total
    end

    test "all / none: each is offered unless it is already the case", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")
      total = rows(view)

      assert has_element?(view, "#atlas-activity-days-none")
      refute has_element?(view, "#atlas-activity-days-all")

      view |> element("#atlas-activity-days-none") |> render_click()

      assert rows(view) == 0
      refute has_element?(view, "#atlas-activity-days-none")

      assert count(view, "#atlas-activity .atlas-activity__day") ==
               length(AtlasLive.activity_days(events()))

      view |> element("#atlas-activity-days-all") |> render_click()
      assert rows(view) == total
    end

    test "folding is how the list is read, not what is read: it stays out of the URL",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")

      view |> element("#atlas-activity-days-none") |> render_click()

      refute_patched(view)
      assert view |> element("#atlas-overview") |> render() =~ "#{length(events())} of"
    end

    test "choosing a record opens its day, so it can be found in the list", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")
      view |> element("#atlas-activity-days-none") |> render_click()

      event = List.last(events())
      render_hook(view, "select_event", %{"id" => event.event_id})

      assert has_element?(view, "#atlas-activity-#{length(events()) - 1}")
      assert rows(view) < length(events())
    end

    test "filters narrow the days with the rows", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      shown = events() |> Enum.slice(1..3) |> AtlasLive.activity_days()

      groups =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-activity .atlas-activity__day")
        |> Enum.count()

      assert groups == length(shown)
    end
  end

  describe "verbs and nouns" do
    defp nouns(events), do: Enum.count(events, &(Event.part_of_speech(&1) == "noun"))

    test "an event that registers an entity is a noun; one where something happened is a verb" do
      events = events()

      assert nouns(events) > 0
      assert nouns(events) < length(events)

      for event <- events do
        registers? = is_binary(get_in(event.payload, ["entity", "ref"]))
        assert Event.part_of_speech(event) == if(registers?, do: "noun", else: "verb")
      end
    end

    test "the filter sits in the sticky controls with the other two, both on", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = events()

      assert has_element?(view, "#atlas-controls #atlas-activity-speech")

      assert has_element?(view, ~s(#atlas-activity-speech-verb[aria-checked="true"]))
      assert has_element?(view, ~s(#atlas-activity-speech-noun[aria-checked="true"]))

      assert view |> element("#atlas-activity-speech-noun .atlas-truthfilter__n") |> render() =~
               "#{nouns(events)}"
    end

    test "unchecking nouns leaves the verbs, and rides the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      events = events()

      view |> element("#atlas-activity-speech-noun") |> render_click()

      assert assert_patch(view) =~ "speech=verb"
      assert rows(view) == length(events) - nouns(events)
      assert has_element?(view, ~s(#atlas-activity-speech-verb[aria-disabled="true"]))
    end

    test "nouns only, from a link; checking verbs again is no filter", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?speech=noun")

      assert rows(view) == nouns(events)

      view |> element("#atlas-activity-speech-verb") |> render_click()

      refute assert_patch(view) =~ "speech="
      assert rows(view) == length(events)
    end

    test "each filter counts with the other applied", %{conn: conn} do
      events = events()
      state = partial_state(events)
      {:ok, view, _} = live(conn, ~p"/atlas?#{[truth: state]}")

      expected =
        Enum.count(events, &(&1.truth_state == state and Event.part_of_speech(&1) == "noun"))

      shown =
        view
        |> element("#atlas-activity-speech-noun .atlas-truthfilter__n")
        |> render()
        |> String.replace(~r/<[^>]+>|\s/, "")

      assert shown == "#{expected}"
    end

    test "rows carry no mark of their own: the filter says it, the list stays clean", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-activity .atlas-activity__speech")
    end

    test "filtered-out activities stay on the timeline, hollow", %{conn: conn} do
      events = events()
      {:ok, view, _} = live(conn, ~p"/atlas?speech=verb")

      [json] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-timeline-scene")
        |> LazyHTML.attribute("data-scene")

      nodes = Jason.decode!(json)["nodes"]
      assert length(nodes) == length(events)
      assert Enum.count(nodes, & &1["read"]) == length(events) - nouns(events)
    end

    test "Clear filters clears it too", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?speech=noun&truth=none")

      assert view |> element("#atlas-activity-empty") |> render() =~ "nouns only"

      view |> element("#atlas-activity-reset") |> render_click()
      refute assert_patch(view) =~ "speech="
    end
  end

  describe "verbs and nouns are named" do
    alias IndivisualWeb.AtlasLive

    test "a verb is the kind of happening, without the source's namespace; a noun is an entity" do
      words = AtlasLive.speech_words(events())

      assert %{word: "plan initiated", ref: nil, n: 1} in words["verb"]
      assert Enum.all?(words["noun"], &is_binary(&1.ref))

      assert length(words["noun"]) ==
               events() |> Enum.filter(&(Event.part_of_speech(&1) == "noun")) |> length()

      assert words["verb"] |> Enum.map(& &1.n) |> Enum.sum() ==
               Enum.count(events(), &(Event.part_of_speech(&1) == "verb"))
    end

    test "the bar calls them events and entities, and lists the words of each", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      words = AtlasLive.speech_words(events())

      assert view |> element("#atlas-activity-speech-verb") |> render() =~ "Events"
      assert view |> element("#atlas-activity-speech-noun") |> render() =~ "Entities"
      assert has_element?(view, "details#atlas-activity-speech-words[open]")

      verbs = view |> element("#atlas-activity-speech-words-verb") |> render()
      for %{word: word} <- words["verb"], do: assert(verbs =~ word)

      for %{ref: ref} <- words["noun"] do
        assert has_element?(
                 view,
                 ~s(#atlas-activity-speech-words-noun button[phx-value-ref="#{ref}"])
               )
      end
    end

    test "an entity's name focuses it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")
      [%{ref: ref} | _] = AtlasLive.speech_words(events())["noun"]

      view
      |> element(~s(#atlas-activity-speech-words-noun button[phx-value-ref="#{ref}"]))
      |> render_click()

      assert assert_patch(view) =~ "entity=#{URI.encode_www_form(ref)}"
    end

    test "a filtered-out part keeps its words, marked as out", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?speech=verb")

      assert has_element?(view, "#atlas-activity-speech-words-noun.is-out button")
      refute has_element?(view, "#atlas-activity-speech-words-verb.is-out")
    end
  end

  describe "entity focus" do
    test "the sticky timeline says an entity is narrowing it, and redraws for it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")
      refute has_element?(view, "#atlas-timeline-entity")

      events = events()

      # The entity the fewest activities are about: the change is unmistakable.
      {ref, about} =
        events
        |> Enum.flat_map(&Event.affected_refs/1)
        |> Enum.frequencies()
        |> Enum.min_by(&elem(&1, 1))

      render_hook(view, "focus_entity", %{"ref" => ref})
      assert_patch(view)

      chip = view |> element("#atlas-controls #atlas-timeline-entity") |> render()
      assert chip =~ "#{about} of #{length(events)}"

      # Same record on the band, but only the entity's activities are inked…
      assert count(view, "#atlas-timeline-dots .atlas-range__dot") == length(events)
      assert count(view, "#atlas-timeline-dots .atlas-range__dot.is-read") == about

      # …and the three.js strip is told the same.
      strip =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-timeline-scene")
        |> LazyHTML.attribute("data-scene")
        |> hd()
        |> Jason.decode!()

      assert Enum.count(strip["nodes"], & &1["read"]) == about
      assert strip["focus"]

      # The chip is a way out, like the one in column 1.
      view |> element("#atlas-timeline-entity-clear") |> render_click()
      refute assert_patch(view) =~ "entity="
      refute has_element?(view, "#atlas-timeline-entity")
    end

    test "no chip until something is in focus", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-applied-entity")
      refute has_element?(view, "#atlas-entity-context")
    end

    test "narrows the list to events that touch the entity", %{conn: conn} do
      events = events()
      ref = hub(events)
      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      assert has_element?(view, "#atlas-applied-entity")
      assert rows(view) < length(events)
      assert rows(view) > 0
    end

    test "is view state: it holds whatever else the view is set to", %{conn: conn} do
      ref = hub(events())

      for projection <- ["", "connected=1", "truth=observed", "event=none"] do
        {:ok, view, _} = live(conn, "/atlas?#{projection}&entity=#{ref}")

        assert has_element?(view, "#atlas-applied-entity"), projection
        assert has_element?(view, "#atlas-entity-context"), projection
      end
    end

    test "shows what surrounds the entity: events, sources, unresolved", %{conn: conn} do
      ref = hub(events())
      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      assert view |> element("#atlas-entity-context-summary") |> render() =~ ~r/\d+ event\(s\)/
      assert has_element?(view, "#atlas-entity-context-sources li")
    end

    test "an unresolved item opens its record", %{conn: conn} do
      events = events()

      ref =
        Enum.find_value(events, fn event ->
          event.truth_state in ~w(reported proposed) && List.first(Event.affected_refs(event))
        end)

      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      view |> element("#atlas-entity-context-unresolved li:first-child button") |> render_click()

      assert assert_patch(view) =~ "event="
    end

    test "it closes like a record: a ✕ on the entity in the reader", %{conn: conn} do
      ref = hub(events())
      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      view |> element("#atlas-entity-context-close") |> render_click()

      refute assert_patch(view) =~ "entity="
      refute has_element?(view, "#atlas-applied-entity")
      refute has_element?(view, "#atlas-entity-context")
      assert rows(view) == length(events())
    end

    test "the chip on the timeline clears it too: one chip, wherever a filter is drawn",
         %{conn: conn} do
      ref = hub(events())
      {:ok, view, _} = live(conn, ~p"/atlas?entity=#{ref}")

      # Same component as the read-only one in column 1; this one has a way out.
      assert has_element?(view, ~s(#atlas-timeline-entity.atlas-entitychip[data-filter="entity"]))
      assert has_element?(view, ~s(#atlas-applied-entity.atlas-entitychip[data-filter="entity"]))

      view |> element("#atlas-timeline-entity-clear") |> render_click()

      refute assert_patch(view) =~ "entity="
      assert rows(view) == length(events())
    end

    test "an entity the view does not mention says so, rather than going blank", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?entity=thing:nowhere")

      assert has_element?(view, "#atlas-entity-context-close")

      assert view |> element("#atlas-entity-context-summary") |> render() =~
               "Nothing in the current view"

      assert rows(view) == 0
    end
  end

  describe "no selection" do
    test "by default the latest event is selected", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-selected")
      refute has_element?(view, "#atlas-overview")
    end

    test "the record closes like a modal, leaving the view", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-selected-close") |> render_click()

      assert assert_patch(view) =~ "event=none"
      refute has_element?(view, "#atlas-selected")
      assert has_element?(view, "#atlas-overview")
      assert has_element?(view, ~s(#atlas-activity-all-button[aria-current="true"]))
      assert count(view, "#atlas-activity li[data-source] .is-selected") == 0
    end

    test "All at the head of the list does the same", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      view |> element("#atlas-activity-all-button") |> render_click()

      assert assert_patch(view) =~ "event=none"
      assert has_element?(view, "#atlas-overview")
    end

    test "the overview describes what the view is reading", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none&from=1&to=3")

      overview = view |> element("#atlas-overview") |> render()
      assert overview =~ "3 of #{length(events())} activities"
      assert overview =~ "entities"
    end

    test "an emptied view still gives the count: zero of the total", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?truth=none")

      title = view |> element("#atlas-overview-title") |> render()
      assert title =~ "0 of #{length(events())} activities"
    end

    test "stays closed while the view around it changes", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")

      view |> form("#atlas-timeline-range", %{"from" => "1", "to" => "3"}) |> render_change()

      assert assert_patch(view) =~ "event=none"
      refute has_element?(view, "#atlas-selected")
    end

    test "stays closed when a live event arrives", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")

      send(view.pid, {:atlas_event, List.last(events())})

      refute has_element?(view, "#atlas-selected")
      assert has_element?(view, "#atlas-overview")
    end

    test "choosing an event reopens a record", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?event=none")

      view |> element("#atlas-activity-0 button") |> render_click()

      path = assert_patch(view)
      assert path =~ "event="
      refute path =~ "event=none"
      assert has_element?(view, "#atlas-selected")
    end

    # The graph that drew these is unmounted; the entity list under Spacetime
    # reads the same topology read model, so it is what shows the window now.
    test "with no selection the topology reads the whole window", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?connected=1&event=none")

      assert count(view, "#atlas-entity-list > li") ==
               map_size(Projections.materialize("topology", events()).entities)
    end
  end
end
