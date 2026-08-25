defmodule Ysc.Tickets.CheckoutCancel do
  @moduledoc """
  Guards for cancelling pending ticket checkout orders without racing Stripe.

  Used when users close checkout and when admin grants supersede an open cart.
  """

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder

  @blocked_pi_statuses ~w(requires_action processing requires_confirmation succeeded)

  @doc """
  Returns pending checkout orders for a user/event that block admin grants.

  Orders with in-flight or succeeded payment intents must not be cancelled
  while a complimentary grant is being created, or the member can be charged
  without ticket fulfillment or end up double-booked.
  """
  def blocking_pending_orders(user_id, event_id) do
    pending_orders_query(user_id, event_id)
    |> Repo.all()
    |> Enum.reject(
      &pending_order_safe_to_cancel?(&1, context: "admin_grant_precheck")
    )
  end

  @doc """
  Returns true when checkout has a Stripe payment that must not be cancelled,
  repriced, or expired (3DS, processing, succeeded, or redirect in progress).
  """
  def checkout_payment_in_flight?(%TicketOrder{} = order, opts \\ []) do
    not pending_order_safe_to_cancel?(order, opts)
  end

  @doc """
  Returns whether a pending ticket order can be cancelled without racing Stripe.
  """
  def pending_order_safe_to_cancel?(%TicketOrder{} = order, opts \\ []) do
    if Keyword.get(opts, :payment_redirect_in_progress, false) do
      false
    else
      case order.payment_intent_id do
        nil ->
          true

        payment_intent_id ->
          payment_intent_allows_checkout_cancel?(
            payment_intent_id,
            order.id,
            Keyword.get(opts, :context, "checkout")
          )
      end
    end
  end

  @doc """
  Resolves a checkout abandonment by attempting to *cancel* the order's Stripe
  PaymentIntent, rather than merely reading its status.

  A point-in-time status read (as used by `pending_order_safe_to_cancel?/2`) leaves
  a gap: the client can still be mid-confirmation when we read "not yet succeeded,"
  and can complete the charge with Stripe moments after we decide it's safe to
  cancel locally, orphaning a captured payment against an order nobody will ever
  fulfill. Calling Stripe's cancel endpoint instead closes that gap, because Stripe
  itself is the atomic arbiter: it only refuses to cancel a PaymentIntent that has
  already succeeded or is actively processing, and once it accepts the cancel, that
  PaymentIntent can never be confirmed successfully afterwards - so a client that's
  still mid-flow gets a hard failure from Stripe instead of silently completing a
  charge behind our back.

  Returns:
    * `{:cancel, nil}` - no PaymentIntent on the order, nothing to reconcile with Stripe
    * `{:cancel, payment_intent}` - Stripe confirms the PaymentIntent is canceled (or already was)
    * `{:already_succeeded, payment_intent}` - Stripe refused to cancel because the
      payment already went through; the caller must fulfill the order instead of
      cancelling it, or the payment is orphaned
    * `{:in_progress, payment_intent}` - Stripe refused to cancel because it's
      actively processing (e.g. ACH); do not cancel, let it resolve via webhook
    * `{:error, reason}` - could not reach Stripe; be conservative and don't cancel
  """
  def cancel_payment_intent_for_abandoned_checkout(
        ticket_order,
        context \\ "cancel_ticket_order"
      )

  def cancel_payment_intent_for_abandoned_checkout(
        %TicketOrder{payment_intent_id: nil},
        _context
      ) do
    {:cancel, nil}
  end

  def cancel_payment_intent_for_abandoned_checkout(
        %TicketOrder{payment_intent_id: payment_intent_id, id: ticket_order_id},
        context
      ) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.cancel_payment_intent(payment_intent_id, %{}) do
      {:ok, payment_intent} ->
        {:cancel, payment_intent}

      {:error, %Stripe.Error{}} ->
        resolve_uncancellable_payment_intent(
          stripe_client,
          payment_intent_id,
          ticket_order_id,
          context
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_uncancellable_payment_intent(
         stripe_client,
         payment_intent_id,
         ticket_order_id,
         context
       ) do
    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, %{status: "succeeded"} = payment_intent} ->
        Ysc.Logging.warning(
          "Payment succeeded before checkout-abandonment cancel reached Stripe; fulfilling instead of orphaning it",
          context: context,
          payment_intent_id: payment_intent_id,
          ticket_order_id: ticket_order_id
        )

        {:already_succeeded, payment_intent}

      {:ok, %{status: "canceled"} = payment_intent} ->
        {:cancel, payment_intent}

      {:ok, payment_intent} ->
        {:in_progress, payment_intent}

      {:error, reason} ->
        Ysc.Logging.warning(
          "Could not retrieve payment intent after failed cancel, not cancelling order",
          context: context,
          payment_intent_id: payment_intent_id,
          ticket_order_id: ticket_order_id
        )

        {:error, reason}
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    pending_orders_query(Fixtures.ulid(), Fixtures.ulid())
  end

  defp pending_orders_query(user_id, event_id) do
    from(to in TicketOrder,
      where:
        to.user_id == ^user_id and to.event_id == ^event_id and
          to.status == :pending
    )
  end

  defp payment_intent_allows_checkout_cancel?(
         payment_intent_id,
         ticket_order_id,
         context
       ) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, payment_intent} ->
        case payment_intent.status do
          status when status in @blocked_pi_statuses ->
            false

          _ ->
            true
        end

      {:error, _} ->
        Ysc.Logging.warning(
          "Could not retrieve payment intent status, not cancelling order",
          context: context,
          payment_intent_id: payment_intent_id,
          ticket_order_id: ticket_order_id
        )

        false
    end
  end
end
