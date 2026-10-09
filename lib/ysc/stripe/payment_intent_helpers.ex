defmodule Ysc.Stripe.PaymentIntentHelpers do
  @moduledoc false

  # Stripe PaymentIntent objects use `latest_charge` (id or expanded Charge).
  # Legacy maps / older payloads may still nest `charges.data`.

  @doc """
  Returns the expanded charge object when present on the payment intent.

  When `latest_charge` is only a charge id string, returns `nil` (use `charge_id/1`).
  """
  @spec first_expanded_charge(term()) :: Stripe.Charge.t() | map() | nil
  def first_expanded_charge(%Stripe.PaymentIntent{latest_charge: lc} = pi) do
    cond do
      is_struct(lc, Stripe.Charge) -> lc
      is_map(lc) -> lc
      true -> first_expanded_charge(Map.from_struct(pi))
    end
  end

  def first_expanded_charge(pi) when is_map(pi) do
    lc = Map.get(pi, :latest_charge) || Map.get(pi, "latest_charge")

    cond do
      is_struct(lc, Stripe.Charge) -> lc
      is_map(lc) -> lc
      true -> legacy_first_charge(pi)
    end
  end

  def first_expanded_charge(_), do: nil

  defp legacy_first_charge(pi) do
    first_from_charges(Map.get(pi, :charges) || Map.get(pi, "charges"))
  end

  defp first_from_charges(%Stripe.List{data: [c | _]}), do: c
  defp first_from_charges(%{data: [c | _]}) when is_map(c), do: c
  defp first_from_charges(%{"data" => [c | _]}) when is_map(c), do: c
  defp first_from_charges(_), do: nil

  @doc """
  Returns a Stripe charge id for the payment intent, from `latest_charge` or legacy `charges`.
  """
  @spec charge_id(term()) :: String.t() | nil
  def charge_id(%Stripe.PaymentIntent{latest_charge: lc} = pi) do
    cond do
      is_binary(lc) -> lc
      is_struct(lc, Stripe.Charge) -> lc.id
      is_map(lc) -> Map.get(lc, :id) || Map.get(lc, "id")
      true -> charge_id(Map.from_struct(pi))
    end
  end

  def charge_id(pi) when is_map(pi) do
    lc = Map.get(pi, :latest_charge) || Map.get(pi, "latest_charge")

    cond do
      is_binary(lc) ->
        lc

      is_map(lc) ->
        Map.get(lc, :id) || Map.get(lc, "id")

      true ->
        case legacy_first_charge(pi) do
          %Stripe.Charge{id: id} when is_binary(id) -> id
          m when is_map(m) -> Map.get(m, :id) || Map.get(m, "id")
          _ -> nil
        end
    end
  end

  def charge_id(_), do: nil

  @doc """
  Returns true when the PaymentIntent's captured charge has been fully refunded.

  Stripe leaves `PaymentIntent.status` as `"succeeded"` after a refund, so
  checkout-abandonment code that only looks at status would treat the refunded
  Intent as a live capture and fulfill it.
  """
  @spec fully_refunded?(term()) :: boolean()
  def fully_refunded?(payment_intent) do
    case first_expanded_charge(payment_intent) do
      nil -> false
      charge -> charge_fully_refunded?(charge)
    end
  end

  defp charge_fully_refunded?(charge) do
    refunded? = charge_get(charge, :refunded) in [true, "true"]
    amount = charge_get(charge, :amount)
    amount_refunded = charge_get(charge, :amount_refunded)

    refunded? or
      (is_integer(amount) and amount > 0 and is_integer(amount_refunded) and
         amount_refunded >= amount)
  end

  defp charge_get(charge, key) when is_map(charge) do
    Map.get(charge, key) || Map.get(charge, Atom.to_string(key))
  end

  defp charge_get(_charge, _key), do: nil
end
