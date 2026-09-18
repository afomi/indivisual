defmodule Indivisual.Repo.Migrations.AddGithubOauthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :github_uid, :string
      add :github_login, :string
      add :github_avatar_url, :string
      # Cloak-encrypted ciphertext, not readable SQL text.
      add :github_access_token, :binary
    end

    create unique_index(:users, [:github_uid])

    # A GitHub account may keep its email private, so the OAuth callback can
    # legitimately arrive without one. github_uid is the real identity here;
    # email is supplementary. (hashed_password is already nullable from the
    # generated migration — OAuth users never set a password.)
    alter table(:users) do
      modify :email, :citext, null: true, from: {:citext, null: false}
    end
  end
end
