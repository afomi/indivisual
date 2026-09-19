defmodule Indivisual.Spaces do
  @moduledoc """
  Context for Spaces and their Nodes.
  """

  import Ecto.Query, warn: false
  alias Indivisual.Repo
  alias Indivisual.Space
  alias Indivisual.Visual.Node
  alias Indivisual.Visual.Link

  # --- Spaces ---

  def list_spaces do
    Repo.all(from s in Space, order_by: [desc: s.inserted_at])
  end

  def get_space!(id), do: Repo.get!(Space, id)

  def get_space_by_slug!(slug), do: Repo.get_by!(Space, slug: slug)

  def get_space_by_slug(slug), do: Repo.get_by(Space, slug: slug)

  def create_space(attrs \\ %{}) do
    %Space{}
    |> Space.changeset(attrs)
    |> Repo.insert()
  end

  def get_or_create_default_space do
    case Repo.get_by(Space, slug: "default") do
      nil ->
        {:ok, space} = create_space(%{name: "Default", slug: "default"})
        space

      space ->
        space
    end
  end

  # --- Nodes ---

  def list_nodes_for_space(%Space{id: space_id}) do
    Repo.all(from n in Node, where: n.space_id == ^space_id, order_by: [asc: n.id])
  end

  def get_node!(id), do: Repo.get!(Node, id)

  def create_node(%Space{} = space, attrs \\ %{}) do
    %Node{}
    |> Node.changeset(Map.put(attrs, "space_id", space.id))
    |> Repo.insert()
    |> maybe_enqueue_embedding()
  end

  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
    |> maybe_enqueue_embedding(node)
  end

  # Re-embed when text-bearing fields change (not on x/y moves).
  defp maybe_enqueue_embedding(result, before \\ nil)

  defp maybe_enqueue_embedding({:ok, node} = result, before) do
    if before == nil or
         node.name != before.name or
         node.description != before.description or
         node.metadata != before.metadata do
      %{"node_id" => node.id}
      |> Indivisual.Workers.EmbedNodeWorker.new()
      |> Oban.insert()
    end

    result
  end

  defp maybe_enqueue_embedding(result, _before), do: result

  def delete_node(%Node{} = node), do: Repo.delete(node)

  # --- Edges ---

  def list_edges_for_space(%Space{id: space_id}) do
    Repo.all(from e in Link, where: e.space_id == ^space_id)
  end

  def create_edge(%Space{} = space, from_id, to_id) do
    %Link{}
    |> Link.changeset(%{
      "from_id" => from_id,
      "to_id" => to_id,
      "space_id" => space.id
    })
    |> Repo.insert()
  end

  def delete_edge(%Link{} = edge), do: Repo.delete(edge)
end
