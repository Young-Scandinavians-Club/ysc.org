defmodule Ysc.ScanRateLimit do
  @moduledoc """
  Rate limiting for QR scan events to mitigate brute-force token guessing.
  """
  use Hammer, backend: :ets

  @default_limit 20
  @scale_ms :timer.minutes(1)

  @doc """
  Checks scan rate limit by admin user ID.

  Returns `:ok` if allowed, or `:rate_limited` if over limit.
  """
  def check(user_id) when is_binary(user_id) do
    key = "scan:#{user_id}"

    case hit(key, @scale_ms, @default_limit) do
      {:allow, _count} -> :ok
      {:deny, _retry_after_ms} -> :rate_limited
    end
  end

  def check(_), do: :rate_limited
end
