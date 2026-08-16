defmodule YscWeb.FlowrouteWebhookE2ETest do
  @moduledoc """
  End-to-end tests for the FlowRoute SMS integration.

  Unlike flowroute_webhook_controller_test.exs (which calls the controller
  functions directly to cover parsing/edge cases), these tests exercise the
  actual routes registered in router.ex via real HTTP requests, and cover
  full round trips: sending an SMS through Ysc.Messages and then receiving
  the FlowRoute webhooks for it (delivery receipts, inbound replies,
  opt-in/opt-out) exactly as FlowRoute would deliver them in production.
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.FlowrouteFixtures

  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.Sms

  setup do
    Cachex.clear(:ysc_cache)
    :ok
  end

  describe "send an SMS then receive delivery receipt webhooks" do
    test "outbound SMS is sent, then DLR webhooks progress it to delivered", %{
      conn: conn
    } do
      to = unique_user_phone()

      {:ok, %{id: message_id}} =
        Ysc.Messages.run_send_sms_idempotent(
          to,
          "Your booking is confirmed",
          %{
            message_type: :sms,
            idempotency_key: "e2e-booking-#{unique_key()}",
            message_template: "booking_confirmation"
          }
        )

      # The outbound send itself stores the SmsMessage as :sent.
      assert Sms.get_sms_message_by_provider_id(:flowroute, message_id).status ==
               :sent

      # FlowRoute first confirms the message left their platform...
      sent_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "message sent",
            to: to,
            timestamp: "2026-08-16T10:00:00Z"
          )
        )

      assert sent_conn.status == 200
      assert sent_conn.resp_body == "OK"

      # ...then later confirms carrier delivery (distinct timestamp: FlowRoute
      # DLRs are unique per provider/message/timestamp, and real DLRs for the
      # same message always carry different event timestamps).
      delivered_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "delivered",
            to: to,
            timestamp: "2026-08-16T10:00:02Z"
          )
        )

      assert delivered_conn.status == 200

      updated_message =
        Sms.get_sms_message_by_provider_id(:flowroute, message_id)

      assert updated_message.status == :delivered

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, message_id)
      assert length(receipts) == 2

      assert Enum.map(receipts, & &1.status) |> Enum.sort() ==
               [:delivered, :message_sent]

      assert Enum.all?(receipts, &(&1.sms_message_id == updated_message.id))
    end

    test "a failed DLR webhook marks the outbound message failed", %{conn: conn} do
      to = unique_user_phone()

      {:ok, %{id: message_id}} =
        Ysc.Messages.run_send_sms_idempotent(
          to,
          "Reminder: check-in opens tomorrow",
          %{
            message_type: :sms,
            idempotency_key: "e2e-fail-#{unique_key()}",
            message_template: "checkin_reminder"
          }
        )

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "failed",
            status_code: "100",
            status_code_description: "carrier rejected",
            to: to
          )
        )

      assert resp.status == 200

      updated_message =
        Sms.get_sms_message_by_provider_id(:flowroute, message_id)

      assert updated_message.status == :failed
    end

    test "MMS delivery receipt via /webhooks/flowroute/mms_dlr links and updates status",
         %{conn: conn} do
      to = unique_user_phone()

      {:ok, %{id: message_id}} =
        Ysc.Messages.run_send_sms_idempotent(
          to,
          "Here's your event photo",
          %{
            message_type: :sms,
            idempotency_key: "e2e-mms-#{unique_key()}",
            message_template: "event_photo"
          }
        )

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/mms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "delivered",
            to: to
          )
        )

      assert resp.status == 200

      updated_message =
        Sms.get_sms_message_by_provider_id(:flowroute, message_id)

      assert updated_message.status == :delivered
    end
  end

  describe "receive inbound SMS/MMS webhooks" do
    test "inbound SMS via /webhooks/flowroute/sms is stored and matched to the user",
         %{conn: conn} do
      user = user_fixture(%{phone_number: unique_user_phone()})
      from = String.trim_leading(user.phone_number, "+")
      message_id = "mdr2-e2e-inbound-#{unique_key()}"

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms",
          inbound_message_payload(
            message_id: message_id,
            from: from,
            to: "12061231234",
            body: "Thanks, see you there!"
          )
        )

      assert resp.status == 200
      assert resp.resp_body == "OK"

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, message_id)

      assert sms_received.user_id == user.id
      assert sms_received.body == "Thanks, see you there!"
      assert sms_received.is_mms == false
    end

    test "inbound MMS via /webhooks/flowroute/mms is stored with is_mms true",
         %{
           conn: conn
         } do
      message_id = "mdr2-e2e-mms-#{unique_key()}"

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/mms",
          inbound_message_payload(
            message_id: message_id,
            from: "14155551234",
            to: "12061231234",
            body: "check out this pic",
            is_mms: true,
            media_urls: ["https://media.flowroute.com/example.jpg"]
          )
        )

      assert resp.status == 200

      sms_received = Sms.get_sms_received_by_provider_id(:flowroute, message_id)

      assert sms_received.is_mms == true
    end

    test "STOP via the real route opts the user out and sends a real opt-out SMS reply",
         %{conn: conn} do
      user = user_fixture(%{phone_number: unique_user_phone()})

      user
      |> Ecto.Changeset.change(
        account_notifications_sms: true,
        event_notifications_sms: true
      )
      |> Repo.update!()

      from = String.trim_leading(user.phone_number, "+")

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms",
          inbound_message_payload(from: from, to: "12061231234", body: "STOP")
        )

      assert resp.status == 200

      updated_user = Repo.get!(User, user.id)
      refute updated_user.account_notifications_sms
      refute updated_user.event_notifications_sms

      reply = latest_sms_message_to(user.phone_number)
      assert reply != nil
      assert reply.body =~ "unsubscribed"
    end

    test "START via the real route opts the user back in and sends a confirmation reply",
         %{conn: conn} do
      user = user_fixture(%{phone_number: unique_user_phone()})

      user
      |> Ecto.Changeset.change(
        account_notifications_sms: false,
        event_notifications_sms: false
      )
      |> Repo.update!()

      from = String.trim_leading(user.phone_number, "+")

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms",
          inbound_message_payload(from: from, to: "12061231234", body: "START")
        )

      assert resp.status == 200

      updated_user = Repo.get!(User, user.id)
      assert updated_user.account_notifications_sms
      assert updated_user.event_notifications_sms

      reply = latest_sms_message_to(user.phone_number)
      assert reply != nil
      assert reply.body =~ "subscribed"
    end

    test "HELP via the real route sends a help SMS reply", %{conn: conn} do
      phone = unique_user_phone()
      from = String.trim_leading(phone, "+")

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/sms",
          inbound_message_payload(from: from, to: "12061231234", body: "HELP")
        )

      assert resp.status == 200

      reply = latest_sms_message_to(phone)
      assert reply != nil
      assert reply.body =~ "info@ysc.org"
    end

    test "malformed payload posted to the real inbound route returns 400", %{
      conn: conn
    } do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/flowroute/sms", %{"unexpected" => "shape"})

      assert resp.status == 400
      assert resp.resp_body == "Invalid payload"
    end

    test "malformed payload posted to the real DLR route returns 400", %{
      conn: conn
    } do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/flowroute/sms_dlr", %{"unexpected" => "shape"})

      assert resp.status == 400
      assert resp.resp_body == "Invalid payload"
    end
  end

  defp unique_key, do: System.unique_integer([:positive, :monotonic])

  defp latest_sms_message_to(to) do
    Repo.one(
      from m in Ysc.Sms.SmsMessage,
        where: m.to == ^to,
        order_by: [desc: m.inserted_at],
        limit: 1
    )
  end
end
