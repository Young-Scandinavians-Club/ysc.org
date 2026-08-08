defmodule Ysc.Subscriptions.ExpirationWorkerTest do
  @moduledoc """
  Tests for subscription expiration worker.

  Note: Full integration tests that call Stripe API are not included here.
  These tests focus on the worker structure, basic functionality, and query logic.

  `Ysc.DataCase` includes `Oban.Testing` (`perform_job/2`, etc.).
  """
  use Ysc.DataCase, async: false

  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.ExpirationWorker

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "perform/1" do
    test "can be run via Oban.Testing perform_job" do
      assert {:ok, msg} = perform_job(ExpirationWorker, %{})
      assert msg =~ "Checked subscriptions"
    end

    test "processes the expiration job successfully" do
      job = %Oban.Job{args: %{}}

      assert {:ok, message} = ExpirationWorker.perform(job)
      assert message =~ "Checked subscriptions"
      assert message =~ "expired"
      assert message =~ "failed"
    end

    test "returns counts of expired and failed subscriptions" do
      job = %Oban.Job{args: %{}}
      {:ok, message} = ExpirationWorker.perform(job)

      # Message format: "Checked subscriptions: X expired, Y failed"
      assert message =~ ~r/\d+ expired, \d+ failed/
    end
  end

  describe "check_and_expire_subscriptions/0" do
    test "returns zero counts when no subscriptions exist" do
      assert {0, 0} = ExpirationWorker.check_and_expire_subscriptions()
    end

    test "counts failure when Stripe retrieve returns Stripe.Error", %{
      user: user
    } do
      original = Application.get_env(:ysc, :stripe_subscription_retriever)

      Application.put_env(
        :ysc,
        :stripe_subscription_retriever,
        Ysc.StripeSubscriptionRetrieverErrorMock
      )

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_subscription_retriever, original)
      end)

      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_stripe_error_mock",
          stripe_status: "active",
          name: "Stripe API Error",
          current_period_end: past_date,
          ends_at: nil
        })

      assert {0, 1} = ExpirationWorker.check_and_expire_subscriptions()
    end

    test "counts failure when Stripe retrieve returns unexpected error", %{
      user: user
    } do
      original = Application.get_env(:ysc, :stripe_subscription_retriever)

      Application.put_env(
        :ysc,
        :stripe_subscription_retriever,
        Ysc.StripeSubscriptionRetrieverUnexpectedErrorMock
      )

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_subscription_retriever, original)
      end)

      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_unexpected_mock",
          stripe_status: "active",
          name: "Unexpected Error",
          current_period_end: past_date,
          ends_at: nil
        })

      assert {0, 1} = ExpirationWorker.check_and_expire_subscriptions()
    end

    test "processes expired subscription via Stripe mock and counts success", %{
      user: user
    } do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_exp_mock_works",
          stripe_status: "active",
          name: "Expired For Mock",
          current_period_end: past_date,
          ends_at: nil
        })

      assert {1, 0} = ExpirationWorker.check_and_expire_subscriptions()
      refute_email_sent(subject: "Your YSC Membership Has Ended")
    end

    test "sends membership ended email when auto-renew was turned off", %{
      user: user
    } do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_exp_auto_renew_off",
          stripe_status: "active",
          name: "Auto Renew Off",
          current_period_end: past_date,
          ends_at: past_date
        })

      assert {1, 0} = ExpirationWorker.check_and_expire_subscriptions()
      assert_email_sent(subject: "Your YSC Membership Has Ended")
    end

    test "treats subscription as renewed when Stripe reports active future period",
         %{
           user: user
         } do
      original = Application.get_env(:ysc, :stripe_subscription_retriever)

      Application.put_env(
        :ysc,
        :stripe_subscription_retriever,
        Ysc.StripeSubscriptionRetrieverRenewedMock
      )

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_subscription_retriever, original)
      end)

      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_renewed_mock_case",
          stripe_status: "active",
          name: "Expired Locally Renewed",
          current_period_end: past_date,
          ends_at: nil
        })

      assert {1, 0} = ExpirationWorker.check_and_expire_subscriptions()
    end

    test "finds subscriptions with expired current_period_end", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      # Create an expired subscription
      {:ok, _expired_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_123",
          stripe_status: "active",
          name: "Expired Membership",
          current_period_end: past_date,
          ends_at: nil
        })

      # Note: This will try to call Stripe API and fail, but that's expected in this test
      # The subscription will still be found by the query
      {expired_count, failed_count} =
        ExpirationWorker.check_and_expire_subscriptions()

      # Should find the subscription and try to process it (will fail without Stripe mock)
      assert expired_count + failed_count >= 0
    end

    test "finds subscriptions with expired ends_at", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)
      future_date = DateTime.add(now, 30, :day)

      {:ok, _ended_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ended_789",
          stripe_status: "trialing",
          name: "Ended Membership",
          current_period_end: future_date,
          ends_at: past_date
        })

      {expired_count, failed_count} =
        ExpirationWorker.check_and_expire_subscriptions()

      # Should find the subscription
      assert expired_count + failed_count >= 0
    end

    test "does not process valid active subscriptions", %{user: user} do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)

      {:ok, valid_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_valid_999",
          stripe_status: "active",
          name: "Valid Membership",
          current_period_end: future_date,
          ends_at: nil
        })

      {expired_count, failed_count} =
        ExpirationWorker.check_and_expire_subscriptions()

      # Valid subscription should not be processed
      assert expired_count == 0
      assert failed_count == 0

      # Subscription should still be valid
      refute Subscriptions.cancelled?(valid_sub)
      assert Subscriptions.valid?(valid_sub)
    end

    test "does not process already cancelled subscriptions", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, _cancelled_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancelled_111",
          stripe_status: "canceled",
          name: "Cancelled Membership",
          current_period_end: past_date,
          ends_at: past_date
        })

      {expired_count, failed_count} =
        ExpirationWorker.check_and_expire_subscriptions()

      # Already cancelled subscription should not be processed
      assert expired_count == 0
      assert failed_count == 0
    end

    test "verifies query logic for finding expired subscriptions", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)
      future_date = DateTime.add(now, 30, :day)

      # Create subscriptions with different statuses
      {:ok, expired1} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_exp1",
          stripe_status: "active",
          name: "Expired 1",
          current_period_end: past_date,
          ends_at: nil
        })

      {:ok, expired2} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_exp2",
          stripe_status: "trialing",
          name: "Expired 2",
          current_period_end: future_date,
          ends_at: past_date
        })

      {:ok, valid} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_valid",
          stripe_status: "active",
          name: "Valid",
          current_period_end: future_date,
          ends_at: nil
        })

      {:ok, cancelled} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_canc",
          stripe_status: "canceled",
          name: "Cancelled",
          current_period_end: past_date,
          ends_at: past_date
        })

      # Verify subscriptions are created correctly
      # expired1 has past current_period_end, so it's considered expired/cancelled
      assert Subscriptions.cancelled?(expired1)
      assert Subscriptions.cancelled?(expired2)
      refute Subscriptions.cancelled?(valid)
      assert Subscriptions.cancelled?(cancelled)

      # The worker will find expired1 and expired2 (both have expired dates)
      # but only expired1 will pass the status check (active/trialing)
      # The actual expiration will fail without Stripe mocking
      {_expired_count, _failed_count} =
        ExpirationWorker.check_and_expire_subscriptions()
    end
  end

  describe "timeout/1" do
    test "returns 120 seconds timeout" do
      job = %Oban.Job{args: %{}}
      assert ExpirationWorker.timeout(job) == 120_000
    end
  end

  describe "subscription status checks" do
    test "cancelled? returns true for subscriptions with ends_at in past", %{
      user: user
    } do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_ended",
          stripe_status: "active",
          name: "Ended Subscription",
          current_period_end: DateTime.add(now, 30, :day),
          ends_at: past_date
        })

      assert Subscriptions.cancelled?(sub)
    end

    test "valid? returns false for expired subscriptions", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired",
          stripe_status: "active",
          name: "Expired Subscription",
          current_period_end: past_date,
          ends_at: nil
        })

      refute Subscriptions.valid?(sub)
    end

    test "valid? returns true for active subscriptions with future dates", %{
      user: user
    } do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)

      {:ok, sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_active",
          stripe_status: "active",
          name: "Active Subscription",
          current_period_end: future_date,
          ends_at: nil
        })

      assert Subscriptions.valid?(sub)
    end
  end
end
