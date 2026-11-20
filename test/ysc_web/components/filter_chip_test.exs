defmodule YscWeb.Components.FilterChipTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "filter_chip/1" do
    test "renders an idle button with filter event attrs" do
      assigns = %{}

      heex = ~H"""
      <.filter_chip phx-click="filter-payments" phx-value-filter="events">
        Events
      </.filter_chip>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|phx-click="filter-payments"|
      assert html =~ ~s|phx-value-filter="events"|
      assert html =~ ~s|type="button"|
      assert html =~ "rounded-full"
      assert html =~ "px-4 py-2"
      assert html =~ "bg-zinc-100"
      assert html =~ "text-zinc-700"
      refute html =~ "shadow-md"
      assert html =~ "Events"
      refute html =~ "<a"
    end

    test "renders the selected color, icon, and id" do
      assigns = %{}

      heex = ~H"""
      <.filter_chip
        id="payment-filter-merch"
        active
        color={:rose}
        icon="hero-shopping-bag"
        phx-click="filter-payments"
        phx-value-filter="merch"
      >
        Club Gear
      </.filter_chip>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="payment-filter-merch"|
      assert html =~ "bg-rose-600"
      assert html =~ "text-white"
      assert html =~ "shadow-md"
      assert html =~ "hero-shopping-bag"
      assert html =~ "flex items-center gap-2"
      assert html =~ "Club Gear"
      refute html =~ "text-rose-600"
    end

    test "idle chip with icon uses the color for the icon only" do
      assigns = %{}

      heex = ~H"""
      <.filter_chip color={:emerald} icon="hero-home" phx-click="filter-payments">
        Clear Lake
      </.filter_chip>
      """

      html = rendered_to_string(heex)

      assert html =~ "text-emerald-600"
      assert html =~ "bg-zinc-100"
      refute html =~ "bg-emerald-600"
      assert html =~ "Clear Lake"
    end

    test "renders a patch link with aria-current when selected" do
      assigns = %{}

      heex = ~H"""
      <.filter_chip
        id="orders-filter-needs_attention"
        active
        patch="/admin/merch/orders?filter=needs_attention"
      >
        Needs attention
      </.filter_chip>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="orders-filter-needs_attention"|
      assert html =~ ~s|href="/admin/merch/orders?filter=needs_attention"|
      assert html =~ ~s|aria-current="true"|
      assert html =~ "bg-blue-600"
      assert html =~ "Needs attention"
      refute html =~ "<button"
      refute html =~ "flex items-center gap-2"
    end

    test "merges extra class onto the control" do
      assigns = %{}

      heex = ~H"""
      <.filter_chip class="sm:px-5" phx-click="filter-payments">
        All
      </.filter_chip>
      """

      html = rendered_to_string(heex)

      assert html =~ "sm:px-5"
      assert html =~ "All"
    end
  end
end
