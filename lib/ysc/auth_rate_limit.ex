defmodule Ysc.AuthRateLimit do
  @moduledoc """
  Rate limiting for authentication flows to slow down credential stuffing.

  Limits are applied by:
  - IP address: slows down one client trying many usernames
  - Identifier (email/username): slows down distributed attacks on a single account
  """
  use Hammer, backend: :ets

  # Per IP: 20 auth attempts per minute (login, OAuth, passkey, forgot password)
  @default_ip_limit 20
  @ip_scale_ms :timer.minutes(1)

  # Per identifier (email): 5 attempts per minute to protect individual accounts
  @default_identifier_limit 5
  @identifier_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  defp identifier_limit do
    Application.get_env(:ysc, __MODULE__, [])[:identifier_limit] ||
      @default_identifier_limit
  end

  @doc """
  Checks rate limit by client IP. Call before processing any auth attempt.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_ip(ip) when is_tuple(ip) do
    ip_string = ip |> :inet.ntoa() |> to_string()
    check_ip(ip_string)
  end

  def check_ip(ip) when is_binary(ip) do
    key = "auth:ip:#{normalize_ip(ip)}"

    case hit(key, @ip_scale_ms, ip_limit()) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end

  @doc """
  Checks rate limit by identifier (email or username). Call when you have the
  identifier from the request (e.g. login form email, forgot password email).

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_identifier(identifier) when is_binary(identifier) do
    key = "auth:id:#{normalize_identifier(identifier)}"

    case hit(key, @identifier_scale_ms, identifier_limit()) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end

  def check_identifier(_), do: :ok

  defp normalize_ip(ip) do
    ip
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_identifier(identifier) do
    identifier
    |> String.trim()
    |> String.downcase()
  end
end
