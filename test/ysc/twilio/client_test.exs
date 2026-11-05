defmodule Ysc.Twilio.ClientTest do
  use Ysc.DataCase, async: false

  alias Ysc.Sms.SmsMessage
  alias Ysc.Twilio.Client

  setup do
    on_exit(fn ->
      Application.delete_env(:ysc, :twilio_req_options)
      Application.put_env(:ysc, :twilio_force_noop, true)
    end)
  end

  describe "send_sms/1 in no-op mode" do
    test "returns a fake Twilio SID and stores the message" do
      assert {:ok, %{id: "SM" <> _ = sid}} =
               Client.send_sms(to: "+46701234567", body: "Your code is 123456")

      message = Repo.get_by!(SmsMessage, provider_message_id: sid)
      assert message.provider == :twilio
      assert message.to == "+46701234567"
      assert message.from == "YSC"
    end

    test "adds the + to digits-only numbers" do
      assert {:ok, %{id: sid}} =
               Client.send_sms(to: "46701234567", body: "Hi")

      assert Repo.get_by!(SmsMessage, provider_message_id: sid).to ==
               "+46701234567"
    end

    test "rejects malformed numbers, empty bodies and missing params" do
      assert {:error, :invalid_phone_number_format} =
               Client.send_sms(to: "+0123", body: "Hi")

      assert {:error, :invalid_phone_number_format} =
               Client.send_sms(to: "abc", body: "Hi")

      assert {:error, :empty_message_body} =
               Client.send_sms(to: "+46701234567", body: "")

      assert {:error, :missing_required_parameter} =
               Client.send_sms(body: "Hi")
    end
  end

  describe "send_sms/1 against the Twilio API" do
    setup do
      Application.put_env(:ysc, :twilio_force_noop, false)
      System.put_env("TWILIO_FORCE_ENABLE", "true")
      on_exit(fn -> System.delete_env("TWILIO_FORCE_ENABLE") end)

      Application.put_env(:ysc, :twilio_req_options,
        plug: {Req.Test, __MODULE__}
      )

      :ok
    end

    test "posts a form-encoded message with basic auth and stores it" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(raw)

        assert conn.method == "POST"

        assert conn.request_path ==
                 "/2010-04-01/Accounts/ACtest00000000000000000000000000/Messages.json"

        assert params == %{
                 "To" => "+46701234567",
                 "Body" => "Your code is 123456",
                 "From" => "YSC"
               }

        assert [
                 "Basic " <> creds
               ] = Plug.Conn.get_req_header(conn, "authorization")

        assert Base.decode64!(creds) ==
                 "ACtest00000000000000000000000000:test_twilio_auth_token"

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"sid" => "SMabc123", "status" => "queued"})
      end)

      assert {:ok, %{id: "SMabc123"}} =
               Client.send_sms(to: "46701234567", body: "Your code is 123456")

      assert %SmsMessage{provider: :twilio, to: "+46701234567"} =
               Repo.get_by!(SmsMessage, provider_message_id: "SMabc123")
    end

    test "prefers the messaging service when configured" do
      original = Application.get_env(:ysc, :twilio)

      Application.put_env(
        :ysc,
        :twilio,
        Keyword.put(original, :messaging_service_sid, "MG123")
      )

      on_exit(fn -> Application.put_env(:ysc, :twilio, original) end)

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(raw)
        assert params["MessagingServiceSid"] == "MG123"
        refute Map.has_key?(params, "From")

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SMms1"})
      end)

      assert {:ok, %{id: "SMms1"}} =
               Client.send_sms(to: "+4741234567", body: "Hi")
    end

    test "surfaces the Twilio error message on a 4xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "code" => 21211,
          "message" => "The 'To' number is not a valid phone number.",
          "status" => 400
        })
      end)

      assert {:error, "The 'To' number is not a valid phone number."} =
               Client.send_sms(to: "+46701234567", body: "Hi")

      assert Repo.aggregate(SmsMessage, :count) == 0
    end

    test "returns :request_failed on a transport error" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :request_failed} =
               Client.send_sms(to: "+46701234567", body: "Hi")
    end

    test "errors when credentials are not configured" do
      original = Application.get_env(:ysc, :twilio)
      Application.put_env(:ysc, :twilio, sender: "YSC")
      on_exit(fn -> Application.put_env(:ysc, :twilio, original) end)

      assert {:error, :twilio_account_sid_not_configured} =
               Client.send_sms(to: "+46701234567", body: "Hi")
    end

    test "errors when no sender is configured" do
      original = Application.get_env(:ysc, :twilio)
      Application.put_env(:ysc, :twilio, Keyword.delete(original, :sender))
      on_exit(fn -> Application.put_env(:ysc, :twilio, original) end)

      assert {:error, :twilio_sender_not_configured} =
               Client.send_sms(to: "+46701234567", body: "Hi")
    end
  end
end
