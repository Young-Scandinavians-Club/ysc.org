defmodule Ysc.Stripe.InvoiceHelpers do
  @moduledoc false

  alias Ysc.Stripe.WebhookHandler

  @doc """
  Returns a charge ID from an invoice map or struct.

  Legacy invoices expose `charge` directly. Newer Stripe API versions attach
  payments through the `payments` list and payment intents.
  """
  @spec charge_id(term()) :: binary() | nil
  def charge_id(invoice) when is_map(invoice) do
    case field(invoice, :charge) do
      id when is_binary(id) ->
        id

      expandable ->
        case WebhookHandler.extract_id_from_expandable(expandable) do
          id when is_binary(id) -> id
          _ -> charge_id_from_payments(invoice)
        end
    end
  end

  def charge_id(_), do: nil

  @doc """
  Returns a payment intent ID from an invoice's `payments` collection, if present.
  """
  @spec payment_intent_id(term()) :: binary() | nil
  def payment_intent_id(invoice) when is_map(invoice) do
    invoice
    |> invoice_payments()
    |> Enum.find_value(&payment_intent_id_from_payment/1)
  end

  def payment_intent_id(_), do: nil

  defp charge_id_from_payments(invoice) do
    case payment_intent_id(invoice) do
      pi_id when is_binary(pi_id) ->
        charge_id_from_payment_intent(pi_id)

      _ ->
        charge_id_from_refetched_invoice(invoice)
    end
  end

  # Webhook payloads carry `payments: null` - Stripe only populates an
  # invoice's `payments` collection when explicitly expanded on a live API
  # call, never on the webhook-delivered object. So for any invoice that
  # reached here without a local payment intent id, re-fetch it live before
  # giving up; this is the only way webhook-driven invoices ever resolve a
  # charge (and therefore a Stripe fee) on newer API versions.
  defp charge_id_from_refetched_invoice(invoice) do
    case field(invoice, :id) do
      invoice_id when is_binary(invoice_id) ->
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               Stripe.Invoice.retrieve(invoice_id, expand: ["payments"])
             end) do
          {:ok, refetched_invoice} ->
            case payment_intent_id(refetched_invoice) do
              pi_id when is_binary(pi_id) ->
                charge_id_from_payment_intent(pi_id)

              _ ->
                nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp charge_id_from_payment_intent(pi_id) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           Stripe.PaymentIntent.retrieve(pi_id)
         end) do
      {:ok, payment_intent} ->
        Ysc.Stripe.PaymentIntentHelpers.charge_id(payment_intent)

      _ ->
        nil
    end
  end

  defp invoice_payments(invoice) do
    case field(invoice, :payments) do
      %Stripe.List{data: data} when is_list(data) -> data
      %{data: data} when is_list(data) -> data
      %{"data" => data} when is_list(data) -> data
      _ -> []
    end
  end

  defp payment_intent_id_from_payment(%Stripe.InvoicePayment{payment: payment}) do
    payment_intent_id_from_payment_map(payment)
  end

  defp payment_intent_id_from_payment(%{payment: payment}) do
    payment_intent_id_from_payment_map(payment)
  end

  defp payment_intent_id_from_payment(payment) when is_map(payment) do
    payment_intent_id_from_payment_map(payment)
  end

  defp payment_intent_id_from_payment(_), do: nil

  defp payment_intent_id_from_payment_map(payment) when is_map(payment) do
    field(payment, :payment_intent)
  end

  defp payment_intent_id_from_payment_map(_), do: nil

  defp field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
