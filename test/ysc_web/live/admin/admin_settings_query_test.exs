defmodule YscWeb.AdminSettingsQueryTest do
  @moduledoc """
  Query-count assertions for admin settings deferred page data loading.

  Runs with `async: false` so global Ecto telemetry handlers are not polluted
  by parallel admin LiveView tests in the main suite module.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "deferred settings loading" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dead render does not query site_settings or google_photos_connections",
         %{
           conn: conn
         } do
      settings_pattern = ~r/FROM "site_settings"/i
      google_photos_pattern = ~r/FROM "google_photos_connections"/i

      {html, settings_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/settings")
            |> html_response(200)
          end,
          pattern: settings_pattern
        )

      {_html, google_photos_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/settings")
            |> html_response(200)
          end,
          pattern: google_photos_pattern
        )

      assert settings_count == 0
      assert google_photos_count == 0
      assert html =~ "Settings"
      assert html =~ ~s|id="admin-settings-loading"|
      refute html =~ ~s|id="admin-settings-form"|
    end

    test "connected mount loads settings and google photos status once", %{
      conn: conn
    } do
      settings_pattern = ~r/FROM "site_settings"/i
      google_photos_pattern = ~r/FROM "google_photos_connections"/i

      {{:ok, view, _html}, settings_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/settings")
            render_async(view)
            {:ok, view, html}
          end,
          pattern: settings_pattern
        )

      {_result, google_photos_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/settings")
            render_async(view)
            {:ok, view, html}
          end,
          pattern: google_photos_pattern
        )

      assert settings_count <= 1
      assert google_photos_count <= 1
      assert has_element?(view, "#admin-settings-form")
      assert has_element?(view, "#google-photos-connect")
    end
  end
end
