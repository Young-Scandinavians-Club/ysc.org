defmodule YscWeb.Components.Events.AttendeeInfoCardsTest do
  use ExUnit.Case, async: true

  alias YscWeb.Components.Events.AttendeeInfoCards

  defp identity_ticket do
    %{
      ticket_tier: %{
        type: :paid,
        requires_registration: true,
        attendee_questions: []
      }
    }
  end

  defp questions_ticket do
    %{
      ticket_tier: %{
        type: :paid,
        requires_registration: false,
        attendee_questions: [%{label: "Dietary restrictions", type: :text}]
      }
    }
  end

  test "checkout heading and timer intro say complete purchase when names are done or never asked" do
    assert AttendeeInfoCards.checkout_heading([identity_ticket()], true) ==
             "Complete Your Purchase"

    assert AttendeeInfoCards.checkout_heading([], false) ==
             "Complete Your Purchase"

    assert AttendeeInfoCards.checkout_timer_intro([identity_ticket()], true) ==
             "Time remaining to complete purchase:"

    assert AttendeeInfoCards.checkout_timer_intro([], false) ==
             "Time remaining to complete purchase:"
  end

  test "checkout heading and timer intro do not say complete purchase while details are incomplete" do
    assert AttendeeInfoCards.checkout_heading([identity_ticket()], false) ==
             "Finish ticket details"

    assert AttendeeInfoCards.checkout_heading([questions_ticket()], false) ==
             "Finish ticket details"

    assert AttendeeInfoCards.checkout_timer_intro([identity_ticket()], false) ==
             "Time remaining:"

    assert AttendeeInfoCards.checkout_timer_intro([questions_ticket()], false) ==
             "Time remaining:"
  end

  test "checkout timer says complete payment when names are done or never asked" do
    paid =
      AttendeeInfoCards.checkout_timer_next_step([identity_ticket()], true)

    assert paid =~ "Complete payment before the timer expires"
    refute paid =~ "who's going"
    refute paid =~ "ticket details"

    no_info = AttendeeInfoCards.checkout_timer_next_step([], false)
    assert no_info =~ "Complete payment before the timer expires"
  end

  test "checkout timer says finish who's going while identity tickets are incomplete" do
    copy =
      AttendeeInfoCards.checkout_timer_next_step([identity_ticket()], false)

    assert copy =~ "Finish adding who's going before the timer runs out"
    refute copy =~ "Complete payment"
  end

  test "checkout timer says finish ticket details while question-only tickets are incomplete" do
    copy =
      AttendeeInfoCards.checkout_timer_next_step([questions_ticket()], false)

    assert copy =~ "Finish the ticket details before the timer runs out"
    refute copy =~ "Complete payment"
    refute copy =~ "who's going"
  end
end
