defmodule Ysc.NewsletterRateLimit do
  @moduledoc """
  Rate limiting for newsletter subscription requests to prevent bot abuse.

  Implements dual rate limiting:
  - Per IP: prevents a single bot from spamming subscriptions
  - Per email: prevents email address enumeration and spam
  """
  use Hammer, backend: :ets

  require Ysc.Logging

  # Per IP: 3 subscription attempts per minute
  @ip_limit 3
  @ip_scale_ms :timer.minutes(1)

  # Per email: 1 subscription per hour (prevents repeated subscribe/unsubscribe abuse)
  @email_limit 1
  @email_scale_ms :timer.hours(1)

  @doc """
  Checks rate limit by IP address.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_ip(ip) when is_tuple(ip) do
    ip_string = ip |> :inet.ntoa() |> to_string()
    check_ip(ip_string)
  end

  def check_ip(ip) when is_binary(ip) do
    key = "newsletter:ip:#{normalize_ip(ip)}"

    case hit(key, @ip_scale_ms, @ip_limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        Ysc.Logging.warning("Newsletter subscription rate limit exceeded by IP",
          extra: %{ip: ip, limit: @ip_limit}
        )

        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end

  @doc """
  Checks rate limit by email address.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_email(email) when is_binary(email) do
    key = "newsletter:email:#{normalize_email(email)}"

    case hit(key, @email_scale_ms, @email_limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        Ysc.Logging.warning(
          "Newsletter subscription rate limit exceeded by email",
          extra: %{email: email, limit: @email_limit}
        )

        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end

  def check_email(_), do: :ok

  @doc """
  Checks both IP and email rate limits.

  Returns `:ok` if both pass, or the first error encountered.
  """
  def check(ip, email) do
    with :ok <- check_ip(ip) do
      check_email(email)
    end
  end

  defp normalize_ip(ip) do
    ip
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(email) do
    email
    |> String.trim()
    |> String.downcase()
  end
end
