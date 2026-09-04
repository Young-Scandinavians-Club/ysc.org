defmodule YscWeb.Emails.MemberFacingCopyTest do
  @moduledoc """
  Locks in member-facing email wording so we keep "book a stay" / "cabin"
  instead of leftover reserve/rent/buyout/property jargon.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.BookingEntitlement

  alias YscWeb.Emails.{
    ApplicationApproved,
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation,
    BookingEntitlementGranted,
    BookingRefundProcessed,
    EventNotification,
    EventUpdateNotification,
    ExpenseReportConfirmation,
    FamilyMemberRemoved,
    MembershipEnded,
    MembershipPaymentConfirmation,
    MembershipRenewalPaymentMethodReminder,
    OutageNotification,
    SaveTheDateAvailable,
    TahoeSummerBuyoutAvailable,
    TahoeWinterWeekendAvailable,
    TicketOrderRefund,
    TicketPurchaseConfirmation,
    TicketReservationCreated,
    WelcomeEmail
  }

  describe "membership emails" do
    test "approval email asks people to pay dues instead of saying they are already members" do
      html = ApplicationApproved.render(%{first_name: "Jane"})
      text = html_text(html)

      assert ApplicationApproved.get_subject() ==
               "Velkommen! (Welcome!) Pay your membership dues to join YSC"

      assert text =~ "There's one more step before you can book the cabins"
      assert text =~ "pay your annual membership dues"
      assert text =~ "Pay your membership dues"
      refute text =~ "You're officially a Young Scandinavian"
      refute text =~ "Pay Your Membership"
      refute text =~ "completing your membership payment"
    end

    test "payment confirmation tells members they can book a stay at the cabins" do
      html =
        MembershipPaymentConfirmation.render(%{
          first_name: "Jane",
          membership_type: "Single",
          amount: "$50.00",
          payment_date: "December 01, 2024",
          paid_elsewhere: false
        })

      text = html_text(html)

      assert text =~ "Book a stay at our Tahoe and Clear Lake cabins"
      refute text =~ "Reserve our"
      refute text =~ "properties for your getaways"
    end

    test "membership ended email uses cabin, not property, language" do
      html =
        MembershipEnded.render(%{
          first_name: "Jane",
          end_date: "August 1, 2026",
          membership_url: "https://example.com/users/membership",
          upcoming_events_url: "https://example.com/events"
        })

      text = html_text(html)

      assert text =~ "cabin bookings at our Tahoe and Clear Lake cabins"
      assert text =~ "Book a stay at our Tahoe and Clear Lake cabins"
      refute text =~ "Reserve our"
      refute text =~ "Clear Lake properties"
    end
  end

  describe "Tahoe seasonal availability emails" do
    test "summer whole-cabin notice uses book, not rent or buyout" do
      user = oauth_user_fixture(%{first_name: "Jane"})

      html =
        TahoeSummerBuyoutAvailable.prepare_email_data(
          ~D[2027-05-07],
          ~D[2027-05-09],
          "2027",
          user
        )
        |> TahoeSummerBuyoutAvailable.render()

      text = html_text(html)

      assert TahoeSummerBuyoutAvailable.get_subject("2027") ==
               "[YSC] Book the whole cabin — Summer 2027 is open!"

      assert text =~ "you can now book the entire cabin"

      assert text =~
               "Booking the entire cabin is only available for non-winter nights"

      refute text =~ "rent out"
      refute text =~ "Whole-cabin buyouts"
    end

    test "winter weekend notice uses book, not reserve or rent out" do
      user = oauth_user_fixture(%{first_name: "Jane"})

      html =
        TahoeWinterWeekendAvailable.prepare_email_data(
          ~D[2026-11-06],
          ~D[2026-11-08],
          "2026/2027",
          user
        )
        |> TahoeWinterWeekendAvailable.render()

      text = html_text(html)

      assert text =~ "you can now book the first full weekend"

      assert text =~
               "the whole cabin isn't available to book during winter nights"

      assert text =~ "A Single membership can book 1 room per stay"
      refute text =~ "rent out"
      refute text =~ "can reserve"
    end
  end

  describe "welcome email" do
    test "winter copy says members can book the entire cabin again in summer" do
      html =
        WelcomeEmail.render(%{
          first_name: "Jane",
          events: [],
          events_url: "https://example.com/events",
          tahoe_url: "https://example.com/bookings/tahoe",
          clear_lake_url: "https://example.com/bookings/clear-lake",
          tahoe_season_name: "Winter",
          tahoe_buyout_allowed: false
        })

      text = html_text(html)

      assert text =~
               "you can book the entire cabin again once summer season starts"

      refute text =~ "full-cabin buyouts"
    end
  end

  describe "booking entitlement granted" do
    test "uses cabin and booking wording, with Pacific expiry" do
      user = oauth_user_fixture(%{first_name: "Jane"})

      expires_at = ~U[2026-09-15 07:00:00Z]

      ent = %BookingEntitlement{
        benefit_kind: :free_nights,
        free_nights: 2,
        buyout_max_discount: Money.new(:USD, 500),
        property: :tahoe,
        expires_at: expires_at
      }

      data = BookingEntitlementGranted.prepare_email_data(ent, user)

      assert data.property_line == "Cabin: Lake Tahoe."

      assert data.buyout_cap_line =~
               "If you book the entire cabin, savings on that stay are capped"

      assert data.manage_bookings_hint =~ "Start a new booking"
      refute data.manage_bookings_hint =~ "reservation"
      refute data.buyout_cap_line =~ "buyout"
      refute data.expiry_line =~ "UTC"
      assert data.expiry_line =~ "Use by"
      assert data.expiry_line =~ "September 15, 2026"

      html = BookingEntitlementGranted.render(data)
      text = html_text(html)
      assert text =~ "Start a new booking"
      refute text =~ "Start a new reservation"
    end
  end

  describe "booking stay emails" do
    test "confirmation uses cabin, not property" do
      html =
        BookingConfirmation.render(%{
          first_name: "Jane",
          booking: %{
            reference_id: "BK-TEST-123",
            property: "Tahoe",
            checkin_date: "December 1, 2026",
            checkout_date: "December 3, 2026",
            guests_count: 2,
            children_count: 0,
            booking_mode: "Room Booking",
            room_names: "Room 1",
            nights: 2,
            total_amount: "$200.00",
            is_buyout: false
          },
          total_amount: "$200.00",
          booking_date: "Nov 1, 2026 at 10:00 AM",
          booking_url: "https://example.com/bookings/preview",
          cabin_email: "tahoe@ysc.org"
        })

      text = html_text(html)

      assert text =~ "host you at the Tahoe cabin"
      assert text =~ "Cabin:"
      assert text =~ "Tahoe Cabin Master at tahoe@ysc.org"
      refute text =~ "our Tahoe property"
      refute text =~ "Property:"
      refute text =~ "info@ysc.org"
    end

    test "check-in reminder uses booking and cabin language" do
      html =
        BookingCheckinReminder.render(%{
          first_name: "Jane",
          door_code: "1234",
          property: "tahoe",
          property_name: "Tahoe",
          property_address: "2685 Cedar Lane, Homewood, CA 96141",
          checkin_date: "December 1, 2026",
          checkout_date: "December 3, 2026",
          checkin_time: "3:00 PM",
          checkout_time: "11:00 AM",
          days_until_checkin: 2,
          booking_reference_id: "BK-TEST-123",
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 2,
          is_buyout: false,
          guests_count: 2,
          children_count: 0,
          cabin_master_name: "Lars Berg",
          cabin_master_email: "cabinmaster@ysc.org",
          cabin_master_phone: "4155550199",
          clear_lake_info_url: "https://example.com/bookings/clear-lake",
          booking_url: "https://example.com/bookings/preview"
        })

      text = html_text(html)

      assert text =~ "the Tahoe cabin"
      assert text =~ "Cabin location"
      assert text =~ "Booking Details"
      assert text =~ "get into the cabin"

      assert text =~
               "Make sure the number of adults on your booking is accurate"

      assert text =~ "Cabin Master"
      refute text =~ "Reservation Details"
      refute text =~ "Property Location"
      refute text =~ "Guests & Reservations"
      refute text =~ "access the property"
    end

    test "checkout reminder uses cabin, not property" do
      html =
        BookingCheckoutReminder.render(%{
          first_name: "Jane",
          property: "tahoe",
          property_name: "Tahoe",
          checkout_date: "December 3, 2026",
          checkout_time: "11:00 AM",
          booking_reference_id: "BK-TEST-123",
          cabin_master_name: "Lars Berg",
          cabin_master_email: "cabinmaster@ysc.org",
          cabin_master_phone: "4155550199",
          booking_url: "https://example.com/bookings/preview"
        })

      text = html_text(html)

      assert text =~ "the Tahoe cabin"
      assert text =~ "Time to leave the cabin"
      refute text =~ "Checkout Reminder"
      refute text =~ "our Tahoe property"

      assert BookingCheckoutReminder.get_subject() ==
               "Leaving tomorrow — cabin check-out reminder 🏡"
    end
  end

  describe "ticket hold email" do
    test "explains the set-aside tickets without hold-window jargon" do
      html =
        TicketReservationCreated.render(%{
          first_name: "Jane",
          event_title: "Nordic Night",
          event: %{
            title: "Nordic Night",
            description: "Join us.",
            location_name: "Golden Gate Park",
            address: "123 Main St",
            age_restriction: 21
          },
          event_date_time: "Dec 1, 2026 at 7:00 PM PST",
          event_url: "https://example.com/events/preview",
          ticket_tier_name: "Member GA",
          quantity: 2,
          discount_display: "10% member pricing",
          has_discount: true,
          hold_expires_display: "December 2, 2026 at 06:00 PM PST",
          has_notes: false,
          notes_text: nil,
          reserved_by_display: "YSC staff",
          notification_settings_url: "https://example.com/users/notifications"
        })

      text = html_text(html)

      assert text =~ "TICKETS SET ASIDE"
      assert text =~ "set aside tickets for you"
      assert text =~ "Ticket details"
      assert text =~ "Finish buying by:"
      assert text =~ "View event & finish buying tickets"
      assert text =~ "Must be 21 or older"
      refute text =~ "Age Restriction"
      refute text =~ "complete tickets"
      refute text =~ "Finish checkout"
      refute text =~ "Complete checkout"
      refute text =~ "hold window"
      refute text =~ "your reservation will be applied"
    end
  end

  describe "new-event email" do
    test "asks members to see event details instead of RSVPing" do
      html =
        EventNotification.render(%{
          first_name: "Jane",
          event: %{
            title: "Nordic Night",
            description: "Join us.",
            location_name: "Golden Gate Park",
            address: "123 Main St",
            age_restriction: 21
          },
          event_date_time: "Dec 1, 2026 at 7:00 PM PST",
          event_url: "https://example.com/events/preview",
          event_image_url: nil,
          notification_settings_url: "https://example.com/users/notifications"
        })

      text = html_text(html)

      assert text =~ "See event details"
      assert text =~ "Must be 21 or older"
      refute text =~ "RSVP"
      refute text =~ "Age Restriction"
    end
  end

  describe "membership renewal payment reminder" do
    test "asks members to save a card instead of a payment method on file" do
      html =
        MembershipRenewalPaymentMethodReminder.render(%{
          first_name: "Jane",
          renewal_date: "March 15, 2026",
          payment_methods_url:
            "https://example.com/users/membership/payment-method",
          membership_url: "https://example.com/users/membership"
        })

      text = html_text(html)

      assert MembershipRenewalPaymentMethodReminder.get_subject() ==
               "Please add a card so your membership can renew"

      assert text =~ "Please add a card so your membership can renew"
      assert text =~ "We don't have a card or bank account saved"
      assert text =~ "Add a card or bank account"
      assert text =~ "Click the button above"
      refute text =~ "payment method on file"
      refute text =~ "Navigate to Payment Methods"
    end
  end

  describe "outage notification" do
    test "uses cabin language, not property, and names the Cabin Master" do
      html =
        OutageNotification.render(%{
          first_name: "Jane",
          property: :tahoe,
          incident_type: :power_outage,
          company_name: "PG&E",
          incident_date: ~D[2026-12-01],
          description: "Scheduled maintenance.",
          checkin_date: ~D[2026-12-01],
          checkout_date: ~D[2026-12-03],
          cabin_master_name: "Lars Berg",
          cabin_master_email: "cabinmaster@ysc.org",
          cabin_master_phone: "4155550199"
        })

      text = html_text(html)

      assert OutageNotification.get_subject(:tahoe) ==
               "Outage at the Tahoe cabin"

      assert text =~ "Cabin outage notice"
      assert text =~ "There's currently a power outage at the Tahoe cabin"
      assert text =~ "Utility company"
      assert text =~ "reach out to the Cabin Master"
      assert text =~ "Check the outage map"
      refute text =~ "Property Outage"
      refute text =~ "Tahoe Property"
      refute text =~ "the cabin master"
    end
  end

  describe "event update email" do
    test "asks members to see event details, not View Event" do
      html =
        EventUpdateNotification.render(%{
          first_name: "Jane",
          event: %{
            title: "Nordic Night",
            location_name: "Golden Gate Park",
            address: "123 Main St"
          },
          update_title: "Doors open later",
          update_body: "<p>Arrive at 8pm.</p>",
          event_date_time: "Dec 1, 2026 at 8:00 PM PST",
          event_url: "https://example.com/events/preview",
          event_image_url: nil,
          notification_settings_url: "https://example.com/users/notifications"
        })

      text = html_text(html)

      assert text =~ "See event details"
      refute text =~ "View Event"
    end
  end

  describe "save-the-date tickets-available email" do
    test "asks members to get tickets instead of viewing the event" do
      html =
        SaveTheDateAvailable.render(%{
          first_name: "Jane",
          event: %{
            title: "Nordic Night",
            description: "Join us.",
            location_name: "Golden Gate Park",
            address: "123 Main St",
            age_restriction: 21
          },
          event_date_time: "Dec 1, 2026 at 7:00 PM PST",
          event_url: "https://example.com/events/preview",
          event_image_url: nil,
          notification_settings_url: "https://example.com/users/notifications"
        })

      text = html_text(html)

      assert text =~ "Get tickets"
      refute text =~ "View Event"
      refute text =~ "registration"

      for template <- SaveTheDateAvailable.subject_templates() do
        refute template =~ "registration"
      end
    end
  end

  describe "ticket purchase confirmation" do
    test "tells members how to check in instead of using receipt jargon" do
      html =
        TicketPurchaseConfirmation.render(%{
          first_name: "Jane",
          event: %{
            title: "Nordic Night",
            description: "Join us.",
            location_name: "Golden Gate Park",
            address: "123 Main St",
            age_restriction: 21
          },
          event_date_time: "Dec 1, 2026 at 7:00 PM PST",
          event_url: "https://example.com/events/preview",
          agenda: [],
          ticket_order: %{reference_id: "TKT-123"},
          purchase_date: "Nov 1, 2026",
          payment: %{reference_id: "PMT-123"},
          payment_date: "Nov 1, 2026",
          payment_method: "Visa ending in 4242",
          paid_in_person: false,
          total_amount: "$20.00",
          gross_total: "$20.00",
          total_discount: "$0.00",
          has_discounts: false,
          ticket_summaries: [
            %{
              ticket_tier_name: "Member GA",
              quantity: 1,
              price_per_ticket: "$20.00",
              total_price: "$20.00",
              original_price: nil,
              discount_amount: nil,
              discount_percentage: nil
            }
          ],
          tickets: [
            %{
              reference_id: "TKT-001",
              ticket_tier_name: "Member GA"
            }
          ],
          tickets_qr_url: "https://example.com/tickets/order-123/qr"
        })

      text = html_text(html)

      assert text =~ "Your tickets are confirmed"
      assert text =~ "See event details"
      assert text =~ "show the tickets on your phone"
      refute text =~ "Ticket Purchase Confirmation"
      refute text =~ "View Event Details"
    end
  end

  describe "refund emails" do
    test "ticket refund says the money is on the way, not that it was processed twice" do
      html =
        TicketOrderRefund.render(%{
          first_name: "Jane",
          event: %{
            title: "Nordic Night",
            description: "Join us.",
            location_name: "Golden Gate Park",
            address: "123 Main St"
          },
          event_date_time: "Dec 1, 2026 at 7:00 PM PST",
          event_url: "https://example.com/events/preview",
          ticket_order: %{reference_id: "TKT-123"},
          refund: %{
            reference_id: "RFD-123",
            reason: "Event cancelled"
          },
          refund_date: "Nov 2, 2026",
          refund_amount: "$20.00",
          ticket_summaries: [
            %{
              ticket_tier_name: "Member GA",
              quantity: 1,
              price_per_ticket: "$20.00",
              total_price: "$20.00"
            }
          ],
          refunded_tickets: [
            %{
              reference_id: "TKT-001",
              ticket_tier_name: "Member GA"
            }
          ]
        })

      text = html_text(html)

      assert TicketOrderRefund.get_subject() ==
               "Your ticket refund is on the way"

      assert text =~ "Your ticket refund is on the way"
      assert text =~ "We've issued your ticket refund"
      assert text =~ "same card or bank account"
      refute text =~ "has been processed"
      refute text =~ "will be processed"
    end

    test "booking refund says the money is on the way, not that it was processed twice" do
      html =
        BookingRefundProcessed.render(%{
          first_name: "Jane",
          booking: %{
            reference_id: "BK-123",
            property: "Tahoe",
            checkin_date: "December 1, 2026",
            checkout_date: "December 3, 2026",
            guests_count: 2,
            children_count: 0
          },
          refund: %{
            reference_id: "RFD-123",
            reason: "Cancelled stay"
          },
          payment: %{
            reference_id: "PMT-123",
            amount: "$200.00"
          },
          refund_date: "Nov 2, 2026",
          refund_amount: "$200.00",
          booking_url: "https://example.com/bookings/preview"
        })

      text = html_text(html)

      assert BookingRefundProcessed.get_subject() ==
               "Your booking refund is on the way"

      assert text =~ "Your booking refund is on the way"
      assert text =~ "We've issued your cabin booking refund"
      assert text =~ "Cabin Master"
      refute text =~ "has been processed"
      refute text =~ "will be processed"
    end
  end

  describe "family member removed email" do
    test "tells the member how to get their own membership" do
      html =
        FamilyMemberRemoved.render(%{
          first_name: "Jane",
          primary_user_name: "John Doe",
          membership_url: "https://example.com/users/membership"
        })

      text = html_text(html)

      assert text =~ "Get your own membership"
      assert text =~ "get your own membership anytime"
      refute text =~ "purchase your own membership at any time"
    end
  end

  describe "expense report confirmation" do
    test "says how much we'll reimburse instead of Net Total" do
      html =
        ExpenseReportConfirmation.render(%{
          first_name: "Jane",
          expense_report_url: "https://example.com/expensereport/preview",
          expense_report: %{
            id: "er-preview",
            purpose: "Cabin supplies",
            submitted_date: "September 1, 2026",
            reimbursement_method: "Bank Transfer",
            event: nil,
            bank_account: nil,
            expense_items: [],
            income_items: [],
            expense_total: "$40.00",
            income_total: "$0.00",
            net_total: "$40.00"
          }
        })

      text = html_text(html)

      assert text =~ "Amount we will reimburse"
      assert text =~ "See your expense report"
      assert text =~ "We'll email you when the money is on the way"
      refute text =~ "Net Total"
      refute text =~ "View Expense Report"
      refute text =~ "reimbursement has been processed"
    end
  end

  defp html_text(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.text()
  end
end
