defmodule YscWeb.Components.LabeledValueTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "labeled_value/1" do
    test "renders the eyebrow label, value, and default receipt size" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value label="Event">Midsummer</.labeled_value>
        """)

      assert html =~ "Event"
      assert html =~ "Midsummer"
      assert html =~ "type-eyebrow"
      assert html =~ "text-xl font-bold text-zinc-900"
      refute html =~ "line-through"
    end

    test "renders an optional detail line and ids" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value
          id="order-when"
          label="Date & Time"
          value_id="order-when-date"
          detail_id="order-when-time"
        >
          June 21, 2026
          <:detail>7:00 PM</:detail>
        </.labeled_value>
        """)

      assert html =~ ~s(id="order-when")
      assert html =~ ~s(id="order-when-date")
      assert html =~ ~s(id="order-when-time")
      assert html =~ "June 21, 2026"
      assert html =~ "7:00 PM"
      assert html =~ "text-sm text-zinc-500"
    end

    test "omits the detail line when the slot is empty" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value label="Event">Midsummer</.labeled_value>
        """)

      refute html =~ "text-sm text-zinc-500"
    end

    test "applies muted strike styling for cancelled records" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value label="Check-in" muted>
          June 21, 2026
          <:detail>After 3:00 PM</:detail>
        </.labeled_value>
        """)

      assert html =~ "text-xl font-bold text-zinc-500 line-through"
      assert html =~ "After 3:00 PM"
      refute html =~ "text-xl font-bold text-zinc-900"
    end

    test "lets callers override value classes for compact panels" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value label="Price" value_class="text-sm font-bold text-zinc-800">
          $25.00
        </.labeled_value>
        """)

      assert html =~ "text-sm font-bold text-zinc-800"
      refute html =~ "text-xl font-bold"
    end

    test "merges extra wrapper and label classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_value
          label="Email"
          class="col-span-2"
          label_class="text-zinc-400"
        >
          member@ysc.org
        </.labeled_value>
        """)

      assert html =~ "col-span-2"
      assert html =~ "text-zinc-400"
      assert html =~ "member@ysc.org"
    end
  end
end
