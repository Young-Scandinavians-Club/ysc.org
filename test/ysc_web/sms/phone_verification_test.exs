defmodule YscWeb.Sms.PhoneVerificationTest do
  use ExUnit.Case, async: true

  alias YscWeb.Sms.PhoneVerification

  describe "get_template_name/0" do
    test "returns correct template name" do
      assert PhoneVerification.get_template_name() == "phone_verification"
    end
  end

  describe "render/1" do
    test "renders SMS with code only" do
      variables = %{code: "123456"}
      message = PhoneVerification.render(variables)

      assert message =~ "[YSC]"
      assert message =~ "123456"
      assert message =~ "Your phone verification code is: 123456"
    end

    test "renders SMS with first name and code" do
      variables = %{code: "654321", first_name: "John"}
      message = PhoneVerification.render(variables)

      assert message =~ "[YSC]"
      assert message =~ "Hej John!"
      assert message =~ "654321"
      assert message =~ "Your phone verification code is: 654321"
    end

    test "handles missing code gracefully" do
      variables = %{}
      message = PhoneVerification.render(variables)

      assert message =~ "[YSC]"
      assert message =~ "Your phone verification code is:"
    end

    test "trims and normalizes whitespace" do
      variables = %{code: "111111"}
      message = PhoneVerification.render(variables)

      # Should not have double spaces or trailing/leading whitespace
      refute message =~ "  "
      assert String.trim(message) == message
    end
  end

  describe "prepare_sms_data/2" do
    test "prepares data with user and string code" do
      user = %{first_name: "Jane"}
      code = "987654"

      result = PhoneVerification.prepare_sms_data(user, code)

      assert result.code == "987654"
      assert result.first_name == "Jane"
    end

    test "prepares data with nil user and string code" do
      result = PhoneVerification.prepare_sms_data(nil, "123456")

      assert result.code == "123456"
      assert result.first_name == nil
    end

    test "prepares data with integer code" do
      user = %{first_name: "Bob"}
      code = 123_456

      result = PhoneVerification.prepare_sms_data(user, code)

      assert result.code == "123456"
      assert result.first_name == "Bob"
    end

    test "pads integer code with leading zeros" do
      user = %{first_name: "Alice"}
      code = 42

      result = PhoneVerification.prepare_sms_data(user, code)

      assert result.code == "000042"
      assert result.first_name == "Alice"
    end
  end
end
