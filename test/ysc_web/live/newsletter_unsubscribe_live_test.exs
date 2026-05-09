defmodule YscWeb.NewsletterUnsubscribeLiveTest do
  @moduledoc """
  Comprehensive tests for the public newsletter unsubscribe page.

  Critical: Users must always be able to remove their email from the newsletter
  list. These tests ensure the page never crashes and the unsubscribe action
  always succeeds when given a valid token.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ysc.Newsletter

  describe "mount - invalid or missing token" do
    test "shows invalid link message for unknown token", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/newsletter/unsubscribe/invalid-token-xyz")

      assert html =~ "Invalid or expired link"
      assert html =~ "please contact us"
    end

    test "shows invalid link for token that is only whitespace", %{conn: conn} do
      # Route would need to allow this; if URL is /newsletter/unsubscribe/%20%20 we get spaces
      {:ok, _view, html} =
        live(conn, "/newsletter/unsubscribe/%20%20")

      assert html =~ "Invalid or expired link"
    end

    test "always shows Return to home link when token is invalid", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/bad-token")

      assert has_element?(view, "a[href='/']", "Return to home")
    end
  end

  describe "mount - valid token, subscribed" do
    test "shows subscriber email and unsubscribe button", %{conn: conn} do
      {:ok, sub} =
        Newsletter.subscribe("unsub@example.com", source: "public_signup")

      {:ok, view, html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      refute html =~ "Invalid or expired link"
      assert html =~ "Unsubscribe from our newsletter"
      assert has_element?(view, "button", "Unsubscribe")
    end

    test "properly interpolates and displays the subscriber's email address", %{
      conn: conn
    } do
      test_email = "test.user@example.com"

      {:ok, sub} =
        Newsletter.subscribe(test_email, source: "public_signup")

      {:ok, view, html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      # Verify the email is properly interpolated in the HTML
      assert html =~ "You are subscribed as"
      assert html =~ test_email

      # Verify it appears within a strong tag for emphasis
      assert html =~ "<strong>#{test_email}</strong>"

      # Also verify through element selector
      assert has_element?(view, "strong", test_email)
    end

    test "displays email correctly with special characters", %{conn: conn} do
      # Test email with plus addressing and dots; example.com has a null MX
      # record so it passes validation while keeping focus on the local-part.
      test_email = "user.name+tag@example.com"

      {:ok, sub} =
        Newsletter.subscribe(test_email, source: "public_signup")

      {:ok, _view, html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      # Ensure special characters are properly displayed (not HTML-escaped or broken)
      assert html =~ test_email
      assert html =~ "<strong>#{test_email}</strong>"
    end

    test "page has predictable id for accessibility and testing", %{conn: conn} do
      {:ok, sub} =
        Newsletter.subscribe("id-check@example.com", source: "public_signup")

      {:ok, _view, html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      assert html =~ "id=\"newsletter-unsubscribe-page\""
    end
  end

  describe "mount - valid token, already unsubscribed (idempotent)" do
    test "shows success state without button when subscriber already unsubscribed",
         %{
           conn: conn
         } do
      {:ok, sub} =
        Newsletter.subscribe("already-out@example.com", source: "public_signup")

      Newsletter.unsubscribe(sub.subscription_token)

      {:ok, view, html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      assert html =~ "You have been unsubscribed"
      refute has_element?(view, "button", "Unsubscribe")
      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "reloading unsubscribe link after success still shows success (no form)",
         %{
           conn: conn
         } do
      {:ok, sub} =
        Newsletter.subscribe("reload@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      view |> element("button", "Unsubscribe") |> render_click()
      assert render(view) =~ "You have been unsubscribed"

      # Simulate user revisiting the same link (e.g. from email again)
      {:ok, view2, html2} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      assert html2 =~ "You have been unsubscribed"
      refute has_element?(view2, "button", "Unsubscribe")
    end
  end

  describe "unsubscribe action - success" do
    test "clicking Unsubscribe sets subscribed to false in DB", %{conn: conn} do
      {:ok, sub} =
        Newsletter.subscribe("db-check@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      view |> element("button", "Unsubscribe") |> render_click()

      updated = Newsletter.get_subscriber_by_email("db-check@example.com")
      assert updated.subscribed == false
      assert updated.unsubscribed_at != nil
    end

    test "after success, UI shows confirmation and Return to home", %{
      conn: conn
    } do
      {:ok, sub} =
        Newsletter.subscribe("success-ui@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      view |> element("button", "Unsubscribe") |> render_click()

      html = render(view)
      assert html =~ "You have been unsubscribed"
      assert html =~ "You will no longer receive our newsletter"
      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "unsubscribe by token only affects the matching subscriber", %{
      conn: conn
    } do
      {:ok, sub1} =
        Newsletter.subscribe("first@example.com", source: "public_signup")

      {:ok, _sub2} =
        Newsletter.subscribe("second@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub1.subscription_token}")

      view |> element("button", "Unsubscribe") |> render_click()

      assert Newsletter.get_subscriber_by_email("first@example.com").subscribed ==
               false

      assert Newsletter.get_subscriber_by_email("second@example.com").subscribed ==
               true
    end

    test "flash message is set on success", %{conn: conn} do
      {:ok, sub} =
        Newsletter.subscribe("flash@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      view |> element("button", "Unsubscribe") |> render_click()

      assert render(view) =~ "unsubscribed from our newsletter"
    end
  end

  describe "unsubscribe action - no double submit" do
    test "button disappears after click so user cannot submit twice", %{
      conn: conn
    } do
      {:ok, sub} =
        Newsletter.subscribe("double@example.com", source: "public_signup")

      {:ok, view, _html} =
        live(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")

      element(view, "button", "Unsubscribe") |> render_click()
      html = render(view)
      refute html =~ "Unsubscribe"
    end
  end

  describe "access without authentication" do
    test "unsubscribe page is public and does not require login", %{conn: conn} do
      {:ok, sub} =
        Newsletter.subscribe("public@example.com", source: "public_signup")

      conn = get(conn, ~p"/newsletter/unsubscribe/#{sub.subscription_token}")
      assert response(conn, 200)
    end
  end

  describe "edge cases - never crash" do
    test "very long token does not crash", %{conn: conn} do
      long_token = String.duplicate("a", 500)

      {:ok, _view, html} =
        live(conn, "/newsletter/unsubscribe/#{long_token}")

      assert html =~ "Invalid or expired link"
    end

    test "token with special characters does not crash", %{conn: conn} do
      # URL-encoded characters that might appear in a token
      {:ok, _view, html} =
        live(conn, "/newsletter/unsubscribe/abc%2B%2F%3Ddef")

      # Either invalid link or, if that happens to match a token, we handle it
      assert html =~ "Invalid or expired link" or html =~ "Unsubscribe"
    end
  end
end
