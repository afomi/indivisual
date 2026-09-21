defmodule Indivisual.SceneModesTest do
  @moduledoc """
  A person's saved Spacetime modes. The thing that must not regress is the
  scoping: a mode is one person's, and no function can be called without saying
  whose.
  """
  use Indivisual.DataCase, async: true

  import Indivisual.AccountsFixtures

  alias Indivisual.Accounts.Scope
  alias Indivisual.SceneModes

  @axes ~w(source truth time)

  defp scope, do: Scope.for_user(user_fixture())

  test "a mode is a name for three axes" do
    scope = scope()

    assert {:ok, mode} = SceneModes.create(scope, %{name: "  By source  ", axes: @axes})
    assert mode.name == "By source"
    assert mode.axes == @axes
    assert SceneModes.list(scope) == [mode]
    assert SceneModes.get_by_axes(scope, @axes) == mode
  end

  test "a person can keep several, in the order they made them" do
    scope = scope()
    {:ok, a} = SceneModes.create(scope, %{name: "One", axes: ~w(source truth time)})
    {:ok, b} = SceneModes.create(scope, %{name: "Two", axes: ~w(truth source time)})

    assert SceneModes.list(scope) == [a, b]
  end

  test "modes are one person's: another person neither sees nor can delete them" do
    mine = scope()
    theirs = scope()
    {:ok, mode} = SceneModes.create(mine, %{name: "Mine", axes: @axes})

    assert SceneModes.list(theirs) == []
    assert SceneModes.get_by_axes(theirs, @axes) == nil
    assert SceneModes.delete(theirs, mode.id) == {:error, :not_found}
    assert SceneModes.list(mine) == [mode]

    # And the same name and axes are theirs to use too.
    assert {:ok, _} = SceneModes.create(theirs, %{name: "Mine", axes: @axes})
  end

  test "there is no way to ask without a scope" do
    # Through `apply/3`: written as a plain call, the compiler's type checker
    # already refuses it — which is the point, but would warn on every build.
    assert_raise FunctionClauseError, fn -> apply(SceneModes, :list, [nil]) end

    assert_raise FunctionClauseError, fn ->
      apply(SceneModes, :create, [nil, %{name: "x", axes: @axes}])
    end

    assert_raise FunctionClauseError, fn -> apply(SceneModes, :delete, [nil, 1]) end
  end

  test "the owner is set from the scope, never from the attributes" do
    mine = scope()
    other = user_fixture()

    {:ok, mode} = SceneModes.create(mine, %{name: "Mine", axes: @axes, user_id: other.id})

    assert mode.user_id == mine.user.id
  end

  describe "what cannot be saved" do
    test "a nameless mode, or an over-long name" do
      scope = scope()

      assert {:error, changeset} = SceneModes.create(scope, %{name: "  ", axes: @axes})
      assert %{name: [_ | _]} = errors_on(changeset)

      assert {:error, changeset} =
               SceneModes.create(scope, %{name: String.duplicate("n", 41), axes: @axes})

      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "axes that are not three known dimensions" do
      assert {:error, changeset} =
               SceneModes.create(scope(), %{name: "x", axes: ~w(nope nope nope)})

      assert %{axes: ["must be three known dimensions"]} = errors_on(changeset)

      assert {:error, _} = SceneModes.create(scope(), %{name: "x", axes: ~w(time)})
    end

    test "a built-in mode: it is already in the switch, under its own name" do
      assert {:error, changeset} =
               SceneModes.create(scope(), %{name: "My map", axes: ~w(lng lat none)})

      assert %{axes: [message]} = errors_on(changeset)
      assert message =~ "Map"
    end

    test "the same name, or the same axes, twice" do
      scope = scope()
      {:ok, _} = SceneModes.create(scope, %{name: "By source", axes: @axes})

      assert {:error, changeset} =
               SceneModes.create(scope, %{name: "By source", axes: ~w(truth source time)})

      assert %{name: ["is already one of your modes"]} = errors_on(changeset)

      assert {:error, changeset} = SceneModes.create(scope, %{name: "Again", axes: @axes})
      assert %{axes: [_ | _]} = errors_on(changeset)
    end
  end

  test "deleting removes it" do
    scope = scope()
    {:ok, mode} = SceneModes.create(scope, %{name: "Gone", axes: @axes})

    assert {:ok, _} = SceneModes.delete(scope, mode.id)
    assert SceneModes.list(scope) == []
  end
end
