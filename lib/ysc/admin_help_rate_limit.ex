defmodule Ysc.AdminHelpRateLimit do
  @moduledoc """
  Rate limiting for admin help LLM features (guide finder and step clarifier).
  """
  use Hammer, backend: :ets

  @limit 10
  @scale_ms :timer.minutes(10)

  @doc """
  Checks rate limit for a user id.

  Returns `:ok` or `:rate_limited`.
  """
  def check(user_id) when is_binary(user_id) do
    key = "admin_help:user:#{user_id}"

    case hit(key, @scale_ms, @limit) do
      {:allow, _} -> :ok
      {:deny, _} -> :rate_limited
    end
  end

  def check(_), do: :rate_limited
end
