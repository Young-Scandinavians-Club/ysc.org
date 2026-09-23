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
    ApplicationApprovedFamilyLinked,
    ApplicationApprovedPaymentSuccess,
    ApplicationSubmitted,
    BookingCancellationConfirmation,
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation,
    BookingEntitlementGranted,
    BookingRefundPending,
    BookingRefundProcessed,
    EventNotification,
    EventUpdateNotification,
    ExpenseReportConfirmation,
    FamilyInviteCancelled,
    FamilyMemberRemoved,
    MembershipEnded,
    MembershipPaymentConfirmation,
    MembershipPaymentFailure,
    MembershipRenewalPaymentMethodReminder,
    MembershipRenewalSuccess,
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
      assert text =~ "After you pay, you'll be able to"
      refute text =~ "Once your payment is processed"
      refute text =~ "You're officially a Young Scandinavian"
      refute text =~ "Pay Your Membership"
      refute text =~ "completing your membership payment"
    end

    test "family-linked approval subject glosses Velkommen" do
      assert ApplicationApprovedFamilyLinked.get_subject() ==
               "Velkommen! (Welcome!) You're officially a Young Scandinavian 🎉"
    end

    test "payment-success approval heading glosses Velkommen" do
      html =
        ApplicationApprovedPaymentSuccess.render(%{
          first_name: "Jane",
          bank_payment: false
        })

      text = html_text(html)

      assert ApplicationApprovedPaymentSuccess.get_subject() ==
               "Velkommen! (Welcome!) Your YSC Membership is Active! 🎉"

      assert text =~ "Velkommen! (Welcome!) Your Membership is Active"
      assert text =~ "Your saved payment method has been charged"
      refute text =~ "Velkommen! Your Membership is Active"
    end

    test "application-submitted email says save a payment method, not card" do
      html = ApplicationSubmitted.render(%{first_name: "Jane"})
      text = html_text(html)

      assert text =~ "option to save a payment method"
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

    test "payment-failure email says after you pay, not once payment is processed" do
      html =
        MembershipPaymentFailure.render(%{
          first_name: "Jane",
          email: "jane@example.com",
          membership_type: "Single",
          is_renewal: false,
          invoice_id: "in_123",
          pay_membership_url: "https://example.com/users/membership",
          retry_payment_url:
            "https://example.com/users/membership?retry_invoice=in_123"
        })

      text = html_text(html)

      assert text =~ "After you pay, you'll have access"
      assert text =~ "You just need to finish paying your dues"
      assert text =~ "Try paying again"

      assert text =~
               "If your card or bank account still works, try the payment again"

      assert text =~ "Update your card or bank account"
      assert text =~ "Expired or invalid card"
      assert text =~ "Using a different card or bank account"
      assert text =~ "payment ID: in_123"
      assert text =~ "jane@example.com"
      refute text =~ "successfully processed"
      refute text =~ "complete the payment process"
      refute text =~ "payment reference"
      refute text =~ "Retry Payment Now"
      refute text =~ "Update Payment Method"
      refute text =~ "payment method"
    end

    test "renewal-failure email says after you pay, not once payment is processed" do
      html =
        MembershipPaymentFailure.render(%{
          first_name: "Jane",
          email: "jane@example.com",
          membership_type: "Family",
          is_renewal: true,
          invoice_id: nil,
          pay_membership_url: "https://example.com/users/membership",
          retry_payment_url: nil
        })

      text = html_text(html)

      assert text =~
               "We couldn't take payment for your Family membership renewal"

      assert text =~ "After you update your card or bank account and pay"
      assert text =~ "Update your card or bank account"
      refute text =~ "successfully processed"
      refute text =~ "couldn't process your"
      refute text =~ "Update Payment Method"
      refute text =~ "payment method"
    end

    test "renewal-success email says we received payment instead of processed" do
      html =
        MembershipRenewalSuccess.render(%{
          first_name: "Jane",
          membership_type: "Single",
          amount: "$50.00",
          renewal_date: "December 01, 2024",
          is_single_to_family_upgrade: false,
          is_upgrade: false,
          is_downgrade: false,
          old_membership_type: nil,
          has_proration: false
        })

      text = html_text(html)

      assert text =~ "We received your payment of $50.00"
      refute text =~ "has been processed"
      refute text =~ "successfully processed"
    end

    test "plan-change success emails say switched or charged, not processed" do
      family_html =
        MembershipRenewalSuccess.render(%{
          first_name: "Jane",
          membership_type: "Family",
          amount: "$65.00",
          renewal_date: "December 01, 2024",
          is_single_to_family_upgrade: true,
          is_upgrade: false,
          is_downgrade: false,
          old_membership_type: nil,
          has_proration: false
        })

      family_text = html_text(family_html)

      assert family_text =~ "Your membership switched from Single to Family"

      assert family_text =~
               "We received your payment of $65.00 for switching to Family"

      refute family_text =~ "successfully processed"
      refute family_text =~ "has been processed"

      switch_html =
        MembershipRenewalSuccess.render(%{
          first_name: "Jane",
          membership_type: "Single",
          amount: "$10.00",
          renewal_date: "February 17, 2026",
          is_single_to_family_upgrade: false,
          is_upgrade: false,
          is_downgrade: true,
          old_membership_type: "Family",
          has_proration: true
        })

      switch_text = html_text(switch_html)

      assert switch_text =~ "We charged $10.00 for switching plans"
      refute switch_text =~ "We processed a payment"
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
        |> Map.put(
          :unsubscribe_url,
          "https://example.com/event-notifications/unsubscribe/token"
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
        |> Map.put(
          :unsubscribe_url,
          "https://example.com/event-notifications/unsubscribe/token"
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

      assert data.benefit_description =~ "2 free nights on your next cabin stay"

      assert data.benefit_description =~
               "4-night stay is half off the cabin price"

      refute data.benefit_description =~ "proportionally"
      refute data.benefit_description =~ "subtotal"
      refute data.benefit_description =~ "eligible stay"

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
            booking_mode: "Individual room(s)",
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
      assert text =~ "Individual room(s)"
      assert text =~ "Tahoe Cabin Master at tahoe@ysc.org"

      assert text =~
               "About 3 days before check-in, we'll email you the door code"

      refute text =~ "24 hours before"
      refute text =~ "Room Booking"
      refute text =~ "Day Booking"
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
          booking_mode: "Individual room(s)",
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
          unsubscribe_url:
            "https://example.com/event-notifications/unsubscribe/token"
        })

      text = html_text(html)

      assert text =~ "See event details"
      assert text =~ "Must be 21 or older"
      refute text =~ "RSVP"
      refute text =~ "Age Restriction"
    end
  end

  describe "membership renewal payment reminder" do
    test "asks members to add a payment method, not just a card" do
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
               "Please add a payment method so your membership can renew"

      assert text =~ "Please add a payment method so your membership can renew"
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
      assert text =~ "Order number:"
      assert text =~ "Payment number:"
      assert text =~ "Your ticket numbers"
      refute text =~ "Payment Reference:"
      refute text =~ "Order Reference"
      refute text =~ "Ticket Reference"
      refute text =~ "Transaction ID:"
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
      assert text =~ "Order number:"
      assert text =~ "Refund number:"
      assert text =~ "Refunded ticket numbers"
      refute text =~ "Refund Reference"
      refute text =~ "Order Reference"
      refute text =~ "Ticket Reference"
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
      assert text =~ "Refund number:"
      assert text =~ "Payment number:"
      refute text =~ "Refund Reference"
      refute text =~ "Payment Reference"
      refute text =~ "has been processed"
      refute text =~ "will be processed"
    end

    test "pending booking refund is a review, not a member-submitted request" do
      html =
        BookingRefundPending.render(%{
          first_name: "Jane",
          booking: %{
            reference_id: "BK-123",
            property: "Tahoe",
            checkin_date: "December 1, 2026",
            checkout_date: "December 3, 2026",
            guests_count: 2,
            children_count: 0
          },
          pending_refund: %{
            policy_refund_amount: "$100.00",
            cancellation_reason: "Change of plans",
            request_date: "Nov 2, 2026 at 10:00 AM",
            refund_percentage: 50.0
          },
          payment: %{
            reference_id: "PMT-123",
            amount: "$200.00"
          },
          request_date: "Nov 2, 2026 at 10:00 AM",
          policy_refund_amount: "$100.00",
          refund_percentage: 50.0,
          booking_url: "https://example.com/bookings/preview"
        })

      text = html_text(html)

      assert BookingRefundPending.get_subject() ==
               "We're reviewing your cabin booking refund"

      assert text =~ "Your cabin booking is cancelled"
      assert text =~ "You don't need to do anything else"
      assert text =~ "Cabin Master"
      assert text =~ "money is on the way"
      assert text =~ "same card or bank account you used"
      refute text =~ "original payment method"
      assert text =~ "Payment number:"
      refute text =~ "Payment Reference"
      refute text =~ "refund request"
      refute text =~ "approved and processed"
    end

    test "booking cancellation confirmation says the money is on the way" do
      pending_html =
        BookingCancellationConfirmation.render(%{
          first_name: "Jane",
          booking: %{
            reference_id: "BK-123",
            property: "Tahoe",
            checkin_date: "December 1, 2026",
            checkout_date: "December 3, 2026"
          },
          cancellation: %{
            date: "Nov 2, 2026",
            reason: "Change of plans"
          },
          payment: %{reference_id: "PMT-123", amount: "$200.00"},
          refund: %{amount: "$100.00", is_pending: true},
          booking_url: "https://example.com/bookings/preview"
        })

      pending_text = html_text(pending_html)

      assert pending_text =~ "money is on the way"
      assert pending_text =~ "Payment number:"
      refute pending_text =~ "Payment Reference"
      refute pending_text =~ "approved and processed"
      refute pending_text =~ "will be processed"

      completed_html =
        BookingCancellationConfirmation.render(%{
          first_name: "Jane",
          booking: %{
            reference_id: "BK-123",
            property: "Tahoe",
            checkin_date: "December 1, 2026",
            checkout_date: "December 3, 2026"
          },
          cancellation: %{
            date: "Nov 2, 2026",
            reason: "Change of plans"
          },
          payment: %{reference_id: "PMT-123", amount: "$200.00"},
          refund: %{amount: "$200.00", is_pending: false},
          booking_url: "https://example.com/bookings/preview"
        })

      completed_text = html_text(completed_html)

      assert completed_text =~
               "go back to the same card or bank account you used"

      assert completed_text =~ "Payment number:"
      refute completed_text =~ "Payment Reference"
      refute completed_text =~ "will be processed"
      refute completed_text =~ "processed and credited"
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

  describe "family invite cancelled email" do
    test "explains the old link no longer works and how to contact YSC" do
      html =
        FamilyInviteCancelled.render(%{
          primary_user_name: "John",
          invite_email: "jane@example.com"
        })

      text = html_text(html)
      membership_email = FamilyInviteCancelled.membership_email()

      assert FamilyInviteCancelled.get_subject() ==
               "Your family membership invitation was cancelled - YSC"

      assert text =~ "Family invitation cancelled"
      assert text =~ "no longer works"
      assert text =~ "cannot use that link to join this family membership"
      assert text =~ membership_email
      refute text =~ "reach out to YSC"
      refute text =~ "invitation link that was previously sent"
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

    test "labels offsets as money already received instead of income" do
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
            expense_items: [
              %{
                vendor: "Costco",
                description: "Event snacks",
                date: "September 1, 2026",
                amount: "$40.00",
                mileage: false,
                mileage_info: nil,
                has_receipt: true
              }
            ],
            income_items: [
              %{
                description: "Guest ticket cash",
                date: "September 1, 2026",
                amount: "$20.00",
                has_proof: true
              }
            ],
            expense_total: "$40.00",
            income_total: "$20.00",
            net_total: "$20.00"
          }
        })

      text = html_text(html)

      assert text =~ "Money already received"
      assert text =~ "Guest ticket cash"
      refute text =~ "Income Items"
      refute text =~ "Total Income"
    end
  end

  defp html_text(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.text()
  end
end
