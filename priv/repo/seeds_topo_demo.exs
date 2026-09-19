# Demo data for /topo.
#
#     mix run priv/repo/seeds_topo_demo.exs
#
# WHY THIS EXISTS: /topo renders nothing until it has records carrying scores
# on at least three COMPUTED semantic axes. Producing those for real means
# running an embedding model (Ollama) over source text and projecting onto
# axis vectors — which is not available in production and is slow locally.
#
# WHAT THIS DOES INSTEAD: writes the *output* of that pipeline directly —
# axes with vectors, nodes, and their scores — with geometry chosen so the
# plot is legible rather than a random cloud. Each city occupies a different
# region of the volume, so rotating it shows actual structure.
#
# This is DEMO data, not a fixture of reality: the scores are authored, not
# measured. It is idempotent (safe to re-run) and scoped to its own space
# slug so it can never collide with a real muni-codes import.

import Ecto.Query

alias Indivisual.Repo
alias Indivisual.Semantic.{Axis, NodeAxisScore}
alias Indivisual.Space
alias Indivisual.Visual.Node

space_slug = "topo-demo"
model = "demo"

# ── Space ───────────────────────────────────────────────────────────────────

space =
  case Repo.get_by(Space, slug: space_slug) do
    nil ->
      Repo.insert!(%Space{
        name: "Topo Demo",
        slug: space_slug,
        status: "published"
      })

    existing ->
      existing
  end

IO.puts("space: #{space.slug} (id=#{space.id})")

# ── Axes ────────────────────────────────────────────────────────────────────
# Names match PREFERRED_AXES in assets/js/topo.js, so the viewer maps them to
# X/Y/Z by default instead of picking arbitrarily. axis_vector must be non-nil:
# the controller only lists axes where it is set (computed_only: true).

axis_specs = [
  {"Permissiveness", "may", "must", [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]},
  {"Substance", "procedural", "substantive", [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]},
  {"Verbosity", "terse", "verbose", [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0]},
  {"Explicitness", "implied", "explicit", [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]}
]

axes =
  for {name, neg, pos, vector} <- axis_specs do
    attrs = %{
      positive_pole: pos,
      negative_pole: neg,
      axis_vector: vector,
      model: model,
      is_active: true,
      metadata: %{"source" => "topo-demo seed", "authored" => true}
    }

    case Repo.get_by(Axis, name: name) do
      nil ->
        Repo.insert!(struct(%Axis{name: name}, attrs))

      existing ->
        existing
        |> Ecto.Changeset.change(attrs)
        |> Repo.update!()
    end
  end

IO.puts("axes: #{Enum.map_join(axes, ", ", & &1.name)}")

# ── Records ─────────────────────────────────────────────────────────────────
# Two cities, each with a recognisable character, so the plot shows separation
# rather than noise. Scores are in [-1, 1] — the range a real cosine projection
# produces.
#
# {city, chapter, title, permissiveness, substance, verbosity, explicitness}

