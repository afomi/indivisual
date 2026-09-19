defmodule Indivisual.MuniCodes do
  @moduledoc """
  Imports municipal-code chapters (from ogenda's provision trees) as Nodes —
  the TOPOLOGICAL_EMBEDDING_SPACES.md worked example, live.

  Granularity is one Node per **chapter** (~280 across two cities): legible on
  the canvas, cheap to embed, and comparable across cities. Each node carries:

    - `name` — chapter number + heading
    - `description` — heading, parent title, and all child section headings
      (this is what gets embedded)
    - `metadata` — `city`, `code_ref` (idempotency key), `chapter`, `title`,
      `section_count`, `earliest_year`, `latest_year`, `span_years` (from
      ordinance history notes)

  Data axes that work out of the box: `metadata.section_count`,
  `metadata.earliest_year`, `metadata.latest_year`, `metadata.span_years`
  (linear), `metadata.city` / `metadata.title` (ordinal). City filters via
  `filter_config` `metadata_city`. Semantic axes apply after embedding.

  Chapter rows come from `mix indivisual.import_muni_codes`, which reads
  ogenda's database directly.
  """

  alias Indivisual.Spaces

  @space_slug "muni-codes"
  @grid_cols 16
  @cell_w 170.0
  @cell_h 70.0

  def space_slug, do: @space_slug

  # City-hall coordinates for the /topo geographic layer — the "traditional
  # coordinates" hub each city's records fan out from.
  @city_coordinates %{
    "vacaville" => %{lat: 38.3566, lng: -121.9877},
    "fairfield" => %{lat: 38.2494, lng: -122.0400}
  }

  def city_coordinates, do: @city_coordinates

  def get_or_create_space do
    case Spaces.get_space_by_slug(@space_slug) do
      nil ->
        {:ok, space} = Spaces.create_space(%{name: "Municipal Codes", slug: @space_slug})
        space

      space ->
        space
    end
  end

  @doc """
  Upserts one Node per chapter row (idempotent on `metadata.code_ref`).

  A row: `%{city:, enum:, header:, parent_header:, section_headings: [..],
  changed_blobs: [..]}`.

  Returns `{:ok, %{created: n, updated: n}}`.
  """
  def import_chapters(space, rows) do
    existing_by_ref =
      space
      |> Spaces.list_nodes_for_space()
      |> Enum.filter(&(&1.metadata["code_ref"] != nil))
      |> Map.new(&{&1.metadata["code_ref"], &1})

    rows
    |> Enum.group_by(& &1.city)
    |> Enum.flat_map(fn {_city, city_rows} -> Enum.with_index(city_rows) end)
    |> Enum.reduce({:ok, %{created: 0, updated: 0}}, fn {row, index}, {:ok, acc} ->
      attrs = node_attrs(row, index)

      case Map.get(existing_by_ref, code_ref(row)) do
        nil ->
          {:ok, _} = Spaces.create_node(space, attrs)
          {:ok, %{acc | created: acc.created + 1}}

        node ->
          {:ok, _} = Spaces.update_node(node, Map.drop(attrs, ["x", "y"]))
          {:ok, %{acc | updated: acc.updated + 1}}
      end
    end)
  end

  @doc false
  def node_attrs(row, index) do
    {earliest, latest} = year_range(row.changed_blobs || [])
    headings = row.section_headings || []

    metadata =
      %{
        "code_ref" => code_ref(row),
        "city" => row.city,
        "chapter" => row.enum,
        "title" => row.parent_header,
        "heading" => row.header,
        "section_count" => length(headings),
        "earliest_year" => earliest,
        "latest_year" => latest,
        "span_years" => earliest && latest && latest - earliest
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %{
      "name" => display_name(row),
      "kind" => "muni_chapter",
      "x" => grid_x(row.city, index),
      "y" => grid_y(index),
      "description" => description(row, headings),
      "metadata" => metadata
    }
  end

  defp code_ref(row), do: "#{row.city} #{row.enum}"

  defp display_name(row) do
    "#{row.enum} #{truncate(titlecase(row.header || ""), 48)}"
  end

  # The city name is deliberately NOT in the description: it is identity, not
  # content, and putting it in the embedding text makes topic clusters
  # segregate by city token instead of by subject matter (FC2.21).
  defp description(row, headings) do
    [
      "#{row.header} (municipal code chapter #{row.enum})",
      row.parent_header,
      Enum.join(headings, ". ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
  end

  # Extract cited years from ordinance history notes like
  # "(Ord. 1042 § 1, 1979)" — a 4-digit number right after "Ord. " is an
  # ordinance number, not a year.
  @doc false
  def year_range(changed_blobs) do
    years =
      changed_blobs
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn blob ->
        Regex.scan(~r/(?<!Ord\. )\b((?:19|20)\d{2})\b/, blob, capture: :all_but_first)
      end)
      |> Enum.map(fn [y] -> String.to_integer(y) end)

    case years do
      [] -> {nil, nil}
      _ -> {Enum.min(years), Enum.max(years)}
    end
  end

  # Freeform starting layout: a grid per city, Fairfield offset to the right.
  defp grid_x("fairfield", index),
    do: 80.0 + @grid_cols * @cell_w + 200.0 + rem(index, @grid_cols) * @cell_w

  defp grid_x(_city, index), do: 80.0 + rem(index, @grid_cols) * @cell_w
  defp grid_y(index), do: 80.0 + div(index, @grid_cols) * @cell_h

  defp titlecase(header) do
    if header == String.upcase(header) do
      header
      |> String.downcase()
      |> String.split(" ")
      |> Enum.map_join(" ", &String.capitalize/1)
    else
      header
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
