defmodule YscWeb.AdminCollapsibleSectionTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_collapsible_section/1" do
    test "renders expanded section with table content wrapper" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_collapsible_section
          section="payments"
          title="Recent Payments"
          collapsed?={false}
        >
          <p id="payments-body">Table body</p>
        </.admin_collapsible_section>
        """)

      assert html =~ ~s(phx-click="toggle_section")
      assert html =~ ~s(phx-value-section="payments")
      assert html =~ "Recent Payments"
      assert html =~ "hero-chevron-down"
      refute html =~ "hero-chevron-right"
      assert html =~ ~s(class="overflow-hidden")
      assert html =~ ~s(id="payments-body")
    end

    test "renders collapsed section without body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_collapsible_section
          section="accounts"
          title="Account Balances"
          collapsed?={true}
          content_variant={:padded}
        >
          <p id="accounts-body">Cards</p>
        </.admin_collapsible_section>
        """)

      assert html =~ "hero-chevron-right"
      refute html =~ "hero-chevron-down"
      refute html =~ ~s(id="accounts-body")
    end

    test "merges custom outer container classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_collapsible_section
          section="ledger_entries"
          title="Ledger Entries"
          collapsed?={false}
          class="mb-8 rounded border"
        >
          <span>content</span>
        </.admin_collapsible_section>
        """)

      assert html =~ ~s(class="mb-8 rounded border")
      refute html =~ "bg-white"
    end
  end
end
