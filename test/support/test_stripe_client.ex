defmodule Ysc.TestStripeClient do
  @moduledoc false

  @behaviour Ysc.StripeBehaviour

  # This is a lightweight, non-networking Stripe client for tests that don't
  # explicitly configure `:stripe_client` via `Application.put_env/3`.
  #
  # Individual tests can still override `:stripe_client` to use Mox-based mocks.

  @impl true
  def create_payment_intent(_params, _opts), do: {:error, :not_implemented}

  @impl true
  def retrieve_payment_intent(id, _opts) when is_binary(id) do
    charge = %Stripe.Charge{id: "ch_test_#{id}"}

    payment_intent = %Stripe.PaymentIntent{
      id: id,
      charges: %Stripe.List{data: [charge]}
    }

    {:ok, payment_intent}
  end

  @impl true
  def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}

  @impl true
  def create_customer(params) do
    {:ok, %Stripe.Customer{id: "cus_test", email: Map.get(params, :email)}}
  end

  @impl true
  def update_customer(id, params) do
    {:ok, %Stripe.Customer{id: id, email: Map.get(params, :email)}}
  end

  @impl true
  def retrieve_payment_method(_id), do: {:error, :not_implemented}
end
