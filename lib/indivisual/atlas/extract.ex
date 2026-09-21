defmodule Indivisual.Atlas.Extract do
  @moduledoc """
  Reads typed things out of free text, so a person can write a good note and the
  record can still hold **structured** facts about it.

      "Met Jane Doe at 650 Merchant St, Vacaville CA 95688 — jane@example.org,
       (707) 555-0134 — about the Carroll Way alignment."

  becomes an email, a telephone number, a postal address, a name, and a link to
  an entity the record already has. The writer types prose; the typing of objects
  is done on their behalf, and shown back before anything is recorded.

  ## Rules, not a model

  Pattern rules, on purpose. `CLAUDE.md`'s invariant is that machine output never
  enters the stream, and an LLM's reading of a note would be exactly that. A rule
  is different in kind: it is deterministic, it can be read, and its result is
  reproducible from the text — so what it finds can be recorded, **with the rule's
  name and version beside it** (`rule/0`). That is `ARCHITECTURE.md`'s derived-value
  envelope: when the rules improve, old mentions stay attributable to the rule
  that produced them, and can be re-derived from the text, which is always kept.

  ## What a mention is

      %{type: "email", value: "jane@example.org", text: "jane@example.org",
        property: "email", personal: true}

  `property` is the schema.org property the value would fill (`email`,
  `telephone`, `address`, `url`, `name`), per `STANDARDS.md`'s rule of using a
  standard's word where it has an exact one. An `entity` mention carries the
  `ref` and `kind` of the entity it matched instead.

  `personal: true` marks contact details. The record is public and a chain is
  permanent (`docs/chain-permanence-vs-privacy.tldr`), so these are flagged at the
  moment they are found — for the writer to see, and for anything downstream that
  must leave them out.

  ## Confidence

  Emails, URLs and phone numbers are near-certain. A street address needs a
  number and a street word. A **name** is a guess — a run of capitalised words —
  and is marked `guess: true`: it is offered, not asserted.
  """

  @rule "extract/v1"

  @email ~r/[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+/
  @url ~r/\bhttps?:\/\/[^\s<>()]+[^\s<>().,;:!?'"]/i
  # +1 707 555 0134 · (707) 555-0134 · 707-555-0134 · 707.555.0134 · +44 20 7946 0958
  @phone ~r/(?<![\w.])(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{2,4}\)[\s.\-]?|\d{2,4}[\s.\-])\d{3,4}[\s.\-]?\d{3,4}(?![\w])/
  @street_words ~w(Street St Avenue Ave Road Rd Boulevard Blvd Drive Dr Lane Ln Way Court Ct Place Pl
                   Parkway Pkwy Highway Hwy Circle Cir Terrace Ter Trail Trl Square Sq)
  @address Regex.compile!(
             "\\b\\d{1,6}\\s+(?:[A-Z][\\w'.\\-]*\\s+){0,4}(?:" <>
               Enum.join(@street_words, "|") <>
               ")\\b\\.?" <>
               "(?:,?\\s+(?:Suite|Ste|Apt|Unit|#)\\s*[\\w\\-]+)?" <>
               "(?:,\\s*[A-Z][A-Za-z.\\-]+(?:\\s+[A-Z][A-Za-z.\\-]+){0,2})?" <>
               "(?:,?\\s+[A-Z]{2})?(?:\\s+\\d{5}(?:-\\d{4})?)?"
           )
  # Two to four capitalised words. Deliberately late and low-confidence.
  @name ~r/(?<![\w@.])(?:[A-Z][a-z]+(?:[-'][A-Z]?[a-z]+)?)(?:\s+(?:[A-Z]\.|[A-Z][a-z]+(?:[-'][A-Z]?[a-z]+)?)){1,3}(?![\w@])/u

  # Capitalised runs that are not people.
  @not_names ~w(January February March April May June July August September October November December
                Monday Tuesday Wednesday Thursday Friday Saturday Sunday The This That There These Those
                City County State Council Commission Department Board Street Avenue Road)

  # A sentence often opens with a capitalised word that is not part of the name
  # after it: "Met Jane Doe", "Dear Jane Doe", "Per Jane Doe".
  @leading ~w(Met Saw Called Emailed Asked Told Talked Spoke Visited Joined Thanked Thanks Thank
              With From To For About And But Per See Hi Hello Dear Re Cc Mr Mrs Ms Dr Prof)

  @type mention :: %{
          required(:type) => String.t(),
          required(:value) => String.t(),
          required(:text) => String.t(),
          optional(:property) => String.t(),
          optional(:personal) => boolean(),
          optional(:guess) => boolean(),
          optional(:ref) => String.t(),
          optional(:kind) => String.t()
        }

  @doc "The rule's name and version, recorded beside whatever it finds."
  def rule, do: @rule

  @doc """
  Every typed thing found in `text`, in the order it appears.

  `entities` is the record's entities (as from `Topology.entities/1`); a label
  found in the text becomes an `entity` mention carrying its ref. Earlier, surer
  finds claim their span of text, so an email's domain is not also a URL and the
  words of an address are not also a name.
  """
  def mentions(text, entities \\ %{})

  def mentions(text, entities) when is_binary(text) do
    [
      {&find(&1, @email), &email/1},
      {&find(&1, @url), &url/1},
      {&find(&1, @phone), &phone/1},
      {&find(&1, @address), &address/1},
      {&find_entities(&1, entities), & &1},
      {&find(&1, @name), &name/1}
    ]
    |> Enum.reduce({[], []}, fn {finder, build}, {found, taken} ->
      text
      |> finder.()
      |> Enum.reduce({found, taken}, fn {span, payload}, {found, taken} ->
        mention = build.(payload)

        if is_nil(mention) or overlaps?(span, taken),
          do: {found, taken},
          else: {[{span, mention} | found], [span | taken]}
      end)
    end)
    |> elem(0)
    |> Enum.sort_by(fn {{start, _len}, _mention} -> start end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(&{&1.type, &1.value})
  end

  def mentions(_text, _entities), do: []

  @doc "Refs of the entities a text mentions, in order."
  def refs(mentions), do: mentions |> Enum.filter(&(&1.type == "entity")) |> Enum.map(& &1.ref)

  @doc "Whether any mention is a contact detail."
  def personal?(mentions), do: Enum.any?(mentions, &Map.get(&1, :personal, false))

  @doc """
  The mentions as an event payload fragment — string keys, the rule beside them —
  or an empty map when nothing was found. Merge it into a payload.
  """
  def payload([]), do: %{}

  def payload(mentions) do
    %{
      "mentions" =>
        Enum.map(mentions, fn mention -> Map.new(mention, fn {k, v} -> {to_string(k), v} end) end),
      "mentions_rule" => @rule
    }
  end

  @doc """
  A client-supplied list of mentions, reduced to what this module could have
  produced: known types, string values, nothing else. Mentions arrive from a form,
  and a payload is no place for whatever a request cared to send.
  """
  def sanitize(list) when is_list(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn mention -> Map.new(mention, fn {k, v} -> {to_string(k), v} end) end)
    |> Enum.filter(fn m ->
      m["type"] in ~w(email url telephone address entity name) and is_binary(m["value"]) and
        String.length(m["value"]) <= 300
    end)
    |> Enum.map(&Map.take(&1, ~w(type value text property personal guess ref kind)))
    |> Enum.take(40)
  end

  def sanitize(_), do: []

  # ── finders: [{ {start, length}, matched_text_or_payload }] ─────────────────

  defp find(text, regex) do
    regex
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, len} | _] -> {{start, len}, binary_part(text, start, len)} end)
  end

  # Longest labels first, whole words only, any case.
  defp find_entities(text, entities) do
    entities
    |> Map.values()
    |> Enum.filter(&(is_binary(&1.label) and String.length(&1.label) >= 4))
    |> Enum.sort_by(&{-String.length(&1.label), &1.ref})
    |> Enum.flat_map(fn entity ->
      pattern =
        Regex.compile!(
          "(?<![\\p{L}\\p{N}])" <> Regex.escape(entity.label) <> "(?![\\p{L}\\p{N}])",
          "iu"
        )

      pattern
      |> Regex.scan(text, return: :index)
      |> Enum.map(fn [{start, len} | _] ->
        {{start, len},
         %{
           type: "entity",
           value: entity.label,
           text: binary_part(text, start, len),
           ref: entity.ref,
           kind: entity.kind
         }}
      end)
    end)
  end

  defp overlaps?({start, len}, taken),
    do: Enum.any?(taken, fn {s, l} -> start < s + l and s < start + len end)

  # ── builders ───────────────────────────────────────────────────────────────

  defp email(text),
    do: %{
      type: "email",
      value: String.downcase(text),
      text: text,
      property: "email",
      personal: true
    }

  defp url(text), do: %{type: "url", value: text, text: text, property: "url"}

  # Kept only with enough digits to be a number someone could dial.
  defp phone(text) do
    digits = String.replace(text, ~r/\D/, "")

    if String.length(digits) in 10..15 do
      value = if String.starts_with?(String.trim(text), "+"), do: "+" <> digits, else: digits

      %{
        type: "telephone",
        value: value,
        text: String.trim(text),
        property: "telephone",
        personal: true
      }
    end
  end

  defp address(text) do
    value = text |> String.trim() |> String.trim_trailing(",")
    %{type: "address", value: value, text: value, property: "address"}
  end

  defp name(text) do
    words =
      text |> String.split() |> Enum.drop_while(&(String.trim_trailing(&1, ".") in @leading))

    if length(words) >= 2 and not Enum.any?(words, &(&1 in @not_names)) do
      value = Enum.join(words, " ")
      %{type: "name", value: value, text: value, property: "name", guess: true}
    end
  end
end
