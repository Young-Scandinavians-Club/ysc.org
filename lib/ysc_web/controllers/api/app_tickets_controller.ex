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

  Both sale paths below bypass the web checkout's "event already started"
  and tier-sale-window guards, and allow exceeding tier/event capacity
  instead of rejecting the sale — this app is for selling in person *while*
  an event is happening, precisely to solve on-the-spot problems (a tier
  capped too low, a walk-in after the posted start time). Membership and
  member-only-tier eligibility are unaffected. A capacity overage doesn't
  fail silently: the response includes `warnings`, computed before the sale
  via `BookingLocker.capacity_warnings/2`, so the app can show the seller
  what they're about to exceed.
  """
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Events.TicketTier
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.BookingLocker
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
         {:ok, selected_tiers} <- load_selected_tiers(event.id, selections),
         :ok <- reject_donation_tiers(selected_tiers),
         warnings <-
           BookingLocker.capacity_warnings(event.id, selections,
             event: event,
             tiers: selected_tiers
           ),
         {:ok, ticket_order} <-
           Tickets.create_ticket_order(member.id, event.id, selections,
             bypass_guards: true,
             user: member,
             event: event,
             tiers: selected_tiers
           ),
         {:ok, payment_intent} <-
           StripeService.create_payment_intent(ticket_order,
             user: member,
             card_present: true,
             tiers: selected_tiers
           ) do
      render(conn, :payment_intent,
        payment_intent: payment_intent,
        ticket_order: ticket_order,
        warnings: warnings
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

  @offline_payment_methods ~w(cash check other)

  @doc """
  Records tickets a member paid for in person with cash or a check — no card
  is collected. Reuses `Ysc.Tickets.grant_admin_tickets/5`, the same primitive
  behind the web admin ticket-tier grant: it creates a completed order with
  confirmed tickets, broadcasts availability, and — because we do not pass
  `skip_email` — sends the member the ticket confirmation email.

  The order total is $0 (a grant, not a charge). How the money was actually
  collected is persisted as typed columns on the order —
  `payment_channel` and `offline_amount_collected` (a `Money`) — for treasurer
  reconciliation; `admin_grant_notes` carries only the human-readable note.
  Event revenue reports are unaffected.

  Capacity and sale-window guards are bypassed here the same way as
  `create_payment_intent/2` — see this module's moduledoc. Donation tiers
  are rejected, matching `create_payment_intent/2`.
  """
  def grant_offline_order(
        conn,
        %{"event_id" => event_id, "member_id" => member_id, "tiers" => tiers} =
          params
      )
      when is_map(tiers) and map_size(tiers) > 0 do
    with {:ok, event} <- fetch_event(event_id),
         {:ok, member} <- fetch_member(member_id),
         :ok <- require_active_membership(member),
         {:ok, selections} <- parse_ticket_selections(tiers),
         {:ok, selected_tiers} <- load_selected_tiers(event.id, selections),
         :ok <- reject_donation_tiers(selected_tiers),
         {:ok, payment_method} <- parse_offline_payment_method(params),
         warnings <-
           BookingLocker.capacity_warnings(event.id, selections,
             event: event,
             tiers: selected_tiers
           ),
         {:ok, ticket_order} <-
           Tickets.grant_admin_tickets(
             conn.assigns.current_user.id,
             member.id,
             event.id,
             selections,
             [
               {:skip_capacity, true},
               {:skip_sale_guards, true},
               {:payment_channel, payment_method},
               {:user, member},
               {:event, event},
               {:tiers, selected_tiers},
               {:admin_grant_notes,
                offline_note(payment_method, blank_to_nil(params["note"]))}
               | offline_amount_opt(params["amount_collected_cents"])
             ]
           ) do
      render(conn, :offline_order,
        ticket_order: ticket_order,
        warnings: warnings
      )
    end
  end

  def grant_offline_order(conn, _params) do
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

  defp load_selected_tiers(event_id, selections) do
    tier_ids = Map.keys(selections)

    tiers =
      from(tt in TicketTier,
        where: tt.id in ^tier_ids and tt.event_id == ^event_id
      )
      |> Repo.all()

    if length(tiers) == length(tier_ids) do
      {:ok, tiers}
    else
      {:error, :invalid_ticket_tier}
    end
  end

  # Finding 48: donation map values are cents in BookingLocker, but this API
  # documents and validates them as quantity. Refuse rather than mis-price.
  defp reject_donation_tiers(tiers) when is_list(tiers) do
    if Enum.any?(tiers, &TicketTierHelpers.donation_tier?/1) do
      {:error, :donation_tier_not_supported_in_app}
    else
      :ok
    end
  end

  # `grant_admin_tickets/5` itself does not gate on membership (admins grant
  # comps to non-members). An in-person sale should follow the same rule as
  # the card path (`Tickets.create_ticket_order/3`), so enforce it here.
  defp require_active_membership(member) do
    if Accounts.has_active_membership?(member) do
      :ok
    else
      {:error, :membership_required}
    end
  end

  defp parse_offline_payment_method(params) do
    case Map.get(params, "payment_method", "cash") do
      method when method in @offline_payment_methods -> {:ok, method}
      _ -> {:error, :invalid_offline_payment_method}
    end
  end

  # Human-readable audit context only — the payment method and collected
  # amount live in the `payment_channel` / `offline_amount_collected` columns,
  # and the acting user in `granted_by_id`.
  defp offline_note(payment_method, nil),
    do: "In-person #{payment_method} payment recorded via the admin app"

  defp offline_note(payment_method, note),
    do:
      "In-person #{payment_method} payment recorded via the admin app — #{note}"

  defp offline_amount_opt(cents) when is_integer(cents) and cents >= 0,
    do: [offline_amount_collected: Ysc.MoneyHelper.cents_to_money(cents, :USD)]

  defp offline_amount_opt(_), do: []

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil
end
