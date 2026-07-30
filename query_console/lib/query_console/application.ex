defmodule QueryConsole.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        QueryConsoleWeb.Telemetry,
        QueryConsole.Repo,
        QueryConsole.AnalyticsRepo,
        {DNSCluster, query: Application.get_env(:query_console, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: QueryConsole.PubSub},
        {Registry, keys: :unique, name: QueryConsole.Runner.Registry},
        QueryConsole.Catalog,
        QueryConsole.Runner.Supervisor,
        QueryConsoleWeb.Endpoint
      ] ++ idle_shutdown_child()

    opts = [strategy: :one_for_one, name: QueryConsole.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    QueryConsoleWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Scale-to-zero on Fly Machines: exit cleanly when no HTTP/LiveView clients
  # remain so the VM stops. Fly wakes it again on the next request.
  # Bandit variant of https://fly.io/phoenix-files/shut-down-idle-phoenix-app/
  defp idle_shutdown_child do
    case Application.get_env(:query_console, :shutdown_when_inactive_ms) do
      ms when is_integer(ms) and ms > 0 ->
        [{Task, fn -> shutdown_when_inactive(ms) end}]

      _ ->
        []
    end
  end

  defp shutdown_when_inactive(every_ms) do
    Process.sleep(every_ms)

    # Double-check after a short gap so a fleeting Fly /up health check does not
    # keep the Machine forever, and so we do not stop mid-check either.
    if idle_connections?() do
      Process.sleep(5_000)

      if idle_connections?() do
        System.stop(0)
      else
        shutdown_when_inactive(every_ms)
      end
    else
      shutdown_when_inactive(every_ms)
    end
  end

  defp idle_connections? do
    with {:ok, bandit_pid} <- Bandit.PhoenixAdapter.bandit_pid(QueryConsoleWeb.Endpoint),
         {:ok, connections} <- ThousandIsland.connection_pids(bandit_pid) do
      connections == []
    else
      _ -> false
    end
  end
end
