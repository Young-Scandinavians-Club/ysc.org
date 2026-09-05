defmodule Ysc.AdminHelpRateLimit do
  @moduledoc """
  Rate limiting for admin help LLM features (guide finder and step clarifier).
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @limit 10
  @scale_ms :timer.minutes(10)

  @doc """
  Checks rate limit for a user id.

  Returns `:ok` or `:rate_limited`.
  """
  def check(user_id) when is_binary(user_id) do
    RateLimit.check_ok(&hit/3, "admin_help:user:#{user_id}", @scale_ms, @limit)
  end

  def check(_), do: :rate_limited
end
