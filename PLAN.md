# PLAN

The entrypoint for this project. Tasks are tracked **inline, in this file**.
When this file and the code disagree about what is done, the code wins — fix
this file.

## Why

Atlas's main inspiration, in Ryan's words: **better interfaces for The Public
Record, and better tools for public decision-makers.** Two audiences, one record.
Weigh every Atlas feature against both: does it make the record easier to read
for a resident, and does it put what matters in front of someone about to decide?

What that is reaching for (Ryan, 2026-09-20; on `/atlas/about` as "What it is
reaching for"): **higher levels of situational awareness** — relations conveyed
explicitly as information; **a single source of truth**, everybody on the same
page; and **perspectives made explicit**, to level up meta-communication. The
last is why filters are 100% visualized, axes are named, and the view state is
a link: how you are looking is on the screen and can be handed over. One record
is not one opinion — it holds what was asserted, by whom, and how settled.

### The bigger idea: data models resolve to schema-typed objects you can see

Ryan, 2026-09-20. Every organization has a data model — all of them implicitly,
some explicitly — and those models should almost always be **resolvable to
schema-typed objects, which can then be viewed.** Two consequences to build
toward:

- **An object should arrive with its assumed UX.** If something resolves to a
  schema.org `Place`, a `GovernmentOrganization`, a `MonetaryAmount`, it should
  come with the representation a person expects for that type — a pin, a card, a
  ledger line — rather than each app inventing one. In Atlas terms this is the
  facet → derivation → view chain (`docs/VIEWS.md`) keyed by TYPE: the type
  registry in `ARCHITECTURE.md` ("strongly typed" entity kinds), the schema.org
  mapping in `STANDARDS.md`, and the one "object card" the record panel is the
  seed of. `AtlasLive.entity_schema_type/2` is the first thread of it.
- **Digital things gain a tangible affordance.** With a chain underneath, an
  object can carry legal ownership and veracity — who holds it, who attests it,
  whether it has been altered — and the UI should let a person *handle* that the
  way they handle a physical document: see it is signed, see whose it is. Atlas
  already keeps the ingredients (content hash, provenance, truth state,
  signature slot); `docs/chain-permanence-vs-privacy.tldr` is the constraint on
  what may be anchored.

Weigh new entity / schema work against this: does it make an organization's
model more resolvable to typed objects, and does the object show what it is?

Authoritative docs (everything else is reference):

- `CLAUDE.md` — commands, architecture, invariants
- `ARCHITECTURE.md` — events → entities → graph, and the order to build it in
- `EVENT_UI.md` — how writes (annotations) should work
- `USER_SCOPING.md` — ownership and GitHub marshalling
- `STANDARDS.md` — which field names are borrowed from standards, and which are ours
- `docs/VIEWS.md` — facets → derivations → views: what the data lets the UI do
- `docs/chain-permanence-vs-privacy.tldr` — the sketch. Frames: chain permanence
  (×2), *Atlas: activity stream + structured elements* (the one-sentence idea), and
  *Atlas: /atlas wireframe and components* (low-res layout; black = component,
  green = what it binds to). Revisit the wireframe when a component mounts,
  unmounts or moves.
- `/atlas/about` (`page_html/atlas_about.html.heex`) — the ideas behind Atlas, for
  readers. **Draft.** Its figure is a PNG export of the Atlas frame above.
- `IndivisualWeb.AtlasComponents` moduledoc — the register of mounted / unmounted UI

## Now

**Make `/atlas` filtering 100% visible.** The projection row is retired (Steps 4
and 5, done): the four projections are each on screen where they belong, and
there is one URL. What remains is the audit under Next — the base (total events,
date selector) reads first, then each filter in the order it restricts.

## Principles

### Filtering is 100% visualized

Decided 2026-09-20. Every filter on `/atlas` has an interface you can *see*, and
the page always answers "how did I get to these results?" at a glance.

- **The base is always on screen:** the total number of events, and a date
  selector over all of them.
- **Each further filter visibly restricts that base.** Sources, truth state,
  entity focus, in/out of range — each shows what it is, what it is set to, and
  what it removed. A filter that narrows results with no visible control or
  readout is a bug. (The old Topology projection did this: it silently narrowed
  the graph to events up to the selected one.)
- **Filtered-out is shown as filtered-out, not as absent.** Dots stay on the
  range bar and go hollow; a truth chip goes quiet rather than disappearing;
  counts say what checking a box would add.
- **Filters are distinct from the activity they narrow.** A source is a
  publisher, a truth state is a kind of claim, an entity is a subject. In column
  1 they sit together (`#atlas-filters`) ABOVE the Activity heading; the list
  under the heading is what they leave.
- **Every filter is URL state**, so a shared link reproduces the view, and
  "checked means included / all checked is no filter / the last one stays on"
  holds for every checklist.
- A lens changes what is read, never what was recorded — and never an entity's
  identity (label, kind, location survive any filter).

### Axes are explicit

Decided 2026-09-20. Every view that places things chooses its axes, and that
choice is an opinion about the record. So:

- **In Spacetime, x and y are the 2D space and z is time** — wherever a mode has
  a time axis. An event's z is when it happened, whatever is on show; a mode
  only decides x and y. `timeline` is that volume seen from the side; a `moment`
  is a plane cutting z at one instant (a temporal slice — the state of things at
  a given time), so the plane moves and the events stay put, and there time runs
  INTO the screen (past near, future far). `map` is the one mode with no time
  axis: it folds z flat.
- **A mode is only a choice of three dimensions**, and the presets are the
  well-known choices: Spacetime `lng, lat, time` (the map with time added),
  Timeline `none, stack, time`, Moment `entity, stack, time`, Map
  `lng, lat, none`, Graph `semantic, semantic, time`. Nothing is a placeholder.
- **Axes are stated in words, in the DOM, beside the view**
  (`AtlasComponents.axes/1`): `x … · y … · z …`. An axis a view folds away is
  said to be "not used"; a view whose positions mean nothing (the graph's ring)
  says that. Never leave it to labels inside a canvas.
- **The axes animate with the points.** A layout's 2D space is one box at
  different proportions — cube, square, the timeline's side-on plane — so the
  frame and its axes morph between layouts instead of being swapped.

### The timeline is a slice

Decided 2026-09-20. The timeline should feel like a huge arc — so large it is
flat — of which we are only ever looking at a piece: a partial state of all
events. What is on screen is what THIS record covers, not what happened.

- **Drawn as a slice.** The axis is an arc of a very large circle (a few pixels
  of sag), inked only across the record's own span; past the first and last
  activity it carries on faint and fades out at the edges instead of stopping.
  A "now" tick splits what happened from what has not.
- **The ends say what lies beyond.** Inside the record: a count, and a way to
  take it in. At the record's own ends: "the record starts / ends here", and
  what kind of source would extend it — never an implication that the world
  begins and ends with our data.
- **Coverage is something a reader can expand.** See "Expanding coverage" under
  Considering.

### Unused UI is registered, not deleted

See the `AtlasComponents` moduledoc. Mount or unmount in the same change that
updates the register.

## Tasks

Each is a user-story scenario with at least one test. Worked in order.

### Done (2026-09-20)

- [x] *As a reader I filter sources from the list they filter.* Compact source
  checklist on the activity column; the full-width row is unmounted
  (`source_nav/1`). — `atlas_activity_sources_test.exs`
- [x] *As a reader I set a date window on one bar.* Two handles on one track; a
  handle at an end is an open bound; in range / out of range; dates ride above
  the handles. — `atlas_timeline_test.exs`
- [x] *As a reader I see every activity on that bar.* One dot per event on the
  handles' (ordinal) axis, packing into counted runs at scale; fans out into one
  lane per source and collapses back. — `atlas_timeline_test.exs`,
  `atlas_timeline_test.exs` (unit)
- [x] *As a reader the calendar tells me the range it covers.* Tick grain
  follows the window; both ends always carry the exact date. — unit tests
- [x] Position scrubber unmounted (`position_scrubber/1`); register of unused UI
  started. — `atlas_components_test.exs`
- [x] **Step 1** — `Projections` has a unit-test baseline. —
  `atlas_projections_test.exs`
- [x] **Step 2** — *As a reader I filter by truth state.* Chips in the activity
  column, all six states always listed, counts respect the other filters. —
  `atlas_view_state_test.exs`
- [x] **Step 3** — *As a reader I focus an entity and can get back out.* Chip
  with ✕ on the list; list narrows to touching events; the reader column shows
  the entity's events, sources and unresolved items under any projection. —
  `atlas_view_state_test.exs`
- [x] *As a reader I can look at the view without a record open.* ✕ on the
  record and an "All" row on the list both give `?event=none`; the reader
  column then describes the view. — `atlas_view_state_test.exs`

- [x] *As a newcomer I can read what Atlas is for before using it.*
  `/atlas/about`, linked from home. — `page_controller_test.exs`

- [x] *As a reader I see every event as a point in a 3D volume, and can open one
  from it.* "Space" panel at the top of the canvas column: one point per event in
  view, three hard-coded opposing-pole axes, orbit / zoom, hover names a point,
  click selects it; the selection is haloed and events after it are dimmed.
  **Positions and axes are placeholders** (`Atlas.Scatter`, `basis:
  :placeholder`, hash of `event_id`) and the caption says so — making them
  meaningful is a separate task. Drawn by `assets/js/atlas_scatter.js` through
  the `.Scatter3D` hook; verified in headless Chrome, not yet by eye in the app.
  — `atlas_scatter_test.exs` (unit + live)
- [x] *As a reader I step through records from where I am reading them.* Prev /
  Next at the top of the reader column, the same `step` event as the timeline's
  pair; disabled at either end. — `atlas_reader_step_test.exs`
- [x] The controls block (`#atlas-controls`) sticks on wide, tall viewports; the
  canvas column sticks *below* it (`--atlas-controls-h`, published by the
  `.ControlsHeight` hook) and scrolls on its own. — `atlas_layout_test.exs`

- [x] *As a reader I get from every truth state to just one in two clicks.*
  "none" beside "all" (`?truth=none`, a real and shareable state); the list says
  why it is empty; the last checked chip still cannot be unchecked. —
  `atlas_view_state_test.exs`
- [x] A truth state looks the same everywhere: `.atlas-truth[data-truth]` is the
  one badge, used on rows, entity context, the record, and the filter chips
  (which were black-on-white: an unlayered `button` rule beats Tailwind's layered
  colour utilities). Activity rows are ruled, with hover and selection on the
  whole row. Checked by rendering the page with the built CSS in headless Chrome.

- [x] **Step 4** — *As a reader, the graph reads exactly the window I set.*
  `Projections.materialize("topology", …)` no longer narrows to the events up to
  the selected one; the range bar is the only window. "connected only" is a
  visible checkbox on the graph's heading (`?connected=1`) that says how many
  entities it hid. — `atlas_projections_test.exs`, `atlas_projection_menu_test.exs`
- [x] **Step 5** — *As a reader I am not asked to choose between things that are
  all on screen.* Projection row unmounted into the register
  (`projection_nav/1`); each question sits on the panel it describes
  (`panel_question/1`); Provenance count chips and the "Entity context with no
  focus" hint removed. **No `?projection=` — one URL, no back-compat** (decided
  2026-09-20: nothing has shipped). — `atlas_projection_menu_test.exs`

- [x] *As a reader I can watch the timeline, the map and the graph turn into
  one another.* "Spacetime" panel, top of the canvas column: every activity and
  every entity is a point in ONE three.js scene, and Timeline / Moment / Map /
  Graph / Space are **layouts** of those points, so switching tweens them — a 2D view is a
  slice of the volume (`time` and `graph` on the XY plane, `map` on the ground),
  and time is the axis perpendicular to the slice. What a layout cannot place
  (an entity with no coordinates) goes to a dimmed shelf and is counted in the
  caption. Layout is URL state (`?scene=`). Server: `Atlas.Scene` (pure);
  client: `assets/js/atlas_scene.js` via the `.Scene3D` hook. —
  `atlas_scene_test.exs` (unit + LiveView). **Not yet seen in a browser**: a
  headless-Chrome screenshot hung on the page's render loop, so the JS is
  bundled and unverified by eye. The existing Space, Map and Graph panels are
  untouched; whether Spacetime replaces them is the open question below.

- [x] *As a reader I see two distinct takes on time.* `timeline` runs ALONG
  time (many events, each its own object, across the span); `moment` cuts ACROSS
  it (a thick slice at the selected event's instant: what happened then lies on
  the plane over the entity it touches, the rest recedes behind or comes forward
  by how long before or after). — `atlas_scene_test.exs` (unit)
- [x] *The timeline is a view mode of Spacetime, rendered twice.*
  `AtlasComponents.spacetime/1` draws both the sticky timeline (`variant="strip"`:
  flat, pixel-laid, events only, locked to `timeline`) and the canvas-column
  panel (Timeline · Moment · Map · Graph · Space; it opens on Moment, and its
  Timeline is the 3D take with entities and links). The date axis under
  the strip stays DOM on the same inset. `?band=dom` swaps the strip for the old
  DOM marks (WebGL fallback; the marks tests run against it). — `atlas_scene_test.exs`
  **Not yet seen in a browser.**
- [x] *As a reader, "By source" and the Sources filter are one control.* The
  toggle sits left of the range bar; fanned out, every source has a row headed by
  the same checkbox as column 1 (`check_source`, same state), its bar under the
  main bar's axis. An unchecked source keeps its row, dimmed and empty. —
  `atlas_timeline_test.exs`

- [x] Column 1's Sources checklist unmounted (`source_checklist/1`, registered):
  sources are filtered on the timeline's "By source" rows, whose labels are now
  smaller, and the folded toggle shows "N of M" while a source filter is on so
  the filter is never invisible. — `atlas_source_filter_test.exs`,
  `atlas_components_test.exs`

- [x] *As a reader I am told what the axes mean.* Convention and legend above;
  morphing frame and axes in `atlas_scene.js`; map is now x/y = lng/lat with
  events coming forward in time; timeline is seen side-on. —
  `atlas_scene_test.exs` (unit + LiveView). **Not yet seen in a browser.**

- [x] *As a reader I see the whole record on the timeline, and zoom to what I
  filtered.* The strip's rectangle runs from the first to the last activity of
  the WHOLE record and every activity is always on it; filters ink or hollow the
  dots and the view focuses on the span they leave ("In focus" / "Whole record",
  `?fit=all`). Year and month markers are drawn in the strip and gain detail
  with the zoom; the view window is on a spring and stacks re-sort as they pull
  apart (after Yugo Nakamura's yugop Flash work). Own renderer,
  `assets/js/atlas_timeline_strip.js`, behind the same `spacetime/1` component.
  The DOM band is now only the `?band=dom` fallback. — `atlas_scene_test.exs`.
  **Not yet seen in a browser.**
- [x] *As a reader I see both clocks at once, and the gap.* Column 2 puts
  Occurred and Observed on one line with the lag between them: `→ 3 d later`,
  `= same moment`, `← 3 d ahead` (announced in advance), `∅ only observed` (the
  source states no time — reported, not filled in). — `atlas_record_test.exs`

- [x] *As a reader I see the places on a real map, in the scene.* The `map`
  layout is laid out in Web Mercator at one scale for both axes
  (`Scene.mercator/2`, `Scene.map_view/1`), and the client lays OpenStreetMap
  tiles on its plane: fetched only when the Map layout is asked for, clipped to
  the frame, dimmed for the dark stage, faded in with the morph, credited in the
  caption. Checked: the fixture centres on Vacaville (38.36, −121.95), zoom 15,
  9 tiles, and the tile server allows cross-origin textures. —
  `atlas_scene_test.exs`. **Tiles not yet seen in a browser.**
- [x] *As a reader I can tell the timeline is a slice.* Arc, fading ends, "now"
  tick, and end caps ("← 12 earlier", "the record ends here →") that release the
  date range on their side. — `atlas_scene_test.exs`

- [x] Truth state moved out of column 1 into the sticky controls, as its own bar
  beside the timeline (a distinct filter: how settled, not when). Column 1 is
  now the entity focus, the Activity heading, and the list. —
  `atlas_view_state_test.exs`, `atlas_legend_test.exs`
- [x] *As a person I write into the record from the Activity header.* "New
  activity" opens ONE composer for the two subclasses of a post
  (`Indivisual.Atlas.Post`): a **note** (a plain post; about the entity in focus,
  if any) and an **annotation** (a note about the open record, with a kind).
  Both are an AS2 `Note` — the annotation has `inReplyTo` — from one source
  ("Posts and annotations"), on one sequence counter, `reported` by default, and
  each appends one event and changes nothing else. The older annotate form in
  column 2 is still there. — `atlas_post_test.exs` (unit + LiveView). Tests that
  append to the shared feed are tagged `:writes_atlas_feed` (see `DataCase`).

- [x] *As a reader I move the timeline into its own tab and it still drives the
  view.* Tabs on one `?v=<token>` share what they READ (filters, range,
  selection) over PubSub and keep how they SHOW it (pane, layout, folds) to
  themselves — `AtlasLive.ViewSync`. "Detach ↗" is a plain link to a new tab
  (`pane=timeline`) and turns this tab into `pane=view`; "Reattach" undoes it and
  tells the timeline tab. A tab that joins late listens first and is brought up
  to date. "Share this view" never carries the token. — `atlas_view_sync_test.exs`
- [x] Map layout behaves as a web map: bird's-eye camera, no turning, drag to
  pan, scroll to zoom, and tiles chosen from what is on screen (zoom level from
  drawn tile size, tiles from the rectangle in view), loaded as the view moves,
  kept until their replacements arrive, capped at 80, pan clamped near the data.
  Events at one place fan out round it in time order (a sunflower spiral), since
  from above they would otherwise hide each other. — `atlas_scene_test.exs`.
  **Pan / zoom / tile loading not yet seen in a browser.**
- [x] Feed status line (data · feed · persistence · events) unmounted from the
  `/atlas` header → `AtlasComponents.feed_status/1`, registered.

- [x] `/topo` removed: routes, `PageController.topo/2`, the template,
  `assets/js/topo.js` (1,695 lines), its CSS, the nav and home links, and its
  tests; `/topo` now 404s. Kept, with no UI: `Spaces`, `Semantic`, `MuniCodes`,
  `Embeddings`, the embedding worker and `priv/repo/seeds_topo_demo.exs`. —
  `topo_atlas_test.exs`

- [x] *As a reader I choose what each Spacetime axis shows.* An x / y / z bar
  runs along the stage's bottom border (no rails up the sides or over the top):
  each axis is a dropdown of every dimension (`Scene.dimensions/0` — time,
  longitude, latitude, entity, ring x/y, simultaneity, source, truth state,
  placeholders, none), with where it currently runs beside it. A layout is only
  a choice of three; three that ARE a preset are that preset, anything else is
  `scene=custom&axes=x,y,z`. Points lacking a chosen dimension are shelved on
  that axis and counted. In the scene an axis carries only its letter. —
  `atlas_scene_test.exs` (unit + LiveView)
- [x] Only the detached timeline tab drops the site header and footer; the view
  tab keeps them.

- [x] Dragging a range handle unchecks "All events" (a filter is now applied);
  the handles are never disabled. — `atlas_timeline_test.exs`

- [x] *The Timeline layout looks like the timeline, and lives in the one scene.*
  In the Spacetime panel `scene=timeline` is the same 3D scene seen from the
  side (so points still travel to and from the other layouts), ruled like the
  sticky strip: an axis along time, a tall tick and label per year, month ticks
  (named when there is room), a red "now". The server sends the `span` z stands
  for. (A first version swapped in the strip's own renderer; that lost the
  journey between layouts and was reverted.) The whole panel is now drawn on the
  page's paper in its inks — truth colours as they come, tiles barely dimmed —
  rather than as a dark stage. — `atlas_scene_test.exs`.
  **Not yet seen in a browser.**
- [x] Flaky explain test fixed: `explain_event` now runs under `start_async/3`,
  so `render_async/1` waits for it (it was a bare `Task.Supervisor` child).

- [x] *As a reader I separate what happened from what exists.* Verbs and nouns:
  an event that registers an entity is a **noun** (the cast), anything else is a
  **verb** (the plot) — `Event.part_of_speech/1`, derived from the event's shape
  and never stored. A third bar in the sticky controls, same checklist contract,
  URL `speech=`, counted with the other filters applied, shared between linked
  tabs; list rows carry the scene's marks (● activity, ◆ entity). —
  `atlas_view_state_test.exs`
- [x] "Entities in view" opens by default and stays as the reader leaves it; the
  x / y / z axes bar is three thin rows; the "view" label on column 2's overview
  is gone.

- [x] Fixed: Spacetime's link lines neither grew nor cleared. three.js 0.181's
  `BufferGeometry.setFromPoints` writes into an existing buffer at its ORIGINAL
  size, so lines added by a filter or layout change were dropped and removed
  ones stayed as stale segments. The scene now owns the buffer (grown on demand,
  `setDrawRange` to the live count). Affected every layout.
- [x] The Timeline layout is locked square-on like the map (no turning; drag
  pans along time, scroll zooms), and the links and the faint volume cube fade
  out there.

- [x] *As a signed-in reader I keep my own Spacetime modes.* The built-in modes
  are explicit x / y / z mappings, so a saved mode is one more: a NAME for three
  axes (`Indivisual.SceneModes`, table `atlas_scene_modes`, scoped like
  `Timelog` — scope first, no `nil` clause). A "My modes…" dropdown beside the
  switch; under a custom set of axes, "Save mode" (or "Saved as X · Delete", or
  a sign-in prompt). The URL still carries the AXES, never the mode, so a shared
  link works for someone who has not saved it and a name stays its owner's.
  `/atlas` stays public: a `live_session` with `UserAuth.on_mount
  (:mount_current_scope)` only tells the LiveView who is signed in. —
  `scene_modes_test.exs`, `atlas_scene_modes_test.exs`
- [x] The map is a GROUND that goes with the axes: any mode with longitude on x
  and latitude on y gets tiles, not only the Map preset (which alone is
  bird's-eye and loads by what is on screen).
- [x] Space is the leftmost mode. In Moment, time runs INTO the screen: the past
  is near the viewer, the future far (map and graph still run it toward you,
  off their back plane). The axes bar says which.
- [x] The activity list is grouped by day: a sticky heading with a count. Every
  row also says its own date (and the time, when the source gave one), so a row
  reads whole on its own. A day folds to its heading; **Days · all / none** opens
  or folds every day, each offered unless it is already the case. Folding is how
  the list is read, not what is read, so it is NOT in the URL; choosing a record
  from anywhere opens its day. — `atlas_view_state_test.exs`
- [x] *As a reader I can see what the verbs are and what the nouns are.* The bar
  is now **Events & entities** — events are the verbs, entities the nouns (the
  same entities as everywhere else) — and under the chips it lists the words:
  each kind of happening without the source's namespace ("plan initiated",
  with a count when it recurs) and each entity by name, which focuses it. A
  filtered-out part keeps its words, struck through. `AtlasLive.speech_words/1`.
  — `atlas_view_state_test.exs`
- [x] One composer. Column 2's annotate form duplicated "New activity", so it is
  unmounted (`AtlasComponents.annotation_form/1`, registered); the record has an
  **Annotate this record** button that opens the composer pre-set to an
  annotation. — `atlas_post_test.exs`
- [x] "Explain this record" looks like what it is — the app's one machine voice,
  and a local one: a tinted, dashed card; under the button a badge names the
  model (`✦ qwen3:8b · local`) and the line it starts says nothing is sent
  anywhere and nothing it writes enters the record. — `atlas_explain_test.exs`

- [x] *Space became Spacetime, and the Graph became about meaning.* Settled with
  Ryan 2026-09-20. **Spacetime** (leftmost mode, id `space`) is the map with time
  as a third axis — `lng, lat, time`, orbiting, tiles underneath, events standing
  over their places at the height of when. **Map** is that ground with no time
  axis (`lng, lat, none`), bird's-eye. **Graph** is x and y on SEMANTIC AXES with
  the relationships drawn and time toward you. The placeholder hash dimensions
  and the meaningless ring are gone. — `atlas_scene_test.exs` (unit + LiveView)
- [x] *As a reader I place things by what they mean.* `Atlas.Semantics` embeds
  each event's text once (ETS, keyed by model + content; in a task, never on the
  reader's process) and scores it against the semantic axes in the database
  (`Indivisual.Semantic.Axis`: two poles, anchored by example phrases). Each axis
  is a dimension in the x / y / z dropdowns of every mode — that is what makes
  them **customizable**. Entities read as the mean of the events that touch
  them. Derived and disposable: nothing here is an event. Unscored points are
  shelved and counted; the panel says when there are no axes, when embedding is
  under way, and when the backend is down. — `atlas_semantics_test.exs`
- [x] Site footer (`about` · `github`); the source link left the home page's text.

- [x] "Share this view" is gone as a heading: the block IS its action, **Copy
  link**, then "Your view state: …". That the link carries the query, not the
  screen — so another reader gets the same query shown their way — is said in
  the button's tooltip only; the visible sentence was removed as clutter.
  Copy link is an `<a href>` to the view itself, so right-click / drag /
  bookmark / ⌘-click all work; a plain click copies. The printed url is gone —
  the address bar already shows it. — `atlas_share_test.exs`
  It lives in the **view bar** (`#atlas-viewbar`), one line at the top of every
  pane: the pane note when the tab is a pane, Copy link + view state, and
  Detach ↗ at the right. So it no longer needs a record to be open.

- [x] The page tagline ("Shared models of reality…") shows only on the whole
  page. Neither pane renders it; the view pane still keeps the site masthead
  and footer (only the detached timeline is `.atlas--bare`). —
  `atlas_view_sync_test.exs`
- [x] Copy link is right-aligned in the view bar: view state in words, then the
  link, then Detach ↗.

- [x] *As a reader I choose which local model explains a record.* The ✦ badge
  is the control, in both the offer and a result: it lists the generation models
  Ollama has installed (`Explain.models/0`; embedding models filtered out by a
  stated heuristic), and the choice writes the next explanation. Per visit, not in
  the URL — it is an instrument the reader brings, not a property of the view.
  The explanation cache is now keyed by model, so one model's words are never
  served as another's; switching clears what the previous one wrote. —
  `explain_test.exs`, `atlas_explain_test.exs`
- [x] *As a reader, a person reads as a person.* First kind-specific entity
  display: `AtlasComponents.person_card/1` over `Atlas.Profile.person/2`, in the
  reader column when the focused entity's kind is `person`. Works from a name
  alone (initials, what they wrote, when first seen, "not registered") and fills
  in from schema.org `Person` properties on a registration (`jobTitle`,
  `affiliation`, `description`, `url`, `image`, `sameAs`), which `Topology` now
  keeps as the entity's `attrs`. Non-http(s) links are dropped. **Nothing yet
  registers a person with those properties** — that is the enrichment write in
  `docs/VIEWS.md`. — `atlas_profile_test.exs`, `atlas_components_test.exs`,
  `atlas_person_card_test.exs`

- [x] Fixed: focusing an entity looked like it did nothing to the sticky
  timeline. The server was already re-marking the dots and refocusing the strip,
  but nothing on the band SAID an entity was the filter, and filtered-out dots
  were too close to inked ones (the busiest entity spans the whole record, so
  nothing moved either). Now the timeline header carries the entity chip
  (`#atlas-timeline-entity`: name, "N of M", ✕), and filtered-out dots are
  smaller and fainter on both the range bar and the three.js strip. —
  `atlas_view_state_test.exs`
- [x] The view pane's note ("The timeline and filters are in another tab…") is a
  dark banner fixed ABOVE the site nav, with Reattach / Open that tab again in
  it. The nav is in the root layout, outside the LiveView, so the banner is
  `position: fixed` and `body:has(#atlas-pane-banner)` pads the page by its
  height. The timeline pane's note stays in the view bar (that pane has no nav).
  Shaped after Tailwind UI's dark banner (centred message, hairline, action at
  the right); its ✕ became **Reattach ✕**, since hiding the message alone would
  leave the controls away with no way back.
  Both tabs of a pair now have one (`AtlasComponents.pane_banner/1`): **dark**
  for the view pane, **indigo** for the detached timeline (in flow — no nav
  there), so the two tabs can be told apart at a glance. The timeline's action
  is "Show the whole page here →".
  — `atlas_view_sync_test.exs`

- [x] Masthead: the nav (atlas, sign in) sits beside the brand on the left. On
  `/atlas` the view bar (view state, **Copy link**, Detach ↗) is lifted into the
  same row, right-aligned — by CSS position, because the masthead is in the root
  layout and a LiveView `portal` would put it beyond `element/2` in tests. Below
  48rem, and in the timeline pane (no masthead), it is an ordinary bar again.
- [x] The detached timeline has a consistent browser target: a window named
  `atlas-timeline-<view token>`, so Detach and "Open that tab again" reuse one
  tab per view instead of opening a new one each click. —
  `atlas_view_sync_test.exs`

- [x] **daisyUI removed.** It was a mix dep that `app.css` never loaded (no
  `@plugin`; zero `.btn` / `.alert` / `.toast` rules in the built CSS), so its
  class names in the generated components, layouts and auth pages did nothing.
  Dep dropped from `mix.exs` / `mix.lock`; inert classes replaced with the
  stylesheet's own `.flash`, plain utilities, and a real error colour. Removing
  it exposed what the names were hiding, now fixed: **text fields had no border
  at all** (Tailwind's reset strips it; `.input` never restored it — the log-in
  page's fields were invisible, and the annotation form's too), the flash close
  button was an empty box, and the flash rendered *below* the page. Fields get a
  plain base-layer rule; flash renders above the content. Checked by rendering
  `/users/log-in` with the built CSS.

- [x] *The record in column 2 reads in four parts, each distinct on purpose.*
  **1. What it is** — a boxed identity block: kind + typed `event_type`
  segments, whether it is an event (verb) or an entity (noun, with its
  schema.org type), and the **event id**, moved up from the bottom. It reifies
  the object: structured, schema-adhering activity, and it tells the reader what
  the item is before any prose. **2. What it says** — the title and body, which
  is conventionally a post. **3. About this record** — metadata under its own
  heading, beginning at truth state (then the two clocks, source, stream, actor,
  affects), then relationships, annotations and Annotate. **4. What it stands
  on** — provenance, last, as a footing under a heavy rule: foundational.
  — `atlas_explain_test.exs` ("the record reads in four parts")
- [x] Intelligence is available, and says so at the top: a purple **✦** beside
  the record's ✕ opens the explain panel as a floating card over the record
  (`toggle_explain_panel`, `@explain_open?` — not URL state). It stays open from
  one record to the next. The panel itself is unchanged (button, model badge and
  picker, skeleton, caveat). — `atlas_explain_test.exs`

- [x] *"Stream · posts:afomi · seq 4" meant nothing to a reader.* The field is
  now **Feed**: the series a source published the record in (an account's posts,
  an RSS feed's items, a chain's transactions). It says the feed's name in words
  ("afomi's posts", "Annotations on “…”"), the record's place ("4 of 6 in this
  feed", counted over the whole record — filters do not shorten a feed), and
  **← earlier in feed / later in feed →** to walk it. The raw `stream_id · seq`
  stays, small and monospace, with a tooltip on what the ordering key is (block
  height + tx index on a chain; item position in RSS). `stream_id` keeps its
  name in the envelope (`STANDARDS.md`); only the label changed. Glossary entry
  rewritten. `AtlasLive.stream_context/2`. — `atlas_record_test.exs`
- [x] A note's id names the thing, not the act: `note:<author>:<date>:<8-hex
  content fingerprint>`, replacing `post:<n>` — "post" read as a verb (the verb
  is the event type, `atlas.post.added`) and `n` was the Feed's running counter,
  a fact about one process's memory. Order within the feed stays `sequence`'s
  job. Rows already persisted as `post:<n>` are untouched (the log is
  insert-only; nothing keys on the prefix). — `atlas_post_test.exs`
- [x] Column 2's ✕ has a line of its own above the record (light grey on hover,
  not the modal's black); the purple ✦ floats in the identity block's top right,
  and its panel opens under it; "something happened / was named" is a tooltip on
  the one word **Event** / **Entity**.

- [x] Column 1 scrolls on its own (`#atlas-list`: sticky under the controls,
  viewport-tall, `overflow-y: auto`, same terms as the canvas column), so
  scrolling the activity list does not carry the record and the scene away. Day
  headings stick to the list's own top. Only on wide, tall viewports — stacked
  layouts scroll as one page. — `atlas_layout_test.exs`

