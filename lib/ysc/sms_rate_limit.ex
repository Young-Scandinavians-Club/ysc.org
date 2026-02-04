defmodule Ysc.SmsRateLimit do
  @moduledoc """
  In-memory rate limiting for SMS messages using Cachex.

  Enforces rate limits to protect SMS costs:
  - 20 SMS per hour per phone number
  - 5 SMS per minute per phone number

  Uses a sliding window approach by storing timestamps for each phone number.
  """
  require Logger

  @cache_name :ysc_cache
  @cache_prefix "sms_rate_limit:"

  # Rate limit constants
  @max_per_hour 20
  @max_per_minute 5

  # Cache TTL: 1 hour (in milliseconds)
  @cache_ttl_ms 60 * 60 * 1000

  @doc """
  Checks if sending an SMS to the given phone number would exceed rate limits.

  Returns:
  - `{:ok, :allowed}` - SMS can be sent
  - `{:error, :rate_limit_exceeded, reason}` - Rate limit exceeded with reason
  """
  @spec check_rate_limit(String.t()) ::
          {:ok, :allowed} | {:error, :rate_limit_exceeded, String.t()}
  def check_rate_limit(phone_number) do
    cache_key = build_cache_key(phone_number)
    now = DateTime.utc_now() |> DateTime.to_unix(:second)

    # Get existing timestamps from cache
    timestamps =
      case Cachex.get(@cache_name, cache_key) do
        {:ok, nil} ->
          []

        {:ok, cached_timestamps} when is_list(cached_timestamps) ->
          # Filter out timestamps older than 1 hour (cleanup old entries)
          Enum.filter(cached_timestamps, fn timestamp ->
            timestamp > now - 3600
          end)

        _ ->
          []
      end

    # Check per-minute limit
    one_minute_ago = now - 60
    minute_count = Enum.count(timestamps, fn ts -> ts >= one_minute_ago end)

    if minute_count >= @max_per_minute do
      Logger.warning("SMS rate limit exceeded: per-minute limit",
        phone_number: phone_number,
        count: minute_count,
        limit: @max_per_minute
      )

      {:error, :rate_limit_exceeded,
       "Rate limit exceeded: maximum #{@max_per_minute} SMS per minute allowed"}
    else
      # Check per-hour limit
      one_hour_ago = now - 3600
      hour_count = Enum.count(timestamps, fn ts -> ts >= one_hour_ago end)

      if hour_count >= @max_per_hour do
        Logger.warning("SMS rate limit exceeded: per-hour limit",
          phone_number: phone_number,
          count: hour_count,
          limit: @max_per_hour
        )

        {:error, :rate_limit_exceeded,
         "Rate limit exceeded: maximum #{@max_per_hour} SMS per hour allowed"}
      else
        {:ok, :allowed}
      end
    end
  end

  @doc """
  Records an SMS send attempt for rate limiting purposes.

  This should be called after successfully sending an SMS (or attempting to send).
  """
  @spec record_sms_send(String.t()) :: :ok
  def record_sms_send(phone_number) do
    cache_key = build_cache_key(phone_number)
    now = DateTime.utc_now() |> DateTime.to_unix(:second)

    # Get existing timestamps and add the new one
    timestamps =
      case Cachex.get(@cache_name, cache_key) do
        {:ok, nil} ->
          [now]

        {:ok, cached_timestamps} when is_list(cached_timestamps) ->
          # Filter out timestamps older than 1 hour and add new timestamp
          filtered =
            Enum.filter(cached_timestamps, fn timestamp ->
              timestamp > now - 3600
            end)

          [now | filtered]

        _ ->
          [now]
      end

    # Store back in cache with TTL
    Cachex.put(@cache_name, cache_key, timestamps, ttl: @cache_ttl_ms)

    :ok
  end

  @doc """
  Gets the current rate limit status for a phone number.

  Returns a map with:
  - `:minute_count` - Number of SMS sent in the last minute
  - `:hour_count` - Number of SMS sent in the last hour
  - `:minute_limit` - Maximum allowed per minute
  - `:hour_limit` - Maximum allowed per hour
  - `:minute_remaining` - Remaining SMS allowed in the current minute
  - `:hour_remaining` - Remaining SMS allowed in the current hour
  """
  @spec get_rate_limit_status(String.t()) :: map()
  def get_rate_limit_status(phone_number) do
    cache_key = build_cache_key(phone_number)
    now = DateTime.utc_now() |> DateTime.to_unix(:second)

    # Get existing timestamps from cache
    timestamps =
      case Cachex.get(@cache_name, cache_key) do
        {:ok, nil} ->
          []

        {:ok, cached_timestamps} when is_list(cached_timestamps) ->
          # Filter out timestamps older than 1 hour
          Enum.filter(cached_timestamps, fn timestamp ->
            timestamp > now - 3600
          end)

        _ ->
          []
      end

    one_minute_ago = now - 60
    one_hour_ago = now - 3600

    minute_count = Enum.count(timestamps, fn ts -> ts >= one_minute_ago end)
    hour_count = Enum.count(timestamps, fn ts -> ts >= one_hour_ago end)

    %{
      minute_count: minute_count,
      hour_count: hour_count,
      minute_limit: @max_per_minute,
      hour_limit: @max_per_hour,
      minute_remaining: max(0, @max_per_minute - minute_count),
      hour_remaining: max(0, @max_per_hour - hour_count)
    }
  end

  # Private functions

  defp build_cache_key(phone_number) do
    "#{@cache_prefix}#{phone_number}"
  end
end
