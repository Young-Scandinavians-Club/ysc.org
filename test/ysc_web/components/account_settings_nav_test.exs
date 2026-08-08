defmodule YscWeb.Components.AccountSettingsNavTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.CoreComponents

  describe "account_settings_nav/1" do
    test "renders all standard links when family link is hidden" do
      html =
        render_component(&CoreComponents.account_settings_nav/1, %{
          current: :profile,
          show_family_link?: false
        })

      assert html =~ "Account"
      assert html =~ "Profile"
      assert html =~ "Membership"
      assert html =~ "Bookings &amp; Payments"
      assert html =~ "Security"
      assert html =~ "Notifications"
      refute html =~ "Family"
    end

    test "includes family link when show_family_link? is true" do
      html =
        render_component(&CoreComponents.account_settings_nav/1, %{
          current: :family,
          show_family_link?: true
        })

      assert html =~ "Family"
      assert html =~ ~s(href="/users/settings/family")
    end

    test "highlights the current section" do
      html =
        render_component(&CoreComponents.account_settings_nav/1, %{
          current: :payments,
          show_family_link?: false
        })

      assert html =~ "bg-blue-600"
      assert html =~ ~s(href="/users/payments")
    end

    test "maps membership routes to membership nav item" do
      html =
        render_component(&CoreComponents.account_settings_nav/1, %{
          current: :membership,
          show_family_link?: false
        })

      assert html =~ ~s(href="/users/membership")
      assert html =~ "bg-blue-600"
    end
  end

  describe "account_settings_nav_link/1" do
    test "renders inactive link with hover classes" do
      html =
        render_component(&CoreComponents.account_settings_nav_link/1, %{
          navigate: "/users/settings",
          icon: "hero-user",
          label: "Profile",
          active?: false
        })

      assert html =~ "Profile"
      assert html =~ "hover:bg-zinc-100"
      refute html =~ "bg-blue-600"
    end

    test "renders active link with highlight classes" do
      html =
        render_component(&CoreComponents.account_settings_nav_link/1, %{
          navigate: "/users/settings/security",
          icon: "hero-shield-check",
          label: "Security",
          active?: true
        })

      assert html =~ "Security"
      assert html =~ "bg-blue-600"
      assert html =~ "aria-active"
    end
  end
end
