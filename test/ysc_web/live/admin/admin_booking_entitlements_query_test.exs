defmodule YscWeb.AdminBookingEntitlementsQueryTest do
  @moduledoc """
  Query-count assertions for admin outstanding booking entitlements.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Bookings.Entitlements
  alias Money

  describe "outstanding entitlements queries" do
    setup %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "dead render does not query entitlements before connect", %{
      conn: conn,
      admin: admin
    } do
      member = user_fixture(%{first_name: "Dead", last_name: "Render"})

      {:ok, _} =
        Entitlements.create_entitlement(
          %{
            user_id: member.id,
            issued_by_user_id: admin.id,
            benefit_kind: :fixed_amount_off,
            amount_off: Money.new(:USD, 10)
          },
          send_notification: false
        )

      entitlements_pattern = ~r/FROM "booking_entitlements"/i

      {html, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            conn
            |> get(~p"/admin/bookings/entitlements")
            |> html_response(200)
          end,
          pattern: entitlements_pattern,
          caller_pids: [self()]
        )

      assert query_count == 0
      assert html =~ "Loading entitlements…"
      refute html =~ "Dead Render"
    end

    test "connected list loads outstanding entitlements once after connect", %{
      conn: conn,
      admin: admin
    } do
      member = user_fixture(%{first_name: "Slim", last_name: "Member"})

      {:ok, _} =
        Entitlements.create_entitlement(
          %{
            user_id: member.id,
            issued_by_user_id: admin.id,
            benefit_kind: :fixed_amount_off,
            amount_off: Money.new(:USD, 10)
          },
          send_notification: false
        )

      {{:ok, view, _html}, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/admin/bookings/entitlements")
            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/FROM "booking_entitlements"/i
        )

      assert query_count == 1
      assert render(view) =~ "Slim Member"
    end
  end
end
