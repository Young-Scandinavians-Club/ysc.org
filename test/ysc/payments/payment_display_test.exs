defmodule Ysc.Payments.PaymentDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Payments.PaymentDisplay

  describe "get_payment_icon/1 and styling" do
    test "booking with Clear Lake property uses emerald styling" do
      booking = %{property: :clear_lake, reference_id: "BK-CL"}
      payment = %{type: :booking, booking: booking}

      assert PaymentDisplay.get_payment_icon(payment) == "hero-home"
      assert PaymentDisplay.get_payment_icon_bg(payment) =~ "emerald"
      assert PaymentDisplay.get_payment_icon_color(payment) =~ "emerald"
      assert PaymentDisplay.get_payment_title(payment) == "Clear Lake Booking"
    end

    test "booking with unknown property uses purple fallback styling" do
      booking = %{property: :other, reference_id: "BK-X"}
      payment = %{type: :booking, booking: booking}

      assert PaymentDisplay.get_payment_icon_bg(payment) =~ "purple"
      assert PaymentDisplay.get_payment_icon_color(payment) =~ "purple"
      assert PaymentDisplay.get_payment_title(payment) == "Cabin Booking"
    end

    test "booking with nil booking falls through to default icon and zinc styling" do
      payment = %{type: :booking, booking: nil}

      assert PaymentDisplay.get_payment_icon(payment) == "hero-credit-card"
      assert PaymentDisplay.get_payment_icon_bg(payment) =~ "zinc"
      assert PaymentDisplay.get_payment_icon_color(payment) =~ "zinc"
    end
  end

  describe "get_payment_title/1" do
    test "ticket without event uses generic title" do
      assert PaymentDisplay.get_payment_title(%{type: :ticket}) ==
               "Event Tickets"
    end

    test "booking with nil reference falls back to em dash in reference" do
      booking = %{property: :tahoe, reference_id: nil}
      assert PaymentDisplay.get_payment_reference(%{booking: booking}) == "—"
    end

    test "ticket order with nil reference_id falls back" do
      assert PaymentDisplay.get_payment_reference(%{
               ticket_order: %{reference_id: nil}
             }) == "—"
    end
  end
end
