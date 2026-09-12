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
end
