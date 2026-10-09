defmodule YscWeb.Emails.OtpToken do
  @moduledoc """
  Builds the `OTP-Token` email header field from
  [draft-goto-otp-token-01](https://datatracker.ietf.org/doc/draft-goto-otp-token/01/).

  The header delivers a One-Time Passcode in a machine-readable, origin-bound
  form alongside the human-readable message, so receiving mail clients can hand
  the code to the page that requested it (autofill, WebOTP-style flows):

      OTP-Token: "123456"; origin="https://ysc.org"

  The value is an RFC 9651 Structured Field Item: a String (the code) with an
  `origin` Parameter holding the ASCII serialization of the origin (RFC 6454)
  the code is bound to. Per the draft the origin MUST NOT be opaque, MUST be a
  potentially trustworthy origin, and MUST be canonical (lowercase, default
  port omitted, ASCII only). When the configured endpoint origin cannot satisfy
  that, no header is emitted and the email is sent without it.
  """

  @header_name "OTP-Token"

  @doc "The header field name."
  def header_name, do: @header_name

  @doc """
  Adds the `OTP-Token` header to a `Swoosh.Email` for `code`, bound to the
  application's endpoint origin. Returns the email unchanged if no valid header
  can be produced.
  """
  def put_header(%Swoosh.Email{} = email, code) when is_binary(code) do
    put_header(email, code, endpoint_origin())
  end

  @doc """
  Same as `put_header/2` with an explicit `origin` (an origin string or `nil`).
  """
  def put_header(%Swoosh.Email{} = email, code, origin) when is_binary(code) do
    case header_value(code, origin) do
      {:ok, value} -> Swoosh.Email.header(email, @header_name, value)
      :error -> email
    end
  end

  @doc """
  Serializes the header value, e.g. `"123456"; origin="https://ysc.org"`.

  Returns `:error` when the code is not a valid Structured Field String
  (printable ASCII only) or the origin is not valid per the draft.
  """
  def header_value(code, origin) when is_binary(code) and is_binary(origin) do
    if sf_string?(code) and valid_origin?(origin) do
      {:ok, ~s("#{escape(code)}"; origin="#{escape(origin)}")}
    else
      :error
    end
  end

  def header_value(_code, _origin), do: :error

  @doc """
  The canonical serialized origin of the Phoenix endpoint, or `nil` when it is
  not a potentially trustworthy origin.
  """
  def endpoint_origin do
    endpoint_origin(YscWeb.Endpoint.url())
  end

  @doc false
  def endpoint_origin(url) when is_binary(url) do
    with %URI{scheme: scheme, host: host, port: port}
         when is_binary(scheme) and is_binary(host) <- URI.parse(url),
         scheme = String.downcase(scheme),
         host = String.downcase(host),
         origin = serialize_origin(scheme, host, port),
         true <- valid_origin?(origin) do
      origin
    else
      _ -> nil
    end
  end

  def endpoint_origin(_), do: nil

  @doc """
  Returns true when `origin` is a canonical, non-opaque, potentially
  trustworthy ASCII serialized origin (`scheme://host[:port]`, nothing else).
  """
  def valid_origin?(origin) when is_binary(origin) do
    case Regex.run(
           ~r/\A(https?):\/\/([a-z0-9.\-]+|\[[0-9a-f:.]+\])(?::(\d{1,5}))?\z/,
           origin
         ) do
      [_, scheme, host, port] ->
        canonical_port?(scheme, port) and trustworthy?(scheme, host)

      [_, scheme, host] ->
        trustworthy?(scheme, host)

      _ ->
        false
    end
  end

  def valid_origin?(_), do: false

  defp serialize_origin(scheme, host, port) do
    host = if String.contains?(host, ":"), do: "[#{host}]", else: host

    if is_nil(port) or port == default_port(scheme) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp default_port("https"), do: 443
  defp default_port("http"), do: 80
  defp default_port(_), do: nil

  # A port that is the scheme default, or has a leading zero, is not canonical.
  defp canonical_port?(scheme, port) do
    case Integer.parse(port) do
      {n, ""} ->
        Integer.to_string(n) == port and n in 1..65_535 and
          n != default_port(scheme)

      _ ->
        false
    end
  end

  # https is always trustworthy; http only for loopback hosts
  # (https://w3c.github.io/webappsec-secure-contexts/).
  defp trustworthy?("https", _host), do: true

  defp trustworthy?("http", host) do
    host in ["localhost", "[::1]"] or String.ends_with?(host, ".localhost") or
      loopback_ipv4?(host)
  end

  defp trustworthy?(_, _), do: false

  defp loopback_ipv4?(host) do
    match?(
      {:ok, {127, _, _, _}},
      :inet.parse_strict_address(String.to_charlist(host))
    )
  end

  # RFC 9651 section 3.3.3: a String is zero or more printable ASCII characters
  # (%x20-7E).
  defp sf_string?(value), do: value =~ ~r/\A[\x20-\x7e]*\z/

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
