defmodule YscWeb.Emails.EmailTemplatesTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Emails.{
    ApplicationApproved,
    ApplicationRejected,
    ApplicationSubmitted,
    AdminApplicationSubmitted,
    ChangeEmail,
    ConfirmEmail,
    ResetPassword,
    ConductViolationConfirmation,
    ConductViolationBoardNotification,
    MembershipPaymentFailure,
    BaseLayout
  }

  alias YscWeb.Emails.Notifier

  describe "email template rendering" do
    test "ApplicationSubmitted renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered with proper assigns
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationSubmitted.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ApplicationSubmitted.get_template_name() == "application_submitted"

      # Test that the subject is correct
      assert ApplicationSubmitted.get_subject() ==
               "Your Young Scandinavians Club application is in! 🎉"
    end

    test "ApplicationApproved renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationApproved.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ApplicationApproved.get_template_name() == "application_approved"

      # Test that the subject is correct
      assert ApplicationApproved.get_subject() ==
               "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)"
    end

    test "ApplicationRejected renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationRejected.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ApplicationRejected.get_template_name() == "application_rejected"

      # Test that the subject is correct
      assert ApplicationRejected.get_subject() ==
               "Update on your Young Scandinavians Club application"
    end

    test "AdminApplicationSubmitted renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        applicant_name: "#{user.first_name} #{user.last_name}",
        submission_date: "2024-01-15",
        review_url: "https://example.com/admin/applications/#{user.id}"
      }

      html = AdminApplicationSubmitted.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert AdminApplicationSubmitted.get_template_name() ==
               "admin_application_submitted"

      # Test that the subject is correct
      assert AdminApplicationSubmitted.get_subject() ==
               "New Membership Application Received - Action Needed"
    end

    test "ChangeEmail renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/confirm-email?token=abc123"
      }

      html = ChangeEmail.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ChangeEmail.get_template_name() == "change_email"
    end

    test "ConfirmEmail renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/confirm-email?token=abc123"
      }

      html = ConfirmEmail.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ConfirmEmail.get_template_name() == "confirm_email"
    end

    test "ResetPassword renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        url: "https://example.com/reset-password?token=abc123"
      }

      html = ResetPassword.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ResetPassword.get_template_name() == "reset_password"
    end

    test "ConductViolationConfirmation renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        summary: "Test violation summary",
        anonymous: false
      }

      html = ConductViolationConfirmation.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ConductViolationConfirmation.get_template_name() ==
               "conduct_violation_confirmation"

      # Test that the subject is correct
      assert ConductViolationConfirmation.get_subject() ==
               "Conduct Violation Report Received - YSC"
    end

    test "ConductViolationBoardNotification renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        phone: user.phone_number,
        report_id: "RPT-123",
        submitted_at: "2024-01-15 10:30:00",
        summary: "Test violation summary",
        anonymous: false
      }

      html = ConductViolationBoardNotification.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert ConductViolationBoardNotification.get_template_name() ==
               "conduct_violation_board_notification"

      # Test that the subject is correct
      assert ConductViolationBoardNotification.get_subject() ==
               "New Conduct Violation Report - Immediate Board Review Required"
    end

    test "MembershipPaymentFailure renders without errors" do
      user = user_fixture()

      # Test that the template can be rendered
      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        membership_type: "Single",
        is_renewal: false,
        pay_membership_url: YscWeb.Endpoint.url() <> "/users/membership",
        invoice_id: nil,
        retry_payment_url: nil
      }

      html = MembershipPaymentFailure.render(assigns)
      assert is_binary(html)
      assert String.length(html) > 0

      # Test that the template name is correct
      assert MembershipPaymentFailure.get_template_name() ==
               "membership_payment_failure"

      # Test that the subject is correct
      assert MembershipPaymentFailure.get_subject() ==
               "Action Needed: YSC Membership Payment Issue"
    end

    test "BaseLayout exists and is properly configured" do
      # Test that the base layout module exists and is properly configured
      assert Code.ensure_loaded?(BaseLayout)
      assert function_exported?(BaseLayout, :__info__, 1)
    end
  end

  describe "email template integration" do
    test "all email templates can be found by Notifier" do
      template_names = [
        "application_rejected",
        "application_approved",
        "application_submitted",
        "confirm_email",
        "reset_password",
        "change_email",
        "admin_application_submitted",
        "conduct_violation_confirmation",
        "conduct_violation_board_notification"
      ]

      for template_name <- template_names do
        template_module = Notifier.get_template_module(template_name)

        assert template_module != nil,
               "Template module not found for #{template_name}"

        # Test that the module exists and can be loaded
        assert Code.ensure_loaded?(template_module),
               "Template module #{template_module} cannot be loaded"
      end
    end

    test "all email templates render valid HTML" do
      user = user_fixture()

      templates_with_assigns = [
        {ApplicationSubmitted,
         %{
           first_name: user.first_name,
           last_name: user.last_name,
           email: user.email
         }},
        {ApplicationApproved,
         %{
           first_name: user.first_name,
           last_name: user.last_name,
           email: user.email
         }},
        {ApplicationRejected,
         %{
           first_name: user.first_name,
           last_name: user.last_name,
           email: user.email
         }},
        {AdminApplicationSubmitted,
         %{
           applicant_name: "#{user.first_name} #{user.last_name}",
           submission_date: "2024-01-15",
           review_url: "https://example.com/admin/applications/#{user.id}"
         }},
        {ChangeEmail,
         %{
           first_name: user.first_name,
           url: "https://example.com/confirm-email?token=abc123"
         }},
        {ConfirmEmail,
         %{
           first_name: user.first_name,
           url: "https://example.com/confirm-email?token=abc123"
         }},
        {ResetPassword,
         %{
           first_name: user.first_name,
           url: "https://example.com/reset-password?token=abc123"
         }},
        {ConductViolationConfirmation,
         %{
           first_name: user.first_name,
           last_name: user.last_name,
           summary: "Test violation summary",
           anonymous: false
         }},
        {ConductViolationBoardNotification,
         %{
           first_name: user.first_name,
           last_name: user.last_name,
           email: user.email,
           phone: user.phone_number,
           report_id: "RPT-123",
           submitted_at: "2024-01-15 10:30:00",
           summary: "Test violation summary",
           anonymous: false
         }},
        {MembershipPaymentFailure,
         %{
           first_name: user.first_name,
           invoice_id: nil,
           last_name: user.last_name,
           email: user.email,
           membership_type: "Single",
           is_renewal: false,
           pay_membership_url: YscWeb.Endpoint.url() <> "/users/membership",
           retry_payment_url: nil
         }}
      ]

      for {template, assigns} <- templates_with_assigns do
        html = template.render(assigns)
        assert is_binary(html)
        assert String.length(html) > 0

        # Basic HTML structure checks
        assert String.contains?(html, "<html") or
                 String.contains?(html, "<!DOCTYPE")

        assert String.contains?(html, "</html>") or
                 String.contains?(html, "</body>")
      end
    end
  end
end
