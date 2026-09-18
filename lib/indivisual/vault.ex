defmodule Indivisual.Vault do
  @moduledoc """
  Cloak vault for encrypting secrets at rest.

  Currently guards `users.github_access_token` — a GitHub OAuth token with
  `repo` scope, which can write to a user's repositories. It must never sit in
  the database in plaintext: a DB snapshot or errant query would otherwise hand
  out write access to every connected user's repos.

  The key comes from `CLOAK_KEY` (base64-encoded 32 bytes) at runtime.
  """
  use Cloak.Vault, otp_app: :indivisual
end

defmodule Indivisual.Encrypted.Binary do
  @moduledoc "Ecto type for a Cloak-encrypted binary field."
  use Cloak.Ecto.Binary, vault: Indivisual.Vault
end
