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
      assert TicketTierHelpers.donation_ticket?(%{ticket_tier: %{type: :donation}})
      refute TicketTierHelpers.donation_ticket?(%{ticket_tier: %{type: :paid}})
      refute TicketTierHelpers.donation_ticket?(%{})
    end
  end

  describe "tier_sale_started?/2" do
    test "nil start_date means sale has started" do
      assert TicketTierHelpers.tier_sale_started?(%TicketTier{start_date: nil}, @now)
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
  end
end
