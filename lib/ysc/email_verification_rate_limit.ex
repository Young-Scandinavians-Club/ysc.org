defmodule Ysc.EmailVerificationRateLimit do
  @moduledoc """
  Rate limits email verification code submission attempts (account setup and similar flows).

  Limits guess volume per target account. Sending codes and submitting guesses also require a
  signed `setup_token` from `YscWeb.AccountSetupAccess` (see account setup security tests).
  """
  use Hammer, backend: :ets

  @default_limit 12
  @scale_ms :timer.minutes(1)

  defp limit do
    Application.get_env(:ysc, __MODULE__, [])[:attempt_limit_per_minute] ||
      @default_limit
  end

  @doc """
  Checks rate limit for verification attempts scoped to the target user ID.

  Returns `:ok` if allowed, or `:rate_limited` if over limit.
  """
  def check(user_id) when is_binary(user_id) do
    key = "email_verify_attempt:user:#{user_id}"

    case hit(key, @scale_ms, limit()) do
      {:allow, _} -> :ok
      {:deny, _} -> :rate_limited
    end
  end

  def check(_), do: :rate_limited
end
