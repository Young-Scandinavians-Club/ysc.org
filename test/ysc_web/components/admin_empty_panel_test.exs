defmodule YscWeb.AdminEmptyPanelTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_empty_panel/1" do
    test "renders dashed empty panel with message" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_empty_panel id="no-payments">
          No payments found for this booking.
        </.admin_empty_panel>
        """)

      assert html =~ ~s(id="no-payments")
      assert html =~ "border-dashed border-zinc-300"
      assert html =~ "No payments found for this booking."
      assert html =~ "text-sm text-zinc-500"
    end

    test "merges custom classes onto the panel" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_empty_panel class="mt-2">
          Nothing here yet.
        </.admin_empty_panel>
        """)

      assert html =~ "mt-2"
      assert html =~ "Nothing here yet."
    end
  end
end
