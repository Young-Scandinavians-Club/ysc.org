defmodule Ysc.Stripe.RetryHelper do
  @moduledoc """
  Transparent retry wrapper for Stripe API calls that handles rate-limit
  (429) responses with exponential backoff + jitter.

  Stripe returns `%Stripe.Error{code: :rate_limit_error}` on 429.
  This module retries up to `@max_retries` times with exponential backoff
  before returning the original error.

  ## Usage

      import Ysc.Stripe.RetryHelper, only: [stripe_retry: 1]

      stripe_retry(fn -> Stripe.Customer.create(params) end)
  """

  require Ysc.Logging

  @max_retries 5
  @base_backoff_ms 1_000

  @doc """
  Executes `callback` and retries on Stripe rate-limit errors.

  Returns whatever the callback returns once it succeeds or a non-rate-limit
  result is produced. Rate-limit retries use exponential backoff (1 s, 2 s,
  4 s, 8 s, 16 s) plus random jitter.
  """
  @spec stripe_retry((-> result)) :: result when result: term()
  def stripe_retry(callback) do
    if Ysc.Env.test?() do
      callback.()
    else
      do_retry(callback, 0)
    end
  end

  defp do_retry(callback, attempt) do
    case callback.() do
      {:error, %Stripe.Error{code: :rate_limit_error}}
      when attempt < @max_retries ->
        backoff = @base_backoff_ms * Integer.pow(2, attempt)
        jitter = :rand.uniform(max(div(backoff, 2), 1))
        sleep_ms = backoff + jitter

        Ysc.Logging.warning(
          "[Stripe] Rate limited (attempt #{attempt + 1}/#{@max_retries}), retrying in #{sleep_ms}ms"
        )

        Process.sleep(sleep_ms)
        do_retry(callback, attempt + 1)

      result ->
        result
    end
  end
end
