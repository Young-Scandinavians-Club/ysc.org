# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Default environment - can be overridden by APP_ENV env var in runtime.exs
config :ysc,
  ecto_repos: [Ysc.Repo],
  environment: "dev"

# Configure Elixir's Calendar to use Timex timezone database
config :elixir, :time_zone_database, Timex.Timezone.Database

config :ysc, Ysc.Repo,
  migration_timestamps: [type: :utc_datetime],
  pool_size: 8,
  timeout: 15_000,
  prepare: :unnamed

# Configures the endpoint
config :ysc, YscWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: YscWeb.ErrorHTML, json: YscWeb.ErrorJSON],
    layout: {YscWeb.Layouts, :error}
  ],
  pubsub_server: Ysc.PubSub,
  live_view: [signing_salt: "CTGAp6Hk"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix,
  static_compressors: [
    PhoenixBakery.Gzip,
    PhoenixBakery.Brotli,
    PhoenixBakery.Zstd
  ]

config :argon2_elixir,
  argon2_type: 1

config :ysc, Oban,
  repo: Ysc.Repo,
  notifier: Oban.Notifiers.PG,
  queues: [default: 10, media: 5, exports: 3, mailers: 20, maintenance: 2],
  log: false,
  plugins: [
    # Maintain for 5 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 5},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", YscWeb.Workers.FileExportCleanUp},
       {"*/30 * * * *", Ysc.PropertyOutages.OutageScraperWorker},
       {"*/5 * * * *", Ysc.Bookings.HoldExpiryWorker},
       {"*/5 * * * *", Ysc.Tickets.TimeoutWorker},
       {"*/5 * * * *", Ysc.Events.EventPublishWorker},
       {"*/15 * * * *", Ysc.Subscriptions.ExpirationWorker},
       {"0 2 * * *", YscWeb.Workers.ImageReprocessor},
       {"0 0 * * *", Ysc.Ledgers.BalanceCheckWorker},
       {"0 1 * * *", Ysc.Ledgers.ReconciliationWorker},
       {"0 3 * * *", YscWeb.Workers.QuickbooksSyncRetryWorker},
       {"0 */6 * * *", YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker},
       {"0 9 * * *", YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker}
     ]}
  ]

config :ex_cldr, default_backend: Ysc.Cldr
config :ex_money, default_cldr_backend: Ysc.Cldr

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

config :flop, repo: Ysc.Repo

# Cloak encryption configuration
# The vault is configured in lib/ysc/vault.ex using the init/1 callback
# to read from environment variables. This config is kept for backwards compatibility
# but the actual configuration happens in the Vault module.

# Stripe configuration
# Note: In production, Stripe is configured at runtime in config/runtime.exs
# This config is for dev/test environments only
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET"),
  public_key: System.get_env("STRIPE_PUBLIC_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

config :stripity_stripe, :retries,
  max_attempts: 3,
  base_backoff: 500,
  max_backoff: 2_000

config :ysc, :radar,
  public_key:
    System.get_env(
      "RADAR_PUBLIC_KEY",
      "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966"
    )

# Email configuration defaults for dev/test environments
# Production runtime configuration is in config/runtime.exs
config :ysc, :emails,
  from_email: "noreply@ysc.org",
  from_name: "YSC",
  contact_email: "info@ysc.org",
  admin_email: "admin@ysc.org",
  membership_email: "membership@ysc.org",
  board_email: "board@ysc.org",
  volunteer_email: "volunteer@ysc.org",
  tahoe_email: "tahoe@ysc.org",
  clear_lake_email: "cl@ysc.org"

# Removed Bling configuration - using internal subscription management

# Membership plans configuration
# Note: In production, membership plans are configured at runtime in config/runtime.exs
# This config is for dev/test environments only
config :ysc,
  membership_plans: [
    %{
      id: :single,
      name: "Single",
      interval: "year",
      amount: 45,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id:
        System.get_env(
          "STRIPE_SINGLE_PRICE_ID",
          "price_1QfrfDIZd8GkARoBcwlNchx4"
        ),
      statement_descriptor: "Single Membership",
      description: "Membership just for yourself",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "year"
      }
    },
    %{
      id: :family,
      name: "Family",
      interval: "year",
      amount: 65,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id:
        System.get_env(
          "STRIPE_FAMILY_PRICE_ID",
          "price_1QfrgWIZd8GkARoB5JBtjoIL"
        ),
      statement_descriptor: "Family Membership",
      description: "For you, your Spouse and your children under 18",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "year"
      }
    },
    %{
      id: :lifetime,
      name: "Lifetime",
      interval: "lifetime",
      amount: 0,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id: nil,
      statement_descriptor: "Lifetime Membership",
      description:
        "Lifetime membership with all Family membership perks - never expires",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "lifetime"
      }
    }
  ]

