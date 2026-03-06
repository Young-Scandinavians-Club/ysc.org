defmodule YscWeb.Workers.NewsletterScheduleChecker do
  @moduledoc """
  Backup safety net for scheduled newsletter editions.

  Runs every 5 minutes. Finds any editions whose `scheduled_at` has passed but
  whose status is still `:scheduled` (meaning the primary Oban job was lost or
  exhausted all retries), and enqueues a fresh `NewsletterSender` job for them.

  The `NewsletterSender` worker uses an Oban unique constraint keyed on
  `edition_id`, so if the primary job is still pending or running this insert
  is silently deduplicated and no double-send occurs.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Ysc.Logging

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Newsletter.Edition

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    overdue =
      from(e in Edition,
        where: e.status == :scheduled and e.scheduled_at <= ^now,
        select: e.id
      )
      |> Repo.all()

    Enum.each(overdue, fn edition_id ->
      result =
        %{edition_id: edition_id}
        |> YscWeb.Workers.NewsletterSender.new()
        |> Oban.insert()

      case result do
        {:ok, %{conflict?: true}} ->
          Ysc.Logging.info(
            "NewsletterScheduleChecker: primary job already queued, skipping",
            edition_id: edition_id
          )

        {:ok, _job} ->
          Ysc.Logging.info(
            "NewsletterScheduleChecker: enqueued overdue newsletter",
            edition_id: edition_id
          )

        {:error, reason} ->
          Ysc.Logging.error(
            "NewsletterScheduleChecker: failed to enqueue",
            edition_id: edition_id,
            error: inspect(reason)
          )
      end
    end)

    :ok
  end
end
