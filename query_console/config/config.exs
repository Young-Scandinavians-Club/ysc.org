# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Only the metadata Repo participates in mix ecto.* tasks. AnalyticsRepo is
# started in the supervision tree but must never receive migrations/drops —
# in local/dev it often points at the live YSC database.
config :query_console,
  ecto_repos: [QueryConsole.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  max_result_rows: 10_000,
  max_result_bytes: 5_000_000,
  workbook_revision_limit: 50,
  statement_timeout_ms: 30_000,
  lock_timeout_ms: 5_000,
  idle_in_transaction_session_timeout_ms: 60_000,
  work_mem: "16MB",
  temp_file_limit: "256MB",
  query_lease_ttl_ms: 120_000

# Decode Postgres uuid columns as Crockford ULIDs for raw analytics queries.
# Do not set this on QueryConsole.Repo — Ecto.ULID schema fields expect binaries
# from the driver and load/dump themselves.
config :query_console, QueryConsole.AnalyticsRepo, types: QueryConsole.PostgrexTypes

# Configures the endpoint
config :query_console, QueryConsoleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: QueryConsoleWeb.ErrorHTML, json: QueryConsoleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: QueryConsole.PubSub,
  live_view: [signing_salt: "AzknkYht"]

# Lotus stores metadata in QueryConsole.Repo; analytics reads use AnalyticsRepo.
config :lotus,
  ecto_repo: QueryConsole.Repo,
  default_repo: "analytics",
  data_repos: %{
    "analytics" => QueryConsole.AnalyticsRepo
  },
  unique_names: false,
  read_only: true,
  cache: %{
    adapter: Lotus.Cache.ETS,
    profiles: %{
      results: [ttl_ms: 60_000],
      schema: [ttl_ms: 3_600_000],
      options: [ttl_ms: 300_000]
    }
  }

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  query_console: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" =>
        Enum.join(
          [
            Path.expand("../assets/node_modules", __DIR__),
            Path.expand("../deps", __DIR__),
            Mix.Project.build_path()
          ],
          ":"
        )
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  query_console: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
