defmodule Ysc.AuthRateLimit do
  @moduledoc """
  Rate limiting for authentication flows to slow down credential stuffing.

  Limits are applied by:
  - IP address: slows down one client trying many usernames
  - Identifier (email/username): slows down distributed attacks on a single account
  """
  use Hammer, backend: :ets

  alias Ysc.Accounts.Email
  alias Ysc.RateLimit

  # Per IP: 20 auth attempts per minute (login, OAuth, passkey, forgot password)
  @default_ip_limit 20
  @ip_scale_ms :timer.minutes(1)

  # Per identifier (email): 5 attempts per minute to protect individual accounts
  @default_identifier_limit 5
  @identifier_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  defp identifier_limit do
    Application.get_env(:ysc, __MODULE__, [])[:identifier_limit] ||
      @default_identifier_limit
  end

  @doc """
  Checks rate limit by client IP. Call before processing any auth attempt.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    RateLimit.check_ip(&hit/3, "auth:ip:", ip, @ip_scale_ms, ip_limit())
  end

  @doc """
  Checks rate limit by identifier (email or username). Call when you have the
  identifier from the request (e.g. login form email, forgot password email).

  The identifier is canonicalized the same way account lookup is
  (`Ysc.Accounts.Email.normalize/1`), so Gmail dot / `+tag` / `googlemail.com`
  variants of one mailbox share a bucket instead of each getting a fresh budget
  against the same account.

  Pass the client `ip` for unauthenticated flows (login, forgot password).
  The bucket is then per identifier *and* IP, so someone hammering a victim's
  email only exhausts their own budget and cannot lock the victim out of
  sign-in or password recovery. Without `ip` the bucket is global to the
  identifier; use that only where the caller is already authenticated or the
  identifier is a one-time token.

  ## Options

    * `:scope` - bucket namespace, `"id"` by default (account email). Callers
      whose identifier is not an account email and is attacker-chosen (passkey
      `user_id`, one-time tokens) pass their own scope so they can never name,
      and burn, an account's email bucket.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_seconds}` if over limit.
  """
  def check_identifier(identifier, ip \\ nil, opts \\ [])

  def check_identifier(identifier, ip, opts) when is_binary(identifier) do
    RateLimit.check(
      &hit/3,
      identifier_key(identifier, ip, Keyword.get(opts, :scope, "id")),
      @identifier_scale_ms,
      identifier_limit()
    )
  end

  def check_identifier(_, _, _), do: :ok

  defp identifier_key(identifier, nil, scope),
    do: "auth:#{scope}:#{canonical(identifier)}"

  # Distinct `<scope>_ip` namespace, and the IP is length-prefixed, so no
  # identifier text (which the requester controls) can produce another bucket's
  # key, whether global or scoped to a different IP.
  defp identifier_key(identifier, ip, scope) do
    ip = RateLimit.normalize_ip(ip)
    "auth:#{scope}_ip:#{byte_size(ip)}:#{ip}:#{canonical(identifier)}"
  end

  defp canonical(identifier) do
    identifier
    |> RateLimit.normalize_identifier()
    |> Email.normalize()
  end
end
