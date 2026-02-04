defmodule Ysc.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Tickets` context.
  """

  alias Ysc.Tickets
  alias Ysc.EventsFixtures

  def ticket_order_fixture(attrs \\ %{}) do
    user =
      cond do
        attrs[:user] -> attrs[:user]
        attrs[:user_id] -> Ysc.Accounts.get_user!(attrs[:user_id])
        true -> Ysc.AccountsFixtures.user_fixture()
      end

    # Ensure user has membership (required for ticket orders)
    # Always update to ensure membership is set, then reload from DB
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()
      # Reload from DB to ensure the change is reflected when create_ticket_order fetches the user
      |> Ysc.Repo.reload!()

    event = attrs[:event] || EventsFixtures.event_fixture()

    tier =
      attrs[:tier] || EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

    ticket_selections = attrs[:ticket_selections] || %{tier.id => 1}

    {:ok, ticket_order} =
      Tickets.create_ticket_order(user.id, event.id, ticket_selections)

    # Update status if provided
    ticket_order =
      if attrs[:status] do
        ticket_order
        |> Ecto.Changeset.change(status: attrs[:status])
        |> Ysc.Repo.update!()
      else
        ticket_order
      end

    ticket_order
  end
end
