defmodule IndivisualWeb.AtlasLive do
  @moduledoc """
  `/atlas` — a live read interface over the Atlas event stream.

  Three regions: a projection rail (projections, source filters, truth legend), an
  Atlas canvas (server-rendered SVG topology of entities and relationships), and a
  context reader with a timeline scrubber, selected-event details, provenance, and an
  annotation form.

  URL state carries `projection`, `event`, `entity`, and `sources` so a specific
  context can be shared and reproduced. Live appends arrive over PubSub and refresh
  the read model without resetting the selection.
  """

  use IndivisualWeb, :live_view

  alias Indivisual.Atlas
  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Projections
  alias Indivisual.Atlas.Sources.Annotations
  alias Indivisual.Atlas.Topology

  @truth_glyphs %{
    "observed" => "●",
    "reported" => "◐",
    "proposed" => "◇",
    "adopted" => "■",
    "delivered" => "✔",
    "superseded" => "⊘"
  }

  @truth_colors %{
    "observed" => "text-emerald-700 border-emerald-300 bg-emerald-50",
    "reported" => "text-sky-700 border-sky-300 bg-sky-50",
    "proposed" => "text-amber-700 border-amber-300 bg-amber-50",
    "adopted" => "text-indigo-700 border-indigo-300 bg-indigo-50",
    "delivered" => "text-teal-700 border-teal-300 bg-teal-50",
    "superseded" => "text-gray-600 border-gray-300 bg-gray-100"
  }

  @truth_strokes %{
    "observed" => "#047857",
    "reported" => "#0369a1",
    "proposed" => "#b45309",
    "adopted" => "#4338ca",
    "delivered" => "#0f766e",
    "superseded" => "#6b7280"
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Feed.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Atlas")
     |> assign(
       :meta_description,
       "Atlas: a shared, inspectable model of public reality read from an append-only event stream."
     )
     |> assign(:projections, Projections.list())
     |> assign(:sources, Atlas.sources())
     |> assign(:adapters, Feed.adapters())
     |> assign(:live_updates, 0)
     |> assign(:live?, connected?(socket))
     |> assign(:feed_status, Feed.status())
     |> assign(:annotation_form, blank_annotation_form())
     |> assign(:annotation_errors, [])
     |> assign(:range_from, nil)
     |> assign(:range_to, nil)
     |> assign(:show_all, false)
     |> assign(:all_events, [])
     |> assign(:show_legend, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    projection =
      case Projections.get(params["projection"]) do
        nil -> Projections.default_id()
        def -> def.id
      end

    source_filter =
      (params["sources"] || "")
      |> String.split(",", trim: true)
      |> Enum.filter(&Map.has_key?(socket.assigns.sources, &1))

    {:noreply,
     socket
     |> assign(:projection, projection)
     |> assign(:source_filter, source_filter)
     |> assign(:entity, blank_to_nil(params["entity"]))
     |> assign(:requested_event, blank_to_nil(params["event"]))
     |> assign(:range_from, parse_index(params["from"]))
     |> assign(:range_to, parse_index(params["to"]))
     |> assign(:show_all, params["all"] == "1")
     |> load()}
  end

  # --- events ---

  @impl true
  # The radio group posts "projection"; `name="id"` would shadow the form
  # element's own DOM id, which LiveView warns about.
  def handle_event("select_projection", %{"projection" => id}, socket) do
    {:noreply, patch(socket, projection: id)}
  end

  def handle_event("select_projection", %{"id" => id}, socket) do
    {:noreply, patch(socket, projection: id)}
  end

  def handle_event("select_event", %{"id" => id}, socket) do
    {:noreply, patch(socket, event: id)}
  end

  def handle_event("scrub", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {i, _} ->
        case Enum.at(socket.assigns.events, i) do
          nil -> {:noreply, socket}
          event -> {:noreply, patch(socket, event: event.event_id)}
        end

      :error ->
        {:noreply, socket}
    end
  end

  # The range is a FILTER, not a selection: it narrows which events the whole
  # page reads. Either bound may be nil, which is what makes it open-ended.
  def handle_event("range", params, socket) do
    total = length(socket.assigns.all_events)

    from = clamp_index(parse_index(params["from"]), total)
    to = clamp_index(parse_index(params["to"]), total)

    # A dragged-past bound is a reversed range; swap rather than reject it, so
    # the dial never feels stuck.
    {from, to} =
      case {from, to} do
        {f, t} when is_integer(f) and is_integer(t) and f > t -> {t, f}
        pair -> pair
      end

    {:noreply, patch(socket, from: from, to: to, event: nil)}
  end

  def handle_event("show_legend", _params, socket) do
    {:noreply, assign(socket, :show_legend, true)}
  end

  # Not URL state: a legend is reference material, not part of the view someone
  # would share, so it stays out of the shareable path.
  def handle_event("hide_legend", _params, socket) do
    {:noreply, assign(socket, :show_legend, false)}
  end

  def handle_event("toggle_all", _params, socket) do
    if socket.assigns.show_all do
      {:noreply, patch(socket, all: false)}
    else
      # "All" clears the window rather than remembering it: one visible control,
      # one meaning.
      {:noreply, patch(socket, all: true, from: nil, to: nil, event: nil)}
    end
  end

  def handle_event("clear_range", _params, socket) do
    {:noreply, patch(socket, from: nil, to: nil, event: nil)}
  end

  def handle_event("step", %{"dir" => dir}, socket) do
    %{events: events, selected_index: idx} = socket.assigns
    delta = if dir == "prev", do: -1, else: 1
    next = (idx || length(events) - 1) + delta

    case Enum.at(events, next) do
      nil -> {:noreply, socket}
      _ when next < 0 -> {:noreply, socket}
      event -> {:noreply, patch(socket, event: event.event_id)}
    end
  end

  def handle_event("toggle_source", %{"id" => id}, socket) do
    filter = socket.assigns.source_filter

    next =
      if id in filter, do: List.delete(filter, id), else: filter ++ [id]

    {:noreply, patch(socket, sources: next)}
  end

  def handle_event("clear_sources", _params, socket) do
    {:noreply, patch(socket, sources: [])}
  end

  def handle_event("focus_entity", %{"ref" => ref}, socket) do
    {:noreply, patch(socket, projection: "entity", entity: ref)}
  end

  def handle_event("clear_entity", _params, socket) do
    {:noreply, patch(socket, entity: nil)}
  end

  def handle_event("validate_annotation", %{"annotation" => attrs}, socket) do
    {:noreply, assign(socket, :annotation_form, to_form(attrs, as: :annotation))}
  end

  def handle_event("annotate", %{"annotation" => attrs}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, assign(socket, :annotation_errors, [{:event, "select an event to annotate"}])}

      %Event{event_id: about_id} ->
        case Atlas.annotate(about_id, attrs) do
          {:ok, _event} ->
            {:noreply,
             socket
             |> assign(:annotation_form, blank_annotation_form())
             |> assign(:annotation_errors, [])
             |> put_flash(
               :info,
               "Annotation recorded as its own event; source events are unchanged."
             )}

          {:error, errors} ->
            {:noreply,
             socket
             |> assign(:annotation_form, to_form(attrs, as: :annotation))
             |> assign(:annotation_errors, errors)}
        end
    end
  end

  @impl true
  def handle_info({:atlas_event, _event}, socket) do
    {:noreply,
     socket
     |> update(:live_updates, &(&1 + 1))
     |> assign(:feed_status, Feed.status())
     |> assign(:requested_event, selected_id(socket))
     |> load()}
  end

  # --- loading ---

  defp load(socket) do
    %{projection: projection, source_filter: filter, entity: entity, requested_event: requested} =
      socket.assigns

    sources = if filter == [], do: nil, else: filter

    # `all_events` is the source-filtered stream the timeline scrubs over;
    # `events` is that stream narrowed to the selected range. The timeline
    # needs the full extent to draw against, so both are kept.
    all_events = Feed.events(Feed, sources: sources)

    events =
      if socket.assigns.show_all,
        do: all_events,
        else: slice_range(all_events, socket.assigns.range_from, socket.assigns.range_to)

    selected =
      Enum.find(events, &(&1.event_id == requested)) || List.last(events)

    selected_index = if selected, do: Enum.find_index(events, &(&1.event_id == selected.event_id))

    read_model =
      Projections.materialize(projection, events,
        entity: entity,
        until: selected && selected.event_id
      )

    affected = if selected, do: Event.affected_refs(selected), else: []
    all_relationships = Topology.relationships(events)

    socket
    |> assign(:all_events, all_events)
    |> assign(:events, events)
    |> assign(:selected, selected)
    |> assign(:selected_index, selected_index)
    |> assign(:read_model, read_model)
    |> assign(:affected, affected)
    |> assign(
      :selected_relationships,
      if(selected,
        do: Enum.filter(all_relationships, &(&1.event_id == selected.event_id)),
        else: []
      )
    )
    |> assign(
      :entity_relationships,
      Enum.flat_map(affected, &Topology.relationships_for(all_relationships, &1)) |> Enum.uniq()
    )
    |> assign(
      :annotations_for_selected,
      if(selected, do: annotations_about(events, selected.event_id), else: [])
    )
    |> assign(:share_path, share_path(socket, selected))
  end

  defp annotations_about(events, about_id) do
    Enum.filter(events, fn e ->
      Event.annotation?(e) and e.payload["about_event_id"] == about_id
    end)
  end

  defp selected_id(socket) do
    case socket.assigns[:selected] do
      %Event{event_id: id} -> id
      _ -> nil
    end
  end

  defp patch(socket, changes) do
    current = %{
      projection: socket.assigns.projection,
      event: selected_id(socket),
      entity: socket.assigns.entity,
      sources: socket.assigns.source_filter,
      from: socket.assigns[:range_from],
      to: socket.assigns[:range_to],
      all: socket.assigns[:show_all]
    }

    next = Map.merge(current, Map.new(changes))
    push_patch(socket, to: path_for(next))
  end

  # --- timeline range ---

  defp parse_index(nil), do: nil
  defp parse_index(""), do: nil

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} when i >= 0 -> i
      _ -> nil
    end
  end

  defp parse_index(i) when is_integer(i) and i >= 0, do: i
  defp parse_index(_), do: nil

  defp clamp_index(nil, _total), do: nil
  defp clamp_index(_i, 0), do: nil
  defp clamp_index(i, total), do: i |> max(0) |> min(total - 1)

  # Either bound may be nil — that is what "open ended either way" means: a
  # nil start reads from the beginning, a nil end runs to the present.
  defp slice_range(events, nil, nil), do: events

  defp slice_range(events, from, to) do
    last = length(events) - 1
    first = from || 0
    final = to || last

    if first > final or events == [] do
      []
    else
      Enum.slice(events, first..final)
    end
  end

  defp share_path(socket, selected) do
    path_for(%{
      projection: socket.assigns.projection,
      event: selected && selected.event_id,
      entity: socket.assigns.entity,
      sources: socket.assigns.source_filter,
      from: socket.assigns.range_from,
      to: socket.assigns.range_to,
      all: socket.assigns.show_all
    })
  end

  defp path_for(%{projection: projection, event: event, entity: entity, sources: sources} = opts) do
    query =
      []
      |> maybe_put(
        :projection,
        if(projection == Projections.default_id(), do: nil, else: projection)
      )
      |> maybe_put(:event, event)
      |> maybe_put(:entity, entity)
      |> maybe_put(:sources, if(sources in [nil, []], do: nil, else: Enum.join(sources, ",")))
      |> maybe_put(:from, opts[:from])
      |> maybe_put(:to, opts[:to])
      |> maybe_put(:all, if(opts[:all], do: "1", else: nil))

    ~p"/atlas?#{query}"
  end

  defp maybe_put(query, _key, nil), do: query
  defp maybe_put(query, key, value), do: query ++ [{key, value}]

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp blank_annotation_form do
    to_form(%{"kind" => "question", "body" => "", "author" => ""}, as: :annotation)
  end

  # --- template helpers ---

  @doc "Glyph for a truth state (text cue, independent of color)."
  def truth_glyph(state), do: Map.get(@truth_glyphs, state, "○")

  @doc "Tailwind classes for a truth-state badge."
  def truth_classes(state),
    do: Map.get(@truth_colors, state, "text-gray-600 border-gray-300 bg-gray-50")

  @doc "SVG stroke color for a truth state."
  def truth_stroke(state), do: Map.get(@truth_strokes, state, "#6b7280")

  @doc "Label for an entity ref using the read model's entities, falling back to a humanized ref."
  def entity_label(%{entities: entities}, ref) do
    case Map.get(entities, ref) do
      %{label: label} -> label
      _ -> Topology.humanize(ref)
    end
  end

  @doc "Source title for a source id."
  def source_title(sources, id) do
    case Map.get(sources, id) do
      %{title: title} -> title
      _ -> id
    end
  end

  @doc "Source status label for a source id (e.g. linked, indexed, fixture, in-memory)."
  def source_status(sources, id) do
    case Map.get(sources, id) do
      %{status: status} -> status
      _ -> "unregistered"
    end
  end

  @doc "Source URL for a source id, if registered."
  def source_url(sources, id) do
    case Map.get(sources, id) do
      %{url: url} -> url
      _ -> nil
    end
  end

  @doc "Date portion of a datetime, or `—`."
  def date(nil), do: "—"
  def date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  @truth_descriptions %{
    "observed" => "present in a primary record or seen directly",
    "reported" => "asserted by a source, not independently confirmed",
    "proposed" => "suggested or applied for, not yet adopted",
    "adopted" => "formally authorized",
    "delivered" => "carried out in the world",
    "superseded" => "replaced by a later record"
  }

  @doc "One-line meaning of a truth state, for the legend."
  def truth_description(state), do: Map.get(@truth_descriptions, state, "")

  @doc "Name of the active projection, for the always-visible menu summary."
  def projection_name(projections, id) do
    case Enum.find(projections, &(&1.id == id)) do
      nil -> "—"
      def -> def.name
    end
  end

  @doc "Date at one index of the timeline, for a range dial's accessible value."
  def index_label(events, index) do
    case Enum.at(events, index) do
      nil -> "—"
      event -> date(Event.effective_time(event))
    end
  end

  @doc """
  Human label for the selected range. An open bound is named as open rather
  than silently filled in with the extent.
  """
  def range_label(events, from, to) do
    last = max(length(events) - 1, 0)

    start_text = if from, do: index_label(events, from), else: "start"
    end_text = if to, do: index_label(events, to), else: "now"

    cond do
      is_nil(from) and is_nil(to) -> "full range"
      from == to -> index_label(events, from || last)
      true -> "#{start_text} → #{end_text}"
    end
  end

  @doc "Full ISO timestamp, or `—`."
  def stamp(nil), do: "—"
  def stamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @doc "Renders a sequence list like `[7, 2]` as `7.2`."
  def sequence(seq) when is_list(seq), do: Enum.join(seq, ".")

  @doc "Annotation kinds for the form select."
  def annotation_kinds, do: Annotations.kinds()

  @doc "Adapter status for a source id."
  def adapter_status(sources, id) do
    case Map.get(sources, id) do
      %{adapter: %{status: status}} -> status
      _ -> nil
    end
  end

  @doc "Total events across all sources (ignores filter), for the rail counts."
  def source_count(events, source_id), do: Enum.count(events, &(&1.source_id == source_id))
end
