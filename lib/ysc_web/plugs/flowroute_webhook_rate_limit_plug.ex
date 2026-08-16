defmodule YscWeb.Plugs.FlowrouteWebhookRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the FlowRoute webhook routes (before token auth).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Ysc.FlowrouteWebhookRateLimit.check_ip(conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> send_resp(429, "Too many requests")
        |> halt()
    end
  end
end
