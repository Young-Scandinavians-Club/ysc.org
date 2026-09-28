defmodule YscWeb.Components.HomeLogoLinkTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "home_logo_link/1" do
    test "renders a home link with the 112px logo, aria-label, and default id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.home_logo_link />
        """)

      assert html =~ ~s(id="home-logo-link")
      assert html =~ ~s(href="/")
      assert html =~ ~s(aria-label="Young Scandinavians Club home")
      assert html =~ ~s(src="/images/ysc_logo.png")
      assert html =~ ~s(width="112")
      assert html =~ ~s(height="112")
      assert html =~ ~s(fetchpriority="high")
      assert html =~ "hover:opacity-80"
      # Link carries the accessible name, so the logo image is decorative
      assert html =~ ~s(alt="")
      refute html =~ "The Young Scandinavian Club Logo"
    end

    test "applies a custom id and extra link classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.home_logo_link id="login-home-logo" class="py-8" />
        """)

      assert html =~ ~s(id="login-home-logo")
      assert html =~ "py-8"
      refute html =~ ~s(id="home-logo-link")
    end
  end

  describe "ysc_logo/1" do
    test "has descriptive alt text by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.ysc_logo width={40} height={40} />
        """)

      assert html =~ ~s(alt="The Young Scandinavian Club Logo")
    end
  end

  describe "input/1 password-toggle" do
    test "binds the toggle button to its input with aria-controls" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.input
          type="password-toggle"
          name="user[password]"
          id="user_password"
          value=""
        />
        """)

      assert html =~ ~s(aria-controls="user_password")
      assert html =~ ~s(aria-pressed="false")
    end
  end
end
