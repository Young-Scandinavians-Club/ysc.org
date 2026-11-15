defmodule YscWeb.TicketUserMessagesTest do
  use ExUnit.Case, async: true

  alias YscWeb.TicketUserMessages

  test "unpaid ticket checkout leave copy" do
    assert TicketUserMessages.leave_unpaid_checkout_button() ==
             "Leave without tickets"

    refute TicketUserMessages.leave_unpaid_checkout_button() == "Cancel"

    assert TicketUserMessages.leave_unpaid_checkout_busy() == "Leaving..."

    assert TicketUserMessages.leave_unpaid_checkout_confirm() =~
             "Leave without tickets?"

    assert TicketUserMessages.leave_unpaid_checkout_confirm() =~
             "go back on sale"

    assert TicketUserMessages.leave_unpaid_checkout_confirm() =~
             "not confirmed yet"

    refute TicketUserMessages.leave_unpaid_checkout_confirm() =~
             "Cancel this"

    refute TicketUserMessages.leave_unpaid_checkout_confirm() =~
             "release these tickets"

    assert TicketUserMessages.leave_unpaid_checkout_toast() =~
             "left without tickets"

    assert TicketUserMessages.leave_unpaid_checkout_toast() =~
             "available again"

    refute TicketUserMessages.leave_unpaid_checkout_toast() =~
             "availability has been released"

    refute TicketUserMessages.leave_unpaid_checkout_toast() =~
             "We cancelled this unfinished"
  end
end
