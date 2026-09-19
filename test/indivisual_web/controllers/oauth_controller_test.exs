defmodule IndivisualWeb.OAuthControllerTest do
  @moduledoc """
  GitHub is the sign-in path, so /auth/github must hand off to GitHub rather
  than 404 or error. Ueberauth's request phase runs as a plug, so a correctly
  wired route redirects to github.com; a misconfigured one falls through to
  the controller's own `request/2` and flashes an error instead.
  """
  use IndivisualWeb.ConnCase, async: true

  test "GET /auth/github redirects to GitHub", %{conn: conn} do
    conn = get(conn, ~p"/auth/github")

    assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
  end

  test "requests the repo scope, which backs file persistence", %{conn: conn} do
    conn = get(conn, ~p"/auth/github")
    location = redirected_to(conn)

    assert location =~ "repo"
    assert location =~ "user%3Aemail" or location =~ "user:email"
  end
end
