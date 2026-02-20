defmodule YscWeb.Workers.MembershipRenewalReminderWorkerTest do
  @moduledoc """
  Tests for MembershipRenewalReminderWorker.

  Two scenarios are covered:

  1. Daily cron job (`perform/1`) — sends reminders to all active members whose
     `current_period_end` falls exactly 7 days from today and who have a payment
     method on file (so the renewal will actually succeed).

  2. Admin billing anchor move (`schedule_reminder_if_within_window/2`) — sends
     a reminder immediately when an admin shifts a renewal date into the ≤7-day
     window that the daily cron would otherwise miss, again only for members
     with a payment method on file.

  Oban is configured in `:inline` mode for tests, meaning jobs execute
  synchronously on insert. Email delivery is asserted via Swoosh.TestAssertions.
  """
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions

  alias YscWeb.Workers.MembershipRenewalReminderWorker
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  @subject "Your YSC Membership Renews in 7 Days"

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Daily cron job
  # ---------------------------------------------------------------------------

  describe "perform/1" do
    test "returns :ok when there are no subscriptions" do
      assert :ok = MembershipRenewalReminderWorker.perform(build_job())
      refute_email_sent(subject: @subject)
    end

    test "sends reminder to member renewing in exactly 7 days who has a payment method" do
      user = user_fixture()
      insert_subscription(user, days_from_now(7))
      insert_payment_method(user)

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      assert_email_sent(subject: @subject, to: {nil, user.email})
    end

    test "does not send reminder to member renewing in 7 days without a payment method" do
      user = user_fixture()
      insert_subscription(user, days_from_now(7))

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      refute_email_sent(subject: @subject)
    end

    test "does not send reminder for a subscription renewing in 6 days" do
      user = user_fixture()
      insert_subscription(user, days_from_now(6))

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      refute_email_sent(subject: @subject)
    end

    test "does not send reminder for a subscription renewing in 8 days" do
      user = user_fixture()
      insert_subscription(user, days_from_now(8))

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      refute_email_sent(subject: @subject)
    end

    test "ignores subscriptions already scheduled for cancellation (ends_at set)" do
      user = user_fixture()
      insert_subscription(user, days_from_now(7), ends_at: days_from_now(6))

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      refute_email_sent(subject: @subject)
    end

    test "ignores subscriptions with a non-active stripe_status" do
      user = user_fixture()
      insert_subscription(user, days_from_now(7), stripe_status: "past_due")

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      refute_email_sent(subject: @subject)
    end

    test "sends reminders to all qualifying members on the same renewal day" do
      user1 = user_fixture()
      user2 = user_fixture()
      insert_subscription(user1, days_from_now(7))
      insert_subscription(user2, days_from_now(7))
      insert_payment_method(user1)
      insert_payment_method(user2)

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      assert_email_sent(subject: @subject, to: {nil, user1.email})
      assert_email_sent(subject: @subject, to: {nil, user2.email})
    end

    test "only sends to members with a payment method when some do not have one" do
      user_with_pm = user_fixture()
      user_without_pm = user_fixture()
      insert_subscription(user_with_pm, days_from_now(7))
      insert_subscription(user_without_pm, days_from_now(7))
      insert_payment_method(user_with_pm)

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())

      assert_email_sent(subject: @subject, to: {nil, user_with_pm.email})

      # refute_email_sent/1 does not accept function arguments or dynamic `to:`
      # values at compile time, so we inspect Swoosh's process-level email store
      # directly to verify no renewal reminder was sent to the user without a PM.
      no_pm_email = user_without_pm.email

      assert [] ==
               Process.get(Swoosh.Adapters.Test, [])
               |> Enum.filter(fn email ->
                 email.subject == @subject and
                   Enum.any?(email.to, fn {_, addr} -> addr == no_pm_email end)
               end)
    end

    test "handles a subscription with nil current_period_end without raising" do
      user = user_fixture()

      %Subscription{
        user_id: user.id,
        stripe_id: "sub_nil_end_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        name: "membership",
        current_period_end: nil,
        current_period_start: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

      assert :ok = MembershipRenewalReminderWorker.perform(build_job())
    end
  end

  # ---------------------------------------------------------------------------
  # Admin billing anchor move
  # ---------------------------------------------------------------------------

  describe "schedule_reminder_if_within_window/2" do
    test "sends reminder immediately when new date is 1 day away and user has a payment method" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(1))
      insert_payment_method(user)

      assert :ok =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      assert_email_sent(subject: @subject, to: {nil, user.email})
    end

    test "sends reminder immediately when new date is 3 days away and user has a payment method" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(3))
      insert_payment_method(user)

      assert :ok =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      assert_email_sent(subject: @subject, to: {nil, user.email})
    end

    test "sends reminder when new date is 5 days away and user has a payment method" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(5))
      insert_payment_method(user)

      assert :ok =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      assert_email_sent(subject: @subject, to: {nil, user.email})
    end

    test "skips and sends no email when user has no payment method on file" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(3))

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      refute_email_sent(subject: @subject)
    end

    test "skips and sends no email when new date is 14 days away" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(14))

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      refute_email_sent(subject: @subject)
    end

    test "skips and sends no email when new date is in the past" do
      user = user_fixture()
      subscription = insert_subscription(user, days_from_now(-2))

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      refute_email_sent(subject: @subject)
    end

    test "skips when subscription is already scheduled for cancellation (ends_at set)" do
      user = user_fixture()

      subscription =
        insert_subscription(user, days_from_now(3), ends_at: days_from_now(2))

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      refute_email_sent(subject: @subject)
    end

    test "skips when subscription is not active" do
      user = user_fixture()

      subscription =
        insert_subscription(user, days_from_now(3), stripe_status: "canceled")

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      refute_email_sent(subject: @subject)
    end

    test "email contains the correct renewal date" do
      user = user_fixture()
      renewal = days_from_now(3)
      subscription = insert_subscription(user, renewal)
      insert_payment_method(user)

      assert :ok =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 subscription
               )

      expected_date =
        renewal
        |> DateTime.to_date()
        |> Calendar.strftime("%B %d, %Y")

      assert_email_sent(subject: @subject, html_body: ~r/#{expected_date}/)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_job do
    %Oban.Job{
      id: 1,
      args: %{},
      worker: "YscWeb.Workers.MembershipRenewalReminderWorker",
      queue: "default",
      state: "available",
      attempt: 1
    }
  end

  # Adds n full days to now and truncates to second precision.
  # Use values clearly within or outside the 7-day window to avoid
  # off-by-one issues from DateTime.diff/3 truncation:
  #   within window  → 1, 3, 5 days
  #   outside window → 14 days
  defp days_from_now(n) do
    DateTime.utc_now()
    |> DateTime.add(n, :day)
    |> DateTime.truncate(:second)
  end

  defp insert_payment_method(user) do
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
      is_default: true
    }
    |> Repo.insert!()
  end

  defp insert_subscription(user, renewal_date, opts \\ []) do
    stripe_status = Keyword.get(opts, :stripe_status, "active")
    ends_at = Keyword.get(opts, :ends_at, nil)

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
      current_period_end: renewal_date,
      current_period_start: start_date,
      ends_at: ends_at_truncated
    }
    |> Repo.insert!()
  end
end
