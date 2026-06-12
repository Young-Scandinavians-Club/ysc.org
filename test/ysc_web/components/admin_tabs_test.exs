defmodule YscWeb.AdminTabsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_tabs/1 and admin_tab/1" do
    test "compact density renders bordered nav with active tab styles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_tabs id="tabs" aria_label="Sections">
          <.admin_tab active={true}>One</.admin_tab>
          <.admin_tab active={false}>Two</.admin_tab>
        </.admin_tabs>
        """)

      assert html =~ ~s(id="tabs")
      assert html =~ ~s(aria-label="Sections")
      assert html =~ "overflow-x-auto"
      assert html =~ "admin-tabs-nav"
      assert html =~ "overflow-y-hidden"
      assert html =~ "min-w-0"
      assert html =~ "flex-nowrap"
      assert html =~ "shrink-0"
      assert html =~ "border-blue-500 text-blue-600 bg-white"
      assert html =~ "border-transparent text-zinc-500"
      assert html =~ "rounded-t"
      assert html =~ "py-3 px-4"
    end

    test "spacious density omits rounded top and active background" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_tabs aria_label="Bookings" density={:spacious}>
          <.admin_tab active={true} density={:spacious}>Calendar</.admin_tab>
        </.admin_tabs>
        """)

      assert html =~ "space-x-8"
      assert html =~ "py-4 px-1"
      assert html =~ "overflow-x-auto"
      assert html =~ "admin-tabs-nav"
      assert html =~ "overflow-y-hidden"
      assert html =~ "min-w-0"
      assert html =~ "flex-nowrap"
      assert html =~ "shrink-0"
      assert html =~ "border-blue-500 text-blue-600"
      refute html =~ "bg-white"
      refute html =~ "rounded-t"
    end

    test "patch tab renders a link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_tabs aria_label="Events">
          <.admin_tab active={true} patch="/admin/events?tab=all">All</.admin_tab>
        </.admin_tabs>
        """)

      assert html =~ ~s(href="/admin/events?tab=all")
      assert html =~ "All"
    end

    test "button tab forwards phx-click via rest" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_tabs aria_label="Newsletter" role="tablist">
          <.admin_tab active={true} phx-click="switch-tab" phx-value-tab="editions">
            Editions
          </.admin_tab>
        </.admin_tabs>
        """)

      assert html =~ ~s(phx-click="switch-tab")
      assert html =~ ~s(phx-value-tab="editions")
      assert html =~ ~s(role="tablist")
    end
  end

  describe "admin_sending_badge/1" do
    test "renders spinner pill with default label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_sending_badge />
        """)

      assert html =~ "Sending…"
      assert html =~ "animate-spin"
      assert html =~ "bg-blue-100 text-blue-700"
    end

    test "custom label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_sending_badge label="Processing" />
        """)

      assert html =~ "Processing"
      refute html =~ "Sending…"
    end
  end

  describe "admin_toggle_pill/1" do
    test "active and inactive pill styles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_toggle_pill active={true} phx-click="filter" phx-value-filter="all">
          All
        </.admin_toggle_pill>
        <.admin_toggle_pill active={false} phx-click="filter" phx-value-filter="active">
          Active
        </.admin_toggle_pill>
        """)

      assert html =~ "bg-zinc-200 text-zinc-800"
      assert html =~ "bg-zinc-100 text-zinc-600"
      assert html =~ ~s(phx-value-filter="all")
    end

    test "primary variant uses blue active state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_toggle_pill variant={:primary} active={true} patch="/admin/memberships">
          All
        </.admin_toggle_pill>
        <.admin_toggle_pill
          variant={:primary}
          active={false}
          patch="/admin/memberships?type=single"
        >
          Single
        </.admin_toggle_pill>
        """)

      assert html =~ "bg-blue-600 text-white"
      assert html =~ ~s(href="/admin/memberships")
      assert html =~ ~s(href="/admin/memberships?type=single")
      refute html =~ "bg-zinc-200 text-zinc-800"
    end

    test "dark compact pill variant for media-library year filters" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_toggle_pill
          variant={:dark}
          size={:compact}
          shape={:pill}
          active={true}
          phx-click="filter-year"
          phx-value-year=""
        >
          All
        </.admin_toggle_pill>
        <.admin_toggle_pill
          variant={:dark}
          size={:compact}
          shape={:pill}
          active={false}
          phx-click="filter-year"
          phx-value-year="2024"
        >
          2024
        </.admin_toggle_pill>
        """)

      assert html =~ "bg-zinc-800 text-white"
      assert html =~ "rounded-full"
      assert html =~ "text-xs"
      assert html =~ "bg-zinc-100 text-zinc-600"
      assert html =~ ~s(phx-value-year="2024")
    end
  end
end
