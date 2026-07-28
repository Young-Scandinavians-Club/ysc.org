defmodule Ysc.Email.DeliveryError do
  @moduledoc false

  @type category ::
          :rate_limited | :quota_exhausted | :transient | :permanent | :unknown

  @spec classify(term()) :: %{
          category: category(),
          code: String.t() | nil,
          message: String.t()
        }
  def classify({:error, %{code: code, message: message}})
      when is_binary(code) do
    category =
      case code do
        code
        when code in [
               "Throttling",
               "ThrottlingException",
               "TooManyRequestsException"
             ] ->
          :rate_limited

        code
        when code in ["AccountSendingPausedException", "DailyQuotaExceeded"] ->
          :quota_exhausted

        code
        when code in ["ServiceUnavailable", "InternalFailure", "RequestTimeout"] ->
          :transient

        _ ->
          :permanent
      end

    %{category: category, code: code, message: to_string(message)}
  end

  def classify({:error, reason})
      when reason in [:timeout, :closed, :econnrefused, :smtp_unavailable],
      do: %{category: :transient, code: nil, message: inspect(reason)}

  def classify({:error, reason}) do
    # Transport adapters expose several opaque error structs. Retrying unknown
    # outcomes is intentional: SES may have accepted a request before a timeout.
    %{category: :unknown, code: nil, message: inspect(reason, limit: :infinity)}
  end

  def classify(error),
    do: %{
      category: :unknown,
      code: nil,
      message: inspect(error, limit: :infinity)
    }

  def retryable?(%{category: category}),
    do: category in [:rate_limited, :quota_exhausted, :transient, :unknown]
end
