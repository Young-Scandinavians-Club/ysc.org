defmodule Ysc.SmsTest do
  @moduledoc """
  Tests for the Ysc.Sms context module.

  Tests CRUD operations for SMS messages, received messages, and delivery receipts.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Sms
  alias Ysc.Sms.{SmsMessage, SmsReceived, SmsDeliveryReceipt}

  describe "create_sms_message/1" do
    test "creates a valid SMS message" do
      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-test-123",
        to: "14155551234",
        from: "12061231234",
        body: "Test message",
        status: :sent
      }

      assert {:ok, %SmsMessage{} = sms_message} = Sms.create_sms_message(attrs)
      assert sms_message.provider == :flowroute
      assert sms_message.provider_message_id == "mdr2-test-123"
      assert sms_message.to == "14155551234"
      assert sms_message.from == "12061231234"
      assert sms_message.body == "Test message"
      assert sms_message.status == :sent
    end

    test "creates SMS message with user association" do
      user = user_fixture()

      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-user-123",
        to: "14155551234",
        from: "12061231234",
        body: "Test message",
        user_id: user.id
      }

      assert {:ok, %SmsMessage{} = sms_message} = Sms.create_sms_message(attrs)
      assert sms_message.user_id == user.id
    end

    test "creates MMS message with media URLs" do
      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-mms-123",
        to: "14155551234",
        from: "12061231234",
        body: "MMS message",
        is_mms: true,
        media_urls: [
          "https://example.com/image1.jpg",
          "https://example.com/image2.jpg"
        ]
      }

      assert {:ok, %SmsMessage{} = sms_message} = Sms.create_sms_message(attrs)
      assert sms_message.is_mms == true
      assert length(sms_message.media_urls) == 2
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Sms.create_sms_message(%{})
      assert "can't be blank" in errors_on(changeset).provider
      assert "can't be blank" in errors_on(changeset).provider_message_id
      assert "can't be blank" in errors_on(changeset).to
      assert "can't be blank" in errors_on(changeset).from
      assert "can't be blank" in errors_on(changeset).body
    end

    test "enforces unique constraint on provider + provider_message_id" do
      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-unique-123",
        to: "14155551234",
        from: "12061231234",
        body: "Test message"
      }

      assert {:ok, _} = Sms.create_sms_message(attrs)
      assert {:error, changeset} = Sms.create_sms_message(attrs)
      # The unique constraint might report on provider or provider_message_id
      errors = errors_on(changeset)

      assert Map.has_key?(errors, :provider) or
               Map.has_key?(errors, :provider_message_id)
    end
  end

  describe "get_sms_message_by_provider_id/2" do
    test "returns SMS message when found" do
      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-get-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message"
        })

      found = Sms.get_sms_message_by_provider_id(:flowroute, "mdr2-get-123")
      assert found.id == sms_message.id
    end

    test "returns nil when not found" do
      assert Sms.get_sms_message_by_provider_id(:flowroute, "nonexistent") ==
               nil
    end
  end

  describe "update_sms_message_status/2" do
    test "updates SMS message status" do
      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-update-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      assert {:ok, updated} =
               Sms.update_sms_message_status(sms_message, :delivered)

      assert updated.status == :delivered
    end

    test "updates status to failed" do
      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-fail-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message",
          status: :sent
        })

      assert {:ok, updated} =
               Sms.update_sms_message_status(sms_message, :failed)

      assert updated.status == :failed
    end
  end

  describe "create_sms_received/1" do
    test "creates a valid inbound SMS record" do
      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-inbound-123",
        from: "14155551234",
        to: "12061231234",
        body: "Incoming message",
        direction: :inbound
      }

      assert {:ok, %SmsReceived{} = sms_received} =
               Sms.create_sms_received(attrs)

      assert sms_received.provider == :flowroute
      assert sms_received.from == "14155551234"
      assert sms_received.to == "12061231234"
      assert sms_received.body == "Incoming message"
      assert sms_received.direction == :inbound
    end

    test "creates inbound SMS with timestamp" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-timestamp-123",
        from: "14155551234",
        to: "12061231234",
        provider_timestamp: timestamp
      }

      assert {:ok, %SmsReceived{} = sms_received} =
               Sms.create_sms_received(attrs)

      assert sms_received.provider_timestamp == timestamp
    end

    test "stores raw payload" do
      raw_payload = %{"data" => %{"id" => "test", "attributes" => %{}}}

      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-raw-123",
        from: "14155551234",
        to: "12061231234",
        raw_payload: raw_payload
      }

      assert {:ok, %SmsReceived{} = sms_received} =
               Sms.create_sms_received(attrs)

      assert sms_received.raw_payload == raw_payload
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Sms.create_sms_received(%{})
      assert "can't be blank" in errors_on(changeset).provider
      assert "can't be blank" in errors_on(changeset).provider_message_id
      assert "can't be blank" in errors_on(changeset).from
      assert "can't be blank" in errors_on(changeset).to
    end
  end

  describe "match_sms_received_to_user/1" do
    test "matches SMS to user by phone number" do
      user = user_fixture(%{phone_number: "+14155551234"})

      {:ok, sms_received} =
        Sms.create_sms_received(%{
          provider: :flowroute,
          provider_message_id: "mdr2-match-123",
          from: "14155551234",
          to: "12061231234"
        })

      assert {:ok, matched} = Sms.match_sms_received_to_user(sms_received)
      assert matched.user_id == user.id
    end

    test "returns unchanged when no user matches" do
      {:ok, sms_received} =
        Sms.create_sms_received(%{
          provider: :flowroute,
          provider_message_id: "mdr2-no-match-123",
          from: "19995551234",
          to: "12061231234"
        })

      assert {:ok, unchanged} = Sms.match_sms_received_to_user(sms_received)
      assert unchanged.user_id == nil
    end

    test "handles E.164 format phone number matching" do
      user = user_fixture(%{phone_number: "+14155551234"})

      {:ok, sms_received} =
        Sms.create_sms_received(%{
          provider: :flowroute,
          provider_message_id: "mdr2-e164-123",
          from: "+14155551234",
          to: "12061231234"
        })

      assert {:ok, matched} = Sms.match_sms_received_to_user(sms_received)
      assert matched.user_id == user.id
    end
  end

  describe "create_delivery_receipt/1" do
    test "creates a valid delivery receipt" do
      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-dlr-123",
        status: :delivered,
        status_code: "0",
        status_code_description: "Message delivered"
      }

      assert {:ok, %SmsDeliveryReceipt{} = dlr} =
               Sms.create_delivery_receipt(attrs)

      assert dlr.provider == :flowroute
      assert dlr.status == :delivered
      assert dlr.status_code == "0"
    end

    test "creates delivery receipt with timestamp" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-dlr-ts-123",
        status: :delivered,
        provider_timestamp: timestamp
      }

      assert {:ok, %SmsDeliveryReceipt{} = dlr} =
               Sms.create_delivery_receipt(attrs)

      assert dlr.provider_timestamp == timestamp
    end

    test "stores raw payload" do
      raw_payload = %{"data" => %{"id" => "test"}}

      attrs = %{
        provider: :flowroute,
        provider_message_id: "mdr2-dlr-raw-123",
        status: :delivered,
        raw_payload: raw_payload
      }

      assert {:ok, %SmsDeliveryReceipt{} = dlr} =
               Sms.create_delivery_receipt(attrs)

      assert dlr.raw_payload == raw_payload
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Sms.create_delivery_receipt(%{})
      assert "can't be blank" in errors_on(changeset).provider
      assert "can't be blank" in errors_on(changeset).provider_message_id
      assert "can't be blank" in errors_on(changeset).status
    end
  end

  describe "list_delivery_receipts_for_message/2" do
    test "returns delivery receipts for a message" do
      {:ok, _dlr1} =
        Sms.create_delivery_receipt(%{
          provider: :flowroute,
          provider_message_id: "mdr2-list-123",
          status: :message_sent,
          provider_timestamp: ~U[2025-12-05 10:00:00Z]
        })

      {:ok, _dlr2} =
        Sms.create_delivery_receipt(%{
          provider: :flowroute,
          provider_message_id: "mdr2-list-123",
          status: :delivered,
          provider_timestamp: ~U[2025-12-05 10:01:00Z]
        })

      receipts =
        Sms.list_delivery_receipts_for_message(:flowroute, "mdr2-list-123")

      assert length(receipts) == 2
      # Ordered by timestamp descending
      assert hd(receipts).status == :delivered
    end

    test "returns empty list when no receipts found" do
      receipts =
        Sms.list_delivery_receipts_for_message(:flowroute, "nonexistent")

      assert receipts == []
    end
  end

  describe "link_delivery_receipt_to_message/1" do
    test "links delivery receipt to SMS message" do
      {:ok, sms_message} =
        Sms.create_sms_message(%{
          provider: :flowroute,
          provider_message_id: "mdr2-link-test-123",
          to: "14155551234",
          from: "12061231234",
          body: "Test message"
        })

      {:ok, dlr} =
        Sms.create_delivery_receipt(%{
          provider: :flowroute,
          provider_message_id: "mdr2-link-test-123",
          status: :delivered
        })

      assert {:ok, linked} = Sms.link_delivery_receipt_to_message(dlr)
      assert linked.sms_message_id == sms_message.id
    end

    test "returns unchanged when no matching SMS message found" do
      {:ok, dlr} =
        Sms.create_delivery_receipt(%{
          provider: :flowroute,
          provider_message_id: "mdr2-no-link-123",
          status: :delivered
        })

      assert {:ok, unchanged} = Sms.link_delivery_receipt_to_message(dlr)
      assert unchanged.sms_message_id == nil
    end
  end
end
