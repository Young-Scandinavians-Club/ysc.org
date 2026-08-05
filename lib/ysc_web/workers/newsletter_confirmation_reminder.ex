defmodule YscWeb.Workers.NewsletterConfirmationReminder do
  @moduledoc """
  Oban worker for the 24-hour double opt-in confirmation reminder.

  Scheduled once by `Ysc.Newsletter.request_confirmation/2`. The "is this
  still needed" check lives in `Ysc.Newsletter.deliver_confirmation_reminder/1`
  rather than only here, so any future manual/admin trigger gets the same
  safety check.
  """
  use Oban.Worker,
    queue: :transactional_mail,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:subscriber_id],
      states: :incomplete,
      period: :infinity
    ]

  alias Ysc.Newsletter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscriber_id" => subscriber_id}}) do
    Newsletter.deliver_confirmation_reminder(subscriber_id)
    :ok
  end

  @doc """
  Schedules the confirmation reminder for 24 hours from now.

  Unique per `subscriber_id` while a job is incomplete, so requesting
  confirmation more than once (e.g. resending after a rotated token) does
  not stack up duplicate reminder jobs.
  """
  def schedule(subscriber_id) do
    %{"subscriber_id" => subscriber_id}
    |> new(schedule_in: 24 * 60 * 60)
    |> Oban.insert()
  end
end
