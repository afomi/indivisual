import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/indivisual start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :indivisual, IndivisualWeb.Endpoint, server: true
end

config :indivisual, IndivisualWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :indivisual, IndivisualWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/indivisual_web/router\.ex$"E,
        ~r"lib/indivisual_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # RDS requires SSL. Without verified TLS here, migrations fail with a
  # connection timeout that reads like a networking problem but isn't.
  # The CA bundle is fetched at BUILD time by the Dockerfile — never committed.
  config :indivisual, Indivisual.Repo,
    ssl: [
      verify: :verify_peer,
      cacertfile: Path.join(:code.priv_dir(:indivisual), "ssl/aws-rds-ca.pem"),
      server_name_indication: ~c"#{URI.parse(database_url).host}",
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ],
    url: database_url,
    # Shared RDS has a ~400-connection ceiling across the whole fleet, so this
    # defaults low and is raised per-app via the POOL_SIZE secret if needed.
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :indivisual, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :indivisual, IndivisualWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :indivisual, IndivisualWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :indivisual, IndivisualWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

# ── GitHub OAuth ──
# Credentials for the OAuth app; the callback is /auth/github/callback.
#
# Guarded: runtime.exs runs AFTER config/test.exs, so an unconditional config
# here would overwrite the test credentials with nil — and ueberauth raises a
# CaseClauseError on a nil client_id rather than failing gracefully.
if github_client_id = System.get_env("GITHUB_CLIENT_ID") do
  config :ueberauth, Ueberauth.Strategy.Github.OAuth,
    client_id: github_client_id,
    client_secret: System.get_env("GITHUB_CLIENT_SECRET")
end

# In prod the app is unusable without them (GitHub is the only sign-in path),
# so fail loudly at boot instead of at a user's first click.
if config_env() == :prod do
  System.get_env("GITHUB_CLIENT_ID") ||
    raise "environment variable GITHUB_CLIENT_ID is missing (GitHub is the only sign-in path)"

  System.get_env("GITHUB_CLIENT_SECRET") ||
    raise "environment variable GITHUB_CLIENT_SECRET is missing"
end

# ── Encryption at rest ──
# CLOAK_KEY is base64-encoded 32 bytes. Without it the app cannot decrypt
# stored GitHub tokens, so fail loudly at boot rather than at first use.
if config_env() == :prod do
  vault_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: mix phx.gen.secret 32 | base64
      """

  config :indivisual, Indivisual.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES256", key: Base.decode64!(vault_key), iv_length: 12}
    ]
end