- [x] *As a reader I can see, on the list, which filters produced it.* Read-only
  strip above the Activity heading (`AtlasComponents.applied_filters/1` over
  `AtlasLive.applied_filters/1`): range (or "Outside"), sources, truth, speech,
  entity — each with what it is set to — then "N of the whole record". Says
  `none` when nothing is applied. No controls in it, on purpose: each filter is
  set where it is drawn. Only what changes which events are LISTED counts;
  "connected only" and folded days do not. — `atlas_view_state_test.exs`
- [x] *Entity focus is one filter among the rest, and closes like a record.* One
  chip component (`filter_chip/1`) draws every applied filter: with a ✕ on the
  timeline (the control), read-only in the strip. The entity-only chip with its
  own ✕ above Activity is gone; the entity in the reader column now has the same
  ✕-on-its-own-line close as a selected record (`#atlas-entity-context-close`),
  which is also the way out in `?pane=view`, where the controls band is absent.
  `record_total` added: `all_events` is already source-filtered, so it cannot be
  the "of N" for a strip that reports the source filter. — `atlas_view_state_test.exs`

- [x] *An entity is drawn as its kind, in every view.* `AtlasComponents.entity_icon/1`
  (heroicons `user` and `map-pin`, inline — the heroicons plugin is still not
  loaded): beside the name on record chips, the actor, the entity list, the entity
  heading, the person card, and every entity filter chip; and **in the Spacetime
  scene**, where a person or a place is an icon sprite instead of an octahedron —
  a pin stands on its place by its tip, and is kept above the ground tiles
  (`renderOrder`; tiles use their zoom level, which painted over the first
  attempt). One icon set: the server sends the paths to the scene and to the
  unmounted Leaflet map. Checked on the running app in the Map layout.
