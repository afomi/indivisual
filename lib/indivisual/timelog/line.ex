defmodule Indivisual.Timelog.Line do
  @moduledoc """
  Parses one written line into the slots of a timelog entry.

  The line is the interface. A dropdown-and-fields form would be slower than
  the Markdown line people already type, so capture accepts that line and
  fills the slots from it; the parsed result is shown back for correction
  rather than assumed to be right.

      worked on trail easement 9-10:30
      read Seeing Like a State 45m
      ran 5k

  Only the verb, the title and the time are parsed. Everything else stays
  prose in `notes` — it is captured as text now and structured later by a job,
  so nothing about writing a line has to wait on understanding it.

  Times are resolved against a caller-supplied "now", never `DateTime.utc_now()`
  inside the parser, so the same line parses identically in a test and at 11pm.
  """

  @verbs %{
    "read" => "reading",
    "reading" => "reading",
    "ran" => "exercise",
    "run" => "exercise",
    "walked" => "exercise",
    "swam" => "exercise",
    "rode" => "exercise",
    "exercised" => "exercise",
    "worked on" => "work",
    "worked" => "work",
    "did" => "work",
    "met" => "work",
    "wrote" => "work",
    "built" => "work",
    "shipped" => "work",
    "attended" => "event",
    "went to" => "event"
  }

  # Longest first, so "worked on" wins over "worked".
  @verb_phrases @verbs |> Map.keys() |> Enum.sort_by(&(-String.length(&1)))

  @type parsed :: %{
          kind: String.t(),
          title: String.t(),
          valid_from: DateTime.t(),
          valid_to: DateTime.t() | nil,
          notes: String.t() | nil,
          verb: String.t() | nil
        }

  @doc "Known verbs, for showing what the field understands."
  def verbs, do: @verb_phrases

  @doc """
  Parses `line` into entry slots, resolving times against `now`.

  Returns `{:ok, parsed}` or `{:error, :blank}`. An unrecognised verb is not an
  error: the line becomes a `work` entry titled with the whole text, because
  losing what someone typed is worse than mis-filing it.
  """
  def parse(line, now \\ DateTime.utc_now(), notes \\ nil)

  def parse(line, now, notes) when is_binary(line) do
    trimmed = String.trim(line)

    if trimmed == "" do
      {:error, :blank}
    else
      now = DateTime.truncate(now, :second)
      {verb, kind, rest} = take_verb(trimmed)
      {from, to, title} = take_time(rest, now)

      {:ok,
       %{
         kind: kind,
         title: clean_title(title, trimmed),
         valid_from: from,
         valid_to: to,
         notes: blank_to_nil(notes),
         verb: verb
       }}
    end
  end

  def parse(_line, _now, _notes), do: {:error, :blank}

  # --- verb ---

  defp take_verb(line) do
    downcased = String.downcase(line)

    match =
      Enum.find(@verb_phrases, fn phrase ->
        String.starts_with?(downcased, phrase <> " ") or downcased == phrase
      end)

    case match do
      nil -> {nil, "work", line}
      phrase -> {phrase, @verbs[phrase], String.slice(line, String.length(phrase)..-1//1)}
    end
  end

  # --- time ---

  # Each clause returns {valid_from, valid_to, remaining_title}.
  defp take_time(text, now) do
    text = String.trim(text)

    cond do
      # "9-10:30", "09:00-10:30", "9am-10:30am"
      match =
          Regex.run(
            ~r/\s*\b(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:-|–|to)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*$/i,
            text
          ) ->
        [full, a, b] = match
        title = String.replace_suffix(text, full, "")

        # "2-3pm" means 2pm, not 02:00: a bare start inherits the end's
        # meridiem, which is how the range is read aloud.
        a = inherit_meridiem(a, b)

        with {:ok, from} <- clock_to_datetime(a, now),
             {:ok, to} <- clock_to_datetime(b, now) do
          # An end before the start means it ran past midnight.
          to =
            if DateTime.compare(to, from) == :lt, do: DateTime.add(to, 86_400, :second), else: to

          {from, to, title}
        else
          _ -> {now, nil, text}
        end

      # A bare duration: "45m", "1h30", "2h"
      match = Regex.run(~r/\s*\b(\d+\s*h(?:\s*\d+)?|\d+\s*m(?:in)?)\s*$/i, text) ->
        [full, dur] = match
        title = String.replace_suffix(text, full, "")

        case duration_seconds(dur) do
          nil -> {now, nil, text}
          # A duration with no clock time means "just finished": it ends now.
          secs -> {DateTime.add(now, -secs, :second), now, title}
        end

      true ->
        {now, nil, text}
    end
  end

  # Only when the start states no meridiem of its own.
  defp inherit_meridiem(start_text, end_text) do
    start_down = String.downcase(start_text)
    end_down = String.downcase(end_text)

    cond do
      String.contains?(start_down, "am") or String.contains?(start_down, "pm") -> start_text
      String.contains?(end_down, "pm") -> String.trim(start_text) <> "pm"
      String.contains?(end_down, "am") -> String.trim(start_text) <> "am"
      true -> start_text
    end
  end

  defp clock_to_datetime(text, now) do
    text = text |> String.trim() |> String.downcase()

    meridiem =
      cond do
        String.contains?(text, "am") -> :am
        String.contains?(text, "pm") -> :pm
        true -> nil
      end

    digits = String.replace(text, ~r/[^\d:]/, "")

    {hour, minute} =
      case String.split(digits, ":") do
        [h] -> {to_int(h), 0}
        [h, m] -> {to_int(h), to_int(m)}
        _ -> {nil, nil}
      end

    hour = apply_meridiem(hour, meridiem)

    if valid_clock?(hour, minute) do
      with {:ok, time} <- Time.new(hour, minute, 0),
           {:ok, dt} <- DateTime.new(DateTime.to_date(now), time, "Etc/UTC") do
        {:ok, DateTime.truncate(dt, :second)}
      end
    else
      :error
    end
  end

  defp apply_meridiem(nil, _), do: nil
  defp apply_meridiem(12, :am), do: 0
  defp apply_meridiem(h, :am), do: h
  defp apply_meridiem(12, :pm), do: 12
  defp apply_meridiem(h, :pm) when h < 12, do: h + 12
  defp apply_meridiem(h, _), do: h

  defp valid_clock?(h, m), do: is_integer(h) and is_integer(m) and h in 0..23 and m in 0..59

  defp duration_seconds(text) do
    text = text |> String.trim() |> String.downcase()

    cond do
      # "1h30" or "1h 30"
      m = Regex.run(~r/^(\d+)\s*h\s*(\d+)$/, text) ->
        [_, h, mm] = m
        to_int(h) * 3600 + to_int(mm) * 60

      m = Regex.run(~r/^(\d+)\s*h$/, text) ->
        [_, h] = m
        to_int(h) * 3600

      m = Regex.run(~r/^(\d+)\s*m(?:in)?$/, text) ->
        [_, mm] = m
        to_int(mm) * 60

      true ->
        nil
    end
  end

  defp to_int(s) do
    case Integer.parse(String.trim(s)) do
      {i, _} -> i
      :error -> nil
    end
  end

  # --- title ---

  # Strip the connective words a written line carries but a title should not.
  defp clean_title(title, original) do
    cleaned =
      title
      |> String.trim()
      |> String.replace(~r/^(on|to|with|about|the)\s+/i, "")
      |> String.replace(~r/\s+(from|at|for)$/i, "")
      |> String.trim()

    if cleaned == "", do: String.trim(original), else: cleaned
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      t -> t
    end
  end
end
