defmodule IndivisualWeb.AtlasPostTest do
  @moduledoc """
  "New activity": one composer for what a person writes into the record. A post
  and an annotation are the same object and share the form; the only difference
  is whether it is about the record that is open.
  """
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Post

  # Appends to the shared feed; DataCase rebuilds it after the rollback.
  @moduletag :writes_atlas_feed

  defp source_event, do: Feed |> Feed.events([]) |> Enum.find(&(not Post.post?(&1)))

  defp open_composer(conn, path \\ ~p"/atlas") do
    {:ok, view, _} = live(conn, path)
    view |> element("#atlas-activity-new") |> render_click()
    view
  end

  test "there is one composer: the record's Annotate opens it as an annotation", %{conn: conn} do
    event = source_event()
    {:ok, view, _} = live(conn, ~p"/atlas?#{[event: event.event_id]}")

    refute has_element?(view, "#atlas-annotation-form")
    view |> element("#atlas-selected-annotate") |> render_click()

    assert has_element?(view, ~s(#atlas-post-form input[value="annotation"][checked]))
    assert view |> element("#atlas-post-form") |> render() =~ Event.title(event)
  end

  test "a post is not annotatable, so the record offers no Annotate", %{conn: conn} do
    view = open_composer(conn)

    view
    |> form("#atlas-post-form", post: %{type: "note", author: "ryan", body: "A note of my own."})
    |> render_submit()

    post = Feed |> Feed.events([]) |> Enum.find(&Post.post?/1)
    {:ok, view, _} = live(conn, ~p"/atlas?#{[event: post.event_id]}")

    refute has_element?(view, "#atlas-selected-annotate")
  end

  test "the affordance sits in the Activity header, and opens a composer", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert has_element?(view, ~s(#atlas-activity-new[aria-expanded="false"]))
    refute has_element?(view, "#atlas-post-form")

    at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end
    assert at.("atlas-activity-title") < at.("atlas-activity-new")
    assert at.("atlas-activity-new") < at.("atlas-activity")

    view |> element("#atlas-activity-new") |> render_click()

    assert has_element?(view, "#atlas-post-form")
    assert has_element?(view, ~s(#atlas-activity-new[aria-expanded="true"]))
  end

  test "it offers both kinds of post, from one form", %{conn: conn} do
    view = open_composer(conn, ~p"/atlas?#{[event: source_event().event_id]}")

    assert has_element?(view, ~s(#atlas-post-form input[type="radio"][value="note"][checked]))
    assert has_element?(view, ~s(#atlas-post-form input[type="radio"][value="annotation"]))
    # A plain post has no kind; that is the annotation's — offered as badges.
    refute has_element?(view, "#atlas-post-kinds")

    view |> form("#atlas-post-form", %{"post" => %{"type" => "annotation"}}) |> render_change()
    assert has_element?(view, "#atlas-post-kinds .atlas-kind")
    refute has_element?(view, "#atlas-post-form select")
  end

  describe "saying what kind of thing you have to say" do
    test "a kind badge on the record opens the composer already set to it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: source_event().event_id]}")

      for kind <- Indivisual.Atlas.Sources.Annotations.kinds() do
        assert has_element?(view, "#atlas-selected-kinds #atlas-selected-kind-#{kind}")
      end

      view |> element("#atlas-selected-kind-correction") |> render_click()

      assert has_element?(view, ~s(#atlas-post-form input[value="annotation"][checked]))
      assert has_element?(view, ~s(#atlas-post-kind-correction[aria-pressed="true"]))
      assert has_element?(view, ~s(#atlas-selected-kind-correction[aria-pressed="true"]))
      # The prompt says what a good note of THIS kind contains.
      assert view |> element("#atlas-post-form textarea") |> render() =~ "what is right"
    end

    test "the kind can be changed in the form, and is what gets recorded", %{conn: conn} do
      event = source_event()
      {:ok, view, _} = live(conn, ~p"/atlas?#{[event: event.event_id]}")

      view |> element("#atlas-selected-kind-question") |> render_click()
      view |> element("#atlas-post-kind-source") |> render_click()
      assert has_element?(view, ~s(#atlas-post-kind-source[aria-pressed="true"]))

      view
      |> form("#atlas-post-form", %{
        "post" => %{"author" => "afomi", "body" => "See the staff report."}
      })
      |> render_submit()

      written =
        Feed.events(Feed, []) |> Enum.find(&(&1.payload["about_event_id"] == event.event_id))

      assert written.payload["kind"] == "source"
    end

    test "a record that cannot be annotated offers no kinds", %{conn: conn} do
      view = open_composer(conn)

      view
      |> form("#atlas-post-form", %{"post" => %{"author" => "afomi", "body" => "A note."}})
      |> render_submit()

      refute has_element?(view, "#atlas-selected-kinds")
    end
  end

  describe "the note is what matters, and it is typed on the writer's behalf" do
    @body "Met Jane Doe at 650 Merchant St, Vacaville CA 95688 — jane@example.org, (707) 555-0134."

    test "the note leads the form and takes the cursor", %{conn: conn} do
      view = open_composer(conn)
      html = view |> element("#atlas-post-form") |> render()

      assert html =~ ~s(phx-mounted)
      {body_at, _} = :binary.match(html, "<textarea")
      {author_at, _} = :binary.match(html, ~s(name="post[author]"))
      assert body_at < author_at, "the note should come before who is writing it"
    end

    test "what the note is read as is shown before it is recorded", %{conn: conn} do
      view = open_composer(conn)
      before = length(Feed.events(Feed, []))

      view |> form("#atlas-post-form", %{"post" => %{"body" => @body}}) |> render_change()

      for type <- ~w(name address email telephone) do
        assert has_element?(view, ~s(#atlas-post-mentions [data-filter="#{type}"])), type
      end

      assert has_element?(view, "#atlas-post-personal"), "contact details in a public record"
      assert length(Feed.events(Feed, [])) == before
    end

    test "the typed things are recorded with the note, and with the rule that read them",
         %{conn: conn} do
      view = open_composer(conn)

      view
      |> form("#atlas-post-form", %{"post" => %{"author" => "afomi", "body" => @body}})
      |> render_submit()

      note = Feed.events(Feed, []) |> Enum.find(&(&1.payload["body"] == @body))

      assert note.payload["mentions_rule"] == Indivisual.Atlas.Extract.rule()
      types = Enum.map(note.payload["mentions"], & &1["type"])
      assert "email" in types and "telephone" in types and "address" in types
      assert Enum.find(note.payload["mentions"], &(&1["type"] == "email"))["personal"]
    end

    test "naming a thing the record has makes the note ABOUT it", %{conn: conn} do
      place =
        Feed.events(Feed, [])
        |> Indivisual.Atlas.Topology.entities()
        |> Map.fetch!("place:carroll-way")

      view = open_composer(conn)

      view
      |> form("#atlas-post-form", %{
        "post" => %{"author" => "afomi", "body" => "Walked the #{place.label} today."}
      })
      |> render_submit()

      note =
        Feed.events(Feed, [])
        |> Enum.find(&(&1.payload["kind"] == "note" and &1.actor == "person:afomi"))

      assert "place:carroll-way" in note.object
    end

    test "mentions come from the text, never from the browser", %{conn: conn} do
      view = open_composer(conn)

      render_hook(view, "publish_post", %{
        "post" => %{
          "author" => "afomi",
          "body" => "Nothing to find here.",
          "mentions" => [%{"type" => "email", "value" => "forged@example.org"}]
        }
      })

      note = Feed.events(Feed, []) |> Enum.find(&(&1.payload["body"] == "Nothing to find here."))
      refute Map.has_key?(note.payload, "mentions")
    end
  end

  describe "who is writing, signed in" do
    setup %{conn: conn} do
      {:ok, user} =
        Indivisual.Accounts.find_or_create_github_user(%{
          github_uid: "9001",
          github_login: "afomi",
          github_access_token: "test-token",
          email: "afomi@example.test"
        })

      %{conn: log_in_user(conn, user)}
    end

    test "the author is the signed-in handle, shown and not typed", %{conn: conn} do
      view = open_composer(conn)

      assert view |> element("#atlas-post-author") |> render() =~ "afomi"
      refute has_element?(view, ~s(#atlas-post-form input[name="post[author]"]))
    end

    test "and it is the handle that is recorded, whatever the form says", %{conn: conn} do
      view = open_composer(conn)

      render_hook(view, "publish_post", %{
        "post" => %{"type" => "note", "author" => "someone-else", "body" => "Signed, really."}
      })

      note = Feed.events(Feed, []) |> Enum.find(&(&1.payload["body"] == "Signed, really."))
      assert note.actor == "person:afomi"
      assert note.provenance["author"] == "afomi"
    end
  end

  describe "who is writing" do
    test "signed out, a name is typed, and signing in is offered", %{conn: conn} do
      view = open_composer(conn)

      assert has_element?(view, ~s(#atlas-post-form input[name="post[author]"]))
      assert has_element?(view, ~s(#atlas-post-form a[href="/auth/github"]))
    end
  end

  test "a post is recorded as its own event, opened, and changes nothing else", %{conn: conn} do
    before = Feed.events(Feed, [])
    view = open_composer(conn)

    view
    |> form("#atlas-post-form", %{
      "post" => %{"type" => "note", "author" => "ryan", "body" => "The trail reopened today."}
    })
    |> render_submit()

    assert assert_patch(view) =~ "event=note%3Aryan%3A"

    events = Feed.events(Feed, [])
    assert length(events) == length(before) + 1
    assert Enum.all?(before, &(&1 in events))

    post = Enum.find(events, &(&1.event_type == Post.note_type()))
    assert post.truth_state == "reported"
    assert post.actor == "person:ryan"

    refute has_element?(view, "#atlas-post-form")
    assert view |> element("#atlas-selected-title") |> render() =~ "The trail reopened today."
    assert has_element?(view, ~s(#atlas-activity li[data-source="#{post.source_id}"]))
  end

  test "a post written under an entity focus is about that entity", %{conn: conn} do
    ref = source_event() |> Event.affected_refs() |> List.first()
    view = open_composer(conn, ~p"/atlas?#{[entity: ref]}")

    view
    |> form("#atlas-post-form", %{"post" => %{"author" => "ryan", "body" => "About this one."}})
    |> render_submit()

    post = Feed |> Feed.events([]) |> Enum.find(&(&1.event_type == Post.note_type()))
    assert post.object == [ref]
  end

  test "an annotation is about the open record", %{conn: conn} do
    about = source_event()
    view = open_composer(conn, ~p"/atlas?#{[event: about.event_id]}")

    # Choosing the type is what brings the annotation's own field (kind) in.
    view |> form("#atlas-post-form", %{"post" => %{"type" => "annotation"}}) |> render_change()

    view
    |> form("#atlas-post-form", %{
      "post" => %{
        "type" => "annotation",
        "kind" => "question",
        "author" => "ryan",
        "body" => "Why?"
      }
    })
    |> render_submit()

    annotation = Feed |> Feed.events([]) |> Enum.find(&Event.annotation?/1)
    assert annotation.payload["about_event_id"] == about.event_id
    assert annotation.payload["kind"] == "question"
  end

  test "with no record open there is nothing to annotate, and the form says so", %{conn: conn} do
    view = open_composer(conn, ~p"/atlas?event=none")

    assert has_element?(view, ~s(#atlas-post-form input[value="annotation"][disabled]))

    assert view |> element("#atlas-post-form") |> render() =~
             "open a source record to annotate it"
  end

  test "a blank post is refused, and the form keeps what was typed", %{conn: conn} do
    before = length(Feed.events(Feed, []))
    view = open_composer(conn)

    html =
      view
      |> form("#atlas-post-form", %{"post" => %{"author" => "ryan", "body" => "  "}})
      |> render_submit()

    assert html =~ "body can&#39;t be blank"
    assert has_element?(view, ~s(#atlas-post-form input[value="ryan"]))
    assert length(Feed.events(Feed, [])) == before
  end

  test "posts are marked as such in the list", %{conn: conn} do
    view = open_composer(conn)

    view
    |> form("#atlas-post-form", %{"post" => %{"author" => "ryan", "body" => "Hello."}})
    |> render_submit()

    assert_patch(view)
    assert view |> element("#atlas-activity") |> render() =~ ~r/>\s*post\s*</
  end
end
