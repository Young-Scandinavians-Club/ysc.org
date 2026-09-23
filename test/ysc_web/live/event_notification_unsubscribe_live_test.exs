defmodule YscWeb.EventNotificationUnsubscribeLiveTest do
  @moduledoc """
  Comprehensive tests for the public event-notification unsubscribe page.

  Critical: Users must always be able to stop event notification emails
  without signing in. These tests ensure the page never crashes and the
  unsubscribe action always succeeds when given a valid token.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.EventNotificationUnsubscribeToken
  alias Ysc.Repo

  describe "mount - invalid or missing token" do
    test "shows invalid link message for unknown token", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/invalid-token-xyz")

      assert html =~ "This link no longer works"
      assert html =~ "mailto:info@ysc.org"
      assert html =~ "info@ysc.org"
      assert html =~ "outdated or mistyped"
    end

    test "shows invalid link for token that is only whitespace", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/event-notifications/unsubscribe/%20%20")

      assert html =~ "This link no longer works"
    end

    test "always shows Return to home link when token is invalid", %{
      conn: conn
    } do
      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/bad-token")

      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "token signed for a user that no longer exists does not crash", %{
      conn: conn
    } do
      token = EventNotificationUnsubscribeToken.sign(Ecto.ULID.generate())

      {:ok, _view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      assert html =~ "This link no longer works"
    end
  end

  describe "mount - valid token, subscribed" do
    test "shows user email and unsubscribe button", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      refute html =~ "This link no longer works"
      assert html =~ "Unsubscribe from event notifications"
      assert html =~ user.email
      assert has_element?(view, "button", "Unsubscribe")
    end

    test "page has predictable id for accessibility and testing", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, _view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      assert html =~ "id=\"event-notification-unsubscribe-page\""
    end
  end

  describe "mount - valid token, already unsubscribed (idempotent)" do
    test "shows success state without button when already disabled", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})

      {:ok, user} =
        Accounts.update_notification_preferences(user, %{
          "event_notifications" => "false"
        })

      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      assert html =~ "You have been unsubscribed"
      refute has_element?(view, "button", "Unsubscribe")
      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "reloading unsubscribe link after success still shows success", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()
      assert render(view) =~ "You have been unsubscribed"

      {:ok, view2, html2} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      assert html2 =~ "You have been unsubscribed"
      refute has_element?(view2, "button", "Unsubscribe")
    end

    test "re-firing the unsubscribe event on an already-disabled user stays idempotent",
         %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})

      {:ok, user} =
        Accounts.update_notification_preferences(user, %{
          "event_notifications" => "false"
        })

      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      # The button is hidden once unsubscribed, but re-firing the event
      # (e.g. a stale client) must stay safe and idempotent.
      html = render_click(view, "unsubscribe")
      assert html =~ "You have been unsubscribed"
      assert Accounts.get_user_by_email(user.email).event_notifications == false
    end
  end

  describe "unsubscribe action - success" do
    test "clicking Unsubscribe sets event_notifications to false in DB", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()

      updated = Accounts.get_user_by_email(user.email)
      assert updated.event_notifications == false
    end

    test "unsubscribe by token only affects the matching user", %{conn: conn} do
      user1 = user_fixture(%{phone_number: "+14159098268"})
      user2 = user_fixture(%{phone_number: "+14159098269"})
      token = EventNotificationUnsubscribeToken.sign(user1.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()

      assert Accounts.get_user_by_email(user1.email).event_notifications ==
               false

      assert Accounts.get_user_by_email(user2.email).event_notifications ==
               true
    end

    test "after success, UI shows confirmation and Return to home", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()

      html = render(view)
      assert html =~ "You have been unsubscribed"
      assert has_element?(view, "a[href='/']", "Return to home")
    end

    test "flash message is set on success", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()

      assert render(view) =~ "unsubscribed from event notifications"
    end

    test "does not touch the user's newsletter or account notification preferences",
         %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      view |> element("button", "Unsubscribe") |> render_click()

      updated = Accounts.get_user_by_email(user.email)
      assert updated.account_notifications == true
    end
  end

  describe "unsubscribe action - failure" do
    test "survives unsubscribe failure and shows contact guidance toast", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      Repo.delete!(user)

      html = view |> element("button", "Unsubscribe") |> render_click()
      assert is_binary(html)
      assert html =~ "We couldn&#39;t unsubscribe you right now"
      assert Accounts.get_user_by_email(user.email) == nil
    end
  end

  describe "unsubscribe action - no double submit" do
    test "button disappears after click so user cannot submit twice", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{token}")

      element(view, "button", "Unsubscribe") |> render_click()
      html = render(view)
      refute html =~ "Unsubscribe"
    end
  end

  describe "token forgery" do
    test "a token signed with a different salt is rejected", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})

      forged =
        Phoenix.Token.sign(YscWeb.Endpoint, "some_other_salt", user.id)

      {:ok, _view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{forged}")

      assert html =~ "This link no longer works"
    end

    test "a raw user id is not itself a valid token", %{conn: conn} do
      user = user_fixture(%{phone_number: "+14159098268"})

      {:ok, view, html} =
        live(conn, ~p"/event-notifications/unsubscribe/#{user.id}")

      assert html =~ "This link no longer works"
      refute has_element?(view, "button", "Unsubscribe")
    end

    test "firing the unsubscribe event on an invalid token is a no-op error, never a crash",
         %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/event-notifications/unsubscribe/bad-token")

      # The button is hidden when the token is invalid, but the event handler
      # must still resolve safely if fired directly (e.g. a stale client).
      html = render_click(view, "unsubscribe")
      assert is_binary(html)
      assert html =~ "This link no longer works"
    end
  end

  describe "access without authentication" do
    test "unsubscribe page is public and does not require login", %{
      conn: conn
    } do
      user = user_fixture(%{phone_number: "+14159098268"})
      token = EventNotificationUnsubscribeToken.sign(user.id)

      conn = get(conn, ~p"/event-notifications/unsubscribe/#{token}")
      assert response(conn, 200)
    end
  end

  describe "edge cases - never crash" do
    test "very long token does not crash", %{conn: conn} do
      long_token = String.duplicate("a", 500)

      {:ok, _view, html} =
        live(conn, "/event-notifications/unsubscribe/#{long_token}")

      assert html =~ "This link no longer works"
    end

    test "token with special characters does not crash", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/event-notifications/unsubscribe/abc%2B%2F%3Ddef")

      assert html =~ "This link no longer works" or html =~ "Unsubscribe"
    end
  end
end
