defmodule IndivisualWeb.AtlasLive do
  @moduledoc """
  `/atlas` — a live read interface over the Atlas event stream.

  A controls band (the timeline range bar), then three columns: the activity list
  with the filters that narrow it, a reader (the selected record, or the focused
  entity, or a description of the view), and a canvas (3D volume, map, and a
  server-rendered SVG graph of entities and relationships).

  There is no mode switch. The four `Atlas.Projections` are still what the page
  is built from, but each is always on screen where it belongs — activity is the
  list, topology the graph, entity context the reader under a focus, provenance
  the truth-state filter — so nothing asks the reader to choose between them.

  URL state carries `event`, `entity`, `sources`, `truth`, the range, and the
  graph's `connected` toggle, so a specific context can be shared and reproduced.
  Live appends arrive over PubSub and refresh
  the read model without resetting the selection.
  """

  use IndivisualWeb, :live_view

  alias Indivisual.Atlas
  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Extract
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Glossary
  alias Indivisual.Explain
  alias Indivisual.SceneModes
  alias Indivisual.Atlas.Post
  alias Indivisual.Atlas.Profile
  alias Indivisual.Atlas.Projections
  alias Indivisual.Atlas.Scatter
  alias Indivisual.Atlas.Scene
  alias Indivisual.Atlas.Semantics
  alias Indivisual.Atlas.Sources.Annotations
  alias Indivisual.Atlas.Geo
  alias Indivisual.Atlas.Timeline
  alias Indivisual.Atlas.Topology
  alias IndivisualWeb.AtlasComponents
  alias IndivisualWeb.AtlasLive.ViewSync

  # `?event=none`: the reader closed the record and wants the view, not a record.
  @no_selection "none"

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

  @truth_none ["none"]

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
    if connected?(socket) do
      Feed.subscribe()
      # New semantic scores arrive when an embedding batch lands.
      Semantics.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Atlas")
     |> assign(
       :meta_description,
       "Atlas: a shared, inspectable model of public reality read from an append-only event stream."
     )
     |> assign(:sources, Atlas.sources())
     |> assign(:adapters, Feed.adapters())
     |> assign(:live_updates, 0)
     |> assign(:live?, connected?(socket))
     # The semantic axes there are: each is a dimension the scene can put on an
     # axis. Read once per mount, and again when scores change.
     |> assign_semantic_axes()
     # Linked tabs (see ViewSync). A token is minted up front so "Detach" can be
     # a plain link: a new tab opened after a server round-trip would be blocked
     # as a pop-up.
     |> assign(:view_token, nil)
     |> assign(:detach_target, "atlas-timeline")
     |> assign(:spare_token, ViewSync.token())
     |> assign(:pane, nil)
     |> assign(:raw_params, %{})
     |> assign(:view_adopting, nil)
     |> assign(:view_joining?, false)
     |> assign(:reattached?, false)
     |> assign(:feed_status, Feed.status())
     |> assign(:annotation_form, blank_annotation_form())
     |> assign(:annotation_errors, [])
     |> assign(:composing?, false)
     |> assign(:post_form, blank_post_form())
     |> assign(:post_errors, [])
     # Which days of the activity list are folded to their heading. How the list
     # is being read, not what is being read — so it is not URL state.
     |> assign(:collapsed_days, MapSet.new())
     # The reader's own Spacetime modes. Signed out there are none, and none asked for.
     |> load_scene_modes()
     |> assign(:mode_form, to_form(%{"name" => ""}, as: :mode))
     |> assign(:range_from, nil)
     |> assign(:range_to, nil)
     |> assign(:show_all, false)
     |> assign(:entity_total, 0)
     |> assign(:range_outside?, false)
     |> assign(:all_events, [])
     |> assign(:scene_events, [])
     |> assign(:show_legend, false)
     |> assign(:lanes?, false)
     |> assign(:timeline_open?, true)
     |> assign(:scrubber_open?, true)
     |> assign(:timeline, Timeline.build([]))
     |> assign(:scatter, Scatter.build([]))
     |> assign(:scene, Scene.build([], %{}, []))
     |> assign(:scene_layout, Scene.default_layout())
     |> assign(:scene_axes, Scene.layout(Scene.default_layout()).dims)
     |> assign(:scene_def, Scene.layout(Scene.default_layout()))
     |> assign(:semantic_status, :idle)
     |> assign(:band_dom?, false)
     |> assign(:fit_all?, false)
     |> assign(:strip, %{extent: nil, focus: nil, beyond: %{earlier: 0, later: 0}, nodes: []})
     |> assign(:strip_lanes, 0)
     |> assign(:explain, nil)
     |> assign(:explain_event, nil)
     |> assign(:explain_error, nil)
     |> assign(:explain_available?, Explain.available?())
     # Which model writes is the reader's choice, for this visit: it is an
     # instrument they bring, not a property of the record, so it is not in the
     # shareable URL. `explain_models` is nil until the picker is first opened.
     |> assign(:explain_model, Explain.model())
     |> assign(:explain_models, nil)
     |> assign(:explain_picker?, false)
     |> assign(:explain_open?, false)
     |> assign(:stream, stream_context([], nil))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    connected_only? = params["connected"] == "1"

    source_filter =
      (params["sources"] || "")
      |> String.split(",", trim: true)
      |> Enum.filter(&Map.has_key?(socket.assigns.sources, &1))

    socket = join_view(socket, ViewSync.parse_token(params["v"]))
    was_selected = socket.assigns[:selected]

    {:noreply,
     socket
     |> assign(:raw_params, params)
     |> assign(:pane, ViewSync.parse_pane(params["pane"]))
     |> assign(:connected_only?, connected_only?)
     |> assign(:source_filter, source_filter)
     |> assign(:truth_filter, parse_truth(params["truth"]))
     |> assign(
       :speech_filter,
       (params["speech"] || "")
       |> String.split(",", trim: true)
       |> Enum.filter(&(&1 in Event.parts_of_speech()))
     )
     |> assign(:entity, blank_to_nil(params["entity"]))
     |> assign(:requested_event, blank_to_nil(params["event"]))
     |> assign(:range_from, parse_index(params["from"]))
     |> assign(:range_to, parse_index(params["to"]))
     |> assign(:show_all, params["all"] == "1")
     # With no window there is no outside, so a stray out=1 is dropped here
     # rather than leaving the switch saying one thing and the page another.
     |> assign(
       :range_outside?,
       params["out"] == "1" and
         not (is_nil(parse_index(params["from"])) and is_nil(parse_index(params["to"])))
     )
     |> assign(:lanes?, params["lanes"] == "1")
     |> assign_scene_axes(params)
     # The sticky band is the Spacetime strip; `?band=dom` draws plain DOM marks
     # instead, for browsers without WebGL.
     |> assign(:band_dom?, params["band"] == "dom")
     # The timeline focuses on what the filters leave; `fit=all` holds it on the
     # whole record instead.
     |> assign(:fit_all?, params["fit"] == "all")
     |> assign(:timeline_open?, params["tl"] != "0")
     |> assign(:scrubber_open?, params["sc"] != "0")
     |> assign(:explain_event, nil)
     |> assign(:explain_error, nil)
     |> load()
     |> reveal_selected(was_selected)
     |> tell_view(params)}
  end

  # A record chosen from anywhere else — the timeline, Prev / Next, the scene —
  # has to be findable in the list, so choosing one opens its day if it was
  # folded. Only on a CHANGE of selection: folding the open record's day
  # afterwards is the reader's call, and a live append must not undo it.
  defp reveal_selected(%{assigns: %{selected: %Event{} = now}} = socket, was) do
    if was && was.event_id == now.event_id do
      socket
    else
      update(socket, :collapsed_days, &MapSet.delete(&1, date(Event.effective_time(now))))
    end
  end

  defp reveal_selected(socket, _was), do: socket

  defp assign_semantic_axes(socket) do
    axes = Indivisual.Semantic.list_axes(computed_only: true)

    socket
    |> assign(:semantic_axes, axes)
    |> assign(:semantic_dims, Semantics.dimensions(axes))
  end

  # Asks for the whole record to be embedded (a no-op once it is) and says where
  # that stands, so the scene can explain an unscored layout instead of looking
  # broken. Only a connected view asks: the static render must not start work.
  defp semantic_status(socket, events) do
    cond do
      socket.assigns.semantic_axes == [] ->
        :no_axes

      # Axes exist, but none was computed with the embedding model in use: a
      # vector from another model lives in another space, so nothing can be
      # scored against it until it is recomputed.
      socket.assigns.semantic_dims == [] ->
        :other_model

      not connected?(socket) ->
        :idle

      true ->
        Semantics.warm(events)
        Semantics.status()
    end
  end

  defp signed_in(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{id: _}} = scope -> scope
      _ -> nil
    end
  end

  defp load_scene_modes(socket) do
    modes = if scope = signed_in(socket), do: SceneModes.list(scope), else: []
    assign(socket, :scene_modes, modes)
  end

  # The Spacetime layout is a choice of three dimensions, one per axis. A preset
  # is named in `scene`; a reader's own choice rides in `axes` and is the
  # "custom" layout. Anything that does not parse falls back to a preset.
  defp assign_scene_axes(socket, params) do
    semantic = socket.assigns.semantic_dims
    custom = if params["scene"] == "custom", do: Scene.parse_axes(params["axes"], semantic)

    {layout, axes} =
      if custom,
        do: {"custom", custom},
        else:
          {Scene.layout(params["scene"], semantic).id,
           Scene.layout(params["scene"], semantic).dims}

    socket
    |> assign(:scene_layout, layout)
    |> assign(:scene_axes, axes)
    |> assign(:scene_def, scene_def(layout, axes, semantic))
  end

  # What the panel says about the layout on show. A custom one describes itself
  # from its axes, and owns up to any placeholder among them.
  defp scene_def("custom", axes, semantic) do
    semantic? = Enum.any?(axes, &String.starts_with?(&1, "sem:"))

    %{
      id: "custom",
      name: "Custom",
      basis: if(semantic?, do: :semantic, else: :data),
      says:
        "Your own choice of axes: " <>
          Enum.map_join(Enum.zip(~w(x y z), axes), ", ", fn {axis, dim} ->
            "#{axis} is #{Scene.dimension(dim, semantic).name |> String.trim_leading("— ")}"
          end) <> "."
    }
  end

  defp scene_def(layout, _axes, semantic), do: Scene.layout(layout, semantic)

  # --- linked tabs ---

  # Subscribes to the view named in the URL (and leaves any other). On arrival
  # it says hello, so a tab that is already there can bring this one up to date.
  defp join_view(%{assigns: %{view_token: token}} = socket, token), do: socket

  defp join_view(socket, token) do
    if connected?(socket) do
      if old = socket.assigns.view_token,
        do: Phoenix.PubSub.unsubscribe(Indivisual.PubSub, ViewSync.topic(old))

      if token do
        Phoenix.PubSub.subscribe(Indivisual.PubSub, ViewSync.topic(token))
        tell(token, {:view_hello, socket.id})
      end
    end

    # A tab that has just joined LISTENS first. If it announced the state in its
    # own URL, a bare `?v=…` link would wipe the filters of everyone already on
    # the view; instead it says hello, and whoever is there brings it up to date.
    socket
    |> assign(:view_token, token)
    |> assign(:view_joining?, not is_nil(token))
  end

  # Tells the other tabs what this one is now reading — unless this change IS
  # what another tab just told us, in which case repeating it would only echo.
  defp tell_view(%{assigns: %{view_token: nil}} = socket, _params), do: socket

  defp tell_view(socket, params) do
    shared = ViewSync.shared(params)

    if connected?(socket) and not socket.assigns.view_joining? and
         shared != socket.assigns.view_adopting,
       do: tell(socket.assigns.view_token, {:view_state, socket.id, shared})

    socket
    |> assign(:view_adopting, nil)
    |> assign(:view_joining?, false)
  end

  defp tell(token, message),
    do: Phoenix.PubSub.broadcast(Indivisual.PubSub, ViewSync.topic(token), message)

  # --- events ---

  @impl true
  # The radio group posts "projection"; `name="id"` would shadow the form
  # element's own DOM id, which LiveView warns about.
  # Kept for `AtlasComponents.projection_nav/1`, which is unmounted: remounting
  # it should be one tag. Its only remaining effect is Topology's.
  def handle_event("select_projection", %{"projection" => id}, socket) do
    {:noreply, patch(socket, connected: id == "topology")}
  end

  def handle_event("select_projection", %{"id" => id}, socket) do
    {:noreply, patch(socket, connected: id == "topology")}
  end

  # A filter on the graph, so it lives on the graph, says what it is set to, and
  # says what it removed.
  def handle_event("toggle_connected", _params, socket) do
    {:noreply, patch(socket, connected: not socket.assigns.connected_only?)}
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

    # A handle resting on the end of the bar is an OPEN bound, not index 0 or
    # index N. The difference is live data: "to the last event I saw" silently
    # excludes whatever arrives next, where "to the present" does not — and a
    # handle at the far right plainly means the second.
    from = if from == 0, do: nil, else: from
    to = if to == total - 1, do: nil, else: to

    # Outside-of-nothing is nothing, so the mode falls back with the bounds.
    outside? = socket.assigns.range_outside? and not (is_nil(from) and is_nil(to))

    # Dragging a handle IS setting a filter, so it cannot sit beside a checked
    # "All events": the box clears itself the moment the range means something.
    # The handles are never disabled for that reason — a control that has to be
    # unlocked before it can be used is one step too many.
    all? = socket.assigns.show_all and is_nil(from) and is_nil(to)

    {:noreply, patch(socket, from: from, to: to, out: outside?, all: all?, event: nil)}
  end

  # The same window, read from the other side: what happened outside it.
  def handle_event("range_mode", %{"mode" => mode}, socket) do
    %{range_from: from, range_to: to} = socket.assigns
    bounded? = not (is_nil(from) and is_nil(to))

    {:noreply, patch(socket, out: mode == "out" and bounded?, event: nil)}
  end

  def handle_event("show_legend", _params, socket) do
    {:noreply, assign(socket, :show_legend, true)}
  end

  # Not URL state: a legend is reference material, not part of the view someone
  # would share, so it stays out of the shareable path.
  def handle_event("hide_legend", _params, socket) do
    {:noreply, assign(socket, :show_legend, false)}
  end

  # Reference material, like the legend: not part of a view someone would
  # share, so it stays out of the URL.
  def handle_event("explain", %{"term" => slug}, socket) do
    case Glossary.get(slug) do
      nil -> {:noreply, socket}
      term -> {:noreply, assign(socket, :explain, Map.put(term, :slug, slug))}
    end
  end

  def handle_event("hide_explain", _params, socket) do
    {:noreply, assign(socket, :explain, nil)}
  end

  # Runs off the LiveView process so a slow model never blocks the page; the
  # result arrives as a message and is shown if the selection has not moved on.
  def handle_event("explain_event", _params, %{assigns: %{selected: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("explain_event", _params, socket) do
    %{selected: event, events: events, sources: sources, explain_model: model} = socket.assigns

    # `start_async`, not a bare task: LiveView owns it, so it dies with the
    # view, a newer request replaces an older one, and tests can wait for it
    # (`render_async/1`) instead of racing it.
    {:noreply,
     socket
     |> assign(:explain_event, {event.event_id, :loading})
     |> assign(:explain_error, nil)
     |> start_async(:explain, fn ->
       {event.event_id, Explain.explain_event(event, events, sources: sources, model: model)}
     end)}
  end

  # The badge opens a picker. The list is asked for each time it opens — models
  # are pulled and removed outside this app — and off the LiveView process, so a
  # stopped Ollama costs a message, not a frozen page.
  def handle_event(
        "toggle_explain_models",
        _params,
        %{assigns: %{explain_picker?: true}} = socket
      ) do
    {:noreply, assign(socket, :explain_picker?, false)}
  end

  def handle_event("toggle_explain_models", _params, socket) do
    {:noreply,
     socket
     |> assign(:explain_picker?, true)
     |> assign(:explain_models, :loading)
     |> start_async(:explain_models, fn -> Explain.models() end)}
  end

  # Only a model the backend just listed: the name arrives from the browser and
  # goes into a request, so it is checked against what was offered.
  def handle_event("select_explain_model", %{"model" => model}, socket) do
    case socket.assigns.explain_models do
      {:ok, models} ->
        if model in models do
          {:noreply,
           socket
           |> assign(:explain_model, model)
           |> assign(:explain_picker?, false)
           # Whatever is on screen was written by the previous model; leaving it
           # under the new model's name would misattribute it.
           |> assign(:explain_event, nil)
           |> assign(:explain_error, nil)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # The ✦ at the top of the record opens the explain panel as a floating card.
  # How the record is being read, not what is read: not URL state.
  def handle_event("toggle_explain_panel", _params, socket) do
    {:noreply,
     socket
     |> update(:explain_open?, &(not &1))
     |> assign(:explain_picker?, false)}
  end

  def handle_event("hide_explain_event", _params, socket) do
    {:noreply, socket |> assign(:explain_event, nil) |> assign(:explain_error, nil)}
  end

  # Collapsed state rides the URL like every other view choice, so a shared
  # link reproduces the layout someone was actually looking at.
  def handle_event("toggle_timeline", _params, socket) do
    {:noreply, patch(socket, tl: not socket.assigns.timeline_open?)}
  end

  def handle_event("toggle_scrubber", _params, socket) do
    {:noreply, patch(socket, sc: not socket.assigns.scrubber_open?)}
  end

  # Which layout the Spacetime scene is in. View state, so it rides the URL and a
  # shared link lands on the same slice.
  def handle_event("scene_layout", %{"layout" => id}, socket) do
    {:noreply, patch(socket, scene: Scene.layout(id, socket.assigns.semantic_dims).id, axes: nil)}
  end

  # Detach: this tab keeps the view and gives up its controls; the link that was
  # clicked opens them in a new tab on the same token (see `detach_path`).
  def handle_event("detach", _params, socket) do
    token = socket.assigns.view_token || socket.assigns.spare_token
    {:noreply, patch(socket, v: token, pane: "view")}
  end

  def handle_event("reattach", _params, socket) do
    if token = socket.assigns.view_token, do: tell(token, {:view_reattached, socket.id})
    {:noreply, patch(socket, pane: nil)}
  end

  # The timeline's end caps: let go of the date range on one side, so the view
  # takes in what the record holds beyond it.
  def handle_event("open_bound", %{"side" => "start"}, socket) do
    {:noreply, patch(socket, from: nil, event: nil)}
  end

  def handle_event("open_bound", %{"side" => "end"}, socket) do
    {:noreply, patch(socket, to: nil, event: nil)}
  end

  # Saved modes. A mode is only a NAME for a set of axes: choosing one patches to
  # those axes, exactly as the dropdowns would, so the URL never depends on it.
  def handle_event("choose_mode", %{"mode_id" => id}, socket) do
    case Enum.find(socket.assigns.scene_modes, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      mode -> {:noreply, patch(socket, scene: "custom", axes: Enum.join(mode.axes, ","))}
    end
  end

  def handle_event("validate_mode", %{"mode" => attrs}, socket) do
    {:noreply, assign(socket, :mode_form, to_form(attrs, as: :mode))}
  end

  def handle_event("save_mode", %{"mode" => %{"name" => name} = attrs}, socket) do
    case signed_in(socket) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sign in to save a mode of your own.")}

      scope ->
        case SceneModes.create(scope, %{name: name, axes: socket.assigns.scene_axes}) do
          {:ok, mode} ->
            {:noreply,
             socket
             |> load_scene_modes()
             |> assign(:mode_form, to_form(%{"name" => ""}, as: :mode))
             |> put_flash(:info, "Saved “#{mode.name}” as one of your modes.")}

          {:error, changeset} ->
            # Shown against the name: it is the only thing the form asks for.
            errors = Enum.map(changeset.errors, fn {_field, error} -> {:name, error} end)
            {:noreply, assign(socket, :mode_form, to_form(attrs, as: :mode, errors: errors))}
        end
    end
  end

  def handle_event("delete_mode", %{"id" => id}, socket) do
    with %{} = scope <- signed_in(socket),
         {:ok, _mode} <- SceneModes.delete(scope, id) do
      {:noreply,
       socket
       |> load_scene_modes()
       |> put_flash(:info, "Mode deleted. Its axes are still on screen.")}
    else
      _ -> {:noreply, socket}
    end
  end

  # An axis dropdown changed. Three dimensions that are exactly a preset's ARE
  # that preset (so longitude / latitude / time is the map, tiles and all);
  # anything else is the reader's own layout, carried in the URL.
  def handle_event("scene_axes", %{"axes" => %{"x" => x, "y" => y, "z" => z}}, socket) do
    case Scene.parse_axes([x, y, z], socket.assigns.semantic_dims) do
      nil ->
        {:noreply, socket}

      axes ->
        layout = Scene.layout_for(axes, socket.assigns.semantic_dims)

        {:noreply,
         patch(socket, scene: layout, axes: if(layout == "custom", do: Enum.join(axes, ",")))}
    end
  end

  # Whether the timeline is zoomed to what the filters leave, or to everything.
  def handle_event("timeline_fit", %{"layout" => mode}, socket) do
    {:noreply, patch(socket, fit: mode == "all")}
  end

  def handle_event("toggle_lanes", _params, socket) do
    {:noreply, patch(socket, lanes: not socket.assigns.lanes?)}
  end

  def handle_event("toggle_all", _params, socket) do
    if socket.assigns.show_all do
      {:noreply, patch(socket, all: false)}
    else
      # "All" clears the window rather than remembering it: one visible control,
      # one meaning.
      {:noreply, patch(socket, all: true, from: nil, to: nil, out: false, event: nil)}
    end
  end

  def handle_event("clear_range", _params, socket) do
    {:noreply, patch(socket, from: nil, to: nil, out: false, event: nil)}
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

  # The activity list's checklists. Same filter as `toggle_source`, opposite
  # reading: there a pressed button narrows TO a source, here a checked box
  # means a source is included — so unchecking from "all" leaves the rest.
  def handle_event("check_source", %{"source" => id}, socket) do
    %{sources: sources, source_filter: filter} = socket.assigns

    case toggle_inclusion(Map.keys(sources), filter, id) do
      :unchanged -> {:noreply, socket}
      next -> {:noreply, patch(socket, sources: next)}
    end
  end

  # Truth state is a filter on the same terms as source: it changes what is
  # read, never what was recorded.
  def handle_event("check_truth", %{"state" => state}, socket) do
    case toggle_inclusion(Event.truth_states(), socket.assigns.truth_filter, state) do
      :unchanged -> {:noreply, socket}
      next -> {:noreply, patch(socket, truth: next, event: nil)}
    end
  end

  # Verbs and nouns: the same checklist contract as source and truth state.
  def handle_event("check_speech", %{"part" => part}, socket) do
    case toggle_inclusion(Event.parts_of_speech(), socket.assigns.speech_filter, part) do
      :unchanged -> {:noreply, socket}
      next -> {:noreply, patch(socket, speech: next, event: nil)}
    end
  end

  def handle_event("clear_truth", _params, socket) do
    {:noreply, patch(socket, truth: [], event: nil)}
  end

  def handle_event("clear_speech", _params, socket) do
    {:noreply, patch(socket, speech: [], event: nil)}
  end

  # Deliberately nothing: the quick way from "all six" to "just this one" is
  # none, then one click — rather than unchecking five. It is a real state with
  # its own URL, not a transient one, and the page says the list is empty
  # because of it. The last checked chip still cannot be unchecked: that guard
  # is against landing on an empty list by accident, and this is on purpose.
  def handle_event("none_truth", _params, socket) do
    {:noreply, patch(socket, truth: @truth_none, event: nil)}
  end

  def handle_event("focus_entity", %{"ref" => ref}, socket) do
    {:noreply, patch(socket, entity: ref)}
  end

  # "No selection" is a state of its own, distinct from "nothing requested"
  # (which selects the latest event). It is spelled out in the URL so a shared
  # link can land on the view itself rather than on a record.
  def handle_event("clear_selection", _params, socket) do
    {:noreply, patch(socket, event: @no_selection)}
  end

  # The way back from a view the filters have emptied. Drops every filter and
  # nothing else: the graph's own toggle, layout and lanes are not what hid the events.
  def handle_event("reset_filters", _params, socket) do
    {:noreply,
     patch(socket,
       sources: [],
       truth: [],
       speech: [],
       entity: nil,
       from: nil,
       to: nil,
       out: false,
       event: nil
     )}
  end

  def handle_event("clear_entity", _params, socket) do
    {:noreply, patch(socket, entity: nil)}
  end

  # Folding the activity list by day.
  def handle_event("toggle_day", %{"day" => day}, socket) do
    collapsed = socket.assigns.collapsed_days

    next =
      if MapSet.member?(collapsed, day),
        do: MapSet.delete(collapsed, day),
        else: MapSet.put(collapsed, day)

    {:noreply, assign(socket, :collapsed_days, next)}
  end

  def handle_event("days_all", _params, socket) do
    {:noreply, assign(socket, :collapsed_days, MapSet.new())}
  end

  def handle_event("days_none", _params, socket) do
    days = socket.assigns.events |> activity_days() |> MapSet.new(&elem(&1, 0))
    {:noreply, assign(socket, :collapsed_days, days)}
  end

  # The composer is not URL state: a half-written post is not part of a view
  # anyone would share.
  def handle_event("toggle_compose", _params, socket) do
    {:noreply,
     socket
     |> update(:composing?, &(not &1))
     |> assign(:post_errors, [])}
  end

  # "Annotate this record", from the record itself: the same composer, opened
  # as an annotation. What is already typed is kept.
  def handle_event("compose_annotation", params, socket) do
    attrs = Map.put(socket.assigns.post_form.params, "type", "annotation")

    # A kind badge on the record opens the composer already set to that kind: the
    # speech act is chosen where the record is being read, and the form is left
    # with one thing to do — the note.
    attrs =
      if params["kind"] in Annotations.kinds(),
        do: Map.put(attrs, "kind", params["kind"]),
        else: attrs

    {:noreply,
     socket
     |> assign(:composing?, true)
     |> assign(:post_errors, [])
     |> assign(:post_form, to_form(attrs, as: :post))}
  end

  def handle_event("validate_post", %{"post" => attrs}, socket) do
    {:noreply, assign(socket, :post_form, to_form(attrs, as: :post))}
  end

  # The kind, as a badge in the form too (the same badges the record offers).
  def handle_event("set_post_kind", %{"kind" => kind}, socket) do
    if kind in Annotations.kinds() do
      attrs = Map.put(socket.assigns.post_form.params, "kind", kind)
      {:noreply, assign(socket, :post_form, to_form(attrs, as: :post))}
    else
      {:noreply, socket}
    end
  end

  # One handler for both subclasses of a post: the type decides whether it is
  # about the open record (an annotation) or stands alone (a note). Either way
  # it appends one event and changes nothing else.
  def handle_event("publish_post", %{"post" => attrs}, socket) do
    %{selected: selected, entity: entity} = socket.assigns

    # Who wrote it is who is signed in — never what the form says. And what the
    # note was read as is worked out HERE, from the text, not taken from the
    # browser: the chips under the note are this same function's output.
    found = Extract.mentions(attrs["body"] || "", socket.assigns.read_model.entities)

    attrs =
      attrs
      |> Map.put("author", signed_in_handle(socket) || attrs["author"])
      |> Map.put("mentions", Extract.payload(found)["mentions"] || [])

    result =
      case {attrs["type"], selected} do
        {"annotation", %Event{event_id: about_id} = about} ->
          if annotatable?(about),
            do: Atlas.annotate(about_id, attrs),
            else: {:error, [{:annotation, "must be about a source record, not another post"}]}

        {"annotation", nil} ->
          {:error, [{:annotation, "needs an open record to be about"}]}

        _note ->
          # A note is about the entity in focus, and about every entity it names.
          Atlas.post(attrs, mentions: Enum.uniq(List.wrap(entity) ++ Extract.refs(found)))
      end

    case result do
      {:ok, event} ->
        {:noreply,
         socket
         |> assign(:composing?, false)
         |> assign(:post_form, blank_post_form(attrs["author"]))
         |> assign(:post_errors, [])
         |> put_flash(:info, post_flash(event))
         # Open what was just written, so the reader sees it land in the record.
         |> patch(event: event.event_id)}

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(:post_form, to_form(attrs, as: :post))
         |> assign(:post_errors, errors)}
    end
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

  # Test-only: lets a test observe the loading state, which a fast adapter
  # would otherwise skip straight past.
  @impl true
  def handle_info({:force_explain_loading, event_id}, socket) do
    {:noreply, assign(socket, :explain_event, {event_id, :loading})}
  end

  # A stale result (the reader moved on) is dropped rather than shown against
  # the wrong record.
  # The same arrival, as a message: kept so a late or foreign result can be shown
  # to be dropped (see the explain tests).
  def handle_info({:explanation, event_id, result}, socket),
    do: explanation(socket, event_id, result)

  # Another tab on this view changed what it is reading: read the same. This
  # tab's own pane, layout and folded panels are left as they are.
  @impl true
  def handle_info({:view_state, from, shared}, socket) do
    if from == socket.id or shared == ViewSync.shared(socket.assigns.raw_params) do
      {:noreply, socket}
    else
      query = ViewSync.adopt(socket.assigns.raw_params, shared)

      {:noreply,
       socket
       |> assign(:view_adopting, ViewSync.shared(shared))
       |> push_patch(to: ~p"/atlas?#{query}")}
    end
  end

  # A tab has just joined: tell it where the view stands.
  def handle_info({:view_hello, from}, socket) do
    if from != socket.id and socket.assigns.view_token do
      tell(
        socket.assigns.view_token,
        {:view_state, socket.id, ViewSync.shared(socket.assigns.raw_params)}
      )
    end

    {:noreply, socket}
  end

  # The main tab took its timeline back; a detached timeline tab says so.
  def handle_info({:view_reattached, from}, socket) do
    {:noreply,
     assign(socket, :reattached?, from != socket.id and socket.assigns.pane == "timeline")}
  end

  # An embedding batch landed (or failed): re-read the axes and redraw.
  def handle_info({:atlas_semantics, :updated}, socket) do
    {:noreply, socket |> assign_semantic_axes() |> load()}
  end

  def handle_info({:atlas_event, _event}, socket) do
    {:noreply,
     socket
     |> update(:live_updates, &(&1 + 1))
     |> assign(:feed_status, Feed.status())
     |> assign(:requested_event, selected_id(socket) || kept_closed(socket))
     |> load()}
  end

  @impl true
  def handle_async(:explain, {:ok, {event_id, result}}, socket),
    do: explanation(socket, event_id, result)

  def handle_async(:explain, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:explain_event, nil)
     |> assign(:explain_error, explain_error_message(reason))}
  end

  def handle_async(:explain_models, {:ok, result}, socket),
    do: {:noreply, assign(socket, :explain_models, result)}

  def handle_async(:explain_models, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :explain_models, {:error, :unavailable})}

  # A result is shown only if it is for the record still on screen.
  defp explanation(socket, event_id, result) do
    case socket.assigns.explain_event do
      {^event_id, _} ->
        case result do
          {:ok, text} ->
            {:noreply, assign(socket, :explain_event, {event_id, text})}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:explain_event, nil)
             |> assign(:explain_error, explain_error_message(reason))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # --- loading ---

  defp load(socket) do
    %{
      connected_only?: connected_only?,
      source_filter: filter,
      truth_filter: truth_filter,
      speech_filter: speech_filter,
      entity: entity,
      requested_event: requested
    } = socket.assigns

    sources = if filter == [], do: nil, else: filter

    # `all_events` is the source-filtered stream the timeline scrubs over;
    # `events` is that stream narrowed to the selected range. The timeline
    # needs the full extent to draw against, so both are kept.
    all_events = Feed.events(Feed, sources: sources)

    # Counted across the WHOLE feed, not the filtered one, so an unchecked
    # source still says how much it would add.
    unfiltered = if sources, do: Feed.events(Feed, sources: nil), else: all_events

    # The range's bounds are INDEXES into `all_events`, so it is applied first
    # and the remaining filters narrow its result; filtering before it would
    # change which events the handles point at.
    ranged =
      if socket.assigns.show_all,
        do: all_events,
        else:
          slice_range(
            all_events,
            socket.assigns.range_from,
            socket.assigns.range_to,
            socket.assigns.range_outside?
          )

    about_entity = if entity, do: Enum.filter(ranged, &touches?(&1, entity)), else: ranged

    # `scope` is what the graph reads; `events` is what the list reads. They
    # differ only under an entity focus: the list narrows to the events that
    # touch the entity, while the graph still needs its neighbours' events.
    truth_ok? = fn e -> truth_filter == [] or e.truth_state in truth_filter end
    speech_ok? = fn e -> speech_filter == [] or Event.part_of_speech(e) in speech_filter end

    scope = Enum.filter(ranged, &(truth_ok?.(&1) and speech_ok?.(&1)))

    events = if entity, do: Enum.filter(scope, &touches?(&1, entity)), else: scope

    selected =
      if requested == @no_selection,
        do: nil,
        else: Enum.find(events, &(&1.event_id == requested)) || List.last(events)

    selected_index = if selected, do: Enum.find_index(events, &(&1.event_id == selected.event_id))

    registry = Topology.entities(unfiltered)

    # The graph reads the same window as the list — the range bar is the only
    # window — and drops unconnected entities only when its own toggle says so.
    read_model =
      if(connected_only?, do: "topology", else: "activity")
      |> Projections.materialize(scope)
      |> with_identity(registry)

    # The same model over the WHOLE record: the scene is drawn from this so a
    # filtered point dims in place instead of leaving, and `read:` marks which
    # of them the filters leave.
    unfiltered_model =
      "activity"
      |> Projections.materialize(unfiltered)
      |> with_identity(registry)

    # What "connected only" removed, so the toggle can say so.
    graph_hidden =
      if connected_only?,
        do: map_size(Topology.entities(scope)) - map_size(read_model.entities),
        else: 0

    # "What surrounds this entity?" is answered whenever one is in focus, so a
    # focus is never just a highlight.
    entity_context =
      if entity,
        do: "entity" |> Projections.materialize(scope, entity: entity) |> with_identity(registry)

    affected = if selected, do: Event.affected_refs(selected), else: []
    all_relationships = Topology.relationships(scope)

    socket
    |> assign(:all_events, all_events)
    # Every activity of the record. The scene is built from these, so its
    # payload has to look them up here rather than among the filtered ones.
    |> assign(:scene_events, unfiltered)
    |> assign(:shown_sources, shown_sources(socket.assigns.sources, filter))
    |> assign(:source_counts, Enum.frequencies_by(unfiltered, & &1.source_id))
    |> assign(
      :shown_truths,
      if(truth_filter == [], do: Event.truth_states(), else: truth_filter -- @truth_none)
    )
    # Counted with every OTHER filter applied, so a state's number is what
    # checking it would add to the list as it stands.
    # …which now includes the other facet: each filter's counts are taken with
    # every filter but itself applied.
    |> assign(
      :truth_counts,
      about_entity |> Enum.filter(speech_ok?) |> Enum.frequencies_by(& &1.truth_state)
    )
    |> assign(
      :shown_speech,
      if(speech_filter == [], do: Event.parts_of_speech(), else: speech_filter)
    )
    |> assign(
      :speech_counts,
      about_entity |> Enum.filter(truth_ok?) |> Enum.frequencies_by(&Event.part_of_speech/1)
    )
    # Every word, whatever the verbs / nouns filter says: a filtered-out part is
    # shown struck through rather than emptied.
    |> assign(:speech_words, about_entity |> Enum.filter(truth_ok?) |> speech_words())
    # How much of the whole record is about the entity in focus, whatever the
    # other filters leave of it: what the timeline's entity chip says.
    |> assign(
      :entity_total,
      if(entity, do: Enum.count(unfiltered, &touches?(&1, entity)), else: 0)
    )
    |> assign(:entity_context, entity_context)
    |> assign(:events, events)
    # Pinned, so the event being read always has a mark, even on a day busier
    # than the band has lanes for.
    # Built from the WHOLE record with the filtered set marked, so switching a
    # source off dims its marks instead of resizing the band under the cursor.
    |> assign(
      :timeline,
      Timeline.build(unfiltered, pin: selected && selected.event_id, read: events)
    )
    |> assign(:scatter, Scatter.build(events))
    |> assign(:semantic_status, semantic_status(socket, unfiltered))
    # The timeline spans the WHOLE record and shows every activity on it; the
    # filters decide what is inked and where it focuses, never what is there.
    |> assign(:strip, strip_payload(unfiltered, events, selected))
    |> assign(:strip_lanes, Timeline.build(unfiltered).lanes)
    # The same events and entities the list, map and graph read, as one scene.
    |> assign(
      :scene,
      Scene.build(unfiltered, unfiltered_model.entities, unfiltered_model.relationships,
        moment: selected && selected.event_id,
        # The whole record's first and last event — the same ends the sticky
        # timeline strip is drawn between — so filtering never moves a point.
        time_domain: record_span(unfiltered),
        # Built from the whole record with the filtered set marked: a point the
        # filters exclude goes quiet in place rather than leaving the scene, so
        # toggling a filter does not redraw a different picture.
        read: events,
        axes: if(socket.assigns.scene_layout == "custom", do: socket.assigns.scene_axes),
        semantic: %{
          dims: socket.assigns.semantic_dims,
          scores: Semantics.scores(events, socket.assigns.semantic_axes)
        }
      )
    )
    |> assign(
      :range_dots,
      range_dots(all_events, events, selected)
    )
    |> assign(:geo, Geo.project(read_model.entities))
    |> assign(:selected, selected)
    # The feed the open record came in, from the WHOLE record: a feed is the
    # source's series, and the view's filters do not shorten it.
    |> assign(:stream, stream_context(unfiltered, selected))
    |> assign(:selected_index, selected_index)
    |> assign(:read_model, read_model)
    |> assign(:graph_hidden, graph_hidden)
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
    |> assign(:detach_path, detach_path(socket, selected))
    |> assign(:detach_target, detach_target(socket))
  end

  # Where "Detach" opens the controls: this view, on this view's token (or the
  # spare one, if the tab is not linked yet), as the timeline pane.
  # The detached timeline is ONE tab per view, not a new one per click: the link
  # targets a window named after the view's token, so "Detach" and "Open that tab
  # again" land in the same tab (the browser reuses a named window, and opens it
  # if it was closed). Two different views keep two different timelines.
  defp detach_target(socket) do
    "atlas-timeline-#{socket.assigns.view_token || socket.assigns.spare_token}"
  end

  defp detach_path(socket, selected) do
    socket
    |> share_path(selected)
    |> URI.parse()
    |> then(fn uri ->
      query =
        (uri.query || "")
        |> URI.decode_query()
        |> Map.merge(%{
          "v" => socket.assigns.view_token || socket.assigns.spare_token,
          "pane" => "timeline"
        })

      ~p"/atlas?#{query}"
    end)
  end

  # One step of a "checked means included" checklist over `all`, where an empty
  # filter means no filter. Returns the next filter, or `:unchanged`.
  # `[]` means no filter (every state), so "no state at all" needs its own
  # spelling. It is a one-element list holding a word that is not a truth state:
  # it matches no event, joins into `?truth=none`, and `toggle_inclusion/3` turns
  # it into `[state]` on the next check because it is never in `all`.
  defp parse_truth("none"), do: @truth_none

  defp parse_truth(param) do
    (param || "")
    |> String.split(",", trim: true)
    |> Enum.filter(&(&1 in Event.truth_states()))
  end

  defp toggle_inclusion(all, filter, key) do
    shown = if filter == [], do: all, else: filter
    next = if key in shown, do: List.delete(shown, key), else: shown ++ [key]

    cond do
      key not in all -> :unchanged
      # The last checked box stays on; an empty list would read as "nothing happened".
      next == [] -> :unchanged
      # Everything checked IS "no filter" — keep the URL clean.
      length(next) == length(all) -> []
      # Canonical order, so the same selection is always the same URL.
      true -> Enum.filter(all, &(&1 in next))
    end
  end

  # An event touches an entity if it affects it or asserts a relationship to it.
  defp touches?(event, ref) do
    ref in Event.affected_refs(event) or
      case Event.relationship(event) do
        %{subject: subject, object: object} -> ref in [subject, object]
        nil -> false
      end
  end

  # A filtered view often leaves out the event that REGISTERED an entity, which
  # would strip its label, kind and location and leave a humanized ref with no
  # place on the map. Identity is not something a lens should take away, so it
  # is restored from the whole record; which entities appear, and the events
  # behind them, still come from the filtered view alone.
  defp with_identity(read_model, registry) do
    entities =
      Map.new(read_model.entities, fn {ref, entity} ->
        case registry do
          %{^ref => %{registered: true} = known} when not entity.registered ->
            {ref,
             %{entity | label: known.label, kind: known.kind, geo: known.geo, attrs: known.attrs}}

          _ ->
            {ref, entity}
        end
      end)

    %{read_model | entities: entities}
  end

  defp annotations_about(events, about_id) do
    Enum.filter(events, fn e ->
      Event.annotation?(e) and e.payload["about_event_id"] == about_id
    end)
  end

  # A record the reader closed stays closed across live appends and reloads.
  defp kept_closed(socket) do
    if socket.assigns[:requested_event] == @no_selection, do: @no_selection
  end

  defp selected_id(socket) do
    case socket.assigns[:selected] do
      %Event{event_id: id} -> id
      _ -> nil
    end
  end

  defp record_span([]), do: nil

  defp record_span(events) do
    {from, to} =
      events
      |> Enum.map(&DateTime.to_unix(Event.effective_time(&1), :millisecond))
      |> Enum.min_max()

    %{from: from, to: to}
  end

  defp patch(socket, changes) do
    current = %{
      v: socket.assigns[:view_token],
      pane: socket.assigns[:pane],
      connected: socket.assigns[:connected_only?],
      event: selected_id(socket),
      entity: socket.assigns.entity,
      sources: socket.assigns.source_filter,
      truth: socket.assigns[:truth_filter],
      speech: socket.assigns[:speech_filter],
      from: socket.assigns[:range_from],
      to: socket.assigns[:range_to],
      all: socket.assigns[:show_all],
      out: socket.assigns[:range_outside?],
      lanes: socket.assigns[:lanes?],
      scene: socket.assigns[:scene_layout],
      axes:
        if(socket.assigns[:scene_layout] == "custom",
          do: Enum.join(socket.assigns.scene_axes, ",")
        ),
      band: socket.assigns[:band_dom?] && "dom",
      fit: socket.assigns[:fit_all?],
      tl: socket.assigns[:timeline_open?],
      sc: socket.assigns[:scrubber_open?]
    }

    next = Map.merge(current, Map.new(changes))

    # A closed record stays closed while the view around it changes; only
    # choosing an event reopens one.
    next = %{next | event: next.event || kept_closed(socket)}

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
  #
  # `outside?` reads the same window from the other side. With no window there
  # is no outside, so it is ignored rather than emptying the page.
  defp slice_range(events, nil, nil, _outside?), do: events

  defp slice_range(events, from, to, outside?) do
    last = length(events) - 1
    first = from || 0
    final = to || last

    cond do
      events == [] -> []
      first > final and outside? -> events
      first > final -> []
      outside? -> Enum.slice(events, 0, first) ++ Enum.drop(events, final + 1)
      true -> Enum.slice(events, first..final)
    end
  end

  defp share_path(socket, selected) do
    path_for(%{
      connected: socket.assigns[:connected_only?],
      event: (selected && selected.event_id) || kept_closed(socket),
      entity: socket.assigns.entity,
      sources: socket.assigns.source_filter,
      truth: socket.assigns.truth_filter,
      speech: socket.assigns.speech_filter,
      from: socket.assigns.range_from,
      to: socket.assigns.range_to,
      all: socket.assigns.show_all,
      out: socket.assigns.range_outside?,
      lanes: socket.assigns.lanes?,
      scene: socket.assigns.scene_layout,
      axes:
        if(socket.assigns.scene_layout == "custom",
          do: Enum.join(socket.assigns.scene_axes, ",")
        ),
      band: socket.assigns.band_dom? && "dom",
      fit: socket.assigns.fit_all?,
      tl: socket.assigns.timeline_open?,
      sc: socket.assigns.scrubber_open?
    })
  end

  defp path_for(%{event: event, entity: entity, sources: sources} = opts) do
    query =
      []
      |> maybe_put(:event, event)
      |> maybe_put(:entity, entity)
      |> maybe_put(:sources, if(sources in [nil, []], do: nil, else: Enum.join(sources, ",")))
      |> maybe_put(
        :truth,
        if(opts[:truth] in [nil, []], do: nil, else: Enum.join(opts[:truth], ","))
      )
      |> maybe_put(
        :speech,
        if(opts[:speech] in [nil, []], do: nil, else: Enum.join(opts[:speech], ","))
      )
      |> maybe_put(:from, opts[:from])
      |> maybe_put(:to, opts[:to])
      |> maybe_put(:all, if(opts[:all], do: "1", else: nil))
      |> maybe_put(:out, if(opts[:out], do: "1", else: nil))
      |> maybe_put(:lanes, if(opts[:lanes], do: "1", else: nil))
      |> maybe_put(:connected, if(opts[:connected], do: "1", else: nil))
      |> maybe_put(:band, if(opts[:band] == "dom", do: "dom", else: nil))
      |> maybe_put(:fit, if(opts[:fit], do: "all", else: nil))
      |> maybe_put(
        :scene,
        if(opts[:scene] in [nil, Scene.default_layout()], do: nil, else: opts[:scene])
      )
      |> maybe_put(:axes, if(opts[:scene] == "custom", do: opts[:axes]))
      # Only the non-default (collapsed) state needs to appear in the URL.
      |> maybe_put(:tl, if(Map.get(opts, :tl, true) == false, do: "0", else: nil))
      |> maybe_put(:sc, if(Map.get(opts, :sc, true) == false, do: "0", else: nil))
      # Linked tabs. Absent from `share_path/2` on purpose: a shared link is a
      # copy of the view, not a seat at it.
      |> maybe_put(:v, opts[:v])
      |> maybe_put(:pane, opts[:pane])

    ~p"/atlas?#{query}"
  end

  defp maybe_put(query, _key, nil), do: query
  defp maybe_put(query, key, value), do: query ++ [{key, value}]

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # The author carries over between posts; the rest starts clean.
  @doc "The signed-in reader's handle, or nil. The author of whatever they write."
  def signed_in_handle(%{assigns: assigns}), do: signed_in_handle(assigns)

  def signed_in_handle(%{current_scope: %{user: %{github_login: login}}}) when is_binary(login),
    do: login

  def signed_in_handle(_), do: nil

  @doc "What a note is read as, for the chips under it (`Indivisual.Atlas.Extract`)."
  def note_mentions(body, read_model), do: Extract.mentions(body || "", read_model.entities)

  @doc "What each kind of annotation SAYS — the speech act, from `EVENT_UI.md`."
  def kind_says("observation"), do: "I saw this"
  def kind_says("question"), do: "I don't understand this"
  def kind_says("correction"), do: "This is wrong"
  def kind_says("source"), do: "Here is the evidence"
  def kind_says(_), do: ""

  @doc "What a good note of each kind contains — the prompt over the textarea."
  def kind_prompt("observation"), do: "What you saw, first-hand: where, when, and what exactly."
  def kind_prompt("question"), do: "What is unclear, and what answer would settle it."
  def kind_prompt("correction"), do: "What is wrong, what is right, and how you know."
  def kind_prompt("source"), do: "A link or a citation, and which claim it supports."
  def kind_prompt(_), do: "What happened, or what should people know?"

  defp blank_post_form(author \\ "") do
    to_form(%{"type" => "note", "kind" => "question", "body" => "", "author" => author || ""},
      as: :post
    )
  end

  defp post_flash(event) do
    if Event.annotation?(event),
      do: "Annotation recorded as its own event; source events are unchanged.",
      else:
        "Post recorded as its own event, as reported by you. Nothing else in the record changed."
  end

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

  @doc "Truth states present in `events`, in order of settledness, with counts."
  def truth_breakdown(events) do
    counts = Enum.frequencies_by(events, & &1.truth_state)
    for state <- Event.truth_states(), n = counts[state], do: {state, n}
  end

  @doc """
  Source ids currently feeding the view. An empty filter means no filter, so it
  resolves to every source rather than none.
  """
  def shown_sources(sources, []), do: Map.keys(sources)
  def shown_sources(_sources, filter), do: filter

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

  defp explain_error_message(:unavailable),
    do: "No explanation backend is reachable right now."

  defp explain_error_message({:model_not_found, model}),
    do: "The model #{model} is not available."

  defp explain_error_message(_), do: "Could not generate an explanation."

  @doc """
  The absolute URL for a share path, when the endpoint knows its host.

  A shared link has to work outside this browser tab, so it carries the scheme
  and host rather than the bare path the in-page router uses.
  """
  def share_url(path) do
    IndivisualWeb.Endpoint.url() <> path
  end

  @doc """
  The filters currently narrowing the activity list, as data, in the order they
  apply: `[%{id, label, value}]`. Empty when nothing is narrowed.

  Only what changes which events are LISTED. The graph's "connected only" toggle
  and folded days change how things are drawn, not what is read, so they are not
  here. `active_filters/1` below says the same thing as sentences.
  """
  def applied_filters(assigns) do
    [
      (assigns.range_from || assigns.range_to) &&
        %{
          id: "range",
          label: if(assigns.range_outside?, do: "Outside", else: "Range"),
          value: range_label(assigns.all_events, assigns.range_from, assigns.range_to),
          clear: "clear_range",
          clear_label: "Show the whole span again"
        },
      assigns.source_filter != [] &&
        %{
          id: "sources",
          label: "Sources",
          value: "#{length(assigns.source_filter)} of #{map_size(assigns.sources)}",
          title: Enum.map_join(assigns.source_filter, ", ", &source_title(assigns.sources, &1)),
          clear: "clear_sources",
          clear_label: "Show every source again"
        },
      case assigns.truth_filter do
        [] ->
          nil

        @truth_none ->
          %{
            id: "truth",
            label: "Truth",
            value: "none",
            clear: "clear_truth",
            clear_label: "Show every truth state again"
          }

        states ->
          %{
            id: "truth",
            label: "Truth",
            value: Enum.join(states, " + "),
            clear: "clear_truth",
            clear_label: "Show every truth state again"
          }
      end,
      assigns.speech_filter != [] &&
        %{
          id: "speech",
          label: "Speech",
          value: Enum.join(assigns.speech_filter, " + "),
          clear: "clear_speech",
          clear_label: "Show every kind of speech again"
        },
      assigns.entity &&
        %{
          id: "entity",
          label: "Entity",
          kind: entity_kind(assigns.read_model, assigns.entity),
          value: entity_label(assigns.read_model, assigns.entity),
          title: assigns.entity,
          clear: "clear_entity",
          clear_label: "Stop focusing on this entity"
        }
    ]
    |> Enum.filter(&is_map/1)
  end

  @doc """
  The filters currently narrowing the list, in words, in the order they apply.
  An empty list of events shows these, so "nothing listed" always comes with
  the reason and never reads as "nothing happened".
  """
  def active_filters(assigns) do
    [
      assigns.source_filter != [] &&
        "#{length(assigns.source_filter)} of #{map_size(assigns.sources)} sources",
      (assigns.range_from || assigns.range_to) &&
        "#{if assigns.range_outside?, do: "outside ", else: ""}#{range_label(assigns.all_events, assigns.range_from, assigns.range_to)}",
      case assigns.truth_filter do
        [] -> nil
        @truth_none -> "no truth state is on"
        states -> "truth state: #{Enum.join(states, ", ")}"
      end,
      assigns.speech_filter != [] && "#{Enum.join(assigns.speech_filter, ", ")}s only",
      assigns.entity && "entity: #{entity_label(assigns.read_model, assigns.entity)}"
    ]
    |> Enum.filter(&is_binary/1)
  end

  @doc "schema.org type for an entity in the read model, or nil."
  def entity_schema_type(read_model, ref) do
    case read_model.entities[ref] do
      %{kind: kind} -> Glossary.schema_type(kind)
      _ -> nil
    end
  end

  @doc "An entity's kind (`person`, `place`, …) from the read model, else the ref's prefix."
  def entity_kind(read_model, ref) do
    case read_model.entities[ref] do
      %{kind: kind} -> kind
      _ -> Topology.kind_of(ref)
    end
  end

  @doc "Full reference plus type, for an entity chip's title."
  def entity_title(read_model, ref) do
    case entity_schema_type(read_model, ref) do
      nil -> ref
      type -> "#{ref} · schema.org/#{type}"
    end
  end

  @doc """
  Whether a provenance key holds an opaque digest, to be shown abbreviated.

  By suffix rather than by list: an annotation carries `about_content_hash`, and a
  chain source will bring its own, and each would otherwise render as 64
  unbreakable characters.
  """
  def digest_key?(key) when is_binary(key),
    do: key in ["txid", "hash"] or String.ends_with?(key, "_hash")

  def digest_key?(_), do: false

  @doc """
  Shortens a long opaque identifier for display: first and last characters
  with an ellipsis between.

  A 64-character hash rendered in full dominates a card and is read by nobody;
  the head and tail are what a person actually compares, and the full value
  stays available as a title attribute and to copy.
  """
  def abbrev(value, keep \\ 8)

  def abbrev(value, keep) when is_binary(value) do
    if String.length(value) > keep * 2 + 3 do
      String.slice(value, 0, keep) <> "…" <> String.slice(value, -keep, keep)
    else
      value
    end
  end

  def abbrev(value, _keep), do: to_string(value)

  @doc """
  Splits a namespaced identifier into its segments for display.

  `civic:eltsp:entity:goal-quality-of-life` is already a typed reference — a
  scheme, a stream, a kind and a name. Showing the parts makes that structure
  visible instead of leaving it as one opaque string.
  """
  def id_segments(id) when is_binary(id), do: String.split(id, ":")
  def id_segments(_), do: []

  @doc "Whether a provenance value should render as a link."
  def link?(value) when is_binary(value), do: String.starts_with?(value, ["http://", "https://"])
  def link?(_), do: false

  @doc """
  Orders provenance keys so the resolvable ones lead.

  A URI is where to look and a hash is what must be there; the rest is
  qualifying detail.
  """
  def provenance_order(provenance) do
    priority = %{"uri" => 0, "content_hash" => 1, "txid" => 2}

    provenance
    |> Enum.sort_by(fn {k, _} -> {Map.get(priority, k, 9), k} end)
  end

  @doc """
  Map points as plain data for the Leaflet hook.

  Only what the map needs crosses the boundary — a full entity would carry its
  event ids and provenance into a data attribute for no purpose.
  """
  def map_points(geo, focused_ref, affected) do
    Enum.map(geo.points, fn p ->
      %{
        ref: p.ref,
        label: p.entity.label,
        lat: p.lat,
        lng: p.lng,
        # The marker is drawn as its kind: a pin for a place, a person for a
        # person, a dot otherwise. The path rides along so the hook needs no
        # copy of the icon set.
        kind: p.entity.kind,
        icon: AtlasComponents.entity_icon_path(p.entity.kind),
        focused: p.ref == focused_ref,
        affected: p.ref in affected
      }
    end)
  end

  @doc """
  Scatter points as plain data for the three.js hook: the read model's position
  joined to what a reader needs to recognise the event — its title, date, and
  truth state (as the same colour the graph strokes it with) — plus where the
  selection and the scrubber stand.
  """
  def scatter_points(scatter, events, selected, selected_index) do
    selected_id = selected && selected.event_id

    scatter.points
    |> Enum.zip(events)
    |> Enum.with_index()
    |> Enum.map(fn {{point, event}, i} ->
      Map.merge(point, %{
        title: Event.title(event),
        date: date(Event.effective_time(event)),
        truth: event.truth_state,
        color: truth_stroke(event.truth_state),
        selected: point.id == selected_id,
        future: is_integer(selected_index) and i > selected_index
      })
    end)
  end

  @doc """
  The Spacetime scene as the hook wants it: `Scene`'s nodes, joined to what a
  reader needs to recognise each one (colour, date, truth state) and to where the
  selection and the entity focus stand. Links take the truth colour of the claim
  that asserts them.
  """
  def scene_payload(scene, events, selected, entity, axes \\ nil) do
    by_id = Map.new(events, &{&1.event_id, &1})
    selected_id = selected && selected.event_id
    affected = if selected, do: Event.affected_refs(selected), else: []

    nodes =
      Enum.map(scene.nodes, fn
        %{kind: "event", id: id} = node ->
          event = Map.fetch!(by_id, id)

          node
          |> Map.drop([:time])
          |> Map.merge(%{
            color: truth_stroke(event.truth_state),
            date: date(Event.effective_time(event)),
            selected: id == selected_id
          })

        # The same two states the lists show: in focus, and affected by the
        # record that is open.
        %{kind: "entity", id: ref} = node ->
          Map.merge(node, %{focused: ref == entity, affected: ref in affected})
      end)

    %{
      nodes: nodes,
      links: scene.links,
      frames: scene.frames,
      map: scene.map,
      # The map is a GROUND, and a ground goes with the axes, not with a mode's
      # name: wherever x is longitude and y is latitude there is a map to stand
      # on, whatever z is showing — the Map preset is only the best-known case.
      ground: match?(["lng", "lat", _], axes) and not is_nil(scene.map),
      # The page's one icon set, for the kinds in this scene that have an icon.
      icons:
        scene.nodes
        |> Enum.flat_map(fn node -> List.wrap(node[:entity_kind]) end)
        |> Enum.uniq()
        |> Map.new(&{&1, AtlasComponents.entity_icon_path(&1)})
        |> Map.reject(fn {_kind, icon} -> is_nil(icon) end),
      span: scene.span
    }
  end

  @doc """
  The sticky timeline's data: every activity of the whole record (`all`), which
  of them the filters leave (`read`), and the two spans the view can show.

  `extent` is the first and last activity of the record — the rectangle's
  fixed ends. `focus` is the span of what is read, and is nil when nothing is
  filtered out (there is then nothing to focus ON). Times are Unix milliseconds,
  so the client can draw calendar markers without a second source of dates.
  """
  def strip_payload(all, read, selected) do
    read_ids = MapSet.new(read, & &1.event_id)
    selected_id = selected && selected.event_id
    ms = &DateTime.to_unix(Event.effective_time(&1), :millisecond)

    span = fn
      [] ->
        nil

      events ->
        events |> Enum.map(ms) |> Enum.min_max() |> then(fn {a, b} -> %{from: a, to: b} end)
    end

    focus = if(length(read) < length(all), do: span.(read))

    %{
      extent: span.(all),
      focus: focus,
      # What the record holds on either side of the span in view: the view is a
      # slice, and this is how much of the record lies outside it.
      #
      # Counted by MEMBERSHIP, not by timestamp. Twelve activities of this
      # record share one instant, so `time < focus.from` finds none of them
      # when the filtered-out ones sit at exactly that instant — the earlier
      # cap then read "the record starts here" while activities were in fact
      # held back. An activity is outside the view because it was filtered out,
      # which the read set states exactly and time cannot.
      beyond:
        if focus do
          # Each held-back activity belongs to exactly one side. Anything at or
          # before the start of the view counts as earlier; everything else
          # outside the view is later. Partitioning rather than testing each
          # side separately is what keeps an activity at a shared instant from
          # being counted twice when the view is one moment wide.
          {earlier, later} =
            all
            |> Enum.reject(&MapSet.member?(read_ids, &1.event_id))
            |> Enum.split_with(&(ms.(&1) <= focus.from))

          %{earlier: length(earlier), later: length(later)}
        else
          %{earlier: 0, later: 0}
        end,
      nodes:
        Enum.map(all, fn event ->
          %{
            id: event.event_id,
            label: Event.title(event),
            at: ms.(event),
            date: date(Event.effective_time(event)),
            truth: event.truth_state,
            color: truth_stroke(event.truth_state),
            read: MapSet.member?(read_ids, event.event_id),
            selected: event.event_id == selected_id
          }
        end)
    }
  end

  @doc """
  The two ways the sticky timeline can frame the record.

  Named for what the band spans, not for what the camera does: "Date range"
  and "All" say which span is on screen, where "In focus" and "Whole record"
  described a zoom and left the reader to work out the rest.
  """
  def strip_fits do
    [
      %{id: "focus", name: "Date range", says: "Span only the dates the filters leave."},
      %{id: "all", name: "All", says: "Span the whole record, first activity to last."}
    ]
  end

  @doc """
  What the active layout could not place, in words — or nil when it placed
  everything. The scene shelves these rather than inventing a position.
  """
  def scene_shortfall(scene, layout) do
    case Map.get(scene.shortfall, layout, %{entities: 0, events: 0}) do
      %{entities: 0, events: 0} ->
        nil

      %{entities: entities, events: events} ->
        total_entities = Enum.count(scene.nodes, &(&1.kind == "entity"))
        total_events = Enum.count(scene.nodes, &(&1.kind == "event"))

        "#{entities} of #{total_entities} entities and #{events} of #{total_events} events have no place in this layout. They wait on the shelf beside it, dimmed."
    end
  end

  @doc """
  Where the scene's axes currently run, for the Spacetime frame.

  A layout says what an axis MEANS ("earlier → later"); this says where it runs
  FROM and TO right now. Without it the z rails read the same however far the
  date range is narrowed, so the frame stops answering to the sliders.
  """
  def scene_axis_bounds(events, layout_id \\ nil, axes \\ nil)

  def scene_axis_bounds([], _layout_id, _axes), do: %{}

  def scene_axis_bounds(events, layout_id, axes) do
    axes = axes || Scene.layout(layout_id || Scene.default_layout()).dims
    times = Enum.map(events, &Event.effective_time/1)
    low = date(Enum.min(times, DateTime))
    high = date(Enum.max(times, DateTime))

    # Dates belong on whichever axis carries time — z by convention, but a reader
    # can put it anywhere, or nowhere. An axis that is not time gets no dates:
    # stamping them on "Cost ↔ Benefit" would make the bar lie.
    case Enum.find_index(axes, &(&1 == "time")) do
      nil ->
        %{}

      index ->
        # A range narrowed to one day has one date, not two. Repeating it reads
        # as a rendering fault; saying it once says what is true.
        bounds = if low == high, do: %{low: low, high: "same day"}, else: %{low: low, high: high}
        %{Enum.at([:x, :y, :z], index) => bounds}
    end
  end

  @doc "Quarterly tick marks for the timeline band."
  def timeline_ticks(timeline), do: Timeline.ticks(timeline)

  @doc "The glossary entry for a slug, or nil."
  def glossary_term(slug), do: Glossary.get(slug)

  @doc "One-line meaning of a truth state, for the legend."
  def truth_description(state), do: Map.get(@truth_descriptions, state, "")

  @doc """
  The question a panel answers, from the projection it is built on. The words are
  `Atlas.Projections`' own, so the page and the read model cannot drift apart.
  """
  def panel_question(projection_id) do
    case Projections.get(projection_id) do
      %{question: question} -> question
      nil -> nil
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

  @doc """
  The range bar's dots — combined (`:all`) and fanned out per source (`:lanes`)
  — each marked with whether the list reads it and whether it holds the selected
  event. `events` is the bar's whole stream; `read` is what survived every
  filter (range, truth state, entity), so a dot is inked exactly when its event
  is in the list. A packed dot counts as read if ANY of its events is: it
  should not look empty while contributing rows.
  """
  def range_dots(events, read, selected) do
    read_ids = MapSet.new(read, & &1.event_id)
    ids = events |> Enum.map(& &1.event_id) |> List.to_tuple()
    selected_id = selected && selected.event_id

    mark = fn dot ->
      dot
      |> Map.put(:read?, Enum.any?(dot.indexes, &MapSet.member?(read_ids, elem(ids, &1))))
      |> Map.put(:selected?, Enum.any?(dot.indexes, &(elem(ids, &1) == selected_id)))
    end

    %{
      all: events |> Timeline.ordinal_dots() |> Enum.map(mark),
      lanes:
        events
        |> Timeline.ordinal_lanes(& &1.source_id)
        |> Map.new(fn {source_id, dots} -> {source_id, Enum.map(dots, mark)} end)
    }
  end

  # Roughly how much of the bar one date label covers. A label is ~62px; the
  # bar runs from ~340px (phone) to ~900px, so this errs toward the narrow end
  # — a label that flips early costs nothing, one that overflows is clipped.
  @range_label_width 0.14

  @doc """
  Date labels that ride above the range bar's handles: `%{x:, text:, side:,
  open?:}`.

  `side` is which way the text runs from the handle, chosen so a label never
  leaves the bar and the two never print over each other: the start label runs
  leftward and the end label rightward, each flipping inward near its own end
  of the bar. When the handles are too close for two labels, they merge into
  one — `a → b`, or a single date when both handles read the same day — centred
  between them and held inside the bar.

  An open bound is labelled with the date it currently reaches, flagged
  `open?` so it can read as "so far" rather than as a pinned value.
  """
  def range_labels([], _from, _to), do: []

  def range_labels(events, from, to) do
    w = @range_label_width
    f = range_fraction(events, from, :start)
    t = range_fraction(events, to, :end)
    last = length(events) - 1

    start = %{x: f, text: index_label(events, from || 0), open?: is_nil(from)}
    finish = %{x: t, text: index_label(events, to || last), open?: is_nil(to)}

    start_side = if f >= w, do: :left, else: :right
    end_side = if t <= 1 - w, do: :right, else: :left

    # How far apart the handles must be for both labels to fit, given which
    # way each one runs: back to back needs nothing, the same way needs one
    # label's width, facing each other needs two.
    needed =
      case {start_side, end_side} do
        {:left, :right} -> 0.0
        {:right, :left} -> 2 * w
        _same_way -> w
      end

    if t - f < needed do
      text = if start.text == finish.text, do: start.text, else: "#{start.text} → #{finish.text}"
      half = if start.text == finish.text, do: w / 2, else: w * 1.25

      [
        %{
          x: Float.round(((f + t) / 2) |> max(half) |> min(1 - half), 4),
          text: text,
          side: :center,
          open?: start.open? and finish.open?
        }
      ]
    else
      [Map.put(start, :side, start_side), Map.put(finish, :side, end_side)]
    end
  end

  @doc """
  Where a range handle sits along the bar, as a 0–1 fraction. An open bound
  rests on its end of the bar, which is what makes "open" visible.
  """
  def range_fraction(events, index, open_at) do
    last = length(events) - 1

    cond do
      last <= 0 -> if(open_at == :start, do: 0.0, else: 1.0)
      is_nil(index) and open_at == :start -> 0.0
      is_nil(index) -> 1.0
      true -> Float.round(min(index, last) / last, 4)
    end
  end

  @doc """
  Whether an annotation can be written about `event`: there has to be one, and it
  has to be a source record — a post about a post is a thread, which the record
  does not model yet.
  """
  def annotatable?(%Event{} = event), do: not Post.post?(event)
  def annotatable?(_), do: false

  @doc """
  The whole page for this view, still on its token: a share path (which never
  carries the token) with the token put back, for a tab that is leaving its pane
  but not the view.
  """
  def share_path_with(share_path, nil), do: share_path

  def share_path_with(share_path, token) do
    uri = URI.parse(share_path)
    query = (uri.query || "") |> URI.decode_query() |> Map.put("v", token)
    ~p"/atlas?#{query}"
  end

  @doc """
  The feed (`stream_id`) a record came in, made legible: its name in words, the
  record's place in it counted in the source's own order (`sequence`), and its
  neighbours there — so a feed is something to walk, not an opaque id.
  """
  def stream_context(_events, nil),
    do: %{name: nil, position: 0, total: 0, earlier: nil, later: nil}

  def stream_context(events, %Event{} = selected) do
    feed =
      events
      |> Enum.filter(&(&1.stream_id == selected.stream_id))
      |> Enum.sort_by(&{&1.sequence, Event.sort_key(&1)})

    index = Enum.find_index(feed, &(&1.event_id == selected.event_id)) || 0
    at = fn i -> if i >= 0, do: feed |> Enum.at(i) |> then(&(&1 && &1.event_id)) end

    %{
      name: stream_name(selected.stream_id, events),
      position: index + 1,
      total: max(length(feed), 1),
      earlier: at.(index - 1),
      later: at.(index + 1)
    }
  end

  # The conventions the adapters use today. Anything else is a source's own
  # name for its series, and is shown as the source wrote it.
  defp stream_name("posts:" <> author, _events), do: "#{author}'s posts"

  defp stream_name("annotations:" <> event_id, events) do
    case Enum.find(events, &(&1.event_id == event_id)) do
      nil -> "Annotations on a record"
      about -> "Annotations on “#{Event.title(about)}”"
    end
  end

  defp stream_name(stream_id, _events), do: stream_id

  @doc """
  The schema.org type of what a record IS, when it registers an entity (a noun):
  the entity's own type. A verb has none — its type is its event type.
  """
  def record_schema_type(read_model, %Event{payload: %{"entity" => %{"ref" => ref}}}),
    do: entity_schema_type(read_model, ref)

  def record_schema_type(_read_model, _event), do: nil

  @doc "How a part of speech is shown: the same marks the Spacetime scene uses."
  def speech_mark("noun"),
    do: %{
      glyph: "◆",
      name: "Entities",
      one: "Entity",
      aka: "nouns",
      says: "Entities: something was named"
    }

  def speech_mark(_verb),
    do: %{
      glyph: "●",
      name: "Events",
      one: "Event",
      aka: "verbs",
      says: "Events: something happened"
    }

  @doc """
  The words behind each part of speech, from `events`: a verb is a kind of
  happening (`civic.plan.initiated` → "plan initiated") with how many times it
  occurs; a noun is a named entity, with the ref that focuses it. In the order
  the record first says them.
  """
  def speech_words(events) do
    events
    |> Enum.group_by(&Event.part_of_speech/1)
    |> Map.new(fn
      {"noun", nouns} ->
        {"noun",
         nouns
         |> Enum.map(fn e ->
           entity = e.payload["entity"]

           %{
             word: entity["label"] || Atlas.Topology.humanize(entity["ref"]),
             ref: entity["ref"],
             n: 1
           }
         end)
         |> Enum.uniq_by(& &1.ref)}

      {part, verbs} ->
        counts = Enum.frequencies_by(verbs, &verb_of/1)

        {part,
         verbs
         |> Enum.map(&verb_of/1)
         |> Enum.uniq()
         |> Enum.map(&%{word: &1, ref: nil, n: counts[&1]})}
    end)
  end

  # "civic.eir.notice_of_preparation" → "eir notice of preparation": the type
  # without its namespace, which is the source's, not the reader's.
  defp verb_of(%Event{event_type: type}) do
    case type |> to_string() |> String.split(".") do
      [_namespace | [_ | _] = rest] -> rest
      parts -> parts
    end
    |> Enum.join(" ")
    |> String.replace("_", " ")
  end

  @doc "The reader's saved mode that IS the axes on show, or nil."
  def current_mode(modes, "custom", axes), do: Enum.find(modes, &(&1.axes == axes))
  def current_mode(_modes, _layout, _axes), do: nil

  @doc """
  The activity list, grouped by day: `[{"2024-04-09", [{event, index}, …]}, …]`.

  Runs of consecutive events on one day, in list order — so grouping never
  reorders the list, and `index` is the event's place in the WHOLE list (row ids,
  and what counts as after the selection, still hang off it).
  """
  def activity_days(events) do
    events
    |> Enum.with_index()
    |> Enum.chunk_by(fn {event, _i} -> date(Event.effective_time(event)) end)
    |> Enum.map(fn [{event, _i} | _] = rows -> {date(Event.effective_time(event)), rows} end)
  end

  @doc "True when every day in the list is folded to its heading."
  def all_days_collapsed?(events, collapsed) do
    events |> activity_days() |> Enum.all?(fn {day, _rows} -> MapSet.member?(collapsed, day) end)
  end

  @doc """
  The time of day for a row under a day heading — or nothing when the source
  gave only a date (midnight exactly), since "00:00" on every row would be noise
  pretending to be precision.
  """
  def time_of_day(%DateTime{hour: 0, minute: 0, second: 0}), do: ""
  def time_of_day(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  def time_of_day(_), do: ""

  @doc "Time of day, `HH:MM` UTC, or `—`."
  def clock(nil), do: "—"
  def clock(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M") <> " UTC"

  @doc """
  The gap between when an event happened and when it was recorded, in words.

  Returns `%{kind:, glyph:, text:, title:}`. The kinds are distinct findings,
  not formatting:

    * `:after`  — recorded later than it happened. The usual case; the size of
      the gap says how far behind the record runs.
    * `:same`   — recorded as it happened. Where reporting should converge.
    * `:before` — recorded BEFORE it happened: a scheduled or announced event.
    * `:unstated` — the source gives no time of its own, only ours. That is a
      statement about the source, so it is reported rather than filled in.
  """
  def lag(%Event{occurred_at: nil}) do
    %{
      kind: :unstated,
      glyph: "∅",
      text: "only observed",
      title: "The source does not say when this happened. We know only when it was recorded."
    }
  end

  def lag(%Event{occurred_at: occurred, observed_at: observed}) do
    seconds = DateTime.diff(observed, occurred, :second)

    cond do
      seconds == 0 ->
        %{kind: :same, glyph: "=", text: "same moment", title: "Recorded as it happened."}

      seconds > 0 ->
        %{
          kind: :after,
          glyph: "→",
          text: "#{duration(seconds)} later",
          title: "Recorded #{duration(seconds)} after it happened."
        }

      true ->
        %{
          kind: :before,
          glyph: "←",
          text: "#{duration(-seconds)} ahead",
          title:
            "Recorded #{duration(-seconds)} before it happened: scheduled or announced in advance."
        }
    end
  end

  @doc "A span of seconds at the one unit that reads naturally: `3 d`, `5 mo`, `2.4 y`."
  def duration(seconds) when seconds >= 0 do
    cond do
      seconds < 60 -> "#{seconds} s"
      seconds < 3_600 -> "#{div(seconds, 60)} min"
      seconds < 86_400 -> "#{div(seconds, 3_600)} h"
      seconds < 86_400 * 60 -> "#{div(seconds, 86_400)} d"
      seconds < 86_400 * 730 -> "#{round(seconds / (86_400 * 30.44))} mo"
      true -> "#{Float.round(seconds / (86_400 * 365.25), 1)} y"
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
