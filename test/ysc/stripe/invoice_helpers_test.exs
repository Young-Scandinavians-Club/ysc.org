defmodule Ysc.Stripe.InvoiceHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.InvoiceHelpers

  describe "charge_id/1" do
    test "returns legacy charge ids from maps" do
      assert InvoiceHelpers.charge_id(%{charge: "ch_test"}) == "ch_test"
      assert InvoiceHelpers.charge_id(%{"charge" => "ch_test"}) == "ch_test"
    end

    test "extracts charge id from expanded charge objects" do
      assert InvoiceHelpers.charge_id(%{charge: %{id: "ch_expanded"}}) ==
               "ch_expanded"

      assert InvoiceHelpers.charge_id(%{charge: %Stripe.Charge{id: "ch_struct"}}) ==
               "ch_struct"
    end

    test "falls back to invoice payments when charge is absent" do
      invoice = %{
        payments: %Stripe.List{
          data: [%{payment: %{payment_intent: "pi_missing_charge"}}]
        }
      }

      assert InvoiceHelpers.charge_id(invoice) == nil
    end

    test "returns nil for non-map invoices" do
      assert InvoiceHelpers.charge_id(nil) == nil
      assert InvoiceHelpers.charge_id("not-a-map") == nil
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

    test "reads payment intent ids from plain payment maps and list shapes" do
      string_payments_invoice = %{
        "payments" => %{"data" => [%{payment_intent: "pi_from_string_list"}]}
      }

      assert InvoiceHelpers.payment_intent_id(string_payments_invoice) ==
               "pi_from_string_list"

      map_data_invoice = %{
        payments: %{data: [%{"payment_intent" => "pi_string_key"}]}
      }

      assert InvoiceHelpers.payment_intent_id(map_data_invoice) ==
               "pi_string_key"

      plain_map_invoice = %{
        payments: %{data: [%{payment_intent: "pi_direct"}]}
      }

      assert InvoiceHelpers.payment_intent_id(plain_map_invoice) == "pi_direct"
    end

    test "returns nil for non-map invoices and unsupported payment shapes" do
      assert InvoiceHelpers.payment_intent_id(nil) == nil
      assert InvoiceHelpers.payment_intent_id(%{payments: %{data: [123]}}) == nil
    end
  end
end
