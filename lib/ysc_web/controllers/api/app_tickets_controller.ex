defmodule YscWeb.Api.AppTicketsController do
  @moduledoc """
  In-person ticket purchase for the admin/volunteer mobile app.

  Creates a normal `Ysc.Tickets.TicketOrder` for the member being charged —
  the same order/fulfillment pipeline the website's Stripe Elements checkout
  uses — but requests a card-present PaymentIntent that the app's Stripe
  Terminal SDK collects and confirms locally (tap-to-pay or an inserted/swiped
  card reader). The existing webhook handler fulfills the order on
  `payment_intent.succeeded` exactly as it does for web purchases.
  """
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Tickets
  alias Ysc.Tickets.StripeService

  action_fallback YscWeb.Api.FallbackController

  def create_payment_intent(conn, %{
        "ticket_tier_id" => ticket_tier_id,
        "member_id" => member_id
      }) do
    with {:ok, tier} <- fetch_ticket_tier(ticket_tier_id),
         {:ok, member} <- fetch_member(member_id),
         {:ok, ticket_order} <-
           Tickets.create_ticket_order(member.id, tier.event_id, %{tier.id => 1}),
         {:ok, payment_intent} <-
           StripeService.create_payment_intent(ticket_order,
             user: member,
             card_present: true
           ) do
      render(conn, :payment_intent,
        payment_intent: payment_intent,
        ticket_order: ticket_order
      )
    end
  end

  def create_payment_intent(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "ticket_tier_id and member_id are required"})
  end

  defp fetch_ticket_tier(id) do
    with {:ok, cast_id} <- Ecto.ULID.cast(id),
         %Events.TicketTier{} = tier <- Events.get_ticket_tier(cast_id) do
      {:ok, tier}
    else
      _ -> {:error, :ticket_tier_not_found}
    end
  end

  defp fetch_member(id) do
    with {:ok, cast_id} <- Ecto.ULID.cast(id),
         %Accounts.User{} = member <- Accounts.get_user(cast_id) do
      {:ok, member}
    else
      _ -> {:error, :member_not_found}
    end
  end
end
