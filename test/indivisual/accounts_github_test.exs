defmodule Indivisual.AccountsGitHubTest do
  @moduledoc """
  GitHub sign-in is the only auth path, and it stores a `repo`-scoped access
  token. These guard the two things that broke in production on 2026-09-18:
  the Cloak vault not being supervised (so every token write raised), and the
  resulting exception printing the token into the logs.
  """
  use Indivisual.DataCase, async: true

  alias Indivisual.Accounts
  alias Indivisual.Accounts.User
  alias Indivisual.Repo

  @token "gho_exampletokenvalue1234567890"

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        github_uid: "12345",
        github_login: "octocat",
        github_avatar_url: "https://example.com/a.png",
        email: "octocat@example.com",
        github_access_token: @token
      },
      overrides
    )
  end

  test "creates a user from a GitHub callback" do
    assert {:ok, %User{} = user} = Accounts.find_or_create_github_user(attrs())

    assert user.github_uid == "12345"
    assert user.github_login == "octocat"
    assert user.github_access_token == @token
  end

  test "the access token is encrypted at rest, not stored as plaintext" do
    {:ok, user} = Accounts.find_or_create_github_user(attrs())

    # Read the raw column, bypassing the Ecto type that would decrypt it.
    %{rows: [[raw]]} =
      Repo.query!("SELECT github_access_token FROM users WHERE id = $1", [
        Ecto.UUID.dump!(user.id)
      ])

    assert is_binary(raw)
    refute raw =~ "gho_"
    refute String.contains?(raw, @token)
  end

  test "signing in again refreshes the token rather than duplicating the user" do
    {:ok, first} = Accounts.find_or_create_github_user(attrs())
    {:ok, second} = Accounts.find_or_create_github_user(attrs(%{github_access_token: "gho_new"}))

    assert first.id == second.id
    assert second.github_access_token == "gho_new"
    assert Repo.aggregate(User, :count) == 1
  end

  test "a GitHub account with a private email still signs in" do
    # github_uid is the identity, not email — a private GitHub email arrives nil.
    assert {:ok, user} = Accounts.find_or_create_github_user(attrs(%{email: nil}))
    assert user.github_uid == "12345"
  end

  test "returns a tagged error, not a raise, when the upsert fails" do
    # Missing github_uid — the function head that guards on a binary uid.
    assert {:error, _} = Accounts.find_or_create_github_user(%{github_login: "nope"})
  end
end
