defmodule YscWeb.AdminMembershipsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp live_memberships(conn, path \\ ~p"/admin/memberships") do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view, 5000)
    {view, html}
  end

  describe "index" do
    setup [:create_admin]

    test "renders stat cards and type filter pills", %{conn: conn} do
      {_view, html} = live_memberships(conn)

      assert html =~ ~s(id="memberships-stat-total")
      assert html =~ ~s(id="memberships-filter-all")
      assert html =~ ~s(id="memberships-filter-single")
      assert html =~ "Total Memberships"
    end

    test "loads membership rows after async fetch completes", %{conn: conn} do
      member =
        user_fixture(%{phone_number: unique_user_phone()})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      {_view, html} = live_memberships(conn)

      refute html =~ "Loading memberships…"
      assert html =~ member.last_name
    end

    test "highlights active type filter from URL", %{conn: conn} do
      {_view, html} = live_memberships(conn, ~p"/admin/memberships?type=family")

      assert html =~ ~s(id="memberships-filter-family")
      assert html =~ "bg-blue-600 text-white"
    end
  end
end
