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

# Stripe — `payout.paid` webhooks create ledger payouts unless disabled here.
# Set STRIPE_PROCESS_PAYOUT_WEBHOOKS to false, 0, no, or off (case-insensitive) while another
# system handles the same Stripe account (e.g. legacy site); unset means enabled.
# Not applied in :test so `mix test` stays stable when the shell or .env disables payouts.
if config_env() != :test do
  process_stripe_payout_webhooks =
    case System.get_env("STRIPE_PROCESS_PAYOUT_WEBHOOKS") do
      nil -> true
      "" -> true
      v -> String.downcase(String.trim(v)) not in ["false", "0", "no", "off"]
    end

  config :ysc, process_stripe_payout_webhooks: process_stripe_payout_webhooks
end

# stripity_stripe sends Connection: keep-alive, which hackney 4.x rejects with
# :protocol_error. Route all Stripe API calls through Req (see Ysc.Stripe.HttpClient).
config :stripity_stripe,
  http_module: Ysc.Stripe.HttpClient,
  use_connection_pool: false

# ## FlowRoute SMS Configuration
#
# Configure FlowRoute API settings for all environments at runtime.
# These must be set at runtime for releases to work properly.
# In lower environments (dev, test, sandbox), the client will operate as a no-op.
# Not applied in :test so `mix test` keeps config/test.exs's fixed from_number
# and webhook_token instead of resetting them to nil when the FLOWROUTE_* env
# vars aren't set in the shell/CI.
if config_env() != :test do
  config :ysc, :flowroute,
    access_key: System.get_env("FLOWROUTE_ACCESS_KEY"),
    secret_key: System.get_env("FLOWROUTE_SECRET_KEY"),
    from_number: System.get_env("FLOWROUTE_FROM_NUMBER"),
    webhook_token: System.get_env("FLOWROUTE_WEBHOOK_TOKEN")
end

# Radar Maps — publishable key must be resolved at runtime so release builds pick up RADAR_PUBLIC_KEY
# from the host (Fly secrets, etc.). Reading it only in config.exs would bake in the dev default at compile time.
config :ysc, :radar,
  public_key:
    System.get_env(
      "RADAR_PUBLIC_KEY",
      "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966"
    )

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
  membership_email: System.get_env("EMAIL_MEMBERSHIP") || "memberships@ysc.org",
  board_email: System.get_env("EMAIL_BOARD") || "board@ysc.org",
  volunteer_email: System.get_env("EMAIL_VOLUNTEER") || "volunteer@ysc.org",
  tahoe_email: System.get_env("EMAIL_TAHOE") || "tahoe@ysc.org",
  clear_lake_email: System.get_env("EMAIL_CLEAR_LAKE") || "cl@ysc.org"

# OpenRouter — optional; powers admin help guide finder and step clarifier
config :ysc, :open_router,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  model: System.get_env("OPENROUTER_MODEL") || "deepseek/deepseek-v4-flash",
  referer: System.get_env("OPENROUTER_REFERER")

# ## Apple Wallet Configuration
#
# Configure Apple Wallet pass generation for event tickets and membership cards.
# Certificates must be base64-encoded PEM files (generate with: base64 -w0 certificate.pem).
# All values are optional — if not set, the "Add to Wallet" buttons are hidden.
config :ysc, :apple_wallet,
  team_id: System.get_env("APPLE_WALLET_TEAM_ID"),
  org_name: System.get_env("APPLE_WALLET_ORG_NAME"),
  ticket: %{
    cert_pem_b64: System.get_env("APPLE_WALLET_TICKET_CERT_PEM_B64"),
    key_pem_b64: System.get_env("APPLE_WALLET_TICKET_KEY_PEM_B64"),
    key_password: System.get_env("APPLE_WALLET_TICKET_KEY_PASSWORD"),
    pass_type_id: System.get_env("APPLE_WALLET_TICKET_PASS_TYPE_ID")
  },
  membership: %{
    cert_pem_b64: System.get_env("APPLE_WALLET_MEMBERSHIP_CERT_PEM_B64"),
    key_pem_b64: System.get_env("APPLE_WALLET_MEMBERSHIP_KEY_PEM_B64"),
    key_password: System.get_env("APPLE_WALLET_MEMBERSHIP_KEY_PASSWORD"),
    pass_type_id: System.get_env("APPLE_WALLET_MEMBERSHIP_PASS_TYPE_ID")
  }

