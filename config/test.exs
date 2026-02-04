import Config

config :ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock

# Configure Stripe mocks for testing
config :ysc,
  stripe_payment_method_module: Stripe.PaymentMethodMock,
  stripe_setup_intent_module: Stripe.SetupIntentMock,
  stripe_payment_intent_module: Stripe.PaymentIntentMock,
  stripe_customer_module: Stripe.CustomerMock,
  customers_module: Ysc.CustomersMock,
  payments_module: Ysc.PaymentsMock

# In tests run with low complexity for speed
config :argon2_elixir,
  t_cost: 1,
  m_cost: 8

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
config :ysc, :stripe_customer, Stripe.CustomerMock
config :ysc, :stripe_client, Ysc.TestStripeClient
config :ysc, :stripe_subscription_retriever, Ysc.StripeSubscriptionRetrieverMock
config :ysc, :accounts_module, Ysc.AccountsMock
config :ysc, :keila_client, Ysc.Keila.ClientStub

# Discord alerts configuration for testing
config :ysc, Ysc.Alerts.Discord,
  webhook_url: "https://discord.com/api/webhooks/test/token",
  enabled: true

config :ysc,
  expense_reports_s3_bucket: "expense-reports",
  environment: "test"

# FlowRoute SMS configuration for tests
# Use a fake number since we're in noop mode anyway
config :ysc, :flowroute, from_number: "12061231234"

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
