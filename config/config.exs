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
  environment: "dev",
  # Minimum disposable-domain rows expected after loading priv/disposable_domains.txt (tests use this as a floor).
  disposable_domains_threshold: 10_000,
  # Standalone Query Console base URL (admin sidebar link). Override per env / QUERY_CONSOLE_URL.
  query_console_url: nil

# Configure Elixir's Calendar to use Timex timezone database
config :elixir, :time_zone_database, Timex.Timezone.Database

# Tzdata polls IANA for timezone DB updates. The built-in Hackney adapter still
# calls hackney:body/1 on the response tuple, which breaks on hackney 4.x because
# the body is returned directly in the tuple.
config :tzdata, :http_client, Ysc.Tzdata.HttpClient

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
    root_layout: {YscWeb.Layouts, :error},
    layout: false
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

# Shared SES pacing defaults. Production may override these from its verified
# SES sending quota in runtime.exs.
config :ysc,
  ses_max_send_rate: 10,
  ses_rate_window_seconds: 1,
  newsletter_send_interval_ms: 125,
  email_delivery_retry_window_seconds: 48 * 60 * 60

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  admin: [
    args:
      ~w(js/admin.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --log-override:equals-nan=silent),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  # Copies html5-qrcode vendor file as-is so its UMD wrapper runs in global scope
  # when loaded via <script> tag (esbuild bundling breaks UMD global assignment).
  html5_qrcode: [
    args:
      ~w(vendor/html5-qrcode.min.js --loader:.js=copy --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{}
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
  ],
  admin: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/admin.css
      --output=../priv/static/assets/admin.css
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
  queues: [
    default: 10,
    media: 5,
    exports: 3,
    transactional_mail: 10,
    bulk_mail: 2,
    sms: 3,
    # Retained only to drain jobs created before queue prioritization.
    mailers: 2,
    maintenance: 2
  ],
  log: false,
  plugins: [
    # Maintain for 5 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 5},
    # Rebuild indexes concurrently nightly to prevent bloat and fragmentation
    Oban.Plugins.Reindexer,
    # Rescue jobs left stuck `executing` when a node is killed/deployed mid-job
    # (e.g. a large event video upload) back to `available` so they retry.
    # rescue_after is generous because EventPhotoUploadWorker can legitimately
    # run for a long time downloading + re-uploading multi-GB videos; a
    # shorter window would rescue still-running jobs and cause duplicate work.
    {Oban.Plugins.Lifeline, rescue_after: :timer.hours(3)},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", YscWeb.Workers.FileExportCleanUp},
       {"*/30 * * * *", Ysc.PropertyOutages.OutageScraperWorker},
       {"*/5 * * * *", Ysc.Bookings.HoldExpiryWorker},
       {"*/5 * * * *", Ysc.Bookings.ModificationHoldExpiryWorker},
       {"*/5 * * * *", Ysc.Bookings.BookingEntitlementExpiryWorker},
       {"*/5 * * * *", Ysc.Tickets.TimeoutWorker},
       {"*/5 * * * *", Ysc.Tickets.TicketReservationExpiryWorker},
       {"*/5 * * * *", Ysc.Events.EventPublishWorker},
       {"*/5 * * * *", YscWeb.Workers.NewsletterScheduleChecker},
       {"*/15 * * * *", Ysc.Subscriptions.ExpirationWorker},
       # Unused OTP codes expire after ~10 minutes; sweep leftover rows regularly.
       {"*/15 * * * *", Ysc.VerificationCodeCleanupWorker},
       {"0 2 * * *", YscWeb.Workers.ImageReprocessor},
       {"0 2 * * *", Ysc.Stripe.WebhookReconciliationWorker},
       {"0 0 * * *", Ysc.Ledgers.BalanceCheckWorker},
       {"0 1 * * *", Ysc.Ledgers.ReconciliationWorker},
       {"0 3 * * *", YscWeb.Workers.QuickbooksSyncRetryWorker},
       {"0 3 * * *", YscWeb.Workers.WebhookRetryWorker},
       {"0 */6 * * *", YscWeb.Workers.QuickbooksSyncExpenseReportBackupWorker},
       {"0 9 * * *",
        YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker},
       # 04:00 UTC = 8:00 PM PST (UTC-8) / 9:00 PM PDT (UTC-7)
       {"0 4 * * *", YscWeb.Workers.MembershipRenewalReminderWorker},
       {"0 10 * * *", YscWeb.Workers.EventPhotoReminderSweeperWorker},
       # 17:00 UTC = 9:00 AM PST (UTC-8) / 10:00 AM PDT (UTC-7)
       {"0 17 * * *", YscWeb.Workers.SeasonWeekendAvailabilityWorker}
     ]}
  ]

config :ex_cldr, default_backend: Ysc.Cldr
config :ex_money, default_cldr_backend: Ysc.Cldr

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  http_client: ExAws.Request.Req

config :flop, repo: Ysc.Repo

# Cloak encryption configuration
# The vault is configured in lib/ysc/vault.ex using the init/1 callback
# to read from environment variables. This config is kept for backwards compatibility
# but the actual configuration happens in the Vault module.

