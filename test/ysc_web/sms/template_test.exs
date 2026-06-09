defmodule YscWeb.Sms.TemplateTest do
  use ExUnit.Case, async: true

  alias YscWeb.Sms.Template

  describe "normalize_body/1" do
    test "trims and collapses whitespace" do
      assert Template.normalize_body("  hello   world \n") == "hello world"
    end
  end

  describe "format/1" do
    test "adds the YSC prefix and normalizes whitespace" do
      assert Template.format("  hello   world ") == "[YSC] hello world"
    end

    test "does not duplicate the YSC prefix" do
      assert Template.format("[YSC] hello") == "[YSC] hello"
    end
  end

  describe "first_name/2" do
    test "uses the default greeting when missing" do
      assert Template.first_name(%{}) == "Valued Member"
    end

    test "reads the provided first name" do
      assert Template.first_name(%{first_name: "Anna"}) == "Anna"
    end
  end

  describe "greeting/2" do
    test "prefixes the message when a first name is present" do
      assert Template.greeting("Welcome back.", "Anna") ==
               "Hej Anna! Welcome back."
    end

    test "returns the message unchanged when first name is nil" do
      assert Template.greeting("Welcome back.", nil) == "Welcome back."
    end
  end

  describe "security_notification_body/2" do
    test "builds a formatted security notification" do
      body =
        Template.security_notification_body(
          "Anna",
          "Your account password was changed."
        )

      assert body ==
               "[YSC] Hej Anna! Your account password was changed."
    end
  end

  describe "verification_code/1" do
    test "pads integer codes to six digits" do
      assert Template.verification_code(123) == "000123"
    end

    test "returns string codes unchanged" do
      assert Template.verification_code("123456") == "123456"
    end
  end

  describe "verification_variables/2" do
    test "builds code and first name variables" do
      user = %{first_name: "Anna"}

      assert Template.verification_variables(user, 42) == %{
               code: "000042",
               first_name: "Anna"
             }
    end

    test "handles nil users" do
      assert Template.verification_variables(nil, "123456") == %{
               code: "123456",
               first_name: nil
             }
    end
  end
end
