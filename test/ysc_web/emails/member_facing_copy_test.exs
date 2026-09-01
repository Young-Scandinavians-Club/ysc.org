defmodule YscWeb.Emails.MemberFacingCopyTest do
  @moduledoc """
  Locks in member-facing email wording so we keep "book a stay" / "cabin"
  instead of leftover reserve/rent/buyout/property jargon.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Bookings.BookingEntitlement

  alias YscWeb.Emails.{
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation,
    BookingEntitlementGranted,
    EventNotification,
    MembershipEnded,
    MembershipPaymentConfirmation,
    MembershipRenewalPaymentMethodReminder,
    OutageNotification,
    TahoeSummerBuyoutAvailable,
    TahoeWinterWeekendAvailable,
    TicketReservationCreated,
    WelcomeEmail
  }

  describe "membership emails" do
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
      refute text =~ "our Tahoe property"
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
          hold_expires_display:
            "Complete checkout before December 2, 2026 at 06:00 PM PST",
          has_notes: false,
          notes_text: nil,
          reserved_by_display: "YSC staff",
          notification_settings_url: "https://example.com/users/notifications"
        })

      text = html_text(html)

      assert text =~ "TICKETS SET ASIDE"
      assert text =~ "Finish checkout before the deadline below"
      assert text =~ "Ticket details"
      assert text =~ "Checkout:"
      assert text =~ "View event & finish buying tickets"
      assert text =~ "Must be 21 or older"
      refute text =~ "Age Restriction"
      refute text =~ "complete tickets"
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

  defp html_text(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.text()
  end
end
