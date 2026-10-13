defmodule YscWeb.ConductViolationReportLiveTest do
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Forms.ConductViolationReport
  alias Ysc.Repo

  describe "report conduct violation page" do
    test "displays formatted phone number when user is logged in", %{conn: conn} do
      user =
        user_fixture_fast(%{
          first_name: "Jane",
          last_name: "Smith",
          phone_number: "+14155551234"
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/report-conduct-violation")

      assert html =~ "Your Contact Information"
      assert html =~ "You are submitting this report as:"
      assert html =~ "(415) 555-1234"
    end

    test "displays Not provided when logged-in user has no phone", %{conn: conn} do
      user =
        user_fixture_fast(%{
          phone_number: nil
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/report-conduct-violation")

      assert html =~ "Not provided"
    end

    test "shows contact form fields when not logged in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      assert has_element?(view, "#violation-form")
      assert has_element?(view, "input[name='conduct_form[first_name]']")
      assert has_element?(view, "input[name='conduct_form[email]']")
      assert has_element?(view, "input[name='conduct_form[phone]']")
    end
  end

  describe "handle_event save (authenticated)" do
    test "ignores forged identity fields from a signed-in reporter", %{
      conn: conn
    } do
      attacker =
        user_fixture(%{
          first_name: "Real",
          last_name: "Reporter",
          email: "real.reporter.#{System.unique_integer()}@example.com",
          phone_number: "+14155551234"
        })

      conn = log_in_user(conn, attacker)

      {:ok, view, _html} = live(conn, ~p"/report-conduct-violation")

      render_submit(view, "save", %{
        "conduct_form" => %{
          "first_name" => "Forged",
          "last_name" => "Victim",
          "email" => "forged.victim.#{System.unique_integer()}@example.com",
          "phone" => "555-0100",
          "summary" => "Please click https://evil.example/reset to confirm.",
          "anonymous" => "false"
        }
      })

      report =
        Repo.one!(
          from r in ConductViolationReport,
            order_by: [desc: r.inserted_at],
            limit: 1
        )

      assert report.user_id == attacker.id
      assert report.email == attacker.email
      assert report.first_name == "Real"
      assert report.last_name == "Reporter"
      assert report.phone == attacker.phone_number
    end
  end
end
