defmodule Indivisual.Atlas.Capture do
  @moduledoc """
  One typed line into one activity: **who · did what · to what · when**.

      met Jane Doe at Carroll Way yesterday 3pm
      read the ELTSP staff report
      attended Parks Commission with Jane Doe 2026-09-09 18:30

  That shape is the event envelope already — `actor`, `event_type`, `object`,
  `occurred_at`, an ActivityStreams `Activity` — but prose does not fill it: a
  post names no verb and touches an entity only by accident. Small facts of one
  shape are what accumulate into something worth querying, so capture asks for
  the shape, in the cheapest form there is: a line.

  ## The line is the interface

  `Indivisual.Timelog.Line`'s rule, kept: typing a line is faster than filling
  fields, so the line is parsed and the parse is **shown back for correction,
  never assumed right**. `parse/2` returns a draft; nothing is appended until
  `to_events/2` is asked for them. A line the parser cannot read is still a
  valid activity — verb `noted`, the whole text as its title.

  ## What is parsed

    * a **verb**, from the front: the longest phrase in `verbs/0`. Where
      ActivityStreams has an exact word it is recorded too (`read` → `Read`);
      where it has none (`met`) ours stands alone — `STANDARDS.md`'s rule.
    * a **time**, from the end: a date word or ISO date, and a clock time, in
      either order. Resolved against the caller's `now` and never the system
      clock, so a line parses the same in a test and at 11pm. No time means now.
    * **objects**, from what is left, split on `at` / `with` / `and` / commas.
      `at` hints a place and `with` a person. Each is matched against the
      entities already in the record, by label, so a log links up instead of
      forking `person:jane` from `person:jane-doe`. What matches nothing is NEW,
      and logging it appends its registration (a noun event) before the activity.

  ## Truth state

  `reported`. A person logging their own activity is first-hand, but while the
  author is a typed name nobody has verified, the record cannot say so: it is a
  claim by someone calling themselves that. Signed-in capture can be `observed`.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Sources.Annotations
  alias Indivisual.Atlas.Topology

  # phrase => {verb id, ActivityStreams type or nil, what a bare object most likely is}
  @verbs %{
    "met with" => {"met", nil, "person"},
    "met" => {"met", nil, "person"},
    "talked to" => {"talked-to", nil, "person"},
    "talked with" => {"talked-to", nil, "person"},
    "called" => {"called", nil, "person"},
    "emailed" => {"emailed", nil, "person"},
    "read" => {"read", "Read", "document"},
    "watched" => {"viewed", "View", "thing"},
    "saw" => {"viewed", "View", "thing"},
    "viewed" => {"viewed", "View", "thing"},
    "listened to" => {"listened-to", "Listen", "thing"},
    "attended" => {"attended", "Join", "body"},
    "joined" => {"joined", "Join", "body"},
    "left" => {"left", "Leave", "place"},
    "went to" => {"went-to", "Travel", "place"},
    "visited" => {"visited", "Arrive", "place"},
    "arrived at" => {"arrived-at", "Arrive", "place"},
    "wrote" => {"wrote", "Create", "document"},
    "made" => {"made", "Create", "thing"},
    "built" => {"built", "Create", "thing"},
    "created" => {"created", "Create", "thing"},
    "updated" => {"updated", "Update", "thing"},
    "followed" => {"followed", "Follow", "person"},
    "liked" => {"liked", "Like", "thing"},
    "asked" => {"asked", "Question", "person"},
    "proposed" => {"proposed", "Offer", "plan"},
    "paid" => {"paid", nil, "body"},
    "bought" => {"bought", nil, "thing"},
    "worked on" => {"worked-on", nil, "plan"},
    "walked" => {"walked", nil, "place"},
    "ran" => {"ran", nil, "place"},
    "noted" => {"noted", nil, "thing"}
  }

  # Longest first, so "met with" wins over "met".
  @phrases @verbs |> Map.keys() |> Enum.sort_by(&{-String.length(&1), &1})

  @default_verb {"noted", nil, "thing"}

  @type object :: %{
          text: String.t(),
          ref: String.t(),
          label: String.t(),
          kind: String.t(),
          known?: boolean()
        }

  @type draft :: %{
          line: String.t(),
          verb: String.t(),
          phrase: String.t() | nil,
          as2: String.t() | nil,
          objects: [object()],
          occurred_at: DateTime.t(),
          timed?: boolean()
        }

  @doc "Verb phrases the line understands, longest first."
  def verbs, do: @phrases

  @doc """
  Parses `line` into a draft.

  Options: `:now` (a `DateTime`, required for a stable parse; defaults to the
  clock) and `:entities` (the record's entities, as from `Topology.entities/1`,
  to match objects against).

  Returns `{:ok, draft}` or `{:error, :blank}`.
  """
  def parse(line, opts \\ []) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    entities = Keyword.get(opts, :entities, %{})
    text = line |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()

    if text == "" do
      {:error, :blank}
    else
      {phrase, {verb, as2, default_kind}, rest} = take_verb(text)
      {rest, occurred_at, timed?} = take_time(rest, now)

      {:ok,
       %{
         line: text,
         verb: verb,
         phrase: phrase,
         as2: as2,
         # With no verb recognised the line is a note: only what the record already
         # knows is an object, and the rest stays prose rather than becoming a thing.
         objects: objects(rest, entities, default_kind, not is_nil(phrase)),
         occurred_at: occurred_at,
         timed?: timed?
       }}
    end
  end

  @doc """
  The events a draft would append, in order: a registration for each NEW object,
  then the activity itself. `author` is the typed name of who is logging.

  Returns `{:ok, [attrs]}` (maps for `Feed.append/1`) or `{:error, errors}`.
  """
  def to_events(draft, author, opts \\ []) do
    author = author |> to_string() |> String.trim()
    now = Keyword.get(opts, :now) || DateTime.utc_now()

    if author == "" do
      {:error, [{:author, "can't be blank"}]}
    else
      actor = "person:#{slug(author)}"
      at = draft.occurred_at
      # When it was written, as `[seconds, microseconds]`: later lines sort later
      # with no counter to share, and each part fits the store's 32-bit integers
      # (one number of microseconds does not).
      {micro, _precision} = now.microsecond
      seq = [DateTime.to_unix(now), micro]

      registrations =
        draft.objects
        |> Enum.reject(& &1.known?)
        |> Enum.with_index()
        |> Enum.map(fn {object, i} -> registration(object, author, actor, now, seq ++ [i]) end)

      {:ok,
       registrations ++ [activity(draft, author, actor, at, now, seq ++ [length(registrations)])]}
    end
  end

  # ── the activity and its nouns ───────────────────────────────────────────

  defp activity(draft, author, actor, at, now, seq) do
    refs = Enum.map(draft.objects, & &1.ref)
    fingerprint = %{"by" => actor, "line" => draft.line, "at" => at} |> Event.content_hash()

    %{
      "event_id" =>
        "log:#{slug(author)}:#{Date.to_iso8601(DateTime.to_date(at))}:#{binary_part(fingerprint, 0, 8)}",
      "source_id" => Annotations.source_id(),
      "stream_id" => "log:#{slug(author)}",
      "sequence" => seq,
      "event_type" => "log.#{draft.verb}",
      "occurred_at" => at,
      "observed_at" => now,
      "actor" => actor,
      # An activity with nothing named is about the person who did it.
      "object" => if(refs == [], do: [actor], else: refs),
      "payload" =>
        %{"title" => draft.line, "kind" => "log", "verb" => draft.verb}
        |> put_if("as2_type", draft.as2),
      "provenance" => %{
        "author" => author,
        "recorded_by" => "indivisual",
        "captured_line" => draft.line
      },
      "truth_state" => "reported"
    }
  end

  defp registration(object, author, actor, now, seq) do
    %{
      "event_id" => "log:#{slug(author)}:entity:#{object.ref}",
      "source_id" => Annotations.source_id(),
      "stream_id" => "log:#{slug(author)}",
      "sequence" => seq,
      "event_type" => "log.entity.registered",
      "occurred_at" => now,
      "observed_at" => now,
      "actor" => actor,
      "object" => [object.ref],
      "payload" => %{
        "entity" => %{"ref" => object.ref, "label" => object.label, "kind" => object.kind}
      },
      "provenance" => %{"author" => author, "recorded_by" => "indivisual"},
      "truth_state" => "reported"
    }
  end

  # ── verb, from the front ─────────────────────────────────────────────────

  defp take_verb(text) do
    lower = String.downcase(text)

    case Enum.find(@phrases, &(lower == &1 or String.starts_with?(lower, &1 <> " "))) do
      nil ->
        {nil, @default_verb, text}

      phrase ->
        {phrase, Map.fetch!(@verbs, phrase),
         text |> String.slice(String.length(phrase)..-1//1) |> String.trim()}
    end
  end

  # ── time, from the end ───────────────────────────────────────────────────

  @date ~r/^(today|yesterday|\d{4}-\d{2}-\d{2})$/i
  @clock ~r/^(\d{1,2})(?::(\d{2}))?\s?(am|pm)?$/i

  # Up to two trailing words may be a date and a clock time, in either order.
  # A leading "at" or "on" before them is grammar, not an object ("… at 3pm").
  defp take_time(text, now) do
    words = String.split(text, " ", trim: true)
    {tail, found} = peel(Enum.reverse(words), %{})
    tail = drop_glue(tail)
    rest = tail |> Enum.reverse() |> Enum.join(" ")

    case found do
      map when map_size(map) == 0 -> {text, now, false}
      map -> {rest, resolve(map, now), true}
    end
  end

  defp peel([word | rest] = words, found) when map_size(found) < 2 do
    cond do
      not Map.has_key?(found, :date) and word =~ @date -> peel(rest, Map.put(found, :date, word))
      not Map.has_key?(found, :clock) and clock?(word) -> peel(rest, Map.put(found, :clock, word))
      true -> {words, found}
    end
  end

  defp peel(words, found), do: {words, found}

  defp drop_glue([word | rest]) when word in ["at", "on", "At", "On"], do: rest
  defp drop_glue(words), do: words

  # A bare number is not a time ("ran 5" is five of something): a clock needs a
  # colon or an am/pm.
  defp clock?(word) do
    case Regex.run(@clock, word) do
      [_, h, m, ap] -> valid_clock?(h, m, ap)
      [_, h, m] -> m != "" and valid_clock?(h, m, "")
      _ -> false
    end
  end

  defp valid_clock?(h, m, ap) do
    hour = String.to_integer(h)
    minute = if m in ["", nil], do: 0, else: String.to_integer(m)
    (ap != "" or m != "") and minute < 60 and if(ap == "", do: hour < 24, else: hour in 1..12)
  end

  defp resolve(found, now) do
    date =
      case found[:date] && String.downcase(found[:date]) do
        nil -> DateTime.to_date(now)
        "today" -> DateTime.to_date(now)
        "yesterday" -> now |> DateTime.to_date() |> Date.add(-1)
        iso -> with {:ok, date} <- Date.from_iso8601(iso), do: date
      end

    time =
      case found[:clock] && Regex.run(@clock, found[:clock]) do
        nil ->
          if found[:date] in [nil, "today"], do: DateTime.to_time(now), else: ~T[12:00:00]

        [_, h, m | ap] ->
          clock_time(
            String.to_integer(h),
            m,
            ap |> List.first() |> to_string() |> String.downcase()
          )
      end

    case date do
      %Date{} -> DateTime.new!(date, time, "Etc/UTC")
      # An impossible date ("2026-13-40") is not a time; say now rather than crash.
      _ -> now
    end
  end

  defp clock_time(hour, minute, meridiem) do
    minute = if minute in ["", nil], do: 0, else: String.to_integer(minute)

    hour =
      case {meridiem, hour} do
        {"am", 12} -> 0
        {"pm", 12} -> 12
        {"pm", h} -> h + 12
        {_, h} -> h
      end

    Time.new!(hour, minute, 0)
  end

  # ── objects, from what is left ───────────────────────────────────────────

  defp objects("", _entities, _default, _new?), do: []

  defp objects(text, entities, default_kind, new?) do
    index = label_index(entities)
    {text, held} = protect_known(text, entities)

    (" " <> text)
    |> String.split(~r/\s+(?=(?:at|with|and|near)\s)|\s*,\s*/i, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&hinted/1)
    |> inherit_hints()
    |> Enum.map(fn {hint, name} -> {hint, restore(name, held)} end)
    |> Enum.reject(fn {_hint, name} -> name == "" end)
    |> Enum.map(fn {hint, name} -> object(name, hint, default_kind, index) end)
    |> Enum.filter(&(new? or &1.known?))
    |> Enum.uniq_by(& &1.ref)
  end

  # A label the record already knows is one object, whatever words are in it:
  # "Parks and Recreation Commission" must not split at its "and". Longest labels
  # first, each swapped for a spaceless token before splitting and put back after.
  defp protect_known(text, entities) do
    entities
    |> Map.values()
    |> Enum.map(& &1.label)
    |> Enum.uniq()
    |> Enum.sort_by(&{-String.length(&1), &1})
    |> Enum.reduce({text, %{}}, fn label, {text, held} ->
      # The hint word before it ("at Carroll Way") travels with it, or it would be
      # left behind as a name of its own.
      pattern =
        Regex.compile!(
          "(?:(?<![\\p{L}\\p{N}])(at|with|near|and)\\s+)?(?<![\\p{L}\\p{N}])" <>
            Regex.escape(label) <> "(?![\\p{L}\\p{N}])",
          "iu"
        )

      if Regex.match?(pattern, text) do
        token = "\u0001#{map_size(held)}\u0001"

        # Set apart with commas, so whatever prose surrounds it splits away.
        replaced =
          Regex.replace(
            pattern,
            text,
            fn _whole, hint -> ", " <> String.trim("#{hint} #{token}") <> ", " end,
            global: false
          )

        {replaced, Map.put(held, token, label)}
      else
        {text, held}
      end
    end)
  end

  defp restore(name, held), do: Map.get(held, name, name)

  # "with Jane Doe and Bo": an `and` carries on whatever came before it, so Bo is
  # a person too. A comma does the same.
  defp inherit_hints(segments) do
    {out, _} =
      Enum.map_reduce(segments, nil, fn
        {:and, name}, last -> {{last, name}, last}
        {hint, name}, _last -> {{hint, name}, hint}
      end)

    out
  end

  defp hinted(segment) do
    case Regex.run(~r/^(at|with|and|near)\s+(.*)$/i, segment) do
      [_, word, name] -> {hint(String.downcase(word)), clean(name)}
      _ -> {nil, clean(segment)}
    end
  end

  defp hint("and"), do: :and
  defp hint("at"), do: "place"
  defp hint("near"), do: "place"
  defp hint("with"), do: "person"
  defp hint(_), do: nil

  # The name of a thing: no leading article, and no quantity. "ran 5k" and "paid
  # City of Vacaville 40 usd" carry a MEASURE of the activity, not a thing it was
  # done to; it stays in the title (and is a facet of its own — docs/VIEWS.md).
  defp clean(name) do
    name
    |> String.trim()
    |> String.replace(~r/^(the|a|an)\s+/i, "")
    |> String.replace(~r/(^|\s+)\$?\d+([.,]\d+)?(\s?[\p{L}%]{1,4})?$/u, "")
    |> String.trim()
  end

  # Known if the name is an entity's label (or its ref), ignoring case. A kind
  # hint breaks a tie between two entities of the same name, and never overrides
  # a unique match: "at Parks Commission" is still the commission, not a place.
  defp object(name, hint, default_kind, index) do
    # By label, by whole ref, or by the ref's NAME: "Carroll Way" is
    # `place:carroll-way` even though the record labels it "Carroll Way
    # alignment". Without the last, the line would mint the ref that already
    # exists and re-register someone else's entity under a new label.
    matches =
      Map.get(index, String.downcase(name), []) ++ Map.get(index, "name:" <> slug(name), [])

    case Enum.uniq_by(matches, & &1.ref) do
      [] ->
        # `at` and `with` say what the thing is; failing that, the verb's usual
        # object does ("met X": X is a person). A guess, shown for correction.
        kind = hint || default_kind
        %{text: name, ref: "#{kind}:#{slug(name)}", label: name, kind: kind, known?: false}

      matches ->
        entity = Enum.find(matches, &(&1.kind == hint)) || hd(matches)
        %{text: name, ref: entity.ref, label: entity.label, kind: entity.kind, known?: true}
    end
  end

  defp label_index(entities) do
    entities
    |> Map.values()
    |> Enum.sort_by(& &1.ref)
    |> Enum.flat_map(fn entity ->
      name = entity.ref |> String.split(":", parts: 2) |> List.last()

      [
        {String.downcase(entity.label), entity},
        {String.downcase(entity.ref), entity},
        {"name:" <> name, entity}
      ]
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "A ref-safe slug: lowercase, hyphenated, ASCII."
  def slug(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "unnamed"
      slug -> slug
    end
  end

  @doc "The kind a ref's prefix names — for callers holding only a draft's refs."
  def kind_of(ref), do: Topology.kind_of(ref)

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