# ## Google Wallet Configuration
#
# Configure Google Wallet pass generation for event tickets and membership cards.
# Use the full JSON content of the Google service account key file.
# All values are optional — if not set, the "Add to Google Wallet" buttons are hidden.
config :ysc, :google_wallet,
  credentials_json: System.get_env("GOOGLE_WALLET_CREDENTIALS_JSON"),
  issuer_id: System.get_env("GOOGLE_WALLET_ISSUER_ID")

# ## Google Photos (admin OAuth integration)
config :ysc, :google_photos,
  client_id: System.get_env("GOOGLE_PHOTOS_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_PHOTOS_CLIENT_SECRET"),
  redirect_uri: System.get_env("GOOGLE_PHOTOS_REDIRECT_URI")

# Outbound admin link to the standalone Query Console app.
if query_console_url = System.get_env("QUERY_CONSOLE_URL") do
  if query_console_url != "" do
    config :ysc, :query_console_url, query_console_url
  end
end

# ## First-party OAuth clients (Query Console and future apps)
# QUERY_CONSOLE_SSO_* registers the Query Console client into :oauth_clients.
# Only override when QUERY_CONSOLE_SSO_CLIENT_ID is set so test/dev defaults remain.
if System.get_env("QUERY_CONSOLE_SSO_CLIENT_ID") do
  query_console_redirect_uris =
    (System.get_env("QUERY_CONSOLE_SSO_REDIRECT_URIS") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  client_id = System.get_env("QUERY_CONSOLE_SSO_CLIENT_ID")

  post_logout_redirect_uris =
    (System.get_env("QUERY_CONSOLE_SSO_POST_LOGOUT_REDIRECT_URIS") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  clients =
    Map.put(Application.get_env(:ysc, :oauth_clients, %{}), client_id, %{
      client_secret: System.get_env("QUERY_CONSOLE_SSO_CLIENT_SECRET"),
      redirect_uris: query_console_redirect_uris,
      post_logout_redirect_uris: post_logout_redirect_uris,
      roles: [:admin],
      states: [:active]
    })

  config :ysc, :oauth_clients, clients
end

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
  # Sentry reads config when the :sentry app starts (after this file runs). Use runtime
  # env so the Sentry UI matches Fly [env] (ENVIRONMENT=production), not Mix :prod.
  config :sentry,
    environment_name:
      System.get_env("SENTRY_ENVIRONMENT") ||
        System.get_env("ENVIRONMENT") ||
        System.get_env("APP_ENV") ||
        "production",
    release:
      System.get_env("SENTRY_RELEASE") ||
        System.get_env("BUILD_VERSION") ||
        to_string(Application.spec(:ysc, :vsn) || "unknown")

  # Fly.io `release_command` runs e.g. `/app/bin/migrate` in a one-off machine before
  # app VMs update. That process still loads this file, but only needs Repo + Endpoint.
  # Set `RELEASE_COMMAND=1` for the migrate step only (see fly-*.toml) so deploys are not
  # blocked on every integration secret (Stripe, SES, …) being present before first migrate.
  fly_release_command? =
    case System.get_env("RELEASE_COMMAND") do
      nil -> false
      "" -> false
      _ -> true
    end

  database_url =
    System.get_env("DATABASE_URL") ||
      if !fly_release_command?,
        do:
          raise("""
          environment variable DATABASE_URL is missing.
          For example: ecto://USER:PASS@HOST/DATABASE
          """)

  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Unmanaged Fly Postgres: direct connection to Postgres (no PgBouncer). Each pool connection = one Postgres connection.
  config :ysc, Ysc.Repo,
    url: database_url,
    # Total DB connections = POOL_SIZE × app machines; unmanaged Postgres max_connections is 300
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    # Unmanaged Fly Postgres on the private network (.internal) typically does not use TLS; ssl: true causes "ssl connect: closed"
    # Wait longer for a connection when pool is busy (reduces "connection not available" under burst load)
    queue_target: 15_000,
    queue_interval: 1_000,
    # Allow time for DB to respond (e.g. cold start on Fly)
    connect_timeout: 15_000

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      if !fly_release_command?,
        do:
          raise("""
          environment variable SECRET_KEY_BASE is missing.
          You can generate one by calling: mix phx.gen.secret
          """)

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ysc, YscWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://#{host}"],
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
      root_layout: {YscWeb.Layouts, :error},
      layout: false
    ]

  config :ysc, dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")

  # S3 + ExAws: always applied for prod (including release_command one-offs). This must not
  # live only inside `unless fly_release_command?`: if RELEASE_COMMAND were set on app VMs, or
  # the optional block were skipped, `s3_avatars_public_url` / `avatars_s3_bucket` would be
  # missing and uploads would fall back to https://avatars.fly.storage.tigris.dev (wrong bucket).
  s3_bucket = System.get_env("BUCKET_NAME") || "media"
  s3_region = System.get_env("AWS_REGION") || "auto"

  s3_base_url =
    System.get_env("AWS_ENDPOINT_URL_S3") || "https://fly.storage.tigris.dev"

  trim_public_s3_url = fn
    nil ->
      nil

    "" ->
      nil

    url ->
      case url |> String.trim() |> String.trim_trailing("/") do
        "" -> nil
        trimmed -> trimmed
      end
  end

  s3_media_public_url =
    trim_public_s3_url.(System.get_env("S3_MEDIA_PUBLIC_BASE_URL"))

  s3_avatars_public_url =
    trim_public_s3_url.(System.get_env("S3_AVATARS_PUBLIC_BASE_URL"))

  s3_expense_reports_public_url =
    trim_public_s3_url.(System.get_env("S3_EXPENSE_REPORTS_PUBLIC_BASE_URL"))

  s3_use_custom_domain =
    System.get_env("S3_USE_CUSTOM_DOMAIN") in ~w(true 1 yes)

  sandbox? =
    System.get_env("ENVIRONMENT") == "sandbox" ||
      System.get_env("APP_ENV") == "sandbox"

  # Headless Chrome for TV poster capture. Disabled only when CHROMIC_PDF_ENABLED is explicitly
  # false (e.g. local prod release without Chromium). Docker images ship with Chromium on Alpine.
  chromic_pdf_enabled =
    case System.get_env("CHROMIC_PDF_ENABLED") do
      nil -> true
      v -> String.downcase(String.trim(v)) not in ["false", "0", "no", "off"]
    end

  config :ysc, :chromic_pdf_enabled, chromic_pdf_enabled

  if chromic_pdf_enabled do
    config :ysc, ChromicPDF,
      chrome_executable:
        System.get_env("CHROME_EXECUTABLE") || "/usr/bin/chromium-browser"
  else
    config :ysc, :tv_poster_image_module, Ysc.Events.TvPosterImage.ErrorStub
  end

  missing_public =
    [
      {"S3_MEDIA_PUBLIC_BASE_URL", s3_media_public_url},
      {"S3_AVATARS_PUBLIC_BASE_URL", s3_avatars_public_url},
      {"S3_EXPENSE_REPORTS_PUBLIC_BASE_URL", s3_expense_reports_public_url}
    ]
    |> Enum.filter(fn {_, v} -> v in [nil, ""] end)
    |> Enum.map(&elem(&1, 0))

  # Release command (migrate/seed) may run before all secrets exist; full VMs must have URLs.
  if not sandbox? and not fly_release_command? and missing_public != [] do
    raise """
    Non-sandbox production requires custom public origins for all S3 buckets so clients use HTTPS hosts you control (CORS, CSP), not only *.fly.storage.tigris.dev. \
    Set in etc/fly/fly-prod.toml [env] or fly secrets: #{Enum.join(missing_public, ", ")}. \
    With S3_USE_CUSTOM_DOMAIN=true, uploads and object URLs require these (see S3Config). \
    Remove empty secret overrides if they hide [env] values. \
    """
  end

  expense_reports_bucket =
    System.get_env("EXPENSE_REPORTS_BUCKET_NAME") || "expense-reports"

  app_resources_bucket =
    System.get_env("APP_RESOURCES_BUCKET_NAME") || "app-resources"

  avatars_bucket =
    case System.get_env("AVATARS_BUCKET_NAME") do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        if config_env() == :prod,
          do:
            raise(
              "AVATARS_BUCKET_NAME environment variable is required in production"
            ),
          else: "avatars"
    end

  config :ysc,
    s3_bucket: s3_bucket,
    s3_region: s3_region,
    s3_base_url: s3_base_url,
    s3_media_public_url: s3_media_public_url,
    s3_avatars_public_url: s3_avatars_public_url,
    s3_expense_reports_public_url: s3_expense_reports_public_url,
    s3_use_custom_domain: s3_use_custom_domain,
    expense_reports_s3_bucket: expense_reports_bucket,
    app_resources_s3_bucket: app_resources_bucket,
    avatars_s3_bucket: avatars_bucket,
    aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

  config :ex_aws,
    debug_requests: false,
    json_codec: Jason,
    access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
    secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}

  uri = URI.parse(s3_base_url)
  s3_scheme = (uri.scheme || "https") <> "://"
  s3_host = uri.host || "fly.storage.tigris.dev"

  # Tigris requires virtual-hosted-style addressing (https://<bucket>.<host>/<key>)
  # and rejects path-style requests (https://<host>/<bucket>/<key>) with 405 —
  # ExAws.Operation.S3 defaults to path-style unless `virtual_host: true` is set
  # (see ExAws.Operation.S3.add_bucket_to_path/2). Without this, every plain
  # ExAws.S3 operation (get_object, delete_object, head_object, download_file)
  # fails against Tigris; S3Config's own upload-URL helpers already know this
  # (see tigris_bucket_virtual_host_url/1) but that never reached this config.
  normalized_s3_host = s3_host |> String.downcase() |> String.trim_trailing(".")

  s3_virtual_host? =
    normalized_s3_host == "tigris.dev" or
      String.ends_with?(normalized_s3_host, ".tigris.dev")

  ex_aws_s3_config =
    [
      scheme: s3_scheme,
      host: s3_host,
      region: s3_region
    ]
    |> Enum.concat(if uri.port, do: [port: uri.port], else: [])
    |> Enum.concat(if s3_virtual_host?, do: [virtual_host: true], else: [])
    |> Enum.reject(fn {_, v} -> is_nil(v) end)

  config :ex_aws, :s3, ex_aws_s3_config

  # ## Mailer (AWS SES) — always configured in production (not only when RELEASE_COMMAND is unset).
  #
  # `config/config.exs` defaults `Ysc.Mailer` to `Swoosh.Adapters.Local`. `config/prod.exs` sets
  # `swoosh local: false`, which does not start the Local storage GenServer, so using the Local
  # adapter raises (Oban) ** (exit) no process. The former layout applied SES only inside
  # `unless fly_release_command?`; any code path that skipped that block (e.g. a one-off, or
  # mis-set env) left the mailer on Local. Resolve SES the same way as S3: shared AWS creds
  # when present; for Fly release_command (migrate/seed) without keys, use Test instead of Local.
  ses_access_key =
    System.get_env("SES_AWS_ACCESS_KEY_ID") ||
      System.get_env("AWS_ACCESS_KEY_ID")

  ses_secret_key =
    System.get_env("SES_AWS_SECRET_ACCESS_KEY") ||
      System.get_env("AWS_SECRET_ACCESS_KEY")

  cond do
    is_binary(ses_access_key) and ses_access_key != "" and
      is_binary(ses_secret_key) and
        ses_secret_key != "" ->
      config :ysc, Ysc.Mailer,
        adapter: Swoosh.Adapters.AmazonSES,
        region: System.get_env("SES_AWS_REGION") || "us-west-1",
        access_key: ses_access_key,
        secret: ses_secret_key

    fly_release_command? ->
      config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Test

    true ->
      raise """
      Missing AWS SES credentials. Please set either:
      - SES_AWS_ACCESS_KEY_ID and SES_AWS_SECRET_ACCESS_KEY, or
      - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
      """
  end

  config :ysc, :ses_configuration_set, System.get_env("SES_CONFIGURATION_SET")

  sns_allowed_topic_arns =
    (System.get_env("SNS_TOPIC_ARN") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :ysc, :sns_allowed_topic_arns, sns_allowed_topic_arns

  ses_max_send_rate =
    case Integer.parse(String.trim(System.get_env("SES_MAX_SEND_RATE") || "")) do
      {rate, _} when rate > 0 -> rate
      _ -> 10
    end

  newsletter_send_rate =
    case Integer.parse(
           String.trim(System.get_env("NEWSLETTER_SEND_RATE") || "")
         ) do
      {rate, _} when rate > 0 -> min(rate, max(ses_max_send_rate - 2, 1))
      _ -> min(8, max(ses_max_send_rate - 2, 1))
    end

  config :ysc,
    ses_region: System.get_env("SES_AWS_REGION") || "us-west-1",
    ses_max_send_rate: ses_max_send_rate,
    ses_rate_window_seconds: 1,
    newsletter_send_interval_ms: Integer.ceil_div(1_000, newsletter_send_rate),
    email_delivery_retry_window_seconds: 48 * 60 * 60

  # Wax (WebAuthn): no third-party API keys (only `PHX_HOST` and optional `WEBAUTHN_RP_ID`).
  # Apply for every prod process including `RELEASE_COMMAND=1` so we never fall back to
  # dev-style defaults in `user_login_live` / `passkey_registration_live` if the block below
  # were skipped (same class of issue as Local mailer + `swoosh local: false`).
  webauthn_rp_id = System.get_env("WEBAUTHN_RP_ID") || host
  webauthn_origin = "https://#{host}"

  config :wax_,
    rp_id: webauthn_rp_id,
    origin: webauthn_origin,
    attestation: "none"

  # Kiosk + mobile API rate limit: optional env only; safe for migrate/seed VMs.
  config :ysc, :kiosk_api_key, System.get_env("KIOSK_API_KEY")

  config :ysc, Ysc.MobileAPIRateLimit, ip_limit: 120

  # Skipped for `RELEASE_COMMAND=1` (Fly release_command) so first-time deploys are not
  # blocked on every integration secret. S3, SES, mailer, and Wax are configured above;
  # this block holds things that `fetch_env!/1`, raise, or are optional OAuth.
  config :phoenix_turnstile,
    site_key: System.fetch_env!("TURNSTILE_SITE_KEY"),
    secret_key: System.fetch_env!("TURNSTILE_SECRET_KEY")

  # ## Stripe Configuration
  #
  # Configure Stripe API keys for production.
  # These must be set at runtime for releases to work properly.
  stripe_secret = System.get_env("STRIPE_SECRET")
  stripe_public_key = System.get_env("STRIPE_PUBLIC_KEY")
  stripe_webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET")

  config :stripity_stripe,
    api_key: stripe_secret,
    public_key: stripe_public_key,
    webhook_secret: stripe_webhook_secret,
    http_module: Ysc.Stripe.HttpClient,
    use_connection_pool: false

  # Stripe Terminal location the admin/volunteer mobile app's tap-to-pay
  # connection tokens are scoped to. Created once via the Stripe
  # Dashboard/API (a Terminal `Location` object).
  config :ysc,
         :stripe_terminal_location_id,
         System.get_env("STRIPE_TERMINAL_LOCATION_ID")

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

    # Discord alerts configuration
    config :ysc, Ysc.Alerts.Discord,
      webhook_url: System.fetch_env!("DISCORD_WEBHOOK_URL"),
      enabled: true

    # ## Cloak Encryption Configuration
    #
    # Configure Cloak encryption key for production.
    # Generate a key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
    # The vault is configured in lib/ysc/vault.ex using the init/1 callback
    # to read from the CLOAK_ENCRYPTION_KEY environment variable.
    _cloak_key =
      System.get_env("CLOAK_ENCRYPTION_KEY") ||
        if !fly_release_command?,
          do:
            raise("""
            Missing CLOAK_ENCRYPTION_KEY environment variable.
            Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
            """)

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
      webhook_verifier_token:
        System.get_env("QUICKBOOKS_WEBHOOK_VERIFIER_TOKEN"),
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
      # Balance-sheet account for Stripe minimum-balance reserve holds/releases
      # on payout Deposits. Falls back to stripe_account_id when unset.
      stripe_reserve_account_id:
        System.get_env("QUICKBOOKS_STRIPE_RESERVE_ACCOUNT_ID"),
      stripe_reserve_account_name:
        System.get_env("QUICKBOOKS_STRIPE_RESERVE_ACCOUNT_NAME"),
      stripe_fees_account_id:
        System.get_env("QUICKBOOKS_STRIPE_FEES_ACCOUNT_ID"),
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
      # Optional: QuickBooks Customer ID for payments with no user (avoids :user_not_found on payouts)
      system_customer_id: System.get_env("QUICKBOOKS_SYSTEM_CUSTOMER_ID")
  end
end

# ## GeoIP configuration
#
# Deployed environments (sandbox/production) load GeoLite2-City from the shared
# `ysc-app-resources` S3 bucket via Ysc.GeoIP.DatabaseFetcher. The weekly GitHub
# Actions workflow `.github/workflows/sync-geoip-database.yml` downloads from
# MaxMind and uploads `geoip/GeoLite2-City.tar.gz`. Keep MAXMIND_LICENSE_KEY in
# GitHub Actions secrets only — do not set it on Fly app machines.
# See Ysc.Application.maybe_start_geo_ip_loader/0.
