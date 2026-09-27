defmodule YscWeb.Workers.AnnualAccessReviewWorker do
  @moduledoc """
  Runs every March 1 (see the Oban crontab) and emails the WebTech team the
  list of admin and volunteer accounts so access can be reviewed and revoked
  for anyone who has left the board.

  The idempotency key is scoped to the year, so a retry or re-run in the same
  year does not send a duplicate email.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.Accounts.AccessReview
  alias YscWeb.Emails.AdminAccessReview
  alias YscWeb.Emails.Notifier

  @timezone "America/Los_Angeles"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    year = current_year()

    assigns =
      AdminAccessReview.build_assigns(
        AccessReview.list_privileged_users(),
        year
      )

    case Notifier.schedule_email(
           Ysc.EmailConfig.webtech_email(),
           "annual_access_review_#{year}",
           AdminAccessReview.get_subject(year),
           AdminAccessReview.get_template_name(),
           assigns,
           "",
           nil
         ) do
      {:error, _} = error -> error
      _job -> :ok
    end
  end

  defp current_year do
    DateTime.shift_zone!(DateTime.utc_now(), @timezone).year
  end
end
