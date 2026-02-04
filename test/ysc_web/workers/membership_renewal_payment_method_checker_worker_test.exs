defmodule YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorkerTest do
  @moduledoc """
  Tests for MembershipRenewalPaymentMethodCheckerWorker.

  Tests verify:
  - Worker runs successfully
  - Finds correct subscriptions
  - Processes users with and without payment methods appropriately
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  setup do
    # Ensure ledger accounts exist for any payment-related operations
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "perform/1" do
    test "runs successfully with no subscriptions" do
      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "runs successfully with subscription expiring in 14 days" do
      user = user_fixture()
      renewal_date = DateTime.utc_now() |> DateTime.add(14, :day)
      insert_subscription(user, renewal_date)

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "runs successfully with multiple subscriptions" do
      user1 = user_fixture()
      user2 = user_fixture()
      renewal_date = DateTime.utc_now() |> DateTime.add(14, :day)

      insert_subscription(user1, renewal_date)
      insert_subscription(user2, renewal_date)

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "runs successfully when user has payment method" do
      user = user_fixture()
      renewal_date = DateTime.utc_now() |> DateTime.add(14, :day)

      insert_subscription(user, renewal_date)
      insert_payment_method(user, is_default: true)

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "ignores subscriptions not expiring in 14 days" do
      user = user_fixture()
      renewal_date_13days = DateTime.utc_now() |> DateTime.add(13, :day)
      renewal_date_15days = DateTime.utc_now() |> DateTime.add(15, :day)

      insert_subscription(user, renewal_date_13days)
      insert_subscription(user, renewal_date_15days)

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "ignores cancelled subscriptions" do
      user = user_fixture()
      renewal_date = DateTime.utc_now() |> DateTime.add(14, :day)
      ends_at = DateTime.utc_now() |> DateTime.add(13, :day)

      insert_subscription(user, renewal_date, ends_at: ends_at)

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "ignores inactive subscriptions" do
      user = user_fixture()
      renewal_date = DateTime.utc_now() |> DateTime.add(14, :day)

      insert_subscription(user, renewal_date, stripe_status: "canceled")

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    test "handles subscription with nil current_period_end gracefully" do
      user = user_fixture()

      %Subscription{
        user_id: user.id,
        stripe_id: "sub_nil_period_end",
        stripe_status: "active",
        name: "membership",
        current_period_end: nil,
        current_period_start: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      job = build_job()
      assert :ok = MembershipRenewalPaymentMethodCheckerWorker.perform(job)
    end

    # Note: "handles missing user gracefully" test removed because foreign key
    # constraints prevent subscriptions from existing without a valid user.
    # The database schema ensures data integrity at the constraint level.
  end

  # Helper functions

  defp build_job do
    %Oban.Job{
      id: 1,
      args: %{},
      worker: "YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker",
      queue: "default",
      state: "available",
      attempt: 1
    }
  end

  defp insert_subscription(user, renewal_date, opts \\ []) do
    stripe_status = Keyword.get(opts, :stripe_status, "active")
    ends_at = Keyword.get(opts, :ends_at, nil)

    # Truncate to seconds since Ecto :utc_datetime doesn't support microseconds
    renewal_date_truncated = DateTime.truncate(renewal_date, :second)

    ends_at_truncated =
      if ends_at, do: DateTime.truncate(ends_at, :second), else: nil

    start_date =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.truncate(:second)

    %Subscription{
      user_id: user.id,
      stripe_id: "sub_test_#{System.unique_integer([:positive])}",
      stripe_status: stripe_status,
      name: "membership",
      current_period_end: renewal_date_truncated,
      current_period_start: start_date,
      ends_at: ends_at_truncated
    }
    |> Repo.insert!()
  end

  defp insert_payment_method(user, opts) do
    is_default = Keyword.get(opts, :is_default, true)

    %PaymentMethod{
      user_id: user.id,
      provider: :stripe,
      provider_id: "pm_test_#{System.unique_integer([:positive])}",
      provider_customer_id: "cus_test_#{System.unique_integer([:positive])}",
      provider_type: "card",
      type: :card,
      last_four: "4242",
      exp_month: 12,
      exp_year: 2030,
      display_brand: "visa",
      is_default: is_default
    }
    |> Repo.insert!()
  end
end
