defmodule Ysc.ResendRateLimiter do
  @moduledoc """
  Rate limiter for resend operations (email verification, SMS verification, etc.)

  Provides rate limiting functionality to prevent spam and abuse of resend operations.
  Uses cache with TTL to track rate limit state.
  """

  @default_rate_limit_seconds 60

  @doc """
  Checks if a resend operation is currently allowed for the given identifier and type.

  ## Parameters
  - `identifier`: Unique identifier (e.g., user ID)
  - `type`: Type of resend operation (e.g., :email, :sms)
  - `rate_limit_seconds`: Optional rate limit in seconds (default: 60)

  ## Returns
  - `{:ok, :allowed}` if resend is allowed
  - `{:error, :rate_limited, remaining_seconds}` if rate limited with remaining time
  """
  @spec resend_allowed?(String.t() | integer(), atom(), integer()) ::
          {:ok, :allowed} | {:error, :rate_limited, integer()}
  def resend_allowed?(
        identifier,
        type,
        rate_limit_seconds \\ @default_rate_limit_seconds
      ) do
    cache_key = cache_key(identifier, type)

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        {:ok, :allowed}

      {:ok, _disabled_until} ->
        remaining = remaining_seconds(identifier, type, rate_limit_seconds)
        {:error, :rate_limited, remaining}
    end
  end

  @doc """
  Records that a resend operation was performed, setting the rate limit.

  ## Parameters
  - `identifier`: Unique identifier (e.g., user ID)
  - `type`: Type of resend operation (e.g., :email, :sms)
  - `rate_limit_seconds`: Optional rate limit in seconds (default: 60)

  ## Returns
  - `:ok` on success
  """
  @spec record_resend(String.t() | integer(), atom(), integer()) :: :ok
  def record_resend(
        identifier,
        type,
        rate_limit_seconds \\ @default_rate_limit_seconds
      ) do
    cache_key = cache_key(identifier, type)
    ttl_ms = :timer.seconds(rate_limit_seconds)

    case Cachex.put(:ysc_cache, cache_key, true, ttl: ttl_ms) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger

        Logger.error("[ResendRateLimiter] Failed to cache rate limit", %{
          cache_key: cache_key,
          reason: reason
        })

        # In test environment, this might fail if cache isn't initialized
        # For now, we'll still return :ok to avoid breaking callers
        # but the rate limiting won't work if cache fails
        :ok
    end
  end

  @doc """
  Checks if resend is allowed and records it if allowed.

  ## Parameters
  - `identifier`: Unique identifier (e.g., user ID)
  - `type`: Type of resend operation (e.g., :email, :sms)
  - `rate_limit_seconds`: Optional rate limit in seconds (default: 60)

  ## Returns
  - `{:ok, :allowed}` if resend is allowed (and recorded)
  - `{:error, :rate_limited, remaining_seconds}` if rate limited
  """
  @spec check_and_record_resend(String.t() | integer(), atom(), integer()) ::
          {:ok, :allowed} | {:error, :rate_limited, integer()}
  def check_and_record_resend(
        identifier,
        type,
        rate_limit_seconds \\ @default_rate_limit_seconds
      ) do
    case resend_allowed?(identifier, type, rate_limit_seconds) do
      {:ok, :allowed} ->
        record_resend(identifier, type, rate_limit_seconds)
        {:ok, :allowed}

      {:error, :rate_limited, remaining} ->
        {:error, :rate_limited, remaining}
    end
  end

  @doc """
  Gets the remaining seconds until resend is allowed again.

  ## Parameters
  - `identifier`: Unique identifier (e.g., user ID)
  - `type`: Type of resend operation (e.g., :email, :sms)
  - `rate_limit_seconds`: Optional rate limit in seconds (default: 60)

  ## Returns
  - `0` if resend is currently allowed
  - Positive integer representing remaining seconds if rate limited
  """
  @spec remaining_seconds(String.t() | integer(), atom(), integer()) ::
          non_neg_integer()
  def remaining_seconds(
        identifier,
        type,
        rate_limit_seconds \\ @default_rate_limit_seconds
      ) do
    cache_key = cache_key(identifier, type)

    case Cachex.get(:ysc_cache, cache_key) do
      {:ok, nil} ->
        0

      {:ok, _} ->
        # Since we use TTL, if the key exists, it means we're still rate limited
        # We can't get the exact remaining time from Cachex TTL, so we return a conservative estimate
        # In practice, this should be close enough for UI purposes
        min(rate_limit_seconds, 60)
    end
  end

  @doc """
  Gets the disabled_until timestamp for use in LiveView assigns.

  ## Parameters
  - `rate_limit_seconds`: Rate limit in seconds

  ## Returns
  - `DateTime` representing when the rate limit expires
  """
  @spec disabled_until(integer()) :: DateTime.t()
  def disabled_until(rate_limit_seconds) do
    DateTime.utc_now() |> DateTime.add(rate_limit_seconds, :second)
  end

  @doc """
  Helper function to check if resend is available based on assigns.

  ## Parameters
  - `assigns`: LiveView assigns map
  - `type`: Type of resend (:email or :sms)

  ## Returns
  - `true` if resend is available, `false` otherwise
  """
  @spec resend_available?(map(), atom()) :: boolean()
  def resend_available?(assigns, type) do
    key =
      case type do
        :email -> :email_resend_disabled_until
        :sms -> :sms_resend_disabled_until
      end

    case Map.get(assigns, key) do
      nil ->
        true

      disabled_until ->
        DateTime.compare(disabled_until, DateTime.utc_now()) == :lt
    end
  end

  @doc """
  Helper function to get remaining seconds based on assigns.

  ## Parameters
  - `assigns`: LiveView assigns map
  - `type`: Type of resend (:email or :sms)

  ## Returns
  - Remaining seconds as integer
  """
  @spec resend_seconds_remaining(map(), atom()) :: non_neg_integer()
  def resend_seconds_remaining(assigns, type) do
    key =
      case type do
        :email -> :email_resend_disabled_until
        :sms -> :sms_resend_disabled_until
        _ -> nil
      end

    if key do
      case Map.get(assigns, key) do
        nil ->
          0

        disabled_until ->
          case DateTime.diff(disabled_until, DateTime.utc_now(), :second) do
            remaining when is_integer(remaining) -> max(0, remaining)
            _ -> 0
          end
      end
    else
      0
    end
  end

  # Private helper to generate cache keys
  defp cache_key(identifier, type) do
    "resend_#{type}:#{identifier}"
  end
end
