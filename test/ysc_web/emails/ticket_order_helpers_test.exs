defmodule YscWeb.Emails.TicketOrderHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.Emails.TicketOrderHelpers

  describe "tier_total/2" do
    test "multiplies a unit price by quantity" do
      assert Money.equal?(
               TicketOrderHelpers.tier_total(Money.new(:USD, "12.50"), 3),
               Money.new(:USD, "37.50")
             )
    end

    test "returns $0 for non-money prices" do
      assert Money.equal?(
               TicketOrderHelpers.tier_total(nil, 2),
               Money.new(0, :USD)
             )

      assert Money.equal?(
               TicketOrderHelpers.tier_total("12.50", 2),
               Money.new(0, :USD)
             )
    end
  end

  describe "donation_amounts/2" do
    test "splits remainder of total_amount after list prices evenly" do
      ga_tier = %{id: "ga", type: :general, price: Money.new(:USD, "25.00")}
      donation_tier = %{id: "don", type: :donation, price: nil}

      ga = %{id: "t-ga", ticket_tier_id: "ga", ticket_tier: ga_tier}

      d1 = %{
        id: "t-d1",
        ticket_tier_id: "don",
        ticket_tier: donation_tier
      }

      d2 = %{
        id: "t-d2",
        ticket_tier_id: "don",
        ticket_tier: donation_tier
      }

      order = %{
        total_amount: Money.new(:USD, "35.00"),
        tickets: [ga, d1, d2]
      }

      assert TicketOrderHelpers.donation_amounts([d1, d2], order) ==
               {"$5.00", "$10.00"}
    end

    test "returns $0.00 strings when the remainder is not positive" do
      donation_tier = %{id: "don", type: :donation, price: nil}

      donation = %{
        id: "t-d1",
        ticket_tier_id: "don",
        ticket_tier: donation_tier
      }

      order = %{
        total_amount: Money.new(:USD, "0.00"),
        tickets: [donation]
      }

      assert TicketOrderHelpers.donation_amounts([donation], order) ==
               {"$0.00", "$0.00"}
    end

    test "returns $0.00 strings when the order has no tickets list" do
      donation = %{id: "t-d1", ticket_tier_id: "don"}

      assert TicketOrderHelpers.donation_amounts([donation], %{}) ==
               {"$0.00", "$0.00"}

      assert TicketOrderHelpers.donation_amounts([], %{tickets: []}) ==
               {"$0.00", "$0.00"}
    end
  end

  describe "tier_summaries/3" do
    test "groups paid tickets by tier without discount keys by default" do
      ga_tier = %{
        id: "ga",
        type: :general,
        name: "GA",
        price: Money.new(:USD, "20.00")
      }

      tickets = [
        %{
          id: "a",
          ticket_tier_id: "ga",
          ticket_tier: ga_tier,
          discount_amount: nil
        },
        %{
          id: "b",
          ticket_tier_id: "ga",
          ticket_tier: ga_tier,
          discount_amount: nil
        }
      ]

      order = %{total_amount: Money.new(:USD, "40.00"), tickets: tickets}

      assert TicketOrderHelpers.tier_summaries(tickets, order) == [
               %{
                 ticket_tier_name: "GA",
                 quantity: 2,
                 price_per_ticket: "$20.00",
                 total_price: "$40.00"
               }
             ]
    end

    test "includes original price and member discount when discounts: true" do
      ga_tier = %{
        id: "ga",
        type: :general,
        name: "GA",
        price: Money.new(:USD, "50.00")
      }

      tickets = [
        %{
          id: "a",
          ticket_tier_id: "ga",
          ticket_tier: ga_tier,
          discount_amount: Money.new(:USD, "10.00")
        }
      ]

      order = %{total_amount: Money.new(:USD, "40.00"), tickets: tickets}

      [row] =
        TicketOrderHelpers.tier_summaries(tickets, order, discounts: true)

      assert row.ticket_tier_name == "GA"
      assert row.quantity == 1
      assert row.price_per_ticket == "$50.00"
      assert row.original_price == "$50.00"
      assert row.total_price == "$40.00"
      assert row.discount_amount == "$10.00"
      assert_in_delta row.discount_percentage, 20.0, 0.01
    end

    test "summarizes donation tiers from the order remainder" do
      ga_tier = %{
        id: "ga",
        type: :general,
        name: "GA",
        price: Money.new(:USD, "25.00")
      }

      donation_tier = %{
        id: "don",
        type: :donation,
        name: "Donation",
        price: nil
      }

      ga = %{
        id: "t-ga",
        ticket_tier_id: "ga",
        ticket_tier: ga_tier,
        discount_amount: Money.new(0, :USD)
      }

      donation = %{
        id: "t-d1",
        ticket_tier_id: "don",
        ticket_tier: donation_tier
      }

      tickets = [ga, donation]

      order = %{
        total_amount: Money.new(:USD, "40.00"),
        tickets: tickets
      }

      rows = TicketOrderHelpers.tier_summaries(tickets, order)
      donation_row = Enum.find(rows, &(&1.ticket_tier_name == "Donation"))

      assert donation_row.quantity == 1
      assert donation_row.price_per_ticket == "$15.00"
      assert donation_row.total_price == "$15.00"
      refute Map.has_key?(donation_row, :discount_percentage)
    end

    test "raises when a ticket is missing its tier association" do
      tickets = [%{id: "orphan", ticket_tier_id: "missing", ticket_tier: nil}]
      order = %{total_amount: Money.new(0, :USD), tickets: tickets}

      assert_raise ArgumentError,
                   ~r/Ticket missing ticket_tier association/,
                   fn ->
                     TicketOrderHelpers.tier_summaries(tickets, order)
                   end
    end
  end

  describe "ticket_refs/2" do
    test "maps reference id and tier name" do
      tickets = [
        %{
          reference_id: "T-1",
          status: :confirmed,
          ticket_tier: %{name: "GA"}
        }
      ]

      assert TicketOrderHelpers.ticket_refs(tickets) == [
               %{reference_id: "T-1", ticket_tier_name: "GA"}
             ]
    end

    test "includes status when requested and falls back for a missing tier" do
      tickets = [
        %{reference_id: "T-2", status: :cancelled, ticket_tier: nil}
      ]

      assert TicketOrderHelpers.ticket_refs(tickets, status: true) == [
               %{
                 reference_id: "T-2",
                 ticket_tier_name: "Unknown Tier",
                 status: :cancelled
               }
             ]
    end
  end
end