- [x] *Focused and affected mean the same thing in every view.* FOCUSED (the entity
  open in the reader) is amber; AFFECTED by the open record is blue, filled,
  larger. Tokens `--focus` / `--affected`. The scene now receives `affected` too.
  Before, the unmounted map used grey for affected and blue for focused, so blue
  meant two things.
- [x] *Filtering does not move points in the Spacetime scene.* The scene's time axis
  is ruled by the whole record's first and last event (`Scene.build/4`
  `:time_domain`), the same ends as the sticky timeline strip, instead of
  re-stretching to whatever is in view. — `atlas_scene_test.exs` (unit + live)
- [x] **Global element rules moved into `@layer base`** (`h1`, `h2`, `p`, `a`,
  `small`, `hr`, `button`). Unlayered, they beat every Tailwind utility, which is
  why a pasted Tailwind component never looked right (the pane banner: `m-0` lost
  to the `p` margin, `flex p-3` lost to `button`) and why four earlier fixes each
  needed a bespoke override. Measured on `/atlas` first: 22 of 636 elements
  changed, all of them the markup's own classes finally applying — including the
  entity list's selected highlight, which had been suppressed.

- [x] *As someone with something to log, I write one line and it becomes an
  activity.* `/atlas/log`, phone-first, linked from the site nav.
  `Atlas.Capture` parses **who · did what · to what · when** from a line (verb
  from the front, time from the end, things between — `at` a place, `with` a
  person, `and` carries on); the parse is shown back as chips BEFORE anything is
  written. A thing the record knows is linked to — by label, ref, or the ref's
  name, so a line can never re-mint an existing ref and relabel it — and a new
  one is registered first (a noun event, then the verb). Times resolve on the
  writer's clock (`tz_offset` connect param). Below the line: what you have
  logged and what it adds up to. **Prototype: public feed, typed author,
  `reported`.** A signed-in GitHub login is already the default author. —
  `atlas_capture_test.exs`, `atlas_log_live_test.exs`
