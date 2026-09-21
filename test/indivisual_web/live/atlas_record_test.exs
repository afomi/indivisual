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

  describe "the feed a record came in" do
    alias Indivisual.Atlas.Event
    alias Indivisual.Atlas.Feed

    defp feed_of(events, event) do
      events |> Enum.filter(&(&1.stream_id == event.stream_id)) |> Enum.sort_by(& &1.sequence)
    end

    test "is said in words: its name, and this record's place in it", %{conn: conn} do
      events = Feed.events(Feed, [])
      event = Enum.at(events, 3)
      feed = feed_of(events, event)
      place = Enum.find_index(feed, &(&1.event_id == event.event_id)) + 1

      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: event.event_id]}")

      field = view |> element("#atlas-selected-stream") |> render()
      assert field =~ "#{place} of #{length(feed)} in this feed"
      # The structured fact stays, small: the feed's id and the ordering key.
      assert field =~ event.stream_id
      assert field =~ "seq "
      # …and the label is the word people know.
      assert has_element?(view, ~s(button[phx-value-term="stream"]), "Feed")
    end

    test "a feed can be walked: earlier and later are records of the same feed", %{conn: conn} do
      events = Feed.events(Feed, [])
      event = Enum.at(events, 3)
      feed = feed_of(events, event)
      index = Enum.find_index(feed, &(&1.event_id == event.event_id))
      later = Enum.at(feed, index + 1)

      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: event.event_id]}")

      view |> element("#atlas-selected-stream-later") |> render_click()
      assert assert_patch(view) =~ URI.encode_www_form(later.event_id)

      view |> element("#atlas-selected-stream-earlier") |> render_click()
      assert assert_patch(view) =~ URI.encode_www_form(event.event_id)
    end

    test "the ends of a feed offer no step past them; filters do not shorten a feed" do
      events = Feed.events(Feed, [])
      first = events |> feed_of(hd(events)) |> hd()

      assert %{position: 1, earlier: nil, later: later} = AtlasLive.stream_context(events, first)
      assert is_binary(later)
      assert AtlasLive.stream_context(events, first).total == length(feed_of(events, first))
    end

    test "the conventions in use are named in words" do
      events = Feed.events(Feed, [])
      about = hd(events)

      at = ~U[2026-09-20 12:00:00Z]

      post = %Event{
        event_id: "note:x",
        stream_id: "posts:afomi",
        sequence: [4],
        observed_at: at
      }

      note = %Event{
        event_id: "a:x",
        stream_id: "annotations:#{about.event_id}",
        sequence: [1],
        observed_at: at
      }

      assert AtlasLive.stream_context([post | events], post).name == "afomi's posts"
      assert AtlasLive.stream_context([note | events], note).name =~ Event.title(about)
    end
  end

  describe "the top of the record" do
    test "the ✕ has a line of its own above it; event / entity is one word with a tooltip",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-selected > .atlas-record__bar #atlas-selected-close")

      at = fn marker -> html |> :binary.match(marker) |> elem(0) end
      assert at.(~s(id="atlas-selected-close")) < at.(~s(id="atlas-selected-what"))

      speech = view |> element("#atlas-selected-speech") |> render()
      assert speech =~ ~r/title="(Events|Entities): /
      refute speech =~ ~r/>\s*(Events|Entities): something/
    end
  end

  describe "identifier display" do
    test "a long digest is abbreviated, never dumped in full" do
      hash = String.duplicate("a", 64)
      short = AtlasLive.abbrev(hash)

      assert String.length(short) < 30
      assert short =~ "…"
      assert String.starts_with?(short, "aaaaaaaa")
    end

    test "any hash-valued provenance key counts as a digest" do
      assert AtlasLive.digest_key?("content_hash")
      assert AtlasLive.digest_key?("about_content_hash")
      assert AtlasLive.digest_key?("txid")
      refute AtlasLive.digest_key?("uri")
      refute AtlasLive.digest_key?("about_event_id")
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

  describe "the two clocks" do
    alias Indivisual.Atlas.Event
    alias Indivisual.Atlas.Feed

    defp event(occurred, observed) do
      %Event{occurred_at: occurred, observed_at: observed}
    end

    test "occurred and observed share one line, with the gap between them", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-selected-when #atlas-selected-occurred")
      assert has_element?(view, "#atlas-selected-when #atlas-selected-observed")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end
      assert at.("atlas-selected-occurred") < at.("atlas-selected-lag")
      assert at.("atlas-selected-lag") < at.("atlas-selected-observed")
    end

    test "each clock keeps its glossary term", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      for term <- ~w(occurred observed) do
        assert has_element?(view, ~s(#atlas-selected-when button[phx-value-term="#{term}"]))
      end
    end

    test "the gap is stated for the record on screen", %{conn: conn} do
      event = Feed.events(Feed, []) |> Enum.find(& &1.occurred_at)
      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: event.event_id]}")

      assert view |> element("#atlas-selected-lag") |> render() =~ AtlasLive.lag(event).text
    end

    test "recorded after it happened: how far behind" do
      lag = AtlasLive.lag(event(~U[2024-04-09 00:00:00Z], ~U[2024-04-12 00:00:00Z]))

      assert lag.kind == :after
      assert lag.text == "3 d later"
    end

    test "recorded as it happened: where reporting should converge" do
      now = ~U[2024-04-09 12:00:00Z]
      assert %{kind: :same, text: "same moment"} = AtlasLive.lag(event(now, now))
    end

    test "recorded before it happened is its own finding, not a negative number" do
      lag = AtlasLive.lag(event(~U[2024-04-12 00:00:00Z], ~U[2024-04-09 00:00:00Z]))

      assert lag.kind == :before
      assert lag.text == "3 d ahead"
      assert lag.title =~ "in advance"
    end

    test "a source that gives no time is reported, not filled in with ours" do
      lag = AtlasLive.lag(event(nil, ~U[2024-04-09 00:00:00Z]))

      assert lag.kind == :unstated
      assert lag.text == "only observed"
    end

    test "the gap reads at one natural unit" do
      assert AtlasLive.duration(45) == "45 s"
      assert AtlasLive.duration(90) == "1 min"
      assert AtlasLive.duration(7_200) == "2 h"
      assert AtlasLive.duration(86_400 * 10) == "10 d"
      assert AtlasLive.duration(86_400 * 150) == "5 mo"
      assert AtlasLive.duration(86_400 * 900) == "2.5 y"
    end
  end

  describe "relationships on a record" do
    alias Indivisual.Atlas.Feed
    alias Indivisual.Atlas.Topology

    # An event that asserts a relationship, and whose entities are in others too.
    defp asserting_event do
      events = Feed.events()
      rels = Topology.relationships(events)

      busiest =
        rels
        |> Enum.flat_map(&[&1.subject, &1.object])
        |> Enum.frequencies()
        |> Enum.max_by(&elem(&1, 1))
        |> elem(0)

      rel = Enum.find(rels, &(busiest in [&1.subject, &1.object]))
      Enum.find(events, &(&1.event_id == rel.event_id))
    end

    test "the whole row opens the record that asserts it: there is no open link", %{conn: conn} do
      event = asserting_event()
      {:ok, view, _} = live(conn, ~p"/atlas?event=#{event.event_id}")

      assert has_element?(view, "#atlas-selected-relationships button.atlas-rel")
      refute has_element?(view, "#atlas-selected-relationships button", "open")

      other =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#atlas-selected-relationships button.atlas-rel")
        |> LazyHTML.attribute("data-event")
        |> hd()

      view
      |> element(~s(#atlas-selected-relationships button[data-event="#{other}"]))
      |> render_click()

      assert assert_patch(view) =~ URI.encode_www_form(other)
    end

    test "the open record's own relationship is selected, and is not a button", %{conn: conn} do
      event = asserting_event()
      {:ok, view, _} = live(conn, ~p"/atlas?event=#{event.event_id}")

      own = ~s(#atlas-selected-relationships [data-event="#{event.event_id}"])
      assert has_element?(view, own <> ~s(.is-selected[aria-current="true"]))
      refute has_element?(view, "button" <> ~s([data-event="#{event.event_id}"].atlas-rel))
      refute view |> element("#atlas-selected-relationships") |> render() =~ "this record"
    end

    test "a relationship is drawn as an activity row: same list, same item, same badge", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/atlas?event=#{asserting_event().event_id}")

      assert has_element?(view, "ul#atlas-selected-relationships.atlas-activity")
      assert has_element?(view, "#atlas-selected-relationships .atlas-activity__item.atlas-rel")
      assert has_element?(view, "#atlas-selected-relationships .atlas-rel time")

      assert has_element?(
               view,
               "#atlas-selected-relationships .atlas-rel .atlas-truth[data-truth]"
             )
    end
  end
end
