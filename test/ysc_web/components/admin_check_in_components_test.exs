defmodule YscWeb.AdminCheckInComponentsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_check_in_keyboard_hints/1" do
    test "renders navigate, enter, and quick-check-in shortcuts" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_keyboard_hints />
        """)

      assert html =~ "navigate"
      assert html =~ "check in"
      assert html =~ "quick check in"
      assert html =~ ~s(data-key="alt")
      assert html =~ "↵ enter"
    end

    test "renders nothing when show is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_keyboard_hints show={false} />
        """)

      assert html == ""
    end
  end

  describe "admin_check_in_counter/1" do
    test "renders count only when total is omitted" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_counter count={5} />
        """)

      assert html =~ "Checked in:"
      assert html =~ "hero-user-group"
      assert html =~ ~r/\b5\b/
      refute html =~ " / "
    end

    test "renders count and total when total is provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_counter count={3} total={10} />
        """)

      assert html =~ "3 / 10"
    end
  end

  describe "admin_section_heading/1" do
    test "renders title without badge when count is omitted" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_section_heading>Pending</.admin_section_heading>
        """)

      assert html =~ "Pending"
      refute html =~ "rounded-full"
    end

    test "renders zinc count badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_section_heading count={4} badge_tone={:zinc}>
          Pending
        </.admin_section_heading>
        """)

      assert html =~ "Pending"
      assert html =~ ~r/\b4\b/
      assert html =~ "bg-zinc-100 text-zinc-700"
    end

    test "renders emerald count badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_section_heading count={2} badge_tone={:emerald}>
          Checked In
        </.admin_section_heading>
        """)

      assert html =~ "bg-emerald-100 text-emerald-700"
    end
  end

  describe "admin_check_in_sticky_bar/1" do
    test "renders standard width container by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_sticky_bar>
          <span id="bar-slot">Title</span>
        </.admin_check_in_sticky_bar>
        """)

      assert html =~ "sticky top-0"
      assert html =~ "max-w-5xl"
      assert html =~ ~s(id="bar-slot")
    end

    test "renders wide layout when width is :wide" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_sticky_bar width={:wide}>
          <span>Wide</span>
        </.admin_check_in_sticky_bar>
        """)

      assert html =~ "max-w-7xl"
      refute html =~ "max-w-5xl"
    end
  end

  describe "admin_check_in_search_section/1" do
    test "renders search panel padding and slot content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_search_section>
          <input id="search-input" />
        </.admin_check_in_search_section>
        """)

      assert html =~ "pt-3 pb-2"
      assert html =~ ~s(id="search-input")
    end
  end

  describe "admin_check_in_content/1" do
    test "renders content area spacing classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_content>
          <p>Body</p>
        </.admin_check_in_content>
        """)

      assert html =~ "py-6 space-y-8"
      assert html =~ "Body"
    end
  end

  describe "admin_check_in_qr_scanner/1" do
    test "renders desktop and mobile QR scanner controls" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_qr_scanner id="launch-scanner-btn" />
        """)

      assert html =~ ~s(id="launch-scanner-btn")
      assert html =~ "QR Scanner"
      assert html =~ "hero-qr-code"
      assert html =~ ~s(aria-label="Open QR Scanner")
      assert html =~ ~s(phx-click="launch-scanner")
      assert html =~ "hidden sm:inline-flex"
      assert html =~ "sm:hidden"
    end
  end

  describe "admin_loading_panel/1" do
    test "renders centered spinner with default classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_loading_panel />
        """)

      assert html =~ "flex items-center justify-center py-24"
      assert html =~ "w-8 h-8 text-zinc-400"
    end
  end

  describe "admin_event_check_in_table_header/1" do
    test "renders event check-in column labels" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_table_header />
        """)

      assert html =~ "Attendee"
      assert html =~ "Email"
      assert html =~ "Tier"
      assert html =~ "Ticket"
      assert html =~ "Order"
      assert html =~ "uppercase tracking-wide"
    end
  end

  describe "admin_event_check_in_order_group_header/1" do
    test "renders desktop order group with bulk check-in button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_order_group_header
          order_ref="ORD-12345"
          ticket_count={3}
          order_id={42}
        />
        """)

      assert html =~ "ORD-12345"
      assert html =~ "3 tickets"
      assert html =~ "hero-shopping-bag"
      assert html =~ ~s(phx-click="check-in-order")
      assert html =~ ~s(phx-value-order-id="42")
      assert html =~ "Check in all"
      assert html =~ "grid grid-cols-12"
    end

    test "hides bulk action for single-ticket orders" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_order_group_header
          order_ref="ORD-99999"
          ticket_count={1}
          order_id={7}
        />
        """)

      assert html =~ "1 ticket"
      refute html =~ "Check in all"
    end

    test "renders mobile variant with text-only bulk action" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_order_group_header
          variant={:mobile}
          order_ref="ORD-55555"
          ticket_count={2}
          order_id={9}
        />
        """)

      assert html =~ "ORD-55555"
      assert html =~ "Check in all"
      refute html =~ "hero-check-circle"
      refute html =~ "grid grid-cols-12"
    end

    test "renders static bulk action for ghost preview" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_order_group_header
          order_ref="ORD-77777"
          ticket_count={2}
          id="ghost-check-in-order-all"
          interactive={false}
        />
        """)

      assert html =~ ~s(id="ghost-check-in-order-all")
      assert html =~ "Check in all"
      refute html =~ ~s(phx-click="check-in-order")
    end
  end

  describe "admin_check_in_all_button/1" do
    test "renders desktop interactive button with icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_all_button order_id={11} variant={:desktop} />
        """)

      assert html =~ "Check in all"
      assert html =~ "hero-check-circle"
      assert html =~ ~s(phx-value-order-id="11")
    end

    test "renders static desktop label without phx-click" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_all_button variant={:desktop} interactive={false} />
        """)

      assert html =~ "Check in all"
      refute html =~ "phx-click"
    end
  end

  describe "admin_icon_empty_state/1 success variant" do
    test "renders bordered success panel with emerald icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          variant={:success}
          icon="hero-check-circle"
          title="All attendees checked in!"
        />
        """)

      assert html =~ "All attendees checked in!"
      assert html =~ "bg-white rounded border border-zinc-200"
      assert html =~ "text-emerald-400"
    end
  end

  describe "admin_responsive_icon_button/1" do
    test "renders labeled desktop button and icon-only mobile control" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_responsive_icon_button
          id="complete-session-btn"
          icon="hero-check-circle"
          label="Complete"
          aria_label="Complete session"
          phx_click="complete-session"
          variant="outline"
          color="zinc"
          mobile_tone={:zinc}
          data-confirm="Complete this session?"
        />
        """)

      assert html =~ ~s(id="complete-session-btn")
      assert html =~ "Complete"
      assert html =~ "hero-check-circle"
      assert html =~ ~s(aria-label="Complete session")
      assert html =~ ~s(phx-click="complete-session")
      assert html =~ "hidden sm:inline-flex"
      assert html =~ "sm:hidden"
      assert html =~ "text-zinc-500 hover:text-zinc-700"
      assert html =~ ~s(data-confirm="Complete this session?")
    end

    test "uses primary mobile colors by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_responsive_icon_button
          icon="hero-qr-code"
          label="QR Scanner"
          aria_label="Open QR Scanner"
          phx_click="launch-scanner"
        />
        """)

      assert html =~ "text-blue-700 hover:text-blue-900"
    end
  end
end
