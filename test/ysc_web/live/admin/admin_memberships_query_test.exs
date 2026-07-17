defmodule YscWeb.AdminMembershipsQueryTest do
  @moduledoc """
  Query-count assertions for admin memberships page loading.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo

  describe "memberships page queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dead render skips membership queries and shows loading skeleton", %{
      conn: conn
    } do
      user_fixture(%{phone_number: unique_user_phone()})
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

      users_pattern = ~r/FROM "users"/i

      {html, users_query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get("/admin/memberships")
            |> html_response(200)
          end,
          pattern: users_pattern
        )

      assert users_query_count == 0
      assert html =~ ~s|id="memberships-stat-total"|
      assert html =~ "—"
    end

    test "connected load batches subscription preloads for the bounded page", %{
      conn: conn
    } do
      for _ <- 1..8 do
        user_fixture(%{phone_number: unique_user_phone()})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()
      end

      subscription_preload_pattern = ~r/FROM "subscriptions".*user_id.*ANY/i

      {_result, subscription_preload_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, _html} = live(conn, ~p"/admin/memberships")
            render_async(view)
            render(view)
          end,
          pattern: subscription_preload_pattern
        )

      assert subscription_preload_count <= 2
    end
  end
end