- [x] *An event is already the shape of a transaction.* `Atlas.MAP`: an event as
  MAP key-values in an `OP_RETURN` (`app`, `type: log_v1`, then sorted keys:
  `actor`, `data_hash`, `id`, `object`, `timestamp`, `truth`, `verb`) — qart's
  encoding rules and the Yours Wallet provider's `MAP` type and `sendBsv`
  `data: string[]`, which agree. Refs, a time and a hash; never prose. Pure;
  writes to no chain. The capture page shows it per line. —
  `atlas_map_encoding_test.exs`
- [x] **A malformed append can no longer take the feed down.** A `sequence` past
  int4 raised `DBConnection.EncodeError` inside the Feed process and crashed it
  (found by doing exactly that). `Event.new/1` now refuses such a sequence, and
  `Feed.persist/1` rescues the encode error as a refused event. — `atlas_event_test.exs`

- [x] *The Spacetime Timeline layout is a strip, the width of its window.* Time ran
  -1..1 like every axis, so the layout was as tall as wide and its axis crossed
  under half of a 16:10 stage. `atlas_scene.js` now stretches time to the
  window's proportions (`fitStrip` / `timeZ`: points, ruled axis, frame and pan
  limit all go through it), stands the camera where the content's height just
  fits, and refits on resize. Margins keep end labels and the lowest entity
  inside. Checked on the running app; no automated test (WebGL).

