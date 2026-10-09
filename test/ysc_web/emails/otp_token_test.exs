defmodule YscWeb.Emails.OtpTokenTest do
  use Ysc.DataCase, async: true

  import Swoosh.TestAssertions

  alias YscWeb.Emails.AccountSetupVerification
  alias YscWeb.Emails.Notifier
  alias YscWeb.Emails.OtpToken

  describe "header_value/2" do
    test "serializes the code as an SF String with an origin parameter" do
      assert OtpToken.header_value("123456", "https://example.com") ==
               {:ok, ~s("123456"; origin="https://example.com")}
    end

    test "accepts non-default ports and loopback http origins" do
      assert {:ok, _} =
               OtpToken.header_value("123456", "https://example.com:8443")

      assert {:ok, _} = OtpToken.header_value("123456", "http://localhost")
      assert {:ok, _} = OtpToken.header_value("123456", "http://localhost:4000")
      assert {:ok, _} = OtpToken.header_value("123456", "http://127.0.0.1:4000")
      assert {:ok, _} = OtpToken.header_value("123456", "http://[::1]:4000")
    end

    test "rejects origins that are not canonical or trustworthy" do
      for origin <- [
            "null",
            "",
            "http://example.com",
            "https://Example.com",
            "https://example.com:443",
            "http://localhost:80",
            "https://example.com:0443",
            "https://example.com/",
            "https://example.com/path",
            "https://example.com?x=1",
            "https://user@example.com",
            "https://bücher.example",
            "ftp://example.com"
          ] do
        assert OtpToken.header_value("123456", origin) == :error,
               "expected #{inspect(origin)} to be rejected"
      end
    end

    test "rejects codes that are not printable ASCII" do
      assert OtpToken.header_value("12\n456", "https://example.com") == :error
      assert OtpToken.header_value("12é456", "https://example.com") == :error
    end

    test "escapes quotes and backslashes in the code" do
      assert OtpToken.header_value(~S(a"b\c), "https://example.com") ==
               {:ok, ~S("a\"b\\c"; origin="https://example.com")}
    end

    test "returns :error for a missing origin" do
      assert OtpToken.header_value("123456", nil) == :error
    end
  end

  describe "endpoint_origin/1" do
    test "canonicalizes the endpoint URL" do
      assert OtpToken.endpoint_origin("https://YSC.org:443") ==
               "https://ysc.org"

      assert OtpToken.endpoint_origin("https://ysc.org/") == "https://ysc.org"

      assert OtpToken.endpoint_origin("http://localhost:4000") ==
               "http://localhost:4000"
    end

    test "returns nil for untrustworthy or unparseable URLs" do
      assert OtpToken.endpoint_origin("http://ysc.org") == nil
      assert OtpToken.endpoint_origin("not a url") == nil
      assert OtpToken.endpoint_origin(nil) == nil
    end

    test "derives a valid origin from the configured endpoint" do
      assert is_binary(OtpToken.endpoint_origin())
    end
  end

  describe "put_header/3" do
    test "adds the header when the origin is valid" do
      email =
        OtpToken.put_header(Swoosh.Email.new(), "123456", "https://ysc.org")

      assert email.headers["OTP-Token"] ==
               ~s("123456"; origin="https://ysc.org")
    end

    test "leaves the email untouched when no valid header can be built" do
      email = OtpToken.put_header(Swoosh.Email.new(), "123456", nil)
      refute Map.has_key?(email.headers, "OTP-Token")
    end
  end

  describe "verification email delivery" do
    test "includes OTP-Token exactly once, bound to the endpoint origin" do
      user = Ysc.AccountsFixtures.user_fixture()
      origin = OtpToken.endpoint_origin()

      assert {:ok, _} =
               Notifier.send_email_idempotent(
                 user.email,
                 "otp_token_#{Ecto.UUID.generate()}",
                 "Verify Your Email Address - YSC",
                 AccountSetupVerification,
                 %{first_name: user.first_name, verification_code: "654321"},
                 "Your verification code is: 654321",
                 user.id
               )

      assert_email_sent(fn sent ->
        assert sent.headers["OTP-Token"] == ~s("654321"; origin="#{origin}")
      end)
    end

    test "other templates do not carry the header" do
      user = Ysc.AccountsFixtures.user_fixture()

      assert {:ok, _} =
               Notifier.send_email_idempotent(
                 user.email,
                 "otp_token_other_#{Ecto.UUID.generate()}",
                 "Reset",
                 YscWeb.Emails.ResetPassword,
                 %{first_name: user.first_name, url: "https://ysc.org/reset"},
                 "",
                 user.id
               )

      assert_email_sent(fn sent ->
        not Map.has_key?(sent.headers, "OTP-Token")
      end)
    end
  end
end
