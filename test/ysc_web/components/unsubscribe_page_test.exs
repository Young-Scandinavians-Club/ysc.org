defmodule YscWeb.Components.UnsubscribePageTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "unsubscribe_page/1" do
    test "renders the subscribed state with email, button, and required ids" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="newsletter-unsubscribe-page"
          email="member@example.com"
          unsubscribed={false}
          subscribed_title="Unsubscribe from our newsletter"
          subscribed_action="our newsletter"
          unsubscribed_body="You will no longer receive our newsletter."
          still_receive="our newsletter"
        />
        """)

      assert html =~ ~s(id="newsletter-unsubscribe-page")
      assert html =~ ~s(id="newsletter-unsubscribe-page-button")
      assert html =~ "Unsubscribe from our newsletter"
      assert html =~ "<strong>member@example.com</strong>"
      assert html =~ "stop receiving our newsletter"
      assert html =~ "Unsubscribe"
      refute html =~ "You have been unsubscribed"
      refute html =~ "This link no longer works"
      refute html =~ "Return to home"
    end

    test "renders the already-unsubscribed state with a home link" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="event-notification-unsubscribe-page"
          email="member@example.com"
          unsubscribed={true}
          subscribed_title="Unsubscribe from event notifications"
          subscribed_action="event notification emails"
          unsubscribed_body="You will no longer receive event notification emails. You can turn them back on anytime from your notification settings."
          still_receive="event notifications"
        />
        """)

      assert html =~ ~s(id="event-notification-unsubscribe-page")
      assert html =~ ~s(id="event-notification-unsubscribe-page-home")
      assert html =~ "You have been unsubscribed"
      assert html =~ "You will no longer receive event notification emails"
      assert html =~ "Return to home"
      assert html =~ ~s(href="/")
      refute html =~ "Unsubscribe from event notifications"
      refute html =~ ~s(id="event-notification-unsubscribe-page-button")
      refute html =~ "This link no longer works"
    end

    test "renders the invalid-link state when email is missing" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="newsletter-unsubscribe-page"
          unsubscribed={false}
          subscribed_title="Unsubscribe from our newsletter"
          subscribed_action="our newsletter"
          unsubscribed_body="You will no longer receive our newsletter."
          still_receive="our newsletter"
        />
        """)

      assert html =~ "This link no longer works"
      assert html =~ "outdated or mistyped"
      assert html =~ "If you still receive our newsletter"
      assert html =~ ~s(href="mailto:info@ysc.org")
      assert html =~ "info@ysc.org"
      assert html =~ "Return to home"
      refute html =~ "Unsubscribe from our newsletter"
      refute html =~ ~s(id="newsletter-unsubscribe-page-button")
    end

    test "treats a blank email as the invalid-link state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="event-notification-unsubscribe-page"
          email="   "
          unsubscribed={false}
          subscribed_title="Unsubscribe from event notifications"
          subscribed_action="event notification emails"
          unsubscribed_body="You will no longer receive event notification emails."
          still_receive="event notifications"
        />
        """)

      assert html =~ "This link no longer works"
      assert html =~ "If you still receive event notifications"
      refute html =~ "Unsubscribe from event notifications"
    end

    test "HTML-escapes the recipient email" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="newsletter-unsubscribe-page"
          email="a<b>@example.com"
          unsubscribed={false}
          subscribed_title="Unsubscribe from our newsletter"
          subscribed_action="our newsletter"
          unsubscribed_body="You will no longer receive our newsletter."
          still_receive="our newsletter"
        />
        """)

      assert html =~ "a&lt;b&gt;@example.com"
      refute html =~ "a<b>@example.com"
    end

    test "uses a custom unsubscribe event name on the button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.unsubscribe_page
          id="newsletter-unsubscribe-page"
          email="member@example.com"
          unsubscribed={false}
          subscribed_title="Unsubscribe from our newsletter"
          subscribed_action="our newsletter"
          unsubscribed_body="You will no longer receive our newsletter."
          still_receive="our newsletter"
          unsubscribe_event="confirm-unsubscribe"
        />
        """)

      assert html =~ ~s(phx-click="confirm-unsubscribe")
    end
  end
end
