defmodule Indivisual.SceneModes do
  @moduledoc """
  A person's saved Spacetime modes: named x / y / z mappings, beside the built-in
  ones.

  Every function takes an `Indivisual.Accounts.Scope` as its FIRST argument, and
  there is no clause that accepts `nil` — the enforcement `USER_SCOPING.md`
  specifies and `Indivisual.Timelog` first applied. A mode belongs to one person;
  omitting the scope is an arity error, not a query that quietly returns someone
  else's. A signed-out reader simply has none: the caller does not ask.

  A saved mode is NEVER what a URL carries. A view's URL states its axes
  (`scene=custom&axes=source,truth,time`), so a shared link works for someone who
  has not saved that mode, and a mode's name stays its owner's. Saving is only a
  way back to a set of axes — and a name for it.
  """

  import Ecto.Query, warn: false

  alias Indivisual.Accounts.Scope
  alias Indivisual.Accounts.User
  alias Indivisual.Repo
  alias Indivisual.SceneModes.Mode

  @doc "The person's modes, oldest first — the order they were made in."
  def list(%Scope{user: %User{id: uid}}) do
    Repo.all(from m in Mode, where: m.user_id == ^uid, order_by: [asc: m.inserted_at, asc: m.id])
  end

  @doc "The person's mode with exactly these axes, or nil."
  def get_by_axes(%Scope{user: %User{id: uid}}, axes) when is_list(axes) do
    Repo.one(from m in Mode, where: m.user_id == ^uid and m.axes == ^axes)
  end

  @doc "Saves a mode. `attrs` needs `name` and `axes`. Returns `{:ok, mode}` or `{:error, changeset}`."
  def create(%Scope{user: %User{id: uid}}, attrs) do
    %Mode{user_id: uid}
    |> Mode.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes one of the person's modes by id. `{:error, :not_found}` for anyone else's."
  def delete(%Scope{user: %User{id: uid}}, id) do
    case Repo.one(from m in Mode, where: m.user_id == ^uid and m.id == ^id) do
      nil -> {:error, :not_found}
      mode -> Repo.delete(mode)
    end
  end

  @doc "A changeset for the save form."
  def change(%Scope{}, attrs \\ %{}), do: Mode.changeset(%Mode{}, attrs)
end
