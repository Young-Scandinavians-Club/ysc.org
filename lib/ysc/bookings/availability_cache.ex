defmodule Ysc.Bookings.AvailabilityCache do
  @moduledoc """
  Short-TTL cache for Clear Lake daily availability maps.
  """

  require Ysc.Logging

  @cache_name :ysc_cache
  @default_ttl 2 * 60 * 1000

  def get_clear_lake_daily_availability(start_date, end_date) do
    cache_key =
      "availability:clear_lake:#{Date.to_iso8601(start_date)}:#{Date.to_iso8601(end_date)}"

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        value =
          Ysc.Bookings.get_clear_lake_daily_availability_from_db(
            start_date,
            end_date
          )

        cache_with_ttl(cache_key, value)
        value

      {:ok, {:ttl_expires_at, ttl_expires_at, value}} ->
        now = System.system_time(:millisecond)

        if now < ttl_expires_at do
          value
        else
          refetch(cache_key, start_date, end_date)
        end

      {:ok, value} ->
        cache_with_ttl(cache_key, value)
        value

      {:error, _reason} ->
        Ysc.Bookings.get_clear_lake_daily_availability_from_db(
          start_date,
          end_date
        )
    end
  end

  def invalidate do
    case Cachex.keys(@cache_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(
          &(is_binary(&1) and String.starts_with?(&1, "availability:"))
        )
        |> Enum.each(&Cachex.del(@cache_name, &1))

      _ ->
        :ok
    end

    :ok
  end

  defp refetch(cache_key, start_date, end_date) do
    Cachex.del(@cache_name, cache_key)

    value =
      Ysc.Bookings.get_clear_lake_daily_availability_from_db(
        start_date,
        end_date
      )

    cache_with_ttl(cache_key, value)
    value
  end

  defp cache_with_ttl(key, value) do
    ttl_ms = Application.get_env(:ysc, :availability_cache_ttl_ms, @default_ttl)
    now = System.system_time(:millisecond)
    ttl_expires_at = now + ttl_ms

    Cachex.put(@cache_name, key, {:ttl_expires_at, ttl_expires_at, value},
      expire: ttl_ms
    )

    value
  end
end
