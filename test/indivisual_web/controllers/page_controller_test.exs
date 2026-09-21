defmodule IndivisualWeb.PageControllerTest do
  use IndivisualWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    # What the app exists for, plus the GitHub sign-in entry point.
    assert response =~ "indivisual"
    refute response =~ ~s(href="/topo")
    assert response =~ ~s(href="/atlas")
    assert response =~ ~s(href="/auth/github")
    assert response =~ ~s(href="/atlas/about")
  end

  test "every page ends in a footer: about, then github", %{conn: conn} do
    for path <- [~p"/", ~p"/atlas/about", ~p"/atlas"] do
      html = conn |> get(path) |> html_response(200)
      doc = LazyHTML.from_document(html)

      links = doc |> LazyHTML.query("#site-footer a") |> LazyHTML.attribute("href")
      assert links == ["/atlas/about", "https://github.com/afomi/indivisual"], path

      labels =
        doc
        |> LazyHTML.query("#site-footer a")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert labels == ["about", "github"]
    end
  end

  test "the source link lives in the footer now, not in the home page's text", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ "Source code at"
  end

  describe "GET /atlas/about" do
    test "is public and says the one sentence", %{conn: conn} do
      response = conn |> get(~p"/atlas/about") |> html_response(200)

      assert response =~ ~s(id="atlas-about")
      assert response =~ "Activity stream + structured elements = real-time, contextual tools."
      assert response =~ "a view changes what is read, never what was recorded"
    end

    test "names what it is for: the public record, and the people who decide", %{conn: conn} do
      response = conn |> get(~p"/atlas/about") |> html_response(200)

      assert response =~ ~s(id="atlas-about-why")
      # The aim: shared awareness, one record, perspectives made explicit.
      assert response =~ ~s(id="atlas-about-aim")
      assert response =~ "a single source of truth"
      assert response =~ "perspectives made explicit"
      assert response =~ "Better interfaces for The Public Record"
      assert response =~ "Better tools for public decision-makers"
    end

    test "shows the sketch, with a text alternative", %{conn: conn} do
      response = conn |> get(~p"/atlas/about") |> html_response(200)

      [img] =
        response
        |> LazyHTML.from_document()
        |> LazyHTML.query("#atlas-about-figure img")
        |> Enum.to_list()

      assert LazyHTML.attribute(img, "src") == ["/images/atlas-ideas.png"]
      assert [alt] = LazyHTML.attribute(img, "alt")
      assert String.length(alt) > 80
      assert File.exists?(Path.join(:code.priv_dir(:indivisual), "static/images/atlas-ideas.png"))
    end

    test "leads on to Atlas itself", %{conn: conn} do
      response = conn |> get(~p"/atlas/about") |> html_response(200)

      assert response =~ ~s(href="/atlas")
    end
  end
end
