defmodule Ysc.Merch.StripeService do
  @moduledoc """
  Stripe PaymentIntents for merch purchase orders.

  The amount always comes from the order's server-side totals, never from the
  client. An order keeps a single PaymentIntent; a retry reuses it so the
  member can never end up paying twice for one order.
  """
  require Ysc.Logging

  alias Ysc.Accounts.User
  alias Ysc.Merch.{Order, Orders}
  alias Ysc.MoneyHelper
  alias Ysc.Stripe.Idempotency

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  # Statuses in which the member can still (re)attempt payment on the Intent.
  @reusable_statuses [
    "requires_payment_method",
    "requires_confirmation",
    "requires_action"
  ]

  @doc """
  Returns a PaymentIntent for a pending purchase order, creating one if needed.

  `{:error, :not_payable}` for anything but a pending purchase with a positive
  total; otherwise `{:error, message}` with member-safe text.
  """
  @spec ensure_payment_intent(Order.t(), User.t()) ::
          {:ok, Stripe.PaymentIntent.t()} | {:error, :not_payable | String.t()}
  def ensure_payment_intent(
        %Order{kind: :purchase, status: :pending} = order,
        %User{} = user
      ) do
    amount_cents = MoneyHelper.money_to_cents(order.total_amount)

    cond do
      amount_cents <= 0 -> {:error, :not_payable}
      order.payment_intent_id -> reuse_or_create(order, user, amount_cents)
      true -> create(order, user, amount_cents)
    end
  end

  def ensure_payment_intent(%Order{}, _user), do: {:error, :not_payable}

  defp reuse_or_create(order, user, amount_cents) do
    case stripe_client().retrieve_payment_intent(order.payment_intent_id, %{}) do
      {:ok, %{status: status, amount: ^amount_cents} = intent}
      when status in @reusable_statuses ->
        {:ok, intent}

      {:ok, %{status: "succeeded"} = intent} ->
        # Already paid; the caller should finalize the order, not charge again.
        {:ok, intent}

      _ ->
        create(order, user, amount_cents)
    end
  end

  defp create(order, user, amount_cents) do
    params = %{
      amount: amount_cents,
      currency: "usd",
      automatic_payment_methods: %{enabled: true},
      description: "Merch - Order #{order.reference_id}",
      metadata: %{
        merch_order_id: order.id,
        merch_order_reference: order.reference_id,
        user_id: user.id
      }
    }

    {params, _user} =
      Ysc.Customers.attach_customer_to_payment_intent_params(params, user)

    # Amount in the key so a repriced order gets a fresh Intent rather than a
    # stale one back from Stripe.
    idempotency_key =
      Idempotency.key("merch_order_#{order.reference_id}_#{amount_cents}")

    case stripe_client().create_payment_intent(params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, %{amount: ^amount_cents} = intent} ->
        case Orders.attach_payment_intent(order, intent.id) do
          {:ok, _} ->
            {:ok, intent}

          {:error, _} ->
            {:error, Ysc.PaymentUserMessages.payment_setup_failed()}
        end

      {:ok, intent} ->
        Ysc.Logging.warning(
          "Stripe returned a merch PaymentIntent with a stale amount",
          order_id: order.id,
          expected_cents: amount_cents,
          payment_intent_id: intent.id,
          payment_intent_cents: intent.amount
        )

        {:error, Ysc.PaymentUserMessages.payment_setup_failed()}

      {:error, %Stripe.Error{} = error} ->
        {:error, Ysc.PaymentUserMessages.format_stripe_error(error)}

      {:error, _reason} ->
        {:error, Ysc.PaymentUserMessages.payment_setup_failed()}
    end
  end

  @doc """
  Cancels an abandoned PaymentIntent. Returns `{:ok, :canceled}`, or
  `{:ok, :succeeded}` when the member in fact paid (the caller must then
  finalize the order rather than cancel it).
  """
  @spec cancel_payment_intent(String.t()) ::
          {:ok, :canceled | :succeeded} | {:error, term()}
  def cancel_payment_intent(payment_intent_id) do
    case stripe_client().cancel_payment_intent(payment_intent_id, %{}) do
      {:ok, _} ->
        {:ok, :canceled}

      {:error, %Stripe.Error{message: message} = error} ->
        cond do
          String.contains?(message || "", "succeeded") -> {:ok, :succeeded}
          String.contains?(message || "", "already") -> {:ok, :canceled}
          true -> {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
