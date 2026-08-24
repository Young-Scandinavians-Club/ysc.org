defmodule Ysc.Stripe.InvoiceHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.HttpClient.ReqStub
  alias Ysc.Stripe.InvoiceHelpers

  setup context do
    Req.Test.set_req_test_from_context(context)

    on_exit(fn ->
      Application.delete_env(:ysc, :stripe_http_req_opts)
    end)

    Application.put_env(:ysc, :stripe_http_req_opts, plug: {Req.Test, ReqStub})

    :ok
  end

  describe "charge_id/1" do
    test "returns legacy charge ids from maps" do
      assert InvoiceHelpers.charge_id(%{charge: "ch_test"}) == "ch_test"
      assert InvoiceHelpers.charge_id(%{"charge" => "ch_test"}) == "ch_test"
    end

    test "extracts charge id from expanded charge objects" do
      assert InvoiceHelpers.charge_id(%{charge: %{id: "ch_expanded"}}) ==
               "ch_expanded"

      assert InvoiceHelpers.charge_id(%{
               charge: %Stripe.Charge{id: "ch_struct"}
             }) ==
               "ch_struct"
    end

    test "falls back to invoice payments when charge is absent" do
      Req.Test.stub(ReqStub, fn conn ->
        Req.Test.json(conn, %{
          "id" => "pi_missing_charge",
          "object" => "payment_intent",
          "latest_charge" => nil
        })
      end)

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
      Req.Test.stub(ReqStub, fn conn ->
        Req.Test.json(conn, %{
          "id" => "in_test",
          "object" => "invoice",
          "payments" => %{"object" => "list", "data" => [], "has_more" => false}
        })
      end)

      assert InvoiceHelpers.charge_id(%Stripe.Invoice{id: "in_test"}) == nil
      assert InvoiceHelpers.charge_id(%{}) == nil
    end

    test "re-fetches the invoice live when the webhook payload's payments field is nil" do
      # Stripe webhook payloads never carry an expanded `payments` collection
      # (it's `null` as delivered) - the only way to resolve a charge for a
      # webhook-driven invoice is a live re-fetch with `expand: ["payments"]`.
      Req.Test.stub(ReqStub, fn conn ->
        case conn.request_path do
          "/v1/invoices/in_from_webhook" ->
            Req.Test.json(conn, %{
              "id" => "in_from_webhook",
              "object" => "invoice",
              "payments" => %{
                "object" => "list",
                "data" => [
                  %{
                    "id" => "inpay_1",
                    "object" => "invoice_payment",
                    "payment" => %{
                      "type" => "payment_intent",
                      "payment_intent" => "pi_from_refetch"
                    }
                  }
                ],
                "has_more" => false
              }
            })

          "/v1/payment_intents/pi_from_refetch" ->
            Req.Test.json(conn, %{
              "id" => "pi_from_refetch",
              "object" => "payment_intent",
              "latest_charge" => "ch_from_refetch"
            })
        end
      end)

      invoice = %{"id" => "in_from_webhook", "charge" => nil, "payments" => nil}

      assert InvoiceHelpers.charge_id(invoice) == "ch_from_refetch"
    end

    test "returns nil when the invoice has no id to re-fetch" do
      assert InvoiceHelpers.charge_id(%{"charge" => nil, "payments" => nil}) ==
               nil
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

      assert InvoiceHelpers.payment_intent_id(%{payments: %{data: [123]}}) ==
               nil
    end
  end
end
