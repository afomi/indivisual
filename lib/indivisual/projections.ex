defmodule Indivisual.Projections do
  @moduledoc """
  Context for Projections — named, saved views of a Space.
  A Projection stores a filter_config (which nodes/edges to include)
  and a layout hint for the client renderer.
  """

  import Ecto.Query, warn: false
  alias Indivisual.Repo
  alias Indivisual.Projection
  alias Indivisual.Space

  @doc """
  Returns all projections for a space, ordered by name.
  """
  def list_projections_for_space(%Space{id: space_id}) do
    Repo.all(
      from p in Projection,
        where: p.space_id == ^space_id,
        order_by: [asc: p.name]
    )
  end

  @doc """
  Gets a single projection by id. Raises if not found.
  """
  def get_projection!(id), do: Repo.get!(Projection, id)

  @doc """
  Gets a projection by space and name. Returns nil if not found.
  """
  def get_projection_by_name(%Space{id: space_id}, name) do
    Repo.get_by(Projection, space_id: space_id, name: name)
  end

  @doc """
  Creates a projection for a space.
  """
  def create_projection(%Space{} = space, attrs) do
    %Projection{}
    |> Projection.changeset(Map.put(attrs, "space_id", space.id))
    |> Repo.insert()
  end

  @doc """
  Updates a projection.
  """
  def update_projection(%Projection{} = projection, attrs) do
    projection
    |> Projection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a projection.
  """
  def delete_projection(%Projection{} = projection), do: Repo.delete(projection)

  @doc """
  Applies a projection's filter_config to a list of nodes and edges.
  Returns {filtered_nodes, filtered_edges}.

  filter_config keys (all optional):
    - "kinds"     — list of node kind strings to include (nil = all)
    - "node_ids"  — explicit list of node ids to include (nil = all)
  """
  def apply(%Projection{filter_config: filter}, nodes, edges) do
    filtered_nodes = filter_nodes(nodes, filter)
    node_ids = MapSet.new(filtered_nodes, & &1.id)
    filtered_edges =
      Enum.filter(edges, fn e ->
        MapSet.member?(node_ids, e.from_id) and MapSet.member?(node_ids, e.to_id)
      end)

    {filtered_nodes, filtered_edges}
  end

  defp filter_nodes(nodes, filter) when map_size(filter) == 0, do: nodes

  defp filter_nodes(nodes, filter) do
    nodes
    |> maybe_filter_by_kinds(filter["kinds"])
    |> maybe_filter_by_ids(filter["node_ids"])
    |> maybe_filter_by_metadata(filter)
  end

  defp maybe_filter_by_kinds(nodes, nil), do: nodes
  defp maybe_filter_by_kinds(nodes, kinds) do
    Enum.filter(nodes, fn n -> n.kind in kinds end)
  end

  defp maybe_filter_by_ids(nodes, nil), do: nodes
  defp maybe_filter_by_ids(nodes, ids) do
    id_set = MapSet.new(ids)
    Enum.filter(nodes, fn n -> MapSet.member?(id_set, n.id) end)
  end

  # metadata_* keys: filter by node.metadata fields.
  # Scalar match:  metadata_org_type: ["nonprofit"] — node.metadata["org_type"] must be in list
  # Array overlap: metadata_regions: ["Portland"]   — node.metadata["regions"] must intersect list
  defp maybe_filter_by_metadata(nodes, filter) do
    meta_filters =
      filter
      |> Enum.filter(fn {k, _} -> String.starts_with?(k, "metadata_") end)
      |> Enum.map(fn {"metadata_" <> field, values} -> {field, values} end)

    if meta_filters == [] do
      nodes
    else
      Enum.filter(nodes, fn node ->
        meta = node.metadata || %{}
        Enum.all?(meta_filters, fn {field, allowed} ->
          value = Map.get(meta, field)
          case value do
            nil -> false
            list when is_list(list) -> Enum.any?(list, &(&1 in allowed))
            scalar -> scalar in allowed
          end
        end)
      end)
    end
  end
end
