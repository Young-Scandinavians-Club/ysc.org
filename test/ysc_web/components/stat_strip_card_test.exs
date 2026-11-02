defmodule YscWeb.Components.StatStripCardTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "stat_strip_card/1" do
    test "renders cover, labelled stats, and default confirmation chrome" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_strip_card id="order-confirmation-summary">
          <:cover>
            <img src="/images/event.jpg" alt="Midsummer" />
          </:cover>
          <.labeled_value
            id="order-confirmation-event"
            label="Event"
            class="bg-zinc-50 p-5"
          >
            Midsummer
          </.labeled_value>
        </.stat_strip_card>
        """)

      assert html =~ ~s(id="order-confirmation-summary")
      assert html =~ ~s(src="/images/event.jpg")
      assert html =~ "Midsummer"
      assert html =~ "Event"
      assert html =~ "bg-white"
      assert html =~ "border-zinc-200"
      assert html =~ "rounded-xl"
      assert html =~ "h-48"
      assert html =~ "grid-cols-1 md:grid-cols-3 gap-px bg-zinc-200"
      refute html =~ "Cancelled"
      refute html =~ "grayscale"
      refute html =~ "opacity-60"
    end

    test "supports a shorter cover on checkout" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_strip_card
          id="checkout-booking-summary"
          cover_class="h-40"
          class="custom-card"
        >
          <:cover>
            <img src="/images/tahoe.jpg" alt="Tahoe Cabin" />
          </:cover>
          <.labeled_value label="Cabin" class="bg-zinc-50 p-5">
            Tahoe Cabin
          </.labeled_value>
        </.stat_strip_card>
        """)

      assert html =~ ~s(id="checkout-booking-summary")
      assert html =~ "custom-card"
      assert html =~ "h-40"
      refute html =~ "h-48"
      assert html =~ "Tahoe Cabin"
    end

    test "mutes the card and overlays Cancelled when cancelled" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_strip_card id="booking-receipt-stay-details" cancelled?>
          <:cover>
            <img src="/images/tahoe.jpg" alt="Lake Tahoe Cabin" />
          </:cover>
          <.labeled_value label="Check-in" muted class="bg-zinc-50 p-5">
            Jun 1
          </.labeled_value>
        </.stat_strip_card>
        """)

      assert html =~ ~s(id="booking-receipt-stay-details")
      assert html =~ "Cancelled"
      assert html =~ "bg-zinc-100"
      assert html =~ "border-zinc-300"
      assert html =~ "opacity-60"
      assert html =~ "grayscale"
      assert html =~ "bg-red-500/20"
      assert html =~ "Jun 1"
      refute html =~ "bg-white border-zinc-200"
    end
  end
end
