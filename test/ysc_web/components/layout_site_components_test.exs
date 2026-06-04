defmodule YscWeb.Components.LayoutSiteComponentsTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YscWeb.CoreComponents
  alias YscWeb.Layouts

  describe "hide_mobile_menu/1" do
    test "returns JS ops that close the slide-in panel for the given toggle id" do
      js = CoreComponents.hide_mobile_menu("navbar-dropdown")

      assert %Phoenix.LiveView.JS{} = js
      assert js.ops != []
    end
  end

  describe "membership_status_banners/1" do
    test "renders pending approval banner for pending user" do
      user = %{state: :pending_approval}

      html =
        render_component(&Layouts.membership_status_banners/1, %{
          current_user: user,
          active_membership?: false,
          is_fullscreen: false
        })

      assert html =~ "Application Under Review"
      assert html =~ "pending-review"
    end

    test "renders membership required banner for active user without membership" do
      user = %{state: :active}

      html =
        render_component(&Layouts.membership_status_banners/1, %{
          current_user: user,
          active_membership?: false,
          is_fullscreen: false
        })

      assert html =~ "Membership Required"
      assert html =~ "Manage Membership"
    end

    test "renders nothing on fullscreen layout" do
      user = %{state: :pending_approval}

      html =
        render_component(&Layouts.membership_status_banners/1, %{
          current_user: user,
          active_membership?: false,
          is_fullscreen: true
        })

      refute html =~ "Application Under Review"
    end
  end

  describe "footer_section_heading/1" do
    test "renders uppercase section title" do
      html = render_component(&Layouts.footer_section_heading/1, %{title: "Policies"})

      assert html =~ "Policies"
      assert html =~ "uppercase"
    end
  end

  describe "footer_nav_link/1" do
    test "renders link with shared footer underline classes" do
      html =
        render_component(&Layouts.footer_nav_link/1, %{
          navigate: "/privacy-policy",
          inner_block: ["Privacy Policy"]
        })

      assert html =~ "Privacy Policy"
      assert html =~ "underline-offset-4"
      assert html =~ ~s(href="/privacy-policy")
    end
  end
end
