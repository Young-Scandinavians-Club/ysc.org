defmodule Ysc.Stripe.InvoiceHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.InvoiceHelpers

  describe "charge_id/1" do
    test "returns legacy charge ids from maps" do
      assert InvoiceHelpers.charge_id(%{charge: "ch_test"}) == "ch_test"
      assert InvoiceHelpers.charge_id(%{"charge" => "ch_test"}) == "ch_test"
    end

    test "returns nil when no charge or payments are present" do
      assert InvoiceHelpers.charge_id(%Stripe.Invoice{id: "in_test"}) == nil
      assert InvoiceHelpers.charge_id(%{}) == nil
    end
  end

  describe "payment_intent_id/1" do
    test "reads payment intent ids from invoice payments" do
      invoice = %{
        payments: %Stripe.List{
          data: [
            %Stripe.InvoicePayment{
              id: "inpay_test",
              payment: %{payment_intent: "pi_test", type: :payment_intent}
            }
          ]
        }
      }

      assert InvoiceHelpers.payment_intent_id(invoice) == "pi_test"
    end
  end
end
