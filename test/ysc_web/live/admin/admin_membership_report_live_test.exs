defmodule YscWeb.AdminMembershipReportLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp live_report(conn, path \\ ~p"/admin/memberships/report") do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view, 5000)
    {view, html}
  end

  describe "index" do
    setup [:create_admin]

    test "renders report form and summary placeholders", %{conn: conn} do
      {_view, html} = live_report(conn)

      assert html =~ "Membership Report"
      assert html =~ ~s(name="date_from")
      assert html =~ ~s(name="date_to")
      assert html =~ "Generate report"
    end

    test "generates report for date range with pending applications", %{
      conn: conn
    } do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: DateTime.utc_now(),
        review_outcome: nil
      })

      today = Date.utc_today()
      from = Date.to_iso8601(%Date{today | day: 1})
      to = Date.to_iso8601(today)

      {_view, html} =
        live_report(conn, ~p"/admin/memberships/report?from=#{from}&to=#{to}")

      assert html =~ ~s(id="report-stat-applied")
      assert html =~ ~s(id="report-pending")
      assert html =~ user.email
    end

    test "shows error for invalid date range", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/admin/memberships/report?from=2026-05-01&to=2026-04-01")

      html = render(view)

      assert html =~ "Invalid date range"
    end

    test "download_csv pushes download event when report is loaded", %{
      conn: conn
    } do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: DateTime.utc_now(),
        review_outcome: nil
      })

      today = Date.utc_today()
      from = Date.to_iso8601(%Date{today | day: 1})
      to = Date.to_iso8601(today)

      {view, _html} =
        live_report(conn, ~p"/admin/memberships/report?from=#{from}&to=#{to}")

      render_click(view, "download_csv")

      assert_push_event(view, "download-csv", %{
        content: _content,
        filename: filename
      })

      assert filename =~ "membership-report-"
    end

    test "email_report shows success flash when report is loaded", %{conn: conn} do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: DateTime.utc_now(),
        review_outcome: nil
      })

      today = Date.utc_today()
      from = Date.to_iso8601(%Date{today | day: 1})
      to = Date.to_iso8601(today)

      {view, _html} =
        live_report(conn, ~p"/admin/memberships/report?from=#{from}&to=#{to}")

      render_click(view, "email_report")

      flash = :sys.get_state(view.pid).socket.assigns.flash
      assert Phoenix.Flash.get(flash, :info) =~ "emailed to the board"
    end
  end
end
