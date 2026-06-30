defmodule YscWeb.AdminSettingsLiveTest do
  @moduledoc """
  Admin settings LiveView tests.

  Runs with `async: false` because the settings form uses `temporary_assigns` and
  connected-mount timing can otherwise submit before settings fields are in the DOM.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

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

      {:ok, _view, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Missing upload, read, or edit permissions"
      assert html =~ "Disconnect and connect again"
    end

    test "updates settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      # Drain connected mount work before submitting. temporary_assigns clears
      # form/scopes after the dead render, so an immediate submit can post %{} and
      # raise FunctionClauseError in handle_event/3 under CI load.
      html = render(view)
      assert html =~ "Save"
      assert has_element?(view, "#admin-settings-form")
      assert has_element?(view, "input[name^='settings']")

      view
      |> form("#admin-settings-form", %{settings: %{}})
      |> render_submit()

      assert_redirected(view, ~p"/admin/settings")
    end
  end
end
