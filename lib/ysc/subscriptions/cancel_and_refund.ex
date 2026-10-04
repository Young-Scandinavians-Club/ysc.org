defmodule Ysc.Subscriptions.CancelAndRefund do
  @moduledoc """
  Admin action: end a membership subscription immediately and refund its most
  recent payment.

  Order of operations:

    1. Validate the latest payment is refundable (nothing is changed if not).
    2. Cancel the subscription in Stripe right away (`Subscriptions.cancel_immediately/1`).
    3. Refund the latest payment in Stripe, then record it in the ledger.

  Cancelling before refunding guarantees no further renewal charge can land
  after the refund. If the refund step fails the subscription stays cancelled
  and the error carries the cancelled subscription so the admin can retry the
  refund from the Stripe dashboard.

  The Stripe refund uses a deterministic idempotency key, so retrying never
  double-refunds, and the ledger write is idempotent on the Stripe refund ID
  (the `refund.created` webhook records the same refund).
  """

  require Ysc.Logging

  alias Ysc.Bookings
  alias Ysc.Ledgers
  alias Ysc.Ledgers.Payment
  alias Ysc.MoneyHelper
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

  @type error ::
          :no_payment
          | :payment_not_completed
          | :already_refunded
          | :no_stripe_payment
          | {:cancel_failed, term()}
          | {:refund_failed, struct(), term()}

  @doc """
  Returns `{:ok, %{payment: payment, refundable: money}}` describing what
  `run/2` would refund, or `{:error, reason}` when nothing can be refunded.

  `payments` is the subscription's payment list, newest first
  (`Ledgers.get_payments_for_subscription/1`).
  """
  @spec latest_refundable([Payment.t()]) ::
          {:ok, %{payment: Payment.t(), refundable: Money.t()}}
          | {:error, :no_payment | :payment_not_completed | :already_refunded}
  def latest_refundable([]), do: {:error, :no_payment}

  def latest_refundable([%Payment{} = payment | _]) do
    case payment.status do
      :refunded ->
        {:error, :already_refunded}

      :completed ->
        refunded =
          payment.id
          |> List.wrap()
          |> Ledgers.refund_totals_by_payment_id()
          |> Map.get(payment.id, Money.new(0, :USD))

        refundable = Money.sub!(payment.amount, refunded)

        if Money.positive?(refundable) do
          {:ok, %{payment: payment, refundable: refundable}}
        else
          {:error, :already_refunded}
        end

      _pending_or_failed ->
        {:error, :payment_not_completed}
    end
  end

  @doc """
  Cancels `subscription` immediately and refunds its latest payment.

  Returns `{:ok, %{subscription: sub, payment: payment, refund: refund}}`.
  """
  @spec run(struct()) ::
          {:ok,
           %{
             subscription: struct(),
             payment: Payment.t(),
             refund: Ysc.Ledgers.Refund.t()
           }}
          | {:error, error()}
  def run(%Subscription{} = subscription) do
    payments = Ledgers.get_payments_for_subscription(subscription.id)

    with {:ok, %{payment: payment, refundable: refundable}} <-
           latest_refundable(payments),
         :ok <- ensure_stripe_payment(payment),
         {:ok, cancelled} <- cancel(subscription),
         {:ok, refund} <- refund(payment, refundable, cancelled) do
      {:ok, %{subscription: cancelled, payment: payment, refund: refund}}
    end
  end

  defp ensure_stripe_payment(%Payment{
         external_provider: :stripe,
         external_payment_id: id
       })
       when is_binary(id),
       do: :ok

  defp ensure_stripe_payment(_), do: {:error, :no_stripe_payment}

  defp cancel(subscription) do
    case Subscriptions.cancel_immediately(subscription) do
      {:ok, cancelled} -> {:ok, cancelled}
      {:error, reason} -> {:error, {:cancel_failed, reason}}
    end
  end

  defp refund(%Payment{} = payment, refundable, cancelled) do
    amount_cents = MoneyHelper.money_to_cents(refundable)
    reason = "Membership cancelled and refunded by admin"

    # create_stripe_refund/4 normalizes the key via Ysc.Stripe.Idempotency.
    idempotency_key = "admin_membership_refund_#{payment.id}_#{amount_cents}"

    with {:ok, stripe_refund} <-
           Bookings.create_stripe_refund_for_admin(
             payment.external_payment_id,
             amount_cents,
             reason,
             idempotency_key: idempotency_key
           ),
         {:ok, {refund, _transaction, _entries}} <-
           Ledgers.process_refund(%{
             payment_id: payment.id,
             refund_amount: refundable,
             reason: reason,
             external_refund_id: stripe_refund.id
           }) do
      {:ok, refund}
    else
      {:error, reason} ->
        Ysc.Logging.error("Membership cancelled but refund failed",
          payment_id: payment.id,
          subscription_id: cancelled.id,
          error: inspect(reason)
        )

        {:error, {:refund_failed, cancelled, reason}}
    end
  end
end
