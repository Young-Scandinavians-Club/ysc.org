defmodule YscWeb.Components.VerificationPromptTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "verification_dev_hint/1" do
    test "renders the 000000 bypass hint in non-prod with a stable id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.verification_dev_hint id="phone-verification-dev-hint" />
        """)

      assert html =~ ~s(id="phone-verification-dev-hint")
      assert html =~ "Dev Mode:"
      assert html =~ "000000"
      assert html =~ "bg-amber-50"
      assert html =~ "border-amber-200"
    end
  end

  describe "verification_resend_prompt/1" do
    test "shows a resend link when not rate limited" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.verification_resend_prompt
          id="phone-verification-resend"
          channel={:sms}
          event="resend_phone_code"
        />
        """)

      assert html =~ ~s(id="phone-verification-resend")
      assert html =~ "Didn't receive the code?"
      assert html =~ "Check your messages."
      assert html =~ "Resend the code"
      assert html =~ ~s(phx-click="resend_phone_code")
      assert html =~ ~s(phx-disable-with="Sending...")
      refute html =~ "data-countdown"
      refute html =~ "You can resend the code"
    end

    test "uses the email hint and event by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.verification_resend_prompt
          id="email-verification-resend"
          channel={:email}
          event="resend_email_code"
        />
        """)

      assert html =~ "Check your email."
      assert html =~ ~s(phx-click="resend_email_code")
      refute html =~ "Check your messages."
    end

    test "accepts a custom check hint" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.verification_resend_prompt
          id="email-verification-resend"
          channel={:email}
          event="resend_code"
          check_hint="Check your spam folder."
        />
        """)

      assert html =~ "Check your spam folder."
      refute html =~ "Check your email."
    end

    test "shows a countdown with ResendTimer data attrs when rate limited" do
      disabled_until = DateTime.add(DateTime.utc_now(), 45, :second)
      assigns = %{disabled_until: disabled_until}

      html =
        rendered_to_string(~H"""
        <.verification_resend_prompt
          id="phone-verification-resend"
          channel={:sms}
          event="resend_phone_code"
          disabled_until={@disabled_until}
        />
        """)

      assert html =~ ~s(id="phone-verification-resend-countdown")
      assert html =~ ~s(data-timer-type="sms")
      assert html =~ "data-countdown="
      assert html =~ "You can resend the code in"
      assert html =~ "seconds"
      assert html =~ "font-bold"
      refute html =~ "Resend the code"
    end

    test "email countdown uses data-timer-type email" do
      disabled_until = DateTime.add(DateTime.utc_now(), 30, :second)
      assigns = %{disabled_until: disabled_until}

      html =
        rendered_to_string(~H"""
        <.verification_resend_prompt
          id="email-verification-resend"
          channel={:email}
          event="resend_code"
          disabled_until={@disabled_until}
        />
        """)

      assert html =~ ~s(data-timer-type="email")
      assert html =~ ~s(id="email-verification-resend-countdown")
    end
  end
end
