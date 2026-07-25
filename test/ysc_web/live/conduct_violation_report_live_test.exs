defmodule YscWeb.ConductViolationReportLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

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
end
