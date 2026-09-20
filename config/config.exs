# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :indivisual, :scopes,
  user: [
    default: true,
    module: Indivisual.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Indivisual.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :indivisual,
  ecto_repos: [Indivisual.Repo],
  generators: [timestamp_type: :utc_datetime]

# Swoosh mailer — used by phx.gen.auth for confirmation / reset emails.
# Dev/test default only. Prod OVERRIDES this in config/runtime.exs and raises
# if SES is unconfigured; leaving prod on Local silently drops every email.
config :indivisual, Indivisual.Mailer, adapter: Swoosh.Adapters.Local

# Never log these, from any source (params, changesets in error reports).
# github_access_token is a `repo`-scoped credential: it leaked into CloudWatch
# once (2026-09-18) via a raised Ecto.ChangeError that printed the changeset.
config :phoenix, :filter_parameters, [
  "password",
  "secret",
  "token",
  "github_access_token",
  "client_secret",
  "code"
]

# Disable Swoosh's API client by default; runtime.exs enables hackney for SES.
config :swoosh, :api_client, false

# GitHub OAuth. Scopes: `read:user`/`user:email` identify the user; `repo` is
# what lets them persist their files back to their own repository — the point
# of the integration, not an incidental extra.
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "read:user,user:email,repo"]}
  ]

# Background jobs — embedding generation for the topo semantic axes.
config :indivisual, Oban,
  repo: Indivisual.Repo,
  queues: [embeddings: 2]

# Contextual explanation of one event — local Ollama by default.
# Static vocabulary lives in Indivisual.Atlas.Glossary; this covers only the
# part a lookup table cannot answer. Disabled means the UI simply does not
# offer it, never that a page fails.
config :indivisual, Indivisual.Explain,
  adapter: Indivisual.Explain.Ollama,
  url: "http://localhost:11434",
  model: "qwen3:8b"

# Text embeddings (semantic axes) — local Ollama by default.
# The app degrades gracefully (embedding features report unavailable) when
# Ollama is not running. Axes record the model they were computed with, so
# recompute axes and rescore nodes after switching models.
config :indivisual, Indivisual.Embeddings,
  adapter: Indivisual.Embeddings.Ollama,
  url: "http://localhost:11434",
  model: "qwen3-embedding:8b"

# Configure the endpoint
config :indivisual, IndivisualWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IndivisualWeb.ErrorHTML, json: IndivisualWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Indivisual.PubSub,
  live_view: [signing_salt: "3Z7oWYMa"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  indivisual: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  indivisual: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
