defmodule YscWeb.Workers.MembershipRenewalReminderWorkerTest do
  @moduledoc """
  Tests for MembershipRenewalReminderWorker (7-day courtesy renewal reminder).
  """
  use Ysc.DataCase, async: false

  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures

  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias YscWeb.Workers.MembershipRenewalReminderWorker
  alias YscWeb.Emails.{MembershipRenewalReminder, Notifier}

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "perform/1" do
    test "perform_job completes with no subscriptions" do
      assert :ok = perform_job(MembershipRenewalReminderWorker, %{})
    end

    test "completes when no subscriptions match the 7-day window" do
      user = user_fixture()
      # Renewal in 30 days — outside window
      insert_subscription(user, DateTime.utc_now() |> DateTime.add(30, :day))

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      refute_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "sends renewal reminder when subscription renews in exactly 7 days and user has default payment method" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at)
      insert_payment_method(user)

      assert :ok = MembershipRenewalReminderWorker.perform(job())

      assert_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "still sends reminder when default card expiry date is in the past" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at)

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_expired_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_exp_#{System.unique_integer([:positive])}",
        provider_type: "card",
        type: :card,
        last_four: "4242",
        exp_month: 1,
        exp_year: 2019,
        display_brand: "visa",
        is_default: true
      }
      |> Repo.insert!()

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      assert_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "skips reminder when user has no default payment method" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[14:30:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at)

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      refute_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "ignores subscriptions that are not active" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[10:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at, stripe_status: "canceled")
      insert_payment_method(user)

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      refute_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "ignores trialing subscriptions (query only includes active status)" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at, stripe_status: "trialing")
      insert_payment_method(user)

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      refute_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end

    test "perform completes when renewal reminder email job already exists (duplicate Oban insert)" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[12:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      sub = insert_subscription(user, renewal_at)
      insert_payment_method(user)

      email_data = MembershipRenewalReminder.prepare_email_data(user, sub)
      renewal_date = DateTime.to_date(sub.current_period_end)

      idempotency_key =
        "membership_renewal_reminder_#{user.id}_#{renewal_date}"

      assert %Oban.Job{} =
               Notifier.schedule_email(
                 user.email,
                 idempotency_key,
                 MembershipRenewalReminder.get_subject(),
                 MembershipRenewalReminder.get_template_name(),
                 email_data,
                 "",
                 user.id
               )

      assert :ok = MembershipRenewalReminderWorker.perform(job())
    end

    test "ignores subscriptions scheduled to end before renewal" do
      user = user_fixture()

      seven_days_from_now =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.to_date()

      renewal_at =
        DateTime.new!(seven_days_from_now, ~T[11:00:00], "Etc/UTC")
        |> DateTime.truncate(:second)

      ends_at =
        DateTime.utc_now()
        |> DateTime.add(1, :day)
        |> DateTime.truncate(:second)

      insert_subscription(user, renewal_at, ends_at: ends_at)
      insert_payment_method(user)

      assert :ok = MembershipRenewalReminderWorker.perform(job())
      refute_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end
  end

  describe "schedule_reminder_if_within_window/2" do
    test "returns :skipped when renewal is outside the 7-day window" do
      user = user_fixture()

      sub =
        insert_subscription(
          user,
          DateTime.utc_now()
          |> DateTime.add(20, :day)
          |> DateTime.truncate(:second)
        )

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 sub
               )
    end

    test "returns :skipped when subscription is not active" do
      user = user_fixture()

      renewal_at =
        DateTime.utc_now()
        |> DateTime.add(3, :day)
        |> DateTime.truncate(:second)

      sub = insert_subscription(user, renewal_at, stripe_status: "canceled")

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 sub
               )
    end

    test "returns :skipped when subscription has ends_at set (scheduled cancellation)" do
      user = user_fixture()
      insert_payment_method(user)

      renewal_at =
        DateTime.utc_now()
        |> DateTime.add(3, :day)
        |> DateTime.truncate(:second)

      ends_at =
        DateTime.utc_now()
        |> DateTime.add(10, :day)
        |> DateTime.truncate(:second)

      sub = insert_subscription(user, renewal_at, ends_at: ends_at)

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 sub
               )
    end

    test "returns :skipped when renewal date is already in the past" do
      user = user_fixture()
      insert_payment_method(user)

      renewal_at =
        DateTime.utc_now()
        |> DateTime.add(-2, :day)
        |> DateTime.truncate(:second)

      sub = insert_subscription(user, renewal_at)

      assert :skipped =
               MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                 user,
                 sub
               )
    end

    test "schedules email when anchor is within window and user has a payment method" do
      user = user_fixture()
      insert_payment_method(user)

      renewal_at =
        DateTime.utc_now()
        |> DateTime.add(2, :day)
        |> DateTime.truncate(:second)

      sub = insert_subscription(user, renewal_at)

      result =
        MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
          user,
          sub
        )

      assert result == :ok
      assert_email_sent(subject: "Your YSC Membership Renews in 7 Days")
    end
  end

  defp job do
    %Oban.Job{
      id: 1,
      args: %{},
      worker: "YscWeb.Workers.MembershipRenewalReminderWorker",
      queue: "default",
      state: "available",
      attempt: 1
    }
  end

  defp insert_subscription(user, renewal_date, opts \\ []) do
    stripe_status = Keyword.get(opts, :stripe_status, "active")
    ends_at = Keyword.get(opts, :ends_at, nil)

    renewal_date_truncated = DateTime.truncate(renewal_date, :second)

    ends_at_truncated =
      if ends_at, do: DateTime.truncate(ends_at, :second), else: nil

    start_date =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.truncate(:second)

    %Subscription{
      user_id: user.id,
      stripe_id: "sub_rem_#{System.unique_integer([:positive])}",
      stripe_status: stripe_status,
      name: "membership",
      current_period_end: renewal_date_truncated,
      current_period_start: start_date,
      ends_at: ends_at_truncated
    }
    |> Repo.insert!()
  end

  defp insert_payment_method(user) do
    %PaymentMethod{
      user_id: user.id,
      provider: :stripe,
      provider_id: "pm_rem_#{System.unique_integer([:positive])}",
      provider_customer_id: "cus_rem_#{System.unique_integer([:positive])}",
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
end
