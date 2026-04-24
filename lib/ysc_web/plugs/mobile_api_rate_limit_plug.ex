defmodule YscWeb.Plugs.MobileAPIRateLimitPlug do
  @moduledoc """
  IP-based rate limiting for the kiosk mobile JSON API (before bearer auth).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Ysc.MobileAPIRateLimit.check_ip(conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Too many requests"}))
        |> halt()
    end
  end
end
