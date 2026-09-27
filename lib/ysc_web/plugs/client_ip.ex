defmodule YscWeb.Plugs.ClientIP do
  @moduledoc """
  Sets `conn.remote_ip` to the real client address using `YscWeb.ClientIP`.

  Must run before anything that reads `conn.remote_ip` (rate limiters,
  `YscWeb.Plugs.MetricsAuth`, Turnstile verification). Also sets the
  `:remote_ip` Logger metadata (shown in request logs via `metadata: :all`).
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    case YscWeb.ClientIP.from_conn(conn, opts) do
      nil ->
        conn

      ip ->
        Logger.metadata(remote_ip: ip |> :inet.ntoa() |> to_string())
        %{conn | remote_ip: ip}
    end
  end
end
