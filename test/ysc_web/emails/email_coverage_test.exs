defmodule YscWeb.Emails.EmailCoverageTest do
  @moduledoc """
  Comprehensive tests for 100% coverage of all email modules.

  Tests prepare_email_data, helper functions, template branches, and error cases.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias YscWeb.Emails.{
    AccountSetupVerification,
    ApplicationApproved,
    ConductViolationConfirmation,
    ContactFormBoardNotification,
    FamilyInvite,
    FamilyInviteCancelled,
    FamilyMemberRemoved,
    MembershipPaymentConfirmation,
    MembershipPaymentFailure,
    MembershipRenewalPaymentMethodReminder,
    MembershipRenewalReminder,
    MembershipRenewalSuccess,
    OutageNotification,
    BookingCancellationCabinMasterNotification,
    BookingCancellationTreasurerNotification,
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation,
    BookingRefundPending,
    EventNotification,
    ExpenseReportConfirmation,
    ExpenseReportTreasurerNotification,
    Notifier,
    TicketPurchaseConfirmation
  }

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "ApplicationApproved" do
    test "renders and exposes template metadata" do
      html = ApplicationApproved.render(%{first_name: "Astrid"})
      assert is_binary(html)
      assert html =~ "Astrid"
      assert html =~ "Membership Application Approved"

      assert ApplicationApproved.get_template_name() == "application_approved"

      assert ApplicationApproved.get_subject() =~ "Young Scandinavian"

      assert ApplicationApproved.upcoming_events_url() =~ "/events"
      assert ApplicationApproved.pay_membership_url() =~ "/users/membership"
    end
  end

  describe "FamilyInvite" do
    test "renders with family_member_name", %{user: user} do
      assigns = %{
        family_member_name: "Jane",
        primary_user_name: "#{user.first_name} #{user.last_name}",
        invite_url: "https://example.com/invite/abc123",
        expires_in_days: 7,
        invite_button_text: "Accept Invitation"
      }

      html = FamilyInvite.render(assigns)
      assert is_binary(html)
      assert html =~ "Jane"
      assert html =~ "Accept Invitation"
      assert FamilyInvite.get_template_name() == "family_invite"

      assert FamilyInvite.get_subject() ==
               "You're Invited to Join a Family Membership - YSC"
    end

    test "renders without family_member_name" do
      assigns = %{
        family_member_name: nil,
        primary_user_name: "John Doe",
        invite_url: "https://example.com/invite/abc123",
        expires_in_days: 7,
        invite_button_text: "Create account and join membership"
      }

      html = FamilyInvite.render(assigns)
      assert is_binary(html)
      assert html =~ "Hi there"
    end
  end

  describe "AccountSetupVerification" do
    test "renders with assigns" do
      assigns = %{
        first_name: "John",
        verification_code: "123456"
      }

      html = AccountSetupVerification.render(assigns)
      assert is_binary(html)
      assert html =~ "John"
      assert html =~ "123456"

      assert AccountSetupVerification.get_template_name() ==
               "account_setup_verification"
    end
  end

  describe "ContactFormBoardNotification" do
    test "renders with assigns" do
      assigns = %{
        name: "Jane Doe",
        email: "jane@example.com",
        subject: "Question about membership",
        contact_form_id: "CF-123",
        submitted_at: "Dec 1, 2024 at 10:00 AM",
        message: "I have a question about the cabin booking process."
      }

      html = ContactFormBoardNotification.render(assigns)
      assert is_binary(html)
      assert html =~ "Jane Doe"
      assert html =~ "jane@example.com"

      assert ContactFormBoardNotification.get_template_name() ==
               "contact_form_board_notification"

      assert ContactFormBoardNotification.get_subject() ==
               "New Contact Form Submission - YSC"
    end

    test "admin_dashboard_url points at the admin path" do
      url = ContactFormBoardNotification.admin_dashboard_url()
      assert url =~ "/admin"
      assert url == YscWeb.Endpoint.url() <> "/admin"
    end
  end

  describe "FamilyInviteCancelled" do
    test "renders and exposes template metadata" do
      assigns = %{
        primary_user_name: "John Doe",
        invite_email: "jane@example.com"
      }

      html = FamilyInviteCancelled.render(assigns)
      assert is_binary(html)
      assert html =~ "John Doe"
      assert html =~ "jane@example.com"

      assert FamilyInviteCancelled.get_template_name() ==
               "family_invite_cancelled"

      assert FamilyInviteCancelled.get_subject() ==
               "Family Membership Invitation Cancelled - YSC"
    end
  end

  describe "FamilyMemberRemoved" do
    test "renders and exposes template metadata" do
      assigns = %{
        first_name: "Jane",
        primary_user_name: "John Doe"
      }

      html = FamilyMemberRemoved.render(assigns)
      assert is_binary(html)
      assert html =~ "Jane"
      assert html =~ "John Doe"

      assert FamilyMemberRemoved.get_template_name() == "family_member_removed"

      assert FamilyMemberRemoved.get_subject() ==
               "Removed from Family Membership - YSC"
    end
  end

  describe "ConductViolationConfirmation" do
    test "helper URLs and metadata" do
      assert ConductViolationConfirmation.get_template_name() ==
               "conduct_violation_confirmation"

      assert ConductViolationConfirmation.get_subject() ==
               "Conduct Violation Report Received - YSC"

      assert ConductViolationConfirmation.code_of_conduct_url() ==
               YscWeb.Endpoint.url() <> "/code-of-conduct"

      assert ConductViolationConfirmation.contact_url() ==
               YscWeb.Endpoint.url() <> "/contact"
    end

    test "renders with anonymous flag" do
      assigns = %{
        first_name: "Sam",
        last_name: "Smith",
        summary: "Summary text",
        anonymous: true
      }

      html = ConductViolationConfirmation.render(assigns)
      assert is_binary(html)
      assert html =~ "Sam"
    end
  end

  describe "MembershipRenewalReminder" do
    test "renders with assigns" do
      assigns = %{
        first_name: "John",
        renewal_date: "December 8, 2024",
        membership_url: "https://example.com/users/membership"
      }

      html = MembershipRenewalReminder.render(assigns)
      assert is_binary(html)
      assert html =~ "John"

      assert MembershipRenewalReminder.get_template_name() ==
               "membership_renewal_reminder"

      assert MembershipRenewalReminder.get_subject() ==
               "Your YSC Membership Renews in 7 Days"
    end

    test "prepare_email_data returns correct data" do
      user = user_fixture()
      subscription = %{current_period_end: DateTime.utc_now()}

      data = MembershipRenewalReminder.prepare_email_data(user, subscription)
      assert data.first_name == user.first_name
      assert data.renewal_date =~ ~r/\w+ \d+, \d{4}/
      assert data.membership_url =~ "/users/membership"
    end

    test "prepare_email_data uses Valued Member when first_name is nil" do
      user = user_fixture()
      user = %{user | first_name: nil}
      subscription = %{current_period_end: DateTime.utc_now()}

      data = MembershipRenewalReminder.prepare_email_data(user, subscription)
      assert data.first_name == "Valued Member"
    end

    test "prepare_email_data uses Valued Member when first_name is empty" do
      user = user_fixture()
      user = %{user | first_name: ""}
      subscription = %{current_period_end: DateTime.utc_now()}

      data = MembershipRenewalReminder.prepare_email_data(user, subscription)
      assert data.first_name == "Valued Member"
    end

    test "prepare_email_data raises when user is nil" do
      subscription = %{current_period_end: DateTime.utc_now()}

      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipRenewalReminder.prepare_email_data(nil, subscription)
      end
    end

    test "prepare_email_data raises when subscription is nil" do
      user = user_fixture()

      assert_raise ArgumentError, "Subscription cannot be nil", fn ->
        MembershipRenewalReminder.prepare_email_data(user, nil)
      end
    end
  end

  describe "MembershipRenewalPaymentMethodReminder" do
    test "prepare_email_data returns correct data" do
      user = user_fixture()
      subscription = %{current_period_end: DateTime.utc_now()}

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert data.first_name == user.first_name
      assert data.renewal_date =~ ~r/\w+ \d+, \d{4}/
      assert data.payment_methods_url =~ "/users/payment-methods"
      assert data.membership_url =~ "/users/membership"
    end

    test "prepare_email_data raises when user is nil" do
      subscription = %{current_period_end: DateTime.utc_now()}

      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          nil,
          subscription
        )
      end
    end

    test "prepare_email_data raises when subscription is nil" do
      user = user_fixture()

      assert_raise ArgumentError, "Subscription cannot be nil", fn ->
        MembershipRenewalPaymentMethodReminder.prepare_email_data(user, nil)
      end
    end
  end

  describe "OutageNotification" do
    test "property_name with atoms" do
      assert OutageNotification.property_name(:tahoe) == "Tahoe Property"

      assert OutageNotification.property_name(:clear_lake) ==
               "Clear Lake Property"

      assert OutageNotification.property_name(:other) == "Property"
    end

    test "property_name with binaries" do
      assert OutageNotification.property_name("tahoe") == "Tahoe Property"

      assert OutageNotification.property_name("clear_lake") ==
               "Clear Lake Property"

      assert OutageNotification.property_name("unknown") == "Property"
    end

    test "property_name with other types" do
      assert OutageNotification.property_name(123) == "Property"
    end

    test "incident_type_name with atoms" do
      assert OutageNotification.incident_type_name(:power_outage) ==
               "Power Outage"

      assert OutageNotification.incident_type_name(:water_outage) ==
               "Water Outage"

      assert OutageNotification.incident_type_name(:internet_outage) ==
               "Internet Outage"

      assert OutageNotification.incident_type_name(:other) == "Outage"
    end

    test "incident_type_name with binaries" do
      assert OutageNotification.incident_type_name("power_outage") ==
               "Power Outage"

      assert OutageNotification.incident_type_name("water_outage") ==
               "Water Outage"

      assert OutageNotification.incident_type_name("internet_outage") ==
               "Internet Outage"

      assert OutageNotification.incident_type_name("unknown") == "Outage"
    end

    test "provider_outage_map_url" do
      assert OutageNotification.provider_outage_map_url("Optimum") =~ "optimum"

      assert OutageNotification.provider_outage_map_url("Liberty Utilities") =~
               "liberty"

      assert OutageNotification.provider_outage_map_url("PG&E") =~ "pge"
      assert OutageNotification.provider_outage_map_url("SCG") =~ "swgas"
      assert OutageNotification.provider_outage_map_url("Unknown") == nil
    end

    test "format_date with Date struct" do
      date = ~D[2024-12-01]
      assert OutageNotification.format_date(date) =~ "December"
      assert OutageNotification.format_date(date) =~ "2024"
    end

    test "format_date with binary ISO8601" do
      assert OutageNotification.format_date("2024-12-01") =~ "December"
      assert OutageNotification.format_date("2024-12-01") =~ "2024"
    end

    test "format_date with invalid binary" do
      assert OutageNotification.format_date("invalid") == "invalid"
    end

    test "format_date with other types" do
      assert OutageNotification.format_date(123) == "Unknown date"
    end

    test "renders with description and cabin master" do
      assigns = %{
        first_name: "John",
        property: :tahoe,
        property_name: "Tahoe Property",
        incident_type: :power_outage,
        outage_type: "Power Outage",
        company_name: "PG&E",
        incident_date: ~D[2024-12-01],
        description: "Scheduled maintenance",
        checkin_date: ~D[2024-12-05],
        checkout_date: ~D[2024-12-07],
        cabin_master_name: "Jane Smith",
        cabin_master_email: "jane@example.com",
        cabin_master_phone: "555-1234"
      }

      html = OutageNotification.render(assigns)
      assert is_binary(html)
      assert html =~ "Scheduled maintenance"
      assert html =~ "Jane Smith"
      assert html =~ "jane@example.com"
      assert html =~ "555-1234"
    end

    test "renders with provider outage map URL" do
      assigns = %{
        first_name: "John",
        property: :tahoe,
        property_name: "Tahoe Property",
        incident_type: :power_outage,
        outage_type: "Power Outage",
        company_name: "PG&E",
        incident_date: ~D[2024-12-01],
        description: nil,
        checkin_date: ~D[2024-12-05],
        checkout_date: ~D[2024-12-07],
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil
      }

      html = OutageNotification.render(assigns)
      assert is_binary(html)
      assert html =~ "View Outage Map"
    end

    test "renders without cabin master section" do
      assigns = %{
        first_name: "John",
        property: :tahoe,
        property_name: "Tahoe Property",
        incident_type: :power_outage,
        outage_type: "Power Outage",
        company_name: "Unknown Co",
        incident_date: ~D[2024-12-01],
        description: nil,
        checkin_date: ~D[2024-12-05],
        checkout_date: ~D[2024-12-07],
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil
      }

      html = OutageNotification.render(assigns)
      assert is_binary(html)
    end
  end

  describe "MembershipPaymentFailure" do
    test "renders with is_renewal true", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        membership_type: "Single",
        is_renewal: true,
        pay_membership_url: "https://example.com/users/membership",
        invoice_id: "in_123",
        retry_payment_url:
          "https://example.com/users/membership?retry_invoice=in_123"
      }

      html = MembershipPaymentFailure.render(assigns)
      assert is_binary(html)
      assert html =~ "Membership Renewal Payment Failed"
      assert html =~ "Urgent Action Required"
    end

    test "renders with invoice_id and retry_payment_url", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        membership_type: "Single",
        is_renewal: true,
        pay_membership_url: "https://example.com/users/membership",
        invoice_id: "in_123",
        retry_payment_url:
          "https://example.com/users/membership?retry_invoice=in_123"
      }

      html = MembershipPaymentFailure.render(assigns)
      assert html =~ "in_123"
      assert html =~ "Retry Payment Now"
    end

    test "prepare_email_data with renewal and invoice" do
      user = user_fixture()

      data =
        MembershipPaymentFailure.prepare_email_data(
          user,
          "single",
          true,
          "in_123"
        )

      assert data.is_renewal == true
      assert data.invoice_id == "in_123"
      assert data.retry_payment_url =~ "retry_invoice"
    end

    test "prepare_email_data with different membership types" do
      user = user_fixture()

      assert MembershipPaymentFailure.prepare_email_data(user, :single).membership_type ==
               "Single"

      assert MembershipPaymentFailure.prepare_email_data(user, :family).membership_type ==
               "Family"

      assert MembershipPaymentFailure.prepare_email_data(user, "single").membership_type ==
               "Single"

      assert MembershipPaymentFailure.prepare_email_data(user, "family").membership_type ==
               "Family"

      assert MembershipPaymentFailure.prepare_email_data(user, :other).membership_type ==
               "Membership"
    end

    test "prepare_email_data raises when user is nil" do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipPaymentFailure.prepare_email_data(nil, "single")
      end
    end

    test "retry_payment_url returns nil for non-binary" do
      assert MembershipPaymentFailure.retry_payment_url(nil) == nil
      assert MembershipPaymentFailure.retry_payment_url(123) == nil
    end
  end

  describe "MembershipPaymentConfirmation" do
    test "prepare_email_data with paid_elsewhere true" do
      user = user_fixture()

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          "Single",
          Money.new(50, :USD),
          ~D[2024-12-01],
          paid_elsewhere: true
        )

      assert data.paid_elsewhere == true
    end

    test "prepare_email_data with Date" do
      user = user_fixture()

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          "Single",
          Money.new(50, :USD),
          ~D[2024-12-01],
          []
        )

      assert data.payment_date =~ "December"
    end

    test "prepare_email_data with DateTime" do
      user = user_fixture()
      dt = DateTime.utc_now()

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          "Single",
          Money.new(50, :USD),
          dt,
          []
        )

      assert is_binary(data.payment_date)
    end

    test "prepare_email_data with invalid date" do
      user = user_fixture()

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          "Single",
          Money.new(50, :USD),
          "invalid",
          []
        )

      assert data.payment_date == "N/A"
    end

    test "prepare_email_data raises when user is nil" do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipPaymentConfirmation.prepare_email_data(
          nil,
          "Single",
          Money.new(50, :USD),
          ~D[2024-12-01],
          []
        )
      end
    end
  end

  describe "BookingCancellationTreasurerNotification" do
    test "get_subject with requires_review true" do
      assert BookingCancellationTreasurerNotification.get_subject(true) ==
               "Booking Cancellation - Action Required"
    end

    test "get_subject with requires_review false" do
      assert BookingCancellationTreasurerNotification.get_subject(false) ==
               "Booking Cancellation - Financial Notification"
    end

    test "prepare_email_data with booking and payment", %{user: user} do
      booking =
        booking_fixture(%{user_id: user.id})
        |> Ysc.Repo.preload(:user)

      payment = Ysc.LedgersFixtures.payment_fixture(%{user_id: user.id})

      data =
        BookingCancellationTreasurerNotification.prepare_email_data(
          booking,
          payment,
          nil,
          "User requested"
        )

      assert data.booking.reference_id == booking.reference_id
      assert data.user.email == user.email
      assert data.requires_review == false
      assert data.review_url == nil
    end

    test "prepare_email_data with pending_refund", %{user: user} do
      booking =
        booking_fixture(%{user_id: user.id})
        |> Ysc.Repo.preload(:user)

      pending_refund = %{
        policy_refund_amount: Money.new(100, :USD),
        cancellation_reason: "User requested",
        applied_rule_days_before_checkin: 7,
        applied_rule_refund_percentage: Decimal.new("50")
      }

      data =
        BookingCancellationTreasurerNotification.prepare_email_data(
          booking,
          nil,
          pending_refund,
          nil
        )

      assert data.requires_review == true
      assert data.review_url =~ "admin/bookings"
      assert data.pending_refund != nil
    end

    test "admin_bookings_url for different properties" do
      assert BookingCancellationTreasurerNotification.admin_bookings_url(:tahoe) =~
               "tahoe"

      assert BookingCancellationTreasurerNotification.admin_bookings_url(
               :clear_lake
             ) =~ "clear_lake"

      assert BookingCancellationTreasurerNotification.admin_bookings_url(:other) =~
               "other"
    end

    test "prepare_email_data raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        BookingCancellationTreasurerNotification.prepare_email_data(
          nil,
          nil,
          nil,
          nil
        )
      end
    end
  end

  describe "BookingCancellationCabinMasterNotification" do
    test "get_subject with requires_review true" do
      assert BookingCancellationCabinMasterNotification.get_subject(true) ==
               "Booking Cancellation - Action Required"
    end

    test "get_subject with requires_review false" do
      assert BookingCancellationCabinMasterNotification.get_subject(false) ==
               "Booking Cancellation Notification"
    end

    test "prepare_email_data with booking", %{user: user} do
      booking =
        booking_fixture(%{user_id: user.id})
        |> Ysc.Repo.preload(:user)

      data =
        BookingCancellationCabinMasterNotification.prepare_email_data(
          booking,
          nil,
          nil,
          nil
        )

      assert data.booking.reference_id == booking.reference_id
      assert data.user.email == user.email
    end

    test "prepare_email_data raises when booking is nil" do
      assert_raise ArgumentError, "Booking cannot be nil", fn ->
        BookingCancellationCabinMasterNotification.prepare_email_data(
          nil,
          nil,
          nil,
          nil
        )
      end
    end
  end

  describe "Notifier" do
    test "get_template_module returns correct modules" do
      assert Notifier.get_template_module("booking_confirmation") ==
               YscWeb.Emails.BookingConfirmation

      assert Notifier.get_template_module("family_invite") ==
               YscWeb.Emails.FamilyInvite

      assert Notifier.get_template_module("account_setup_verification") ==
               YscWeb.Emails.AccountSetupVerification

      assert Notifier.get_template_module("contact_form_board_notification") ==
               YscWeb.Emails.ContactFormBoardNotification
    end

    test "get_template_module returns nil for unknown template" do
      assert Notifier.get_template_module("unknown_template") == nil
    end
  end

  describe "template branches - MembershipRenewalSuccess" do
    test "renders with is_single_to_family_upgrade true" do
      assigns = %{
        first_name: "John",
        membership_type: "Family",
        renewal_date: "Dec 1, 2024",
        amount: "$65.00",
        is_single_to_family_upgrade: true,
        is_upgrade: false,
        is_downgrade: false,
        old_membership_type: nil,
        has_proration: false
      }

      html = MembershipRenewalSuccess.render(assigns)
      assert html =~ "Membership Upgrade Successful"
    end

    test "renders with is_upgrade and has_proration" do
      assigns = %{
        first_name: "John",
        membership_type: "Family",
        renewal_date: "Feb 17, 2026",
        amount: "$15.08",
        is_single_to_family_upgrade: false,
        is_upgrade: true,
        is_downgrade: false,
        old_membership_type: "Single",
        has_proration: true
      }

      html = MembershipRenewalSuccess.render(assigns)
      assert html =~ "upgraded from Single to Family"
    end

    test "renders with is_downgrade and has_proration" do
      assigns = %{
        first_name: "John",
        membership_type: "Single",
        renewal_date: "Feb 17, 2026",
        amount: "$10.00",
        is_single_to_family_upgrade: false,
        is_upgrade: false,
        is_downgrade: true,
        old_membership_type: "Family",
        has_proration: true
      }

      html = MembershipRenewalSuccess.render(assigns)
      assert html =~ "changed from Family to Single"
    end
  end

  describe "template branches - booking emails" do
    test "BookingCheckinReminder with cabin master" do
      assigns = %{
        first_name: "John",
        door_code: "1234",
        property: "tahoe",
        property_name: "Tahoe",
        property_address: "2685 Cedar Lane",
        checkin_date: "December 1, 2024",
        checkout_date: "December 3, 2024",
        checkin_time: "3:00 PM",
        checkout_time: "11:00 AM",
        days_until_checkin: 2,
        booking_reference_id: "BK-123",
        booking_mode: "Room Booking",
        room_names: "Room 1",
        nights: 2,
        is_buyout: false,
        guests_count: 2,
        children_count: 0,
        cabin_master_name: "Jane Smith",
        cabin_master_email: "jane@example.com",
        cabin_master_phone: "555-1234",
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingCheckinReminder.render(assigns)
      assert html =~ "Jane Smith"
      assert html =~ "jane@example.com"
      assert html =~ "555-1234"
    end

    test "BookingCheckoutReminder with cabin master" do
      assigns = %{
        first_name: "John",
        property: "tahoe",
        property_name: "Tahoe",
        property_address: "2685 Cedar Lane",
        checkout_date: "December 3, 2024",
        checkout_time: "11:00 AM",
        booking_reference_id: "BK-123",
        cabin_master_name: "Jane Smith",
        cabin_master_email: "jane@example.com",
        cabin_master_phone: "555-1234",
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingCheckoutReminder.render(assigns)
      assert html =~ "Jane Smith"
    end

    test "BookingConfirmation with is_buyout true" do
      assigns = %{
        first_name: "John",
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 4,
          children_count: 2,
          booking_mode: "Full Buyout",
          room_names: nil,
          nights: 2,
          is_buyout: true,
          booking_mode_raw: "buyout"
        },
        total_amount: "$400.00",
        booking_date: "Dec 1, 2024 at 10:00 AM",
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingConfirmation.render(assigns)
      assert is_binary(html)
      assert html =~ "Full Buyout"
    end

    test "TicketPurchaseConfirmation with has_discounts true" do
      assigns = %{
        first_name: "John",
        event: %{
          title: "Test Event",
          description: "A test event",
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          location_name: "Test Location",
          address: "123 Test St",
          age_restriction: "21+"
        },
        event_date_time: "Dec 1, 2024 at 10:00 AM",
        event_url: "https://example.com/events/123",
        agenda: [],
        ticket_order: %{
          reference_id: "TKT-123",
          total_amount: "$80.00",
          completed_at: DateTime.utc_now()
        },
        purchase_date: "Dec 1, 2024 at 10:00 AM",
        payment: %{
          reference_id: "PMT-123",
          external_payment_id: "pi_test_123",
          amount: "$80.00",
          payment_date: "Dec 1, 2024 at 10:00 AM"
        },
        payment_date: "Dec 1, 2024 at 10:00 AM",
        payment_method: "Credit Card ending in 1234",
        total_amount: "$80.00",
        gross_total: "$100.00",
        total_discount: "$20.00",
        has_discounts: true,
        ticket_summaries: [
          %{
            ticket_tier_name: "General Admission",
            quantity: 2,
            price_per_ticket: "$40.00",
            total_price: "$80.00",
            original_price: "$50.00",
            discount_amount: "$10.00",
            discount_percentage: 20.0
          }
        ],
        tickets: [
          %{
            reference_id: "TKT-001",
            ticket_tier_name: "General Admission",
            status: :confirmed
          }
        ],
        tickets_qr_url: "https://example.com/tickets/order-123/qr"
      }

      html = TicketPurchaseConfirmation.render(assigns)
      assert is_binary(html)
      assert html =~ "$20.00"
      assert html =~ assigns.tickets_qr_url
    end

    test "TicketPurchaseConfirmation with agenda" do
      assigns = %{
        first_name: "John",
        event: %{
          title: "Test Event",
          description: "A test event",
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          location_name: "Test Location",
          address: "123 Test St",
          age_restriction: "21+"
        },
        event_date_time: "Dec 1, 2024 at 10:00 AM",
        event_url: "https://example.com/events/123",
        agenda: [
          %{
            title: "Morning Session",
            items: [
              %{
                title: "Registration",
                description: "Check in",
                start_time: "09:00 AM",
                end_time: "09:30 AM",
                background_color: "#FEE2E2",
                border_color: "#F87171"
              }
            ]
          }
        ],
        ticket_order: %{
          reference_id: "TKT-123",
          total_amount: "$100.00",
          completed_at: DateTime.utc_now()
        },
        purchase_date: "Dec 1, 2024 at 10:00 AM",
        payment: %{
          reference_id: "PMT-123",
          external_payment_id: "pi_test_123",
          amount: "$100.00",
          payment_date: "Dec 1, 2024 at 10:00 AM"
        },
        payment_date: "Dec 1, 2024 at 10:00 AM",
        payment_method: "Credit Card ending in 1234",
        total_amount: "$100.00",
        gross_total: "$100.00",
        total_discount: "$0.00",
        has_discounts: false,
        ticket_summaries: [],
        tickets: [],
        tickets_qr_url: "https://example.com/tickets/order-123/qr"
      }

      html = TicketPurchaseConfirmation.render(assigns)
      assert is_binary(html)
      assert html =~ assigns.tickets_qr_url
    end

    test "ExpenseReportConfirmation with event and bank_account" do
      assigns = %{
        first_name: "John",
        expense_report: %{
          id: "EXP-123",
          purpose: "Test expense report",
          submitted_date: "Dec 1, 2024 at 10:00 AM",
          reimbursement_method: "Bank Transfer",
          expense_total: "$100.00",
          income_total: "$20.00",
          net_total: "$80.00",
          expense_items: [
            %{
              vendor: "Store",
              description: "Supplies",
              amount: "$100.00",
              date: "Dec 1, 2024",
              has_receipt: false
            }
          ],
          income_items: [
            %{
              description: "Reimbursement",
              amount: "$20.00",
              date: "Dec 1, 2024",
              has_proof: false
            }
          ],
          event: %{title: "Annual Meeting", reference_id: "EVT-123"},
          bank_account: %{last_4: "1234", bank_name: "Chase"}
        },
        expense_report_url: "https://example.com/expensereport/123"
      }

      html = ExpenseReportConfirmation.render(assigns)
      assert is_binary(html)
    end

    test "ExpenseReportTreasurerNotification with address" do
      user = user_fixture()

      assigns = %{
        expense_report: %{
          id: "EXP-123",
          purpose: "Test expense report",
          submitted_date: "Dec 1, 2024 at 10:00 AM",
          reimbursement_method: "Check",
          expense_total: "$100.00",
          income_total: "$0.00",
          net_total: "$100.00",
          expense_items: [],
          income_items: [],
          event: nil,
          bank_account: nil,
          address: %{
            address: "123 Main St",
            city: "City",
            region: "CA",
            postal_code: "94102"
          }
        },
        user: %{name: "#{user.first_name} #{user.last_name}", email: user.email},
        expense_report_url: "https://example.com/expensereport/123",
        admin_url: "https://example.com/admin/expense-reports/123"
      }

      html = ExpenseReportTreasurerNotification.render(assigns)
      assert is_binary(html)
    end

    test "BookingRefundPending with refund details" do
      assigns = %{
        first_name: "John",
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0
        },
        pending_refund: %{
          policy_refund_amount: "$100.00",
          cancellation_reason: "User requested",
          request_date: "Dec 1, 2024 at 10:00 AM",
          refund_percentage: 50.0
        },
        payment: %{reference_id: "PMT-123", amount: "$200.00"},
        request_date: "Dec 1, 2024 at 10:00 AM",
        policy_refund_amount: "$100.00",
        refund_percentage: 50.0,
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingRefundPending.render(assigns)
      assert is_binary(html)
    end

    test "BookingCancellationConfirmation with pending refund" do
      assigns = %{
        first_name: "John",
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0
        },
        cancellation: %{
          date: "Dec 1, 2024 at 10:00 AM",
          reason: "User requested"
        },
        payment: %{reference_id: "PMT-123", amount: "$200.00"},
        refund: %{amount: "$100.00", is_pending: true},
        booking_url: "https://example.com/bookings/123"
      }

      html = YscWeb.Emails.BookingCancellationConfirmation.render(assigns)
      assert is_binary(html)
    end

    test "EventNotification with age_restriction as integer" do
      assigns = %{
        first_name: "John",
        event: %{
          id: "EVT-123",
          title: "Test Event",
          description: "A test event",
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          end_date: nil,
          end_time: nil,
          location_name: "Test Location",
          address: "123 Test St",
          age_restriction: 21,
          organizer: %{first_name: "John", last_name: "Doe"}
        },
        event_date_time: "Dec 1, 2024 at 10:00 AM",
        event_url: "https://example.com/events/123",
        event_image_url: nil,
        notification_settings_url: "https://example.com/users/notifications"
      }

      html = EventNotification.render(assigns)
      assert is_binary(html)
    end
  end
end
