defmodule YscWeb.PrintfulWebhookController do
  @moduledoc """
  Receives Printful webhooks (order and shipment events).

  Printful's v1 webhooks carry no signature we can verify, so the callback URL
  embeds a secret (`PRINTFUL_WEBHOOK_SECRET`) that is checked here, behind a
  per-IP rate limit. A valid event is enqueued for
  `YscWeb.Workers.MerchPrintfulEvent` and acknowledged straight away.
  """
  use YscWeb, :controller

  require Ysc.Logging

  alias YscWeb.Workers.MerchPrintfulEvent

  plug :verify_token

  def handle(conn, %{"type" => type, "data" => data})
      when is_binary(type) and is_map(data) do
    case %{"type" => type, "data" => data}
         |> MerchPrintfulEvent.new()
         |> Oban.insert() do
      {:ok, _job} ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Ysc.Logging.error("Could not enqueue Printful webhook",
          extra: %{type: type, reason: inspect(reason)}
        )

        # A non-2xx makes Printful retry.
        send_resp(conn, 503, "Unavailable")
    end
  end

  def handle(conn, _params) do
    send_resp(conn, 400, "Invalid payload")
  end

  defp verify_token(conn, _opts) do
    configured = Application.get_env(:ysc, :printful, [])[:webhook_secret]
    provided = conn.params["token"]

    cond do
      not (is_binary(configured) and configured != "") ->
        Ysc.Logging.warning("Printful webhook secret is not configured")
        conn |> send_resp(401, "Unauthorized") |> halt()

      is_binary(provided) and Plug.Crypto.secure_compare(configured, provided) ->
        conn

      true ->
        Ysc.Logging.warning("Printful webhook token mismatch")
        conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end
end
