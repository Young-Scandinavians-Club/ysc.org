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
