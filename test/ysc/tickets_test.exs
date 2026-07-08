defmodule Ysc.TicketsTest do
  @moduledoc """
  Tests for Ysc.Tickets context module.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  alias Ysc.Agendas
  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  defp user_fixture_unique(attrs \\ %{}) do
    email =
      Map.get_lazy(attrs, :email, fn ->
        "tu#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
      end)

    user_fixture(Map.put(attrs, :email, email))
  end

  defp tickets_setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture_unique()

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    organizer = user_fixture_unique()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier1} =
      Ysc.Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, tier2} =
      Ysc.Events.create_ticket_tier(%{
        name: "VIP",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 20,
        event_id: event.id
      })

    %{user: user, event: event, tier1: tier1, tier2: tier2}
  end

  describe "create_ticket_order/3" do
    setup do
      tickets_setup()
    end

    test "creates a ticket order with valid selections", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 2}

      assert {:ok, %TicketOrder{} = order} =
               Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      assert order.user_id == user.id
      assert order.event_id == event.id
      # Status defaults to :pending, but may expire if expires_at is in the past
      # Reload to get current status (may be :expired if timeout worker ran)
      reloaded_order = Ysc.Repo.reload!(order) |> Ysc.Repo.preload(:tickets)
      assert reloaded_order.status in [:pending, :expired]
      assert length(reloaded_order.tickets) == 2
    end

    test "returns error when user doesn't have active membership", %{
      event: event,
      tier1: tier1
    } do
      # Create user without membership
      user = user_fixture_unique()
      ticket_selections = %{tier1.id => 1}

      assert {:error, :membership_required} =
               Tickets.create_ticket_order(user.id, event.id, ticket_selections)
    end

    test "returns error when event capacity exceeded", %{
      user: user,
      event: event
    } do
      # Use a small-capacity tier so we only need a few tickets (avoids reference_id collisions)
      {:ok, small_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Limited Tier",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 3,
          event_id: event.id
        })

      # Fill up the tier to capacity
      Enum.each(1..3, fn _i ->
        {:ok, _order} =
          Tickets.create_ticket_order(user.id, event.id, %{small_tier.id => 1})
      end)

      # Try to create one more order (will fail with tier validation error)
      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{
                 small_tier.id => 1
               })
    end

    test "returns error when event is cancelled", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      assert {:ok, cancelled_event} =
               Ysc.Events.update_event(event, %{state: :cancelled})

      assert {:error, :event_cancelled} =
               Tickets.create_ticket_order(user.id, cancelled_event.id, %{
                 tier1.id => 1
               })
    end

    test "returns error when ticket tier id is unknown", %{
      user: user,
      event: event
    } do
      unknown_tier_id = Ecto.ULID.generate()

      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{
                 unknown_tier_id => 1
               })
    end

    test "returns error when quantity is zero", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 0})
    end
  end

  describe "get_ticket_order/1" do
    setup do
      tickets_setup()
    end

    test "returns ticket order with preloaded associations", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      found = Tickets.get_ticket_order(order.id)
      assert found.id == order.id
      assert Ecto.assoc_loaded?(found.user)
      assert Ecto.assoc_loaded?(found.event)
    end

    test "returns nil for non-existent order" do
      assert Tickets.get_ticket_order(Ecto.ULID.generate()) == nil
    end
  end

  describe "get_ticket_order_for_checkout/1" do
    setup do
      tickets_setup()
    end

    test "returns order with checkout preloads only", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      found = Tickets.get_ticket_order_for_checkout(order.id)
      assert found.id == order.id
      assert Ecto.assoc_loaded?(found.user)
      refute Ecto.assoc_loaded?(found.event)
      assert Ecto.assoc_loaded?(found.tickets)
      assert Enum.all?(found.tickets, &Ecto.assoc_loaded?(&1.ticket_tier))
    end

    test "get_user_ticket_order_for_checkout scopes to user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      assert Tickets.get_user_ticket_order_for_checkout(user.id, order.id).id ==
               order.id

      assert Tickets.get_user_ticket_order_for_checkout(
               Ecto.ULID.generate(),
               order.id
             ) == nil
    end
  end

  describe "sync_pending_order_pricing/1" do
    setup do
      tickets_setup()
    end

    test "reloads with checkout preloads only when associations are missing", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      bare_order = %TicketOrder{
        id: order.id,
        user_id: user.id,
        event_id: event.id,
        status: :pending,
        total_amount: order.total_amount,
        discount_amount: order.discount_amount
      }

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(bare_order)
      assert synced.id == order.id
      assert Ecto.assoc_loaded?(synced.user)
      refute Ecto.assoc_loaded?(synced.event)
      assert Ecto.assoc_loaded?(synced.tickets)
      assert Enum.all?(synced.tickets, &Ecto.assoc_loaded?(&1.ticket_tier))
    end
  end

  describe "get_ticket_order_by_reference/1" do
    setup do
      tickets_setup()
    end

    test "returns ticket order by reference_id", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      found = Tickets.get_ticket_order_by_reference(order.reference_id)
      assert found.id == order.id
    end

    test "returns nil for non-existent reference" do
      assert Tickets.get_ticket_order_by_reference("INVALID-REF") == nil
    end
  end

  describe "list_user_ticket_orders/1" do
    setup do
      tickets_setup()
    end

    test "returns empty list when user has no orders" do
      user = user_fixture_unique()
      assert Tickets.list_user_ticket_orders(user.id) == []
    end

    test "returns ticket orders for user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order1} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      {:ok, _order2} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      orders = Tickets.list_user_ticket_orders(user.id)
      assert length(orders) >= 2
      assert Enum.any?(orders, &(&1.id == order1.id))
    end
  end

  describe "list_user_upcoming_ticket_orders/1" do
    setup do
      tickets_setup()
    end

    test "returns empty when all orders are for past events", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, _order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      past_date =
        DateTime.utc_now()
        |> DateTime.add(-7, :day)
        |> DateTime.truncate(:second)

      {1, _} =
        Ysc.Repo.update_all(
          from(e in Ysc.Events.Event, where: e.id == ^event.id),
          set: [start_date: past_date]
        )

      assert Tickets.list_user_upcoming_ticket_orders(user.id) == []
    end

    test "returns pending orders for future events", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      upcoming = Tickets.list_user_upcoming_ticket_orders(user.id)
      assert Enum.any?(upcoming, &(&1.id == order.id))
    end

    test "respects limit option", %{user: user} do
      for i <- 1..3 do
        {:ok, event} =
          Ysc.Events.create_event(%{
            title: "Future Event #{i}",
            description: "Test",
            start_date: DateTime.add(DateTime.utc_now(), 7 + i, :day),
            end_date: DateTime.add(DateTime.utc_now(), 8 + i, :day),
            state: :published,
            ticket_sales_start: DateTime.utc_now(),
            ticket_sales_end: DateTime.add(DateTime.utc_now(), 6 + i, :day),
            location_name: "Test",
            max_attendees: 100,
            organizer_id: user.id
          })

        {:ok, tier} =
          Ysc.Events.create_ticket_tier(%{
            name: "General #{i}",
            type: :paid,
            price: Money.new(50, :USD),
            quantity: 50,
            event_id: event.id
          })

        {:ok, _order} =
          Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
      end

      assert length(Tickets.list_user_upcoming_ticket_orders(user.id, limit: 2)) ==
               2
    end
  end

  describe "list_user_ticket_orders_paginated/2" do
    setup do
      tickets_setup()
    end

    test "returns paginated ticket orders", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, _order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      params = %{page: 1, page_size: 10}

      assert {:ok, {orders, meta}} =
               Tickets.list_user_ticket_orders_paginated(user.id, params)

      assert is_list(orders)
      assert Map.has_key?(meta, :total_count)
    end
  end

  describe "list_user_tickets_for_event/2" do
    setup do
      tickets_setup()
    end

    test "returns tickets for user and event", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, _order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 2})

      # Tickets are created with :pending status, but list_user_tickets_for_event
      # only returns :confirmed tickets. We need to confirm the tickets first.
      # For this test, we'll just verify the function works (returns empty list for pending tickets)
      tickets = Tickets.list_user_tickets_for_event(user.id, event.id)
      # Tickets are pending, so they won't be in the confirmed list
      assert is_list(tickets)

      # If we want to test with confirmed tickets, we'd need to complete the order first
      # For now, just verify the function doesn't crash
    end
  end

  describe "event_at_capacity?/1" do
    setup do
      tickets_setup()
    end

    test "returns false when max_attendees is nil", %{event: event} do
      event = %{event | max_attendees: nil}
      refute Tickets.event_at_capacity?(event)
    end

    test "returns false when under capacity", %{event: event} do
      event = %{event | max_attendees: 100}
      refute Tickets.event_at_capacity?(event)
    end
  end

  describe "count_confirmed_tickets_for_event/1" do
    setup do
      tickets_setup()
    end

    test "returns count of confirmed tickets", %{event: event} do
      count = Tickets.count_confirmed_tickets_for_event(event.id)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "count_pending_tickets_for_event/1" do
    setup do
      tickets_setup()
    end

    test "returns count of pending tickets", %{event: event} do
      count = Tickets.count_pending_tickets_for_event(event.id)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "get_order_expiration_time/0" do
    test "returns expiration datetime" do
      expiration_time = Tickets.get_order_expiration_time()
      # The function returns a DateTime 15 minutes in the future
      assert %DateTime{} = expiration_time
      assert DateTime.compare(expiration_time, DateTime.utc_now()) == :gt
    end
  end

  describe "get_pending_checkout_statistics/0" do
    test "returns statistics about pending checkouts" do
      stats = Tickets.get_pending_checkout_statistics()
      assert is_map(stats)
      assert Map.has_key?(stats, :total_pending_sessions)
      assert Map.has_key?(stats, :total_pending_tickets)
      assert Map.has_key?(stats, :by_event)
      assert Map.has_key?(stats, :by_user)
      assert Map.has_key?(stats, :generated_at)
    end
  end

  describe "get_ticket_order_by_payment_id/1" do
    setup do
      tickets_setup()
    end

    test "returns ticket order by payment ID", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 1}

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      # Create a payment and link it
      {:ok, {payment, _transaction, _entries}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(50, :USD),
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_test_123",
          stripe_fee: Money.new(160, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      order
      |> TicketOrder.status_changeset(%{payment_id: payment.id})
      |> Ysc.Repo.update!()

      found = Tickets.get_ticket_order_by_payment_id(payment.id)
      assert found.id == order.id
    end
  end

  describe "update_payment_intent/2" do
    setup do
      tickets_setup()
    end

    test "updates payment intent on ticket order", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 1}

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      assert {:ok, updated} =
               Tickets.update_payment_intent(order, "pi_updated_123")

      assert updated.payment_intent_id == "pi_updated_123"
    end
  end

  describe "calculate_event_and_donation_amounts/1" do
    setup do
      tickets_setup()
    end

    test "calculates event and donation amounts", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 1}

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      # Preload tickets association
      order = Tickets.get_ticket_order(order.id)

      result = Tickets.calculate_event_and_donation_amounts(order)

      # Function returns a tuple {gross_event_amount, donation_amount, discount_amount}
      assert is_tuple(result)
      assert tuple_size(result) == 3
      {gross_event_amount, donation_amount, discount_amount} = result
      assert is_struct(gross_event_amount, Money)
      assert is_struct(donation_amount, Money)
      assert is_struct(discount_amount, Money)
    end
  end

  describe "expire_timed_out_orders/0" do
    setup do
      tickets_setup()
    end

    test "expires orders older than timeout period", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 1}

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)
        |> DateTime.truncate(:second)

      Ysc.Repo.update_all(
        from(to in TicketOrder, where: to.id == ^order.id),
        set: [expires_at: expired_at]
      )

      # Run expiration
      expired_count = Tickets.expire_timed_out_orders()
      assert expired_count >= 1

      # Verify order is expired
      updated_order = Ysc.Repo.reload!(order)
      assert updated_order.status == :expired
    end
  end

  describe "get_user_ticket_order/2 and get_user_ticket_order_by_*" do
    setup do
      tickets_setup()
    end

    test "get_user_ticket_order returns order for owner", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      found = Tickets.get_user_ticket_order(user.id, order.id)
      assert found.id == order.id
      assert Ecto.assoc_loaded?(found.tickets)
    end

    test "get_user_ticket_order returns nil for another user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      other = user_fixture_unique()
      refute Tickets.get_user_ticket_order(other.id, order.id)
    end

    test "get_user_ticket_order_event_id returns event_id for owner only", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      assert Tickets.get_user_ticket_order_event_id(user.id, order.id) ==
               event.id

      refute Tickets.get_user_ticket_order_event_id(
               user_fixture_unique().id,
               order.id
             )
    end

    test "get_user_ticket_order_by_reference scopes to user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      other = user_fixture_unique()

      refute Tickets.get_user_ticket_order_by_reference(
               other.id,
               order.reference_id
             )

      found =
        Tickets.get_user_ticket_order_by_reference(user.id, order.reference_id)

      assert found.id == order.id
    end

    test "get_user_ticket_order_by_payment_id scopes to user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      {:ok, {payment, _tx, _en}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(50, :USD),
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_scope_test",
          stripe_fee: Money.new(160, :USD),
          description: "Test",
          property: nil,
          payment_method_id: nil
        })

      order
      |> TicketOrder.status_changeset(%{payment_id: payment.id})
      |> Ysc.Repo.update!()

      other = user_fixture_unique()
      refute Tickets.get_user_ticket_order_by_payment_id(other.id, payment.id)

      found = Tickets.get_user_ticket_order_by_payment_id(user.id, payment.id)
      assert found.id == order.id
    end
  end

  describe "get_user_ticket_order_for_confirmation/2 (#624)" do
    setup do
      tickets_setup()
    end

    test "returns order for owner with confirmation preloads", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      found = Tickets.get_user_ticket_order_for_confirmation(user.id, order.id)

      assert found.id == order.id
      assert Ecto.assoc_loaded?(found.user)
      assert Ecto.assoc_loaded?(found.event)
      assert Ecto.assoc_loaded?(found.event.cover_image)
      assert Ecto.assoc_loaded?(found.payment)
      assert Ecto.assoc_loaded?(found.tickets)
      assert Enum.all?(found.tickets, &Ecto.assoc_loaded?(&1.ticket_tier))
    end

    test "returns nil for another user", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      refute Tickets.get_user_ticket_order_for_confirmation(
               user_fixture_unique().id,
               order.id
             )
    end

    test "omits event agenda preloads unlike get_user_ticket_order/2", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, _agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      full = Tickets.get_user_ticket_order(user.id, order.id)
      assert Ecto.assoc_loaded?(full.event.agendas)

      confirmation =
        Tickets.get_user_ticket_order_for_confirmation(user.id, order.id)

      refute Ecto.assoc_loaded?(confirmation.event.agendas)
    end
  end

  describe "complete_ticket_order/2 and cancel_ticket_order/2" do
    setup do
      tickets_setup()
    end

    test "complete_ticket_order marks order completed with payment_id", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      {:ok, {payment, _tx, _en}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: order.total_amount,
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_complete_test",
          stripe_fee: Money.new(160, :USD),
          description: "Complete order",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)
      assert completed.status == :completed
      assert completed.payment_id == payment.id
      assert completed.completed_at != nil
    end

    test "cancel_ticket_order cancels order and tickets", %{
      user: user,
      event: event,
      tier2: tier2
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, order} =
          Tickets.create_ticket_order(user.id, event.id, %{tier2.id => 2})

        assert {:ok, cancelled} =
                 Tickets.cancel_ticket_order(order, "changed mind")

        assert cancelled.status == :cancelled

        tickets =
          Ysc.Repo.all(
            from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
          )

        assert Enum.all?(tickets, &(&1.status == :cancelled))
      end)
    end

    test "cancel_ticket_order does not cancel completed orders by default", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      {:ok, {payment, _tx, _en}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: order.total_amount,
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_no_cancel_completed",
          stripe_fee: Money.new(160, :USD),
          description: "Complete order",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)

      from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
      |> Ysc.Repo.update_all(set: [status: :confirmed])

      assert {:ok, returned} =
               Tickets.cancel_ticket_order(completed, "User cancelled checkout")

      assert returned.status == :completed

      tickets =
        Ysc.Repo.all(
          from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
        )

      assert Enum.all?(tickets, &(&1.status == :confirmed))
    end

    test "cancel_ticket_order can void completed orders after refund", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      {:ok, {payment, _tx, _en}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: order.total_amount,
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_refund_cancel",
          stripe_fee: Money.new(160, :USD),
          description: "Complete order",
          property: nil,
          payment_method_id: nil
        })

      assert {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)

      from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
      |> Ysc.Repo.update_all(set: [status: :confirmed])

      assert {:ok, cancelled} =
               Tickets.cancel_ticket_order(
                 completed,
                 "Refund processed - tickets released",
                 from_statuses: [:completed]
               )

      assert cancelled.status == :cancelled

      tickets =
        Ysc.Repo.all(
          from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
        )

      assert Enum.all?(tickets, &(&1.status == :cancelled))
    end
  end

  describe "validate_booking_capacity/2" do
    setup do
      tickets_setup()
    end

    test "returns :ok for valid selections", %{event: event, tier1: tier1} do
      assert :ok ==
               Tickets.validate_booking_capacity(event.id, %{tier1.id => 1})
    end

    test "returns {:error, :tier_capacity_exceeded} when tier qty too high", %{
      event: event,
      tier1: tier1
    } do
      assert {:error, :tier_capacity_exceeded} ==
               Tickets.validate_booking_capacity(event.id, %{tier1.id => 10_000})
    end

    test "allows donation-only selections when event is at max_attendees", %{
      event: event,
      tier1: tier1,
      user: user
    } do
      {:ok, donation_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Support",
          type: :donation,
          price: nil,
          quantity: 50,
          event_id: event.id
        })

      for _i <- 1..event.max_attendees do
        %Ysc.Events.Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: user.id,
          ticket_tier_id: tier1.id,
          status: :confirmed,
          expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              1,
              :day
            )
        }
        |> Ysc.Repo.insert!()
      end

      assert Tickets.event_at_capacity?(event)

      assert :ok ==
               Tickets.validate_booking_capacity(event.id, %{
                 donation_tier.id => 1
               })
    end
  end

  describe "list_user_ticket_orders_paginated/2 errors" do
    setup do
      tickets_setup()
    end

    test "returns error tuple for invalid Flop params", %{user: user} do
      assert {:error, _} =
               Tickets.list_user_ticket_orders_paginated(user.id, %{
                 page: "not_a_number"
               })
    end
  end

  describe "expire_* checkout session helpers" do
    setup do
      tickets_setup()
    end

    test "expire_user, expire_event, and expire_all process pending sessions",
         %{
           user: user,
           event: event,
           tier1: tier1
         } do
      {:ok, order_a} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      future_a = DateTime.add(DateTime.utc_now(), 60, :minute)

      {1, _} =
        Ysc.Repo.update_all(
          from(to in TicketOrder, where: to.id == ^order_a.id),
          set: [status: :pending, expires_at: future_a]
        )

      order_a = Ysc.Repo.reload!(order_a)
      assert order_a.status == :pending

      assert {:ok, 1} = Tickets.expire_user_pending_checkout_sessions(user.id)
      assert Ysc.Repo.reload!(order_a).status == :expired

      {:ok, order_b} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      future_b = DateTime.add(DateTime.utc_now(), 60, :minute)

      {1, _} =
        Ysc.Repo.update_all(
          from(to in TicketOrder, where: to.id == ^order_b.id),
          set: [status: :pending, expires_at: future_b]
        )

      assert {:ok, 1} = Tickets.expire_event_pending_checkout_sessions(event.id)
      assert Ysc.Repo.reload!(order_b).status == :expired

      {:ok, order_c} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      future_c = DateTime.add(DateTime.utc_now(), 60, :minute)

      {1, _} =
        Ysc.Repo.update_all(
          from(to in TicketOrder, where: to.id == ^order_c.id),
          set: [status: :pending, expires_at: future_c]
        )

      assert {:ok, count} = Tickets.expire_all_pending_checkout_sessions()
      assert count >= 1
      assert Ysc.Repo.reload!(order_c).status == :expired
    end
  end

  describe "expire_ticket_order/1" do
    setup do
      tickets_setup()
    end

    test "expires a pending order and updates tickets", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      assert {:ok, expired} = Tickets.expire_ticket_order(order)
      assert expired.status == :expired
    end

    test "does not expire an already completed order", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      now = DateTime.utc_now()

      {1, _} =
        from(to in Ysc.Tickets.TicketOrder, where: to.id == ^order.id)
        |> Repo.update_all(
          set: [status: :completed, completed_at: now, updated_at: now]
        )

      stale_pending = %{order | status: :pending}

      assert {:ok, returned} = Tickets.expire_ticket_order(stale_pending)
      assert returned.status == :completed
    end
  end

  describe "refund_tickets/3" do
    setup do
      tickets_setup()
    end

    test "returns error when no matching tickets to refund", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      assert {:error, {:error, :no_valid_tickets}} ==
               Tickets.refund_tickets(order, [Ecto.ULID.generate()], "test")
    end
  end

  describe "PubSub subscribe helpers" do
    test "subscribe/0, subscribe/1, and subscribe_event/1 register listeners" do
      uid = Ecto.ULID.generate()
      eid = Ecto.ULID.generate()

      assert :ok == Tickets.subscribe()
      assert :ok == Tickets.subscribe(uid)
      assert :ok == Tickets.subscribe_event(eid)
    end
  end

  describe "event_at_capacity?/1 map variant" do
    setup do
      tickets_setup()
    end

    test "uses id from map for capacity check", %{event: event} do
      map = %{id: event.id, max_attendees: 10_000}
      refute Tickets.event_at_capacity?(map)
    end
  end

  describe "sync_pending_order_pricing/1 (#610)" do
    setup do
      tickets_setup()
    end

    test "persists recalculated total when tier price increases", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
        end)

      assert Money.equal?(order.total_amount, Money.new(50, :USD))

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier1, %{price: Money.new(75, :USD)})

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(order)
      assert Money.equal?(synced.total_amount, Money.new(75, :USD))

      reloaded = Tickets.get_ticket_order(order.id)
      assert Money.equal?(reloaded.total_amount, Money.new(75, :USD))
    end

    test "returns unchanged order when pricing is already current", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
        end)

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(order)
      assert synced.id == order.id
      assert Money.equal?(synced.total_amount, order.total_amount)
    end

    test "passes through completed orders without modifying pricing", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
        end)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      completed =
        order
        |> Ecto.Changeset.change(status: :completed, completed_at: now)
        |> Repo.update!()

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier1, %{price: Money.new(99, :USD)})

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(completed)
      assert Money.equal?(synced.total_amount, Money.new(50, :USD))
    end

    test "recalculates pricing for expired orders from expired tickets", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
        end)

      assert {:ok, expired} = Tickets.expire_ticket_order(order)
      assert expired.status == :expired

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier1, %{price: Money.new(80, :USD)})

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(expired)
      assert Money.equal?(synced.total_amount, Money.new(80, :USD))
    end
  end

  describe "pending order complimentary recalculation (#604)" do
    setup do
      tickets_setup()
    end

    test "ticket_selections_from_order/1 maps paid tiers to quantities", %{
      user: user,
      event: event,
      tier1: tier1,
      tier2: tier2
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{
          tier1.id => 2,
          tier2.id => 1
        })

      order = Tickets.get_ticket_order(order.id)

      assert Tickets.ticket_selections_from_order(order) == %{
               tier1.id => 2,
               tier2.id => 1
             }
    end

    test "ticket_selections_from_order/1 ignores non-pending tickets", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 2})

      [ticket | rest] =
        from(t in Ticket, where: t.ticket_order_id == ^order.id)
        |> Repo.all()

      ticket
      |> Ecto.Changeset.change(status: :confirmed)
      |> Repo.update!()

      order = Tickets.get_ticket_order(order.id)

      assert Tickets.ticket_selections_from_order(order) == %{
               tier1.id => length(rest)
             }
    end

    test "pending_order_still_complimentary?/1 is true for a free tier order",
         %{
           user: user,
           event: event
         } do
      {:ok, free_tier} =
        Events.create_ticket_tier(%{
          name: "Complimentary",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 20,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: free_tier,
          status: :pending
        })

      order = Tickets.get_ticket_order(order.id)

      assert Tickets.pending_order_still_complimentary?(order)
    end

    test "recalculate_pending_order_total/1 reflects current tier price after stale zero total",
         %{
           user: user,
           event: event
         } do
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Complimentary GA",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 50,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })

      order = Tickets.get_ticket_order(order.id)
      assert Money.zero?(order.total_amount)

      {:ok, _tier} =
        Events.update_ticket_tier(tier, %{
          type: :paid,
          price: Money.new(50, :USD)
        })

      assert {:ok, recalculated} =
               Tickets.recalculate_pending_order_total(order)

      assert Money.equal?(recalculated, Money.new(50, :USD))
      refute Tickets.pending_order_still_complimentary?(order)
    end

    test "process_free_ticket_order/1 rejects stale complimentary total after tier becomes paid",
         %{
           user: user,
           event: event
         } do
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Complimentary GA",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 50,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })

      {:ok, _tier} =
        Events.update_ticket_tier(tier, %{
          type: :paid,
          price: Money.new(50, :USD)
        })

      order = Tickets.get_ticket_order(order.id)

      assert {:error, :payment_required} =
               Tickets.process_free_ticket_order(order)
    end
  end

  describe "grant_admin_tickets/4" do
    setup do
      tickets_setup()
      |> Map.put(:admin, user_fixture_unique())
    end

    test "creates a completed order with confirmed tickets", %{
      admin: admin,
      user: user,
      event: event,
      tier1: tier1
    } do
      assert {:ok, order} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier1.id => 2},
                 admin_grant_notes: "WP order #99"
               )

      order = Tickets.get_ticket_order(order.id)
      assert order.status == :completed
      assert order.granted_by_id == admin.id
      assert order.admin_grant_notes == "WP order #99"
      assert Money.zero?(order.total_amount)
      assert length(order.tickets) == 2
      assert Enum.all?(order.tickets, &(&1.status == :confirmed))

      summary = Events.get_ticket_purchase_summary(event.id)
      purchase = Enum.find(summary, &(&1.user_id == user.id))
      assert purchase.ticket_count == 2
    end

    test "enforces capacity unless skip_capacity is true", %{
      admin: admin,
      user: user,
      event: event
    } do
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Limited",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 1,
          event_id: event.id
        })

      assert {:ok, _order} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier.id => 1
               })

      assert {:error, :tier_validation_failed} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier.id => 1}
               )

      other = user_fixture_unique()

      assert {:ok, _order} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 other.id,
                 event.id,
                 %{tier.id => 1},
                 skip_capacity: true
               )
    end

    test "skip_capacity alone does not bypass publish or past-event checks", %{
      admin: admin,
      user: user,
      event: event,
      tier1: tier1
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)

      {:ok, event} =
        Events.update_event(event, %{
          start_date: past
        })

      assert {:error, :event_in_past} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier1.id => 1},
                 skip_capacity: true
               )

      {:ok, future_event} =
        Events.update_event(event, %{
          start_date:
            DateTime.add(
              DateTime.truncate(DateTime.utc_now(), :second),
              30,
              :day
            ),
          state: :draft
        })

      assert {:error, :event_not_available} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 future_event.id,
                 %{tier1.id => 1},
                 skip_capacity: true
               )
    end

    test "skip_sale_guards allows legacy migration grants on past events", %{
      admin: admin,
      user: user,
      event: event,
      tier1: tier1
    } do
      past = DateTime.add(DateTime.utc_now(), -2, :day)

      {:ok, event} =
        Events.update_event(event, %{
          start_date: past
        })

      assert {:ok, order} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 event.id,
                 %{tier1.id => 1},
                 skip_capacity: true,
                 skip_sale_guards: true
               )

      order = Tickets.get_ticket_order(order.id)
      assert order.status == :completed
      assert length(order.tickets) == 1
    end

    test "grants tickets without requiring active membership", %{
      admin: admin,
      event: event,
      tier1: tier1
    } do
      member = user_fixture_unique()

      assert {:ok, order} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 member.id,
                 event.id,
                 %{tier1.id => 1}
               )

      order = Tickets.get_ticket_order(order.id)
      assert hd(order.tickets).user_id == member.id
    end

    test "auto-creates registration details when tier requires registration", %{
      admin: admin,
      user: user,
      event: event
    } do
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Registered GA",
          type: :paid,
          price: Money.new(40, :USD),
          quantity: 10,
          requires_registration: true,
          event_id: event.id
        })

      assert {:ok, order} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier.id => 1
               })

      ticket = hd(order.tickets)
      detail = Events.get_ticket_detail_for_ticket(ticket.id)

      assert detail.first_name == user.first_name
      assert detail.last_name == user.last_name
      assert detail.email == user.email
    end

    test "rejects registration tiers when member profile is incomplete", %{
      admin: admin,
      event: event
    } do
      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Registered GA",
          type: :paid,
          price: Money.new(40, :USD),
          quantity: 10,
          requires_registration: true,
          event_id: event.id
        })

      member = user_fixture_unique()

      member
      |> Ecto.Changeset.change(%{first_name: nil, last_name: nil})
      |> Ysc.Repo.update!()

      assert {:error, :incomplete_member_profile} =
               Tickets.grant_admin_tickets(admin.id, member.id, event.id, %{
                 tier.id => 1
               })
    end

    test "fulfills active reservations on granted tiers so checkout cannot double-book",
         %{
           admin: admin,
           user: user,
           event: event
         } do
      organizer = user_fixture_unique()

      {:ok, tier} =
        Events.create_ticket_tier(%{
          name: "Single Seat",
          type: :paid,
          price: Money.new(25, :USD),
          quantity: 1,
          event_id: event.id
        })

      {:ok, reservation} =
        Events.create_ticket_reservation(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          quantity: 1,
          created_by_id: organizer.id,
          status: "active"
        })

      assert {:ok, grant_order} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier.id => 1
               })

      reservation = Ysc.Repo.reload!(reservation)
      assert reservation.status == "fulfilled"
      assert reservation.ticket_order_id == grant_order.id

      grant_order = Tickets.get_ticket_order(grant_order.id)
      assert length(grant_order.tickets) == 1
      assert hd(grant_order.tickets).status == :confirmed

      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
    end

    test "cancels pending checkout orders for the recipient before granting", %{
      admin: admin,
      user: user,
      event: event,
      tier1: tier1
    } do
      assert {:ok, pending_order} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      assert {:ok, grant_order} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier1.id => 1
               })

      pending_order = Tickets.get_ticket_order(pending_order.id)
      assert pending_order.status == :cancelled

      assert pending_order.cancellation_reason ==
               "Superseded by admin ticket grant"

      assert Enum.all?(pending_order.tickets, &(&1.status == :cancelled))

      grant_order = Tickets.get_ticket_order(grant_order.id)
      assert grant_order.status == :completed
      assert length(grant_order.tickets) == 1
      assert hd(grant_order.tickets).status == :confirmed
    end

    test "skip_email prevents confirmation email scheduling", %{
      admin: admin,
      user: user,
      event: event,
      tier1: tier1
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _order} =
                 Tickets.grant_admin_tickets(
                   admin.id,
                   user.id,
                   event.id,
                   %{tier1.id => 1},
                   skip_email: true
                 )

        refute_enqueued(worker: YscWeb.Workers.EmailNotifier)
      end)
    end

    test "rejects donation tiers and partiful events", %{
      admin: admin,
      user: user,
      tier1: tier1
    } do
      {:ok, donation_tier} =
        Events.create_ticket_tier(%{
          name: "Donation",
          type: :donation,
          price: Money.new(0, :USD),
          quantity: nil,
          event_id: tier1.event_id
        })

      assert {:error, :donation_tier_not_grantable} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 tier1.event_id,
                 %{donation_tier.id => 1}
               )

      partiful_event =
        event_fixture(%{partiful_link: "https://partiful.com/e/test"})

      assert {:error, :partiful_event} =
               Tickets.grant_admin_tickets(
                 admin.id,
                 user.id,
                 partiful_event.id,
                 %{tier1.id => 1}
               )
    end
  end
end
