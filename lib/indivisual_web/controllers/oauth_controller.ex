defmodule IndivisualWeb.OAuthController do
  use IndivisualWeb, :controller
  plug Ueberauth

  alias Indivisual.Accounts
  alias IndivisualWeb.UserAuth

  # Ueberauth handles the request phase via plug — this is only reached
  # if the provider isn't configured.
  def request(conn, _params) do
    conn
    |> put_flash(:error, "Unknown OAuth provider.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    attrs = %{
      email: auth.info.email,
      github_uid: to_string(auth.uid),
      github_login: auth.info.nickname,
      github_avatar_url: auth.info.image,
      github_access_token: auth.credentials && auth.credentials.token
    }

    case Accounts.find_or_create_github_user(attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Signed in as #{user.github_login}.")
        |> UserAuth.log_in_user(user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not sign in with GitHub.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "GitHub authentication failed.")
    |> redirect(to: ~p"/users/log-in")
  end
end
