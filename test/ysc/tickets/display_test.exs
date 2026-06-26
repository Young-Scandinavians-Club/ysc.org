defmodule Ysc.Tickets.DisplayTest do
  use Ysc.DataCase, async: true

  alias Ysc.Tickets.Display

  defp ticket(tier_name, status \\ :confirmed) do
    %{
      status: status,
      ticket_tier: if(tier_name, do: %{name: tier_name}, else: nil)
    }
  end

  describe "tier_name/1" do
    test "defaults nil to General Admission" do
      assert Display.tier_name(nil) == "General Admission"
    end

    test "returns the tier name when present" do
      assert Display.tier_name("VIP") == "VIP"
    end
  end

  describe "format_tier_quantities/1" do
    test "groups tickets by tier name" do
      tickets = [
        ticket("VIP"),
        ticket("VIP"),
        ticket("Early Bird")
      ]

      assert Display.format_tier_quantities(tickets) == "1x Early Bird, 2x VIP"
    end

    test "uses General Admission when tier name is missing" do
      tickets = [ticket(nil), ticket("VIP")]

      assert Display.format_tier_quantities(tickets) == "1x General Admission, 1x VIP"
    end

    test "exclude_cancelled omits cancelled tickets" do
      tickets = [
        ticket("VIP"),
        ticket("VIP", :cancelled)
      ]

      assert Display.format_tier_quantities(tickets, exclude_cancelled: true) == "1x VIP"
    end
  end

  describe "format_order_ticket_summary/1" do
    test "returns No ticket details for nil" do
      assert Display.format_order_ticket_summary(nil) == "No ticket details"
    end

    test "summarizes active tickets" do
      tickets = [ticket("VIP"), ticket("VIP")]

      assert Display.format_order_ticket_summary(tickets) == "2x VIP"
    end

    test "reports all tickets refunded when every ticket is cancelled" do
      tickets = [ticket("VIP", :cancelled), ticket("VIP", :cancelled)]

      assert Display.format_order_ticket_summary(tickets) == "All tickets refunded (2 refunded)"
    end

    test "appends refunded count for mixed orders" do
      tickets = [
        ticket("VIP"),
        ticket("Early Bird", :cancelled)
      ]

      assert Display.format_order_ticket_summary(tickets) ==
               "1x VIP (1 refunded)"
    end
  end

  describe "format_ledger_order_description/1" do
    test "includes tier summary when tickets are present" do
      ticket_order = %{
        event: %{title: "Summer Picnic"},
        tickets: [ticket("VIP"), ticket("VIP")]
      }

      assert Display.format_ledger_order_description(ticket_order) ==
               "Free Tickets: Summer Picnic (2x VIP)"
    end

    test "falls back to Event when event is missing" do
      ticket_order = %{event: nil, tickets: []}

      assert Display.format_ledger_order_description(ticket_order) == "Free Tickets: Event"
    end
  end
end
