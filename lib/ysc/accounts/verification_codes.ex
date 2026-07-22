defmodule Ysc.Accounts.VerificationCodes do
  @moduledoc """
  Central API for email and phone verification codes.

  All LiveViews and controllers should use this module for issuing, ensuring,
  resending, and verifying OTP codes so behavior stays consistent site-wide
  (Postgres-backed storage, resend throttling, attempt throttling, and the
  non-prod `000000` bypass).
  """

  alias Ysc.EmailVerificationRateLimit
  alias Ysc.ResendRateLimiter
  alias Ysc.VerificationCache

  @default_ttl_seconds 600
  @resend_seconds 60

  @type channel :: :email | :phone
  @type issue_result :: %{
          code: String.t(),
          reused?: boolean(),
          sent?: boolean(),
          disabled_until: DateTime.t() | nil
        }

  @doc "Default code lifetime in seconds (10 minutes)."
  def default_ttl_seconds, do: @default_ttl_seconds

  @doc "Default resend cooldown in seconds."
  def resend_seconds, do: @resend_seconds

  @doc """
  Generates a cryptographically strong 6-digit numeric code.
  """
  def generate_code do
    <<n::unsigned-integer-32>> = :crypto.strong_rand_bytes(4)

    n
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @doc """
  Normalizes OTP input from OTP inputs (map/list/string) into a digit string.
  """
  def normalize_otp_input(code) when is_map(code) do
    code
    |> Enum.filter(fn {k, _v} ->
      match?({_int, ""}, Integer.parse(to_string(k)))
    end)
    |> Enum.sort_by(fn {k, _v} ->
      {i, ""} = Integer.parse(to_string(k))
      i
    end)
    |> Enum.map(fn {_k, v} -> to_string(v) end)
    |> Enum.reject(&(&1 in ["", "nil"]))
    |> Enum.join("")
  end

  def normalize_otp_input(code) when is_list(code) do
    code
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 in ["", "nil"]))
    |> Enum.join("")
  end

  def normalize_otp_input(code) when is_binary(code), do: code
  def normalize_otp_input(_), do: ""

  @doc """
  Returns true when the normalized value looks like a complete 6-digit OTP.
  """
  def valid_otp_format?(code) when is_binary(code) do
    String.length(code) == 6 and String.match?(code, ~r/^\d{6}$/)
  end

  def valid_otp_format?(_), do: false

  @doc """
  Stores a verification code for the given channel.
  """
  def store(user, channel, code, expires_in_seconds \\ @default_ttl_seconds) do
    VerificationCache.store_code(
      user.id,
      code_type(channel),
      code,
      expires_in_seconds
    )
  end

  @doc """
  Generates, stores, and returns a verification code (does not send).
  """
  def generate_and_store(
        user,
        channel,
        expires_in_seconds \\ @default_ttl_seconds
      ) do
    code = generate_code()
    :ok = store(user, channel, code, expires_in_seconds)
    code
  end

  @doc """
  Returns the current plaintext code if present and unexpired, else `nil`.
  """
  def get(user, channel) do
    case VerificationCache.get_code(user.id, code_type(channel)) do
      {:ok, code} -> code
      {:error, _} -> nil
    end
  end

  @doc """
  Removes any stored code for the channel.
  """
  def remove(user, channel) do
    VerificationCache.remove_code(user.id, code_type(channel))
  end

  @doc """
  Always generates a new code, stores it, and sends it.

  ## Options
  - `:to` — destination override (`target_email` or `to_phone`)
  - `:ttl` — expiry in seconds (default #{@default_ttl_seconds})
  - `:suffix` — idempotency key suffix (default `issue_<unique>`)
  """
  def issue(user, channel, opts \\ []) when channel in [:email, :phone] do
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)
    to = Keyword.get(opts, :to)
    suffix = Keyword.get(opts, :suffix) || unique_delivery_suffix("issue")

    code = generate_and_store(user, channel, ttl)
    _job = deliver(user, channel, code, to: to, suffix: suffix)

    {:ok,
     %{
       code: code,
       reused?: false,
       sent?: true,
       disabled_until: nil
     }}
  end

  @doc """
  Ensures a valid code exists. Reuses an unexpired code without re-sending;
  otherwise issues and sends a new one.

  Useful for mount/auto-send paths that must not spam the user on refresh.
  """
  def ensure(user, channel, opts \\ []) when channel in [:email, :phone] do
    case VerificationCache.get_code(user.id, code_type(channel)) do
      {:ok, code} ->
        {:ok,
         %{
           code: code,
           reused?: true,
           sent?: false,
           disabled_until: nil
         }}

      {:error, _} ->
        opts = Keyword.put_new(opts, :suffix, "initial")
        issue(user, channel, opts)
    end
  end

  @doc """
  Resends a verification code with resend rate limiting.

  Reuses an unexpired code when present; otherwise generates a new one.
  Always sends (so the user receives the code again).

  ## Options
  - `:to` — destination override
  - `:ttl` — used only when generating a new code
  - `:rate_limit_seconds` — resend cooldown (default #{@resend_seconds})

  Returns:
  - `{:ok, result}` with `disabled_until` set for UI cooldown
  - `{:error, :rate_limited, remaining_seconds}`
  """
  def resend(user, channel, opts \\ []) when channel in [:email, :phone] do
    rate_limit_seconds = Keyword.get(opts, :rate_limit_seconds, @resend_seconds)
    to = Keyword.get(opts, :to)
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)

    case ResendRateLimiter.check_and_record_resend(
           user.id,
           resend_type(channel),
           rate_limit_seconds
         ) do
      {:ok, :allowed} ->
        {code, reused?} =
          case VerificationCache.get_code(user.id, code_type(channel)) do
            {:ok, existing} ->
              {existing, true}

            {:error, _} ->
              {generate_and_store(user, channel, ttl), false}
          end

        suffix =
          if reused?,
            do: unique_delivery_suffix("resend_existing"),
            else: unique_delivery_suffix("resend_new")

        _job = deliver(user, channel, code, to: to, suffix: suffix)

        {:ok,
         %{
           code: code,
           reused?: reused?,
           sent?: true,
           disabled_until: ResendRateLimiter.disabled_until(rate_limit_seconds)
         }}

      {:error, :rate_limited, remaining} ->
        {:error, :rate_limited, remaining}
    end
  end

  @doc """
  Delivers an already-stored verification code via email or SMS.

  Prefer `issue/3` or `resend/3` unless you already generated the code.
  """
  def deliver(user, channel, code, opts \\ [])
      when channel in [:email, :phone] and is_binary(code) do
    to = Keyword.get(opts, :to)
    suffix = Keyword.get(opts, :suffix)
    do_deliver(user, channel, code, suffix, to)
  end

  @doc """
  Verifies a code with attempt rate limiting.

  Returns:
  - `{:ok, :verified}`
  - `{:error, :rate_limited}`
  - `{:error, :invalid_code | :expired | :not_found}`
  """
  def verify(user, channel, provided_code) when channel in [:email, :phone] do
    code = normalize_otp_input(provided_code)

    case EmailVerificationRateLimit.check(user.id, attempt_type(channel)) do
      :rate_limited ->
        {:error, :rate_limited}

      :ok ->
        do_verify(user, channel, code)
    end
  end

  @doc """
  Verifies without attempt rate limiting. Prefer `verify/3` in user-facing flows.
  """
  def verify_unchecked(user, channel, provided_code)
      when channel in [:email, :phone] do
    do_verify(user, channel, normalize_otp_input(provided_code))
  end

  # -- delivery ----------------------------------------------------------------

  defp do_deliver(user, :email, code, suffix, to) do
    email_address = to || user.email
    suffix_part = if suffix, do: "_#{suffix}", else: ""
    idempotency_key = "account_setup_verification_#{user.id}#{suffix_part}"

    YscWeb.Emails.Notifier.schedule_email(
      email_address,
      idempotency_key,
      "Verify Your Email Address - YSC",
      "account_setup_verification",
      %{
        first_name: user.first_name,
        verification_code: code
      },
      """
      ==============================

      Hi #{Ysc.title_case(user.first_name)},

      Your verification code is: #{code}

      This code will expire in 10 minutes.

      ==============================
      """,
      user.id
    )
  end

  defp do_deliver(user, :phone, code, suffix, to) do
    suffix_part = if suffix, do: "_#{suffix}", else: ""
    idempotency_key = "phone_verification_#{user.id}#{suffix_part}"
    destination = to || user.phone_number

    YscWeb.Sms.Notifier.schedule_sms(
      destination,
      idempotency_key,
      "phone_verification",
      YscWeb.Sms.PhoneVerification.prepare_sms_data(user, code),
      user.id
    )
  end

  defp do_verify(user, channel, provided_code) do
    if Ysc.Env.non_prod?() and provided_code == "000000" do
      # Consume any stored code so retries behave like a real success.
      _ = remove(user, channel)
      {:ok, :verified}
    else
      VerificationCache.verify_code(user.id, code_type(channel), provided_code)
    end
  end

  defp code_type(:email), do: :email_verification
  defp code_type(:phone), do: :phone_verification

  defp resend_type(:email), do: :email
  defp resend_type(:phone), do: :sms

  defp attempt_type(:email), do: :email
  defp attempt_type(:phone), do: :phone

  # Oban email/SMS notifiers dedupe on idempotency_key while incomplete
  # (period: :infinity). Seconds-resolution suffixes can collide and skip delivery.
  defp unique_delivery_suffix(prefix) when is_binary(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end

  @doc false
  def ci_query_explain_query do
    VerificationCache.ci_query_explain_query()
  end
end
