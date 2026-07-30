import Config

# Metadata database (writable)
config :query_console, QueryConsole.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "query_console_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Analytics reads reuse the main YSC development database for real schema introspection
config :query_console, QueryConsole.AnalyticsRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ysc_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 2,
  prepare: :unnamed

config :query_console, QueryConsoleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4001")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "3Y/qffqhRI31q5NFi0SOBW4Qvja2ExY/ddegH2oBFObKyVWhgv+6cuuAkcYvvQ74",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:query_console, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:query_console, ~w(--watch)]}
  ]

config :query_console, QueryConsoleWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/query_console_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
    ]
  ]

# Dev SSO defaults (override via env)
config :query_console, QueryConsole.SSO,
  authorize_url:
    System.get_env("YSC_SSO_AUTHORIZE_URL") ||
      "http://localhost:4000/oauth/authorize",
  token_url:
    System.get_env("YSC_SSO_TOKEN_URL") ||
      "http://localhost:4000/oauth/token",
  logout_url:
    System.get_env("YSC_SSO_LOGOUT_URL") || "http://localhost:4000/oauth/logout",
  client_id: System.get_env("YSC_SSO_CLIENT_ID") || "query_console_dev",
  client_secret: System.get_env("YSC_SSO_CLIENT_SECRET") || "dev_secret_change_me",
  redirect_uri:
    System.get_env("YSC_SSO_REDIRECT_URI") || "http://localhost:4001/auth/ysc/callback",
  post_logout_redirect_uri:
    System.get_env("YSC_SSO_POST_LOGOUT_REDIRECT_URI") ||
      "http://localhost:4001/auth/signed-out",
  base_url: System.get_env("QUERY_CONSOLE_BASE_URL") || "http://localhost:4001"

config :query_console, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
