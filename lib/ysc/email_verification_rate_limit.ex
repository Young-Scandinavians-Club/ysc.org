defmodule Ysc.EmailVerificationRateLimit do
  @moduledoc """
  Rate limits verification code submission attempts (email and phone).

  Limits guess volume per target account. Account-setup email sending also requires a signed
  `setup_token` from `YscWeb.AccountSetupAccess` (see account setup security tests).
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @default_limit 12
  @scale_ms :timer.minutes(1)
  @verification_types [:email, :phone]

  defp limit do
    Application.get_env(:ysc, __MODULE__, [])[:attempt_limit_per_minute] ||
      @default_limit
  end

  @doc """
  Checks rate limit for verification attempts scoped to the target user ID.

  `type` is `:email` or `:phone`. Returns `:ok` if allowed, or `:rate_limited` if over limit.
  """
  def check(user_id, type \\ :email)

  def check(user_id, type)
      when is_binary(user_id) and type in @verification_types do
    RateLimit.check_ok(
      &hit/3,
      "verify_attempt:#{type}:user:#{user_id}",
      @scale_ms,
      limit()
    )
  end

  def check(_, _), do: :rate_limited
end
