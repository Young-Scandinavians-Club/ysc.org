defmodule Ysc.Forms do
  @moduledoc """
  Context module for managing form submissions.

  Handles creation and processing of volunteer applications and conduct violation reports.
  """
  require Logger
  import Ecto.Query, warn: false
  alias Ysc.Repo

  def create_volunteer(changeset) do
    case Repo.insert(changeset) do
      {:ok, volunteer} ->
        send_volunteer_emails(volunteer)
        {:ok, volunteer}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_conduct_violation_report(changeset) do
    case Repo.insert(changeset) do
      {:ok, report} ->
        send_conduct_violation_emails(report)
        {:ok, report}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_contact_form(changeset) do
    case Repo.insert(changeset) do
      {:ok, contact_form} ->
        send_contact_form_emails(contact_form)
        {:ok, contact_form}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp format_datetime_for_email(datetime) do
    # Convert UTC datetime to PST timezone
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp format_volunteer_interests(volunteer) do
    interests = []

    interests =
      if volunteer.interest_events,
        do: interests ++ ["Events/Parties"],
        else: interests

    interests =
      if volunteer.interest_activities,
        do: interests ++ ["Activities"],
        else: interests

    interests =
      if volunteer.interest_clear_lake,
        do: interests ++ ["Clear Lake"],
        else: interests

    interests =
      if volunteer.interest_tahoe, do: interests ++ ["Tahoe"], else: interests

    interests =
      if volunteer.interest_marketing,
        do: interests ++ ["Marketing"],
        else: interests

    interests =
      if volunteer.interest_website,
        do: interests ++ ["Website"],
        else: interests

    interests
  end

  defp send_conduct_violation_emails(report) do
    Logger.info("Starting conduct violation email process",
      report_id: report.id,
      email: report.email,
      submitted_at: report.inserted_at
    )

    try do
      # Send confirmation email to reporter
      confirmation_variables = %{
        first_name: report.first_name,
        last_name: report.last_name,
        summary: report.summary,
        anonymous: report.anonymous
      }

      confirmation_idempotency_key =
        "conduct_violation_confirmation_#{report.id}"

      Logger.info("Scheduling confirmation email",
        report_id: report.id,
        email: report.email
      )

      confirmation_result =
        YscWeb.Emails.Notifier.schedule_email(
          report.email,
          confirmation_idempotency_key,
          YscWeb.Emails.ConductViolationConfirmation.get_subject(),
          "conduct_violation_confirmation",
          confirmation_variables,
          ""
        )

      case confirmation_result do
        %Oban.Job{} = job ->
          Logger.info(
            "Conduct violation confirmation email scheduled successfully",
            report_id: report.id,
            email: report.email,
            job_id: job.id,
            idempotency_key: confirmation_idempotency_key
          )

        {:error, reason} ->
          Logger.error(
            "Failed to schedule conduct violation confirmation email",
            report_id: report.id,
            email: report.email,
            error: reason
          )
      end

      # Send notification email to board
      board_variables = %{
        first_name: report.first_name,
        last_name: report.last_name,
        email: report.email,
        phone: report.phone,
        summary: report.summary,
        anonymous: report.anonymous,
        report_id: report.id,
        submitted_at: format_datetime_for_email(report.inserted_at)
      }

      board_idempotency_key =
        "conduct_violation_board_notification_#{report.id}"

      Logger.info("Scheduling board notification email", report_id: report.id)

      board_result =
        YscWeb.Emails.Notifier.schedule_email_to_board(
          board_idempotency_key,
          YscWeb.Emails.ConductViolationBoardNotification.get_subject(),
          "conduct_violation_board_notification",
          board_variables
        )

      case board_result do
        %Oban.Job{} = job ->
          Logger.info(
            "Conduct violation board notification email scheduled successfully",
            report_id: report.id,
            job_id: job.id,
            idempotency_key: board_idempotency_key
          )

        {:error, reason} ->
          Logger.error(
            "Failed to schedule conduct violation board notification email",
            report_id: report.id,
            error: reason
          )
      end
    rescue
      error ->
        Logger.error("Failed to send conduct violation emails",
          report_id: report.id,
          email: report.email,
          error: error,
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_volunteer_emails(volunteer) do
    Logger.info("Starting volunteer email process",
      volunteer_id: volunteer.id,
      email: volunteer.email,
      submitted_at: volunteer.inserted_at
    )

    try do
      interests = format_volunteer_interests(volunteer)

      # Send confirmation email to volunteer
      confirmation_variables = %{
        name: volunteer.name,
        interests: interests
      }

      confirmation_idempotency_key = "volunteer_confirmation_#{volunteer.id}"

      Logger.info("Scheduling confirmation email",
        volunteer_id: volunteer.id,
        email: volunteer.email
      )

      confirmation_result =
        YscWeb.Emails.Notifier.schedule_email(
          volunteer.email,
          confirmation_idempotency_key,
          YscWeb.Emails.VolunteerConfirmation.get_subject(),
          "volunteer_confirmation",
          confirmation_variables,
          ""
        )

      case confirmation_result do
        %Oban.Job{} = job ->
          Logger.info("Volunteer confirmation email scheduled successfully",
            volunteer_id: volunteer.id,
            email: volunteer.email,
            job_id: job.id,
            idempotency_key: confirmation_idempotency_key
          )

        {:error, reason} ->
          Logger.error("Failed to schedule volunteer confirmation email",
            volunteer_id: volunteer.id,
            email: volunteer.email,
            error: reason
          )
      end

      # Send notification email to board
      board_variables = %{
        name: volunteer.name,
        email: volunteer.email,
        volunteer_id: volunteer.id,
        interests: interests,
        submitted_at: format_datetime_for_email(volunteer.inserted_at)
      }

      board_idempotency_key = "volunteer_board_notification_#{volunteer.id}"

      Logger.info("Scheduling board notification email",
        volunteer_id: volunteer.id
      )

      board_result =
        YscWeb.Emails.Notifier.schedule_email_to_board(
          board_idempotency_key,
          YscWeb.Emails.VolunteerBoardNotification.get_subject(),
          "volunteer_board_notification",
          board_variables
        )

      case board_result do
        %Oban.Job{} = job ->
          Logger.info(
            "Volunteer board notification email scheduled successfully",
            volunteer_id: volunteer.id,
            job_id: job.id,
            idempotency_key: board_idempotency_key
          )

        {:error, reason} ->
          Logger.error("Failed to schedule volunteer board notification email",
            volunteer_id: volunteer.id,
            error: reason
          )
      end
    rescue
      error ->
        Logger.error("Failed to send volunteer emails",
          volunteer_id: volunteer.id,
          email: volunteer.email,
          error: error,
          stacktrace: __STACKTRACE__
        )
    end
  end

  defp send_contact_form_emails(contact_form) do
    Logger.info("Starting contact form email process",
      contact_form_id: contact_form.id,
      email: contact_form.email,
      subject: contact_form.subject,
      submitted_at: contact_form.inserted_at
    )

    try do
      # Send notification email to board
      board_variables = %{
        name: contact_form.name,
        email: contact_form.email,
        subject: contact_form.subject,
        message: contact_form.message,
        contact_form_id: contact_form.id,
        submitted_at: format_datetime_for_email(contact_form.inserted_at)
      }

      board_idempotency_key =
        "contact_form_board_notification_#{contact_form.id}"

      Logger.info("Scheduling board notification email",
        contact_form_id: contact_form.id
      )

      board_result =
        YscWeb.Emails.Notifier.schedule_email_to_board(
          board_idempotency_key,
          "New Contact Form: #{contact_form.subject}",
          "contact_form_board_notification",
          board_variables
        )

      case board_result do
        %Oban.Job{} = job ->
          Logger.info(
            "Contact form board notification email scheduled successfully",
            contact_form_id: contact_form.id,
            job_id: job.id,
            idempotency_key: board_idempotency_key
          )

        {:error, reason} ->
          Logger.error(
            "Failed to schedule contact form board notification email",
            contact_form_id: contact_form.id,
            error: reason
          )
      end
    rescue
      error ->
        Logger.error("Failed to send contact form emails",
          contact_form_id: contact_form.id,
          email: contact_form.email,
          error: error,
          stacktrace: __STACKTRACE__
        )
    end
  end
end
