defmodule YscWeb.NewsletterComponentsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.NewsletterComponents

  describe "newsletter_subscribe_form/1" do
    test "renders email field, subscribe button, and form id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_subscribe_form
          id="home-newsletter-form"
          email="guest@example.com"
        />
        """)

      assert html =~ ~s(id="home-newsletter-form")
      assert html =~ ~s(phx-submit="subscribe_newsletter")
      assert html =~ ~s(id="newsletter-email")
      assert html =~ ~s(value="guest@example.com")
      assert html =~ "Subscribe"
      refute html =~ ~s(id="newsletter-error")
      refute html =~ "one step away"
    end

    test "shows error alert and disables submit on success state" do
      assigns = %{}

      error_html =
        rendered_to_string(~H"""
        <.newsletter_subscribe_form
          id="newsletter-subscribe-form"
          error="Please enter a valid email address."
        />
        """)

      assert error_html =~ ~s(id="newsletter-error")
      assert error_html =~ "Please enter a valid email address."
      assert error_html =~ ~s(role="alert")
      assert error_html =~ "Subscribe"

      submitted_html =
        rendered_to_string(~H"""
        <.newsletter_subscribe_form id="newsletter-subscribe-form" submitted />
        """)

      assert submitted_html =~ "Check your email to confirm your subscription"
      refute submitted_html =~ ">Subscribe<"
    end

    test "renders optional footer slot and labelledby" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_subscribe_form
          id="home-newsletter-form"
          labelledby="newsletter-heading"
          describedby="newsletter-privacy-footer"
        >
          <:footer>
            <p id="newsletter-privacy-footer">privacy policy</p>
          </:footer>
        </.newsletter_subscribe_form>
        """)

      assert html =~ ~s(aria-labelledby="newsletter-heading")
      assert html =~ ~s(aria-describedby="newsletter-privacy-footer")
      assert html =~ ~s(id="newsletter-privacy-footer")
      assert html =~ "privacy policy"
    end
  end

  describe "newsletter_member_status/1" do
    test "card layout uses the archive copy and toggle event" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_member_status
          id="newsletter-member-status"
          subscribed={false}
          event="toggle_subscription"
        />
        """)

      assert html =~ ~s(id="newsletter-member-status")
      assert html =~ "You&#39;re not subscribed"
      assert html =~ ~s(phx-click="toggle_subscription")
      assert html =~ "Subscribe"
      assert html =~ "rounded-xl border"
    end

    test "compact layout uses the dashboard copy when subscribed" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_member_status
          id="home-newsletter-member-status"
          subscribed
          layout={:compact}
        />
        """)

      assert html =~ ~s(id="home-newsletter-member-status")
      assert html =~ "Subscribed"
      assert html =~ "You&#39;ll get new newsletters"
      assert html =~ "Unsubscribe"
      assert html =~ ~s(phx-click="toggle_newsletter_subscription")
      refute html =~ "rounded-xl border"
    end

    test "compact layout shows subscribe CTA when not subscribed" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_member_status
          id="home-newsletter-member-status"
          subscribed={false}
          layout={:compact}
        />
        """)

      assert html =~ "Not subscribed"
      assert html =~ "Get news"
      assert html =~ "Subscribe"
      assert html =~ "hero-envelope"
    end

    test "card layout shows subscribed copy" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.newsletter_member_status id="newsletter-member-status" subscribed />
        """)

      assert html =~ "You&#39;re subscribed"
      assert html =~ "Unsubscribe"
      assert html =~ "rounded-xl border"
    end
  end
end
