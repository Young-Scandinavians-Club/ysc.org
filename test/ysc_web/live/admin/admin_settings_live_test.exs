defmodule YscWeb.AdminSettingsLiveTest do
  @moduledoc """
  Admin settings LiveView tests.

  Runs with `async: false` because connected-mount async loading and Oban PubSub
  can race with assertions when the full suite runs under CI load.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  @settings_async_timeout 5_000

  defp render_loaded_settings(view) do
    html = render_async(view, @settings_async_timeout)
    refute html =~ ~s|id="admin-settings-loading"|
    assert html =~ "Save"
    assert html =~ ~s|name="settings|
    html
  end

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Settings" do
    setup [:create_admin]

    test "renders settings page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Settings"
      assert html =~ "Recent Oban Jobs"
      assert has_element?(view, "#google-photos-integration")
    end

    test "shows connect when not connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      render_loaded_settings(view)
      assert has_element?(view, "#google-photos-connect")
      refute has_element?(view, "#google-photos-disconnect")
    end

    test "shows disconnect when connected", %{conn: conn, admin: admin} do
      Ysc.GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600,
          scope: Enum.join(Ysc.GooglePhotos.OAuth.photos_api_scopes(), " ")
        },
        admin.id,
        "photos@example.com"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      render_loaded_settings(view)

      assert has_element?(view, "#google-photos-disconnect")
      assert has_element?(view, "#google-photos-test-connection")
      refute has_element?(view, "#google-photos-connect")
    end

    test "warns when connected grant is missing required Photos scopes", %{
      conn: conn,
      admin: admin
    } do
      Ysc.GooglePhotos.connect!(
        %{
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600,
          scope:
            "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata"
        },
        admin.id,
        "photos@example.com"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      html = render_loaded_settings(view)

      assert html =~ "Missing upload, read, or edit permissions"
      assert html =~ "Disconnect and connect again"
    end

    test "updates settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      render_loaded_settings(view)

      view
      |> form("#admin-settings-form", %{settings: %{}})
      |> render_submit()

      assert_redirected(view, ~p"/admin/settings")
    end
  end
end
