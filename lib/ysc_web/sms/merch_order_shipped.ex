defmodule YscWeb.Sms.MerchOrderShipped do
  @moduledoc """
  SMS telling a member their merch order shipped, with the tracking link when
  there is one.
  """
  alias YscWeb.Sms.Template

  # Keys required in priv/dev/notification_preview_samples.exs (mix lint_notification_samples).
  @preview_keys [:first_name, :reference_id, :carrier, :tracking_url]

  def preview_keys, do: @preview_keys

  def get_template_name, do: "merch_order_shipped"

  def render(variables) do
    first_name = Template.optional_first_name(variables)
    reference_id = Map.get(variables, :reference_id, "")
    carrier = Map.get(variables, :carrier)
    tracking_url = Map.get(variables, :tracking_url)
    estimate = Map.get(variables, :delivery_estimate)

    via = if carrier in [nil, ""], do: "", else: " via #{carrier}"

    track =
      if tracking_url in [nil, ""], do: "", else: " Track it: #{tracking_url}"

    eta =
      if estimate in [nil, ""], do: "", else: " Est. delivery #{estimate}."

    "Your YSC order #{reference_id} has shipped#{via}.#{eta}#{track}"
    |> Template.greeting(first_name)
    |> Template.format()
  end

  def prepare_sms_data(order, shipment, first_name \\ nil) do
    %{
      first_name: first_name,
      reference_id: order.reference_id,
      carrier: shipment.carrier,
      tracking_url: Ysc.Merch.Shipment.safe_tracking_url(shipment.tracking_url),
      delivery_estimate: Ysc.Merch.Shipping.delivery_estimate(order)
    }
  end
end
