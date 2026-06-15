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
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               Stripe.PaymentIntent.retrieve(pi_id)
             end) do
          {:ok, payment_intent} ->
            Ysc.Stripe.PaymentIntentHelpers.charge_id(payment_intent)

          _ ->
            nil
        end

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
