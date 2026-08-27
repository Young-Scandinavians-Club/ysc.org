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

    test "defaults to the 1–3 range with no order shortcut" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_keyboard_hints />
        """)

      assert html =~ "1–3"
      refute html =~ "check in order"
      refute html =~ ~s(data-key="shift-mod")
    end

    test "advertises the wider range and order shortcut when opted in" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_keyboard_hints quick_range="1–8" order_shortcut />
        """)

      assert html =~ "1–8"
      refute html =~ "1–3"
      assert html =~ "check in order"
      assert html =~ ~s(data-key="shift-mod")
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
      assert html =~ "data-checkin-all-btn"
      assert html =~ "checkin-kbd-order-badge"
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
      refute html =~ "checkin-kbd-order-badge"
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
      refute html =~ "checkin-kbd-order-badge"
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

    test "renders mobile interactive button without icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_all_button order_id={5} variant={:mobile} />
        """)

      assert html =~ "Check in all"
      assert html =~ ~s(phx-value-order-id="5")
      refute html =~ "hero-check-circle"
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

    test "uses variant icon_class when icon_class is omitted" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_icon_empty_state
          variant={:success}
          icon="hero-check-circle"
          title="Done"
          description="Everyone is here"
        />
        """)

      assert html =~ "w-10 h-10 mx-auto mb-2 text-emerald-400"
      assert html =~ "Everyone is here"
      assert html =~ "text-sm mt-1 text-zinc-400"
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

  describe "admin_responsive_clipboard_button/1" do
    test "renders labeled desktop button and icon-only mobile clipboard control" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_responsive_clipboard_button
          id="copy-url-btn"
          copy="https://example.com/admin/session"
          icon="hero-clipboard"
          label="Share"
          aria_label="Copy session link for other admins to join"
          title="Copy session link for other admins to join"
          variant="outline"
          color="zinc"
          mobile_tone={:zinc}
        />
        """)

      assert html =~ ~s(id="copy-url-btn")
      assert html =~ "Share"
      assert html =~ "hero-clipboard"
      assert html =~ ~s(aria-label="Copy session link for other admins to join")
      assert html =~ ~s(phx-hook="ClipboardCopy")
      assert html =~ ~s(data-copy="https://example.com/admin/session")
      assert html =~ "hidden sm:inline-flex"
      assert html =~ "sm:hidden"
      assert html =~ "text-zinc-500 hover:text-zinc-700"
    end

    test "supports copy_target for element-based clipboard sources" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_responsive_clipboard_button
          id="copy-target-btn"
          copy_target="source-field"
          label="Copy"
          aria_label="Copy value"
        />
        """)

      assert html =~ ~s(data-copy-target="source-field")
    end
  end

  describe "admin_event_check_in_pending_row/1" do
    test "renders interactive desktop row with check-in control and order tooltip" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_pending_row
          variant={:desktop}
          ticket_id={42}
          name="Ada Lovelace"
          email="ada@example.com"
          tier="General"
          ticket_ref="TKT-001"
          order_ref="ORD-001"
          order_ref_tooltip="ORD-001-full"
        />
        """)

      assert html =~ "Ada Lovelace"
      assert html =~ "ada@example.com"
      assert html =~ "General"
      assert html =~ "TKT-001"
      assert html =~ "ORD-001"
      assert html =~ ~s(phx-value-ticket-id="42")
      assert html =~ "data-checkin-row"
      assert html =~ "data-checkin-btn"
      assert html =~ "checkin-kbd-badge"
    end

    test "renders static desktop row for ghost previews" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_pending_row
          variant={:desktop}
          interactive={false}
          name="Ghost Guest"
          email="ghost@example.com"
          tier="VIP"
          ticket_ref="TKT-ghost"
          order_ref="ORD-ghost"
        />
        """)

      assert html =~ "Ghost Guest"
      assert html =~ "VIP"
      refute html =~ "phx-click"
      refute html =~ "data-checkin-row"
      refute html =~ "data-checkin-btn"
    end

    test "renders mobile pending row with check-in button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_pending_row
          variant={:mobile}
          ticket_id={7}
          name="Mobile Guest"
          email="mobile@example.com"
          ticket_ref="TKT-007"
        />
        """)

      assert html =~ "Mobile Guest"
      assert html =~ "Check in"
      assert html =~ ~s(phx-value-ticket-id="7")
      assert html =~ "data-checkin-row"
    end
  end

  describe "admin_event_check_in_checked_in_row/1" do
    test "renders interactive desktop row with undo control and check-in time" do
      checked_in_at = ~U[2026-06-24 14:30:00Z]
      assigns = %{checked_in_at: checked_in_at}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_checked_in_row
          id="checked-1"
          variant={:desktop}
          ticket_id={99}
          name="Checked Guest"
          email="checked@example.com"
          tier="General"
          ticket_ref="TKT-099"
          checked_in_at={@checked_in_at}
          checked_in_time_label="Jun 24, 14:30 UTC"
        />
        """)

      assert html =~ ~s(id="checked-1")
      assert html =~ "Checked Guest"
      assert html =~ "line-through"
      assert html =~ ~s(phx-value-ticket-id="99")
      assert html =~ "Undo check-in"
      assert html =~ "checkin-time-99"
      assert html =~ "Jun 24, 14:30 UTC"
      assert html =~ "hero-clock"
    end

    test "renders static desktop row for ghost previews" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_checked_in_row
          variant={:desktop}
          interactive={false}
          name="Ghost Checked"
          email="ghost-checked@example.com"
          tier="VIP"
          ticket_ref="TKT-done"
        />
        """)

      assert html =~ "Ghost Checked"
      assert html =~ "hero-check"
      refute html =~ "phx-click"
      refute html =~ "hero-clock"
    end

    test "renders mobile checked-in row with undo button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_check_in_checked_in_row
          id="mobile-checked-1"
          variant={:mobile}
          ticket_id={12}
          name="Mobile Checked"
          email="mobile-checked@example.com"
          ticket_ref="TKT-012"
        />
        """)

      assert html =~ ~s(id="mobile-checked-1")
      assert html =~ "Mobile Checked"
      assert html =~ "Undo"
      assert html =~ ~s(phx-value-ticket-id="12")
    end
  end
end
