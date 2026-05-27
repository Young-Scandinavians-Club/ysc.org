defmodule YscWeb.Emails.HelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.Emails.Helpers

  describe "member_greeting_name/1" do
    test "returns Valued Member for nil, blank, or whitespace-only" do
      assert Helpers.member_greeting_name(nil) == "Valued Member"
      assert Helpers.member_greeting_name("") == "Valued Member"
      assert Helpers.member_greeting_name("   ") == "Valued Member"
    end

    test "returns trimmed name for binary input" do
      assert Helpers.member_greeting_name("  Anna  ") == "Anna"
    end

    test "reads :first_name from maps and structs" do
      assert Helpers.member_greeting_name(%{first_name: "Bo"}) == "Bo"
      assert Helpers.member_greeting_name(%{first_name: nil}) == "Valued Member"
      assert Helpers.member_greeting_name(%{first_name: ""}) == "Valued Member"
    end

    test "defaults for maps without first_name" do
      assert Helpers.member_greeting_name(%{}) == "Valued Member"
    end

    test "defaults for unexpected types" do
      assert Helpers.member_greeting_name(:atom) == "Valued Member"
    end
  end

  describe "origin/0 and absolute_url/1" do
    test "absolute_url appends a path to the endpoint origin" do
      origin = YscWeb.Endpoint.url()
      assert Helpers.origin() == origin
      id = "evt-id-123"
      assert Helpers.absolute_url("/events/#{id}") == origin <> "/events/#{id}"
    end
  end

  describe "site URL helpers" do
    test "membership_url/0, upcoming_events_url/0, payment_methods_url/0, news_url/0, and home_url/0" do
      origin = YscWeb.Endpoint.url()

      assert Helpers.membership_url() == origin <> "/users/membership"
      assert Helpers.upcoming_events_url() == origin <> "/events"
      assert Helpers.payment_methods_url() == origin <> "/users/payment-methods"
      assert Helpers.news_url() == origin <> "/news"
      assert Helpers.home_url() == origin <> "/"
    end
  end

  describe "membership_payment_reminder_data/1" do
    test "builds reminder assigns for a user" do
      origin = YscWeb.Endpoint.url()
      user = %{first_name: "Anna"}

      assert Helpers.membership_payment_reminder_data(user) == %{
               first_name: "Anna",
               pay_membership_url: origin <> "/users/membership",
               upcoming_events_url: origin <> "/events"
             }
    end

    test "raises when user is nil" do
      assert_raise ArgumentError, "User cannot be nil", fn ->
        Helpers.membership_payment_reminder_data(nil)
      end
    end
  end
end
