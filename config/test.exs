import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :indivisual, Indivisual.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "indivisual_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :indivisual, IndivisualWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "cg+f6O5DN7ZrGnYS6SGN4eSnAaOxqp08g1uFq0g5G38rgZICpz+kPSDLLCe/s1GM",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Never deliver real mail in tests.
config :indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.Test

# Non-production vault key — deterministic, never used for real secrets.
config :indivisual, Indivisual.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES256",
      key: Base.decode64!("3Jnb0hZiHIzHTOih7t2cTGYjRjR3ZLZ5U8n0Q7pQ2Hk="),
      iv_length: 12
    }
  ]

# Oban: no queues or plugins in test; jobs run inline where asserted.
config :indivisual, Oban, testing: :inline

# No Ollama in test — use the deterministic fake embedding adapter.
config :indivisual, Indivisual.Embeddings, adapter: Indivisual.Embeddings.Fake
