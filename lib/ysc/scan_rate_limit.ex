defmodule Ysc.ScanRateLimit do
  @moduledoc """
  Rate limiting for QR scan events to mitigate brute-force token guessing.
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @default_limit 20
  @scale_ms :timer.minutes(1)

  @doc """
  Checks scan rate limit by admin user ID.

  Returns `:ok` if allowed, or `:rate_limited` if over limit.
  """
  def check(user_id) when is_binary(user_id) do
    RateLimit.check_ok(&hit/3, "scan:#{user_id}", @scale_ms, @default_limit)
  end

  def check(_), do: :rate_limited
end
