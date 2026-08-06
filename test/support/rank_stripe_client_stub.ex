defmodule Ysc.RankStripeClientStub do
  @moduledoc false
  # Used by PaymentMethodFormatterTest to force payment-method/charge lookups
  # to fail while exercising `payment_details_from_payment_intent/2`'s
  # rank-based tie-breaking between an intent's payment_method and charge.

  def retrieve_payment_method("pm_unknown"), do: {:error, :not_found}
  def retrieve_charge("ch_unknown", _opts), do: {:error, :not_found}
end
