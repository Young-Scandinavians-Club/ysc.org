defmodule YscWeb.Emails.MembershipPaymentConfirmationTest do
  @moduledoc """
  Tests for YscWeb.Emails.MembershipPaymentConfirmation email template.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Emails.MembershipPaymentConfirmation

  describe "get_template_name/0" do
    test "returns membership_payment_confirmation" do
      assert MembershipPaymentConfirmation.get_template_name() ==
               "membership_payment_confirmation"
    end
  end

  describe "get_subject/0" do
    test "returns welcome subject" do
      assert MembershipPaymentConfirmation.get_subject() ==
               "Welcome to YSC – Your Membership is Active! 🎉"
    end
  end

  describe "prepare_email_data/5" do
    test "returns map with first_name, membership_type, amount, payment_date, paid_elsewhere" do
      user = user_fixture(%{first_name: "Jane", last_name: "Doe"})
      amount = Money.new(50, :USD)
      payment_date = ~D[2024-12-01]

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          :single,
          amount,
          payment_date
        )

      assert data.first_name == "Jane"
      assert data.membership_type == "Single"
      assert data.amount == "$50.00"
      assert data.payment_date == "December 01, 2024"
      assert data.paid_elsewhere == false
    end

    test "includes paid_elsewhere when opts passed" do
      user = user_fixture()
      amount = Money.new(50, :USD)
      payment_date = ~D[2024-12-01]

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          :single,
          amount,
          payment_date,
          paid_elsewhere: true
        )

      assert data.paid_elsewhere == true
    end

    test "formats family membership type" do
      user = user_fixture()
      amount = Money.new(75, :USD)
      payment_date = ~D[2024-12-01]

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          :family,
          amount,
          payment_date
        )

      assert data.membership_type == "Family"
    end

    test "uses Valued Member when user has no first_name" do
      base_user = user_fixture()
      user = %{base_user | first_name: nil}
      amount = Money.new(50, :USD)
      payment_date = ~D[2024-12-01]

      data =
        MembershipPaymentConfirmation.prepare_email_data(
          user,
          :single,
          amount,
          payment_date
        )

      assert data.first_name == "Valued Member"
    end

    test "raises when user is nil" do
      amount = Money.new(50, :USD)
      payment_date = ~D[2024-12-01]

      assert_raise ArgumentError, "User cannot be nil", fn ->
        MembershipPaymentConfirmation.prepare_email_data(
          nil,
          :single,
          amount,
          payment_date
        )
      end
    end
  end
end
