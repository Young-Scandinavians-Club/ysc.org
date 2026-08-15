defmodule Ysc.Events.TicketTierHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.{TicketTier, TicketTierHelpers}

  @now ~U[2026-07-15 12:00:00Z]
  @past ~U[2026-07-10 12:00:00Z]
  @future ~U[2026-07-20 12:00:00Z]

  describe "donation_tier?/1" do
    test "recognizes donation type atoms and strings" do
      assert TicketTierHelpers.donation_tier?(:donation)
      assert TicketTierHelpers.donation_tier?("donation")
    end

    test "recognizes donation on structs and maps" do
      tier = %TicketTier{type: :donation}
      assert TicketTierHelpers.donation_tier?(tier)
      assert TicketTierHelpers.donation_tier?(%{type: "donation"})
      assert TicketTierHelpers.donation_tier?(%{"type" => :donation})
    end

    test "returns false for non-donation tiers" do
      refute TicketTierHelpers.donation_tier?(:paid)
      refute TicketTierHelpers.donation_tier?(%TicketTier{type: :paid})
      refute TicketTierHelpers.donation_tier?(%{type: :free})
    end
  end

  describe "donation_ticket?/1" do
    test "checks nested ticket_tier" do
      assert TicketTierHelpers.donation_ticket?(%{
               ticket_tier: %{type: :donation}
             })

      refute TicketTierHelpers.donation_ticket?(%{ticket_tier: %{type: :paid}})
      refute TicketTierHelpers.donation_ticket?(%{})
    end
  end

  describe "tier_sale_started?/2" do
    test "nil start_date means sale has started" do
      assert TicketTierHelpers.tier_sale_started?(
               %TicketTier{start_date: nil},
               @now
             )

      assert TicketTierHelpers.tier_sale_started?(%{"start_date" => nil}, @now)
    end

    test "compares against start_date" do
      refute TicketTierHelpers.tier_sale_started?(
               %TicketTier{start_date: @future},
               @now
             )

      assert TicketTierHelpers.tier_sale_started?(
               %TicketTier{start_date: @past},
               @now
             )
    end
  end

  describe "tier_on_sale?/2 and tier_sale_ended?/2" do
    test "on sale when started and not ended" do
      tier = %TicketTier{start_date: @past, end_date: @future}

      assert TicketTierHelpers.tier_on_sale?(tier, @now)
      refute TicketTierHelpers.tier_sale_ended?(tier, @now)
    end

    test "not on sale when sale ended" do
      tier = %TicketTier{start_date: @past, end_date: @past}

      refute TicketTierHelpers.tier_on_sale?(tier, @now)
      assert TicketTierHelpers.tier_sale_ended?(tier, @now)
    end

    test "not on sale before start" do
      tier = %TicketTier{start_date: @future, end_date: nil}

      refute TicketTierHelpers.tier_on_sale?(tier, @now)
      refute TicketTierHelpers.tier_sale_ended?(tier, @now)
    end

    test "works with plain maps using atom or string date keys" do
      tier = %{
        "start_date" => @past,
        "end_date" => @future
      }

      assert TicketTierHelpers.tier_on_sale?(tier, @now)
      refute TicketTierHelpers.tier_sale_ended?(tier, @now)

      ended_tier = %{start_date: @past, end_date: @past}

      refute TicketTierHelpers.tier_on_sale?(ended_tier, @now)
      assert TicketTierHelpers.tier_sale_ended?(ended_tier, @now)
    end

    test "Pacific end-of-day sale end stays on sale through the labeled calendar day" do
      # Admin picks Aug 14 as sale end; DateRangePicker stores Aug 14 23:59:59 PDT.
      end_of_sale_day = ~U[2026-08-15 06:59:59Z]
      tier = %TicketTier{start_date: @past, end_date: end_of_sale_day}

      late_on_sale_day = ~U[2026-08-15 05:00:00Z]

      assert TicketTierHelpers.tier_on_sale?(tier, late_on_sale_day)
      refute TicketTierHelpers.tier_sale_ended?(tier, late_on_sale_day)

      after_sale_day = ~U[2026-08-15 07:00:00Z]

      refute TicketTierHelpers.tier_on_sale?(tier, after_sale_day)
      assert TicketTierHelpers.tier_sale_ended?(tier, after_sale_day)
    end

    test "midnight UTC sale end incorrectly expires before the labeled Pacific day" do
      # Pre-fix storage: picking Aug 14 anchored to Aug 14 00:00:00Z (5pm Aug 13 PDT).
      buggy_end = ~U[2026-08-14 00:00:00Z]
      tier = %TicketTier{start_date: @past, end_date: buggy_end}

      during_labeled_day = ~U[2026-08-14 12:00:00Z]

      refute TicketTierHelpers.tier_on_sale?(tier, during_labeled_day)
      assert TicketTierHelpers.tier_sale_ended?(tier, during_labeled_day)
    end
  end
end
