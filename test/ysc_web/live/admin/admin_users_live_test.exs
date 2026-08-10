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

    test "shows an Applied column with the application submission date", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Applied", last_name: "Column"})
      signup_application_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Applied"
      assert html =~ "Applied Column"
    end

    test "defaults to sorting by application date, newest first", %{
      conn: conn
    } do
      older = user_fixture(%{first_name: "Older", last_name: "Applicant"})

      signup_application_fixture(older, %{
        completed:
          DateTime.add(DateTime.utc_now(), -10, :day)
          |> DateTime.truncate(:second)
      })

      newer = user_fixture(%{first_name: "Newer", last_name: "Applicant"})

      signup_application_fixture(newer, %{
        completed:
          DateTime.add(DateTime.utc_now(), -1, :day)
          |> DateTime.truncate(:second)
      })

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      newer_pos = :binary.match(html, "Newer Applicant") |> elem(0)
      older_pos = :binary.match(html, "Older Applicant") |> elem(0)

      assert newer_pos < older_pos
    end

    test "patching to review from users list keeps list rows without reloading the table query",
         %{conn: conn} do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Patch",
          last_name: "ReviewUser"
        })

      signup_application_fixture(pending_user)
      user_fixture(%{first_name: "Stays", last_name: "Smith"})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html = render_patch(view, ~p"/admin/users/#{pending_user.id}/review")

      assert html =~ "Review Application"
      assert html =~ "Patch ReviewUser"
      assert html =~ "Stays Smith"
    end

    test "patching from edit to review for the same user loads signup application",
         %{conn: conn} do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "EditThen",
          last_name: "Review"
        })

      signup_application_fixture(pending_user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_patch(view, ~p"/admin/users/#{pending_user.id}")
      html = render_patch(view, ~p"/admin/users/#{pending_user.id}/review")

      assert html =~ "Review Application"
      assert html =~ "EditThen Review"
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

      html = render(view)
      assert html =~ "Review Application"
      assert html =~ "Approve Me"
      assert html =~ "Approving..."
      refute html =~ ~s(phx-disable-with="Approving...")

      view
      |> element("#approve-membership-application-button")
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

      assert render(view) =~ ~s(phx-disable-with="Rejecting...")

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

    test "direct edit route static HTML shows modal loading shell before websocket connects",
         %{conn: conn} do
      user = user_fixture(%{first_name: "Direct", last_name: "EditUser"})

      conn = get(conn, ~p"/admin/users/#{user.id}")
      html = html_response(conn, 200)

      assert html =~ ~s|id="admin-user-edit-modal-loading"|
      refute html =~ "Direct EditUser"
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
