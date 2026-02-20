defmodule YscWeb.Workers.MembershipRenewalReminderWorker do
  @moduledoc """
  Oban worker that runs daily to send courtesy renewal reminder emails to members
  whose membership will automatically renew in 7 days.

  This gives members an opportunity to cancel before they are charged if they no
  longer wish to continue their membership.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias Ysc.Payments
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias YscWeb.Emails.{Notifier, MembershipRenewalReminder}

  @reminder_window_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ysc.Logging.info("Starting membership renewal reminder check (7-day)")

    seven_days_from_now =
      DateTime.utc_now()
      |> DateTime.add(@reminder_window_days, :day)
      |> DateTime.to_date()

    day_start = DateTime.new!(seven_days_from_now, ~T[00:00:00], "Etc/UTC")
    day_end = DateTime.new!(seven_days_from_now, ~T[23:59:59], "Etc/UTC")

    Ysc.Logging.info(
      "Checking for subscriptions renewing on #{seven_days_from_now}"
    )

    subscriptions =
      from(s in Subscription,
        where: s.current_period_end >= ^day_start,
        where: s.current_period_end <= ^day_end,
        where: s.stripe_status == "active",
        where: is_nil(s.ends_at),
        preload: [:user]
      )
      |> Repo.all()

    Ysc.Logging.info(
      "Found #{length(subscriptions)} subscriptions renewing in 7 days"
    )

    results =
      Enum.map(subscriptions, fn s -> maybe_send_reminder_email(s.user, s) end)

    success_count = Enum.count(results, fn r -> r == :ok end)

    error_count =
      Enum.count(results, fn
        {:error, _} -> true
        _ -> false
      end)

    Ysc.Logging.info(
      "Membership renewal reminder check complete",
      success_count: success_count,
      error_count: error_count,
      total: length(subscriptions)
    )

    :ok
  end

  @doc """
  Schedules a renewal reminder email immediately if the subscription's
  `current_period_end` falls within the #{@reminder_window_days}-day reminder window.

  This is called when an admin moves the billing anchor so that members still
  receive a courtesy notice even when the new date is too close for the daily
  cron job to catch it. The email is idempotent per user per renewal date, so
  calling this when a reminder was already sent for the same date is safe.
  """
  def schedule_reminder_if_within_window(user, subscription) do
    now = DateTime.utc_now()

    days_until_renewal =
      DateTime.diff(subscription.current_period_end, now, :day)

    within_window? =
      days_until_renewal >= 0 and days_until_renewal <= @reminder_window_days

    is_active? = subscription.stripe_status == "active"
    not_cancelling? = is_nil(subscription.ends_at)

    if within_window? and is_active? and not_cancelling? do
      Ysc.Logging.info(
        "Billing anchor moved within reminder window — sending renewal reminder immediately",
        user_id: user.id,
        days_until_renewal: days_until_renewal,
        renewal_date: subscription.current_period_end
      )

      maybe_send_reminder_email(user, subscription)
    else
      :skipped
    end
  end

  defp maybe_send_reminder_email(user, subscription) do
    case Payments.get_default_payment_method(user) do
      nil ->
        Ysc.Logging.debug(
          "Skipping renewal reminder — user has no payment method on file",
          user_id: user.id,
          subscription_id: subscription.id
        )

        :skipped

      _payment_method ->
        send_reminder_email(user, subscription)
    end
  end

  defp send_reminder_email(user, subscription) do
    email_data =
      MembershipRenewalReminder.prepare_email_data(user, subscription)

    subject = MembershipRenewalReminder.get_subject()
    template_name = MembershipRenewalReminder.get_template_name()
    renewal_date = DateTime.to_date(subscription.current_period_end)
    idempotency_key = "membership_renewal_reminder_#{user.id}_#{renewal_date}"

    Ysc.Logging.info("Sending membership renewal reminder",
      user_id: user.id,
      email: user.email,
      renewal_date: subscription.current_period_end
    )

    case Notifier.schedule_email(
           user.email,
           idempotency_key,
           subject,
           template_name,
           email_data,
           "",
           user.id
         ) do
      %Oban.Job{} ->
        Ysc.Logging.info(
          "Membership renewal reminder scheduled successfully",
          user_id: user.id,
          subscription_id: subscription.id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to schedule membership renewal reminder",
          user_id: user.id,
          subscription_id: subscription.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
