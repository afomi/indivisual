defmodule Indivisual.Visual do
  @moduledoc """
  The Visual context.
  """

  import Ecto.Query, warn: false
  alias Indivisual.Repo

  alias Indivisual.Visual.Node

  @doc """
  Returns the list of nodes.

  ## Examples

      iex> list_nodes()
      [%Node{}, ...]

  """
  def list_nodes do
    Node
    |> limit(1000)
    |> Repo.all()
  end

  @spec list_wardley_nodes :: any
  def list_wardley_nodes do
    Repo.all(
      from u in "nodes",
        # limit: 1000,
        where: u.wardley_x > 0,
        select: [
          :id,
          :wardley_x,
          :wardley_y,
          :z,
          :wardley_text,
          :hash,
          :name,
          :description,
          :kind
        ]
    )
  end

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.

  ## Examples

      iex> get_node!(123)
      %Node{}

      iex> get_node!(456)
      ** (Ecto.NoResultsError)

  """
  def get_node!(id), do: Repo.get!(Node, id)

  @doc """
  Creates a node.

  ## Examples

      iex> create_node(%{field: value})
      {:ok, %Node{}}

      iex> create_node(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a node.

  ## Examples

      iex> update_node(node, %{field: new_value})
      {:ok, %Node{}}

      iex> update_node(node, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a node.

  ## Examples

      iex> delete_node(node)
      {:ok, %Node{}}

      iex> delete_node(node)
      {:error, %Ecto.Changeset{}}

  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.

  ## Examples

      iex> change_node(node)
      %Ecto.Changeset{data: %Node{}}

  """
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  @doc """
  Computes how directly each intent Node's heading points at a goal coordinate.

  An intent Node is a Node with a `heading` (radians, `atan2(dx, dz)` convention).
  Alignment is the cosine similarity of the heading unit vector and the
  (node → goal) unit vector, in [-1, 1]: 1.0 = pointing straight at the goal,
  -1.0 = pointing directly away. Nodes without a heading are excluded — a point
  has no declared intent to align.

  Goal is a coordinate `{goal_x, goal_y}` in the same plane as the nodes'
  `x`/`y`, not necessarily a Node.

  ## Examples

      iex> aligned_to_goal([%Node{x: 0.0, y: 0.0, heading: :math.pi()/2}], {10.0, 0.0})
      [%{node: %Node{}, alignment: 1.0, distance: 10.0}]

  """
  def aligned_to_goal(nodes, {goal_x, goal_y}) do
    nodes
    |> Enum.filter(& &1.heading)
    |> Enum.map(fn node ->
      # heading unit vector, matching the /3d plane convention: atan2(dx, dz)
      hx = :math.sin(node.heading)
      hy = :math.cos(node.heading)

      dx = goal_x - (node.x || 0.0)
      dy = goal_y - (node.y || 0.0)
      distance = :math.sqrt(dx * dx + dy * dy)

      alignment =
        if distance == 0.0 do
          # on top of the goal: no direction to compare, treat as fully aligned
          1.0
        else
          (hx * dx + hy * dy) / distance
        end

      %{node: node, alignment: alignment, distance: distance}
    end)
  end

  alias Indivisual.Visual.Link

  @doc """
  Returns the list of links.

  ## Examples

      iex> list_links()
      [%Link{}, ...]

  """
  def list_links do
    Link
    |> limit(2100)
    # |> limit(200)
    |> Repo.all()
  end

  def list_wardley_links do
    Repo.all(
      from u in "edges",
        where: not is_nil(u.to_hash),
        limit: 7000,
        select: [:id, :from_id, :to_id, :from_hash, :to_hash, :description]
    )
  end

  @doc """
  Gets a single link.

  Raises `Ecto.NoResultsError` if the Link does not exist.

  ## Examples

      iex> get_link!(123)
      %Link{}

      iex> get_link!(456)
      ** (Ecto.NoResultsError)

  """
  def get_link!(id), do: Repo.get!(Link, id)

  @doc """
  Creates a link.

  ## Examples

      iex> create_link(%{field: value})
      {:ok, %Link{}}

      iex> create_link(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_link(attrs \\ %{}) do
    %Link{}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a link.

  ## Examples

      iex> update_link(link, %{field: new_value})
      {:ok, %Link{}}

      iex> update_link(link, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_link(%Link{} = link, attrs) do
    link
    |> Link.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a link.

  ## Examples

      iex> delete_link(link)
      {:ok, %Link{}}

      iex> delete_link(link)
      {:error, %Ecto.Changeset{}}

  """
  def delete_link(%Link{} = link) do
    Repo.delete(link)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking link changes.

  ## Examples

      iex> change_link(link)
      %Ecto.Changeset{data: %Link{}}

  """
  def change_link(%Link{} = link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end
end
