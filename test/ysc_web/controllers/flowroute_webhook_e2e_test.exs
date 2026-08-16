defmodule YscWeb.FlowrouteWebhookE2ETest do
  @moduledoc """
  End-to-end tests for the FlowRoute SMS integration.

  Unlike flowroute_webhook_controller_test.exs (which calls the controller
  functions directly to cover parsing/edge cases), these tests exercise the
  actual routes registered in router.ex via real HTTP requests — including
  the webhook token auth plug — and cover full round trips: sending an SMS
  through Ysc.Messages and then receiving the FlowRoute webhooks for it
  (delivery receipts, inbound replies, opt-in/opt-out) exactly as FlowRoute
  would deliver them in production.
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures
  import Ysc.FlowrouteFixtures

  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias Ysc.Sms

  @token "test_flowroute_webhook_token"

  setup do
    Cachex.clear(:ysc_cache)

    # config/runtime.exs re-declares :ysc, :flowroute at boot (even under
    # `mix test`) from FLOWROUTE_* env vars, which clobbers whatever
    # config/test.exs set for keys it doesn't have locally — so the webhook
    # token is set here directly rather than relied on from config files.
    previous_config = Application.get_env(:ysc, :flowroute, [])

    Application.put_env(
      :ysc,
      :flowroute,
      Keyword.put(previous_config, :webhook_token, @token)
    )

    on_exit(fn -> Application.put_env(:ysc, :flowroute, previous_config) end)

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
        |> post_webhook(
          "sms_dlr",
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
        |> post_webhook(
          "sms_dlr",
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
        |> post_webhook(
          "sms_dlr",
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

    test "MMS delivery receipt via /webhooks/flowroute/:token/mms_dlr links and updates status",
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
        |> post_webhook(
          "mms_dlr",
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

    test "a duplicate DLR (same message_id + timestamp) is acknowledged without creating a second receipt",
         %{conn: conn} do
      to = unique_user_phone()

      {:ok, %{id: message_id}} =
        Ysc.Messages.run_send_sms_idempotent(
          to,
          "Your ticket is ready",
          %{
            message_type: :sms,
            idempotency_key: "e2e-dup-dlr-#{unique_key()}",
            message_template: "ticket_ready"
          }
        )

      payload =
        delivery_receipt_payload(
          message_id: message_id,
          status: "delivered",
          to: to,
          timestamp: "2026-08-16T10:00:00Z"
        )

      first = conn |> post_webhook("sms_dlr", payload)
      assert first.status == 200

      # Same webhook delivered again (FlowRoute retry, or duplicate delivery).
      second = build_conn() |> post_webhook("sms_dlr", payload)

      # Acknowledged, not treated as a failure that would make FlowRoute retry.
      assert second.status == 200
      assert second.resp_body == "OK"

      receipts = Sms.list_delivery_receipts_for_message(:flowroute, message_id)
      assert length(receipts) == 1
    end

    test "an out-of-order DLR does not regress an already-delivered message status",
         %{conn: conn} do
      to = unique_user_phone()

      {:ok, %{id: message_id}} =
        Ysc.Messages.run_send_sms_idempotent(
          to,
          "Your registration is complete",
          %{
            message_type: :sms,
            idempotency_key: "e2e-out-of-order-#{unique_key()}",
            message_template: "registration_complete"
          }
        )

      # "delivered" DLR arrives first...
      delivered_conn =
        conn
        |> post_webhook(
          "sms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "delivered",
            to: to,
            timestamp: "2026-08-16T10:00:05Z"
          )
        )

      assert delivered_conn.status == 200

      assert Sms.get_sms_message_by_provider_id(:flowroute, message_id).status ==
               :delivered

      # ...then an earlier-stage "message sent" DLR shows up late (FlowRoute
      # gives no ordering guarantee). It must not downgrade the terminal
      # :delivered status back to :sent.
      late_conn =
        build_conn()
        |> post_webhook(
          "sms_dlr",
          delivery_receipt_payload(
            message_id: message_id,
            status: "message sent",
            to: to,
            timestamp: "2026-08-16T10:00:01Z"
          )
        )

      assert late_conn.status == 200

      assert Sms.get_sms_message_by_provider_id(:flowroute, message_id).status ==
               :delivered
    end
  end

  describe "receive inbound SMS/MMS webhooks" do
    test "inbound SMS via /webhooks/flowroute/:token/sms is stored and matched to the user",
         %{conn: conn} do
      user = user_fixture(%{phone_number: unique_user_phone()})
      from = String.trim_leading(user.phone_number, "+")
      message_id = "mdr2-e2e-inbound-#{unique_key()}"

      resp =
        conn
        |> post_webhook(
          "sms",
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

    test "inbound MMS via /webhooks/flowroute/:token/mms is stored with is_mms true",
         %{
           conn: conn
         } do
      message_id = "mdr2-e2e-mms-#{unique_key()}"

      resp =
        conn
        |> post_webhook(
          "mms",
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

    test "a duplicate inbound SMS webhook is acknowledged without reprocessing",
         %{conn: conn} do
      message_id = "mdr2-e2e-dup-inbound-#{unique_key()}"

      payload =
        inbound_message_payload(
          message_id: message_id,
          from: "14155551234",
          to: "12061231234",
          body: "hello again"
        )

      first = conn |> post_webhook("sms", payload)
      assert first.status == 200

      second = build_conn() |> post_webhook("sms", payload)

      assert second.status == 200
      assert second.resp_body == "OK"

      assert Sms.get_sms_received_by_provider_id(:flowroute, message_id) != nil
    end

    test "START from an unknown number still returns 200", %{conn: conn} do
      resp =
        conn
        |> post_webhook(
          "sms",
          inbound_message_payload(
            from: "19998887777",
            to: "12061231234",
            body: "START"
          )
        )

      assert resp.status == 200
      assert resp.resp_body == "OK"
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
        |> post_webhook(
          "sms",
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
        |> post_webhook(
          "sms",
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
        |> post_webhook(
          "sms",
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
      resp = conn |> post_webhook("sms", %{"unexpected" => "shape"})

      assert resp.status == 400
      assert resp.resp_body == "Invalid payload"
    end

    test "malformed payload posted to the real DLR route returns 400", %{
      conn: conn
    } do
      resp = conn |> post_webhook("sms_dlr", %{"unexpected" => "shape"})

      assert resp.status == 400
      assert resp.resp_body == "Invalid payload"
    end
  end

  describe "webhook token auth" do
    test "a request with an empty token segment does not match the route", %{
      conn: conn
    } do
      # `//` collapses to an empty path segment, which Phoenix's router
      # never matches against `:token` (dynamic segments require at least
      # one character) — so this 404s before verify_webhook_token ever runs,
      # same as omitting the segment entirely.
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/flowroute//sms", %{})

      assert resp.status == 404
    end

    test "a request with a wrong token is rejected with 401 and not processed",
         %{conn: conn} do
      message_id = "mdr2-e2e-badtoken-#{unique_key()}"

      payload =
        inbound_message_payload(
          message_id: message_id,
          from: "14155551234",
          to: "12061231234",
          body: "should not be stored"
        )

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/flowroute/wrong-token/sms", payload)

      assert resp.status == 401

      assert Sms.get_sms_received_by_provider_id(:flowroute, message_id) == nil
    end

    test "a request with no token segment does not match the route", %{
      conn: conn
    } do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/flowroute/sms", %{})

      assert resp.status == 404
    end

    test "DLR route also rejects a wrong token with 401", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/webhooks/flowroute/wrong-token/sms_dlr",
          delivery_receipt_payload(
            message_id: "mdr2-irrelevant",
            status: "delivered"
          )
        )

      assert resp.status == 401
    end

    test "a request is rejected with 401 when no token is configured on the server (fails closed)",
         %{conn: conn} do
      config_without_token =
        Application.get_env(:ysc, :flowroute, [])
        |> Keyword.delete(:webhook_token)

      Application.put_env(:ysc, :flowroute, config_without_token)

      message_id = "mdr2-e2e-notoken-#{unique_key()}"

      resp =
        conn
        |> post_webhook(
          "sms",
          inbound_message_payload(
            message_id: message_id,
            from: "14155551234",
            to: "12061231234",
            body: "should not be stored"
          )
        )

      assert resp.status == 401
      assert Sms.get_sms_received_by_provider_id(:flowroute, message_id) == nil
    end

    test "rejects requests when webhook token is configured as empty string",
         %{conn: conn} do
      config_without_token =
        Application.get_env(:ysc, :flowroute, [])
        |> Keyword.put(:webhook_token, "")

      Application.put_env(:ysc, :flowroute, config_without_token)

      message_id = "mdr2-e2e-empty-token-#{unique_key()}"

      resp =
        conn
        |> post_webhook(
          "sms",
          inbound_message_payload(
            message_id: message_id,
            from: "14155551234",
            to: "12061231234",
            body: "should not be stored"
          )
        )

      assert resp.status == 401
      assert Sms.get_sms_received_by_provider_id(:flowroute, message_id) == nil
    end
  end

  describe "webhook rate limiting" do
    @rate_limit_ip {198, 51, 100, 42}

    setup do
      Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 2)

      on_exit(fn ->
        Application.put_env(:ysc, Ysc.FlowrouteWebhookRateLimit, ip_limit: 60)
      end)

      :ok
    end

    test "returns 429 when the same IP exceeds the webhook rate limit", %{conn: conn} do
      conn = Map.put(conn, :remote_ip, @rate_limit_ip)

      assert conn
             |> post_webhook("sms", rate_limit_probe_payload(1))
             |> Map.get(:status) == 200

      assert build_conn()
             |> Map.put(:remote_ip, @rate_limit_ip)
             |> post_webhook("sms", rate_limit_probe_payload(2))
             |> Map.get(:status) ==
               200

      resp =
        build_conn()
        |> Map.put(:remote_ip, @rate_limit_ip)
        |> post_webhook("sms", rate_limit_probe_payload(3))

      assert resp.status == 429
      [retry_after] = get_resp_header(resp, "retry-after")
      assert String.to_integer(retry_after) > 0
      assert resp.resp_body == "Too many requests"
    end
  end

  defp post_webhook(conn, kind, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/webhooks/flowroute/#{@token}/#{kind}", payload)
  end

  defp rate_limit_probe_payload(n) do
    inbound_message_payload(
      message_id: "mdr2-e2e-ratelimit-#{n}-#{unique_key()}",
      from: "14155551234",
      to: "12061231234",
      body: "rate limit probe #{n}"
    )
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
