defmodule Ysc.Printful.Error do
  @moduledoc """
  Error returned by `Ysc.Printful.Client`.

  `type` tells callers whether to retry:

    * transient (`:network`, `:rate_limited`, `:server`) - retry later
    * permanent (`:invalid`, `:auth`, `:not_found`, `:not_configured`) - retrying
      the same request will not help; surface it for a human
  """
  defexception [:type, :status, :message, :retry_after]

  @type type ::
          :network
          | :rate_limited
          | :server
          | :invalid
          | :auth
          | :not_found
          | :not_configured

  @type t :: %__MODULE__{
          type: type(),
          status: non_neg_integer() | nil,
          message: String.t(),
          retry_after: non_neg_integer() | nil
        }

  @transient [:network, :rate_limited, :server]

  @doc """
  True when the same request may succeed if retried later.
  """
  @spec transient?(t() | term()) :: boolean()
  def transient?(%__MODULE__{type: type}), do: type in @transient
  def transient?(_), do: false
end
