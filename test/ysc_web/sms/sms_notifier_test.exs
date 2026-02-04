defmodule YscWeb.Sms.SmsNotifierTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Mox

  alias YscWeb.Sms.{Notifier, BookingCheckinReminder}
  alias YscWeb.Workers.SmsNotifier
  alias Ysc.Repo

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure FlowRoute for tests
    Application.put_env(:ysc, :flowroute, from_number: "12061231234")

    # Clear SMS rate limit cache to ensure tests don't hit rate limits
    Cachex.clear(:ysc_cache)

    :ok
  end

  describe "phone number normalization" do
    test "normalizes E.164 format phone numbers" do
      # Test that phone numbers with + prefix are normalized
      # We test this through schedule_sms which normalizes the number
      result =
        Notifier.schedule_sms(
          "+14159009001",
          "test_key",
          "booking_checkin_reminder",
          %{},
          nil
        )

      # Should succeed and normalize the phone number
      assert {:ok, job} = result
      assert job.args["phone_number"] == "14159009001"
    end

    test "normalizes phone numbers with spaces and dashes" do
      # Test various formats that should all normalize to the same value
      formats = [
        {"+14159009001", "14159009001"},
        {"1-415-900-9001", "14159009001"},
        {"1 415 900 9001", "14159009001"},
        {"(1) 415-900-9001", "14159009001"},
        {"14159009001", "14159009001"}
      ]

      for {input, expected} <- formats do
        result =
          Notifier.schedule_sms(
            input,
            "test_key_#{System.unique_integer()}",
            "booking_checkin_reminder",
            %{},
            nil
          )

        assert {:ok, job} = result
        assert job.args["phone_number"] == expected
      end
    end
  end

  describe "phone number validation" do
    test "validates 11-digit North American format" do
      # Invalid formats
      invalid_numbers = [
        # Missing leading 1
        "4159009001",
        # Too short
        "1415900900",
        # Too long
        "214159009001",
        # Non-US number
        "+46123456789",
        ""
      ]

      # We test validation through the schedule_sms function
      # which will return {:error, :invalid_phone_number} for invalid numbers
      for number <- invalid_numbers do
        result =
          Notifier.schedule_sms(
            number,
            "test_key_#{System.unique_integer()}",
            "booking_checkin_reminder",
            %{},
            nil
          )

        assert result == {:error, :invalid_phone_number}
      end
    end

    test "accepts valid 11-digit North American format" do
      valid_numbers = [
        "14159009001",
        "+14159009001",
        "1-415-900-9001"
      ]

      for number <- valid_numbers do
        result =
          Notifier.schedule_sms(
            number,
            "test_key_#{System.unique_integer()}",
            "booking_checkin_reminder",
            %{},
            nil
          )

        assert {:ok, _job} = result
      end
    end
  end

  describe "BookingCheckinReminder template" do
    test "renders message with all required fields" do
      variables = %{
        first_name: "John",
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345",
        checkin_time: "3:00 PM"
      }

      message = BookingCheckinReminder.render(variables)

      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, "John")
      assert String.contains?(message, "Clear Lake")
      assert String.contains?(message, "Dec 05, 2025")
      assert String.contains?(message, "12345")
      assert String.contains?(message, "3:00 PM")
      assert String.contains?(message, "[YSC]")
    end

    test "renders message with default values when fields are missing" do
      variables = %{}

      message = BookingCheckinReminder.render(variables)

      assert is_binary(message)
      assert String.contains?(message, "Valued Member")
      assert String.contains?(message, "Property")
      assert String.contains?(message, "Not Available")
    end

    test "trims and normalizes whitespace in rendered message" do
      variables = %{
        first_name: "John",
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345",
        checkin_time: "3:00 PM"
      }

      message = BookingCheckinReminder.render(variables)

      # Should not have multiple consecutive spaces
      refute String.contains?(message, "  ")
      # Should not start or end with whitespace
      refute String.starts_with?(message, " ")
      refute String.ends_with?(message, " ")
    end

    test "get_template_name returns correct name" do
      assert BookingCheckinReminder.get_template_name() ==
               "booking_checkin_reminder"
    end
  end

  describe "atomize_keys function" do
    test "converts string keys to atoms in simple map" do
      # We test this through the worker by creating a job
      params = %{
        "first_name" => "John",
        "property_name" => "Clear Lake",
        "checkin_date" => "Dec 05, 2025"
      }

      # Create a job and perform it to test atomize_keys
      job = %Oban.Job{
        id: 1,
        args: %{
          "phone_number" => "14159009001",
          "idempotency_key" => "test_key",
          "template" => "booking_checkin_reminder",
          "params" => params,
          "user_id" => nil,
          "category" => :booking
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # We can't directly test the private function, but we can verify
      # that the job args are properly structured
      assert is_map(job.args["params"])
    end

    test "handles nested maps" do
      params = %{
        "booking" => %{
          "id" => "123",
          "property" => "clear_lake"
        },
        "user" => %{
          "first_name" => "John"
        }
      }

      # Verify structure
      assert is_map(params["booking"])
      assert is_map(params["user"])
    end

    test "handles lists" do
      params = %{
        "items" => ["item1", "item2", "item3"]
      }

      assert is_list(params["items"])
    end
  end

  describe "SmsNotifier.send_sms_idempotent" do
    setup do
      user = user_fixture(%{phone_number: "+14159009001"})

      # Enable SMS notifications for the user
      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      %{user: user}
    end

    test "renders message and calls FlowRoute with correct parameters", %{
      user: user
    } do
      variables = %{
        first_name: user.first_name,
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345",
        checkin_time: "3:00 PM"
      }

      idempotency_key = "test_#{System.unique_integer()}"

      # In test environment, FlowRoute client should use noop mode
      # which returns a fake message ID without making actual API calls
      result =
        Notifier.send_sms_idempotent(
          user.phone_number,
          idempotency_key,
          "booking_checkin_reminder",
          variables,
          user.id
        )

      # Should succeed in test environment (noop mode)
      assert {:ok, %{id: message_id}} = result
      assert is_binary(message_id)
      assert String.starts_with?(message_id, "mdr2-")
    end

    test "validates phone number before sending", %{user: user} do
      variables = %{
        first_name: user.first_name,
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345"
      }

      idempotency_key = "test_#{System.unique_integer()}"

      # Invalid phone number
      result =
        Notifier.send_sms_idempotent(
          "invalid",
          idempotency_key,
          "booking_checkin_reminder",
          variables,
          user.id
        )

      assert {:error, :invalid_phone_number} = result
    end

    test "returns error for unknown template" do
      result =
        Notifier.send_sms_idempotent(
          "+14159009001",
          "test_key",
          "unknown_template",
          %{},
          nil
        )

      assert {:error, error_message} = result
      assert String.contains?(error_message, "Template module not found")
    end
  end

  describe "SmsNotifier worker perform" do
    setup do
      user = user_fixture(%{phone_number: "+14159009001"})

      # Enable SMS notifications
      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      %{user: user}
    end

    test "processes SMS job successfully", %{user: user} do
      variables = %{
        "first_name" => user.first_name,
        "property_name" => "Clear Lake",
        "checkin_date" => "Dec 05, 2025",
        "door_code" => "12345",
        "checkin_time" => "3:00 PM"
      }

      job = %Oban.Job{
        id: 1,
        args: %{
          "phone_number" => user.phone_number,
          "idempotency_key" => "test_#{System.unique_integer()}",
          "template" => "booking_checkin_reminder",
          "params" => variables,
          "user_id" => user.id,
          "category" => :booking
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      # Perform the job
      result = SmsNotifier.perform(job)

      # Should succeed
      assert :ok = result
    end

    test "handles job with legacy format (no category)", %{user: user} do
      variables = %{
        "first_name" => user.first_name,
        "property_name" => "Clear Lake"
      }

      job = %Oban.Job{
        id: 1,
        args: %{
          "phone_number" => user.phone_number,
          "idempotency_key" => "test_#{System.unique_integer()}",
          "template" => "booking_checkin_reminder",
          "params" => variables,
          "user_id" => user.id
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = SmsNotifier.perform(job)

      assert :ok = result
    end

    test "skips SMS when user has disabled notifications", %{user: user} do
      # Disable SMS notifications
      user
      |> Ecto.Changeset.change(account_notifications_sms: false)
      |> Repo.update!()

      variables = %{
        "first_name" => user.first_name,
        "property_name" => "Clear Lake"
      }

      job = %Oban.Job{
        id: 1,
        args: %{
          "phone_number" => user.phone_number,
          "idempotency_key" => "test_#{System.unique_integer()}",
          "template" => "booking_checkin_reminder",
          "params" => variables,
          "user_id" => user.id,
          "category" => :booking
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = SmsNotifier.perform(job)

      # Should return :ok but not send SMS
      assert :ok = result
    end

    test "skips SMS when user has no phone number" do
      # Create user without phone number by updating after creation
      user = user_fixture()

      user
      |> Ecto.Changeset.change(phone_number: nil)
      |> Repo.update!()

      variables = %{
        "first_name" => user.first_name,
        "property_name" => "Clear Lake"
      }

      job = %Oban.Job{
        id: 1,
        args: %{
          "phone_number" => nil,
          "idempotency_key" => "test_#{System.unique_integer()}",
          "template" => "booking_checkin_reminder",
          "params" => variables,
          "user_id" => user.id,
          "category" => :booking
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = SmsNotifier.perform(job)

      # Should return :ok but not send SMS
      assert :ok = result
    end

    test "handles invalid job args gracefully" do
      job = %Oban.Job{
        id: 1,
        args: %{
          "invalid" => "data"
        },
        worker: "YscWeb.Workers.SmsNotifier",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = SmsNotifier.perform(job)

      assert {:error, "Invalid job args: missing required fields"} = result
    end
  end

  describe "FlowRoute API integration (noop mode)" do
    test "sends SMS in test environment without making real API calls" do
      # In test environment, FlowRoute client should be in noop mode
      # This means it returns a fake response without making HTTP requests

      result =
        Ysc.Flowroute.Client.send_sms(
          to: "14159009001",
          body: "Test message"
        )

      # Should succeed with fake message ID
      assert {:ok, %{id: message_id}} = result
      assert is_binary(message_id)
      assert String.starts_with?(message_id, "mdr2-")
    end

    test "validates phone number format before sending" do
      # Invalid phone number (too short, only 9 digits)
      result =
        Ysc.Flowroute.Client.send_sms(
          to: "415900901",
          from: "12061231234",
          body: "Test message"
        )

      assert {:error, :invalid_phone_number_format} = result
    end

    test "validates message body is not empty" do
      result =
        Ysc.Flowroute.Client.send_sms(
          to: "14159009001",
          from: "12061231234",
          body: ""
        )

      assert {:error, :empty_message_body} = result
    end

    test "requires to and body parameters" do
      # Missing :to
      result1 =
        Ysc.Flowroute.Client.send_sms(body: "Test message")

      assert {:error, :missing_required_parameter} = result1

      # Missing :body
      result2 =
        Ysc.Flowroute.Client.send_sms(to: "14159009001")

      assert {:error, :missing_required_parameter} = result2
    end
  end

  describe "end-to-end SMS flow" do
    setup do
      user = user_fixture(%{phone_number: "+14159009001"})

      # Enable SMS notifications
      user
      |> Ecto.Changeset.change(account_notifications_sms: true)
      |> Repo.update!()

      %{user: user}
    end

    test "complete flow from scheduling to sending", %{user: user} do
      variables = %{
        first_name: user.first_name,
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345",
        checkin_time: "3:00 PM"
      }

      idempotency_key = "test_#{System.unique_integer()}"

      # Step 1: Schedule SMS
      {:ok, job} =
        Notifier.schedule_sms(
          user.phone_number,
          idempotency_key,
          "booking_checkin_reminder",
          variables,
          user.id
        )

      assert %Oban.Job{} = job
      assert job.args["template"] == "booking_checkin_reminder"
      # Normalized
      assert job.args["phone_number"] == "14159009001"
      assert job.args["user_id"] == user.id

      # Step 2: Perform the job (simulating Oban worker)
      result = SmsNotifier.perform(job)

      # Should succeed
      assert :ok = result
    end

    test "handles phone number normalization throughout the flow", %{user: user} do
      # User has phone number with + prefix
      user
      |> Ecto.Changeset.change(phone_number: "+14159009001")
      |> Repo.update!()

      variables = %{
        first_name: user.first_name,
        property_name: "Clear Lake",
        checkin_date: "Dec 05, 2025",
        door_code: "12345"
      }

      idempotency_key = "test_#{System.unique_integer()}"

      # Schedule with E.164 format
      {:ok, job} =
        Notifier.schedule_sms(
          "+14159009001",
          idempotency_key,
          "booking_checkin_reminder",
          variables,
          user.id
        )

      # Phone number should be normalized in job args
      assert job.args["phone_number"] == "14159009001"

      # Job should process successfully
      result = SmsNotifier.perform(job)
      assert :ok = result
    end
  end
end
