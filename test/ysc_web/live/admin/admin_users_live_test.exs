defmodule YscWeb.AdminUsersLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "access control" do
    test "redirects non-admin members away from users list", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users")
    end
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

      assert_patched(view, "/admin/users?id=#{pending_user.id}")

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
      |> element("button", "Reject Application...")
      |> render_click()

      view
      |> element("#reject-application-form")
      |> render_submit(%{"reject" => %{"note" => ""}})

      assert_patched(view, "/admin/users?id=#{pending_user.id}")

      # Verify user state in DB
      updated_user = Ysc.Accounts.get_user!(pending_user.id)
      assert updated_user.state == :rejected
    end

    test "submits CSV export form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html =
        view
        |> form("form[phx-submit=export-csv]", %{
          "csv_export" => %{
            "id" => "true",
            "email" => "false",
            "first_name" => "false",
            "last_name" => "false",
            "phone_number" => "false",
            "state" => "false",
            "address" => "false",
            "only_subscribers" => "false"
          }
        })
        |> render_submit()

      assert html =~ "Export" || html =~ "progress" || html =~ "spinner"
    end

    test "clear-search patches away search params", %{conn: conn} do
      _u = user_fixture(%{first_name: "Findable", last_name: "User"})

      qs = Plug.Conn.Query.encode(%{"search" => %{"query" => "Findable"}})
      {:ok, view, _html} = live(conn, "/admin/users?" <> qs)

      render_click(view, "clear-search", %{"input-id" => "user-search"})
      patched = assert_patch(view)
      refute String.contains?(patched, "search")
    end

    test "change event accepts flat search query param", %{conn: conn} do
      user_fixture(%{first_name: "FlatSearch", last_name: "Hit"})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_change(view, "change", %{"search" => "FlatSearch"})
      patched = assert_patch(view)
      assert patched =~ "FlatSearch"
    end
  end
end
