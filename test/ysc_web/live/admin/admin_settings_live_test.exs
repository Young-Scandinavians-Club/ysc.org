defmodule YscWeb.AdminSettingsLiveTest do
  @moduledoc """
  Admin settings LiveView tests.

  Runs with `async: false` because connected-mount async loading and Oban PubSub
  can race with assertions when the full suite runs under CI load.
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.PropertyOutages.OutageTracker
  alias Ysc.Repo

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

  describe "Reported Outages" do
    setup [:create_admin]

    test "shows the empty state when no outages have been recorded", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Reported Outages"

      render_async(view, @settings_async_timeout)

      assert has_element?(view, "#reported-outages")
      assert has_element?(view, "#reported-outages-empty")
      refute has_element?(view, "#reported-outages-loading")
    end

    test "lists a reported outage with property, type, company, and date", %{
      conn: conn
    } do
      outage =
        insert_outage(%{
          incident_type: :internet_outage,
          property: :tahoe,
          company_name: "Optimum",
          description: "Fiber cut on Cedar Lane",
          incident_date: ~D[2026-08-20]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      render_async(view, @settings_async_timeout)

      assert has_element?(view, "#outage-row-#{outage.id}")
      assert has_element?(view, "#outage-time-#{outage.id}")
      html = render(view)
      assert html =~ "Tahoe"
      assert html =~ "internet outage"
      assert html =~ "Optimum"
      assert html =~ "Fiber cut on Cedar Lane"
      assert html =~ "August 20, 2026"
    end

    test "renders em dashes when company and description are missing", %{
      conn: conn
    } do
      outage =
        insert_outage(%{
          incident_type: :power_outage,
          property: :clear_lake,
          company_name: nil,
          description: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      render_async(view, @settings_async_timeout)

      row = element(view, "#outage-row-#{outage.id}")
      html = render(row)
      assert html =~ "Clear Lake"
      assert html =~ "power outage"
      assert html =~ "—"
    end

    test "lists the most recently reported outage first", %{conn: conn} do
      older = insert_outage(%{description: "Older reported outage"})
      newer = insert_outage(%{description: "Newer reported outage"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.update_all(from(o in OutageTracker, where: o.id == ^older.id),
        set: [inserted_at: DateTime.add(now, -120, :second)]
      )

      Repo.update_all(from(o in OutageTracker, where: o.id == ^newer.id),
        set: [inserted_at: now]
      )

      {:ok, view, _html} = live(conn, ~p"/admin/settings")
      html = render_async(view, @settings_async_timeout)

      newer_idx = :binary.match(html, "outage-row-#{newer.id}") |> elem(0)
      older_idx = :binary.match(html, "outage-row-#{older.id}") |> elem(0)
      assert newer_idx < older_idx
    end
  end

  defp insert_outage(attrs) do
    defaults = %{
      incident_id: "settings-outage-#{System.unique_integer([:positive])}",
      incident_type: :power_outage,
      property: :tahoe,
      company_name: "Liberty Utilities",
      description: "Default outage description",
      incident_date: ~D[2026-08-01]
    }

    {:ok, outage} =
      %OutageTracker{}
      |> OutageTracker.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    outage
  end
end
