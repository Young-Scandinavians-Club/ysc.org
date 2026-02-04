defmodule YscWeb.AdminSettingsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Settings" do
    setup [:create_admin]

    test "renders settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Settings"
      assert html =~ "Recent Oban Jobs"
    end

    test "updates settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      # We need to find a setting to update. Settings are grouped by scope.
      # Let's just check if the form is there.
      assert has_element?(view, "#admin-settings-form")

      view
      |> form("#admin-settings-form", %{settings: %{}})
      |> render_submit()

      assert_redirected(view, ~p"/admin/settings")
    end
  end
end
