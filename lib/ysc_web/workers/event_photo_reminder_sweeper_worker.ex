defmodule YscWeb.Workers.EventPhotoReminderSweeperWorker do
  @moduledoc """
  Daily safety net: sends photo reminders for published events that ended on or before
  yesterday (America/Los_Angeles) but were not scheduled or sent.
  """
  require Ysc.Logging

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

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
      where:
        fragment(
          "(timezone(?, timezone('UTC', coalesce(?, ?))))::date <= ?",
          ^@timezone,
          e.end_date,
          e.start_date,
          type(^yesterday, :date)
        ),
      preload: [event: e]
    )
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn %{event: event} = collection, :ok ->
      Ysc.Logging.info("Sweeper sending event photo reminder",
        event_id: event.id
      )

      case EventPhotoReminderWorker.send_reminders(event, collection) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp yesterday_in_la do
    DateTime.utc_now()
    |> DateTime.shift_zone!(@timezone)
    |> DateTime.to_date()
    |> Date.add(-1)
  end
end