- [x] *The Spacetime panel's layouts are tabs beside its title.* Right-aligned on
  the "Spacetime · N events · N entities" row, each as wide as its word, the
  active one underlined on the row's rule — not a bar across the full width.
  Panel variant only (the sticky strip keeps its own); still a radio group to a
  keyboard. CSS only. Checked on the running app.

- [x] *A relationship on a record is an activity row, and the whole row opens it.*
  `AtlasComponents.relationship_row/1`, built in the activity item's own classes:
  date and truth badge, the claim where a title would be (the verb lighter),
  the source underneath, same bar / hover / selected. The small "open" link is
  gone. The open record's own relationship is the selected state and not a
  button; no "this record" label. Checked on the running app (row and activity
  item measure identical). — `atlas_record_test.exs`

- [x] *Written things share one icon.* `document` and `plan` entities draw the
  same `document-text` icon as `policy` (one `@written` path in
  `AtlasComponents`); `data-kind` still carries the real kind, and the word beside
  the icon says which. `goal`, `money` and `note` still have none. Checked on the
  running app, in the entity list and the scene's icon set. — `atlas_components_test.exs`

- [x] *The canvas panel is titled "Projection".* What the panel is, is a choice of
  three axes onto which typed data is laid — physical (longitude, latitude, time)
  or projective (a semantic axis, a graph layout) — and "Spacetime" named one such
  choice. It is still the name of that tab (the lng · lat · time preset). Title,
  its explanatory `title=` and the stage's label only; component, ids, CSS and
  `Atlas.Scene` keep their names. Naming note: `Atlas.Projections` are read models
  of the log, this is a projection onto axes — both senses are the mathematical
  one, and the unmounted `projection_nav/1` is the old read-model switch.
