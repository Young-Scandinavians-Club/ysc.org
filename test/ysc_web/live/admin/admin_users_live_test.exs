defmodule YscWeb.AdminUsersLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "Admin Users" do
    setup [:create_admin]

    test "lists users", %{conn: conn} do
      user_fixture(%{first_name: "Member", last_name: "One"})

      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Users"
      assert html =~ "Member One"
    end

    test "searches users", %{conn: conn} do
      user_fixture(%{first_name: "Searchable", last_name: "User"})
      user_fixture(%{first_name: "Other", last_name: "User"})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html =
        view
        |> form("#user-search-form", %{search: %{query: "Searchable"}})
        |> render_change()

      assert html =~ "Searchable User"
      refute html =~ "Other User"
    end

    test "approves a user application", %{conn: conn} do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Approve",
          last_name: "Me"
        })

      signup_application_fixture(pending_user)

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{pending_user.id}/review")

      assert render(view) =~ "Review Application"
      assert render(view) =~ "Approve Me"

      view
      |> element("button", "Approve")
      |> render_click()

      assert_redirected(view, "/admin/users?id=#{pending_user.id}")

      # Verify user state in DB
      updated_user = Ysc.Accounts.get_user!(pending_user.id)
      assert updated_user.state == :active
    end

    test "rejects a user application", %{conn: conn} do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Reject",
          last_name: "Me"
        })

      signup_application_fixture(pending_user)

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{pending_user.id}/review")

      view
      |> element("button", "Reject")
      |> render_click()

      assert_redirected(view, "/admin/users?id=#{pending_user.id}")

      # Verify user state in DB
      updated_user = Ysc.Accounts.get_user!(pending_user.id)
      assert updated_user.state == :rejected
    end
  end
end
