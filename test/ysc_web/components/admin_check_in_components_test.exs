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

  describe "admin_check_in_sticky_header/1" do
    test "renders sticky shell with wide max width by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_sticky_header>
          <:leading><span id="leading">Back</span></:leading>
          <:center><span id="center">3 / 10</span></:center>
          <:actions><span id="actions">Scan</span></:actions>
        </.admin_check_in_sticky_header>
        """)

      assert html =~ "sticky top-0"
      assert html =~ "max-w-7xl"
      assert html =~ ~s(id="leading")
      assert html =~ ~s(id="center")
      assert html =~ ~s(id="actions")
    end

    test "renders narrow max width when max_width is :narrow" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_check_in_sticky_header max_width={:narrow}>
          <:leading>Title</:leading>
          <:actions>Go</:actions>
        </.admin_check_in_sticky_header>
        """)

      assert html =~ "max-w-5xl"
      refute html =~ "max-w-7xl"
    end
  end

  describe "admin_mobile_icon_button/1" do
    test "renders primary mobile icon button with phx-click" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_icon_button
          icon="hero-qr-code"
          aria_label="Open QR Scanner"
          phx-click="launch-scanner"
        />
        """)

      assert html =~ "sm:hidden"
      assert html =~ "hero-qr-code"
      assert html =~ ~s(aria-label="Open QR Scanner")
      assert html =~ ~s(phx-click="launch-scanner")
      assert html =~ "text-blue-700"
    end

    test "renders muted tone and data-confirm" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_icon_button
          icon="hero-check-circle"
          aria_label="Complete session"
          tone={:muted}
          phx-click="complete-session"
          data-confirm="Complete this session?"
        />
        """)

      assert html =~ "text-zinc-500"
      assert html =~ ~s(data-confirm="Complete this session?")
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
end
