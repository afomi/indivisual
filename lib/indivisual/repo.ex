defmodule Indivisual.Repo do
  use Ecto.Repo,
    otp_app: :indivisual,
    adapter: Ecto.Adapters.Postgres
end
