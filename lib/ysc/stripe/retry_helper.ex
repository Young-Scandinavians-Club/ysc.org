defmodule Ysc.Stripe.RetryHelper do
  @moduledoc """
  Transparent retry wrapper for Stripe API calls that handles rate-limit
  (429) responses with exponential backoff + jitter.

  Stripe 429 responses surface as either `%Stripe.Error{code: :rate_limit_error}`
  (when the body carries an explicit type) or `%Stripe.Error{code: :too_many_requests}`
  (when only the HTTP status is present). This module retries on both, up to
  `@max_retries` times with exponential backoff before returning the original error.

  ## Usage

      import Ysc.Stripe.RetryHelper, only: [stripe_retry: 1]

      stripe_retry(fn -> Stripe.Customer.create(params) end)
  """

  require Ysc.Logging

  @max_retries 5
  @base_backoff_ms 1_000

  @transient_error_codes [
    :rate_limit_error,
    :too_many_requests,
    :api_connection_error
  ]

  @transient_http_statuses [500, 502, 503, 504, 529]

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

  @doc """
  Like `stripe_retry/1`, but also retries transient Stripe/network failures
  (connection errors and 5xx responses) with exponential backoff.
  """
  @spec stripe_retry_transient((-> result), keyword()) :: result
        when result: term()
  def stripe_retry_transient(callback, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @max_retries)

    if Ysc.Env.test?() do
      callback.()
    else
      do_retry_transient(callback, 0, max_retries)
    end
  end

  @doc false
  def transient_stripe_error?(%Stripe.Error{} = error) do
    code = Map.get(error, :code)

    cond do
      code in @transient_error_codes ->
        true

      code == :api_error ->
        http_status_transient?(error)

      true ->
        http_status_transient?(error)
    end
  end

  def transient_stripe_error?(_), do: false

  defp http_status_transient?(%Stripe.Error{} = error) do
    case get_http_status(error) do
      status when status in @transient_http_statuses -> true
      _ -> false
    end
  end

  defp get_http_status(%Stripe.Error{extra: %{http_status: status}})
       when is_integer(status),
       do: status

  defp get_http_status(%Stripe.Error{extra: %{"http_status" => status}})
       when is_integer(status),
       do: status

  defp get_http_status(_), do: nil

  defp do_retry_transient(callback, attempt, max_retries) do
    case callback.() do
      {:error, %Stripe.Error{} = error} = err ->
        if transient_stripe_error?(error) and attempt < max_retries do
          sleep_ms = backoff_ms(attempt)

          Ysc.Logging.warning(
            "[Stripe] Transient error #{inspect(error.code)} " <>
              "(attempt #{attempt + 1}/#{max_retries}), retrying in #{sleep_ms}ms"
          )

          Process.sleep(sleep_ms)
          do_retry_transient(callback, attempt + 1, max_retries)
        else
          err
        end

      result ->
        result
    end
  end

  defp backoff_ms(attempt) do
    backoff = @base_backoff_ms * Integer.pow(2, attempt)
    jitter = :rand.uniform(max(div(backoff, 2), 1))
    backoff + jitter
  end

  defp do_retry(callback, attempt) do
    case callback.() do
      {:error, %Stripe.Error{code: code}}
      when code in [:rate_limit_error, :too_many_requests] and
             attempt < @max_retries ->
        sleep_ms = backoff_ms(attempt)

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
