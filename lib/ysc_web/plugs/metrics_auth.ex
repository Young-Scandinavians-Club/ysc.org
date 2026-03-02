defmodule YscWeb.Plugs.MetricsAuth do
  @moduledoc """
  Restricts access to the /metrics (Prometheus) endpoint to private/internal IPs only.

  In production, only requests from private network ranges are allowed
  (e.g. Fly.io private network 172.16.0.0/12 and fdaa::/16). In development, all requests are allowed.
  Returns 404 for disallowed IPs to avoid leaking that the endpoint exists.
  """
  import Bitwise
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if metrics_path?(conn.request_path) do
      if Ysc.Env.dev?() do
        conn
      else
        if private_ip?(conn.remote_ip) do
          conn
        else
          conn
          |> send_resp(404, "Not Found")
          |> halt()
        end
      end
    else
      conn
    end
  end

  defp metrics_path?(path) when is_binary(path) do
    String.starts_with?(path, "/metrics")
  end

  defp metrics_path?(_), do: false

  # IPv4: 127.0.0.0/8 (loopback), 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
  defp private_ip?({a, b, _c, _d}) do
    a == 127 or
      a == 10 or
      (a == 172 and b >= 16 and b <= 31) or
      (a == 192 and b == 168)
  end

  # IPv6: ::1 (loopback), fe80::/10 (link-local), fc00::/7 (ULA), fdaa::/16 (Fly internal)
  defp private_ip?({a, b, c, d, e, f, g, h}) do
    (a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0 and g == 0 and
       h == 1) or
      (a == 0xFE80 and band(b, 0xC000) == 0) or
      (a == 0xFC00 or a == 0xFD00) or
      (a == 0xFDA0 and b >= 0)
  end

  defp private_ip?(_), do: false
end
