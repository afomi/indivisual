defmodule Indivisual.AtlasExtractTest do
  use ExUnit.Case, async: true

  alias Indivisual.Atlas.Extract

  @entities %{
    "place:carroll-way" => %{
      ref: "place:carroll-way",
      label: "Carroll Way alignment",
      kind: "place"
    },
    "org:parks" => %{ref: "org:parks", label: "Parks and Recreation Commission", kind: "body"}
  }

  defp found(text, entities \\ @entities), do: Extract.mentions(text, entities)
  defp of(mentions, type), do: mentions |> Enum.filter(&(&1.type == type)) |> Enum.map(& &1.value)

  describe "a writer types prose; the objects in it are typed for them" do
    test "one note, five kinds of thing, in the order they appear" do
      note =
        "Met Jane Doe at 650 Merchant St, Vacaville CA 95688 — jane@example.org, " <>
          "(707) 555-0134 — about the Carroll Way alignment."

      assert Enum.map(found(note), & &1.type) == ~w(name address email telephone entity)
    end

    test "an email, lowercased" do
      assert of(found("write to Jane.Doe@Example.ORG today"), "email") == ["jane.doe@example.org"]
    end

    test "a telephone number, as digits, keeping a leading +" do
      assert of(found("call (707) 555-0134"), "telephone") == ["7075550134"]
      assert of(found("call +1 707-449-5100."), "telephone") == ["+17074495100"]
      assert of(found("call 707.555.0134 now"), "telephone") == ["7075550134"]
    end

    test "a number that is not a phone number is left alone" do
      assert found("ran 5k in 2026, paid 40 usd; item 3A page 12", %{}) == []
      assert of(found("order 12-3456 shipped"), "telephone") == []
    end

    test "a url, without the sentence's full stop" do
      assert of(found("See https://www.cityofvacaville.gov/parks."), "url") ==
               ["https://www.cityofvacaville.gov/parks"]
    end

    test "a street address, with as much of city, state and zip as was written" do
      assert of(found("at 650 Merchant St, Vacaville CA 95688 yesterday"), "address") ==
               ["650 Merchant St, Vacaville CA 95688"]

      assert of(found("the office at 40 Eldridge Avenue"), "address") == ["40 Eldridge Avenue"]
    end

    test "a thing the record already has, by its label, whatever the case" do
      [entity] = found("walked the carroll way alignment") |> Enum.filter(&(&1.type == "entity"))

      assert entity.ref == "place:carroll-way"
      assert entity.kind == "place"
      assert Extract.refs(found("walked the carroll way alignment")) == ["place:carroll-way"]
    end
  end

  describe "a name is a guess, and says so" do
    test "a run of capitalised words" do
      [name] = found("Maria Lopez-Garcia spoke first", %{})

      assert name.value == "Maria Lopez-Garcia"
      assert name.guess
    end

    test "not the verb, title or greeting in front of it" do
      assert of(found("Met Jane Doe at the park", %{}), "name") == ["Jane Doe"]
      assert of(found("Dear Dr. Maria Lopez, thank you", %{}), "name") == ["Maria Lopez"]
    end

    test "not months, days, or institutions" do
      assert of(found("On Tuesday the City Council met in September", %{}), "name") == []
    end

    test "not the words of something already read as something surer" do
      # "Parks and Recreation Commission" is the entity; "Merchant St" the address.
      mentions = found("Parks and Recreation Commission met at 650 Merchant St")

      assert of(mentions, "name") == []
      assert of(mentions, "entity") == ["Parks and Recreation Commission"]
    end
  end

  describe "contact details are flagged where they are found" do
    test "emails and phone numbers are personal; an address and a url are not" do
      mentions =
        found("jane@example.org (707) 555-0134 650 Merchant St https://example.org/x", %{})

      assert Extract.personal?(mentions)

      assert mentions |> Enum.filter(& &1[:personal]) |> Enum.map(& &1.type) ==
               ~w(email telephone)

      refute Extract.personal?(found("650 Merchant St", %{}))
    end
  end

  describe "what is recorded" do
    test "the mentions, string-keyed, beside the rule that read them" do
      payload = "jane@example.org" |> found(%{}) |> Extract.payload()

      assert payload["mentions_rule"] == "extract/v1"

      assert [%{"type" => "email", "property" => "email", "personal" => true}] =
               payload["mentions"]
    end

    test "nothing found is nothing recorded" do
      assert Extract.payload([]) == %{}
    end

    test "each thing once, however often it is written" do
      assert length(found("jane@example.org or JANE@example.org", %{})) == 1
    end

    test "a list from outside is cut down to what the rule could have produced" do
      dirty = [
        %{"type" => "email", "value" => "a@b.co", "extra" => "dropped"},
        %{"type" => "script", "value" => "alert(1)"},
        %{"type" => "name", "value" => 42},
        "not a map"
      ]

      assert Extract.sanitize(dirty) == [%{"type" => "email", "value" => "a@b.co"}]
      assert Extract.sanitize(nil) == []
    end

    test "the same text always reads the same" do
      note = "Met Jane Doe at 650 Merchant St — jane@example.org"

      assert found(note) == found(note)
    end
  end
end
