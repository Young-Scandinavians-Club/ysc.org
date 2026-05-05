defmodule Ysc.Http.UrlFetchGuard do
  @moduledoc """
  Validates URLs before the server fetches them (SSRF mitigation).

  Ensures the scheme is HTTP(S), the host is not obviously disallowed, and
  (in production-like environments) the resolved addresses are not private,
  loopback, link-local, or similar special-use space.
  """

  import Bitwise, only: [band: 2, bsr: 2]

  @blocked_hosts MapSet.new([
                   "localhost",
                   "metadata.google.internal",
                   "metadata.goog"
                 ])

  @doc """
  Returns `:ok` if `url` is safe for a server-side GET, or `{:error, reason}`.

  In `:dev` and `:test` environments, RFC1918 / loopback targets are allowed so
  local object storage and tests against loopback HTTP servers still work.
  """
  @spec validate_url_for_server_fetch(String.t()) :: :ok | {:error, atom()}
  def validate_url_for_server_fetch(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- validate_scheme(uri),
         :ok <- validate_no_userinfo(uri),
         :ok <- validate_host_present(uri) do
      host = host_string(uri)

      case validate_host_literal(host) do
        :ok -> validate_resolved_addresses(host)
        {:error, _} = err -> err
      end
    end
  end

  defp validate_no_userinfo(%URI{userinfo: nil}), do: :ok
  defp validate_no_userinfo(%URI{userinfo: ""}), do: :ok
  defp validate_no_userinfo(_), do: {:error, :userinfo_not_allowed}

  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"],
    do: :ok

  defp validate_scheme(%URI{scheme: scheme}) when is_binary(scheme) do
    {:error, :unsupported_scheme}
  end

  defp validate_scheme(_), do: {:error, :missing_scheme}

  defp validate_host_present(%URI{host: host})
       when is_binary(host) and host != "",
       do: :ok

  defp validate_host_present(_), do: {:error, :missing_host}

  defp host_string(%URI{host: host}) do
    host = String.downcase(host)

    if String.starts_with?(host, "[") and String.ends_with?(host, "]") do
      String.slice(host, 1..-2//1)
    else
      host
    end
  end

  defp validate_host_literal(host) do
    cond do
      MapSet.member?(@blocked_hosts, host) ->
        {:error, :blocked_host}

      String.ends_with?(host, ".local") ->
        {:error, :blocked_host}

      true ->
        case :inet.parse_address(String.to_charlist(host)) do
          {:ok, ip} ->
            if strict_fetch?() and private_or_special_ip?(ip) do
              {:error, :blocked_ip}
            else
              :ok
            end

          {:error, _} ->
            :ok
        end
    end
  end

  defp validate_resolved_addresses(host) do
    if strict_fetch?() do
      host_cl = String.to_charlist(host)

      ipv4s = :inet_res.lookup(host_cl, :in, :a)
      ipv6s = :inet_res.lookup(host_cl, :in, :aaaa)
      addrs = ipv4s ++ ipv6s

      cond do
        addrs == [] ->
          {:error, :dns_resolution_failed}

        Enum.all?(addrs, &(not private_or_special_ip?(&1))) ->
          :ok

        true ->
          {:error, :blocked_resolved_ip}
      end
    else
      :ok
    end
  end

  defp strict_fetch? do
    Ysc.Env.prod?() or Ysc.Env.sandbox?()
  end

  defp private_or_special_ip?({a, b, c, d})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    cond do
      a == 127 -> true
      a == 0 -> true
      a == 10 -> true
      a == 192 and b == 168 -> true
      a == 172 and b in 16..31 -> true
      a == 169 and b == 254 -> true
      a == 100 and b in 64..127 -> true
      a == 255 and b == 255 and c == 255 and d == 255 -> true
      # Multicast and historically "reserved" IPv4 space (not routable on the public Internet)
      a >= 224 -> true
      true -> false
    end
  end

  defp private_or_special_ip?({a, b, c, d, e, f, g, h})
       when is_integer(a) and is_integer(b) do
    cond do
      # ::1
      a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0 and g == 0 and
          h == 1 ->
        true

      # IPv6 unique local fc00::/7 (fc00:: – fdff:ffff:...)
      band(a, 0xFE00) == 0xFC00 ->
        true

      # IPv6 link-local fe80::/10 (fe80:: – febf:ffff:...)
      a >= 0xFE80 and a <= 0xFEBF ->
        true

      # IPv6 multicast ff00::/8
      band(a, 0xFF00) == 0xFF00 ->
        true

      # IPv4-mapped IPv6 ::ffff:x.x.x.x
      a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0xFFFF ->
        private_or_special_ip?(
          {bsr(g, 8), band(g, 0xFF), bsr(h, 8), band(h, 0xFF)}
        )

      true ->
        false
    end
  end

  defp private_or_special_ip?(_), do: false
end
