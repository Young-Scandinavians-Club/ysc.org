defmodule Ysc.Subscriptions.CancelAndRefundTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Ledgers
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.CancelAndRefund

  defp subscription_for(user) do
    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        name: "Membership",
        current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
      })

    subscription
  end

  # A membership payment linked to the subscription through a ledger entry,
  # the way `Ledgers.get_payments_for_subscription/1` finds it.
  defp membership_payment(user, subscription, attrs \\ %{}) do
    Ledgers.ensure_basic_accounts()
    n = System.unique_integer([:positive])

    {:ok, payment} =
      Ledgers.create_payment(
        Map.merge(
          %{
            user_id: user.id,
            external_provider: :stripe,
            external_payment_id: "in_test_#{n}",
            amount: Money.new(:USD, 100),
            status: :completed,
            payment_date: DateTime.utc_now() |> DateTime.truncate(:second)
          },
          attrs
        )
      )

    for {account, debit_credit} <- [
          {"stripe_account", :debit},
          {"membership_revenue", :credit}
        ] do
      {:ok, _entry} =
        Ledgers.create_entry(%{
          account_id: Ledgers.get_account_by_name(account).id,
          payment_id: payment.id,
          related_entity_type: :membership,
          related_entity_id: subscription.id,
          amount: payment.amount,
          debit_credit: debit_credit
        })
    end

    payment
  end

  describe "latest_refundable/1" do
    test "errors when there are no payments" do
      assert {:error, :no_payment} = CancelAndRefund.latest_refundable([])
    end

    test "errors when the latest payment is not completed" do
      user = user_fixture()
      sub = subscription_for(user)
      membership_payment(user, sub, %{status: :pending})

      payments = Ledgers.get_payments_for_subscription(sub.id)

      assert {:error, :payment_not_completed} =
               CancelAndRefund.latest_refundable(payments)
    end

    test "refunds only the latest payment, not older ones" do
      user = user_fixture()
      sub = subscription_for(user)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      old =
        membership_payment(user, sub, %{
          amount: Money.new(:USD, 50),
          payment_date: DateTime.add(now, -365, :day)
        })

      latest =
        membership_payment(user, sub, %{
          amount: Money.new(:USD, 75),
          payment_date: now
        })

      payments = Ledgers.get_payments_for_subscription(sub.id)

      assert {:ok, %{payment: payment, refundable: refundable}} =
               CancelAndRefund.latest_refundable(payments)

      assert payment.id == latest.id
      refute payment.id == old.id
      assert Money.equal?(refundable, Money.new(:USD, 75))
    end

    test "returns only the unrefunded remainder after a partial refund" do
      user = user_fixture()
      sub = subscription_for(user)
      payment = membership_payment(user, sub)

      {:ok, _} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(:USD, 30),
          reason: "partial",
          external_refund_id: "re_partial_#{System.unique_integer([:positive])}"
        })

      payments = Ledgers.get_payments_for_subscription(sub.id)

      assert {:ok, %{refundable: refundable}} =
               CancelAndRefund.latest_refundable(payments)

      assert Money.equal?(refundable, Money.new(:USD, 70))
    end

    test "errors when the latest payment is already fully refunded" do
      user = user_fixture()
      sub = subscription_for(user)
      payment = membership_payment(user, sub)

      {:ok, _} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: payment.amount,
          reason: "full",
          external_refund_id: "re_full_#{System.unique_integer([:positive])}"
        })

      payments = Ledgers.get_payments_for_subscription(sub.id)

      assert {:error, :already_refunded} =
               CancelAndRefund.latest_refundable(payments)
    end
  end

  describe "run/1 precondition failures" do
    test "does not cancel the subscription when there is nothing to refund" do
      user = user_fixture()
      sub = subscription_for(user)

      assert {:error, :no_payment} = CancelAndRefund.run(sub)

      assert Repo.get!(Subscriptions.Subscription, sub.id).stripe_status ==
               "active"
    end

    test "does not cancel the subscription when the payment is not a Stripe payment" do
      user = user_fixture()
      sub = subscription_for(user)
      membership_payment(user, sub, %{external_payment_id: nil})

      assert {:error, :no_stripe_payment} = CancelAndRefund.run(sub)

      assert Repo.get!(Subscriptions.Subscription, sub.id).stripe_status ==
               "active"
    end
  end
end