records = [
  {"vacaville", "8", "Noise regulation — residential hours", -0.70, 0.55, 0.20, 0.80},
  {"vacaville", "8", "Noise — construction exemptions", -0.40, 0.35, 0.55, 0.65},
  {"vacaville", "14", "Tree preservation — heritage oaks", -0.85, 0.75, 0.35, 0.70},
  {"vacaville", "14", "Tree removal permits", -0.55, 0.45, 0.60, 0.85},
  {"vacaville", "6", "Animal control — licensing", -0.60, 0.25, 0.15, 0.75},
  {"vacaville", "6", "Animal control — nuisance findings", -0.45, 0.40, 0.45, 0.50},
  {"vacaville", "2", "Council meeting procedure", 0.30, -0.80, 0.70, 0.40},
  {"vacaville", "2", "Committee appointments", 0.45, -0.65, 0.50, 0.30},
  {"vacaville", "16", "Sign ordinance — dimensions", -0.75, 0.30, 0.85, 0.90},
  {"vacaville", "16", "Sign ordinance — temporary signage", -0.35, 0.20, 0.65, 0.55},
  {"fairfield", "9", "Public nuisance — abatement", -0.65, 0.70, 0.40, 0.60},
  {"fairfield", "9", "Nuisance — cost recovery", -0.30, 0.50, 0.75, 0.45},
  {"fairfield", "12", "Streets — encroachment permits", -0.50, 0.60, 0.55, 0.80},
  {"fairfield", "12", "Sidewalk maintenance duty", -0.80, 0.65, 0.30, 0.70},
  {"fairfield", "3", "Revenue — business license tax", -0.25, 0.15, 0.90, 0.95},
  {"fairfield", "3", "Transient occupancy tax", -0.20, 0.10, 0.80, 0.90},
  {"fairfield", "2", "Administration — city manager", 0.55, -0.70, 0.45, 0.35},
  {"fairfield", "2", "Records retention", 0.40, -0.55, 0.35, 0.50},
  {"fairfield", "17", "Zoning — permitted uses", 0.15, 0.80, 0.95, 0.85},
  {"fairfield", "17", "Zoning — variances", 0.60, 0.55, 0.70, 0.40}
]

axis_by_name = Map.new(axes, &{&1.name, &1})

nodes =
  for {city, chapter, title, perm, subst, verb, expl} <- records do
    hash = :crypto.hash(:sha256, "#{space_slug}:#{city}:#{chapter}:#{title}") |> Base.encode16(case: :lower)

    metadata = %{
      "city" => city,
      "chapter" => chapter,
      "section_count" => 3 + :erlang.phash2({city, title}, 18),
      "earliest_year" => 1968 + :erlang.phash2({title, :early}, 40),
      "latest_year" => 2009 + :erlang.phash2({title, :late}, 17)
    }

    node =
      case Repo.get_by(Node, hash: hash) do
        nil ->
          Repo.insert!(%Node{
            name: title,
            description: "#{String.capitalize(city)} Municipal Code, chapter #{chapter}.",
            hash: hash,
            kind: "muni_section",
            space_id: space.id,
            metadata: metadata
          })

        existing ->
          existing
          |> Ecto.Changeset.change(%{metadata: metadata, space_id: space.id})
          |> Repo.update!()
      end

    scores = %{
      "Permissiveness" => perm,
      "Substance" => subst,
      "Verbosity" => verb,
      "Explicitness" => expl
    }

    # Upsert scores: delete-then-insert per node keeps this idempotent without
    # relying on a unique index that may not exist for [node, axis, model].
    Repo.delete_all(from(s in NodeAxisScore, where: s.node_id == ^node.id and s.model == ^model))

    for {axis_name, score} <- scores do
      axis = Map.fetch!(axis_by_name, axis_name)

      Repo.insert!(%NodeAxisScore{
        node_id: node.id,
        semantic_axis_id: axis.id,
        score: score,
        model: model
      })
    end

    node
  end

IO.puts("nodes: #{length(nodes)}")

# ── Explicit verification ───────────────────────────────────────────────────
# Assert the END STATE the page actually depends on, rather than trusting that
# the inserts above returned without raising.

space = Repo.get_by!(Space, slug: space_slug)
computed_axes = Repo.all(from a in Axis, where: not is_nil(a.axis_vector))
scored = Indivisual.Semantic.node_scores_for_space(space)
models = Indivisual.Semantic.score_models_for_space(space)

plottable = Enum.count(scored, fn {_id, by_model} -> map_size(Map.get(by_model, model, %{})) >= 3 end)

IO.puts("""

verification
  computed axes:      #{length(computed_axes)} (need >= 3)
  nodes with scores:  #{map_size(scored)}
  plottable (>=3):    #{plottable}
  models:             #{inspect(models)}
""")

cond do
  length(computed_axes) < 3 ->
    raise "topo needs at least 3 axes with a non-nil axis_vector; got #{length(computed_axes)}"

  plottable == 0 ->
    raise "no node has scores on 3+ axes — /topo would render its empty state"

  true ->
    IO.puts("OK — /topo/#{space_slug} has plottable data.")
end
