defmodule IndivisualWeb.AtlasLogLive do
  @moduledoc """
  `/atlas/log` — capture. One line in, one activity out: **who · did what · to
  what · when** (`Indivisual.Atlas.Capture`).

  A page of its own, and phone-first, because logging your own activity is a
  different act from reading the record: it happens in a spare moment, one line
  at a time, and what matters is that writing the next line is cheap.

  The line is parsed as it is typed and the parse is shown back as chips —
  verb, things, time — so a wrong guess is corrected by editing the line, before
  anything is appended. Below it: what this author has logged, and what that has
  added up to, because accumulation is the point and should be visible.

  ## A prototype, and what it is missing

  Activities go to the PUBLIC feed, under a name the writer types. That is right
  for trying the shape out and wrong for a personal log: `Indivisual.Timelog`'s
  rule is that private, per-user data must not ride the global feed. Sign-in
  comes next (`PLAN.md`); then a log is scoped to its owner and publishing is a
  separate act. When someone IS signed in, their GitHub login is already the
  default author here, so the two steps meet.
  """
  use IndivisualWeb, :live_view

  alias Indivisual.Atlas.Capture
  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.MAP
  alias Indivisual.Atlas.Topology
  alias IndivisualWeb.AtlasComponents

  @recent 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Feed.subscribe()

    author =
      case socket.assigns[:current_scope] do
        %{user: %{github_login: login}} when is_binary(login) -> login
        _ -> ""
      end

    {:ok,
     socket
     |> assign(:page_title, "Log")
     |> assign(:tz_offset, tz_offset(socket))
     |> assign(:author, author)
     |> assign(:signed_in?, author != "")
     |> assign(:line, "")
     |> assign(:draft, nil)
     |> assign(:preview, nil)
     |> assign(:errors, [])
     |> assign(:just_logged, nil)
     |> load()}
  end

  @impl true
  def handle_event("parse", %{"capture" => params}, socket) do
    {:noreply,
     socket
     |> assign(:author, author(socket, params))
     |> assign(:errors, [])
     |> draft(params["line"] || "")
     |> load()}
  end

  def handle_event("log", %{"capture" => params}, socket) do
    socket = socket |> assign(:author, author(socket, params)) |> draft(params["line"] || "")

    with %{} = draft <- socket.assigns.draft || {:error, [{:line, "write a line first"}]},
         {:ok, attrs} <- Capture.to_events(draft, socket.assigns.author),
         {:ok, logged} <- append_all(attrs) do
      {:noreply,
       socket
       |> assign(:line, "")
       |> assign(:draft, nil)
       |> assign(:preview, nil)
       |> assign(:errors, [])
       |> assign(:just_logged, logged.event_id)
       |> load()}
    else
      {:error, errors} -> {:noreply, assign(socket, :errors, List.wrap(errors))}
    end
  end

  @impl true
  def handle_info({:atlas_event, _event}, socket), do: {:noreply, load(socket)}

  # A signed-in author is who they are; only an anonymous one types a name.
  defp author(%{assigns: %{signed_in?: true, author: author}}, _params), do: author
  defp author(_socket, params), do: params["author"] |> to_string() |> String.trim()

  # "yesterday 3pm" is the WRITER's yesterday. The parser is pure and knows no
  # zones, so it is handed the writer's wall clock as if it were UTC, and the
  # moment it returns is moved back by the same offset. A time that was not
  # typed is simply now.
  defp draft(socket, line) do
    offset = socket.assigns.tz_offset * 60
    now = DateTime.utc_now()

    case Capture.parse(line, entities: socket.assigns.entities, now: DateTime.add(now, offset)) do
      {:ok, draft} ->
        at = if draft.timed?, do: DateTime.add(draft.occurred_at, -offset), else: now
        draft = %{draft | occurred_at: at}
        socket |> assign(:line, line) |> assign(:draft, draft) |> preview(draft)

      {:error, :blank} ->
        socket |> assign(:line, line) |> assign(:draft, nil) |> assign(:preview, nil)
    end
  end

  # What this activity would be as transaction data — the same pairs a wallet
  # would be handed. Read-only: nothing here touches a chain.
  defp preview(socket, draft) do
    with {:ok, attrs} <- Capture.to_events(draft, socket.assigns.author |> presence("you")),
         {:ok, event} <- attrs |> List.last() |> Event.new() do
      assign(socket, :preview, %{pairs: MAP.pairs(event), bytes: MAP.byte_size(event)})
    else
      _ -> assign(socket, :preview, nil)
    end
  end

  # Minutes east of UTC, from the browser; 0 when it is not told (and in tests).
  defp tz_offset(socket) do
    case connected?(socket) && get_connect_params(socket)["tz_offset"] do
      offset when is_integer(offset) and offset in -840..840 -> offset
      _ -> 0
    end
  end

  defp presence("", fallback), do: fallback
  defp presence(value, _fallback), do: value

  # Registrations first, then the activity: if a noun fails, the verb that
  # names it is not written. An entity someone else already registered is not
  # an error — the log links to it.
  defp append_all(attrs) do
    Enum.reduce_while(attrs, {:ok, nil}, fn attr, _acc ->
      case Feed.append(attr) do
        {:ok, event} ->
          {:cont, {:ok, event}}

        {:error, errors} ->
          if attr["event_type"] == "log.entity.registered" and Keyword.has_key?(errors, :event_id),
            do: {:cont, {:ok, nil}},
            else: {:halt, {:error, errors}}
      end
    end)
  end

  defp load(socket) do
    events = Feed.events()
    entities = Topology.entities(events)
    actor = "person:#{Capture.slug(socket.assigns.author)}"

    mine =
      events
      |> Enum.filter(&(&1.actor == actor and &1.payload["kind"] == "log"))
      |> Enum.reverse()

    socket
    |> assign(:entities, entities)
    |> assign(:mine, Enum.take(mine, @recent))
    |> assign(:summary, summary(mine, entities, actor))
  end

  # What the log has added up to: the point of logging in one shape.
  defp summary(mine, entities, actor) do
    touched = mine |> Enum.flat_map(& &1.object) |> Enum.reject(&(&1 == actor))

    top = fn list ->
      list |> Enum.frequencies() |> Enum.sort_by(fn {key, n} -> {-n, key} end) |> Enum.take(5)
    end

    %{
      activities: length(mine),
      entities: touched |> Enum.uniq() |> length(),
      verbs: mine |> Enum.map(& &1.payload["verb"]) |> top.(),
      things:
        touched
        |> top.()
        |> Enum.map(fn {ref, n} ->
          {ref, entity_label(entities, ref), entity_kind(entities, ref), n}
        end)
    }
  end

  @doc "An entity's label, or a humanized ref when the record does not know it."
  def entity_label(entities, ref) do
    case entities[ref] do
      %{label: label} -> label
      _ -> Topology.humanize(ref)
    end
  end

  @doc "An entity's kind, from the record or the ref's prefix."
  def entity_kind(entities, ref) do
    case entities[ref] do
      %{kind: kind} -> kind
      _ -> Topology.kind_of(ref)
    end
  end

  @doc "When, on the writer's clock: `offset` is minutes east of UTC."
  def stamp(%DateTime{} = at, offset \\ 0),
    do: at |> DateTime.add(offset * 60) |> Calendar.strftime("%Y-%m-%d %H:%M")

  @doc "A verb id as words: `went-to` → `went to`."
  def verb_words(verb), do: verb |> to_string() |> String.replace("-", " ")
end
