defmodule YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker do
  @moduledoc """
  Oban worker that runs daily to check for memberships renewing in 14 days
  without a payment method on file.

  For users who paid with cash or other offline methods, this sends a courtesy
  reminder to add a payment method before their renewal date.
  """
  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias Ysc.Repo
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Payments
  alias YscWeb.Emails.{Notifier, MembershipRenewalPaymentMethodReminder}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting membership renewal payment method check")

    # Calculate the date 14 days from now
    fourteen_days_from_now =
      DateTime.utc_now()
      |> DateTime.add(14, :day)
      |> DateTime.to_date()

    # Calculate the start and end of that day for the query
    day_start = DateTime.new!(fourteen_days_from_now, ~T[00:00:00], "Etc/UTC")
    day_end = DateTime.new!(fourteen_days_from_now, ~T[23:59:59], "Etc/UTC")

    Logger.info(
      "Checking for subscriptions renewing on #{fourteen_days_from_now}"
    )

    # Find all active subscriptions renewing in 14 days
    subscriptions =
      from(s in Subscription,
        where: s.current_period_end >= ^day_start,
        where: s.current_period_end <= ^day_end,
        where: s.stripe_status == "active",
        where: is_nil(s.ends_at),
        preload: [:user]
      )
      |> Repo.all()

    Logger.info(
      "Found #{length(subscriptions)} subscriptions renewing in 14 days"
    )

    # Check each subscription for missing payment method
    results =
      Enum.map(subscriptions, fn subscription ->
        check_and_notify_subscription(subscription)
      end)

    success_count = Enum.count(results, fn r -> r == :ok end)

    error_count =
      Enum.count(results, fn
        {:error, _} -> true
        _ -> false
      end)

    Logger.info(
      "Membership renewal payment method check complete",
      success_count: success_count,
      error_count: error_count,
      total: length(subscriptions)
    )

    :ok
  end

  defp check_and_notify_subscription(subscription) do
    user = subscription.user

    # Check if user has a payment method
    case Payments.get_default_payment_method(user) do
      nil ->
        # No payment method on file, send reminder
        Logger.info("User has no payment method, sending reminder",
          user_id: user.id,
          subscription_id: subscription.id,
          renewal_date: subscription.current_period_end
        )

        send_reminder_email(user, subscription)

      _payment_method ->
        # User has payment method, no need to send reminder
        Logger.debug("User has payment method on file, skipping reminder",
          user_id: user.id,
          subscription_id: subscription.id
        )

        :ok
    end
  end

  defp send_reminder_email(user, subscription) do
    email_module = MembershipRenewalPaymentMethodReminder
    email_data = email_module.prepare_email_data(user, subscription)
    subject = email_module.get_subject()
    template_name = email_module.get_template_name()

    # Generate idempotency key to prevent duplicate emails
    # Include the renewal date to ensure one email per renewal period
    renewal_date = DateTime.to_date(subscription.current_period_end)

    idempotency_key =
      "membership_renewal_payment_method_reminder_#{user.id}_#{renewal_date}"

    Logger.info("Sending membership renewal payment method reminder",
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
        Logger.info(
          "Membership renewal payment method reminder scheduled successfully",
          user_id: user.id,
          subscription_id: subscription.id
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to schedule membership renewal payment method reminder",
          user_id: user.id,
          subscription_id: subscription.id,
          error: inspect(reason)
        )

        # Report to Sentry
        Sentry.capture_message(
          "Failed to schedule membership renewal payment method reminder",
          level: :error,
          extra: %{
            user_id: user.id,
            subscription_id: subscription.id,
            email: user.email,
            renewal_date: subscription.current_period_end,
            error: inspect(reason)
          },
          tags: %{
            email_template: template_name,
            worker: "membership_renewal_payment_method_checker"
          }
        )

        {:error, reason}
    end
  end
end
