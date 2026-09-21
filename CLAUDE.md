# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Start with `PLAN.md` — it is the entrypoint: the active thread (`## Now`), the task list, and the UI principles (notably: filtering is 100% visualized).

Framework conventions (Phoenix 1.8, LiveView, HEEx, Ecto, auth routing, test style) live in `AGENTS.md` — follow it; this file does not repeat it.

## Commands

```bash
mix setup                          # deps, create+migrate DB, install+build assets
mix test                           # creates/migrates the test DB first (alias)
mix test test/indivisual/atlas_timeline_test.exs        # one file
mix test test/indivisual/atlas_timeline_test.exs:42     # one test, by line
mix test --failed                  # re-run only previous failures
mix precommit                      # compile --warnings-as-errors, deps.unlock --unused, format, test
mix credo                          # lint (default config; no .credo.exs)
mix ecto.reset                     # drop + setup
```

- `mix precommit` runs in the `:test` env (`preferred_envs` in `mix.exs`). Run it when a change is finished.
- Postgres is expected at `localhost` with `postgres`/`postgres`.
- Tests need no network: `config/test.exs` swaps in `Embeddings.Fake`, `Explain.Fake`, `Swoosh.Adapters.Test`, inline Oban, a deterministic Cloak key, and dummy GitHub OAuth credentials (Ueberauth raises a `CaseClauseError` if those are nil).
- Dev uses a local Ollama at `localhost:11434` for embeddings (`qwen3-embedding:8b`) and explanations (`qwen3:8b`). Both are optional — see "Optional backends" below.
- Deploy: push to `main` or `develop` builds a Docker image to ECR and does a rolling restart (`.github/workflows/`). `/healthz` is the ALB health check and must stay out of `force_ssl`'s redirect.

## What the app is

One feature (see `router.ex`), plus auth, an about page (`/atlas/about`), and two contexts with no UI:

| Route | What | Rendering |
|---|---|---|
| `/atlas` | Live read interface over an append-only civic event stream | LiveView, server-rendered SVG |

It is currently **public and unauthenticated**, and everything behind it is global (no owner column). `USER_SCOPING.md` is the design for changing that.

## Atlas: events → projections → LiveView

`Indivisual.Atlas` is the facade the web layer calls. The pipeline:

```
Source adapters (Atlas.Source behaviour: info/0, sources/0, events/0)
   Sources.CivicFixture  ← priv/atlas/civic_fixture.json
   Sources.Annotations   ← user-written annotations
        ↓ Source.load/1 normalises into Atlas.Event envelopes, keeps `raw`, stamps a content hash
Atlas.Feed (GenServer)  holds an Atlas.Log in memory; broadcasts appends on PubSub "atlas:feed"
        ↓ runtime appends are written to Atlas.Store (atlas_events table) BEFORE entering the stream
Atlas.Projections.materialize/3  — pure function of (events, opts)
   activity | entity | topology | provenance      (Atlas.Topology derives entities + relationships)
        ↓
IndivisualWeb.AtlasLive
```

Invariants to preserve — these are load-bearing, not style:

- **The event log is insert-only.** Never update or delete an `atlas_events` row. A wrong fact is corrected by a later event (`superseded`), not an edit. Every user write appends an event; no form mutates a record (`EVENT_UI.md`).
- **Only runtime appends are persisted.** Adapter-seeded events are rebuilt from their adapter on boot, so adapters + store always reproduce the stream. If the store is unreachable the Feed still serves adapter events but refuses appends.
- **Projections are pure and disposable.** Same events + options (`:sources`, `:until`, `:entity`) → same read model. A lens changes what is read, never what was recorded. They are recomputed on every `Atlas.read/2` — there is no cache yet, and `ARCHITECTURE.md` specifies the order to build one (typed entity kinds → derived-value envelope → cache keyed by event epoch).
- **Truth state comes from intent, never defaulted.** `observed` means first-hand; an annotation's truth state is derived from its kind. The civic fixture emits `observed`, `reported`, `proposed`, and `adopted`; `delivered` and `superseded` are declared but have no producer.
- **Relationships carry the asserting event's source and truth state**, so an inferred link is never presented as a source fact. A relationship is shaped `subject` / `relationship` / `object` (an ActivityStreams `Relationship`), and `Event.new/1` refuses any other shape rather than dropping the link. Entity "kind" is just the ref prefix (`place:vacaville` → `place`) — a naming convention, not a validated type.
- **Standard names are used only where exact.** `event.actor` and `event.object` are the ActivityStreams properties; the envelope fields AS2 has no word for (`observed_at`, `truth_state`, `sequence`, …) keep their own names. Check `STANDARDS.md` before naming a new field.
- **Machine output never enters the stream.** `Indivisual.Explain` paraphrases are ephemeral (cached in `Explain.Cache`, never stored as events). `Atlas.Glossary` definitions are static on purpose — fixed vocabulary gets a written definition, not a generated one.

