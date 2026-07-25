defmodule Ysc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Resolved at compile time; Mix is not available in releases.
  @env Mix.env()

  @dialyzer {:nowarn_function, start: 2}

  @impl true
  def start(_type, _args) do
    # Ensures Stripe uses Req even if an older release omitted http_module in config.
    Application.put_env(:stripity_stripe, :http_module, Ysc.Stripe.HttpClient)
    Application.put_env(:stripity_stripe, :use_connection_pool, false)

    # Req 0.6+ disables automatic gzip/brotli/zstd decompression by default; keep prior
    # behavior for external API and asset downloads (Google, GitHub, SNS certs, etc.).
    Req.default_options(compressed: true)

    :logger.add_handler(:ysc_sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        capture_metadata: [:file, :line],
        # Most call sites use Ysc.Logging.error/2 without an :error struct; still report
        # those Logger.error lines to Sentry (crashes were already captured by default).
        capture_log_messages: true,
        capture_level: :error
      }
    })

    maybe_start_geo_ip_loader()

    # Add shutdown task for sandbox environment only
    base_children =
      [
        # Start the Vault for encryption
        Ysc.Vault,
        # Start the Telemetry supervisor
        YscWeb.Telemetry,
        # Start the Ecto repository
        Ysc.Repo,
        # Start the PubSub system
        {Phoenix.PubSub, name: Ysc.PubSub},
        # Start DNS cluster to cluster the app
        {DNSCluster,
         query: Application.get_env(:ysc, :dns_cluster_query) || :ignore},
        # Start Finch
        {Finch, name: Ysc.Finch},
        # Start cache
        {Cachex, name: :ysc_cache},
        # Warm site settings cache on boot (avoids cold DB hits on public pages)
        {Ysc.Settings, []},
        # Auth rate limiting (credential stuffing protection)
        {Ysc.AuthRateLimit, [clean_period: :timer.minutes(1)]},
        # Newsletter rate limiting (bot protection)
        {Ysc.NewsletterRateLimit, [clean_period: :timer.minutes(1)]},
        # QR scan rate limiting (brute-force protection)
        {Ysc.ScanRateLimit, [clean_period: :timer.minutes(1)]},
        # Email verification code brute-force protection (account setup)
        {Ysc.EmailVerificationRateLimit, [clean_period: :timer.minutes(1)]},
        # Kiosk `/api/v1/mobile` JSON API (per-IP abuse / scraping)
        {Ysc.MobileAPIRateLimit, [clean_period: :timer.minutes(1)]},
        # Admin help LLM (guide finder + step clarifier)
        {Ysc.AdminHelpRateLimit, [clean_period: :timer.minutes(1)]},
        # Start Apple Wallet certificate manager
        Ysc.AppleWallet.CertManager,
        # Start Google Wallet credentials manager
        Ysc.GoogleWallet.Credentials,
        # Google Photos OAuth token cache
        Ysc.GooglePhotos.TokenStore,
        # Task supervisor for fire-and-forget async work (e.g. OAuth avatar sync)
        {Task.Supervisor, name: Ysc.TaskSupervisor}
      ] ++
        chromic_pdf_children() ++
        [
          # Start the Endpoint (http/https)
          YscWeb.Endpoint,
          # Start a worker by calling: Ysc.Worker.start_link(arg)
          # {Ysc.Worker, arg}
          {Oban, Application.fetch_env!(:ysc, Oban)}
        ]

    # Start Goth (Google OAuth2 token server) only when Google Wallet is configured
    base_children =
      base_children ++ Ysc.GoogleWallet.Credentials.goth_child_spec()

    # PromEx periodically polls metrics (including DB-backed plugins). In tests, this can
    # generate noisy ownership errors due to the SQL sandbox.
    base_children =
      if @env == :test do
        base_children
      else
        base_children ++ [Ysc.PromEx]
      end

    children =
      base_children ++
        if sandbox_environment?() do
          [{Task, fn -> shutdown_when_inactive(:timer.minutes(10)) end}]
        else
          []
        end

    # Newsletter disposable-domain checks use a named public ETS table. Load it
    # before accepting HTTP traffic: the supervision tree includes Endpoint, so
    # starting the supervisor first would allow requests that hit
    # `EmailValidator.validate_email/1` to crash with ArgumentError from
    # `:ets.lookup/2` while the table is still missing.
    Ysc.Newsletter.EmailValidator.init_ets_table()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ysc.Supervisor]

    supervisor =
      case Supervisor.start_link(children, opts) do
        {:ok, sup} ->
          sup

        {:error, reason} ->
          raise "failed to start Ysc.Supervisor: #{inspect(reason)}"
      end

    # Start the outage scraper scheduler
    Ysc.PropertyOutages.Scheduler.start_scheduler()

    # Start the expense report QuickBooks sync scheduler
    Ysc.ExpenseReports.Scheduler.start_scheduler()

    # Start the ticket timeout scheduler
    Ysc.Tickets.Scheduler.start_scheduler()

    if @env != :test do
      Ysc.GooglePhotos.maybe_seed_from_env()
    end

    {:ok, supervisor}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YscWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Check if we're running in the sandbox environment
  defp sandbox_environment? do
    System.get_env("ENVIRONMENT", "development") |> String.downcase() ==
      "sandbox"
  end

  defp chromic_pdf_children do
    if Application.get_env(:ysc, :chromic_pdf_enabled, true) do
      [{ChromicPDF, Application.get_env(:ysc, ChromicPDF, [])}]
    else
      []
    end
  end

  defp maybe_start_geo_ip_loader do
    if Ysc.GeoIP.configured?() and Ysc.Env.deployed?() and
         Code.ensure_loaded?(:locus) do
      :locus.start_loader(:city, {:maxmind, "GeoLite2-City"})
    end
  end

  # Shuts down the application if no active HTTP connections are found.
  # This supports "scale to 0" on fly.io for the sandbox environment.
  defp shutdown_when_inactive(every_ms) do
    Process.sleep(every_ms)

    if :ranch.procs(YscWeb.Endpoint.HTTP, :connections) == [] do
      System.stop(0)
    else
      shutdown_when_inactive(every_ms)
    end
  end
end
