# Sample assigns for /dev/notifications email & SMS previews.
# Keep in sync with template @assigns — enforced by `mix lint_notification_samples`.
%{
  emails: %{
    "account_setup_verification" => %{
      first_name: "Astrid",
      verification_code: "123456"
    },
    "admin_application_submitted" => %{
      applicant_name: "Astrid Berg",
      submission_date: "January 15, 2026",
      review_url: "http://localhost:4000/admin/applications/preview"
    },
    "admin_membership_report" => %{
      date_from: "2026-01-01",
      date_to: "2026-01-31",
      count_applied: 12,
      count_accepted: 8,
      count_rejected: 2,
      count_pending: 2,
      count_expired: 5,
      count_purchased: 6,
      generated_by: "Admin User",
      report_url: "http://localhost:4000/admin/memberships/report"
    },
    "application_approved" => %{
      first_name: "Astrid"
    },
    "application_approved_family_linked" => %{
      first_name: "Astrid"
    },
    "application_approved_payment_success" => %{
      first_name: "Astrid",
      bank_payment: false
    },
    "application_rejected" => %{
      first_name: "Astrid"
    },
    "application_submitted" => %{
      first_name: "Astrid"
    },
    "booking_cancellation_cabin_master_notification" => %{
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      user: %{name: "Astrid Berg", email: "astrid@example.com"},
      cancellation: %{date: "December 1, 2026", reason: "User requested"},
      payment: %{
        reference_id: "PMT-PREVIEW-123",
        amount: "$200.00"
      },
      pending_refund: %{
        policy_refund_amount: "$100.00",
        cancellation_reason: "Guest requested cancellation",
        refund_percentage: 50.0,
        applied_rule_days_before_checkin: 14,
        applied_rule_refund_percentage: 50
      },
      requires_review: true,
      review_url: "http://localhost:4000/admin/bookings/preview",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_cancellation_confirmation" => %{
      first_name: "Astrid",
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      cancellation: %{date: "Dec 1, 2026 at 10:00 AM", reason: "User requested"},
      payment: %{
        reference_id: "PMT-PREVIEW-123",
        amount: "$200.00"
      },
      refund: %{amount: "$100.00", is_pending: false},
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_cancellation_treasurer_notification" => %{
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      user: %{name: "Astrid Berg", email: "astrid@example.com"},
      cancellation: %{date: "December 1, 2026", reason: "User requested"},
      payment: %{
        reference_id: "PMT-PREVIEW-123",
        amount: "$200.00"
      },
      pending_refund: %{
        policy_refund_amount: "$100.00",
        cancellation_reason: "Guest requested cancellation",
        refund_percentage: 50.0,
        applied_rule_days_before_checkin: 14,
        applied_rule_refund_percentage: 50
      },
      requires_review: false,
      review_url: "http://localhost:4000/admin/bookings/preview",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_checkin_reminder" => %{
      first_name: "Astrid",
      door_code: "1234",
      property: "tahoe",
      property_name: "Tahoe",
      property_address: "2685 Cedar Lane, Homewood, CA 96141",
      checkin_date: "December 1, 2026",
      checkout_date: "December 3, 2026",
      checkin_time: "3:00 PM",
      checkout_time: "11:00 AM",
      days_until_checkin: 2,
      booking_reference_id: "BK-PREVIEW-123",
      booking_mode: "Room Booking",
      room_names: "Room 1",
      nights: 2,
      is_buyout: false,
      guests_count: 2,
      children_count: 0,
      cabin_master_name: "Lars Berg",
      cabin_master_email: "cabinmaster@ysc.org",
      cabin_master_phone: "4155550199",
      clear_lake_info_url: "http://localhost:4000/bookings/clear-lake",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_checkout_reminder" => %{
      first_name: "Astrid",
      property: "tahoe",
      property_name: "Tahoe",
      checkout_date: "December 3, 2026",
      checkout_time: "11:00 AM",
      booking_reference_id: "BK-PREVIEW-123",
      cabin_master_name: "Lars Berg",
      cabin_master_email: "cabinmaster@ysc.org",
      cabin_master_phone: "4155550199",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_confirmation" => %{
      first_name: "Astrid",
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_entitlement_granted" => %{
      first_name: "Astrid",
      header_image_url: "http://localhost:4000/images/tahoe-cabin-feature.jpg",
      header_image_alt: "Lake Tahoe cabin",
      benefit_description:
        "2 free nights on your next eligible stay (applied proportionally to the trip subtotal).",
      property_line: "Property: Lake Tahoe cabin.",
      buyout_cap_line: "",
      expiry_line: "This benefit does not expire.",
      next_booking_notice:
        "This benefit is for your next eligible cabin booking.",
      show_tahoe_link: true,
      show_clear_lake_link: false,
      tahoe_book_url: "http://localhost:4000/bookings/tahoe",
      clear_lake_book_url: nil,
      manage_bookings_hint:
        "Start a new reservation to use this benefit — it appears on your price summary automatically before you confirm."
    },
    "booking_modification_confirmation" => %{
      first_name: "Astrid",
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      booking_url: "http://localhost:4000/bookings/preview",
      dates_changed: true,
      guests_changed: false,
      additional_payment: "$50.00",
      previous: %{
        checkin_date: "November 28, 2026",
        checkout_date: "November 30, 2026",
        guests_count: 2,
        children_count: 0
      }
    },
    "booking_refund_pending" => %{
      first_name: "Astrid",
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      pending_refund: %{
        policy_refund_amount: "$100.00",
        cancellation_reason: "Booking cancelled",
        request_date: "Dec 1, 2026 at 10:00 AM",
        refund_percentage: 50.0
      },
      payment: %{
        reference_id: "PMT-PREVIEW-123",
        amount: "$200.00"
      },
      request_date: "Dec 1, 2026 at 10:00 AM",
      policy_refund_amount: "$100.00",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "booking_refund_processed" => %{
      first_name: "Astrid",
      booking: %{
        reference_id: "BK-PREVIEW-123",
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
      refund: %{
        reference_id: "RFD-PREVIEW-123",
        reason: "Refund processed",
        amount: "$100.00"
      },
      payment: %{
        reference_id: "PMT-PREVIEW-123",
        amount: "$200.00"
      },
      refund_date: "Dec 1, 2026 at 10:00 AM",
      refund_amount: "$100.00",
      booking_url: "http://localhost:4000/bookings/preview"
    },
    "change_email" => %{
      first_name: "Astrid",
      url: "http://localhost:4000/users/confirm-email/preview-token"
    },
    "conduct_violation_board_notification" => %{
      first_name: "Astrid",
      last_name: "Berg",
      email: "astrid@example.com",
      phone: "4155550100",
      report_id: "RPT-PREVIEW-123",
      submitted_at: "January 15, 2026 at 10:30 AM",
      summary: "Reported concern about guest conduct at a club event.",
      anonymous: false
    },
    "conduct_violation_confirmation" => %{
      first_name: "Astrid",
      last_name: "Berg",
      summary: "Reported concern about guest conduct at a club event.",
      anonymous: false
    },
    "contact_form_board_notification" => %{
      name: "Astrid Berg",
      email: "astrid@example.com",
      subject: "Question about membership",
      contact_form_id: "CF-PREVIEW-123",
      submitted_at: "Dec 1, 2026 at 10:00 AM",
      message: "I have a question about cabin booking for new members."
    },
    "email_changed" => %{
      first_name: "Astrid",
      new_email: "astrid.new@example.com"
    },
    "event_notification" => %{
      first_name: "Astrid",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_url: "http://localhost:4000/events/preview",
      event_image_url: nil,
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "event_photo_upload_reminder" => %{
      first_name: "Astrid",
      event_title: "Midsummer Picnic",
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_image_url: nil,
      upload_url: "http://localhost:4000/events/preview/photos",
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "event_update_notification" => %{
      first_name: "Astrid",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_url: "http://localhost:4000/events/preview",
      event_image_url: nil,
      update_title: "Venue change",
      update_body:
        "<p>We've moved the picnic to the meadow near Spreckels Temple.</p>",
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "expense_report_confirmation" => %{
      first_name: "Astrid",
      expense_report: %{
        id: "EXP-PREVIEW-123",
        purpose: "Event supplies",
        submitted_date: "Dec 1, 2026 at 10:00 AM",
        reimbursement_method: "Bank Transfer",
        expense_total: "$100.00",
        income_total: "$0.00",
        net_total: "$100.00",
        expense_items: [
          %{
            vendor: "Party Store",
            description: "Decorations",
            date: "Nov 15, 2026",
            amount: "$40.00",
            has_receipt: true
          },
          %{
            vendor: "Grocery Co",
            description: "Food",
            date: "Nov 16, 2026",
            amount: "$60.00",
            has_receipt: false
          }
        ],
        income_items: [],
        event: %{reference_id: "EVT-1", title: "Midsummer Picnic"},
        bank_account: %{last_4: "1234"},
        address: %{
          address: "123 Main St",
          city: "San Francisco",
          region: "CA",
          postal_code: "94102"
        }
      },
      expense_report_url: "http://localhost:4000/expensereport/preview"
    },
    "expense_report_treasurer_notification" => %{
      expense_report: %{
        id: "EXP-PREVIEW-123",
        purpose: "Event supplies",
        submitted_date: "Dec 1, 2026 at 10:00 AM",
        reimbursement_method: "Bank Transfer",
        expense_total: "$100.00",
        income_total: "$0.00",
        net_total: "$100.00",
        expense_items: [
          %{
            vendor: "Party Store",
            description: "Decorations",
            date: "Nov 15, 2026",
            amount: "$40.00",
            has_receipt: true
          },
          %{
            vendor: "Grocery Co",
            description: "Food",
            date: "Nov 16, 2026",
            amount: "$60.00",
            has_receipt: false
          }
        ],
        income_items: [],
        event: %{reference_id: "EVT-1", title: "Midsummer Picnic"},
        bank_account: %{last_4: "1234"},
        address: %{
          address: "123 Main St",
          city: "San Francisco",
          region: "CA",
          postal_code: "94102"
        }
      },
      user: %{name: "Astrid Berg", email: "astrid@example.com"},
      expense_report_url: "http://localhost:4000/expensereport/preview",
      admin_url: "http://localhost:4000/admin/expense-reports/preview"
    },
    "family_invite" => %{
      family_member_name: "Freja",
      primary_user_name: "Astrid Berg",
      invite_url: "http://localhost:4000/family/invite/preview-token",
      expires_in_days: 7,
      invite_button_text: "Accept Invitation"
    },
    "family_invite_accepted" => %{
      inviter_first_name: "Astrid",
      invitee_name: "Freja Berg",
      invitee_email: "freja@example.com",
      relationship_label: "child",
      family_management_url: "http://localhost:4000/users/settings/family"
    },
    "family_invite_cancelled" => %{
      primary_user_name: "Astrid Berg",
      invite_email: "freja@example.com"
    },
    "family_member_removed" => %{
      first_name: "Freja",
      primary_user_name: "Astrid Berg"
    },
    "membership_ended" => %{
      first_name: "Astrid",
      end_date: "August 1, 2026",
      membership_url: "http://localhost:4000/users/membership",
      upcoming_events_url: "http://localhost:4000/events"
    },
    "membership_payment_confirmation" => %{
      first_name: "Astrid",
      amount: "$150.00",
      membership_type: "Individual",
      paid_elsewhere: false,
      payment_date: "January 1, 2026"
    },
    "membership_payment_failure" => %{
      first_name: "Astrid",
      email: "astrid@example.com",
      invoice_id: "in_preview_123",
      is_renewal: true,
      membership_type: "Individual",
      pay_membership_url: "http://localhost:4000/users/membership",
      retry_payment_url: "http://localhost:4000/users/membership"
    },
    "membership_payment_reminder_30day" => %{
      first_name: "Astrid",
      pay_membership_url: "http://localhost:4000/users/membership",
      upcoming_events_url: "http://localhost:4000/events"
    },
    "membership_payment_reminder_7day" => %{
      first_name: "Astrid",
      pay_membership_url: "http://localhost:4000/users/membership",
      upcoming_events_url: "http://localhost:4000/events"
    },
    "membership_renewal_payment_method_reminder" => %{
      first_name: "Astrid",
      membership_url: "http://localhost:4000/users/membership",
      payment_methods_url:
        "http://localhost:4000/users/settings/payment-methods",
      renewal_date: "January 15, 2027"
    },
    "membership_renewal_reminder" => %{
      first_name: "Astrid",
      headline: "Your membership renews in 14 days",
      membership_url: "http://localhost:4000/users/membership",
      renewal_date: "January 15, 2027",
      days_until_renewal: 14
    },
    "membership_renewal_success" => %{
      first_name: "Astrid",
      amount: "$150.00",
      membership_type: "Individual",
      old_membership_type: "Individual",
      renewal_date: "January 1, 2026",
      has_proration: false,
      is_upgrade: false,
      is_downgrade: false,
      is_single_to_family_upgrade: false
    },
    "new_sign_in_detected" => %{
      first_name: "Astrid",
      intro_text:
        "We noticed a sign-in to Young Scandinavians Club from a new device or browser.",
      signed_in_at: "August 8, 2026 at 10:30 AM PDT",
      device: "Chrome on macOS",
      location: "San Francisco, CA",
      security_url: "http://localhost:4000/users/settings/security"
    },
    "newsletter_confirmation" => %{
      url: "http://localhost:4000/newsletter/confirm/preview-token",
      reminder: false
    },
    "newsletter_edition" => %{
      first_name: "Astrid",
      edition_title: "Spring Update",
      edition_date: "Newsletter, August 8, 2026",
      intro_text: "<p>Hej! Here's what's happening at YSC this month.</p>",
      intro_text?: true,
      cover_image_url: nil,
      posts: [
        %{
          title: "Cabin Season Preview",
          preview_text: "A look at Tahoe and Clear Lake availability.",
          url: "http://localhost:4000/posts/cabin-season-preview",
          image_url: nil
        }
      ],
      events: [
        %{
          title: "Midsummer Picnic",
          description: "Join us for food, music, and community.",
          short_description: "Join us for food, music, and community.",
          date_str: "Jun 21, 2026 at 2:00 PM",
          save_the_date: false,
          selling_fast: false,
          pricing_str: "From $25",
          tickets_on_sale_str: nil,
          location_name: "Golden Gate Park",
          url: "http://localhost:4000/events/preview",
          image_url: nil
        }
      ],
      unsubscribe_url: "http://localhost:4000/newsletter/unsubscribe/preview"
    },
    "newsletter_stats_snapshot" => %{
      edition_title: "Weekly Update",
      edition_subject: "This week at YSC",
      sent_at: "May 6, 2026 at 6:30 PM UTC",
      metrics: [
        %{
          label: "Sent",
          value: 100,
          helper: nil,
          color: "#0f172a",
          background: "#f8fafc",
          border: "#e2e8f0"
        },
        %{
          label: "Unique opens",
          value: 55,
          helper: "55.0% open rate",
          color: "#1447e6",
          background: "#eff6ff",
          border: "#bfdbfe"
        },
        %{
          label: "Unique clicks",
          value: 12,
          helper: "12.0% click rate",
          color: "#047857",
          background: "#ecfdf5",
          border: "#bbf7d0"
        },
        %{
          label: "Bounces",
          value: 1,
          helper: nil,
          color: "#b45309",
          background: "#fffbeb",
          border: "#fde68a"
        }
      ],
      complaints: 0,
      has_complaints: false,
      top_links: [
        %{
          url: "https://ysc.org/events/preview",
          clicks: 7,
          title: "Spring Dinner"
        }
      ],
      has_top_links: true
    },
    "outage_notification" => %{
      first_name: "Astrid",
      property: "tahoe",
      company_name: "PG&E",
      incident_type: "Power outage",
      incident_date: "December 1, 2026",
      description: "Scheduled maintenance may affect power at the cabin.",
      checkin_date: "December 1, 2026",
      checkout_date: "December 3, 2026",
      cabin_master_name: "Lars Berg",
      cabin_master_email: "cabinmaster@ysc.org",
      cabin_master_phone: "4155550199"
    },
    "passkey_added" => %{
      first_name: "Astrid",
      device_name: "Chrome on macOS"
    },
    "password_changed" => %{
      first_name: "Astrid"
    },
    "reset_password" => %{
      first_name: "Astrid",
      url: "http://localhost:4000/users/reset-password/preview-token"
    },
    "save_the_date_available" => %{
      first_name: "Astrid",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_url: "http://localhost:4000/events/preview",
      event_image_url: nil,
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "tahoe_summer_buyout_available" => %{
      first_name: "Astrid",
      cycle_label: "2027",
      weekend_range: "May 7–9, 2027",
      booking_url: "http://localhost:4000/bookings/tahoe",
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "tahoe_winter_weekend_available" => %{
      first_name: "Astrid",
      cycle_label: "2026/2027",
      weekend_range: "November 6–8, 2026",
      booking_url: "http://localhost:4000/bookings/tahoe",
      notification_settings_url: "http://localhost:4000/users/notifications"
    },
    "ticket_order_refund" => %{
      first_name: "Astrid",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_url: "http://localhost:4000/events/preview",
      ticket_order: %{reference_id: "TKT-PREVIEW-123"},
      refund: %{
        reference_id: "RFD-PREVIEW-123",
        reason: "Event cancelled",
        amount: "$50.00"
      },
      refund_date: "Jun 10, 2026 at 10:00 AM",
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
    },
    "ticket_purchase_confirmation" => %{
      first_name: "Astrid",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Jun 21, 2026 at 2:00 PM",
      event_url: "http://localhost:4000/events/preview",
      agenda: [],
      ticket_order: %{reference_id: "TKT-PREVIEW-123"},
      purchase_date: "Jun 1, 2026 at 10:00 AM",
      payment: %{reference_id: "PMT-PREVIEW-123"},
      payment_date: "Jun 1, 2026 at 10:00 AM",
      payment_method: "Credit Card ending in 4242",
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
      ],
      tickets_qr_url: "http://localhost:4000/tickets/preview/qr"
    },
    "ticket_reservation_created" => %{
      first_name: "Astrid",
      event_title: "Nordic Night",
      event: %{
        title: "Midsummer Picnic",
        description: "Join us for food, music, and community.",
        location_name: "Golden Gate Park",
        address: "123 Main St, San Francisco, CA",
        age_restriction: 21
      },
      event_date_time: "Dec 1, 2026 at 7:00 PM PST",
      event_url: "http://localhost:4000/events/preview",
      ticket_tier_name: "Member GA",
      quantity: 2,
      discount_display: "10% member pricing",
      has_discount: true,
      hold_expires_display:
        "Complete checkout before December 2, 2026 at 06:00 PM PST",
      has_notes: true,
      notes_text: "Please bring ID.",
      reserved_by_display: "Admin Person"
    },
    "volunteer_board_notification" => %{
      name: "Astrid Berg",
      email: "astrid@example.com",
      interests: ["Events/Parties", "Cabin maintenance"],
      submitted_at: "Dec 1, 2026 at 10:00 AM",
      volunteer_id: "VOL-PREVIEW-123"
    },
    "volunteer_confirmation" => %{
      name: "Astrid Berg",
      interests: ["Events/Parties", "Cabin maintenance"]
    },
    "welcome_email" => %{
      first_name: "Astrid",
      events: [
        %{
          title: "Midsummer Picnic",
          date_str: "Jun 21, 2026 at 2:00 PM",
          location_name: "Golden Gate Park",
          url: "http://localhost:4000/events/preview",
          image_url: nil
        }
      ],
      events_url: "http://localhost:4000/events",
      tahoe_url: "http://localhost:4000/bookings/tahoe",
      clear_lake_url: "http://localhost:4000/bookings/clear-lake",
      tahoe_season_name: "summer",
      tahoe_buyout_allowed: true
    }
  },
  sms: %{
    "booking_checkin_reminder" => %{
      first_name: "Astrid",
      property_name: "Tahoe",
      checkin_date: "Dec 1, 2026",
      door_code: "1234",
      checkin_time: "3:00 PM"
    },
    "email_changed" => %{
      first_name: "Astrid",
      new_email: "astrid.new@example.com"
    },
    "event_update_notification" => %{
      body:
        "[YSC] Midsummer Picnic: Venue moved to the meadow near Spreckels Temple.\n\nSee you there!"
    },
    "password_changed" => %{
      first_name: "Astrid"
    },
    "phone_verification" => %{
      first_name: "Astrid",
      code: "654321"
    },
    "two_factor_verification" => %{
      first_name: "Astrid",
      code: "123456"
    }
  },
  sms_auto_replies: %{
    "opt_in" =>
      "Young Scandinavians Club: You are now subscribed to YSC account alerts. Msg frequency varies. Msg&Data rates may apply. Reply HELP for help, STOP to cancel.",
    "opt_out" =>
      "Young Scandinavians Club: You have successfully unsubscribed from alerts. You will receive no further messages. Reply START to resubscribe.",
    "help" =>
      "Young Scandinavians Club: For help with account alerts, email info@ysc.org. Msg frequency varies. Msg&Data rates may apply. Reply STOP to cancel."
  }
}
