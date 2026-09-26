defmodule YscWeb.ClientIP do
  @moduledoc """
  Resolves the real client IP address for HTTP requests and LiveViews.

  On Fly.io every request reaches the app through Fly Proxy, so the TCP peer is
  the proxy and the rightmost `X-Forwarded-For` entry is the app's own shared
  or dedicated IP (see https://fly.io/docs/networking/request-headers/). Fly
  Proxy sets `Fly-Client-IP` to the address it accepted the connection from.

  Production (`ysc.org`) is additionally proxied by Cloudflare, so there
  `Fly-Client-IP` is a Cloudflare edge address. Only in that case do we trust
  `CF-Connecting-IP`, which Cloudflare sets to the visitor's address; a client
  hitting the Fly origin directly cannot spoof it because its own address (not
  a Cloudflare one) ends up in `Fly-Client-IP`.

  Proxy headers are only honoured when `trust_proxy_headers` is enabled (set in
  `config/runtime.exs` when `FLY_APP_NAME` is present). Elsewhere (dev, test)
  the TCP peer address is used as-is.

  ## LiveViews

  Websocket `connect_info` cannot carry `Fly-Client-IP` (only `x-` prefixed
  headers are exposed), so the IP resolved for the initial HTTP request is put
  into the signed LiveView session via `live_session/1` and read back with
  `from_socket/2`.
  """

  import Bitwise

  @session_key "client_ip"

  # https://www.cloudflare.com/ips-v4 and https://www.cloudflare.com/ips-v6
  @cloudflare_cidrs ~w(
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
    2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  )

  @cloudflare_ranges (for cidr <- @cloudflare_cidrs do
                        [addr, prefix] = String.split(cidr, "/")

                        {:ok, ip} =
                          :inet.parse_strict_address(String.to_charlist(addr))

                        {ip, String.to_integer(prefix)}
                      end)

  @doc """
  Resolves the client IP from request headers and the TCP peer address.

  Options:

    * `:trust_proxy_headers` - honour `Fly-Client-IP` / `CF-Connecting-IP`.
      Defaults to `trust_proxy_headers?/0`.
  """
  @spec resolve([{String.t(), String.t()}], :inet.ip_address() | nil, keyword()) ::
          :inet.ip_address() | nil
  def resolve(headers, peer_ip, opts \\ []) do
    if Keyword.get_lazy(opts, :trust_proxy_headers, &trust_proxy_headers?/0) do
      case header_ip(headers, "fly-client-ip") do
        nil ->
          peer_ip

        fly_ip ->
          if cloudflare?(fly_ip),
            do: header_ip(headers, "cf-connecting-ip") || fly_ip,
            else: fly_ip
      end
    else
      peer_ip
    end
  end

  @doc "Resolves the client IP for a conn (headers + TCP peer)."
  @spec from_conn(Plug.Conn.t(), keyword()) :: :inet.ip_address() | nil
  def from_conn(%Plug.Conn{} = conn, opts \\ []) do
    resolve(conn.req_headers, conn.remote_ip, opts)
  end

  @doc """
  `live_session` session callback: stores the conn's client IP (already
  resolved by `YscWeb.Plugs.ClientIP`) in the signed LiveView session.

      live_session :name, session: {YscWeb.ClientIP, :live_session, []} do
  """
  @spec live_session(Plug.Conn.t()) :: %{String.t() => String.t()}
  def live_session(%Plug.Conn{remote_ip: ip}) when is_tuple(ip) do
    %{@session_key => ip |> :inet.ntoa() |> to_string()}
  end

  def live_session(%Plug.Conn{}), do: %{}

  @doc """
  Client IP for a LiveView `mount/3`.

  Reads the IP stored by `live_session/1`, falling back to the socket peer
  address (correct in dev/test, the proxy address on Fly) and finally
  `{0, 0, 0, 0}`.
  """
  @spec from_socket(Phoenix.LiveView.Socket.t(), map()) :: :inet.ip_address()
  def from_socket(%Phoenix.LiveView.Socket{} = socket, session)
      when is_map(session) do
    parse_ip(Map.get(session, @session_key)) || peer_address(socket) ||
      {0, 0, 0, 0}
  end

  @doc "Whether proxy headers should be trusted (running behind Fly Proxy)."
  @spec trust_proxy_headers?() :: boolean()
  def trust_proxy_headers? do
    :ysc
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:trust_proxy_headers, false)
  end

  @doc "Whether `ip` belongs to one of Cloudflare's published edge ranges."
  @spec cloudflare?(:inet.ip_address()) :: boolean()
  def cloudflare?(ip), do: Enum.any?(@cloudflare_ranges, &in_range?(ip, &1))

  @doc """
  Parses a single IP address string. IPv4-mapped IPv6 addresses are
  normalised to IPv4. Returns `nil` for anything else.
  """
  @spec parse_ip(term()) :: :inet.ip_address() | nil
  def parse_ip(value) when is_binary(value) do
    case :inet.parse_strict_address(
           value
           |> String.trim()
           |> String.to_charlist()
         ) do
      {:ok, {0, 0, 0, 0, 0, 0xFFFF, hi, lo}} ->
        {hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF}

      {:ok, ip} ->
        ip

      {:error, _} ->
        nil
    end
  end

  def parse_ip(_), do: nil

  defp header_ip(headers, name) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> parse_ip(value)
      nil -> nil
    end
  end

  defp peer_address(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end

  defp in_range?(ip, {net, prefix}) when tuple_size(ip) == tuple_size(net) do
    bits = if tuple_size(ip) == 4, do: 32, else: 128
    shift = bits - prefix
    to_integer(ip) >>> shift == to_integer(net) >>> shift
  end

  defp in_range?(_ip, _range), do: false

  defp to_integer({_, _, _, _} = ip), do: tuple_reduce(ip, 8)
  defp to_integer({_, _, _, _, _, _, _, _} = ip), do: tuple_reduce(ip, 16)

  defp tuple_reduce(ip, width) do
    ip
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> acc <<< width ||| part end)
  end
end
