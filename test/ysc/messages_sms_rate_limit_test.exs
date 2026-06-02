defmodule Ysc.MessagesSmsRateLimitTest do
  @moduledoc false
  use Ysc.DataCase, async: false

  alias Ysc.Messages
  alias Ysc.SmsRateLimit

  defp sms_attrs(key, template \\ "booking_checkin_reminder", user_id \\ nil) do
    %{
      message_type: :sms,
      idempotency_key: key,
      message_template: template,
      params: %{},
      phone_number: "12065551234",
      rendered_message: "[YSC] Test SMS message.",
      user_id: user_id
    }
  end

  test "run_send_sms_idempotent/3 returns error when per-minute SMS rate limit is exceeded" do
    phone =
      ("1" <>
         String.pad_leading(
           Integer.to_string(System.unique_integer([:positive])),
           10,
           "0"
         ))
      |> String.slice(0, 11)

    for _ <- 1..5, do: SmsRateLimit.record_sms_send(phone)

    key6 = "sms_rl_blocked_#{System.unique_integer()}"
    parent = self()

    ref =
      :telemetry.attach(
        "ysc-messages-sms-rl-exceeded-#{key6}",
        [:ysc, :sms, :rate_limit_exceeded],
        fn _event, measurements, metadata, _ ->
          if metadata[:idempotency_key] == key6 do
            send(parent, {:sms_rl_exceeded, measurements, metadata})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)

    assert {:error, msg} =
             Messages.run_send_sms_idempotent(
               phone,
               "[YSC] Should block.",
               sms_attrs(key6)
             )

    assert is_binary(msg)

    assert_receive {:sms_rl_exceeded, %{count: 1}, meta}, 3_000
    assert meta.template == "booking_checkin_reminder"
    assert meta.recipient == phone
  end
end
