defmodule Indivisual.AtlasProfileTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Profile
  alias Indivisual.Atlas.Topology

  defp event(id, overrides) do
    Event.new!(
      Map.merge(
        %{
          "event_id" => id,
          "source_id" => "test",
          "stream_id" => "test",
          "sequence" => [1],
          "event_type" => "atlas.annotation.added",
          "occurred_at" => "2026-03-01T00:00:00Z",
          "observed_at" => "2026-03-01T00:00:00Z",
          "object" => ["plan:one"],
          "provenance" => %{"uri" => "https://example.test/#{id}"}
        },
        overrides
      )
    )
  end

  defp entity(events, ref), do: events |> Topology.entities() |> Map.fetch!(ref)

  describe "a person nobody registered" do
    setup do
      events = [
        event("a", %{"actor" => "person:afomi", "payload" => %{"kind" => "question"}}),
        event("b", %{
          "actor" => "person:afomi",
          "payload" => %{"kind" => "question"},
          "occurred_at" => "2026-05-01T00:00:00Z"
        }),
        event("c", %{"actor" => "person:afomi", "payload" => %{"kind" => "observation"}}),
        event("d", %{"object" => ["plan:one", "person:afomi"]})
      ]

      %{events: events, profile: Profile.person(entity(events, "person:afomi"), events)}
    end

    test "is still a whole profile: a name, initials, and what the record shows", %{profile: p} do
      assert p.name == "Afomi"
      assert p.initials == "A"
      refute p.registered?
      assert p.authored == 3
      assert p.mentioned == 1
    end

    test "says what they wrote, most frequent first", %{profile: p} do
      assert p.wrote == [{"question", 2}, {"observation", 1}]
    end

    test "is dated by the events, not by the clock", %{profile: p} do
      assert p.first_seen == ~U[2026-03-01 00:00:00Z]
      assert p.last_seen == ~U[2026-05-01 00:00:00Z]
    end

    test "has nothing it was not told", %{profile: p} do
      for field <- [:job_title, :affiliation, :description, :url, :image] do
        assert is_nil(Map.fetch!(p, field)), "#{field} should be absent, not invented"
      end

      assert p.same_as == []
    end
  end

  describe "a registered person" do
    defp registered(attrs) do
      events = [
        event("r", %{
          "event_type" => "civic.entity.registered",
          "object" => ["person:jane-doe"],
          "payload" => %{
            "entity" =>
              Map.merge(
                %{"ref" => "person:jane-doe", "label" => "Jane Q. Doe", "kind" => "person"},
                attrs
              )
          }
        })
      ]

      Profile.person(entity(events, "person:jane-doe"), events)
    end

    test "reads schema.org Person properties from the registration" do
      p =
        registered(%{
          "jobTitle" => "Parks planner",
          "affiliation" => "City of Vacaville",
          "description" => " Leads the trails programme. ",
          "url" => "https://example.test/jane",
          "image" => "https://example.test/jane.jpg",
          "sameAs" => ["https://social.example/@jane"]
        })

      assert p.registered?
      assert p.initials == "JD"
      assert p.job_title == "Parks planner"
      assert p.affiliation == "City of Vacaville"
      assert p.description == "Leads the trails programme."
      assert p.url == "https://example.test/jane"
      assert p.image == "https://example.test/jane.jpg"
      assert p.same_as == ["https://social.example/@jane"]
    end

    test "a link that is not http(s) is dropped, never rendered" do
      p =
        registered(%{
          "url" => "javascript:alert(1)",
          "image" => "data:image/png;base64,AAAA",
          "sameAs" => ["ftp://example.test/x", "https://ok.example/y", 42]
        })

      assert is_nil(p.url)
      assert is_nil(p.image)
      assert p.same_as == ["https://ok.example/y"]
    end

    test "blank values count as absent" do
      p = registered(%{"jobTitle" => "  ", "description" => ""})

      assert is_nil(p.job_title)
      assert is_nil(p.description)
    end
  end

  test "only a person gets the card" do
    assert Profile.person?(%{kind: "person"})
    refute Profile.person?(%{kind: "place"})
    refute Profile.person?(nil)
  end
end
