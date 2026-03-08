defmodule YscWeb.Workers.EmailNotifierTest do
  use Ysc.DataCase

  alias YscWeb.Emails.Notifier
  alias YscWeb.Workers.EmailNotifier
  import Ysc.AccountsFixtures
  import Swoosh.TestAssertions

  describe "perform/1" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "sends email successfully", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF123",
          property: "Tahoe",
          checkin_date: "Jan 1, 2024",
          checkout_date: "Jan 5, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 4,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$100.00",
        booking_date: "Dec 25, 2023",
        booking_url: "http://example.com/bookings/123"
      }

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "idemp_123",
                 "subject" => "Test Subject",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      assert_email_sent(
        subject: "Test Subject",
        to: {nil, user.email},
        html_body: ~r/REF123/
      )

      # Verify idempotency record created
      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: "idemp_123"
             )
    end

    test "handles legacy args without category", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF123",
          property: "Tahoe",
          checkin_date: "Jan 1, 2024",
          checkout_date: "Jan 5, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 4,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$100.00",
        booking_date: "Dec 25, 2023",
        booking_url: "http://example.com/bookings/123"
      }

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "legacy_123",
                 "subject" => "Legacy Subject",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id
               })

      assert_email_sent(subject: "Legacy Subject")
    end

    test "skips email if user notification preference is disabled", %{
      user: user
    } do
      # Disable notification for this category (bookings)
      # Assuming "booking_confirmation" maps to :bookings category and user has it enabled by default
      {:ok, user} =
        Ysc.Accounts.update_notification_preferences(user, %{
          account_notifications: true,
          account_notifications_sms: true,
          event_notifications: true,
          event_notifications_sms: true
          # We need to find where "bookings" preference is stored.
          # Looking at User schema, it has:
          # event_notifications
          # account_notifications
          # (Newsletter state lives in newsletter_subscribers.)
          # It does NOT have "bookings" field.
          # But EmailCategories might map "booking_confirmation" to one of these.
        })

      # Let's check EmailCategories mapping.
      # But for now, let's mock a preference update by updating the user directly if needed.
      # However, EmailCategories.should_send_email? logic matters.
      # Let's check EmailCategories.

      # Assuming bookings maps to :account_notifications (most likely for transactional/booking emails)
      # Wait, booking emails are usually transactional and shouldn't be disabled?
      # Or maybe they map to account_notifications.
      # Let's update account_notifications to false? But validation says it cannot be disabled.

      # Let's skip this test if I can't easily disable it, or find a category that CAN be disabled.
      # "event_notification" maps to :event_notifications.
      # Let's use "event_notification" template for this test.

      {:ok, user} =
        Ysc.Accounts.update_notification_preferences(user, %{
          event_notifications: false,
          account_notifications: true
        })

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "optout_123",
                 "subject" => "OptOut Subject",
                 "template" => "event_notification",
                 "params" => %{
                   event_title: "Test Event",
                   event_description: "Desc",
                   event_url: "url",
                   event_date: "date",
                   event_location: "loc",
                   first_name: "John"
                 },
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "events"
               })

      assert_no_email_sent()
    end

    test "sends email even if user not found (fallback)", %{user: _user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF123",
          property: "Tahoe",
          checkin_date: "Jan 1, 2024",
          checkout_date: "Jan 5, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 4,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$100.00",
        booking_date: "Dec 25, 2023",
        booking_url: "http://example.com/bookings/123"
      }

      non_existent_id = Ecto.ULID.generate()

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => "unknown@example.com",
                 "idempotency_key" => "unknown_user_123",
                 "subject" => "Unknown User Subject",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => non_existent_id,
                 "category" => "bookings"
               })

      assert_email_sent(subject: "Unknown User Subject")
    end

    test "raises error for invalid template", %{user: user} do
      assert {:error,
              %RuntimeError{
                message:
                  "Template module not found for template: non_existent_template"
              }} =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "invalid_template_123",
                 "subject" => "Invalid Template",
                 "template" => "non_existent_template",
                 "params" => %{},
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "bookings"
               })
    end

    test "schedule_email includes reply_to for membership templates", %{
      user: user
    } do
      job =
        Notifier.deliver_membership_payment_confirmation(
          user,
          :single,
          Money.new(50, :USD),
          ~D[2024-12-01]
        )

      assert job
      assert job.args["reply_to"] == Ysc.EmailConfig.membership_email()
    end

    test "sets reply_to to memberships@ysc.org for membership emails", %{
      user: user
    } do
      params = %{
        first_name: "Jane",
        membership_type: "Single",
        amount: "$50.00",
        payment_date: "December 01, 2024",
        paid_elsewhere: false
      }

      membership_email = Ysc.EmailConfig.membership_email()

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "membership_reply_to_test",
                 "subject" => "Welcome to YSC – Your Membership is Active! 🎉",
                 "template" => "membership_payment_confirmation",
                 "params" => params,
                 "text_body" => "",
                 "user_id" => user.id,
                 "category" => "account",
                 "reply_to" => membership_email
               })

      assert_email_sent(
        subject: "Welcome to YSC – Your Membership is Active! 🎉",
        to: {nil, user.email},
        reply_to: membership_email
      )
    end

    test "idempotency: duplicate job returns :ok but sends only one email",
         %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF123",
          property: "Tahoe",
          checkin_date: "Jan 1, 2024",
          checkout_date: "Jan 5, 2024",
          guests_count: 2,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 4,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$100.00",
        booking_date: "Dec 25, 2023",
        booking_url: "http://example.com/bookings/123"
      }

      args = %{
        "recipient" => user.email,
        "idempotency_key" => "idemp_dup_worker_#{System.unique_integer()}",
        "subject" => "Duplicate Subject",
        "template" => "booking_confirmation",
        "params" => params,
        "text_body" => "Text body",
        "user_id" => user.id,
        "category" => "bookings"
      }

      key = args["idempotency_key"]

      # First run – email delivered, idempotency record committed.
      assert :ok = perform_job(EmailNotifier, args)
      assert_email_sent(subject: "Duplicate Subject")

      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: key
             )

      # Second run with identical args – pre-check fires, Mailer is never called.
      assert :ok = perform_job(EmailNotifier, args)
      assert_no_email_sent()

      # Exactly one idempotency record was ever written.
      import Ecto.Query

      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1
    end

    test "idempotency: three identical jobs produce exactly one email and one record",
         %{user: user} do
      params = %{
        first_name: "Jane",
        booking: %{
          reference_id: "REF999",
          property: "Alpine",
          checkin_date: "Feb 1, 2025",
          checkout_date: "Feb 3, 2025",
          guests_count: 1,
          children_count: 0,
          booking_mode: "Room Booking",
          room_names: "Room 2",
          nights: 2,
          is_buyout: false,
          booking_mode_raw: "room"
        },
        total_amount: "$200.00",
        booking_date: "Jan 25, 2025",
        booking_url: "http://example.com/bookings/999"
      }

      key = "idemp_triple_#{System.unique_integer()}"

      args = %{
        "recipient" => user.email,
        "idempotency_key" => key,
        "subject" => "Triple Idempotency",
        "template" => "booking_confirmation",
        "params" => params,
        "text_body" => "",
        "user_id" => user.id,
        "category" => "bookings"
      }

      assert :ok = perform_job(EmailNotifier, args)
      assert_email_sent(subject: "Triple Idempotency")

      assert :ok = perform_job(EmailNotifier, args)
      assert_no_email_sent()

      assert :ok = perform_job(EmailNotifier, args)
      assert_no_email_sent()

      import Ecto.Query

      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1
    end
  end
end
