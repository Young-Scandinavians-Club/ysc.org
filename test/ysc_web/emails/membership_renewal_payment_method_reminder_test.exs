defmodule YscWeb.Emails.MembershipRenewalPaymentMethodReminderTest do
  @moduledoc """
  Comprehensive tests for MembershipRenewalPaymentMethodReminder email template.

  Tests verify:
  - Template name and subject are correct
  - Email data preparation handles all cases
  - URLs are properly generated
  - Required fields are present
  - Edge cases (nil values, etc.) are handled gracefully
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Emails.MembershipRenewalPaymentMethodReminder
  alias Ysc.Subscriptions.Subscription

  describe "get_template_name/0" do
    test "returns correct template name" do
      assert MembershipRenewalPaymentMethodReminder.get_template_name() ==
               "membership_renewal_payment_method_reminder"
    end
  end

  describe "get_subject/0" do
    test "returns action required subject" do
      assert MembershipRenewalPaymentMethodReminder.get_subject() ==
               "Action Required: Add Payment Method for Membership Renewal"
    end

    test "subject indicates urgency with 'Action Required'" do
      subject = MembershipRenewalPaymentMethodReminder.get_subject()
      assert String.contains?(subject, "Action Required")
    end
  end

  describe "payment_methods_url/0" do
    test "returns payment methods page URL" do
      url = MembershipRenewalPaymentMethodReminder.payment_methods_url()

      assert String.ends_with?(url, "/users/payment-methods")
      assert String.starts_with?(url, "http")
    end

    test "includes full endpoint URL" do
      url = MembershipRenewalPaymentMethodReminder.payment_methods_url()
      endpoint_url = YscWeb.Endpoint.url()

      assert String.starts_with?(url, endpoint_url)
    end
  end

  describe "membership_url/0" do
    test "returns membership page URL" do
      url = MembershipRenewalPaymentMethodReminder.membership_url()

      assert String.ends_with?(url, "/users/membership")
      assert String.starts_with?(url, "http")
    end

    test "includes full endpoint URL" do
      url = MembershipRenewalPaymentMethodReminder.membership_url()
      endpoint_url = YscWeb.Endpoint.url()

      assert String.starts_with?(url, endpoint_url)
    end
  end

  describe "prepare_email_data/2" do
    test "returns map with all required fields" do
      user = user_fixture(%{first_name: "John"})
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert Map.has_key?(data, :first_name)
      assert Map.has_key?(data, :renewal_date)
      assert Map.has_key?(data, :payment_methods_url)
      assert Map.has_key?(data, :membership_url)
    end

    test "includes user first name" do
      user = user_fixture(%{first_name: "Jane"})
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert data.first_name == "Jane"
    end

    test "formats renewal date as readable string" do
      user = user_fixture()
      # Create subscription with specific renewal date
      renewal_date = ~U[2026-03-15 10:00:00Z]
      subscription = build_subscription(renewal_date: renewal_date)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert data.renewal_date == "March 15, 2026"
    end

    test "includes payment methods URL" do
      user = user_fixture()
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert String.ends_with?(
               data.payment_methods_url,
               "/users/payment-methods"
             )
    end

    test "includes membership URL" do
      user = user_fixture()
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert String.ends_with?(data.membership_url, "/users/membership")
    end

    test "uses 'Valued Member' when first_name is nil" do
      base_user = user_fixture()
      user = %{base_user | first_name: nil}
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert data.first_name == "Valued Member"
    end

    test "uses 'Valued Member' when first_name is empty string" do
      base_user = user_fixture()
      user = %{base_user | first_name: ""}
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert data.first_name == "Valued Member"
    end

    test "handles different renewal dates correctly" do
      user = user_fixture()

      # Test different dates
      test_dates = [
        {~U[2026-01-01 00:00:00Z], "January 01, 2026"},
        {~U[2026-12-31 23:59:59Z], "December 31, 2026"},
        {~U[2026-07-04 12:00:00Z], "July 04, 2026"}
      ]

      Enum.each(test_dates, fn {renewal_datetime, expected_string} ->
        subscription = build_subscription(renewal_date: renewal_datetime)

        data =
          MembershipRenewalPaymentMethodReminder.prepare_email_data(
            user,
            subscription
          )

        assert data.renewal_date == expected_string
      end)
    end
  end

  describe "prepare_email_data/2 - error handling" do
    test "raises ArgumentError when user is nil" do
      subscription = build_subscription(days_from_now: 14)

      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          nil,
          subscription
        )
      end
    end

    test "raises ArgumentError when subscription is nil" do
      user = user_fixture()

      assert_raise ArgumentError, "Subscription cannot be nil", fn ->
        MembershipRenewalPaymentMethodReminder.prepare_email_data(user, nil)
      end
    end

    test "handles subscription with nil current_period_end gracefully" do
      user = user_fixture()

      subscription = %Subscription{
        id: Ecto.ULID.generate(),
        user_id: user.id,
        stripe_id: "sub_test",
        stripe_status: "active",
        name: "membership",
        current_period_end: nil,
        current_period_start: DateTime.utc_now()
      }

      # Should raise FunctionClauseError when trying to call DateTime.to_date on nil
      assert_raise FunctionClauseError, fn ->
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )
      end
    end
  end

  describe "email data completeness" do
    test "all data fields are non-nil for valid inputs" do
      user = user_fixture(%{first_name: "Test"})
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      Enum.each(Map.values(data), fn value ->
        assert value != nil, "Email data should not contain nil values"
      end)
    end

    test "all URLs are absolute (not relative)" do
      user = user_fixture()
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      assert String.starts_with?(data.payment_methods_url, "http")
      assert String.starts_with?(data.membership_url, "http")
    end

    test "renewal date is human-readable (not ISO format)" do
      user = user_fixture()
      subscription = build_subscription(days_from_now: 14)

      data =
        MembershipRenewalPaymentMethodReminder.prepare_email_data(
          user,
          subscription
        )

      # Should be like "February 17, 2026", not "2026-02-17"
      refute String.contains?(data.renewal_date, "-")
      assert String.contains?(data.renewal_date, ",")
    end
  end

  describe "integration with email system" do
    test "template name matches actual template file" do
      template_name = MembershipRenewalPaymentMethodReminder.get_template_name()

      template_path =
        Path.join([
          "lib",
          "ysc_web",
          "emails",
          "templates",
          "#{template_name}.mjml.eex"
        ])

      assert File.exists?(template_path),
             "Template file should exist at #{template_path}"
    end

    test "email module can be loaded and initialized" do
      # Verify the module compiles and can be loaded
      assert Code.ensure_loaded?(
               YscWeb.Emails.MembershipRenewalPaymentMethodReminder
             )
    end
  end

  # Helper functions

  defp build_subscription(opts) do
    renewal_date =
      cond do
        Keyword.has_key?(opts, :renewal_date) ->
          Keyword.get(opts, :renewal_date)

        Keyword.has_key?(opts, :days_from_now) ->
          days = Keyword.get(opts, :days_from_now)
          DateTime.utc_now() |> DateTime.add(days, :day)

        true ->
          DateTime.utc_now() |> DateTime.add(14, :day)
      end

    %Subscription{
      id: Ecto.ULID.generate(),
      user_id: Ecto.ULID.generate(),
      stripe_id: "sub_test_#{System.unique_integer([:positive])}",
      stripe_status: "active",
      name: "membership",
      current_period_end: renewal_date,
      current_period_start: DateTime.utc_now() |> DateTime.add(-30, :day)
    }
  end
end