- [x] *The applied-filters row carries no "none" and no "N of M".* With nothing
  applied it is its label and the view's link alone; the count is the timeline's
  readout, which is always on screen. `record_total` removed with it. —
  `atlas_view_state_test.exs`, `atlas_filter_dismiss_test.exs`

- [x] *As a reader I say what KIND of thing I have to say, on the record.* Kind
  badges (observation · question · correction · source) under "Annotate this
  record"; each opens the one composer already set to that kind. The same badges
  replace the form's Kind select, and the prompt over the note says what a good
  note of that kind contains (`kind_says/1`, `kind_prompt/1`). — `atlas_post_test.exs`
- [x] *The note is the form.* It leads, is the largest field, and takes the cursor.
  **Who is writing is who is signed in**: the GitHub handle, shown and not typed,
  and enforced on the server whatever the form sends. Signed out, a name is still
  typed and signing in is offered. (A public key as the author waits on a wallet;
  see "Sign-in for capture" below.) — `atlas_post_test.exs`
- [x] *A writer types prose; its objects are typed on their behalf.*
  `Atlas.Extract` (`extract/v1`) reads emails, telephone numbers, URLs, street
  addresses, entities the record already has, and — as a marked guess — names,
  out of a note. Shown under the note as chips BEFORE it is recorded; recorded as
  `payload["mentions"]` beside `mentions_rule`, each with the schema.org property
  it fills. A note becomes ABOUT every entity it names. Contact details are
  flagged `personal` and the form warns that the record is public. **Rules, not a
  model**: deterministic and versioned, so it may enter the stream where an LLM's
  reading may not; computed on the server from the text, never taken from the
  browser. — `atlas_extract_test.exs`, `atlas_post_test.exs`

### Next
- [ ] **Turn a mention into an entity.** `Extract` finds a name or an address; it
  does not yet REGISTER one. Next: a chip offers "add as person / place", which
  appends the registration (the enrichment write in `docs/VIEWS.md`), and a street
  address can be geocoded into a `geo` — behind an optional backend, like
  embeddings. Until then a name is a string in a payload, not a node in the graph.
