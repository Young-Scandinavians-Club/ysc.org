defmodule Ysc.Tickets.ReservationPurchasingIntegrationTest do
  @moduledoc """
  Domain-layer tests for how active ticket reservations interact with public
  purchasing: tier inventory, event max capacity, and checkout enforcement.
  """
  use Ysc.DataCase, async: true

  import Ysc.ReservationPurchasingTestHelpers

  alias Ysc.Events
  alias Ysc.Tickets.{BookingLocker, BookingValidator}

  describe "BookingValidator.check_tier_capacity/3 — tier inventory" do
    test "public pool subtracts all active reservations" do
      ctx = setup_single_tier_event(tier_quantity: 5)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(2, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      assert public_tier_available(ctx.tier) == 1

      assert {:ok, 1} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 1, stranger.id)

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 2, stranger.id)

      assert {:ok, 3} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 3, holder.id)
    end

    test "reservation holder gets their quantity added back to available" do
      ctx = setup_single_tier_event(tier_quantity: 5)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(3, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      assert public_tier_available(ctx.tier) == 0
      assert user_tier_available(ctx.tier, holder.id) == 2

      assert {:ok, 2} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 2, holder.id)

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 3, holder.id)
    end

    test "stranger cannot buy when only another user's holds remain" do
      ctx = setup_single_tier_event(tier_quantity: 3)
      %{stranger: stranger} = ctx

      insert_sold_tickets!(1, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      assert public_tier_available(ctx.tier) == 0

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 1, stranger.id)
    end

    test "expired reservations do not reduce public availability" do
      ctx = setup_single_tier_event(tier_quantity: 3)
      %{stranger: stranger} = ctx

      reservation = insert_reservation!(ctx, 2)
      expire_reservation!(reservation)

      assert public_tier_available(ctx.tier) == 3

      assert {:ok, 3} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 3, stranger.id)
    end

    test "tier fully sold with no reservations blocks everyone" do
      ctx = setup_single_tier_event(tier_quantity: 2)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(2, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 1, holder.id)

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 1, stranger.id)
    end

    test "tier fully held by reservations blocks strangers" do
      ctx = setup_single_tier_event(tier_quantity: 2)
      %{stranger: stranger} = ctx

      insert_reservation!(ctx, 2)

      assert {:error, :insufficient_capacity} =
               BookingValidator.check_tier_capacity(ctx.tier.id, 1, stranger.id)
    end
  end

  describe "BookingValidator.validate_booking/3 — event max capacity" do
    test "stranger blocked when event is sold out and they have no reservation" do
      ctx = setup_single_tier_event(max_attendees: 5, tier_quantity: 20)
      %{stranger: stranger} = ctx

      insert_sold_tickets!(5, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      assert true == BookingValidator.event_at_capacity?(ctx.event.id)

      assert {:error, :event_at_capacity} =
               BookingValidator.validate_booking(
                 stranger.id,
                 ctx.event.id,
                 %{ctx.tier.id => 1}
               )
    end

    test "reservation holder can book when event is publicly at capacity" do
      ctx = setup_single_tier_event(max_attendees: 5, tier_quantity: 7)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(5, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      assert true == BookingValidator.event_at_capacity?(ctx.event.id)

      assert :ok =
               BookingValidator.validate_booking(
                 holder.id,
                 ctx.event.id,
                 %{ctx.tier.id => 2}
               )

      assert {:error, :tier_capacity_exceeded} =
               BookingValidator.validate_booking(
                 holder.id,
                 ctx.event.id,
                 %{ctx.tier.id => 3}
               )
    end

    test "reservation holder bypasses event cap but still respects tier inventory" do
      ctx = setup_single_tier_event(max_attendees: 10, tier_quantity: 4)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(4, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 1)

      assert public_tier_available(ctx.tier) == 0
      assert user_tier_available(ctx.tier, holder.id) == 1

      assert :ok =
               BookingValidator.validate_booking(
                 holder.id,
                 ctx.event.id,
                 %{ctx.tier.id => 1}
               )
    end

    test "stranger blocked at tier level when only holds remain even if event has room" do
      ctx = setup_single_tier_event(max_attendees: 100, tier_quantity: 3)
      %{stranger: stranger} = ctx

      insert_sold_tickets!(1, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      refute BookingValidator.event_at_capacity?(ctx.event.id)

      assert {:error, :tier_capacity_exceeded} =
               BookingValidator.validate_booking(
                 stranger.id,
                 ctx.event.id,
                 %{ctx.tier.id => 1}
               )
    end
  end

  describe "BookingLocker.atomic_booking/3 — checkout enforcement" do
    test "holder completes purchase when tier is publicly sold out" do
      ctx = setup_single_tier_event(tier_quantity: 4)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(3, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 1)

      assert public_tier_available(ctx.tier) == 0

      assert {:ok, order} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })

      assert order.user_id == holder.id
    end

    test "stranger rejected when tier only has holds left" do
      ctx = setup_single_tier_event(tier_quantity: 2)
      %{stranger: stranger} = ctx

      insert_reservation!(ctx, 2)

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(stranger.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })
    end

    test "holder cannot exceed reservation plus public pool" do
      ctx = setup_single_tier_event(tier_quantity: 5)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(4, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 1)

      assert user_tier_available(ctx.tier, holder.id) == 1

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 2
               })
    end

    test "expired hold does not grant holder extra inventory" do
      ctx = setup_single_tier_event(tier_quantity: 2)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(2, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      reservation = insert_reservation!(ctx, 1)
      expire_reservation!(reservation)

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })
    end

    test "multiple holders: each can only claim their own holds" do
      ctx = setup_single_tier_event(tier_quantity: 4)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(2, %{user: holder, event: ctx.event, tier: ctx.tier})

      insert_reservation!(ctx, 1)

      stranger_ctx = Map.put(ctx, :holder, stranger)
      insert_reservation!(stranger_ctx, 1)

      assert public_tier_available(ctx.tier) == 0

      assert {:ok, _} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })

      assert {:ok, _} =
               BookingLocker.atomic_booking(stranger.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })

      assert {:error, :tier_validation_failed} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 1
               })
    end

    test "holder can purchase when event max is reached via sold tickets" do
      ctx = setup_single_tier_event(max_attendees: 3, tier_quantity: 10)
      %{holder: holder, stranger: stranger} = ctx

      insert_sold_tickets!(3, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      assert true == BookingValidator.event_at_capacity?(ctx.event.id)

      assert {:ok, order} =
               BookingLocker.atomic_booking(holder.id, ctx.event.id, %{
                 ctx.tier.id => 2
               })

      assert order.user_id == holder.id
    end
  end

  describe "Events availability helpers" do
    test "batch reserved counts and non-donation event totals" do
      ctx = setup_single_tier_event(max_attendees: 10, tier_quantity: 8)
      %{stranger: stranger} = ctx

      insert_sold_tickets!(5, %{
        user: stranger,
        event: ctx.event,
        tier: ctx.tier
      })

      insert_reservation!(ctx, 2)

      tiers = Events.list_ticket_tiers_for_event(ctx.event.id)

      reserved_counts =
        Events.batch_count_reserved_tickets_for_tiers(Enum.map(tiers, & &1.id))

      assert reserved_counts[ctx.tier.id] == 2

      assert Events.non_donation_reserved_count_from_tiers(
               tiers,
               reserved_counts
             ) == 2

      sold = Events.non_donation_sold_count_from_tiers(tiers)
      assert sold == 5
      assert 10 - sold - 2 == 3
    end
  end
end
