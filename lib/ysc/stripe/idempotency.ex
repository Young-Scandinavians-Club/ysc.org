defmodule Ysc.Stripe.Idempotency do
  @moduledoc """
  Keeps Stripe idempotency keys within Stripe's 255-character limit.

  Our keys are built from record IDs and short static prefixes, so they stay
  well under the limit today, but nothing stops a future key from growing
  past it (a longer reference format, an extra interpolated field, etc.) -
  Stripe would then reject the request outright. `key/1` is a safety net:
  call it on every Stripe-bound idempotency key right before use.
  """

  @max_length 255
  @hash_length 16

  @doc """
  Returns `raw` unchanged when it's within Stripe's 255-character limit.
  Otherwise truncates and appends a short hash of the full string, so two
  long keys that only differ near the end don't collide after truncation.
  """
  @spec key(String.t()) :: String.t()
  def key(raw) when is_binary(raw) do
    if String.length(raw) <= @max_length do
      raw
    else
      hash =
        :sha256
        |> :crypto.hash(raw)
        |> Base.encode16(case: :lower)
        |> String.slice(0, @hash_length)

      prefix_length = @max_length - @hash_length - 1

      String.slice(raw, 0, prefix_length) <> "_" <> hash
    end
  end
end
