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
  | `accordion/1` | mounted | `/atlas` Timeline panel |
  | `range_dots/1` | mounted | `/atlas` range bar and its per-source lanes |
  | `source_nav/1` | **unmounted** 2026-09-20 | Replaced by the source checklist on the activity list. Kept: the only control that *describes* a source (publisher, status, adapter). |
  | `position_scrubber/1` | **unmounted** 2026-09-20 | Selecting an event is already done by the activity list, marks band and Prev / Next. Kept: the only drag-through-events control. |

  An unmounted component's host events stay handled in `IndivisualWeb.AtlasLive`
  (`toggle_source`, `clear_sources`, `scrub`, `toggle_scrubber`), and its CSS
  stays in `app.css`, so remounting is one tag.

  Related, outside this module: `Indivisual.Atlas.Coherence` is computed and
  tested but has no UI at all — see its moduledoc.
  """
  use Phoenix.Component

  embed_templates "atlas_components/*"

  @doc "Components that exist but are on no page. Mirrors the moduledoc register."
  def unmounted, do: [:source_nav, :position_scrubber]

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

  defp accordion_action(true, name), do: "Collapse #{String.downcase(name)}"
  defp accordion_action(false, name), do: "Expand #{String.downcase(name)}"
end
