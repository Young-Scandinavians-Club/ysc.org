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
  end
end
