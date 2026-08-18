defmodule YscWeb.AdminDashboardQueryTest do
  @moduledoc """
  Query-count assertions for admin dashboard pending-application preview loading.
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Repo

  describe "pending application preview queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dashboard preview loads at most three pending users with separate count",
         %{conn: conn} do
      Repo.update_all(from(u in User, where: u.state == :pending_approval),
        set: [state: :active]
      )

      for idx <- 1..5 do
        user_fixture(%{
          state: :pending_approval,
          first_name: "Preview",
          last_name: "Applicant#{idx}",
          email: "preview-applicant-#{idx}@example.com"
        })
      end

      assert Accounts.count_pending_approval_users() == 5

      users_pattern =
        ~r/FROM "users" AS u0 WHERE \(u0\."state" = 'pending_approval'\)/i

      {_result, users_query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, _html} = live(conn, ~p"/admin")
            render_async(view)
            render(view)
          end,
          pattern: users_pattern
        )

      # One COUNT query plus one LIMIT 3 list query for pending applications.
      assert users_query_count == 2

      {:ok, view, _html} = live(conn, ~p"/admin")
      html = render_async(view) |> then(fn _ -> render(view) end)

      assert html =~ "5 pending"
      assert html =~ "Preview Applicant1"
      refute html =~ "Preview Applicant5"
    end
  end

  describe "property stats queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dashboard property stats use a single grouped bookings query", %{
      conn: conn
    } do
      bookings_pattern = ~r/FROM "bookings" AS b0.*GROUP BY b0\."property"/i

      {_result, bookings_query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, _html} = live(conn, ~p"/admin")
            render_async(view)
            render(view)
          end,
          pattern: bookings_pattern
        )

      assert bookings_query_count == 1
    end
  end

  describe "application statistics queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dashboard application statistics use a single filtered count query",
         %{
           conn: conn
         } do
      pattern = ~r/count\(u0\."id"\) FILTER \(WHERE u0\."inserted_at"/i

      {_result, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, _html} = live(conn, ~p"/admin")
            render_async(view)
            render(view)
          end,
          pattern: pattern
        )

      assert query_count == 1
    end
  end
end