# Stripe configuration
# Note: In production, Stripe is configured at runtime in config/runtime.exs
# This config is for dev/test environments only
#
# stripity_stripe defaults to hackney with Connection: keep-alive, which returns
# :protocol_error on hackney 4.x. Use Req via Ysc.Stripe.HttpClient instead.
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET"),
  public_key: System.get_env("STRIPE_PUBLIC_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  http_module: Ysc.Stripe.HttpClient,
  use_connection_pool: false

config :stripity_stripe, :retries,
  max_attempts: 3,
  base_backoff: 500,
  max_backoff: 2_000

# Radar publishable key — set in config/runtime.exs so releases read RADAR_PUBLIC_KEY at VM start
# (compile-time env in config.exs is empty during Docker build and would bake in the test default).

# Email configuration defaults for dev/test environments
# Production runtime configuration is in config/runtime.exs
config :ysc, :emails,
  from_email: "noreply@ysc.org",
  from_name: "YSC",
  contact_email: "info@ysc.org",
  admin_email: "admin@ysc.org",
  membership_email: "memberships@ysc.org",
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

# Common event venue presets for the admin event editor (quick-pick pills)
config :ysc, :event_location_presets, [
  %{
    id: "swedish_american_hall",
    label: "Swedish American Hall",
    location_name: "Swedish American Hall",
    address: "2174 Market St, San Francisco, CA 94114",
    latitude: 37.76667619093857,
    longitude: -122.4304435827406
  },
  %{
    id: "clear_lake",
    label: "Clear Lake",
    location_name: "Clear Lake Cabin",
    address: "9325 Bass Road, Kelseyville, CA 95451",
    latitude: 38.981104,
    longitude: -122.7355958
  },
  %{
    id: "norwegian_club",
    label: "Norwegian Club",
    location_name: "The Norwegian Club of San Francisco",
    address: "1900 Fell St, San Francisco, CA 94117",
    latitude: 37.7727715,
    longitude: -122.4493584
  }
]

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
  from_number: System.get_env("FLOWROUTE_FROM_NUMBER"),
  webhook_token: System.get_env("FLOWROUTE_WEBHOOK_TOKEN")

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
  stripe_account_id: System.get_env("QUICKBOOKS_STRIPE_ACCOUNT_ID"),
  # Stripe fees expense account for payout Deposit fee lines.
  # Prefer ID when known; otherwise Name or FullyQualifiedName (paths with ":").
  stripe_fees_account_id: System.get_env("QUICKBOOKS_STRIPE_FEES_ACCOUNT_ID"),
  stripe_fees_account_name:
    System.get_env(
      "QUICKBOOKS_STRIPE_FEES_ACCOUNT_NAME",
      "Administration:Bank Service Charges:Stripe"
    ),
  ticket_discounts_account_id:
    System.get_env("QUICKBOOKS_TICKET_DISCOUNTS_ACCOUNT_ID"),
  ticket_discounts_account_name:
    System.get_env(
      "QUICKBOOKS_TICKET_DISCOUNTS_ACCOUNT_NAME",
      "Ticket Discounts"
    ),
  # Optional: QuickBooks Customer ID for payments with no user (e.g. system/anonymous).
  # Set this to avoid :user_not_found when exporting payouts that include such payments.
  system_customer_id: System.get_env("QUICKBOOKS_SYSTEM_CUSTOMER_ID")

# Client retry and delay configurations
# These control how long various operations wait/retry to improve resilience
# Set to 0 in test.exs to speed up test suite
config :ysc,
  # QuickBooks API rate limit retry configuration
  quickbooks_max_429_retries: 3,
  quickbooks_default_429_backoff_seconds: 2,
  # Payment success page retry configuration
  payment_success_retry_delay_ms: 500,
  payment_success_total_timeout_ms: 10_000,
  # Stripe customer database sync delays
  stripe_customer_db_sync_delay_ms: 50,
  stripe_customer_db_sync_retry_delay_ms: 100,
  # Overridden in runtime.exs from STRIPE_PROCESS_PAYOUT_WEBHOOKS (default: process webhooks).
  process_stripe_payout_webhooks: true

config :phoenix_template, :format_encoders, []

config :mime, :types, %{
  "application/atom+xml" => ["atom"],
  "application/xml" => ["xml"],
  "text/styles" => ["styles"],
  "video/x-m4v" => ["m4v"],
  "video/x-matroska" => ["mkv"]
}

# Headless Chrome for TV poster image capture (ChromicPDF)
config :ysc, ChromicPDF,
  no_sandbox: true,
  chrome_args: ["--disable-dev-shm-usage"]

config :ysc, :tv_poster_image_module, Ysc.Events.TvPosterImage.Chromic

# Ueberauth configuration
# Provider credentials are configured at runtime in config/runtime.exs
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    facebook:
      {Ueberauth.Strategy.Facebook,
       [
         default_scope: "email,public_profile",
         profile_fields: "id,name,email,picture.type(large)"
       ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
