defmodule YscWeb.Api.AppTicketsController do
  @moduledoc """
  In-person ticket purchase for the admin/volunteer mobile app.

  Creates a normal `Ysc.Tickets.TicketOrder` for the member being charged —
  the same order/fulfillment pipeline the website's Stripe Elements checkout
  uses, including buying multiple ticket tiers with different quantities in
  one order — but requests a card-present PaymentIntent that the app's
  Stripe Terminal SDK collects and confirms locally (tap-to-pay or an
  inserted/swiped card reader). The existing webhook handler fulfills the
  order on `payment_intent.succeeded` exactly as it does for web purchases.

  Donation tiers are rejected: this endpoint's `tiers` map is
  `ticket_tier_id => quantity`, but `BookingLocker` treats donation values as
  **cents**. Accepting donations here would undercharge (e.g. `50` → $0.50)
  or overcharge when a client follows the quantity contract.
  """
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Events.TicketTier
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.StripeService

  import Ecto.Query, warn: false

  action_fallback YscWeb.Api.FallbackController

  def create_payment_intent(conn, %{
        "event_id" => event_id,
        "member_id" => member_id,
        "tiers" => tiers
      })
      when is_map(tiers) and map_size(tiers) > 0 do
    with {:ok, event} <- fetch_event(event_id),
         {:ok, member} <- fetch_member(member_id),
         {:ok, selections} <- parse_ticket_selections(tiers),
         :ok <- reject_donation_tiers(event.id, selections),
         {:ok, ticket_order} <-
           Tickets.create_ticket_order(member.id, event.id, selections),
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
    |> json(%{
      error:
        "event_id, member_id, and tiers (ticket_tier_id => quantity) are required"
    })
  end

  defp fetch_event(id) do
    with {:ok, cast_id} <- Ecto.ULID.cast(id),
         %Events.Event{} = event <- Events.get_event(cast_id) do
      {:ok, event}
    else
      _ -> {:error, :event_not_found}
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

  defp parse_ticket_selections(tiers) do
    Enum.reduce_while(tiers, {:ok, %{}}, fn {tier_id, quantity}, {:ok, acc} ->
      with {:ok, cast_id} <- Ecto.ULID.cast(tier_id),
           true <- is_integer(quantity) and quantity > 0 do
        {:cont, {:ok, Map.put(acc, cast_id, quantity)}}
      else
        _ -> {:halt, {:error, :invalid_ticket_selection}}
      end
    end)
  end

  # Finding 48: donation map values are cents in BookingLocker, but this API
  # documents and validates them as quantity. Refuse rather than mis-price.
  defp reject_donation_tiers(event_id, selections) do
    tier_ids = Map.keys(selections)

    donation? =
      from(tt in TicketTier,
        where: tt.id in ^tier_ids and tt.event_id == ^event_id
      )
      |> Repo.all()
      |> Enum.any?(&TicketTierHelpers.donation_tier?/1)

    if donation? do
      {:error, :donation_tier_not_supported_in_app}
    else
      :ok
    end
  end
end
