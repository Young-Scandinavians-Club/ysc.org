defmodule YscWeb.Components.LabeledDividerTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "labeled_divider/1" do
    test "renders the label, default rule color, and required id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_divider id="login-or-divider">or</.labeled_divider>
        """)

      assert html =~ ~s(id="login-or-divider")
      assert html =~ "or"
      assert html =~ "border-zinc-200"
      assert html =~ "bg-white px-2 text-zinc-500"
      refute html =~ "border-zinc-300"
    end

    test "applies extra wrapper, line, and label classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_divider
          id="payment-add-new-divider"
          class="my-6"
          line_class="border-zinc-300"
          label_class="bg-white px-3 text-xs text-zinc-400 uppercase tracking-wide"
        >
          Add new
        </.labeled_divider>
        """)

      assert html =~ ~s(id="payment-add-new-divider")
      assert html =~ "my-6"
      assert html =~ "border-zinc-300"
      assert html =~ "Add new"
      assert html =~ "uppercase tracking-wide"
      refute html =~ "border-zinc-200"
    end

    test "omits the label when show_label is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.labeled_divider id="payment-add-new-divider" show_label={false}>
          Add new
        </.labeled_divider>
        """)

      assert html =~ ~s(id="payment-add-new-divider")
      assert html =~ "border-zinc-200"
      refute html =~ "Add new"
    end
  end
end
