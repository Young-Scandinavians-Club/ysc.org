defmodule Ysc.NewsletterTest do
  use Ysc.DataCase

  alias Ysc.Accounts
  alias Ysc.Newsletter
  alias Ysc.Newsletter.Subscriber

  import Ysc.AccountsFixtures

  describe "subscribe/2" do
    test "creates a new subscriber with email and source" do
      assert {:ok, %Subscriber{} = s} =
               Newsletter.subscribe("new@example.com", source: "public_signup")

      assert s.email == "new@example.com"
      assert s.subscribed == true
      assert s.source == "public_signup"
      assert s.subscription_token != nil
      assert s.subscribed_at != nil
      assert s.user_id == nil
    end

    test "stores email case-insensitively (citext) - lookup matches regardless of case" do
      {:ok, s} =
        Newsletter.subscribe("User@Example.COM", source: "public_signup")

      found = Newsletter.get_subscriber_by_email("user@example.com")
      assert found != nil
      assert found.id == s.id
    end

    test "returns error for invalid email" do
      assert {:error, :invalid_email} = Newsletter.subscribe("")
      assert {:error, :invalid_email} = Newsletter.subscribe("no-at-sign")
      assert {:error, :invalid_email} = Newsletter.subscribe(nil)
    end

    test "updates existing subscriber when subscribing again (re-activates)" do
      {:ok, first} =
        Newsletter.subscribe("again@example.com", source: "public_signup")

      token = first.subscription_token

      {:ok, _} = Newsletter.unsubscribe("again@example.com")
      refute Newsletter.get_subscriber_by_email("again@example.com").subscribed

      assert {:ok, updated} =
               Newsletter.subscribe("again@example.com",
                 source: "public_signup"
               )

      assert updated.subscribed == true
      assert updated.subscription_token == token
      assert updated.unsubscribed_at == nil
    end

    test "links existing anonymous subscription when user registers (same email)" do
      {:ok, anon} =
        Newsletter.subscribe("link@example.com", source: "public_signup")

      assert anon.user_id == nil

      # Registering a user with same email triggers subscribe_user_to_newsletter,
      # which updates the existing subscriber and links user_id
      user =
        user_fixture(%{
          email: "link@example.com",
          first_name: "Link",
          last_name: "User"
        })

      linked = Newsletter.get_subscriber_by_email("link@example.com")
      assert linked.id == anon.id
      assert linked.user_id == user.id
      assert linked.source == "user_registration_linked"
      assert linked.first_name == "Link"
      assert linked.last_name == "User"
    end

    test "accepts optional metadata" do
      metadata = %{"signup_date" => "2026-01-01T00:00:00Z"}

      assert {:ok, s} =
               Newsletter.subscribe("meta@example.com",
                 source: "public_signup",
                 metadata: metadata
               )

      assert s.metadata == metadata
    end
  end

  describe "unsubscribe/1" do
    test "unsubscribes by email" do
      {:ok, _s} =
        Newsletter.subscribe("out@example.com", source: "public_signup")

      assert {:ok, updated} = Newsletter.unsubscribe("out@example.com")
      assert updated.subscribed == false
      assert updated.unsubscribed_at != nil
    end

    test "unsubscribes by token" do
      {:ok, s} =
        Newsletter.subscribe("token@example.com", source: "public_signup")

      assert {:ok, updated} = Newsletter.unsubscribe(s.subscription_token)
      assert updated.subscribed == false
    end

    test "returns not_found for unknown email" do
      assert {:error, :not_found} =
               Newsletter.unsubscribe("unknown@example.com")
    end

    test "returns not_found for unknown token" do
      assert {:error, :not_found} = Newsletter.unsubscribe("invalid-token-xyz")
    end
  end

  describe "get_subscriber_by_email/1" do
    test "returns nil for unknown email" do
      refute Newsletter.get_subscriber_by_email("nope@example.com")
    end

    test "returns subscriber for existing email" do
      {:ok, s} =
        Newsletter.subscribe("get@example.com", source: "public_signup")

      found = Newsletter.get_subscriber_by_email("get@example.com")
      assert found != nil
      assert found.id == s.id
    end
  end

  describe "get_subscriber_by_token/1" do
    test "returns nil for unknown token" do
      refute Newsletter.get_subscriber_by_token("unknown")
    end

    test "returns subscriber for valid token" do
      {:ok, s} =
        Newsletter.subscribe("tok@example.com", source: "public_signup")

      found = Newsletter.get_subscriber_by_token(s.subscription_token)
      assert found != nil
      assert found.id == s.id
    end
  end

  describe "sync_user_preference/2" do
    test "subscribes when newsletter_subscribed: true" do
      user = user_fixture()
      Newsletter.sync_user_preference(user, newsletter_subscribed: true)
      sub = Newsletter.get_subscriber_by_email(user.email)
      assert sub != nil
      assert sub.subscribed == true
      assert sub.user_id == user.id
    end

    test "unsubscribes when newsletter_subscribed: false" do
      user = user_fixture()
      # User is subscribed by default from registration
      Newsletter.sync_user_preference(user, newsletter_subscribed: false)
      sub = Newsletter.get_subscriber_by_email(user.email)
      assert sub != nil
      assert sub.subscribed == false
    end
  end

  describe "list_subscribers/1" do
    test "returns all subscribers without opts" do
      Newsletter.subscribe("a@example.com", source: "public_signup")
      Newsletter.subscribe("b@example.com", source: "public_signup")
      list = Newsletter.list_subscribers()
      assert length(list) >= 2
    end

    test "filters by subscribed: true" do
      Newsletter.subscribe("active@example.com", source: "public_signup")

      {:ok, _} =
        Newsletter.subscribe("inactive@example.com", source: "public_signup")

      Newsletter.unsubscribe("inactive@example.com")
      list = Newsletter.list_subscribers(subscribed: true)
      emails = Enum.map(list, & &1.email)
      assert "active@example.com" in emails
      refute "inactive@example.com" in emails
    end
  end

  describe "Subscriber.generate_subscription_token/0" do
    test "returns a non-empty URL-safe string" do
      token = Subscriber.generate_subscription_token()
      assert is_binary(token)
      assert byte_size(token) > 0
      refute String.contains?(token, ["+", "/", "="])
    end
  end
end
