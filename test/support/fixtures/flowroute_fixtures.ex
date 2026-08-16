defmodule Ysc.FlowrouteFixtures do
  @moduledoc """
  Realistic FlowRoute webhook payloads (JSON:API shape, matching what
  FlowRoute actually POSTs to Messaging Callback Service URLs), for use in
  end-to-end webhook tests.

  See https://developer.flowroute.com/api/messages/v2.1/receive-an-sms/,
  .../receive-an-mms/, and .../receive-a-dlr/.
  """

  @doc """
  Builds an inbound SMS/MMS webhook payload, as delivered to the
  `/webhooks/flowroute/sms` and `/webhooks/flowroute/mms` callback URLs.
  """
  def inbound_message_payload(opts \\ []) do
    message_id = Keyword.get(opts, :message_id, unique_message_id())
    is_mms = Keyword.get(opts, :is_mms, false)

    %{
      "data" => %{
        "id" => message_id,
        "type" => "message",
        "attributes" => %{
          "from" => Keyword.fetch!(opts, :from),
          "to" => Keyword.fetch!(opts, :to),
          "body" => Keyword.fetch!(opts, :body),
          "direction" => "inbound",
          "message_type" => if(is_mms, do: "mms", else: "sms"),
          "message_encoding" => 0,
          "is_mms" => is_mms,
          "media_urls" => Keyword.get(opts, :media_urls, []),
          "timestamp" => Keyword.get(opts, :timestamp, iso_now())
        }
      }
    }
  end

  @doc """
  Builds a delivery receipt (DLR) webhook payload, as delivered to the
  `/webhooks/flowroute/sms_dlr` and `/webhooks/flowroute/mms_dlr` callback
  URLs.
  """
  def delivery_receipt_payload(opts) do
    message_id = Keyword.fetch!(opts, :message_id)
    status = Keyword.get(opts, :status, "delivered")

    %{
      "data" => %{
        "id" => message_id,
        "type" => "message",
        "attributes" => %{
          "to" => Keyword.get(opts, :to, "+14155551234"),
          "from" => Keyword.get(opts, :from, "+12061231234"),
          "body" => Keyword.get(opts, :body),
          "status" => status,
          "status_code" => Keyword.get(opts, :status_code, "0"),
          "status_code_description" =>
            Keyword.get(
              opts,
              :status_code_description,
              default_status_description(status)
            ),
          "timestamp" => Keyword.get(opts, :timestamp, iso_now())
        }
      }
    }
  end

  defp default_status_description("delivered"), do: "message delivered"
  defp default_status_description("failed"), do: "carrier rejected"
  defp default_status_description(_), do: nil

  defp unique_message_id do
    "mdr2-" <>
      (System.unique_integer([:positive, :monotonic]) |> Integer.to_string())
  end

  defp iso_now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
