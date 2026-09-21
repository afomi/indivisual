defmodule IndivisualWeb.AtlasReleasedUiTest do
  @moduledoc """
  The switch is built from the offered layouts, so hiding one removes its
  button rather than dimming it. This checks the rendered page, not the list.
  """
  # async: false — toggles application env that other tests read.
  use IndivisualWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original = Application.get_env(:indivisual, :unreleased_layouts)
    Application.put_env(:indivisual, :unreleased_layouts, false)
    on_exit(fn -> Application.put_env(:indivisual, :unreleased_layouts, original) end)
    :ok
  end

  test "no button is drawn for an unreleased layout", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-scene-layout-timeline")
    assert has_element?(view, "#atlas-scene-layout-map")

    for id <- ~w(space moment graph) do
      refute has_element?(view, "#atlas-scene-layout-#{id}"),
             "#{id} should have no button at all"
    end
  end

  test "a link to a hidden layout still renders a page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/atlas?scene=graph")

    assert html =~ "atlas-scene"
    assert has_element?(view, "#atlas-scene-layout-timeline[aria-checked=true]")
  end
end
