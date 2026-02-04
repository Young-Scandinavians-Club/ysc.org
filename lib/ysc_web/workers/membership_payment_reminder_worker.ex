defmodule YscWeb.Workers.MembershipPaymentReminderWorker do
  @moduledoc """
  Oban worker for sending membership payment reminder emails.

  Checks if a user has paid for membership and sends a reminder email if they haven't.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Accounts

  alias YscWeb.Emails.{
    Notifier,
    MembershipPaymentReminder7Day,
    MembershipPaymentReminder30Day
  }

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "reminder_type" => reminder_type}
      }) do
    Logger.info("Processing membership payment reminder",
      user_id: user_id,
      reminder_type: reminder_type
    )

    case Accounts.get_user(user_id) do
      nil ->
        Logger.warning("User not found for membership payment reminder",
          user_id: user_id,
          reminder_type: reminder_type
        )

        :ok

      user ->
        # Check if user has active membership
        if Accounts.has_active_membership?(user) do
          Logger.info("User already has active membership, skipping reminder",
            user_id: user_id,
            reminder_type: reminder_type
          )

          :ok
        else
          # User hasn't paid, send reminder
          send_reminder_email(user, reminder_type)
        end
    end
  end

  defp send_reminder_email(user, "7day") do
    require Logger

    email_module = MembershipPaymentReminder7Day
    email_data = email_module.prepare_email_data(user)
    subject = email_module.get_subject()
    template_name = email_module.get_template_name()

    # Generate idempotency key to prevent duplicate emails
    idempotency_key = "membership_payment_reminder_7day_#{user.id}"

    Logger.info("Sending 7-day membership payment reminder",
      user_id: user.id,
      email: user.email
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
        Logger.info("7-day membership payment reminder scheduled successfully",
          user_id: user.id
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to schedule 7-day membership payment reminder",
          user_id: user.id,
          error: inspect(reason)
        )

        # Report to Sentry
        Sentry.capture_message(
          "Failed to schedule 7-day membership payment reminder",
          level: :error,
          extra: %{
            user_id: user.id,
            email: user.email,
            error: inspect(reason)
          },
          tags: %{
            email_template: template_name,
            reminder_type: "7day"
          }
        )

        {:error, reason}
    end
  end

  defp send_reminder_email(user, "30day") do
    require Logger

    email_module = MembershipPaymentReminder30Day
    email_data = email_module.prepare_email_data(user)
    subject = email_module.get_subject()
    template_name = email_module.get_template_name()

    # Generate idempotency key to prevent duplicate emails
    idempotency_key = "membership_payment_reminder_30day_#{user.id}"

    Logger.info("Sending 30-day membership payment reminder",
      user_id: user.id,
      email: user.email
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
        Logger.info("30-day membership payment reminder scheduled successfully",
          user_id: user.id
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to schedule 30-day membership payment reminder",
          user_id: user.id,
          error: inspect(reason)
        )

        # Report to Sentry
        Sentry.capture_message(
          "Failed to schedule 30-day membership payment reminder",
          level: :error,
          extra: %{
            user_id: user.id,
            email: user.email,
            error: inspect(reason)
          },
          tags: %{
            email_template: template_name,
            reminder_type: "30day"
          }
        )

        {:error, reason}
    end
  end

  defp send_reminder_email(_user, reminder_type) do
    require Logger

    Logger.warning("Unknown reminder type",
      reminder_type: reminder_type
    )

    {:error, "Unknown reminder type: #{reminder_type}"}
  end

  @doc """
  Schedules a 7-day membership payment reminder for a user.
  """
  def schedule_7day_reminder(user_id) do
    # Schedule for 7 days from now
    schedule_in_seconds = 7 * 24 * 60 * 60

    %{
      "user_id" => user_id,
      "reminder_type" => "7day"
    }
    |> new(schedule_in: schedule_in_seconds)
    |> Oban.insert()
  end

  @doc """
  Schedules a 30-day membership payment reminder for a user.
  """
  def schedule_30day_reminder(user_id) do
    # Schedule for 30 days from now
    schedule_in_seconds = 30 * 24 * 60 * 60

    %{
      "user_id" => user_id,
      "reminder_type" => "30day"
    }
    |> new(schedule_in: schedule_in_seconds)
    |> Oban.insert()
  end
end
