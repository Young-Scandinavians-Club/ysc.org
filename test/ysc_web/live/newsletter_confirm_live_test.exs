defmodule YscWeb.NewsletterConfirmLiveTest do
  @moduledoc """
  Tests for the public double opt-in newsletter confirmation page.

  This page is what actually activates a newsletter subscription — these
  tests ensure it never crashes on a bad token and that confirming is
  idempotent (safe to reload the emailed link more than once).
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ysc.Newsletter

  describe "mount - invalid or missing token" do
    test "shows invalid link message for unknown token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/newsletter/confirm/invalid-token-xyz")

      assert html =~ "Invalid or expired link"
      assert html =~ "sign up again"
    end

    test "shows invalid link for token that is only whitespace", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/newsletter/confirm/%20%20")

      assert html =~ "Invalid or expired link"
    end

    test "always shows Return to home link when token is invalid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/newsletter/confirm/bad-token")

      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "does not create or mutate any subscriber for an unknown token", %{
      conn: conn
    } do
      {:ok, _view, _html} = live(conn, ~p"/newsletter/confirm/unknown-token-abc")

      refute Newsletter.get_subscriber_by_email("unknown-token-abc@example.com")
    end
  end

  describe "mount - valid pending token" do
    test "confirms the subscription and shows success", %{conn: conn} do
      email = "confirm-page@example.com"
      {:ok, :pending} = Newsletter.request_confirmation(email, source: "public_signup")
      pending = Newsletter.get_subscriber_by_email(email)

      {:ok, view, html} =
        live(conn, ~p"/newsletter/confirm/#{pending.confirmation_token}")

      refute html =~ "Invalid or expired link"
      assert html =~ "You&#39;re subscribed!"
      assert has_element?(view, "strong", email)

      updated = Newsletter.get_subscriber_by_email(email)
      assert updated.subscribed == true
      assert updated.confirmed_at != nil
      assert updated.subscribed_at != nil
    end

    test "page has predictable id for accessibility and testing", %{conn: conn} do
      email = "confirm-id@example.com"
      {:ok, :pending} = Newsletter.request_confirmation(email, source: "public_signup")
      pending = Newsletter.get_subscriber_by_email(email)

      {:ok, _view, html} =
        live(conn, ~p"/newsletter/confirm/#{pending.confirmation_token}")

      assert html =~ "id=\"newsletter-confirm-page\""
    end
  end

  describe "mount - valid token, already confirmed (idempotent)" do
    test "revisiting the same link after confirming still shows success", %{
      conn: conn
    } do
      email = "confirm-again@example.com"
      {:ok, :pending} = Newsletter.request_confirmation(email, source: "public_signup")
      pending = Newsletter.get_subscriber_by_email(email)

      {:ok, _view, _html} =
        live(conn, ~p"/newsletter/confirm/#{pending.confirmation_token}")

      first_confirmed_at = Newsletter.get_subscriber_by_email(email).confirmed_at

      {:ok, _view2, html2} =
        live(conn, ~p"/newsletter/confirm/#{pending.confirmation_token}")

      assert html2 =~ "You&#39;re subscribed!"

      second_confirmed_at = Newsletter.get_subscriber_by_email(email).confirmed_at
      assert DateTime.compare(second_confirmed_at, first_confirmed_at) == :eq
    end
  end

  describe "access without authentication" do
    test "confirm page is public and does not require login", %{conn: conn} do
      email = "confirm-public@example.com"
      {:ok, :pending} = Newsletter.request_confirmation(email, source: "public_signup")
      pending = Newsletter.get_subscriber_by_email(email)

      conn = get(conn, ~p"/newsletter/confirm/#{pending.confirmation_token}")
      assert response(conn, 200)
    end
  end

  describe "edge cases - never crash" do
    test "very long token does not crash", %{conn: conn} do
      long_token = String.duplicate("a", 500)

      {:ok, _view, html} = live(conn, "/newsletter/confirm/#{long_token}")

      assert html =~ "Invalid or expired link"
    end

    test "token with special characters does not crash", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/newsletter/confirm/abc%2B%2F%3Ddef")

      assert html =~ "Invalid or expired link" or html =~ "You&#39;re subscribed!"
    end
  end
end
