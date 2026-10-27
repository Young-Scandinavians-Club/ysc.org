defmodule Ysc.GooglePhotos.PosterSyncWorker do
  @moduledoc """
  Syncs upcoming-event posters into the Google Photos albums (see
  `Ysc.GooglePhotos.PosterAlbums`).

  Enqueued whenever an event changes (debounced, since the admin editor
  auto-saves) and hourly by cron, which also removes posters for events that
  have ended and refreshes posters whose content changed (e.g. sold out).

  This is low-priority, best-effort work that must never affect admins or
  visitors: every failure is swallowed and logged as a warning, jobs never
  retry (the next event change or hourly run is the retry), and it runs last on
  a single-concurrency queue so it can't compete with real work.
  """

  use Oban.Worker,
    queue: :google_photos,
    max_attempts: 1,
    priority: 9,
    unique: [period: 60, states: [:available, :scheduled]]

  require Ysc.Logging

  alias Ysc.Events.Event
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.PosterAlbums

  @debounce_seconds 45

  @doc """
  Queues a sync after an event changes. Always returns `:ok` and never raises or
  exits, whatever goes wrong (database, Oban, Google Photos configuration).

  A no-op when Google Photos isn't connected, or when the event is neither
  published nor already on a poster album (nothing to add or remove).
  """
  def enqueue_for_event(%Event{} = event) do
    if GooglePhotos.uploads_available?() and
         (event.state == :published or PosterAlbums.has_items?(event.id)) do
      {:ok, _job} = %{} |> new(schedule_in: @debounce_seconds) |> Oban.insert()
    end

    :ok
  rescue
    error -> log_ignored(error)
  catch
    kind, reason -> log_ignored({kind, reason})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if GooglePhotos.uploads_available?() do
      case PosterAlbums.sync() do
        {:ok, summary} ->
          Ysc.Logging.info("Synced Google Photos event poster albums",
            published: summary.published,
            removed: summary.removed
          )

        {:error, reason} ->
          log_ignored(reason)
      end
    end

    :ok
  rescue
    error -> log_ignored(error)
  catch
    kind, reason -> log_ignored({kind, reason})
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  defp log_ignored(reason) do
    Ysc.Logging.warning("Ignoring Google Photos poster sync failure",
      error: inspect(reason, limit: 20)
    )

    :ok
  end
end