- [ ] **Sign-in for capture, then a personal log.** Next after the capture
  prototype (decided 2026-09-20: capture page, then sign-in). A log scoped to
  its owner (`USER_SCOPING.md`; `Timelog` is the reference shape), read through
  the same Atlas views; publishing to the public record a separate act; a
  signed-in self-log can be `observed`. Then the actor becomes an identity
  PUBKEY (Yours: `identityPubKey`) and a `signature` field joins the MAP pairs.
- [ ] **Heroicons draw nothing.** Same cause as daisyUI: `app.css` has no
  `@plugin "../vendor/heroicons"`, so every `<.icon name="hero-…">` is an empty
  span (`assets/vendor/heroicons.js` and the `heroicons` dep are present and
  unused). Either load the plugin or replace the few icons with characters and
  drop the dep. Found 2026-09-20; the flash's close icon is already a "✕".

- [ ] **Author semantic axes from `/atlas`.** *As a reader I add an axis: a name,
  two poles, a few example phrases for each.* The dropdowns already list every
  axis in `semantic_axes`; today those are the four written for municipal code
  (Explicitness, Permissiveness, Substance, Verbosity), so Atlas wants its own —
  e.g. Local ↔ Regional, Plan ↔ Built, Cost ↔ Benefit, the old placeholders made
  real. Needs: a form (`Semantic.create_axis/1` + `compute_axis_vector/1`, which
  needs the embedding backend), a quality readout (`pole_separation` is already
  computed), and a decision on ownership — the table is global today
  (`USER_SCOPING.md`), so gate authoring to signed-in users at least.

- [ ] **One set of timeline dots, not two.** The range bar draws every activity
  as an HTML dot (ordinal: event 1, 2, 3…) and the strip under it draws every
  activity again in three.js (real time). Recommendation, 2026-09-20: keep the
  three.js strip as the ONE drawing and move the range handles onto it — real
  `<input type="range">`s laid over the canvas, so keyboard and screen-reader
  behaviour stay native — which means the range becomes time-based (the open
  "time-based range bar" item below). The HTML dots and the `?band=dom` marks
  then become the no-WebGL fallback, drawn from the same payload. Needs a
  decision because `from` / `to` change meaning in shared URLs.
- [ ] **Decide what the rest of the topo data layer is for.** `Semantic`'s AXES
  now have a reader (the Graph, via `Atlas.Semantics`). Still without one:
  `Spaces`, node embeddings and scores, topic models, `MuniCodes`, the Oban
  embedding queue and the demo seed. Keep what Atlas can use, drop the rest.
- [ ] **A sources / settings page.** *As a reader I can see and connect my
  sources.* Starts with `feed_status/1` (what is connected, what is persisted),
  then the list of sources with their coverage, then adding one — which is where
  "expanding coverage" (Considering) lands. Ryan: "a user is going to have to be
  able to source items easily."

- [ ] **Posts: what is still open.** (The two forms became one — see Done.)
  Replies to posts (threads — `annotatable?/1` refuses them today), `author`
  from the signed-in GitHub user instead of a text field (`EVENT_UI.md`), and
  per-kind fields for annotations (`EVENT_UI.md`'s "the kind is a contract").
- [ ] **Show the prompt; log the call.** The explain card makes a reader wonder
  what the model was asked. `Explain.prompt_for/3` is already public and pure,
  so a "what was asked" disclosure is a render of it — no model needed. Logging
  (prompt, model, options, latency, response, cache hit) must stay OUT of the
  event stream (machine output never enters it): a separate table or log only.
- [ ] **Feeds as real sources, and as a filter.** Today's feeds are fixture
  series, posts per author, and annotations per record. The expectation is that
  a feed is a BSV stream or an RSS feed in a structured format: a
  `Atlas.Source` adapter per kind, `sequence` = `[block_height, tx_index]` or
  item position, and the Feed field linking out to the feed itself (the RSS url,
  the chain address). Then `stream=` as a URL filter, drawn like "By source".
- [ ] **Filter by event type?** The Events & entities bar names the verbs but a
  verb is only said, not clickable: there is no `type=` filter. If it earns one,
  it follows the checklist contract and goes in the URL like the rest.
- [ ] **Lag as a view.** The occurred→observed gap is now shown per record; the
  expectation is that it trends toward zero as sources report in real time.
  A lag view over the whole record (`docs/VIEWS.md` already lists it) would show
  that trend, and how many events are `only observed`.
- [ ] **Saved views / snapshots.** *As a reader I save (or have auto-saved) a
  view and share it as a snapshot in time that is explicit about its
  perspective, its filters and its parameters.* What exists: the URL already
  carries every filter and view choice (`sources`, `truth`, `entity`, `from`,
  `to`, `out`, `event`, `scene`, `lanes`, `band`), and "Share this view"
  describes it in words. What a snapshot adds:
  1. **Perspective** — the scene's layout is in the URL, but the camera (orbit,
     zoom) is not. A snapshot needs it, or it is not the view that was saved.
  2. **A point in the record** — the log is append-only, so pin the snapshot to
     the max `event_id`/`sequence` at save time ("as of event N"); replaying to
     that epoch reproduces it exactly even as the record grows. Without this a
     saved view silently changes. (Same epoch idea as the entity cache in
     `ARCHITECTURE.md`.)
  3. **A name and an owner** — user-owned, so it follows `USER_SCOPING.md`
     (scope as first argument, no `nil` clause) like `Timelog`. Auto-save is
     "latest unnamed snapshot per user".
  4. **Its own explicitness** — a saved view shows its axes legend, its active
     filters and its as-of point before anything else: a snapshot is a claim
     about how the record looked from somewhere, and should read as one.
  Open: is a snapshot an *event* (`atlas.view.saved`, so sharing one is itself
  on the record) or private state? Decide before building.

- [ ] *As a reader I see the base before the filters.* Audit against the
  principle: total events + date selector read as the base, then each filter in
  the order it restricts. Today the total only appears in the timeline readout
  and the header's "Events:" count.
- [ ] Convert the template's remaining inherited Tailwind utility classes to the
  Swiss system in `app.css` (the note at the top of `atlas_live.html.heex`).

### Considering

