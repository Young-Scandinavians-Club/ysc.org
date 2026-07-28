defmodule YscWeb.Workers.EmailNotifierTest do
  use Ysc.DataCase, async: false

  alias Ysc.Accounts.AuthEvent
  alias Ysc.Newsletter
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

    test "skips all email categories after recipient hard bounces", %{
      user: user
    } do
      test_pid = self()

      handler_id =
        "hard-bounce-suppression-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:ysc, :email, :suppressed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _subscriber} =
        Newsletter.subscribe(user.email, user_id: user.id)

      assert {:ok, _subscriber} = Newsletter.handle_hard_bounce(user.email)

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" =>
                   "hard_bounce_account_#{System.unique_integer()}",
                 "subject" => "Must not send",
                 "template" => "booking_confirmation",
                 "params" => %{},
                 "text_body" => "Must not send",
                 "user_id" => user.id,
                 "category" => "account"
               })

      assert_no_email_sent()

      assert_receive {:telemetry, [:ysc, :email, :suppressed], %{count: 1},
                      %{
                        reason: :hard_bounce,
                        template: "booking_confirmation",
                        category: "account"
                      }}
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

    test "handles legacy args with optional reply_to", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-LEG-RT",
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

      reply = "legacy-reply-#{System.unique_integer()}@example.com"

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "legacy_reply_#{System.unique_integer()}",
                 "subject" => "Legacy With Reply-To",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "reply_to" => reply
               })

      assert_email_sent(subject: "Legacy With Reply-To", reply_to: reply)
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

    test "records invalid templates as terminal render failures", %{user: user} do
      assert {:error, :email_render_failed} =
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

    test "returns error for completely invalid job args" do
      assert {:error, "Invalid job args: missing required fields"} =
               perform_job(EmailNotifier, %{"foo" => "bar"})
    end

    test "normalizes tuple recipient to email string", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-TUPLE",
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

      job = %Oban.Job{
        id: System.unique_integer([:positive]),
        args: %{
          "recipient" => {"Display Name", user.email},
          "idempotency_key" => "tuple_recipient_#{System.unique_integer()}",
          "subject" => "Tuple Recipient",
          "template" => "booking_confirmation",
          "params" => params,
          "text_body" => "Text body",
          "user_id" => user.id,
          "category" => "bookings"
        },
        attempt: 1
      }

      assert :ok = EmailNotifier.perform(job)

      assert_email_sent(subject: "Tuple Recipient", to: {nil, user.email})
    end

    test "normalizes list recipient with {name, email} tuple", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-TUPLE-LIST",
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

      job = %Oban.Job{
        id: System.unique_integer([:positive]),
        args: %{
          "recipient" => [{"Display", user.email}],
          "idempotency_key" =>
            "tuple_list_recipient_#{System.unique_integer()}",
          "subject" => "Tuple List Recipient",
          "template" => "booking_confirmation",
          "params" => params,
          "text_body" => "Text body",
          "user_id" => user.id,
          "category" => "bookings"
        },
        attempt: 1
      }

      assert :ok = EmailNotifier.perform(job)

      assert_email_sent(subject: "Tuple List Recipient", to: {nil, user.email})
    end

    test "sends email when user_id is nil (board-style jobs skip preference check)" do
      params = %{
        first_name: "Board",
        booking: %{
          reference_id: "REF-NIL-USER",
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
                 "recipient" => "board-style@example.com",
                 "idempotency_key" => "nil_user_#{System.unique_integer()}",
                 "subject" => "Nil User Subject",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => nil,
                 "category" => "bookings"
               })

      assert_email_sent(
        subject: "Nil User Subject",
        to: {nil, "board-style@example.com"}
      )
    end

    test "normalizes unexpected recipient map via inspect fallback", %{
      user: user
    } do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-WEIRD",
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

      weird = %{not_a: "normal_recipient", email: user.email}

      job = %Oban.Job{
        id: System.unique_integer([:positive]),
        args: %{
          "recipient" => weird,
          "idempotency_key" => "weird_recipient_#{System.unique_integer()}",
          "subject" => "Weird Recipient",
          "template" => "booking_confirmation",
          "params" => params,
          "text_body" => "Text body",
          "user_id" => user.id,
          "category" => "bookings"
        },
        attempt: 1
      }

      assert :ok = EmailNotifier.perform(job)

      assert_email_sent(subject: "Weird Recipient")
    end

    test "normalizes list recipient with bare email string", %{user: user} do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-LIST",
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
                 "recipient" => [user.email],
                 "idempotency_key" =>
                   "list_recipient_#{System.unique_integer()}",
                 "subject" => "List Recipient",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      assert_email_sent(subject: "List Recipient", to: {nil, user.email})
    end

    test "legacy job args without user_id are invalid (inner invalid-args branch)" do
      assert {:error, "Invalid job args: missing required fields"} =
               perform_job(EmailNotifier, %{
                 "recipient" => "legacy-no-uid@example.com",
                 "idempotency_key" => "leg_no_uid_#{System.unique_integer()}",
                 "subject" => "Legacy Subject",
                 "template" => "booking_confirmation",
                 "params" => %{},
                 "text_body" => "Text body"
               })
    end

    test "normalizes list recipient with nil head via inspect fallback", %{
      user: user
    } do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-NIL-HEAD",
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

      job = %Oban.Job{
        id: System.unique_integer([:positive]),
        queue: "mailers",
        worker: "YscWeb.Workers.EmailNotifier",
        state: :executing,
        attempt: 1,
        args: %{
          "recipient" => [nil, user.email],
          "idempotency_key" => "nil_head_list_#{System.unique_integer()}",
          "subject" => "Nil head list",
          "template" => "booking_confirmation",
          "params" => params,
          "text_body" => "Text body",
          "user_id" => user.id,
          "category" => "bookings"
        }
      }

      assert :ok = EmailNotifier.perform(job)

      assert_email_sent(subject: "Nil head list")
    end

    test "perform logs job metadata when job struct includes queue and worker",
         %{
           user: user
         } do
      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-META",
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

      job = %Oban.Job{
        id: System.unique_integer([:positive]),
        queue: "mailers",
        worker: "YscWeb.Workers.EmailNotifier",
        state: :available,
        attempt: 1,
        args: %{
          "recipient" => user.email,
          "idempotency_key" => "meta_job_#{System.unique_integer()}",
          "subject" => "Meta job struct",
          "template" => "booking_confirmation",
          "params" => params,
          "text_body" => "Text body",
          "user_id" => user.id,
          "category" => "bookings"
        }
      }

      assert :ok = EmailNotifier.perform(job)

      assert_email_sent(subject: "Meta job struct")
    end
  end

  describe "perform/1 new_sign_in_detected deferred rendering" do
    test "resolves auth event details at send time and delivers email" do
      user = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(user, %{
          ip_address: "203.0.113.1",
          browser: "Chrome",
          operating_system: "macOS",
          country: "SE",
          region: "Stockholm",
          city: "Stockholm",
          threat_indicators: ["new_device"]
        })
        |> Ysc.Repo.insert()

      idempotency_key = "new_sign_in_#{user.id}_#{auth_event.id}"

      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => idempotency_key,
                 "subject" => "New Sign-In to Your YSC Account",
                 "template" => "new_sign_in_detected",
                 "params" => %{"auth_event_id" => auth_event.id},
                 "text_body" => "",
                 "user_id" => user.id,
                 "category" => "account"
               })

      assert_email_sent(
        subject: "New Sign-In to Your YSC Account",
        to: {nil, user.email},
        text_body: ~r/new device or browser/,
        html_body: ~r/Stockholm, Sweden/
      )

      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: idempotency_key
             )
    end

    test "records a terminal failure when auth event cannot be resolved for the user" do
      user = user_fixture()
      other = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(other, %{
          ip_address: "203.0.113.1",
          browser: "Chrome",
          operating_system: "macOS"
        })
        |> Ysc.Repo.insert()

      assert {:error, :email_render_failed} =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" =>
                   "new_sign_in_wrong_user_#{System.unique_integer()}",
                 "subject" => "New Sign-In to Your YSC Account",
                 "template" => "new_sign_in_detected",
                 "params" => %{"auth_event_id" => auth_event.id},
                 "text_body" => "",
                 "user_id" => user.id,
                 "category" => "account"
               })

      refute_email_sent()
    end

    test "records a terminal failure when deferred template is missing user_id" do
      user = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(user, %{
          ip_address: "203.0.113.1",
          browser: "Chrome",
          operating_system: "macOS"
        })
        |> Ysc.Repo.insert()

      assert {:error, :email_render_failed} =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" =>
                   "new_sign_in_missing_user_#{System.unique_integer()}",
                 "subject" => "New Sign-In to Your YSC Account",
                 "template" => "new_sign_in_detected",
                 "params" => %{"auth_event_id" => auth_event.id},
                 "text_body" => "",
                 "user_id" => nil,
                 "category" => "account"
               })

      refute_email_sent()
    end
  end

  describe "perform/1 invalid args" do
    test "returns error tuple when required keys are missing" do
      assert {:error, "Invalid job args: missing required fields"} =
               perform_job(EmailNotifier, %{
                 "recipient" => "a@example.com",
                 "template" => "booking_confirmation"
               })
    end
  end

  describe "perform/1 when Mailer.deliver fails" do
    setup do
      prev = Application.get_env(:ysc, Ysc.Mailer) || []

      on_exit(fn ->
        Application.put_env(:ysc, Ysc.Mailer, prev)
      end)

      {:ok, mailer_config: prev}
    end

    test "returns {:error, reason} when run_send_message_idempotent cannot deliver",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config, adapter: Ysc.Test.FailingSwooshAdapter)
      )

      user = user_fixture()
      key = "notifier_inline_fail_#{System.unique_integer()}"

      params = %{
        first_name: "John",
        booking: %{
          reference_id: "REF-FAIL-INLINE",
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

      assert {:error, "failed to send email"} =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => key,
                 "subject" => "Inline Mailer Failure",
                 "template" => "booking_confirmation",
                 "params" => params,
                 "text_body" => "Text body",
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      assert %Ysc.Messages.MessageIdempotency{delivery_status: :pending} =
               Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
                 idempotency_key: key
               )
    end
  end

  describe "atomize_keys/1" do
    test "recurses into nested maps and lists" do
      input = %{
        "outer" => %{
          "inner" => "v"
        },
        "items" => [%{"a" => 1}, %{"b" => 2}]
      }

      result = EmailNotifier.atomize_keys(input)

      assert result.outer.inner == "v"
      assert [first, second] = result.items
      assert first.a == 1
      assert second.b == 2
    end

    test "keeps string keys that are not existing atoms" do
      weird_key = "zz_unknown_atom_key_#{System.unique_integer()}"
      result = EmailNotifier.atomize_keys(%{weird_key => "keep"})

      assert Map.get(result, weird_key) == "keep"
    end

    test "passes through non-map, non-list values" do
      assert EmailNotifier.atomize_keys(:atom) == :atom
      assert EmailNotifier.atomize_keys(42) == 42
    end
  end

  describe "perform/1 additional templates" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "sends password_changed template", %{user: user} do
      assert :ok =
               perform_job(EmailNotifier, %{
                 "recipient" => user.email,
                 "idempotency_key" => "pwd_#{System.unique_integer()}",
                 "subject" => "Your password was changed",
                 "template" => "password_changed",
                 "params" => %{"first_name" => "Pat"},
                 "text_body" => "",
                 "user_id" => user.id,
                 "category" => "account"
               })

      assert_email_sent(subject: "Your password was changed")
    end
  end
end