# Keila configuration
# For production, set KEILA_API_URL, KEILA_API_KEY, KEILA_PROJECT_ID, and KEILA_FORM_ID environment variables
config :ysc, :keila,
  api_url: System.get_env("KEILA_API_URL"),
  api_key: System.get_env("KEILA_API_KEY"),
  project_id: System.get_env("KEILA_PROJECT_ID"),
  form_id: System.get_env("KEILA_FORM_ID")

# Accounting settings
config :ysc, :accounting,
  default_currency: :USD,
  quickbooks_classes: ["Administration", "Events", "Clear Lake", "Tahoe"]

# FlowRoute SMS configuration
# Note: In production, FlowRoute is configured at runtime in config/runtime.exs
# This config is for dev/test environments only
config :ysc, :flowroute,
  access_key: System.get_env("FLOWROUTE_ACCESS_KEY"),
  secret_key: System.get_env("FLOWROUTE_SECRET_KEY"),
  from_number: System.get_env("FLOWROUTE_FROM_NUMBER")

# QuickBooks configuration
# Note: In production, QuickBooks is configured at runtime in config/runtime.exs
# This config is for dev/test environments only
config :ysc, :quickbooks,
  client_id: System.get_env("QUICKBOOKS_CLIENT_ID"),
  client_secret: System.get_env("QUICKBOOKS_CLIENT_SECRET"),
  company_id: System.get_env("QUICKBOOKS_COMPANY_ID"),
  webhook_verifier_token: System.get_env("QUICKBOOKS_WEBHOOK_VERIFIER_TOKEN"),
  url:
    System.get_env(
      "QUICKBOOKS_BASE_URL",
      "https://sandbox-quickbooks.api.intuit.com/v3"
    ),
  app_id: System.get_env("QUICKBOOKS_APP_ID"),
  access_token: System.get_env("QUICKBOOKS_ACCESS_TOKEN"),
  refresh_token: System.get_env("QUICKBOOKS_REFRESH_TOKEN"),
  realm_id: System.get_env("QUICKBOOKS_REALM_ID"),
  # QuickBooks Item IDs for different entity types (optional - will auto-create if not set)
  event_item_id: System.get_env("QUICKBOOKS_EVENT_ITEM_ID"),
  donation_item_id: System.get_env("QUICKBOOKS_DONATION_ITEM_ID"),
  tahoe_booking_item_id: System.get_env("QUICKBOOKS_TAHOE_BOOKING_ITEM_ID"),
  clear_lake_booking_item_id:
    System.get_env("QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID"),
  membership_item_id: System.get_env("QUICKBOOKS_MEMBERSHIP_ITEM_ID"),
  single_membership_item_id:
    System.get_env("QUICKBOOKS_SINGLE_MEMBERSHIP_ITEM_ID"),
  family_membership_item_id:
    System.get_env("QUICKBOOKS_FAMILY_MEMBERSHIP_ITEM_ID"),
  default_item_id: System.get_env("QUICKBOOKS_DEFAULT_ITEM_ID"),
  stripe_fee_item_id: System.get_env("QUICKBOOKS_STRIPE_FEE_ITEM_ID"),
  # QuickBooks Account IDs (required - cannot be auto-created)
  bank_account_id: System.get_env("QUICKBOOKS_BANK_ACCOUNT_ID"),
  stripe_account_id: System.get_env("QUICKBOOKS_STRIPE_ACCOUNT_ID")

config :phoenix_template, :format_encoders, swiftui: Phoenix.HTML.Engine

config :mime, :types, %{
  "text/styles" => ["styles"],
  "text/swiftui" => ["swiftui"]
}

config :live_view_native,
  plugins: [
    LiveViewNative.SwiftUI
  ]

config :phoenix, :template_engines, neex: LiveViewNative.Engine

config :live_view_native_stylesheet,
  content: [
    swiftui: [
      "lib/**/swiftui/*",
      "lib/**/*swiftui*"
    ]
  ],
  output: "priv/static/assets"

# Ueberauth configuration
# Provider credentials are configured at runtime in config/runtime.exs
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    facebook: {Ueberauth.Strategy.Facebook, [default_scope: "email"]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
