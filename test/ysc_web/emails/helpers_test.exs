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
      assert Helpers.security_settings_url() ==
               origin <> "/users/settings/security"
      assert Helpers.news_url() == origin <> "/news"
      assert Helpers.home_url() == origin <> "/"
    end
  end

  describe "sign-in email helpers" do
    test "sign_in_method_label/1 maps auth methods to member-facing labels" do
      assert Helpers.sign_in_method_label(%{metadata: %{"auth_method" => "passkey"}}) ==
               "Passkey"

      assert Helpers.sign_in_method_label(%{metadata: %{auth_method: "google"}}) ==
               "Google"

      assert Helpers.sign_in_method_label(%{
               metadata: %{"auth_method" => "oauth"}
             }) ==
               "Google or Facebook"

      assert Helpers.sign_in_method_label(%{metadata: %{}}) == "Sign-in"
      assert Helpers.sign_in_method_label(%{}) == "Sign-in"
    end

    test "sign_in_device_description/1 formats browser and OS" do
      assert Helpers.sign_in_device_description(%{
               browser: "Chrome",
               operating_system: "macOS"
             }) == "Chrome on macOS"

      assert Helpers.sign_in_device_description(%{
               browser: nil,
               operating_system: nil
             }) ==
               "Unknown browser on Unknown OS"
    end

    test "sign_in_location/1 prefers geo labels and falls back to IP" do
      assert Helpers.sign_in_location(%{
               city: "Stockholm",
               region: "Stockholm",
               country: "SE",
               ip_address: "24.206.103.29"
             }) == "Stockholm, Stockholm, SE (24.206.103.29)"

      assert Helpers.sign_in_location(%{
               city: nil,
               region: nil,
               country: nil,
               ip_address: "203.0.113.1"
             }) == "203.0.113.1"

      assert Helpers.sign_in_location(%{
               city: nil,
               region: nil,
               country: nil,
               ip_address: nil
             }) == "Unknown location"
    end
  end

  describe "format_date/1" do
    test "formats dates and datetimes" do
      assert Helpers.format_date(~D[2026-01-15]) == "January 15, 2026"

      assert Helpers.format_date(~U[2026-01-15 12:00:00Z]) ==
               "January 15, 2026"
    end

    test "returns default for nil and unsupported values" do
      assert Helpers.format_date(nil) == "N/A"
      assert Helpers.format_date(nil, "—") == "—"
      assert Helpers.format_date(:invalid) == "N/A"
    end
  end

  describe "format_datetime/1" do
    test "formats datetimes in Pacific time" do
      datetime = ~U[2026-01-15 20:30:00Z]

      assert Helpers.format_datetime(datetime) =~ "January 15, 2026"

      assert Helpers.format_datetime(datetime) =~ "PST" or
               Helpers.format_datetime(datetime) =~ "PDT"
    end

    test "returns default for nil and unsupported values" do
      assert Helpers.format_datetime(nil) == "N/A"
      assert Helpers.format_datetime(:invalid) == "N/A"
    end
  end

  describe "format_event_start_datetime/2" do
    test "formats wall-clock Pacific time without UTC conversion" do
      result =
        Helpers.format_event_start_datetime(
          ~U[2026-07-15 00:00:00Z],
          ~T[17:00:00]
        )

      assert result =~ "July 15, 2026"
      assert result =~ "5:00 PM"
      assert result =~ "PDT"
      refute result =~ "10:00 AM"
    end

    test "formats date only when start_time is nil" do
      result =
        Helpers.format_event_start_datetime(~U[2026-07-15 00:00:00Z], nil)

      assert result == "July 15, 2026"
      refute result =~ " at "
    end

    test "returns default when start_date is nil" do
      assert Helpers.format_event_start_datetime(nil, ~T[17:00:00]) == nil

      assert Helpers.format_event_start_datetime(nil, ~T[17:00:00], "TBD") ==
               "TBD"
    end
  end

  describe "plain_text_from_html/1" do
    test "strips tags and decodes HTML entities" do
      assert Helpers.plain_text_from_html("At Tupper &amp; Reed") ==
               "At Tupper & Reed"

      assert Helpers.plain_text_from_html("<p>Hello <strong>world</strong></p>") ==
               "Hello world"
    end

    test "returns nil for nil and empty input" do
      assert Helpers.plain_text_from_html(nil) == nil
      assert Helpers.plain_text_from_html("") == nil
    end
  end

  describe "format_money/1" do
    test "formats money with comma separators and two decimals" do
      money = Money.new(:USD, "1234.50")
      assert Helpers.format_money(money) == "$1,234.50"
    end

    test "returns default for nil and non-money values" do
      assert Helpers.format_money(nil) == "$0.00"
      assert Helpers.format_money("invalid") == "$0.00"
      assert Helpers.format_money(nil, "N/A") == "N/A"
    end
  end

  describe "format_membership_money/1" do
    test "formats money using Money default string style" do
      money = Money.new(:USD, "99.00")
      assert Helpers.format_membership_money(money) == "$99.00"
    end

    test "returns default for nil and non-money values" do
      assert Helpers.format_membership_money(nil) == "N/A"
      assert Helpers.format_membership_money(:invalid) == "N/A"
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
        Ysc.Test.Invoke.call(Helpers, :membership_payment_reminder_data, [nil])
      end
    end
  end
end
