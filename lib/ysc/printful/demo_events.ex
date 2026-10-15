defmodule Ysc.Printful.DemoEvents do
  @moduledoc """
  Plays the part of Printful's webhooks in demo mode: moves a demo order
  through production, shipping, delivery (or trouble) and delivers the matching
  event through the same Oban worker as a real webhook, so the whole path (order
  status, shipments, emails, SMS, board alerts) is exercised for real.

  Used by the dev-only `/dev/merch` page. Only meaningful with
  `Ysc.Printful.DemoClient`.
  """
  alias Ysc.Printful.DemoClient
  alias YscWeb.Workers.MerchPrintfulEvent

  @actions [:production, :ship, :deliver, :return, :fail, :cancel, :hold]

  def actions, do: @actions

  @doc """
  Applies `action` to the demo order `printful_order_id` and enqueues the
  event Printful would send. Returns `{:ok, event_type}`.
  """
  @spec trigger(integer(), atom()) :: {:ok, String.t()} | {:error, term()}
  def trigger(printful_order_id, action) when action in @actions do
    with {:ok, order} <-
           DemoClient.update_order(printful_order_id, &apply_action(&1, action)),
         {type, data} = event(order, action),
         {:ok, _job} <-
           %{"type" => type, "data" => data}
           |> MerchPrintfulEvent.new()
           |> Oban.insert() do
      {:ok, type}
    end
  end

  # How each action changes the demo order's own record.
  defp apply_action(order, :production),
    do: Map.put(order, "status", "inprocess")

  defp apply_action(order, :ship) do
    n = System.unique_integer([:positive, :monotonic])

    shipment = %{
      "id" => 700_000 + n,
      "carrier" => "USPS",
      "service" => "Priority Mail",
      "tracking_number" =>
        "9400DEMO#{String.pad_leading(Integer.to_string(n), 12, "0")}",
      "tracking_url" =>
        "https://tools.usps.com/go/TrackConfirmAction?tLabels=DEMO#{n}",
      "reshipment" => false,
      "shipped_at" => System.os_time(:second)
    }

    order
    |> Map.put("status", "fulfilled")
    |> Map.update("shipments", [shipment], &(&1 ++ [shipment]))
  end

  defp apply_action(order, :deliver), do: Map.put(order, "status", "fulfilled")
  defp apply_action(order, :return), do: order

  defp apply_action(order, :fail),
    do:
      order
      |> Map.put("status", "failed")
      |> Map.put("error", "Demo: out of stock")

  defp apply_action(order, :cancel), do: Map.put(order, "status", "canceled")
  defp apply_action(order, :hold), do: Map.put(order, "status", "onhold")

  # The webhook Printful would send for it.
  defp event(order, :production), do: {"order_updated", %{"order" => order}}

  defp event(order, :ship),
    do:
      {"package_shipped",
       %{"order" => order, "shipment" => List.last(order["shipments"])}}

  defp event(order, :deliver),
    do:
      {"package_delivered",
       %{"order" => order, "shipment" => List.last(order["shipments"] || [])}}

  defp event(order, :return),
    do:
      {"package_returned",
       %{"order" => order, "shipment" => List.last(order["shipments"] || [])}}

  defp event(order, :fail),
    do: {"order_failed", %{"order" => order, "reason" => order["error"]}}

  defp event(order, :cancel), do: {"order_canceled", %{"order" => order}}

  defp event(order, :hold),
    do:
      {"order_put_hold",
       %{"order" => order, "reason" => "Demo: payment method declined"}}
end
