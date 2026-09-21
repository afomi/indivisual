defmodule IndivisualWeb.TopoAtlasTest do
  @moduledoc """
  /atlas renders against an empty database — the state a fresh deploy is in —
  rather than only resolving as a route. (/topo, which this file also covered,
  was removed on 2026-09-20.)
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/topo" do
    test "is gone", %{conn: conn} do
      assert conn |> get("/topo") |> response(404)
      assert conn |> get("/topo/muni-codes") |> response(404)
    end
  end

  describe "/atlas" do
    test "mounts the LiveView", %{conn: conn} do
      assert {:ok, _view, html} = live(conn, ~p"/atlas")
      assert html =~ "atlas" or html =~ "Atlas"
    end
  end
end
