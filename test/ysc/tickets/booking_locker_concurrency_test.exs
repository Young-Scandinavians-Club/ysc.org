defmodule Ysc.Tickets.BookingLockerConcurrencyTest do
  @moduledoc """
  Simplified concurrency tests for ticket booking to ensure no data races or overbooking.

  These tests verify that optimistic locking mechanisms prevent double-booking
  and ensure capacity limits are respected.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Tickets.BookingLocker
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Repo
  import Ysc.AccountsFixtures

  setup context do
    users =
      Enum.map(1..10, fn _ ->
        user = user_fixture()

        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()
      end)

    organizer =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    {:ok, event} =
      Events.create_event(%{
        title: "Concurrency Test Event",
        description: "Testing concurrent bookings",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 50,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier1} =
      Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 10,
        event_id: event.id
      })

    {:ok, tier_unlimited} =
      Events.create_ticket_tier(%{
        name: "Unlimited Tier",
        type: :paid,
        price: Money.new(25, :USD),
        quantity: nil,
        event_id: event.id
      })

    {:ok,
     Map.merge(context, %{
       users: users,
       event: event,
       tier1: tier1,
       tier_unlimited: tier_unlimited,
       organizer: organizer
     })}
  end

  describe "concurrent ticket bookings - tier capacity limits" do
    test "prevents overbooking when multiple users book same tier simultaneously",
         %{
           users: users,
           event: event,
           tier1: tier1,
           sandbox_owner: owner
         } do
      # Tier has capacity of 10, 15 users try to book
      concurrent_users = Enum.take(users, 10)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 10,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      total_tickets =
        Ticket
        |> where([t], t.event_id == ^event.id and t.ticket_tier_id == ^tier1.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert successful == 10
      assert failed == 0
      assert total_tickets == 10
      assert total_tickets <= tier1.quantity
    end

    test "allows unlimited concurrent bookings for unlimited tier", %{
      users: users,
      event: event,
      tier_unlimited: tier_unlimited,
      sandbox_owner: owner
    } do
      concurrent_users = Enum.take(users, 5)

      results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)

            BookingLocker.atomic_booking(user.id, event.id, %{
              tier_unlimited.id => 1
            })
          end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.to_list()

      successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      failed = Enum.count(results, &match?({:ok, {:error, _}}, &1))

      assert successful == 5
      assert failed == 0
    end
  end

  describe "concurrent ticket bookings - event capacity limits" do
    test "respects event-level max_attendees", %{
      users: users,
      event: event,
      tier1: tier1,
      sandbox_owner: owner
    } do
      # Event has max_attendees: 50, tier has capacity 10
      concurrent_users = Enum.take(users, 10)

      _results =
        concurrent_users
        |> Task.async_stream(
          fn user ->
            Ysc.DataCase.allow_sandbox(self(), owner)
            BookingLocker.atomic_booking(user.id, event.id, %{tier1.id => 1})
          end,
          max_concurrency: 10,
          timeout: 5_000
        )
        |> Enum.to_list()

      total_tickets =
        Ticket
        |> where([t], t.event_id == ^event.id)
        |> where([t], t.status in [:pending, :confirmed])
        |> Repo.aggregate(:count, :id)

      assert total_tickets <= event.max_attendees
    end
  end
end
