defmodule YscWeb.Components.AuthPanelTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "auth_panel/1" do
    test "renders the shared auth column, home logo, and inner content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.auth_panel logo_id="login-home-logo">
          <p id="auth-panel-body">Sign in</p>
        </.auth_panel>
        """)

      assert html =~ "max-w-sm"
      assert html =~ "mx-auto"
      assert html =~ "py-4"
      assert html =~ "px-4"
      assert html =~ ~s(id="login-home-logo")
      assert html =~ "py-8"
      assert html =~ ~s(href="/")
      assert html =~ ~s(aria-label="Young Scandinavians Club home")
      assert html =~ ~s(id="auth-panel-body")
      assert html =~ "Sign in"
      refute html =~ ~s(id="home-logo-link")
    end

    test "forwards a wrapper id and extra column classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.auth_panel
          id="reset-auth-panel"
          logo_id="reset-password-home-logo"
          class="bg-white"
        >
          <h1>Reset Your Password</h1>
        </.auth_panel>
        """)

      assert html =~ ~s(id="reset-auth-panel")
      assert html =~ ~s(id="reset-password-home-logo")
      assert html =~ "bg-white"
      assert html =~ "Reset Your Password"
    end
  end
end
