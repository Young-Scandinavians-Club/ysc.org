defmodule YscWeb.Workers.EventPhotoReminderSweeperWorker do
  @moduledoc """
  Daily safety net: sends photo reminders for published events that ended yesterday
  but were not scheduled or sent.
  """
  require Ysc.Logging

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Ysc.EventPhotos
  alias Ysc.EventPhotos.Collection
  alias Ysc.Events.Event
  alias Ysc.Repo
  alias YscWeb.Workers.EventPhotoReminderWorker

  @timezone "America/Los_Angeles"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    yesterday = yesterday_in_la()

    from(c in Collection,
      join: e in Event,
      on: c.event_id == e.id,
      where: e.state in [:published, "published"],
      where: is_nil(c.reminder_sent_at),
      preload: [event: e]
    )
    |> Repo.all()
    |> Enum.filter(fn %{event: event} ->
      EventPhotos.effective_end_date(event) == yesterday
    end)
    |> Enum.each(fn %{event: event} = collection ->
      Ysc.Logging.info("Sweeper sending event photo reminder",
        event_id: event.id
      )

      EventPhotoReminderWorker.send_reminders(event, collection)
    end)

    :ok
  end

  defp yesterday_in_la do
    DateTime.utc_now()
    |> DateTime.shift_zone!(@timezone)
    |> DateTime.to_date()
    |> Date.add(-1)
  end
end
