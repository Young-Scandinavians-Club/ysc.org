# Tests for `YscWeb.ConductViolationReportLive` (source: `lib/ysc_web/live/violation_form_live.ex`).
defmodule YscWeb.ViolationFormLiveTest do
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "page copy" do
    test "uses plain language on the concern report form", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14155559999"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/report-conduct-violation")

      assert html =~ "Report a concern"
      assert html =~ "What happened?"
      refute html =~ "Violation Summary"
      assert html =~ "kept private"
      refute html =~ "confidentiality protocols"
    end
  end

  describe "handle_event validate and save" do
    test "validate updates the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      html =
        view
        |> form("#violation-form",
          conduct_form: %{
            "first_name" => "Sam",
            "last_name" => "Case",
            "email" => "sam@example.com",
            "phone" => "555-123-4567",
            "summary" => "Details about the incident for validation."
          }
        )
        |> render_change()

      assert html =~ "violation-form"
      assert html =~ "Incident Details"
    end

    test "submits successfully when logged in with valid data", %{conn: conn} do
      user =
        user_fixture(%{
          first_name: "Log",
          last_name: "Inuser",
          email: "logged.in.#{System.unique_integer()}@example.com",
          phone_number: "+14155559876"
        })

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      html =
        view
        |> form("#violation-form",
          conduct_form: %{
            "first_name" => user.first_name,
            "last_name" => user.last_name,
            "email" => user.email,
            "phone" => user.phone_number,
            "summary" =>
              "This is a complete summary of what happened for the report.",
            "anonymous" => "false"
          }
        )
        |> render_submit()

      assert html =~ "Thank You for Your Report"

      assert html =~
               "This is a complete summary of what happened for the report."
    end

    test "ignores forged status and user_id on logged-in submit", %{conn: conn} do
      reporter = user_fixture(%{phone_number: "+14155552222"})
      victim = user_fixture()
      conn = log_in_user(conn, reporter)

      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      render_submit(view, "save", %{
        "conduct_form" => %{
          "first_name" => reporter.first_name,
          "last_name" => reporter.last_name,
          "email" => reporter.email,
          "phone" => reporter.phone_number,
          "summary" => "LiveView submission with forged privileged fields.",
          "anonymous" => "false",
          "status" => "reviewed",
          "user_id" => victim.id
        }
      })

      report =
        Ysc.Repo.one(
          from r in Ysc.Forms.ConductViolationReport,
            where:
              r.summary == "LiveView submission with forged privileged fields.",
            order_by: [desc: r.inserted_at],
            limit: 1
        )

      assert report.status == :submitted
      assert report.user_id == reporter.id
    end

    test "returns form errors when summary is empty", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14155551111"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      html =
        view
        |> form("#violation-form",
          conduct_form: %{
            "first_name" => user.first_name,
            "last_name" => user.last_name,
            "email" => user.email,
            "phone" => user.phone_number,
            "summary" => "",
            "anonymous" => "false"
          }
        )
        |> render_submit()

      refute html =~ "Thank You for Your Report"
      assert html =~ "violation-form"
    end
  end

  describe "handle_params" do
    test "assigns request_path on patch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      render_patch(view, ~p"/report-conduct-violation")

      rendered = :sys.get_state(view.pid)
      assert rendered.socket.assigns.request_path == "/report-conduct-violation"
    end
  end
end
