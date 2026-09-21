defmodule Indivisual.AtlasEventTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Event

  defp attrs(overrides) do
    Map.merge(
      %{
        "event_id" => "evt:1",
        "source_id" => "test",
        "stream_id" => "test",
        "sequence" => [1],
        "event_type" => "civic.plan.initiated",
        "observed_at" => "2026-01-01T00:00:00Z",
        "actor" => "org:council",
        "object" => ["plan:one"],
        "provenance" => %{"uri" => "https://example.test/1"}
      },
      overrides
    )
  end

  describe "a reader of the record sees who did what to what" do
    test "actor and object are the ActivityStreams properties of the same name" do
      assert {:ok, event} = Event.new(attrs(%{}))
      assert event.actor == "org:council"
      assert event.object == ["plan:one"]
      assert Event.affected_refs(event) == ["plan:one", "org:council"]
    end

    test "an event that affects nothing is refused" do
      assert {:error, errors} = Event.new(attrs(%{"object" => []}))
      assert {:object, _} = List.keyfind(errors, :object, 0)
    end

    test "a relationship reads subject, relationship, object" do
      payload = %{
        "relationship" => %{
          "subject" => "org:council",
          "relationship" => "initiated",
          "object" => "plan:one"
        }
      }

      assert {:ok, event} = Event.new(attrs(%{"payload" => payload}))

      assert Event.relationship(event) ==
               %{subject: "org:council", relationship: "initiated", object: "plan:one"}
    end

    test "a relationship in any other shape is refused, not dropped" do
      payload = %{
        "relationship" => %{"from" => "org:council", "verb" => "initiated", "to" => "plan:one"}
      }

      assert {:error, errors} = Event.new(attrs(%{"payload" => payload}))
      assert {:payload, message} = List.keyfind(errors, :payload, 0)
      assert message =~ "subject"
    end

    test "a sequence the store cannot hold is refused here, not at the database" do
      assert {:error, errors} = Event.new(attrs(%{"sequence" => [1_789_953_347_958_406]}))
      assert {:sequence, message} = List.keyfind(errors, :sequence, 0)
      assert message =~ "32-bit"

      assert {:ok, _} = Event.new(attrs(%{"sequence" => [1_789_953_347, 958_406, 0]}))
    end
  end
end
