defmodule YscWeb.Admin.AdminBookingsLiveTest do
  @moduledoc """
  Tests for AdminBookingsLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Bookings" do
    setup [:create_admin]

    test "renders bookings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/bookings")
      assert html =~ "Bookings"
      assert html =~ "Calendar"
    end

    test "filters by property", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=clear_lake")
      assert render(view) =~ "Clear Lake"

      {:ok, view, _html} = live(conn, ~p"/admin/bookings?property=tahoe")
      assert render(view) =~ "Lake Tahoe"
    end

    test "navigates to configuration section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings")

      view
      |> element("button", "Configuration")
      |> render_click()

      assert render(view) =~ "Door Codes"
      assert render(view) =~ "Seasons"
      assert render(view) =~ "Pricing Rules"
    end

    test "opens new pricing rule modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/bookings?section=config")

      view
      |> element("button", "New Pricing Rule")
      |> render_click()

      assert_redirected(
        view,
        "/admin/bookings/pricing-rules/new?property=tahoe&section=config"
      )
    end
  end
end
