defmodule IndivisualWeb.AtlasSceneModesTest do
  @moduledoc """
  Saving a custom set of Spacetime axes as a mode of one's own. A mode is only a
  name for the axes: the URL always carries the axes themselves, so a link works
  for someone who never saved it, and signed out the page is unchanged.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Accounts.Scope
  alias Indivisual.SceneModes

  @custom "/atlas?scene=custom&axes=source%2Ctruth%2Ctime"

  describe "signed out" do
    test "the page works as ever, and a custom mode says what signing in would add", %{conn: conn} do
      {:ok, view, _} = live(conn, @custom)

      assert has_element?(view, "#atlas-scene-mode-signin a[href='/auth/github']")
      refute has_element?(view, "#atlas-scene-mode-form")
      refute has_element?(view, "#atlas-scene-mode-picker")
    end

    test "a built-in mode offers nothing to save", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?scene=map")
      refute has_element?(view, "#atlas-scene-modes")
    end
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "a custom set of axes can be named and saved", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, @custom)

      assert has_element?(view, "#atlas-scene-mode-form")

      view
      |> form("#atlas-scene-mode-form", %{"mode" => %{"name" => "By source"}})
      |> render_submit()

      assert [%{name: "By source", axes: ~w(source truth time)}] =
               SceneModes.list(Scope.for_user(user))

      # Now it is one of theirs: named, pickable, deletable — and no longer a form.
      assert view |> element("#atlas-scene-mode-current") |> render() =~ "By source"
      assert has_element?(view, "#atlas-scene-mode-select option[selected]", "By source")
      refute has_element?(view, "#atlas-scene-mode-form")
    end

    test "several can be kept, and picking one only sets the axes", %{conn: conn, user: user} do
      scope = Scope.for_user(user)
      {:ok, _} = SceneModes.create(scope, %{name: "By source", axes: ~w(source truth time)})
      {:ok, two} = SceneModes.create(scope, %{name: "Settledness", axes: ~w(truth stack time)})

      {:ok, view, _} = live(conn, ~p"/atlas")

      assert has_element?(view, "#atlas-scene-mode-select option", "By source")
      assert has_element?(view, "#atlas-scene-mode-select option", "Settledness")

      view |> form("#atlas-scene-mode-picker", %{"mode_id" => "#{two.id}"}) |> render_change()

      path = assert_patch(view)
      assert path =~ "scene=custom"
      assert path =~ "truth"
      # The URL names the axes, never the saved mode.
      refute path =~ "mode"
      refute path =~ "Settledness"
    end

    test "a name is needed, and a duplicate is refused where it was typed", %{
      conn: conn,
      user: user
    } do
      {:ok, _} =
        SceneModes.create(Scope.for_user(user), %{name: "Taken", axes: ~w(truth stack time)})

      {:ok, view, _} = live(conn, @custom)

      html =
        view
        |> form("#atlas-scene-mode-form", %{"mode" => %{"name" => "Taken"}})
        |> render_submit()

      assert html =~ "is already one of your modes"
      assert length(SceneModes.list(Scope.for_user(user))) == 1
    end

    test "deleting a mode leaves its axes on screen", %{conn: conn, user: user} do
      {:ok, _} =
        SceneModes.create(Scope.for_user(user), %{name: "By source", axes: ~w(source truth time)})

      {:ok, view, _} = live(conn, @custom)

      view |> element("#atlas-scene-mode-delete") |> render_click()

      assert SceneModes.list(Scope.for_user(user)) == []
      assert has_element?(view, "#atlas-scene-mode-form")
      assert has_element?(view, ~s(#atlas-scene[data-layout="custom"]))
    end

    test "someone else's modes are not offered", %{conn: conn} do
      other = Indivisual.AccountsFixtures.user_fixture()

      {:ok, _} =
        SceneModes.create(Scope.for_user(other), %{name: "Theirs", axes: ~w(source truth time)})

      {:ok, view, _} = live(conn, @custom)

      refute has_element?(view, "#atlas-scene-mode-picker")
      refute render(view) =~ "Theirs"
      # The same axes are theirs to save under their own name.
      assert has_element?(view, "#atlas-scene-mode-form")
    end
  end
end
