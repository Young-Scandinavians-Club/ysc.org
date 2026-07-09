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
    |> Enum.reject(&pending_order_safe_to_cancel?(&1, context: "admin_grant_precheck"))
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

  def pending_order_safe_to_cancel?(_order, _opts), do: true

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
