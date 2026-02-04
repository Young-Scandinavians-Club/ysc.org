defmodule YscWeb.Sms.AllSmsTemplatesTest do
  @moduledoc """
  Comprehensive tests to ensure ALL SMS templates can be rendered.

  This test file ensures every single SMS template in the system can be
  successfully rendered with appropriate test data, preventing template
  rendering errors and missing variable issues.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Sms.Notifier

  alias YscWeb.Sms.{
    BookingCheckinReminder,
    TwoFactorVerification,
    EmailChanged,
    PasswordChanged
  }

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "all SMS templates can be rendered" do
    test "BookingCheckinReminder renders", %{user: user} do
      variables = %{
        first_name: user.first_name,
        property_name: "Tahoe",
        checkin_date: "Dec 1, 2024",
        door_code: "1234",
        checkin_time: "3:00 PM"
      }

      message = BookingCheckinReminder.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, user.first_name)
      assert String.contains?(message, "Tahoe")
      assert String.contains?(message, "1234")

      assert BookingCheckinReminder.get_template_name() ==
               "booking_checkin_reminder"
    end

    test "TwoFactorVerification renders with first_name", %{user: user} do
      variables = %{
        code: "123456",
        first_name: user.first_name
      }

      message = TwoFactorVerification.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, "123456")
      assert String.contains?(message, user.first_name)
      assert String.contains?(message, "[YSC]")

      assert TwoFactorVerification.get_template_name() ==
               "two_factor_verification"
    end

    test "TwoFactorVerification renders without first_name" do
      variables = %{
        code: "123456"
      }

      message = TwoFactorVerification.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, "123456")
      assert String.contains?(message, "[YSC]")

      assert TwoFactorVerification.get_template_name() ==
               "two_factor_verification"
    end

    test "EmailChanged renders", %{user: user} do
      variables = %{
        first_name: user.first_name,
        new_email: "newemail@example.com"
      }

      message = EmailChanged.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, user.first_name)
      assert String.contains?(message, "newemail@example.com")
      assert String.contains?(message, "[YSC]")
      assert EmailChanged.get_template_name() == "email_changed"
    end

    test "EmailChanged renders with default values" do
      variables = %{}

      message = EmailChanged.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, "[YSC]")
      assert EmailChanged.get_template_name() == "email_changed"
    end

    test "PasswordChanged renders", %{user: user} do
      variables = %{
        first_name: user.first_name
      }

      message = PasswordChanged.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, user.first_name)
      assert String.contains?(message, "[YSC]")
      assert PasswordChanged.get_template_name() == "password_changed"
    end

    test "PasswordChanged renders with default values" do
      variables = %{}

      message = PasswordChanged.render(variables)
      assert is_binary(message)
      assert String.length(message) > 0
      assert String.contains?(message, "[YSC]")
      assert PasswordChanged.get_template_name() == "password_changed"
    end
  end

  describe "SMS template prepare functions" do
    test "TwoFactorVerification.prepare_sms_data works with string code", %{
      user: user
    } do
      result = TwoFactorVerification.prepare_sms_data(user, "123456")
      assert is_map(result)
      assert result.code == "123456"
      assert result.first_name == user.first_name
    end

    test "TwoFactorVerification.prepare_sms_data works with integer code", %{
      user: user
    } do
      result = TwoFactorVerification.prepare_sms_data(user, 123_456)
      assert is_map(result)
      assert result.code == "123456"
      assert result.first_name == user.first_name
    end

    test "TwoFactorVerification.prepare_sms_data pads integer code", %{
      user: user
    } do
      result = TwoFactorVerification.prepare_sms_data(user, 123)
      assert is_map(result)
      assert result.code == "000123"
      assert result.first_name == user.first_name
    end

    test "EmailChanged.prepare_sms_data works", %{user: user} do
      result = EmailChanged.prepare_sms_data(user, "newemail@example.com")
      assert is_map(result)
      assert result.new_email == "newemail@example.com"
      assert result.first_name == user.first_name
    end

    test "EmailChanged.prepare_sms_data works with nil user" do
      result = EmailChanged.prepare_sms_data(nil, "newemail@example.com")
      assert is_map(result)
      assert result.new_email == "newemail@example.com"
      assert result.first_name == nil
    end

    test "PasswordChanged.prepare_sms_data works", %{user: user} do
      result = PasswordChanged.prepare_sms_data(user)
      assert is_map(result)
      assert result.first_name == user.first_name
    end

    test "PasswordChanged.prepare_sms_data works with nil user" do
      result = PasswordChanged.prepare_sms_data(nil)
      assert is_map(result)
      assert result.first_name == nil
    end
  end

  describe "all SMS templates are registered in Notifier" do
    test "every template in Notifier can be loaded and rendered" do
      # Get all template mappings from Notifier
      template_mappings = %{
        "booking_checkin_reminder" => BookingCheckinReminder,
        "two_factor_verification" => TwoFactorVerification,
        "email_changed" => EmailChanged,
        "password_changed" => PasswordChanged
      }

      for {template_name, expected_module} <- template_mappings do
        # Verify Notifier can find the template
        module = Notifier.get_template_module(template_name)

        assert module == expected_module,
               "Template #{template_name} should map to #{expected_module}, got #{module}"

        # Verify module can be loaded
        assert Code.ensure_loaded?(module),
               "Template module #{module} cannot be loaded"

        # Verify module has required functions
        assert function_exported?(module, :get_template_name, 0),
               "Template module #{module} missing get_template_name/0"

        assert function_exported?(module, :render, 1),
               "Template module #{module} missing render/1"

        # Verify template name matches
        assert module.get_template_name() == template_name,
               "Template name mismatch for #{module}: expected #{template_name}, got #{module.get_template_name()}"
      end
    end

    test "all SMS templates render valid messages" do
      # Test that all templates can render with minimal test data
      templates_with_variables = [
        {BookingCheckinReminder,
         %{
           first_name: "Test",
           property_name: "Tahoe",
           checkin_date: "Dec 1, 2024",
           door_code: "1234",
           checkin_time: "3:00 PM"
         }},
        {TwoFactorVerification, %{code: "123456"}},
        {EmailChanged, %{first_name: "Test", new_email: "test@example.com"}},
        {PasswordChanged, %{first_name: "Test"}}
      ]

      for {template, variables} <- templates_with_variables do
        message = template.render(variables)
        assert is_binary(message), "Template #{template} should return a binary"

        assert String.length(message) > 0,
               "Template #{template} should return non-empty message"

        assert String.length(message) <= 1600,
               "Template #{template} message too long (#{String.length(message)} chars)"
      end
    end
  end
end