`AtlasLive` has one URL and no mode switch: the four `Atlas.Projections` are each always on screen where they belong (activity is the list, topology the graph, entity context the reader under a focus, provenance the truth-state filter). It keeps `event`, `entity`, `sources`, `truth`, the range, and the graph's `connected` toggle in the URL so any view is shareable and reproducible; live appends refresh the read model without resetting the selection. The view-model helpers are separate pure modules, each with its own test file: `Atlas.Timeline` (time-honest x-axis, simultaneous events stack into capped lanes, overflow is reported), `Atlas.Geo` (validates coordinates; returns unlocated entities separately rather than inventing positions), `Atlas.Coherence` (computed and tested but **deliberately not mounted** — see its moduledoc before wiring it in).

A recurring principle across these modules: when data is missing or doesn't fit, **report it** (unlocated count, lane overflow, `persistence: {:error, _}`) rather than silently dropping or fabricating.

## Spaces, nodes, semantic axes (no UI)

The `/topo` page — a three.js scatter of nodes on semantic axes — was removed on 2026-09-20 (route, controller action, template, `assets/js/topo.js`). The data layer it read is still here. One part has a reader again: `Indivisual.Semantic`'s **axes** are the dimensions behind the Spacetime scene's Graph mode — `Indivisual.Atlas.Semantics` embeds each event's text and scores it against them (derived, cached in ETS, never an event; see `PLAN.md`). The rest (spaces, node embeddings and scores, topic models, `MuniCodes`) has no UI. `assets/js/three_stage.js`, which topo shared, now serves `/atlas` only.

- `Indivisual.Spaces` owns `Space` → `Visual.Node` / `Visual.Link` (table `edges`); `Indivisual.Projections` is *saved views of a Space* — unrelated to `Atlas.Projections` despite the name.
- `Indivisual.Semantic`: an axis is two poles anchored by example phrases; the axis vector is the normalised difference of pole centroids. Nodes are embedded (`Workers.EmbedNodeWorker`, Oban queue `embeddings`), then projected onto axes into `node_axis_scores`. Scores and embeddings are **keyed by embedding model** — after switching models, recompute axes and rescore.
- `Indivisual.MuniCodes` imports municipal-code chapters as nodes into the `muni-codes` space Its moduledoc references `mix indivisual.import_muni_codes`, but no `lib/mix/` task exists in this repo.

## Optional backends

`Indivisual.Embeddings` and `Indivisual.Explain` share one pattern: a behaviour + configured adapter (`Ollama` / `Fake`), where adapters return `{:error, :unavailable}` instead of raising. The app must work fully with no backend; the UI simply doesn't offer the feature. Follow this pattern for any new external dependency.

## Auth, users, and scoping

- `phx.gen.auth` (controller-based, magic-link + password) plus **GitHub OAuth** via Ueberauth (`/auth/:provider`). `github_uid` is the identity key. The `repo` scope is intentional: `Indivisual.GitHub.put_files/4` commits N files as one commit (Git Data API) to a repo the user owns — GitHub is meant to be the system of record, the DB a working copy.
- `users.github_access_token` is Cloak-encrypted. `Indivisual.Vault` **must start before `Repo`** in the supervision tree. The token is in `:filter_parameters` because it once leaked into logs via a raised changeset — keep new credential fields filtered too.
- `Indivisual.Timelog` is the first user-owned data and the reference implementation of the scoping rule: every read takes an `Accounts.Scope` as its **first argument with no `nil` clause**, so a forgotten filter is an arity error, not a leak. It broadcasts on a per-user topic, deliberately not the global Atlas feed. It has no web UI yet. Apply the same shape when scoping `Spaces` (`USER_SCOPING.md`: ownership on `spaces.user_id`, `NULL` = global/demo).

## Design docs

`ARCHITECTURE.md` (events → entities → graph, build order, truth states, provenance depth), `EVENT_UI.md` (annotation kinds as contracts, flash as teaching surface), `USER_SCOPING.md` (ownership + GitHub marshalling), `docs/VIEWS.md` (the facet → derivation → view meta-model, and which views the data already supports), `STANDARDS.md` (which Atlas names are ActivityStreams / schema.org / PROV terms, which are deliberately not, and the constraints on serializing, federating, and anchoring). Each states its own built/not-built status at the top; when a doc and the code disagree, the code wins — fix the doc.

## Frontend notes

- Only the `app.js` / `app.css` bundles exist. The one npm dependency is `three` (`assets/package.json`), bundled by esbuild from `assets/node_modules` — `mix setup` does **not** install it; run `npm install --prefix assets` on a fresh checkout (the Dockerfile does this before `assets.deploy`). LiveView hooks are colocated hooks only (`hooks: {...colocatedHooks}`).
- **Unused UI is registered, not deleted.** Shared Atlas components live in `IndivisualWeb.AtlasComponents` (templates in `components/atlas_components/`). Its moduledoc holds the register of what is mounted and what is deliberately unmounted (the list is long now — read it there, not here), mirrored by `unmounted/0`, which tests check against the page. When you mount or unmount a component, update the register in the same change; keep the unmounted component's host events handled in `AtlasLive` so remounting is one tag.
- There is no component library. daisyUI was removed (2026-09-20): it was a dep the CSS never loaded, so its class names in the generated components did nothing. Components are hand-written — the project's own rules in `app.css`, plus Tailwind utilities (`AGENTS.md`).
