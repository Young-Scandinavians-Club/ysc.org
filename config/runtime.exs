import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Set environment name for alerting and logging
# Priority: APP_ENV env var > default from config.exs > config_env() fallback
# Only override if APP_ENV is explicitly set, otherwise use default from config.exs
if System.get_env("ENVIRONMENT") do
  config :ysc,
    environment: System.get_env("ENVIRONMENT")
end

# ## FlowRoute SMS Configuration
#
# Configure FlowRoute API settings for all environments at runtime.
# These must be set at runtime for releases to work properly.
# In lower environments (dev, test, sandbox), the client will operate as a no-op.
config :ysc, :flowroute,
  access_key: System.get_env("FLOWROUTE_ACCESS_KEY"),
  secret_key: System.get_env("FLOWROUTE_SECRET_KEY"),
  from_number: System.get_env("FLOWROUTE_FROM_NUMBER")

# ## Email Address Configuration
#
# Configure email addresses for outgoing emails and contact information.
# These can be set via environment variables at runtime for all environments.
# All values are optional and will fall back to defaults from config.exs if not set.
config :ysc, :emails,
  from_email: System.get_env("EMAIL_FROM") || "noreply@ysc.org",
  from_name: System.get_env("EMAIL_FROM_NAME") || "YSC",
  contact_email: System.get_env("EMAIL_CONTACT") || "info@ysc.org",
  admin_email: System.get_env("EMAIL_ADMIN") || "admin@ysc.org",
  membership_email: System.get_env("EMAIL_MEMBERSHIP") || "membership@ysc.org",
  board_email: System.get_env("EMAIL_BOARD") || "board@ysc.org",
  volunteer_email: System.get_env("EMAIL_VOLUNTEER") || "volunteer@ysc.org",
  tahoe_email: System.get_env("EMAIL_TAHOE") || "tahoe@ysc.org",
  clear_lake_email: System.get_env("EMAIL_CLEAR_LAKE") || "cl@ysc.org"

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ysc start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ysc, YscWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ysc, Ysc.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
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
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ysc, YscWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind on all interfaces (0.0.0.0) to be reachable by fly-proxy
      # This is required for Fly.io deployments
      # For IPv6, use {0, 0, 0, 0, 0, 0, 0, 0}
      # For local network only, use {127, 0, 0, 1} or {0, 0, 0, 0, 0, 0, 0, 1}
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    render_errors: [
      formats: [html: YscWeb.ErrorHTML, json: YscWeb.ErrorJSON],
      layout: {YscWeb.Layouts, :error}
    ]

  config :ysc, dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")

  config :phoenix_turnstile,
    site_key: System.fetch_env!("TURNSTILE_SITE_KEY"),
    secret_key: System.fetch_env!("TURNSTILE_SECRET_KEY")

  # Wax (WebAuthn) configuration for production
  #
  # RP ID (Relying Party ID) determines which domains can share passkeys.
  # WebAuthn is strictly bound to a single domain - passkeys registered on one domain
  # cannot be used on a different domain unless they share the same RP ID.
  #
  # For subdomain sharing (e.g., app.ysc.org, api.ysc.org, www.ysc.org):
  #   Set WEBAUTHN_RP_ID environment variable to the base domain: "ysc.org"
  #   This allows passkeys registered on any subdomain to work on all subdomains
  #
  # For separate domains (e.g., ysc-sandbox.fly.dev vs ysc.org):
  #   Use the full hostname as RP ID (default behavior)
  #   Each domain will have its own separate passkeys
  #
  # Default: Uses PHX_HOST value (e.g., "ysc-sandbox.fly.dev" or "ysc.org")
  # Override: Set WEBAUTHN_RP_ID environment variable to customize
  rp_id = System.get_env("WEBAUTHN_RP_ID") || host
  origin = "https://#{host}"

  config :wax_,
    rp_id: rp_id,
    origin: origin,
    attestation: "none"

  # ## Stripe Configuration
  #
  # Configure Stripe API keys for production.
  # These must be set at runtime for releases to work properly.
  stripe_secret = System.get_env("STRIPE_SECRET")
  stripe_public_key = System.get_env("STRIPE_PUBLIC_KEY")
  stripe_webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET")

  if stripe_secret && stripe_public_key && stripe_webhook_secret do
    config :stripity_stripe,
      api_key: stripe_secret,
      public_key: stripe_public_key,
      webhook_secret: stripe_webhook_secret
  else
    raise """
    Missing Stripe credentials. Please set:
    - STRIPE_SECRET
    - STRIPE_PUBLIC_KEY
    - STRIPE_WEBHOOK_SECRET
    """
  end

  # ## Membership Plans Configuration
  #
  # Configure membership plans with Stripe Price IDs for production.
  # These must be set at runtime for releases to work properly.
  stripe_single_price_id = System.get_env("STRIPE_SINGLE_PRICE_ID")
  stripe_family_price_id = System.get_env("STRIPE_FAMILY_PRICE_ID")

  if stripe_single_price_id && stripe_family_price_id do
    config :ysc,
      membership_plans: [
        %{
          id: :single,
          name: "Single",
          interval: "year",
          amount: 45,
          currency: "usd",
          trial_period_days: 0,
          stripe_price_id: stripe_single_price_id,
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
          stripe_price_id: stripe_family_price_id,
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
  else
    raise """
    Missing Stripe Price IDs. Please set:
    - STRIPE_SINGLE_PRICE_ID
    - STRIPE_FAMILY_PRICE_ID
    """
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ysc, YscWeb.Endpoint,
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
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :ysc, YscWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :ysc, Ysc.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # ## Mailer Configuration (AWS SES)
  #
  # Configure Swoosh to use Amazon SES for sending emails in production.
  # The adapter expects `access_key` and `secret` (not `access_key_id` and `secret_access_key`).
  ses_access_key =
    System.get_env("SES_AWS_ACCESS_KEY_ID") ||
      System.get_env("AWS_ACCESS_KEY_ID")

  ses_secret_key =
    System.get_env("SES_AWS_SECRET_ACCESS_KEY") ||
      System.get_env("AWS_SECRET_ACCESS_KEY")

  if ses_access_key && ses_secret_key do
    config :ysc, Ysc.Mailer,
      adapter: Swoosh.Adapters.AmazonSES,
      region: System.get_env("SES_AWS_REGION") || "us-west-1",
      access_key: ses_access_key,
      secret: ses_secret_key
  else
    raise """
    Missing AWS SES credentials. Please set either:
    - SES_AWS_ACCESS_KEY_ID and SES_AWS_SECRET_ACCESS_KEY, or
    - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
    """
  end

  # ## S3 Configuration (Tigris)
  #
  # Configure Tigris storage settings (S3-compatible) based on environment variables.
  # For production: Uses Tigris endpoint (https://fly.storage.tigris.dev)
  # Object URLs use virtual-hosted style: https://<bucket-name>.fly.storage.tigris.dev/key
  # Set BUCKET_NAME, AWS_REGION (defaults to "auto" for Tigris), and optionally AWS_ENDPOINT_URL_S3
  # If AWS_ENDPOINT_URL_S3 is not set, defaults to Tigris endpoint.
  s3_bucket = System.get_env("BUCKET_NAME") || "media"
  s3_region = System.get_env("AWS_REGION") || "auto"

  s3_base_url =
    System.get_env("AWS_ENDPOINT_URL_S3") || "https://fly.storage.tigris.dev"

  # Store S3 config for application use
  expense_reports_bucket =
    System.get_env("EXPENSE_REPORTS_BUCKET_NAME") || "expense-reports"

  config :ysc,
    s3_bucket: s3_bucket,
    s3_region: s3_region,
    s3_base_url: s3_base_url,
    expense_reports_s3_bucket: expense_reports_bucket,
    aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

  # Configure ExAws for S3 access to Tigris
  # Following Tigris documentation format
  # IMPORTANT: These credentials are used for ALL S3 operations including:
  # - Media bucket uploads/downloads
  # - Expense reports bucket uploads/downloads
  # Ensure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY have appropriate permissions:
  # - Read/Write access to the media bucket
  # - Read/Write access to the expense-reports bucket
  config :ex_aws,
    debug_requests: false,
    json_codec: Jason,
    access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
    secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}

  # Configure ExAws S3 endpoint
  # Dev/Test: Uses localstack
  # Production: Uses Tigris endpoint (fly.storage.tigris.dev for Fly, or t3.storage.dev for general Tigris)
  ex_aws_s3_config =
    cond do
      # Local development with localstack
      config_env() in [:dev, :test] ->
        [
          scheme: "http://",
          host: "media.s3.localhost.localstack.cloud",
          port: "4566"
        ]

      # Production - use Tigris endpoint
      true ->
        uri = URI.parse(s3_base_url)

        # Extract hostname (e.g., "fly.storage.tigris.dev" from "https://fly.storage.tigris.dev")
        host = uri.host || "fly.storage.tigris.dev"

        [
          scheme: "https://",
          host: host,
          region: s3_region
        ]
        |> Enum.concat(if uri.port, do: [port: uri.port], else: [])
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
    end

  config :ex_aws, :s3, ex_aws_s3_config

  # Discord alerts configuration
  config :ysc, Ysc.Alerts.Discord,
    webhook_url: System.fetch_env!("DISCORD_WEBHOOK_URL"),
    enabled: true

  # ## Native iOS API Key Configuration
  #
  # Configure API key for native iOS app authentication.
  # This key is used to validate requests from the iOS app.
  # Set via NATIVE_API_KEY environment variable.
  config :ysc, :native_api_key, System.get_env("NATIVE_API_KEY")

  # ## Cloak Encryption Configuration
  #
  # Configure Cloak encryption key for production.
  # Generate a key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
  # The vault is configured in lib/ysc/vault.ex using the init/1 callback
  # to read from the CLOAK_ENCRYPTION_KEY environment variable.
  _cloak_key =
    System.get_env("CLOAK_ENCRYPTION_KEY") ||
      raise """
      Missing CLOAK_ENCRYPTION_KEY environment variable.
      Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """

  # ## OAuth Configuration
  #
  # Configure OAuth providers (Google and Facebook) for production.
  # These must be set at runtime for releases to work properly.
  google_client_id = System.get_env("GOOGLE_CLIENT_ID")
  google_client_secret = System.get_env("GOOGLE_CLIENT_SECRET")
  facebook_client_id = System.get_env("FACEBOOK_CLIENT_ID")
  facebook_client_secret = System.get_env("FACEBOOK_CLIENT_SECRET")

  if google_client_id && google_client_secret do
    config :ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: google_client_id,
      client_secret: google_client_secret
  end

  if facebook_client_id && facebook_client_secret do
    config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
      client_id: facebook_client_id,
      client_secret: facebook_client_secret
  end

  # ## QuickBooks Configuration
  #
  # Configure QuickBooks API settings for production.
  # These must be set at runtime for releases to work properly.
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
end
