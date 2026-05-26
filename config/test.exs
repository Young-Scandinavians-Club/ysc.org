import Config

# Newsletter MX checks: never hit real DNS in tests unless @tag :external_dns
config :ysc, Ysc.Newsletter.EmailValidator,
  mx_resolver: fn _domain -> :ok end,
  mx_lookup_timeout_ms: 200

config :ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock

# Credential keys are cleared in test/test_helper.exs so host .env never triggers Intuit HTTP.

# Skip SNS signature verification in tests (no real AWS cert to fetch)
config :ysc, :sns_skip_signature_verification, true

# Speed up QuickBooks tests by disabling rate limit backoff delays
config :ysc,
  quickbooks_max_429_retries: 0,
  quickbooks_default_429_backoff_seconds: 0

# Speed up payment success retry delays
config :ysc,
  payment_success_retry_delay_ms: 0,
  payment_success_total_timeout_ms: 1_000

# Speed up Stripe customer database sync delays
config :ysc,
  stripe_customer_db_sync_delay_ms: 0,
  stripe_customer_db_sync_retry_delay_ms: 0

# Configure Stripe mocks for testing
config :ysc,
  stripe_payment_method_module: Stripe.PaymentMethodMock,
  stripe_setup_intent_module: Ysc.TestStripeSetupIntent,
  stripe_payment_intent_module: Stripe.PaymentIntentMock,
  stripe_customer_module: Stripe.CustomerMock,
  stripe_subscription_module: Stripe.SubscriptionMock,
  stripe_invoice_module: Stripe.InvoiceMock,
  customers_module: Ysc.CustomersMock,
  payments_module: Ysc.PaymentsMock,
  # runtime.exs does not read STRIPE_PROCESS_PAYOUT_WEBHOOKS in :test; keep explicit so
  # payout webhook tests stay green regardless of shell/.env.
  process_stripe_payout_webhooks: true

# Minimum Argon2 parameters for tests — fast but still exercises the real hash path.
# t_cost: 1  — single iteration (minimum)
# m_cost: 8  — 256 KiB memory (minimum recommended)
# parallelism: 1 — single thread; avoids spawning 4 OS threads per hash when
#                  ExUnit runs many concurrent cases, reducing thread contention.
config :argon2_elixir,
  t_cost: 1,
  m_cost: 8,
  parallelism: 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ysc, Ysc.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ysc_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 20,
  queue_target: 50_000,
  queue_interval: 1_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ysc, YscWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "JR0p+50lWrtv0/Y2H9jGQbi0lPOIw/jTGkHJOhpOD6JpyyJDLpN5I1058al/ibel",
  server: false

# In test we don't send emails.
config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Test

# ExAws: static credentials + MinIO-style host so presigned URL generation
# (e.g. expense report file redirects) works in CI without EC2 instance metadata.
#
# Default ExAws retries (10 attempts, exponential backoff up to 10s) make
# intentional connection-failure tests (e.g. AvatarProcessor on a closed port)
# very slow; a single attempt is enough in test.
config :ex_aws,
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin",
  retries: [max_attempts: 1],
  s3: [
    scheme: "http://",
    host: "localhost",
    port: 9000
  ]

# Relax auth rate limits in test so login/forgot-password tests don't hit them
config :ysc, Ysc.AuthRateLimit, ip_limit: 10_000, identifier_limit: 10_000

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
# Suppress error logs for cleaner test output
config :logger, level: :error

# Note: You may see some Postgrex disconnection errors during test runs.
# These are expected and occur when async database operations are still running
# while tests finish and cleanup. They don't indicate actual problems and can be
# safely ignored. The test suite handles proper cleanup via Ecto.Adapters.SQL.Sandbox.

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :ysc, Oban, testing: :inline

config :ysc, sql_sandbox_timeout: 30_000
config :ysc, sql_sandbox: true

config :phoenix_test, :endpoint, YscWeb.Endpoint
config :phoenix_turnstile, :turnstile_module, TurnstileMock
config :ysc, :stripe_customer, Stripe.CustomerMock
config :ysc, :stripe_client, Ysc.TestStripeClient
config :ysc, :stripe_subscription_retriever, Ysc.StripeSubscriptionRetrieverMock
config :ysc, :accounts_module, Ysc.AccountsMock

# Discord alerts configuration for testing.
# The HTTP client is mocked so no real network I/O occurs.
config :ysc, Ysc.Alerts.Discord,
  webhook_url: "https://discord.com/api/webhooks/test/token",
  enabled: true

config :ysc, :discord_http_client, Ysc.Alerts.DiscordHttpMock

config :ysc,
  expense_reports_s3_bucket: "expense-reports",
  expense_reports_s3_upload: Ysc.ExpenseReports.S3UploadMock,
  environment: "test"

# FlowRoute SMS configuration for tests
# Use a fake number since we're in noop mode anyway
config :ysc, :flowroute, from_number: "12061231234"
config :ysc, :flowroute_force_noop, true

# Enables `Application.put_env(:ysc, :flowroute_test_raise, ...)` in SMS tests only.
config :ysc, :flowroute_test_inject_enabled, true

# OAuth Configuration for tests
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: "test_google_client_id",
  client_secret: "test_google_client_secret"

config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: "test_facebook_client_id",
  client_secret: "test_facebook_client_secret"

# Wax (WebAuthn) configuration for tests
#
# RP ID: "localhost" (test environment - separate from dev/prod)
# All binary data uses Base64URL encoding for WebAuthn compatibility
config :wax_,
  rp_id: "localhost",
  origin: "http://localhost:4002",
  attestation: "none"

# Disable season cache in tests to avoid race conditions with async tests
config :ysc, :season_cache_enabled, false

# Fail fast on accidental real Stripe HTTP (no retries; dummy key if unset)
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET") || "sk_test_stub_no_network",
  public_key: System.get_env("STRIPE_PUBLIC_KEY") || "pk_test_stub"

config :stripity_stripe, :retries, max_attempts: 1

# Avoid real S3 uploads and OpenSSL pass signing in tests
config :ysc, :media_s3_uploader, Ysc.Media.TestS3Uploader

config :ysc,
       :apple_wallet_passbook_generator,
       Ysc.AppleWallet.TestPassbookGenerator
