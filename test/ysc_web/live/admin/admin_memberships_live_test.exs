defmodule YscWeb.AdminMembershipsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "index" do
    setup [:create_admin]

    test "renders stat cards and type filter pills", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/memberships")

      assert has_element?(view, "#memberships-stat-total")
      assert has_element?(view, "#memberships-filter-all")
      assert has_element?(view, "#memberships-filter-single")
      assert render(view) =~ "Total Memberships"
    end

    test "highlights active type filter from URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/memberships?type=family")

      html = render(view)
      assert html =~ ~s(id="memberships-filter-family")
      assert html =~ "bg-blue-600 text-white"
    end
  end
end
