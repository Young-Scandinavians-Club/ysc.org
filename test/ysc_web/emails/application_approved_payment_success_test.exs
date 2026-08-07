defmodule YscWeb.Emails.ApplicationApprovedPaymentSuccessTest do
  use Ysc.DataCase, async: true

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  alias Ysc.Payments
  alias YscWeb.Emails.ApplicationApprovedPaymentSuccess

  test "get_template_name/0 and get_subject/0" do
    assert ApplicationApprovedPaymentSuccess.get_template_name() ==
             "application_approved_payment_success"

    assert ApplicationApprovedPaymentSuccess.get_subject() =~
             "Membership is Active"
  end

  test "render/1 produces HTML email body for card payment" do
    user = user_fixture()

    html =
      ApplicationApprovedPaymentSuccess.render(%{
        first_name: user.first_name,
        bank_payment: false
      })

    assert is_binary(html)
    assert html =~ user.first_name
    assert html =~ "has been charged"
    refute html =~ "bank payment is processing"
  end

  test "render/1 produces bank-aware copy when bank_payment is true" do
    user = user_fixture()

    html =
      ApplicationApprovedPaymentSuccess.render(%{
        first_name: user.first_name,
        bank_payment: true
      })

    assert html =~ "bank payment is processing"
    assert html =~ "payment receipt"
    refute html =~ "has been charged"
  end

  test "schedule/1 sends payment success email" do
    user = user_fixture()

    assert %Oban.Job{
             args: %{
               "template" => "application_approved_payment_success",
               "idempotency_key" => "approved_payment_success_" <> _,
               "params" => %{"bank_payment" => false}
             }
           } = ApplicationApprovedPaymentSuccess.schedule(user)

    assert_email_sent(
      subject: ApplicationApprovedPaymentSuccess.get_subject(),
      to: {nil, user.email}
    )
  end

  test "schedule/1 sets bank_payment when default PM is bank account" do
    user = user_fixture(%{state: :active})

    user =
      user
      |> Ysc.Accounts.User.update_user_changeset(%{
        stripe_id: "cus_bank_email_#{System.unique_integer([:positive])}"
      })
      |> Ysc.Repo.update!()

    {:ok, _pm} =
      Payments.insert_payment_method(%{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_bank_#{System.unique_integer([:positive])}",
        provider_customer_id: user.stripe_id,
        type: :bank_account,
        provider_type: "us_bank_account",
        is_default: true
      })

    assert %Oban.Job{
             args: %{
               "params" => %{"bank_payment" => true}
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
