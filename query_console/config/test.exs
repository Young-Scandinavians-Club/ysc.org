import Config

config :query_console, QueryConsole.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "query_console_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :query_console, QueryConsole.AnalyticsRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ysc_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 2,
  prepare: :unnamed

config :query_console, QueryConsoleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "px17aYwN53gH40eY4HiLJgo30BQZy1wHUpLFmoIkJ8DfgQq9DFnrZl75byz2m/zN",
  server: false

config :query_console, QueryConsole.SSO,
  authorize_url: "http://localhost:4000/oauth/authorize",
  token_url: "http://localhost:4000/oauth/token",
  logout_url: "http://localhost:4000/oauth/logout",
  client_id: "query_console_test",
  client_secret: "test_secret_change_me",
  redirect_uri: "http://localhost:4001/auth/ysc/callback",
  post_logout_redirect_uri: "http://localhost:4001/auth/signed-out",
  base_url: "http://localhost:4001"

config :query_console, :catalog_auto_refresh, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
