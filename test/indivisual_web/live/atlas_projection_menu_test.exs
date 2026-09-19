defmodule IndivisualWeb.AtlasProjectionMenuTest do
  @moduledoc """
  The projection moved from a fixed rail column into a radio row in the nav.
  What matters: all four options are visible at once, exactly one is selected,
  and choosing one still round-trips through the URL so a view stays shareable.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Indivisual.Atlas.Projections

  test "the selector is a radio group in a nav, not the rail", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas")

    assert has_element?(view, "nav#atlas-projection-nav")
    assert has_element?(view, ~s(#atlas-projections[role="radiogroup"]))
    # It precedes the column grid rather than living inside the aside.
    assert html =~ ~r/id="atlas-projection-nav".*lg:grid-cols-/s
    refute html =~ ~r/id="atlas-rail".*id="atlas-projections"/s
  end

  test "every projection is a radio option, with name and question", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    for def <- Projections.list() do
      assert has_element?(view, ~s(input[type="radio"][name="projection"][value="#{def.id}"])),
             "expected a radio for #{def.id}"

      # Main text and subtext both render.
      assert render(view) =~ def.name
      assert render(view) =~ def.question
    end
  end

  test "exactly one option is checked, and it is the active projection", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")
    default_id = Projections.default_id()

    assert has_element?(view, ~s(input[value="#{default_id}"][checked]))

    checked =
      view
      |> render()
      |> then(&Regex.scan(~r/<input[^>]*type="radio"[^>]*checked/, &1))
      |> length()

    assert checked == 1, "expected exactly one checked radio, got #{checked}"
  end

  test "choosing a projection patches the URL and moves the selection", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    other = Enum.find(Projections.list(), &(&1.id != Projections.default_id()))

    view |> form("#atlas-projections", %{"projection" => other.id}) |> render_change()

    assert assert_patch(view) =~ "projection=#{other.id}"
    assert has_element?(view, ~s(input[value="#{other.id}"][checked]))
  end

  test "the active option is marked for styling and assistive tech", %{conn: conn} do
    other = Enum.find(Projections.list(), &(&1.id != Projections.default_id()))
    {:ok, view, _} = live(conn, ~p"/atlas?projection=#{other.id}")

    assert has_element?(view, ~s(input[value="#{other.id}"][checked]))
    assert has_element?(view, ".atlas-projnav__option.is-active")
  end
end
