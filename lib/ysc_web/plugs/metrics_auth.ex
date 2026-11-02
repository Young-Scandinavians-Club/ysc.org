defmodule YscWeb.Plugs.MetricsAuth do
  @moduledoc """
  Restricts access to the /metrics (Prometheus) endpoint to private/internal IPs only.

  In production, only requests from private network ranges are allowed
  (e.g. Fly.io private network 172.16.0.0/12 and fdaa::/16). In development, all requests are allowed.
  Returns 404 for disallowed IPs to avoid leaking that the endpoint exists.

  `conn.remote_ip` is set by `YscWeb.Plugs.ClientIP` in `YscWeb.Endpoint`: requests via
  Fly Proxy carry the public client address from `Fly-Client-IP`, while scrapes over
  Fly's private network have no such header and keep their private peer address.
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

  # IPv4-mapped IPv6 (::ffff:a.b.c.d) is judged by the embedded IPv4 address.
  defp private_ip?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}) do
    private_ip?({hi >>> 8, band(hi, 0xFF), lo >>> 8, band(lo, 0xFF)})
  end

  # IPv6: ::1 (loopback), fe80::/10 (link-local), fc00::/7 (unique local, which
  # includes Fly's private network fdaa::/16). The prefix is compared on the
  # first 16-bit group: fe80::/10 keeps its top 10 bits, fc00::/7 its top 7.
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  defp private_ip?({a, _b, _c, _d, _e, _f, _g, _h}) do
    band(a, 0xFFC0) == 0xFE80 or band(a, 0xFE00) == 0xFC00
  end

  defp private_ip?(_), do: false
end
