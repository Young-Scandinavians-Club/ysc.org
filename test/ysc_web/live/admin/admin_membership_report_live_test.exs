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
      {view, _html} = live_report(conn)

      assert has_element?(view, "h1", "Membership Report")
      assert has_element?(view, "#membership-report-form")
      assert has_element?(view, "#date_from")
      assert has_element?(view, "#date_to")
      assert has_element?(view, "#generate-report-button", "Generate report")
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

      {view, html} =
        live_report(conn, ~p"/admin/memberships/report?from=#{from}&to=#{to}")

      assert html =~ ~s(id="report-stat-applied")
      assert has_element?(view, "#report-pending")
      assert html =~ user.email
    end

    test "shows accepted applications in report output", %{conn: conn} do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: ~U[2026-03-05 10:00:00Z],
        review_outcome: "approved",
        reviewed_at: ~U[2026-03-12 10:00:00Z]
      })

      {view, html} =
        live_report(
          conn,
          ~p"/admin/memberships/report?from=2026-03-01&to=2026-03-31"
        )

      assert has_element?(view, "#report-accepted")
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

      assert has_element?(view, "#flash-mirror", "emailed to the board")
    end

    test "generate form patches to selected date range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/memberships/report")

      view
      |> form("#membership-report-form", %{
        "date_from" => "2026-02-01",
        "date_to" => "2026-02-28"
      })
      |> render_submit()

      assert_patch(
        view,
        ~p"/admin/memberships/report?from=2026-02-01&to=2026-02-28"
      )
    end

    test "shows rejected applications in report output", %{conn: conn} do
      user = user_fixture()

      signup_application_fixture(user, %{
        completed: ~U[2026-03-10 09:00:00Z],
        review_outcome: "rejected",
        reviewed_at: ~U[2026-03-18 14:00:00Z]
      })

      {view, html} =
        live_report(
          conn,
          ~p"/admin/memberships/report?from=2026-03-01&to=2026-03-31"
        )

      assert has_element?(view, "#report-rejected")
      assert html =~ user.email
      assert html =~ "Rejected"
    end

    test "shows expired subscriptions in report output", %{conn: conn} do
      user = user_fixture()
      period_end = ~U[2026-02-20 08:00:00Z]

      {:ok, _subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_live_#{System.unique_integer()}",
          stripe_status: "canceled",
          name: "Single Membership",
          current_period_end: period_end
        })

      {view, html} =
        live_report(
          conn,
          ~p"/admin/memberships/report?from=2026-02-01&to=2026-02-28"
        )

      assert has_element?(view, "#report-expired")
      assert html =~ user.email
      assert html =~ "Expired on"
    end

    test "shows purchased memberships with application details", %{conn: conn} do
      user = user_fixture()
      reviewed_at = ~U[2026-04-05 10:00:00Z]
      start_date = ~U[2026-04-06 10:00:00Z]

      signup_application_fixture(user, %{
        completed: ~U[2026-04-01 09:00:00Z],
        review_outcome: "approved",
        reviewed_at: reviewed_at,
        membership_eligibility: ["born_in_scandinavia"],
        link_to_scandinavia: "Family in Oslo"
      })

      {:ok, _subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_purchased_live_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Single Membership",
          start_date: start_date,
          current_period_end: DateTime.add(start_date, 365, :day)
        })

      {view, html} =
        live_report(
          conn,
          ~p"/admin/memberships/report?from=2026-04-01&to=2026-04-30"
        )

      assert has_element?(view, "#report-purchased")
      assert html =~ user.email
      assert html =~ "Family in Oslo"
      assert html =~ "Eligibility:"
    end

    test "download_csv is a no-op when report is not loaded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/memberships/report")

      html = render_click(view, "download_csv")
      assert html =~ "Membership Report"
    end

    test "email_report is a no-op when report is not loaded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/memberships/report")

      render_click(view, "email_report")

      refute has_element?(view, "#flash-mirror", "emailed to the board")
    end
  end

  describe "handle_async generate_report exit" do
    setup [:create_admin]

    test "handles report generation task exit without crashing", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/admin/memberships/report?from=2026-03-01&to=2026-03-31")

      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, updated_socket} =
               YscWeb.AdminMembershipReportLive.handle_async(
                 :generate_report,
                 {:exit, :test_reason},
                 socket
               )

      assert updated_socket.assigns.generating? == false

      assert updated_socket.assigns.error ==
               "Failed to generate report. Please try again."
    end
  end
end
