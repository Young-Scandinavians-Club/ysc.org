defmodule Ysc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Resolved at compile time; Mix is not available in releases.
  @env Mix.env()

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:ysc_sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    # Add shutdown task for sandbox environment only
    base_children = [
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
      # Auth rate limiting (credential stuffing protection)
      {Ysc.AuthRateLimit, [clean_period: :timer.minutes(1)]},
      # Start verification code cache
      Ysc.VerificationCache,
      # Start the Endpoint (http/https)
      YscWeb.Endpoint,
      # Start a worker by calling: Ysc.Worker.start_link(arg)
      # {Ysc.Worker, arg}
      {Oban, Application.fetch_env!(:ysc, Oban)}
    ]

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

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ysc.Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # Start the outage scraper scheduler
    Ysc.PropertyOutages.Scheduler.start_scheduler()

    # Start the expense report QuickBooks sync scheduler
    Ysc.ExpenseReports.Scheduler.start_scheduler()

    # Start the ticket timeout scheduler
    Ysc.Tickets.Scheduler.start_scheduler()

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
