defmodule YscWeb.Emails.ApplicationApprovedPaymentSuccessTest do
  use Ysc.DataCase, async: true

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  alias YscWeb.Emails.ApplicationApprovedPaymentSuccess

  test "get_template_name/0 and get_subject/0" do
    assert ApplicationApprovedPaymentSuccess.get_template_name() ==
             "application_approved_payment_success"

    assert ApplicationApprovedPaymentSuccess.get_subject() =~
             "Membership is Active"
  end

  test "render/1 produces HTML email body" do
    user = user_fixture()

    html =
      ApplicationApprovedPaymentSuccess.render(%{
        first_name: user.first_name
      })

    assert is_binary(html)
    assert html =~ user.first_name
  end

  test "schedule/1 sends payment success email" do
    user = user_fixture()

    assert %Oban.Job{
             args: %{
               "template" => "application_approved_payment_success",
               "idempotency_key" => "approved_payment_success_" <> _
             }
           } = ApplicationApprovedPaymentSuccess.schedule(user)

    assert_email_sent(
      subject: ApplicationApprovedPaymentSuccess.get_subject(),
      to: {nil, user.email}
    )
  end

  test "maybe_schedule/2 only schedules on :activated" do
    user = user_fixture()

    assert :ok =
             ApplicationApprovedPaymentSuccess.maybe_schedule(
               user,
               :already_active
             )

    refute_email_sent()

    assert %Oban.Job{} =
             ApplicationApprovedPaymentSuccess.maybe_schedule(user, :activated)

    assert_email_sent(
      subject: ApplicationApprovedPaymentSuccess.get_subject(),
      to: {nil, user.email}
    )
  end
end
