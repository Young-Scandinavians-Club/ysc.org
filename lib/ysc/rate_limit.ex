defmodule Ysc.RateLimit do
  @moduledoc """
  Shared Hammer `hit/3` helpers used by IP and identifier rate limiters.

  Each limiter still `use Hammer` (separate ETS tables and limits) and
  calls these functions with `&hit/3`:

      RateLimit.check_ip(&hit/3, "auth:ip:", ip, scale_ms, limit)
      RateLimit.check(&hit/3, "auth:id:\#{RateLimit.normalize_identifier(email)}", scale_ms, limit)
      RateLimit.check_ok(&hit/3, "scan:\#{user_id}", scale_ms, limit)
  """

  @type check_result :: :ok | {:error, :rate_limited, pos_integer()}
  @type limited_result :: :ok | :rate_limited
  @type hit_fun :: (String.t(), pos_integer(), pos_integer() ->
                      {:allow, term()} | {:deny, integer()})

  @doc """
  Turns a Hammer `hit/3` into `:ok` or `{:error, :rate_limited, retry_after_seconds}`.
  """
  def check(hit_fun, key, scale_ms, limit)
      when is_function(hit_fun, 3) and is_binary(key) and is_integer(scale_ms) and
             is_integer(limit) do
    case hit_fun.(key, scale_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, retry_after_seconds(retry_after_ms)}
    end
  end

  @doc """
  Like `check/4` but returns `:rate_limited` without a retry-after (scan / LLM helpers).
  """
  def check_ok(hit_fun, key, scale_ms, limit) do
    case check(hit_fun, key, scale_ms, limit) do
      :ok -> :ok
      {:error, :rate_limited, _} -> :rate_limited
    end
  end

  @doc """
  `check/4` scoped to a client IP. `prefix` is concatenated with the normalized IP.
  """
  def check_ip(hit_fun, prefix, ip, scale_ms, limit)
      when is_function(hit_fun, 3) and is_binary(prefix) do
    check(hit_fun, prefix <> normalize_ip(ip), scale_ms, limit)
  end

  @doc """
  Normalizes a connection IP (tuple or string) for use as a Hammer key.
  """
  def normalize_ip(ip) when is_tuple(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
    |> normalize_ip()
  end

  def normalize_ip(ip) when is_binary(ip) do
    ip
    |> String.trim()
    |> String.downcase()
  end

  @doc """
  Normalizes an email or username so case and surrounding whitespace share a bucket.
  """
  def normalize_identifier(identifier) when is_binary(identifier) do
    identifier
    |> String.trim()
    |> String.downcase()
  end

  defp retry_after_seconds(retry_after_ms) when is_integer(retry_after_ms) do
    max(1, div(retry_after_ms, 1000))
  end
end
