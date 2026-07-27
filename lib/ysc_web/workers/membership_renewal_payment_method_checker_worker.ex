defmodule YscWeb.Workers.MembershipRenewalPaymentMethodCheckerWorker do
  @moduledoc """
  Oban worker that runs daily to check for memberships renewing in 14 days
  without a payment method on file.

  For users who paid with cash or other offline methods, this sends a courtesy
  reminder to add a payment method before their renewal date.
  """
  require Ysc.Logging
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Payments
  alias YscWeb.Emails.{Notifier, MembershipRenewalPaymentMethodReminder}
  alias YscWeb.Workers.MembershipRenewalQuery

  @reminder_window_days 14

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ysc.Logging.info("Starting membership renewal payment method check")

    renewal_date =
      MembershipRenewalQuery.renewal_date_from_now(@reminder_window_days)

    Ysc.Logging.info("Checking for subscriptions renewing on #{renewal_date}")

    subscriptions =
      MembershipRenewalQuery.list_subscriptions_renewing_in_days(
        @reminder_window_days
      )

    Ysc.Logging.info(
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

    Ysc.Logging.info(
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
        Ysc.Logging.info("User has no payment method, sending reminder",
          user_id: user.id,
          subscription_id: subscription.id,
          renewal_date: subscription.current_period_end
        )

        send_reminder_email(user, subscription)

      _payment_method ->
        # User has payment method, no need to send reminder
        Ysc.Logging.debug("User has payment method on file, skipping reminder",
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

    Ysc.Logging.info("Sending membership renewal payment method reminder",
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
          "Membership renewal payment method reminder scheduled successfully",
          user_id: user.id,
          subscription_id: subscription.id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to schedule membership renewal payment method reminder",
          user_id: user.id,
          subscription_id: subscription.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
