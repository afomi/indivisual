defmodule IndivisualWeb.TopoAtlasTest do
  @moduledoc """
  The two features indivisual exists for. These assert the pages actually
  render against an empty database — the state a fresh deploy is in — rather
  than only that a route resolves.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /topo" do
    test "renders with no space data", %{conn: conn} do
      conn = get(conn, ~p"/topo")
      assert html_response(conn, 200)
    end

    test "renders for an unknown space slug", %{conn: conn} do
      conn = get(conn, ~p"/topo/does-not-exist")
      assert html_response(conn, 200)
    end
  end

  describe "/atlas" do
    test "mounts the LiveView", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, ~p"/atlas")
      assert html =~ "atlas" or html =~ "Atlas"
    end
  end
end
