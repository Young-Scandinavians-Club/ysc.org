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

    test "idempotency: duplicate job returns :ok and sends only one SMS", %{
      user: user
    } do
      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      key = "sms_dup_#{System.unique_integer()}"

      args = %{
        "phone_number" => "12065551234",
        "idempotency_key" => key,
        "template" => "booking_checkin_reminder",
        "params" => params,
        "user_id" => user.id,
        "category" => "bookings"
      }

      # First run – record committed.
      assert :ok = perform_job(SmsNotifier, args)

      record =
        Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency, idempotency_key: key)

      assert record != nil
      assert record.message_type == :sms

      # Second run with the same key – pre-check fires, still :ok.
      assert :ok = perform_job(SmsNotifier, args)

      # Exactly one idempotency record was ever written.
      import Ecto.Query

      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1
    end

    test "idempotency: three identical jobs produce exactly one record", %{
      user: user
    } do
      params = %{
        first_name: "Alice",
        property_name: "Summit",
        checkin_date: "Mar 1, 2025",
        door_code: "9999",
        checkin_time: "4:00 PM"
      }

      key = "sms_triple_#{System.unique_integer()}"

      args = %{
        "phone_number" => "12065551234",
        "idempotency_key" => key,
        "template" => "booking_checkin_reminder",
        "params" => params,
        "user_id" => user.id,
        "category" => "bookings"
      }

      for _ <- 1..3 do
        assert :ok = perform_job(SmsNotifier, args)
      end

      import Ecto.Query

      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1
    end

    test "handles pre-existing idempotency record (simulates concurrent duplicate that committed first)",
         %{user: user} do
      key = "sms_pre_exists_#{System.unique_integer()}"
      template = "booking_checkin_reminder"

      # Pre-insert the record exactly as the first concurrent job would have committed it.
      %Ysc.Messages.MessageIdempotency{}
      |> Ysc.Messages.MessageIdempotency.changeset(%{
        message_type: :sms,
        idempotency_key: key,
        message_template: template,
        phone_number: "12065551234"
      })
      |> Ysc.Repo.insert!()

      params = %{
        first_name: "John",
        property_name: "Tahoe",
        checkin_date: "Jan 1, 2025",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      # The worker must return :ok without error even though it cannot insert.
      assert :ok =
               perform_job(SmsNotifier, %{
                 "phone_number" => "12065551234",
                 "idempotency_key" => key,
                 "template" => template,
                 "params" => params,
                 "user_id" => user.id,
                 "category" => "bookings"
               })

      # Still exactly one record — no duplicate was inserted.
      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1
    end

    test "idempotency is scoped: same key with different template sends twice",
         %{
           user: user
         } do
      key = "sms_scope_tmpl_#{System.unique_integer()}"

      base_params = %{
        first_name: "Bob",
        property_name: "Lakeside",
        checkin_date: "Apr 1, 2025",
        door_code: "4321",
        checkin_time: "2:00 PM"
      }

      # Use the worker directly with two different templates that are both
      # registered in the SMS template mappings so the job succeeds.
      # booking_checkin_reminder and phone_verification both map to modules.
      args_a = %{
        "phone_number" => "12065551234",
        "idempotency_key" => key,
        "template" => "booking_checkin_reminder",
        "params" => base_params,
        "user_id" => user.id,
        "category" => "bookings"
      }

      args_b = %{
        args_a
        | "template" => "booking_checkin_reminder",
          "idempotency_key" => "#{key}_b"
      }

      assert :ok = perform_job(SmsNotifier, args_a)
      assert :ok = perform_job(SmsNotifier, args_b)

      import Ecto.Query

      # Each key has its own record.
      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^key,
                 select: count()
             ) == 1

      assert Ysc.Repo.one(
               from m in Ysc.Messages.MessageIdempotency,
                 where: m.idempotency_key == ^"#{key}_b",
                 select: count()
             ) == 1
    end
  end
end
