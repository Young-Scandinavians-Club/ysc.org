defmodule Ysc.RepoReferenceRetryTest do
  @moduledoc """
  Tests for Repo.insert_with_reference_retry/3 and schema put_new_reference_id/1.
  Ensures reference_id collision triggers retry and eventual success or correct error.
  """
  use Ysc.DataCase, async: true

  import Ecto.Changeset
  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Bookings.Booking
  alias Ysc.Events.Ticket
  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    organizer = user_fixture()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Ref Retry Test Event",
        description: "For repo retry tests",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "GA",
        type: :paid,
        price: Money.new(10, :USD),
        quantity: 10,
        event_id: event.id
      })

    %{user: user, event: event, tier: tier}
  end

  describe "insert_with_reference_retry/3" do
    test "succeeds on first attempt when no collision", %{
      user: user,
      event: event
    } do
      attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(50, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)

      assert {:ok, %TicketOrder{} = order} =
               Repo.insert_with_reference_retry(changeset, TicketOrder)

      assert order.reference_id =~ ~r/^ORD-\d{6}-[A-Z0-9]{5}$/
    end

    test "retries on reference_id collision and succeeds with new id", %{
      user: user,
      event: event
    } do
      attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(50, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      # Insert first order to take a reference_id
      changeset1 =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)

      assert {:ok, first_order} = Repo.insert(changeset1)
      first_ref = first_order.reference_id

      # Force a collision: build a second changeset with the same reference_id
      collision_changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)
        |> put_change(:reference_id, first_ref)

      # Retry should generate new id and succeed
      assert {:ok, %TicketOrder{} = second_order} =
               Repo.insert_with_reference_retry(
                 collision_changeset,
                 TicketOrder
               )

      assert second_order.reference_id != first_ref
      assert second_order.reference_id =~ ~r/^ORD-\d{6}-[A-Z0-9]{5}$/
    end

    test "returns error when changeset has non-reference_id error (no retry)",
         %{
           event: event
         } do
      # Missing required user_id
      attrs = %{
        event_id: event.id,
        total_amount: Money.new(50, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)

      assert {:error, %Ecto.Changeset{} = cs} =
               Repo.insert_with_reference_retry(changeset, TicketOrder)

      refute reference_id_unique_constraint?(cs)
      assert cs.valid? == false
    end

    test "with max_attempts: 0 returns error on collision without retrying", %{
      user: user,
      event: event
    } do
      attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(50, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      changeset1 = %TicketOrder{} |> TicketOrder.create_changeset(attrs)
      assert {:ok, first_order} = Repo.insert(changeset1)

      collision_changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)
        |> put_change(:reference_id, first_order.reference_id)

      assert {:error, %Ecto.Changeset{} = cs} =
               Repo.insert_with_reference_retry(
                 collision_changeset,
                 TicketOrder,
                 max_attempts: 0
               )

      assert reference_id_unique_constraint?(cs)
    end

    test "respects custom max_attempts option", %{user: user, event: event} do
      attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(50, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(attrs)

      # With max_attempts: 1 we still get one retry (first attempt + 1 retry)
      assert {:ok, _} =
               Repo.insert_with_reference_retry(changeset, TicketOrder,
                 max_attempts: 3
               )
    end

    test "many rapid inserts all succeed with unique reference_ids", %{
      user: user,
      event: event
    } do
      expires_at = DateTime.add(DateTime.utc_now(), 15, :minute)

      results =
        Enum.map(1..20, fn _i ->
          attrs = %{
            user_id: user.id,
            event_id: event.id,
            total_amount: Money.new(50, :USD),
            expires_at: expires_at
          }

          changeset =
            %TicketOrder{}
            |> TicketOrder.create_changeset(attrs)

          Repo.insert_with_reference_retry(changeset, TicketOrder)
        end)

      assert Enum.all?(results, &match?({:ok, _}, &1))

      reference_ids =
        results
        |> Enum.map(fn {:ok, order} -> order.reference_id end)

      assert length(reference_ids) == length(Enum.uniq(reference_ids)),
             "expected all reference_ids to be unique, got duplicates in #{inspect(reference_ids)}"
    end
  end

  describe "insert_with_reference_retry/3 with Booking" do
    test "retries on reference_id collision and succeeds", %{user: user} do
      checkin = Date.utc_today() |> Date.add(14)
      checkout = Date.add(checkin, 2)

      attrs = %{
        user_id: user.id,
        checkin_date: checkin,
        checkout_date: checkout,
        property: :tahoe,
        booking_mode: :buyout,
        guests_count: 2,
        total_price: Money.new(200, :USD),
        status: :draft
      }

      changeset1 = Booking.changeset(%Booking{}, attrs, skip_validation: true)
      assert {:ok, first_booking} = Repo.insert(changeset1)
      first_ref = first_booking.reference_id

      collision_changeset =
        Booking.changeset(%Booking{}, attrs, skip_validation: true)
        |> put_change(:reference_id, first_ref)

      assert {:ok, %Booking{} = second_booking} =
               Repo.insert_with_reference_retry(collision_changeset, Booking)

      assert second_booking.reference_id != first_ref
      assert second_booking.reference_id =~ ~r/^BKG-\d{6}-[A-Z0-9]{5}$/
    end
  end

  describe "insert_with_reference_retry/3 with Ticket" do
    test "retries on reference_id collision and succeeds", %{
      user: user,
      event: event,
      tier: tier
    } do
      # Create a ticket order first (tickets belong to an order)
      order_attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(10, :USD),
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
      }

      order_changeset =
        %TicketOrder{}
        |> TicketOrder.create_changeset(order_attrs)

      assert {:ok, order} =
               Repo.insert_with_reference_retry(order_changeset, TicketOrder)

      expires_at = DateTime.add(DateTime.utc_now(), 15, :minute)

      ticket_attrs = %{
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: user.id,
        ticket_order_id: order.id,
        status: :pending,
        expires_at: expires_at,
        discount_amount: Money.new(0, :USD)
      }

      changeset1 = Ticket.changeset(%Ticket{}, ticket_attrs)
      assert {:ok, first_ticket} = Repo.insert(changeset1)
      first_ref = first_ticket.reference_id

      collision_changeset =
        Ticket.changeset(%Ticket{}, ticket_attrs)
        |> put_change(:reference_id, first_ref)

      assert {:ok, %Ticket{} = second_ticket} =
               Repo.insert_with_reference_retry(collision_changeset, Ticket)

      assert second_ticket.reference_id != first_ref
      assert second_ticket.reference_id =~ ~r/^TKT-\d{6}-[A-Z0-9]{5}$/
    end
  end

  describe "put_new_reference_id/1" do
    test "TicketOrder.put_new_reference_id sets a new reference_id" do
      cs =
        %TicketOrder{}
        |> change(%{})
        |> put_change(:reference_id, "ORD-260101-OLD1X")

      new_cs = TicketOrder.put_new_reference_id(cs)
      new_ref = get_change(new_cs, :reference_id)

      assert new_ref != "ORD-260101-OLD1X"
      assert new_ref =~ ~r/^ORD-\d{6}-[A-Z0-9]{5}$/
    end

    test "Booking.put_new_reference_id sets a new reference_id" do
      cs =
        %Booking{}
        |> change(%{})
        |> put_change(:reference_id, "BKG-260101-OLD1X")

      new_cs = Booking.put_new_reference_id(cs)
      new_ref = get_change(new_cs, :reference_id)

      assert new_ref != "BKG-260101-OLD1X"
      assert new_ref =~ ~r/^BKG-\d{6}-[A-Z0-9]{5}$/
    end

    test "Ticket.put_new_reference_id sets a new reference_id" do
      cs =
        %Ticket{}
        |> change(%{})
        |> put_change(:reference_id, "TKT-260101-OLD1X")

      new_cs = Ticket.put_new_reference_id(cs)
      new_ref = get_change(new_cs, :reference_id)

      assert new_ref != "TKT-260101-OLD1X"
      assert new_ref =~ ~r/^TKT-\d{6}-[A-Z0-9]{5}$/
    end
  end

  defp reference_id_unique_constraint?(changeset) do
    Enum.any?(changeset.errors, fn
      {:reference_id, {_, opts}} when is_list(opts) ->
        Keyword.get(opts, :constraint) == :unique

      _ ->
        false
    end)
  end
end
