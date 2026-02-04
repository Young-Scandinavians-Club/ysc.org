defmodule YscWeb.Workers.SmsNotifierTest do
  use Ysc.DataCase

  alias YscWeb.Workers.SmsNotifier
  import Ysc.AccountsFixtures
  import Ecto.Query

  describe "perform/1" do
    setup do
      user = user_fixture()
      # Ensure user has phone number
      {:ok, updated_user} =
        Ysc.Accounts.update_user_profile(user, %{
          phone_number: "+12065551234"
        })

      # Update notification preferences separately
      {:ok, _} =
        Ysc.Accounts.update_notification_preferences(updated_user, %{
          account_notifications_sms: true
        })

      # Reload user to ensure we have fresh data
      user = Ysc.Repo.reload!(updated_user)

      # Clear rate limits before test
      Cachex.clear(:ysc_cache)

      %{user: user}
    end

    test "sends sms successfully", %{user: user} do
      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      result =
        perform_job(SmsNotifier, %{
          "phone_number" => "12065551234",
          "idempotency_key" => "sms_idemp_123",
          "template" => "booking_checkin_reminder",
          "params" => params,
          "user_id" => user.id,
          "category" => "bookings"
        })

      assert :ok = result

      # Verify idempotency record created
      # The transaction should have committed, so the record should be visible
      record =
        Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
          idempotency_key: "sms_idemp_123"
        )

      assert record != nil,
             "Expected idempotency record with key 'sms_idemp_123'"

      assert record.message_type == :sms
    end

    test "handles legacy args without category", %{user: user} do
      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      assert :ok =
               perform_job(SmsNotifier, %{
                 "phone_number" => "12065551234",
                 "idempotency_key" => "sms_legacy_123",
                 "template" => "booking_checkin_reminder",
                 "params" => params,
                 "user_id" => user.id
               })

      # Query all records to ensure we see committed transactions
      record =
        Ysc.Repo.one(
          from(m in Ysc.Messages.MessageIdempotency,
            where: m.idempotency_key == "sms_legacy_123"
          )
        )

      assert record != nil,
             "Expected idempotency record with key 'sms_legacy_123'"
    end

    test "skips sms if user notification preference is disabled", %{user: user} do
      # Disable notification for this category
      # "booking_checkin_reminder" likely maps to :account_notifications or :event_notifications?
      # Actually, looking at User schema:
      # field :account_notifications_sms, :boolean, default: true
      # field :event_notifications_sms, :boolean, default: true

      # Let's use "booking_checkin_reminder" and assume it maps to account_notifications_sms?
      # Or verify.
      # Ysc.Accounts.SmsCategories maps "booking_checkin_reminder" to something.
      # Let's check SmsCategories.
      # But I'll just disable both SMS prefs to be safe.

      {:ok, user} =
        Ysc.Accounts.update_notification_preferences(user, %{
          account_notifications_sms: false,
          event_notifications_sms: false,
          # required to be true
          account_notifications: true
        })

      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      assert :ok =
               perform_job(SmsNotifier, %{
                 "phone_number" => "12065551234",
                 "idempotency_key" => "sms_optout_123",
                 "template" => "booking_checkin_reminder",
                 "params" => params,
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      # Should NOT create idempotency record because it was skipped before sending
      refute Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: "sms_optout_123"
             )
    end

    test "uses user phone number if provided phone number is nil", %{user: user} do
      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      assert :ok =
               perform_job(SmsNotifier, %{
                 "phone_number" => nil,
                 "idempotency_key" => "sms_user_phone_123",
                 "template" => "booking_checkin_reminder",
                 "params" => params,
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      # Query all records to ensure we see committed transactions
      record =
        Ysc.Repo.one(
          from(m in Ysc.Messages.MessageIdempotency,
            where: m.idempotency_key == "sms_user_phone_123"
          )
        )

      assert record != nil,
             "Expected idempotency record with key 'sms_user_phone_123'"

      # The record should have the user's phone number
      # Normalize expected phone number
      assert record.phone_number == "12065551234"
    end

    test "skips if user has no phone number and none provided", %{user: user} do
      {:ok, user} =
        user
        |> Ecto.Changeset.change(phone_number: nil)
        |> Ysc.Repo.update()

      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      assert :ok =
               perform_job(SmsNotifier, %{
                 "phone_number" => nil,
                 "idempotency_key" => "sms_no_phone_123",
                 "template" => "booking_checkin_reminder",
                 "params" => params,
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      refute Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: "sms_no_phone_123"
             )
    end

    test "raises error for invalid template", %{user: user} do
      assert {:error,
              "Template module not found for template: non_existent_template"} =
               perform_job(SmsNotifier, %{
                 "phone_number" => "+12065551234",
                 "idempotency_key" => "sms_invalid_template_123",
                 "template" => "non_existent_template",
                 "params" => %{},
                 "user_id" => user.id,
                 "category" => "bookings"
               })
    end

    test "idempotency: duplicate job returns success but sends only one sms", %{
      user: user
    } do
      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      args = %{
        "phone_number" => "12065551234",
        "idempotency_key" => "sms_dup_123",
        "template" => "booking_checkin_reminder",
        "params" => params,
        "user_id" => user.id,
        "category" => "bookings"
      }

      # First run
      assert :ok = perform_job(SmsNotifier, args)
      # Verify idempotency record created
      record =
        Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
          idempotency_key: "sms_dup_123"
        )

      assert record != nil, "Expected idempotency record with key 'sms_dup_123'"

      initial_count =
        Ysc.Repo.aggregate(Ysc.Messages.MessageIdempotency, :count)

      # Second run
      assert :ok = perform_job(SmsNotifier, args)

      # Count should not increase (idempotency record already exists)
      final_count = Ysc.Repo.aggregate(Ysc.Messages.MessageIdempotency, :count)
      assert final_count == initial_count
    end
  end
end
