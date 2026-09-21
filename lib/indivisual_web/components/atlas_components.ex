defmodule IndivisualWeb.AtlasComponents do
  @moduledoc """
  Shared Atlas UI components. Templates live in `atlas_components/`.

  Not imported app-wide — call as `<IndivisualWeb.AtlasComponents.source_nav ... />`
  or import where needed.

  ## What is mounted, and what is not

  Some components here are deliberately NOT on any page. They were built, worked,
  and were replaced by something tidier — and are kept rather than deleted so the
  decision stays reversible. This table is the register: update it in the same
  change that mounts or unmounts anything, so "unused" is always a stated choice
  and never an accident. `unmounted/0` is the same list for tests to hold us to.

  | Component | Status | Where / why |
  |---|---|---|
  | `filter_chip/1` | mounted | `/atlas`: the entity focus on the timeline (with ✕), and every item of `applied_filters/1` (read-only) |
  | `applied_filters/1` | mounted | `/atlas` column 1, above the Activity heading |
  | `entity_icon/1` | mounted | `/atlas`, wherever an entity is named: record chips, entity list, filter chips, entity heading, graph nodes, map markers |
  | `relationship_row/1` | mounted | `/atlas` record panel, the Relationships list |
  | `person_card/1` | mounted | `/atlas` reader column, in place of the plain heading, when the focused entity is a person |
  | `accordion/1` | mounted | `/atlas` Timeline panel |
  | `pane_banner/1` | mounted ×2 | `/atlas` linked tabs: the view pane (`dark`, fixed above the site nav) and the detached timeline pane (`indigo`, in flow — that pane has no nav). Two tones so the two tabs of a pair can be told apart at a glance. |
  | `spacetime/1` | mounted ×2 | `/atlas` sticky timeline (strip, locked to `timeline`) and the **Projection** panel in the canvas column (its on-page title; the component keeps the name it was built under — "Spacetime" is now only the tab for the lng · lat · time preset) |
  | `axes/1` | unmounted with `graph/1` | The read-only axes legend. Spacetime no longer uses it: its axes are the x / y / z dropdown bar under the stage (part of `spacetime/1`), which says the same and can be changed. Still used inside the unmounted `graph/1`. |
  | `range_dots/1` | mounted | `/atlas` range bar and its per-source lanes |
  | `feed_status/1` | **unmounted** 2026-09-20 | Was the data · feed · persistence · events line in the `/atlas` header. About the plumbing, not the record. Kept: the seed of a sources / settings page. |
  | `source_checklist/1` | **unmounted** 2026-09-20 | Was the Sources block at the top of column 1. Replaced by the checkboxes on the timeline's "By source" rows. Kept: the source filter for any page without a timeline. |
  | `source_nav/1` | **unmounted** 2026-09-20 | Replaced by the source checklist on the activity list. Kept: the only control that *describes* a source (publisher, status, adapter). |
  | `projection_nav/1` | **unmounted** 2026-09-20 | The four projections are all on screen at once — activity is the list, topology the graph, entity context the reader under a focus, provenance the truth filter — so a switch between them asked a question with no answer. Each panel now carries its projection's question. Kept: the only place the four are named side by side. |
  | `position_scrubber/1` | **unmounted** 2026-09-20 | Selecting an event is already done by the activity list, marks band and Prev / Next. Kept: the only drag-through-events control. |
  | `space/1` | **unmounted** 2026-09-20 | Was the "Space" 3D scatter under Spacetime in the canvas column. Its positions were placeholders (a hash of the event id), and Spacetime now draws the same events in layouts that mean something. Kept: the three-opposing-pole-axes volume, for when events carry real coordinates on such axes. |
  | `map/1` | **unmounted** 2026-09-20 | Was the Leaflet map in the canvas column. Spacetime's `map` layout places the same entities on the same ground. Kept: the only real slippy map, with pins that focus an entity and a count of what has no location. |
  | `annotation_form/1` | **unmounted** 2026-09-20 | Was the "Annotate" form under the open record in column 2. It duplicated "New activity", which makes the same annotation from one composer; the record now has an "Annotate this record" button that opens that composer. Kept: an annotate form that can sit beside a record on a page with no activity composer. |
  | `graph/1` | **unmounted** 2026-09-20 | Was the SVG topology graph and its "connected only" filter, at the foot of the canvas column (the entity list that sat under it stayed on the page, under Spacetime: it is what a keyboard gets in place of the WebGL scene). Spacetime's `graph` layout covers it. Kept: the only view that draws every relationship as a labelled edge, and the only plain-DOM (no WebGL) picture of the record. |

  An unmounted component's host events stay handled in `IndivisualWeb.AtlasLive`
  (`validate_annotation`, `annotate`, `toggle_source`, `clear_sources`, `scrub`, `toggle_scrubber`, `select_projection`,
  `toggle_connected`; `select_event` and `focus_entity` are in use regardless), and its CSS
  stays in `app.css`, so remounting is one tag.

  Related, outside this module: `Indivisual.Atlas.Coherence` is computed and
  tested but has no UI at all — see its moduledoc.
  """
  use Phoenix.Component

  import IndivisualWeb.CoreComponents, only: [input: 1]

  embed_templates "atlas_components/*"

  @doc "Components that exist but are on no page. Mirrors the moduledoc register."
  def unmounted,
    do: [
      :source_nav,
      :position_scrubber,
      :projection_nav,
      :source_checklist,
      :feed_status,
      :space,
      :map,
      :graph,
      :annotation_form
    ]

  @doc """
  A one-line banner across the top of a pane: a bold title, a dot, a message, and
  one action at the right. Shaped after Tailwind UI's banners — a `before:flex-1`
  spacer balances the right-hand action so the message sits centred.

  Two tones, one per tab of a linked pair: `dark` (gray-900, with a hairline) for
  the view pane, `indigo` for the detached timeline. `fixed` pins it above
  everything at a known height (`h-11`), for a page whose nav is outside the
  LiveView; `app.css` makes room with `body:has(#atlas-pane-banner)`.

  The `:action` slot is what ENDS the state the banner announces, not a dismiss:
  hiding the message alone would leave the reader in the state with no way out.
  Style what goes in it with `.atlas-pane-banner__action`.
  """
  attr :id, :string, required: true
  attr :note_id, :string, default: nil, doc: "id for the message paragraph"
  attr :tone, :string, default: "dark", values: ~w(dark indigo)
  attr :fixed, :boolean, default: false
  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :action

  def pane_banner(assigns)

  @doc """
  The annotate form that sat under the open record.

  **Currently unmounted.** "New activity" in column 1 is the one composer; the
  record opens it with `compose_annotation`. Emits `validate_annotation` and
  `annotate` (params under `"annotation"`: `kind`, `author`, `body`), both still
  handled by `IndivisualWeb.AtlasLive`, which also still holds the
  `annotation_form` / `annotation_errors` assigns to pass here.
  """
  attr :form, :any, required: true, doc: "a form built with `as: :annotation`"
  attr :errors, :list, default: [], doc: "`{field, message}` pairs"
  attr :kinds, :list, required: true, doc: "annotation kinds, as from `Atlas.annotation_kinds/0`"
  attr :id, :string, default: "atlas-annotation-form"

  def annotation_form(assigns)

  @doc """
  The full-width source selector: one option per source, naming what it is, who
  publishes it, and its ingestion status.

  **Currently unmounted.** `/atlas` filters sources from the compact checklist
  on the activity list instead, which sits beside the thing it filters. This row
  is kept because it is the only control that *describes* each source rather
  than just switching it.

  Emits `toggle_source` (with `phx-value-id`) and `clear_sources`; the host
  LiveView must handle both — `IndivisualWeb.AtlasLive` already does. Here a
  pressed button narrows TO a source, so an empty `source_filter` means all.

  Styled by `.atlas-projnav` / `.atlas-sourcenav__*` in `assets/css/app.css`.
  """
  attr :sources, :map, required: true, doc: "sources keyed by id, as from `Atlas.sources/0`"
  attr :source_filter, :list, default: [], doc: "selected source ids; `[]` means all"
  attr :id, :string, default: "atlas-source-nav"

  def source_nav(assigns)

  @doc """
  One relationship on a record, as a row that IS its own way in: the whole row
  opens the event that asserts it. There is no "open" link to aim at.

  It is built as an ACTIVITY ROW, in the activity row's own classes
  (`.atlas-activity__item`): the date and the truth badge on the first line, the
  claim where a title would be, the source underneath, the same left bar, hover
  and selected states. A relationship is what an activity asserted, so it should
  not look like a different kind of object from the activity.

  The relationship asserted by the record already open has nowhere to go, so it
  renders as a plain block in the SELECTED state — the same bar and tint the open
  activity has in the list, which says it without another word.

  Slots: the claim in the inner block; `:at` (date), `:badge` (truth state),
  `:source`.
  """
  attr :event_id, :string, required: true, doc: "the event that asserts the relationship"
  attr :own?, :boolean, default: false, doc: "asserted by the record that is open"
  attr :open, :string, default: "select_event", doc: "host event that opens a record"
  slot :inner_block, required: true
  slot :at
  slot :badge
  slot :source

  def relationship_row(assigns)

  # Heroicons (MIT), 20px solid: `user`, `user-group`, `map-pin` and
  # `document-text`. Inline, because the
  # heroicons Tailwind plugin is not loaded by app.css, so `hero-*` classes draw
  # nothing. One source for every place an entity's kind is drawn — the HTML
  # component below, the graph's SVG nodes, and the map's markers (which get the
  # path as data) — so a kind cannot look different from one view to the next.
  # `document-text`: a written instrument, its ruled lines saying so. One icon
  # for the three kinds that ARE written things — a policy, a document, a plan —
  # because what a reader needs at a glance is "this is a text", and which sort
  # of text is in the word beside it. (`data-kind` still carries the real kind.)
  @written %{
    rule: "evenodd",
    d:
      "M4.5 2A1.5 1.5 0 0 0 3 3.5v13A1.5 1.5 0 0 0 4.5 18h11a1.5 1.5 0 0 0 1.5-1.5V7.621a1.5 1.5 0 0 0-.44-1.06l-4.12-4.122A1.5 1.5 0 0 0 11.378 2H4.5Zm2.25 8.5a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5Zm0 3a.75.75 0 0 0 0 1.5h6.5a.75.75 0 0 0 0-1.5h-6.5Z"
  }

  @entity_icons %{
    "person" => %{
      d:
        "M10 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM3.465 14.493a1.23 1.23 0 0 0 .41 1.412A9.957 9.957 0 0 0 10 18c2.31 0 4.438-.784 6.131-2.1.43-.333.604-.903.408-1.41a7.002 7.002 0 0 0-13.074.003Z"
    },
    "place" => %{
      rule: "evenodd",
      d:
        "m9.69 18.933.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 0 0 .281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 1 0 3 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 0 0 2.273 1.765 11.842 11.842 0 0 0 .976.544l.062.029.018.008.006.003ZM10 11.25a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5Z"
    },
    # `user-group`: a body is people acting together, which reads against the
    # single `user` for a person — the same figure, more of them.
    "body" => %{
      d:
        "M10 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 8a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM1.49 15.326a.78.78 0 0 1-.358-.442 3 3 0 0 1 4.308-3.516 6.484 6.484 0 0 0-1.905 3.959c-.023.222-.014.442.025.654a4.97 4.97 0 0 1-2.07-.655ZM16.44 15.98a4.97 4.97 0 0 0 2.07-.654.78.78 0 0 0 .357-.442 3 3 0 0 0-4.308-3.517 6.484 6.484 0 0 1 1.907 3.96 2.32 2.32 0 0 1-.026.654ZM18 8a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM5.304 16.19a.844.844 0 0 1-.277-.71 5 5 0 0 1 9.947 0 .843.843 0 0 1-.277.71A6.975 6.975 0 0 1 10 18a6.974 6.974 0 0 1-4.696-1.81Z"
    },
    "policy" => @written,
    "document" => @written,
    "plan" => @written
  }

  @doc "The icon for an entity kind as `%{d:, rule:}` (a 20×20 path), or nil when the kind has none."
  def entity_icon_path(kind), do: Map.get(@entity_icons, kind)

  @doc """
  The small icon that says what KIND of thing an entity is: a person for
  `person`, a group for `body`, a map pin for `place`, a written page for
  `policy`, `document` and `plan`. A kind without an icon renders nothing, so it can be placed
  unconditionally beside any entity's name.

  Decorative (`aria-hidden`): the kind is always also in text nearby.
  """
  attr :kind, :string, required: true
  attr :class, :any, default: nil

  def entity_icon(assigns)

  @doc """
  One applied filter, as a chip: what kind of filter, and what it is set to.

  The single treatment for "this is narrowing what you see". With `clear` it is a
  control — the named host event removes the filter, and a ✕ appears. Without, it
  is read-only: it reports a filter whose control lives somewhere else.

  Styled by `.atlas-entitychip*` in `app.css` (the entity focus was the first
  filter drawn this way, and the class kept its name).
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the kind of filter: \"Entity\", \"Range\""
  attr :value, :string, required: true, doc: "what it is set to, in words"
  attr :filter, :string, default: nil, doc: "machine name, exposed as `data-filter`"
  attr :title, :string, default: nil, doc: "hover text; defaults to the value"
  attr :count, :string, default: nil, doc: "e.g. \"11 of 23\""
  attr :clear, :string, default: nil, doc: "host event that removes the filter; nil = read-only"
  attr :clear_label, :string, default: "Remove this filter"
  attr :inline, :boolean, default: false, doc: "no bottom margin, for a line of chips"
  attr :kind, :string, default: nil, doc: "an entity kind, to draw its icon before the value"

  def filter_chip(assigns)

  @doc """
  The filters currently narrowing the activity list: `Filters  Range … · Truth … ·
  Entity …`.

  It sits on the list it describes and answers "how did I get these results?"
  without the reader looking anywhere else. Each filter is SET where it is drawn
  (the range bar, the source rows, the truth and speech bars, the entity in the
  reader) and can be DISMISSED here: undoing a filter is the one thing a reader
  wants from the place that names it, and a chip's ✕ removes that filter
  entirely rather than editing it — so there is still one place to set each one.
  With nothing applied the row is its label (and the view's link) alone. How many
  events that leaves is not repeated here: the timeline's readout says it, and is
  always on screen.

  `filters` is `[%{id, label, value}]`, as from `AtlasLive.applied_filters/1`.
  """
  attr :filters, :list, required: true
  attr :id, :string, default: "atlas-applied"

  slot :action,
    doc: "beside the label: something that acts on the view these filters describe"

  def applied_filters(assigns)

  @doc """
  A person, as a card: the first **kind-specific display** of an entity. Any kind
  may have one; a kind without one keeps the plain heading.

  Takes an `Indivisual.Atlas.Profile` map. Everything but the name is optional —
  most people in the record were never registered, only seen writing something —
  so the card is built to look finished with a name and initials alone, and to
  fill in (photo, role, description, links) as a registration supplies schema.org
  `Person` properties. It never invents: no image means initials, and an
  unregistered person is labelled as such.

  The heading keeps the id it is given, because the surrounding section is
  labelled by it.

  Tailwind, on the page's own theme variables (`--paper`, `--ink`, `--rule`,
  `--link`) rather than fixed palette colours, so it follows light and dark with
  the rest of the page. `.atlas-person` in `app.css` only undoes two global prose
  rules (the `h2` top margin, the paragraph measure).
  """
  attr :profile, :map, required: true, doc: "as from `Indivisual.Atlas.Profile.person/2`"
  attr :id, :string, default: "atlas-person"
  attr :title_id, :string, default: "atlas-person-title"

  def person_card(assigns)

  @doc """
  The projection row: the four `Atlas.Projections` as a radio group, each with
  its name and the question it answers.

  **Currently unmounted.** Nothing on `/atlas` is chosen by projection any more.
  The page shows all four at once, so the row offered a choice between things
  that were already side by side; its questions moved onto the panels they
  describe (`AtlasLive.panel_question/1`).

  Emits `select_projection` with `projection`. The host still handles it, but
  only Topology has an effect left — it switches the graph's "connected only"
  toggle — because that was the one thing a projection changed that nothing else
  on the page now covers.

  Styled by `.atlas-projnav*` in `assets/css/app.css`.
  """
  attr :projections, :list, required: true, doc: "as from `Atlas.projections/0`"
  attr :projection, :string, required: true, doc: "id of the active projection"
  attr :id, :string, default: "atlas-projection-nav"

  def projection_nav(assigns)

  @doc """
  The Position panel: a collapsible scrubber that steps the selection through
  the events in the current range, one index at a time.

  **Currently unmounted.** It selects an event, which the activity list, the
  marks band and Prev / Next already do, and the range bar's dots now show where
  the selection stands. Kept because it is the only control that moves through
  events by dragging.

  Emits `scrub` (form change, `%{"index" => i}`) and `toggle_scrubber`; the host
  LiveView must handle both — `IndivisualWeb.AtlasLive` already does, and still
  carries the panel's open state in the URL as `sc`.

  Styled by `.atlas-timeline__scrub` and `.atlas-accordion*` in
  `assets/css/app.css`; expects to sit inside `.atlas-timeline`.
  """
  attr :count, :integer, required: true, doc: "events in the current range"
  attr :index, :integer, default: nil, doc: "index of the selected event"
  attr :valuetext, :string, default: nil, doc: "the selected event, in words"
  attr :open?, :boolean, default: true

  def position_scrubber(assigns)

  @doc """
  The feed's status line: where the data comes from, whether the live feed is
  connected, whether appended events are being persisted, and how many events
  are in view.

  **Currently unmounted** (2026-09-20). It sat in the `/atlas` header, above the
  timeline. It is useful, but it describes the plumbing rather than the record,
  so it should not be the first thing on the page. Kept as the seed of a sources
  / settings page — the place a reader will connect and inspect their sources.

  Takes `Feed.status/1` as `status`. Inner ids (`atlas-live-status`,
  `atlas-persistence-status`, `atlas-event-count`) are fixed, so mount it once.
  """
  attr :id, :string, default: "atlas-status"
  attr :status, :map, required: true, doc: "`%{persistence:, persisted_count:}`"
  attr :live?, :boolean, default: false
  attr :live_updates, :integer, default: 0
  attr :event_count, :integer, required: true

  def feed_status(assigns)

  @doc """
  The compact Sources checklist: one row per source — box, title, event count —
  with "N of M" and an `all` reset in its head.

  **Currently unmounted** (2026-09-20). It sat at the top of column 1 on
  `/atlas`. Sources are now filtered on the timeline, where the "By source" rows
  carry the same checkboxes beside each source's bar; two copies of one control
  in two places was one too many. Kept because it is the form to use wherever a
  source filter is needed without a timeline beside it.

  Emits `check_source` (`phx-value-source`) and `clear_sources`; the host must
  handle both — `IndivisualWeb.AtlasLive` does. Checked means included: `shown`
  is every source when `filter` is `[]`.

  Styled by `.atlas-srcfilter*` in `assets/css/app.css`.
  """
  attr :sources, :map, required: true, doc: "sources keyed by id, as `Atlas.sources/0`"
  attr :filter, :list, default: [], doc: "the raw filter; `[]` means no filter"
  attr :shown, :list, required: true, doc: "ids currently included"
  attr :counts, :map, default: %{}, doc: "events per source id"
  attr :id, :string, default: "atlas-activity-sources"
  attr :item_prefix, :string, default: "atlas-activity-source"

  def source_checklist(assigns)

  @doc """
  What each axis of a view means, in words: `x … · y … · z …`.

  Every spatial view on `/atlas` chooses its axes, and that choice is an opinion
  about the record — so it is stated, in the DOM, beside the view, rather than
  left to be inferred from a picture (or from labels inside a WebGL canvas that
  a screen reader cannot reach). Use it on any view that places things. Pass
  `nil` for an axis the view has but does not use — that is said too ("not
  used") — and leave an axis at its default `:omit` for a view that has none
  (a 2D view has no z).
  """
  attr :id, :string, default: nil
  attr :x, :any, default: :omit
  attr :y, :any, default: :omit
  attr :z, :any, default: :omit

  def axes(assigns)

  @doc """
  The Spacetime scene: every activity and entity as a point in one three.js
  scene, where the timeline, a moment, the map and the graph are LAYOUTS of the
  same points (`Indivisual.Atlas.Scene`). Drawn by `assets/js/atlas_scene.js`
  through the `.Scene3D` hook defined in this component's template.

  It is one component so it can be **rendered more than once on a page**, each
  instance a different cut of the same payload:

    * `variant="panel"` — a 3D stage you can orbit, with a layout switch.
    * `variant="strip"` — flat and fixed, laid out in pixels. `/atlas` uses this
      for the sticky timeline, locked to the `timeline` layout with
      `kinds={["event"]}` and no switch, so the band in the controls and the
      scene in the canvas column are the same points drawn twice. The panel
      offers `timeline` too: there it is the 3D take, with entities and links.

  The layout switch is real DOM and emits `switch` (default `scene_layout`) with
  `phx-value-layout`; the host keeps the layout (on `/atlas`, in the URL). Pass
  `layouts={[]}` to lock an instance to its `layout`. A point emits
  `select_event` (`id`) or `focus_entity` (`ref`) when clicked.

  The canvas is decorative to assistive tech (`role="img"`): `label` must say
  where the same information lives as text.
  """
  attr :id, :string, required: true
  attr :payload, :map, required: true, doc: "`%{nodes:, links:}`, as `AtlasLive.scene_payload/4`"
  attr :layout, :string, required: true
  attr :all_layouts, :list, required: true, doc: "every layout definition, for guides and axes"
  attr :layouts, :list, default: [], doc: "the ones offered in the switch; `[]` locks the layout"
  attr :variant, :string, default: "panel", values: ~w(panel strip)
  attr :kinds, :list, default: [], doc: "node kinds to draw; `[]` draws all"
  attr :switch, :string, default: "scene_layout"
  attr :label, :string, required: true
  attr :stage_style, :string, default: nil

  attr :fit, :string, default: nil, doc: "strip only: \"focus\" | \"all\", which span it shows"
  attr :band_style, :string, default: nil, doc: "inline style while flat, e.g. `--lanes: 12`"

  attr :axes, :list,
    default: [],
    doc: "the `[x, y, z]` dimension ids on show; `[]` (the strip) draws no axes bar"

  attr :dimensions, :list,
    default: [],
    doc: "everything an axis can carry, as `%{id:, name:, says:}` (`Scene.dimensions/0`)"

  attr :axes_event, :string,
    default: "scene_axes",
    doc: "host event for a dropdown change; params `%{\"axes\" => %{\"x\" => id, …}}`"

  attr :axis_bounds, :map,
    default: %{},
    doc: """
    Per-axis pole overrides, e.g. `%{z: %{low: "2024-04-09", high: "2026-09-19"}}`.
    A layout states what an axis MEANS ("earlier → later"); this says where it
    currently runs FROM and TO, so the frame answers to the filters rather than
    reading the same whatever is in view.
    """

  slot :title
  slot :tools, doc: "beside the layout switch: e.g. a picker of the reader's saved modes"
  slot :caption

  def spacetime(assigns)

  # What an axis means, from the dimension on it.
  defp axis_says(dimensions, dim) do
    case Enum.find(dimensions, &(&1.id == dim)) do
      %{says: says} -> says
      nil -> "not used"
    end
  end

  # Where an axis currently RUNS — "2024-04-09 → 2026-09-19" — when the host
  # knows (`axis_bounds`); otherwise what it means. An axis that read the same
  # however far the date range was narrowed would have stopped describing the view.
  defp axis_runs(_dimensions, _dim, %{low: low, high: high})
       when is_binary(low) and is_binary(high),
       do: "#{low} → #{high}"

  defp axis_runs(dimensions, dim, _bounds), do: axis_says(dimensions, dim)

  @doc """
  Activity dots along a range bar or one of its per-source lanes. Each dot is
  `%{x:, count:, read?:, selected?:}` — `x` a 0–1 fraction along the bar, as
  from `Indivisual.Atlas.Timeline.ordinal_dots/2`. A dot with `count > 1` is a
  packed run and prints its count.

  Decorative (`aria-hidden`) and never takes the pointer: the handles above the
  dots do, and the surrounding readout says the same thing in words.

  Styled by `.atlas-range__dot*` in `assets/css/app.css`; the parent must set
  `--thumb-w` so dots line up with the handles.
  """
  attr :dots, :list, required: true
  attr :id, :string, default: nil

  def range_dots(assigns)

  @doc """
  A collapsible panel: a rule down its left edge, a caret, a title, and whatever
  the caller puts beside the title. The header stays when the body folds, so
  anything in `:head` is what a collapsed panel still says about itself.

  The component owns no state. `open?` comes from the host, and `toggle` names the
  host event that flips it — so the host can keep the state in the URL.

  The body is hidden with the `hidden` attribute, not removed. A caller whose body
  is expensive should wrap its own content in `if @open?`.

  Styled by `.atlas-accordion*` in `assets/css/app.css`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open?, :boolean, required: true
  attr :toggle, :string, required: true, doc: "host event that flips `open?`"
  attr :toggle_id, :string, required: true, doc: "id of the caret button"
  attr :body_id, :string, required: true, doc: "id of the folding region"
  attr :label, :string, default: nil, doc: "name used in \"Collapse …\"; defaults to the title"
  slot :head, doc: "controls and readouts beside the title; visible when collapsed"
  slot :inner_block, required: true

  def accordion(assigns)

  @doc """
  "Space": one point per event in a WebGL volume of three opposing-pole axes.

  **Currently unmounted.** Positions are placeholders — a hash of the event id —
  and the Spacetime panel draws the same events in layouts whose axes mean
  something. Kept for when events carry real coordinates on axes like these.

  Emits `select_event` with `id`. Carries its own `.Scatter3D` colocated hook,
  which wraps `assets/js/atlas_scatter.js`. Styled by `.atlas-scatter*`.
  """
  attr :scatter, :map, required: true, doc: "as from `Indivisual.Atlas.Scatter`"
  attr :events, :list, required: true
  attr :selected, :any, default: nil, doc: "the selected `Atlas.Event`, if any"
  attr :selected_index, :any, default: nil

  def space(assigns)

  @doc """
  A real map: Leaflet over OpenStreetMap tiles, one pin per located entity, and
  a count of the entities that have no location. Renders nothing when no entity
  is located.

  **Currently unmounted.** Spacetime's `map` layout places the same entities on
  the same ground. Kept: the only slippy map.

  Emits `focus_entity` with `ref`. Carries its own `.LeafletMap` colocated hook.
  Styled by `.atlas-map*`.
  """
  attr :geo, :map, required: true, doc: "as from `Indivisual.Atlas.Geo.project/1`"
  attr :entity, :any, default: nil, doc: "the focused entity ref, if any"
  attr :affected, :list, default: []

  def map(assigns)

  @doc """
  The topology as an SVG graph: entities on a ring, every relationship a
  labelled edge, with the "connected only" filter.

  **Currently unmounted.** Spacetime's `graph` layout covers it. Kept: the only
  view that labels every edge, and the only picture of the record that is plain
  DOM rather than WebGL.

  Emits `toggle_connected` and `focus_entity` (with `ref`). Its heading is
  `#atlas-canvas-title`, which the canvas column used to be labelled by — if this
  is remounted there, point the column's `aria-labelledby` back at it. Styled by
  `.atlas-graph*` and `.atlas-panelhead`.
  """
  attr :read_model, :map, required: true, doc: "the topology read model"
  attr :selected, :any, default: nil
  attr :entity, :any, default: nil
  attr :affected, :list, default: []
  attr :connected_only?, :boolean, default: false
  attr :graph_hidden, :any, default: nil, doc: "what \"connected only\" removed"

  def graph(assigns)

  defp accordion_action(true, name), do: "Collapse #{String.downcase(name)}"
  defp accordion_action(false, name), do: "Expand #{String.downcase(name)}"
end
