defmodule IndivisualWeb.PageControllerTest do
  use IndivisualWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    # The two features the app exists for, plus the GitHub sign-in entry point.
    assert response =~ "indivisual"
    assert response =~ ~s(href="/topo")
    assert response =~ ~s(href="/atlas")
    assert response =~ ~s(href="/auth/github")
  end
end
