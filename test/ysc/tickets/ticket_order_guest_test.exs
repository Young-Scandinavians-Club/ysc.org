defmodule Ysc.Tickets.TicketOrderGuestTest do
  use ExUnit.Case, async: true

  alias Ysc.Tickets.TicketOrder

  @guest %TicketOrder{
    user_id: nil,
    guest_email: "g@example.com",
    guest_first_name: "Gus",
    guest_last_name: "Buyer"
  }

  test "guest orders are identified by email" do
    assert TicketOrder.guest?(@guest)
    assert TicketOrder.buyer_email(@guest) == "g@example.com"
    assert TicketOrder.buyer_name(@guest) == "Gus Buyer"
  end

  test "member orders are not guest orders" do
    member = %TicketOrder{
      user_id: "u1",
      user: %{email: "m@example.com", first_name: "Mem", last_name: "Ber"}
    }

    refute TicketOrder.guest?(member)
    assert TicketOrder.buyer_email(member) == "m@example.com"
    assert TicketOrder.buyer_name(member) == "Mem Ber"
  end

  test "display_user shapes guests like users for admin cards" do
    assert %{email: "g@example.com", first_name: "Gus", last_name: "Buyer"} =
             TicketOrder.display_user(@guest)

    assert TicketOrder.display_user(%TicketOrder{user: %{email: "m@x.com"}}) ==
             %{email: "m@x.com"}

    assert TicketOrder.display_user(%TicketOrder{}) == nil
  end

  test "normalize_email trims and lowercases" do
    assert TicketOrder.normalize_email("  A@B.Com ") == "a@b.com"
  end

  test "normalize_email canonicalizes Gmail dots, plus-tags, and googlemail" do
    assert TicketOrder.normalize_email("Jane.Doe+tag@Googlemail.com") ==
             "janedoe@gmail.com"

    assert TicketOrder.normalize_email("jane.doe@gmail.com") ==
             "janedoe@gmail.com"
  end
end
