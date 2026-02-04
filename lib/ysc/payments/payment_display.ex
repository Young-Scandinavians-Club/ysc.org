defmodule Ysc.Payments.PaymentDisplay do
  @moduledoc """
  Helper functions for displaying payment information in user interfaces.

  Extracted from UserSettingsLive to improve code organization and reusability.
  """

  @doc """
  Gets the icon name for a payment type.
  """
  def get_payment_icon(%{type: :booking, booking: booking})
      when not is_nil(booking) do
    "hero-home"
  end

  def get_payment_icon(%{type: :ticket}), do: "hero-ticket"
  def get_payment_icon(%{type: :membership}), do: "hero-heart"
  def get_payment_icon(%{type: :donation}), do: "hero-gift"
  def get_payment_icon(_), do: "hero-credit-card"

  @doc """
  Gets the background color class for a payment icon.
  """
  def get_payment_icon_bg(%{type: :booking, booking: booking})
      when not is_nil(booking) do
    case booking.property do
      :tahoe -> "bg-blue-50 group-hover:bg-blue-600"
      :clear_lake -> "bg-emerald-50 group-hover:bg-emerald-600"
      _ -> "bg-purple-50 group-hover:bg-purple-600"
    end
  end

  def get_payment_icon_bg(%{type: :ticket}),
    do: "bg-purple-50 group-hover:bg-purple-600"

  def get_payment_icon_bg(%{type: :membership}),
    do: "bg-teal-50 group-hover:bg-teal-600"

  def get_payment_icon_bg(%{type: :donation}),
    do: "bg-yellow-50 group-hover:bg-yellow-600"

  def get_payment_icon_bg(_), do: "bg-zinc-50 group-hover:bg-zinc-600"

  @doc """
  Gets the text color class for a payment icon.
  """
  def get_payment_icon_color(%{type: :booking, booking: booking})
      when not is_nil(booking) do
    case booking.property do
      :tahoe -> "text-blue-600 group-hover:text-white"
      :clear_lake -> "text-emerald-600 group-hover:text-white"
      _ -> "text-purple-600 group-hover:text-white"
    end
  end

  def get_payment_icon_color(%{type: :ticket}),
    do: "text-purple-600 group-hover:text-white"

  def get_payment_icon_color(%{type: :membership}),
    do: "text-teal-600 group-hover:text-white"

  def get_payment_icon_color(%{type: :donation}),
    do: "text-yellow-600 group-hover:text-white"

  def get_payment_icon_color(_), do: "text-zinc-600 group-hover:text-white"

  @doc """
  Gets the display title for a payment.
  """
  def get_payment_title(%{type: :booking, booking: booking})
      when not is_nil(booking) do
    property_name =
      case booking.property do
        :tahoe -> "Tahoe"
        :clear_lake -> "Clear Lake"
        _ -> "Cabin"
      end

    "#{property_name} Booking"
  end

  def get_payment_title(%{type: :ticket, event: event})
      when not is_nil(event) do
    event.title
  end

  def get_payment_title(%{type: :ticket}), do: "Event Tickets"
  def get_payment_title(%{type: :membership}), do: "Membership Payment"
  def get_payment_title(%{type: :donation}), do: "Donation"
  def get_payment_title(%{description: description}), do: description
  def get_payment_title(_), do: "Payment"

  @doc """
  Gets the reference ID for a payment.
  """
  def get_payment_reference(%{booking: booking}) when not is_nil(booking) do
    booking.reference_id || "—"
  end

  def get_payment_reference(%{ticket_order: ticket_order})
      when not is_nil(ticket_order) do
    ticket_order.reference_id || "—"
  end

  def get_payment_reference(%{payment: payment}) when not is_nil(payment) do
    payment.reference_id || "—"
  end

  def get_payment_reference(_), do: "—"
end
