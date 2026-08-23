defmodule Ysc.Tickets.DonationDisplayTest do
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.DonationDisplay

  describe "amounts_by_ticket_id/1" do
    test "splits donation total evenly across donation tickets" do
      ga_tier = %{type: :general, price: Money.new(:USD, "25.00")}
      donation_tier = %{type: :donation, price: nil}

      ga_ticket = %{
        id: "ticket-ga",
        ticket_tier: ga_tier,
        discount_amount: Money.new(0, :USD)
      }

      donation_1 = %{id: "ticket-d1", ticket_tier: donation_tier}
      donation_2 = %{id: "ticket-d2", ticket_tier: donation_tier}

      order = %{
        total_amount: Money.new(:USD, "35.00"),
        tickets: [ga_ticket, donation_1, donation_2]
      }

      assert DonationDisplay.amounts_by_ticket_id(order) == %{
               "ticket-d1" => "$5.00",
               "ticket-d2" => "$5.00"
             }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.equal?(amounts["ticket-ga"], Money.new(:USD, "25.00"))
      assert Money.equal?(amounts["ticket-d1"], Money.new(:USD, "5.00"))
      assert Money.equal?(amounts["ticket-d2"], Money.new(:USD, "5.00"))
    end

    test "keeps original donation share when a sibling donation is cancelled" do
      ga_tier = %{type: :paid, price: Money.new(:USD, "50.00")}
      donation_tier = %{type: :donation, price: nil}

      order = %{
        total_amount: Money.new(:USD, "60.00"),
        tickets: [
          %{
            id: "paid",
            ticket_tier: ga_tier,
            discount_amount: Money.new(0, :USD)
          },
          %{id: "d1", ticket_tier: donation_tier, status: :cancelled},
          %{id: "d2", ticket_tier: donation_tier, status: :confirmed}
        ]
      }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.equal?(amounts["d2"], Money.new(:USD, "5.00"))
    end

    test "subtracts discount from paid ticket net amount" do
      ga_tier = %{type: :paid, price: Money.new(:USD, "50.00")}

      order = %{
        total_amount: Money.new(:USD, "30.00"),
        tickets: [
          %{
            id: "paid",
            ticket_tier: ga_tier,
            discount_amount: Money.new(:USD, "20.00")
          }
        ]
      }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.equal?(amounts["paid"], Money.new(:USD, "30.00"))
    end

    test "returns Donation fallback when order has no positive donation split" do
      donation_tier = %{type: :donation, price: nil}
      donation = %{id: "ticket-d1", ticket_tier: donation_tier}

      order = %{
        total_amount: Money.new(:USD, "0.00"),
        tickets: [donation]
      }

      assert DonationDisplay.amounts_by_ticket_id(order) == %{
               "ticket-d1" => "Donation"
             }
    end

    test "amount_for_ticket/2 uses precomputed map" do
      donation_tier = %{type: :donation, price: nil}
      donation = %{id: "ticket-d1", ticket_tier: donation_tier}

      order = %{
        total_amount: Money.new(:USD, "10.00"),
        tickets: [donation]
      }

      assert DonationDisplay.amount_for_ticket(order, "ticket-d1") == "$10.00"
      assert DonationDisplay.amount_for_ticket(order, "missing") == "Donation"
    end

    test "returns empty maps for orders without a ticket list" do
      assert DonationDisplay.amounts_by_ticket_id(%{}) == %{}
      assert DonationDisplay.amounts_by_ticket_id(nil) == %{}
      assert DonationDisplay.money_amounts_by_ticket_id(%{}) == %{}
      assert DonationDisplay.money_amounts_by_ticket_id(nil) == %{}
    end

    test "falls back to Donation when money amounts cannot be computed" do
      donation = %{id: "ticket-d1", ticket_tier: %{type: :donation, price: nil}}

      assert DonationDisplay.amounts_by_ticket_id(%{tickets: [donation]}) == %{
               "ticket-d1" => "Donation"
             }
    end

    test "treats free tickets as zero regardless of listed price" do
      order = %{
        total_amount: Money.new(:USD, "0.00"),
        tickets: [
          %{
            id: "free-atom",
            ticket_tier: %{type: :free, price: Money.new(:USD, "50.00")},
            discount_amount: Money.new(0, :USD)
          },
          %{
            id: "free-string",
            ticket_tier: %{type: "free", price: Money.new(:USD, "50.00")}
          }
        ]
      }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.zero?(amounts["free-atom"])
      assert Money.zero?(amounts["free-string"])
    end

    test "floors over-discounted paid tickets and nil prices at zero" do
      order = %{
        total_amount: Money.new(:USD, "0.00"),
        tickets: [
          %{
            id: "over-discount",
            ticket_tier: %{type: :paid, price: Money.new(:USD, "20.00")},
            discount_amount: Money.new(:USD, "50.00")
          },
          %{
            id: "nil-price",
            ticket_tier: %{type: :paid, price: nil},
            discount_amount: Money.new(:USD, "5.00")
          }
        ]
      }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.zero?(amounts["over-discount"])
      assert Money.zero?(amounts["nil-price"])
    end

    test "skips mismatched-currency paid tickets when totaling donation remainder" do
      donation = %{id: "d1", ticket_tier: %{type: :donation, price: nil}}

      order = %{
        total_amount: Money.new(:USD, "40.00"),
        tickets: [
          %{
            id: "usd",
            ticket_tier: %{type: :paid, price: Money.new(:USD, "30.00")},
            discount_amount: Money.new(0, :USD)
          },
          %{
            id: "eur",
            ticket_tier: %{type: :paid, price: Money.new(:EUR, "10.00")},
            discount_amount: Money.new(0, :USD)
          },
          donation
        ]
      }

      amounts = DonationDisplay.money_amounts_by_ticket_id(order)
      assert Money.equal?(amounts["usd"], Money.new(:USD, "30.00"))
      assert Money.equal?(amounts["eur"], Money.new(:EUR, "10.00"))
      assert Money.equal?(amounts["d1"], Money.new(:USD, "10.00"))
    end
  end
end