- **Capture gets its own UI: log `entity verb entity @ time`.** Idea, 2026-09-20.
  The premise, after unwriter's Planaria: small public facts of one shape —
  *who · did what · to what · when* — accumulate into something worth querying.
  That shape is already the envelope (`actor`, `event_type`, `object`,
  `occurred_at` — an AS2 Activity), but nothing on the page WRITES it: "New
  activity" collects an author and prose, so a post names no verb and only
  touches an entity if one happened to be in focus. Proposal: a capture line, on
  a page of its own (`/atlas/log`, phone-first). `met Jane Doe at Carroll Way
  yesterday 3pm` parses to chips — actor (me) · verb · objects · time — shown
  back for correction BEFORE it is appended, which is `Timelog.Line`'s rule
  ("the line is the interface"; its parser and verb table are the starting
  point). Objects autocomplete against entities already in the record, so a log
  links up instead of forking `person:jane` from `person:jane-doe`; naming a new
  thing appends its noun event first. Verbs take AS2's word where one is exact
  (`Read`, `Join`, `Arrive`, `Travel`, `Follow`…) and ours where not
  (`STANDARDS.md`'s rule). Under the line: what you have logged, and what it has
  added up to. **The decision it turns on: personal or public.** `Timelog`'s
  moduledoc is firm that private, per-user, geo-stamped data must not ride the
  global feed. So: a personal stream, scoped to the signed-in user and read
  through the SAME Atlas views, with publishing to the public record a separate,
  deliberate act — which needs sign-in (`USER_SCOPING.md`) first.

- **Expanding coverage: datasets from the past and the future.** Ryan's idea,
  2026-09-20: let a reader widen the slice by bringing in other datasets —
  historical activities, sports results, predictions, even science-fiction
  references — so the band reaches further back and ahead. What is already in
  place: a source is an adapter (`Atlas.Source`), adding one needs no UI change,
  every source gets its own "By source" row, and the band's end caps are where
  "add earlier / later" belongs. What has to be decided first:
  1. **Truth states do not cover these.** A forecast is not `proposed` (nobody
     applied for it) and a novel's 2049 is not `reported`. Likely new states on
     the epistemic axis — `predicted`, `imagined` — kept visibly apart from the
     civic lifecycle, or a separate "register" field (record / history /
     forecast / fiction) beside `truth_state`. Fiction beside sourced civic
     claims must never be mistakable for them (`ARCHITECTURE.md`, truth states).
  2. **Sources should declare their coverage** (`covers: from..to`, and a
     register), so the end caps can say "2 sources reach earlier" and the reader
     chooses, rather than the band silently growing.
  3. **Per-user or shared?** A reader's added datasets are theirs (like
     `Atlas.Coherence`'s chains): user-scoped, overlaid, not installed for all.
  4. **"now" becomes a real boundary**: right of it only `predicted`,
     `proposed`, scheduled and `imagined` things can sit.
- **Map tiles: next steps.** Tiles are raster OSM, dimmed for the dark stage.
  Vector shapes on the same plane (a city boundary, parcels as GeoJSON →
  `THREE.Shape`) now only need the same Mercator transform (`Scene.mercator/2`).
  Self-hosting or a tile provider if usage grows past OSM's policy.

- **Zoom and pan on the strip.** The sticky timeline is now an orthographic
  three.js strip, so zooming the time axis is a camera change rather than a
  re-layout. It must carry the DOM date axis with it (ticks are server-rendered
  for the whole span today).
- **Refresh the `/atlas` wireframe frame** in the `.tldr`: By source moved left,
  lanes gained checkboxes, the calendar band became the Spacetime strip, the
  projection row is gone, and the canvas column gained the Spacetime panel.

- **Folding the Map and Graph panels into Spacetime.** The scene's `map` layout
  is a graticule with pins, not a map: no basemap. Next step if it earns its
  place: load real shapes onto the ground slice (a city boundary / parcels as
  GeoJSON → `THREE.Shape`, or tile textures), then decide whether the Leaflet
  panel is still needed. The `space` layout is still `Scatter`'s placeholder
  hash; real axes (embeddings → PCA, or semantic axes as in `/topo`) would make
  it mean something. If Spacetime holds up, the old Space panel is the first to
  unmount (it is a strict subset).

- **The timeline as a three.js scene.** Idea, 2026-09-20. *A first stage now
  exists to build on: the "Space" panel (`Atlas.Scatter` + `atlas_scatter.js`),
  on placeholder positions. Giving it a time axis is one candidate for making
  those positions real; embeddings → `Semantic.Topics.pca_3d/1` is another.* The premise: **every
  activity and every entity is a visualized dot — a manifestation of activity
  in 3D spacetime.** Time is one axis; the other two are free to carry place
  (entities with `geo`), source, or relationship. An event is a point in time;
  an entity is what persists between the events that touch it, so it may read
  as a line or a trail rather than a single dot. The map, the graph and the
  timeline are then three views of one scene rather than three panels.
  `three` is already a
  dependency (`/topo`), and `assets/js/three_stage.js` is a reusable stage. What
  it could buy: real zoom and pan on the time axis (the open question behind dot
  packing), per-source lanes as depth rather than stacked rows, and smooth
  transitions as filters restrict the set. What it must not lose: the filtering
  principle above (every restriction still visible), keyboard access and
  `aria-valuetext` on the range (today these come free from native inputs), and
  server-rendered state in the URL. Likely shape: the scene *draws* the base and
  the restrictions, while the controls that set them stay real DOM.
- **Split "truth state" into two things.** Idea, 2026-09-20. The six values mix
  two questions (`ARCHITECTURE.md`, "Truth states"), which is why the filter is
  hard to use on purpose. **Basis** — how we know: `observed` / `reported`, plus
  `superseded` as "corrected". A property of each *event*; stays on the badge.
  **Stage** — where the thing stands: `proposed` → `adopted` → `delivered`. A
  property of the *noun*, and the fixture already says so: "proposed" sits on
  three `civic.entity.registered` events (a proposed park), and "adopted" on
  events whose `event_type` already names the act (`civic.contract.approved`).
  So stage becomes a rollup over the activities that happened to an entity
  (AS2 `Offer` → `Accept` / `Reject`; schema.org `actionStatus`), shown on the
  entity — object card, graph node, a dashed pin for a proposed park — not
  repeated on every row. Reader questions this would serve: *what is decided vs
  only proposed?* (stage), *what is first-hand vs hearsay?* (basis), *what needs
  attention?* (unresolved). UI wording to test: "Basis" or "How we know", and
  "Stage", instead of "Truth state". Keep the legend modal; split it in two.
- **A time-based range bar.** The bar is ordinal today (handles snap to event 1,
  2, 3…), so its dots align with its handles but not with the calendar band
  below. Going time-based would unify the two axes and make day-packing and zoom
  natural; it changes what `from` / `to` mean in shared URLs. A three.js
  timeline would force this decision.
- Range-bar dots are display-only because the Position scrubber used to be the
  selector. With it unmounted, dots could select.

## Decisions

- **2026-09-20 — "Truth state" is the filter; "Provenance" is the record's
  source trail.** The projection used one word for both. How settled a claim is
  and where a record came from are different questions.
- **2026-09-20 — Range filter applies before the others.** Its bounds are
  indexes into the source-filtered stream, so truth and entity filters narrow
  its result rather than renumbering what the handles point at.
- **2026-09-20 — The activity density toggle is removed**, not registered: it
  was a setting, not a component. It cost a URL param, an assign, a handler, two
  CSS rules and five tests to hide one line per row, and the source and truth
  filters now do the real work of making the list manageable. Old `?dense=1`
  links still load.
