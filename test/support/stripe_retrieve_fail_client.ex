defmodule Ysc.StripeRetrieveFailClient do
  @moduledoc false
  # Forces `retrieve_payment_intent/2` to fail for tests covering refund error paths.

  @behaviour Ysc.StripeBehaviour

  @impl true
  def retrieve_payment_intent(_id, _opts),
    do: {:error, :forced_retrieve_failure}

  @impl true
  defdelegate create_payment_intent(p, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate cancel_payment_intent(id, o), to: Ysc.TestStripeClient

  @impl true
  defdelegate create_customer(p), to: Ysc.TestStripeClient

  @impl true
  defdelegate update_customer(id, p), to: Ysc.TestStripeClient

  @impl true
  defdelegate retrieve_payment_method(id), to: Ysc.TestStripeClient

  @impl true
  defdelegate list_events(p, o), to: Ysc.TestStripeClient
end
