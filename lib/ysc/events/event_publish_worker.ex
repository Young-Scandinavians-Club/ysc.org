defmodule Ysc.Events.EventPublishWorker do
  @moduledoc """
  Background worker for publishing scheduled events.

  This worker runs periodically to:
  - Find events with state = :scheduled AND publish_at <= now (UTC)
  - Publish those events automatically
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Ysc.Logging

  alias Ysc.Events.Event
  alias Ysc.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    publish_scheduled_events()
    {:ok, "Processed scheduled events"}
  end

  @doc """
  Manually trigger publishing of scheduled events.
  This can be called from a cron job or scheduled task.
  """
  def publish_scheduled_events do
    now = DateTime.utc_now()

    Event
    |> where([e], e.state == "scheduled")
    |> where([e], not is_nil(e.publish_at))
    |> where([e], e.publish_at <= ^now)
    |> Repo.all()
    |> Enum.each(fn event ->
      case Ysc.Events.publish_event(event) do
        {:ok, published_event} ->
          Ysc.Logging.info("Published scheduled event",
            event_id: event.id,
            reference_id: event.reference_id,
            title: event.title,
            scheduled_publish_at: event.publish_at,
            published_at: published_event.published_at
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          Ysc.Logging.error("Failed to publish scheduled event",
            event_id: event.id,
            reference_id: event.reference_id,
            title: event.title,
            errors: inspect(changeset.errors)
          )

        {:error, reason} ->
          Ysc.Logging.error("Failed to publish scheduled event",
            event_id: event.id,
            reference_id: event.reference_id,
            title: event.title,
            errors: inspect(reason)
          )
      end
    end)
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 60 seconds (may need to process multiple events)
    60_000
  end

  @doc false
  def ci_query_explain_query do
    now = DateTime.utc_now()

    from(e in Event,
      where: e.state == "scheduled",
      where: not is_nil(e.publish_at),
      where: e.publish_at <= ^now
    )
  end
end
