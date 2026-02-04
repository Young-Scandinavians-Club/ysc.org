defmodule YscWeb.Emails.AllEmailTemplatesTest do
  @moduledoc """
  Comprehensive tests to ensure ALL email templates can be rendered.

  This test file ensures every single email template in the system can be
  successfully rendered with appropriate test data, preventing template
  compilation errors and missing variable issues.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Emails.Notifier

  alias YscWeb.Emails.{
    ApplicationApproved,
    ApplicationRejected,
    ApplicationSubmitted,
    AdminApplicationSubmitted,
    ChangeEmail,
    ConfirmEmail,
    ResetPassword,
    PasswordChanged,
    PasskeyAdded,
    EmailChanged,
    ConductViolationConfirmation,
    ConductViolationBoardNotification,
    TicketPurchaseConfirmation,
    TicketOrderRefund,
    BookingConfirmation,
    BookingRefundProcessed,
    BookingRefundPending,
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingCancellationConfirmation,
    BookingCancellationCabinMasterNotification,
    BookingCancellationTreasurerNotification,
    VolunteerConfirmation,
    VolunteerBoardNotification,
    OutageNotification,
    MembershipPaymentConfirmation,
    MembershipPaymentFailure,
    MembershipRenewalSuccess,
    MembershipPaymentReminder7Day,
    MembershipPaymentReminder30Day,
    EventNotification,
    ExpenseReportConfirmation,
    ExpenseReportTreasurerNotification
  }

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "all email templates can be rendered" do
    test "ApplicationApproved renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationApproved.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ApplicationApproved.get_template_name() == "application_approved"
    end

    test "ApplicationRejected renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationRejected.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ApplicationRejected.get_template_name() == "application_rejected"
    end

    test "ApplicationSubmitted renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationSubmitted.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ApplicationSubmitted.get_template_name() == "application_submitted"
    end

    test "AdminApplicationSubmitted renders", %{user: user} do
      assigns = %{
        applicant_name: "#{user.first_name} #{user.last_name}",
        submission_date: "2024-01-15",
        review_url: "https://example.com/admin/applications/#{user.id}"
      }

      html = AdminApplicationSubmitted.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert AdminApplicationSubmitted.get_template_name() ==
               "admin_application_submitted"
    end

    test "ChangeEmail renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/confirm-email?token=abc123"
      }

      html = ChangeEmail.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ChangeEmail.get_template_name() == "change_email"
    end

    test "ConfirmEmail renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/confirm-email?token=abc123"
      }

      html = ConfirmEmail.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ConfirmEmail.get_template_name() == "confirm_email"
    end

    test "ResetPassword renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/reset-password?token=abc123"
      }

      html = ResetPassword.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert ResetPassword.get_template_name() == "reset_password"
    end

    test "PasswordChanged renders", %{user: user} do
      assigns = %{
        first_name: user.first_name
      }

      html = PasswordChanged.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert PasswordChanged.get_template_name() == "password_changed"
    end

    test "PasskeyAdded renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        device_name: "Chrome on macOS"
      }

      html = PasskeyAdded.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert PasskeyAdded.get_template_name() == "passkey_added"
    end

    test "EmailChanged renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        new_email: "newemail@example.com"
      }

      html = EmailChanged.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert EmailChanged.get_template_name() == "email_changed"
    end

    test "ConductViolationConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        summary: "Test violation summary",
        anonymous: false
      }

      html = ConductViolationConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert ConductViolationConfirmation.get_template_name() ==
               "conduct_violation_confirmation"
    end

    test "ConductViolationBoardNotification renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        phone: user.phone_number || "555-1234",
        report_id: "RPT-123",
        submitted_at: "2024-01-15 10:30:00",
        summary: "Test violation summary",
        anonymous: false
      }

      html = ConductViolationBoardNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert ConductViolationBoardNotification.get_template_name() ==
               "conduct_violation_board_notification"
    end

    test "TicketPurchaseConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
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
          total_amount: "$100.00",
          completed_at: DateTime.truncate(DateTime.utc_now(), :second)
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
        ticket_summaries: [
          %{
            ticket_tier_name: "General Admission",
            quantity: 2,
            price_per_ticket: "$50.00",
            total_price: "$100.00",
            original_price: nil,
            discount_amount: nil,
            discount_percentage: nil
          }
        ],
        tickets: [
          %{
            reference_id: "TKT-001",
            ticket_tier_name: "General Admission",
            status: :confirmed
          }
        ]
      }

      html = TicketPurchaseConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert TicketPurchaseConfirmation.get_template_name() ==
               "ticket_purchase_confirmation"
    end

    test "TicketOrderRefund renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        event: %{
          title: "Test Event",
          description: "A test event",
          start_date: ~D[2024-12-01],
          start_time: ~T[10:00:00],
          location_name: "Test Location",
          address: "123 Test St"
        },
        event_date_time: "Dec 1, 2024 at 10:00 AM",
        event_url: "https://example.com/events/123",
        ticket_order: %{
          reference_id: "TKT-123"
        },
        refund: %{
          reference_id: "RFD-123",
          amount: "$50.00",
          reason: "Refund processed",
          refund_date: "Dec 1, 2024 at 10:00 AM"
        },
        refund_date: "Dec 1, 2024 at 10:00 AM",
        refund_amount: "$50.00",
        ticket_summaries: [
          %{
            ticket_tier_name: "General Admission",
            quantity: 1,
            price_per_ticket: "$50.00",
            total_price: "$50.00"
          }
        ],
        refunded_tickets: [
          %{
            reference_id: "TKT-001",
            ticket_tier_name: "General Admission",
            status: :refunded
          }
        ]
      }

      html = TicketOrderRefund.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert TicketOrderRefund.get_template_name() == "ticket_order_refund"
    end

    test "BookingConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 2,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$200.00",
        booking_date: "Dec 1, 2024 at 10:00 AM",
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert BookingConfirmation.get_template_name() == "booking_confirmation"
    end

    test "BookingRefundProcessed renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0
        },
        refund: %{
          reference_id: "RFD-123",
          amount: "$100.00",
          reason: "Refund processed",
          refund_date: "Dec 1, 2024 at 10:00 AM"
        },
        payment: %{
          reference_id: "PMT-123",
          amount: "$200.00"
        },
        refund_date: "Dec 1, 2024 at 10:00 AM",
        refund_amount: "$100.00",
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingRefundProcessed.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingRefundProcessed.get_template_name() ==
               "booking_refund_processed"
    end

    test "BookingRefundPending renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
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
          cancellation_reason: "Booking cancelled",
          request_date: "Dec 1, 2024 at 10:00 AM",
          refund_percentage: 50.0
        },
        payment: %{
          reference_id: "PMT-123",
          amount: "$200.00"
        },
        request_date: "Dec 1, 2024 at 10:00 AM",
        policy_refund_amount: "$100.00",
        refund_percentage: 50.0,
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingRefundPending.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingRefundPending.get_template_name() ==
               "booking_refund_pending"
    end

    test "BookingCheckinReminder renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        door_code: "1234",
        property: "tahoe",
        property_name: "Tahoe",
        property_address: "2685 Cedar Lane, Homewood, CA 96141",
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
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil,
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingCheckinReminder.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingCheckinReminder.get_template_name() ==
               "booking_checkin_reminder"
    end

    test "BookingCheckoutReminder renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        property: "tahoe",
        property_name: "Tahoe",
        property_address: "2685 Cedar Lane, Homewood, CA 96141",
        checkout_date: "December 3, 2024",
        checkout_time: "11:00 AM",
        booking_reference_id: "BK-123",
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil,
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingCheckoutReminder.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingCheckoutReminder.get_template_name() ==
               "booking_checkout_reminder"
    end

    test "BookingCancellationConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
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
        payment: %{
          reference_id: "PMT-123",
          amount: "$200.00"
        },
        refund: %{
          amount: "$100.00",
          is_pending: false
        },
        booking_url: "https://example.com/bookings/123"
      }

      html = BookingCancellationConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingCancellationConfirmation.get_template_name() ==
               "booking_cancellation_confirmation"
    end

    test "BookingCancellationCabinMasterNotification renders", %{user: user} do
      assigns = %{
        booking_reference_id: "BK-123",
        user_name: "#{user.first_name} #{user.last_name}",
        user_email: user.email,
        property_name: "Tahoe",
        checkin_date: "December 1, 2024",
        checkout_date: "December 3, 2024",
        cancellation_reason: "User requested",
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0
        },
        user: %{
          name: "#{user.first_name} #{user.last_name}",
          email: user.email
        },
        cancellation: %{
          date: "December 1, 2024",
          reason: "User requested"
        },
        payment: %{
          reference_id: "PMT-123",
          amount: "$200.00"
        },
        pending_refund: nil,
        requires_review: false,
        review_url: "https://example.com/admin/bookings",
        booking_url: "https://example.com/admin/bookings/123"
      }

      html = BookingCancellationCabinMasterNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingCancellationCabinMasterNotification.get_template_name() ==
               "booking_cancellation_cabin_master_notification"
    end

    test "BookingCancellationTreasurerNotification renders", %{user: user} do
      assigns = %{
        booking: %{
          reference_id: "BK-123",
          property: "Tahoe",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          guests_count: 2,
          children_count: 0
        },
        user: %{
          name: "#{user.first_name} #{user.last_name}",
          email: user.email
        },
        cancellation: %{
          date: "Dec 1, 2024 at 10:00 AM",
          reason: "User requested"
        },
        payment: %{
          reference_id: "PMT-123",
          amount: "$200.00"
        },
        pending_refund: nil,
        requires_review: false,
        review_url: nil,
        booking_url: "https://example.com/admin/bookings/123"
      }

      html = BookingCancellationTreasurerNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert BookingCancellationTreasurerNotification.get_template_name() ==
               "booking_cancellation_treasurer_notification"
    end

    test "VolunteerConfirmation renders", %{user: user} do
      assigns = %{
        name: "#{user.first_name} #{user.last_name}",
        interests: ["Events/Parties", "Activities"]
      }

      html = VolunteerConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert VolunteerConfirmation.get_template_name() ==
               "volunteer_confirmation"
    end

    test "VolunteerBoardNotification renders", %{user: user} do
      assigns = %{
        name: "#{user.first_name} #{user.last_name}",
        email: user.email,
        volunteer_id: "VOL-123",
        interests: ["Events/Parties", "Activities"],
        submitted_at: "Dec 1, 2024 at 10:00 AM"
      }

      html = VolunteerBoardNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert VolunteerBoardNotification.get_template_name() ==
               "volunteer_board_notification"
    end

    test "OutageNotification renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        property: :tahoe,
        property_name: "Tahoe",
        incident_type: :power_outage,
        outage_type: "Power Outage",
        company_name: "PG&E",
        incident_date: ~D[2024-12-01],
        description: "Power outage reported",
        checkin_date: ~D[2024-12-05],
        checkout_date: ~D[2024-12-07],
        cabin_master_name: nil,
        cabin_master_email: nil,
        cabin_master_phone: nil
      }

      html = OutageNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert OutageNotification.get_template_name() == "outage_notification"
    end

    test "MembershipPaymentFailure renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        membership_type: "Single",
        is_renewal: false,
        pay_membership_url: "https://example.com/users/membership",
        invoice_id: nil,
        retry_payment_url: nil
      }

      html = MembershipPaymentFailure.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert MembershipPaymentFailure.get_template_name() ==
               "membership_payment_failure"
    end

    test "MembershipPaymentConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        membership_type: "Single",
        payment_date: "Dec 1, 2024",
        amount: "$50.00",
        paid_elsewhere: false
      }

      html = MembershipPaymentConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert MembershipPaymentConfirmation.get_template_name() ==
               "membership_payment_confirmation"
    end

    test "MembershipRenewalSuccess renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        membership_type: "Single",
        renewal_date: "Dec 1, 2024",
        amount: "$50.00"
      }

      html = MembershipRenewalSuccess.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert MembershipRenewalSuccess.get_template_name() ==
               "membership_renewal_success"
    end

    test "MembershipPaymentReminder7Day renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        membership_type: "Single",
        due_date: "Dec 8, 2024",
        pay_membership_url: "https://example.com/users/membership",
        upcoming_events_url: "https://example.com/events"
      }

      html = MembershipPaymentReminder7Day.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert MembershipPaymentReminder7Day.get_template_name() ==
               "membership_payment_reminder_7day"
    end

    test "MembershipPaymentReminder30Day renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        membership_type: "Single",
        due_date: "Dec 31, 2024",
        pay_membership_url: "https://example.com/users/membership",
        upcoming_events_url: "https://example.com/events"
      }

      html = MembershipPaymentReminder30Day.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert MembershipPaymentReminder30Day.get_template_name() ==
               "membership_payment_reminder_30day"
    end

    test "EventNotification renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
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
          age_restriction: "21+",
          organizer: %{
            first_name: "John",
            last_name: "Doe"
          }
        },
        event_date_time: "Dec 1, 2024 at 10:00 AM",
        event_url: "https://example.com/events/123"
      }

      html = EventNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0
      assert EventNotification.get_template_name() == "event_notification"
    end

    test "ExpenseReportConfirmation renders", %{user: user} do
      assigns = %{
        first_name: user.first_name,
        expense_report: %{
          id: "EXP-123",
          purpose: "Test expense report",
          submitted_date: "Dec 1, 2024 at 10:00 AM",
          reimbursement_method: "Bank Transfer",
          expense_total: "$100.00",
          income_total: "$0.00",
          net_total: "$100.00",
          expense_items: [],
          income_items: [],
          event: nil,
          bank_account: nil
        },
        expense_report_url: "https://example.com/expensereport/123"
      }

      html = ExpenseReportConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert ExpenseReportConfirmation.get_template_name() ==
               "expense_report_confirmation"
    end

    test "ExpenseReportTreasurerNotification renders", %{user: user} do
      assigns = %{
        expense_report: %{
          id: "EXP-123",
          purpose: "Test expense report",
          submitted_date: "Dec 1, 2024 at 10:00 AM",
          reimbursement_method: "Bank Transfer",
          expense_total: "$100.00",
          income_total: "$0.00",
          net_total: "$100.00",
          expense_items: [],
          income_items: [],
          event: nil,
          bank_account: nil,
          address: nil
        },
        user: %{
          name: "#{user.first_name} #{user.last_name}",
          email: user.email
        },
        expense_report_url: "https://example.com/expensereport/123",
        admin_url: "https://example.com/admin/expense-reports/123"
      }

      html = ExpenseReportTreasurerNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      assert ExpenseReportTreasurerNotification.get_template_name() ==
               "expense_report_treasurer_notification"
    end
  end

  describe "all email templates are registered in Notifier" do
    test "every template in Notifier can be loaded and rendered" do
      # Get all template mappings from Notifier
      template_mappings = %{
        "application_rejected" => ApplicationRejected,
        "application_approved" => ApplicationApproved,
        "application_submitted" => ApplicationSubmitted,
        "confirm_email" => ConfirmEmail,
        "reset_password" => ResetPassword,
        "password_changed" => PasswordChanged,
        "passkey_added" => PasskeyAdded,
        "change_email" => ChangeEmail,
        "email_changed" => EmailChanged,
        "admin_application_submitted" => AdminApplicationSubmitted,
        "conduct_violation_confirmation" => ConductViolationConfirmation,
        "conduct_violation_board_notification" =>
          ConductViolationBoardNotification,
        "ticket_purchase_confirmation" => TicketPurchaseConfirmation,
        "ticket_order_refund" => TicketOrderRefund,
        "booking_confirmation" => BookingConfirmation,
        "booking_refund_processed" => BookingRefundProcessed,
        "booking_refund_pending" => BookingRefundPending,
        "volunteer_confirmation" => VolunteerConfirmation,
        "volunteer_board_notification" => VolunteerBoardNotification,
        "outage_notification" => OutageNotification,
        "membership_payment_confirmation" => MembershipPaymentConfirmation,
        "membership_payment_failure" => MembershipPaymentFailure,
        "membership_renewal_success" => MembershipRenewalSuccess,
        "membership_payment_reminder_7day" => MembershipPaymentReminder7Day,
        "membership_payment_reminder_30day" => MembershipPaymentReminder30Day,
        "booking_checkin_reminder" => BookingCheckinReminder,
        "booking_checkout_reminder" => BookingCheckoutReminder,
        "event_notification" => EventNotification,
        "expense_report_confirmation" => ExpenseReportConfirmation,
        "expense_report_treasurer_notification" =>
          ExpenseReportTreasurerNotification,
        "booking_cancellation_confirmation" => BookingCancellationConfirmation,
        "booking_cancellation_cabin_master_notification" =>
          BookingCancellationCabinMasterNotification,
        "booking_cancellation_treasurer_notification" =>
          BookingCancellationTreasurerNotification
      }

      for {template_name, expected_module} <- template_mappings do
        # Verify Notifier can find the template
        module = Notifier.get_template_module(template_name)

        assert module == expected_module,
               "Template #{template_name} should map to #{expected_module}, got #{module}"

        # Verify module can be loaded
        assert Code.ensure_loaded?(module),
               "Template module #{module} cannot be loaded"

        # Verify module has required functions
        assert function_exported?(module, :get_template_name, 0),
               "Template module #{module} missing get_template_name/0"

        # Verify template name matches
        assert module.get_template_name() == template_name,
               "Template name mismatch for #{module}: expected #{template_name}, got #{module.get_template_name()}"
      end
    end
  end
end
