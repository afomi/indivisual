defmodule IndivisualWeb.UserSessionLoginPageTest do
  # async: false — these toggle application env that other tests read.
  use IndivisualWeb.ConnCase, async: false

  setup do
    dev_routes = Application.get_env(:indivisual, :dev_routes)
    mailer = Application.get_env(:indivisual, Indivisual.Mailer)

    on_exit(fn ->
      restore(:dev_routes, dev_routes)
      restore(Indivisual.Mailer, mailer)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:indivisual, key)
  defp restore(key, value), do: Application.put_env(:indivisual, key, value)

  defp login_html(conn), do: conn |> get(~p"/users/log-in") |> html_response(200)

  describe "dev mailbox notice" do
    test "is hidden in prod even if the mailer still points at the local adapter", %{conn: conn} do
      # Regression: prod inherits Swoosh.Adapters.Local from config/config.exs
      # when runtime mail config is absent, which advertised /dev/mailbox — a
      # route that does not exist in prod — to real users on the login page.
      Application.put_env(:indivisual, :dev_routes, false)
      Application.put_env(:indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.Local)

      html = login_html(conn)

      refute html =~ "/dev/mailbox"
      refute html =~ "local mail adapter"
    end

    test "is hidden in prod when mail goes out over SES", %{conn: conn} do
      Application.put_env(:indivisual, :dev_routes, false)
      Application.put_env(:indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.AmazonSES)

      refute login_html(conn) =~ "/dev/mailbox"
    end

    test "is shown in dev, where /dev/mailbox actually routes", %{conn: conn} do
      Application.put_env(:indivisual, :dev_routes, true)
      Application.put_env(:indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.Local)

      assert login_html(conn) =~ "/dev/mailbox"
    end
  end

  describe "GitHub sign-in" do
    test "is offered on the login page in prod", %{conn: conn} do
      # GitHub is the only sign-in path guaranteed to be configured in prod
      # (config/runtime.exs raises at boot without it), but the login page
      # previously offered only the email and password forms.
      Application.put_env(:indivisual, :dev_routes, false)
      Application.put_env(:indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.AmazonSES)

      html = login_html(conn)

      assert html =~ ~p"/auth/github"
      assert html =~ "Sign in with GitHub"
    end
  end
end
