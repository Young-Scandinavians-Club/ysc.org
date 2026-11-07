defmodule Ysc.TicketAccessFixtures do
  @moduledoc """
  Confirmed event tickets for testing the sign-in-free ticket access paths.
  """

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Tickets

  @doc """
  Grants `count` confirmed tickets to a fresh user who has no membership.

  Returns `%{user: user, event: event, order: order, tickets: tickets}`.
  """
  def granted_tickets(count \\ 1) do
    Ysc.Ledgers.ensure_basic_accounts()
    admin = user_fixture()
    user = user_fixture(%{first_name: "Vera", last_name: "Volunteer"})
    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})

    {:ok, order} =
      Tickets.grant_admin_tickets(
        admin.id,
        user.id,
        event.id,
        %{tier.id => count},
        skip_email: true
      )

    %{user: user, event: event, order: order, tickets: order.tickets}
  end
end
