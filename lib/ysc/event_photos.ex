defmodule Ysc.EventPhotos do
  @moduledoc """
  Event photo collections: upload URLs, reminder emails, and Google Photos album linkage.
  """

  import Ecto.Query

  alias Ysc.Ci.QueryExplain.Fixtures
  alias Ysc.EventPhotos.Collection
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo
  alias YscWeb.Emails.Helpers

  @timezone "America/Los_Angeles"

  @doc "Returns the collection for an event, or nil."
  def get_by_event_id(event_id) do
    Repo.one(from c in Collection, where: c.event_id == ^event_id)
  end

  @doc "Returns the collection for an upload token with event preloaded, or nil."
  def get_by_upload_token(upload_token) when is_binary(upload_token) do
    Collection
    |> where([c], c.upload_token == ^upload_token)
    |> preload(:event)
    |> Repo.one()
  end

  @doc "Returns the collection with event preloaded."
  def get_by_upload_token!(upload_token) do
    Collection
    |> where([c], c.upload_token == ^upload_token)
    |> preload(:event)
    |> Repo.one!()
  end

  @doc """
  Ensures a collection row exists for a published event (idempotent).
  """
  def ensure_collection_for_event(%Event{} = event) do
    case get_by_event_id(event.id) do
      %Collection{} = collection ->
        {:ok, collection}

      nil ->
        %Collection{
          event_id: event.id,
          upload_token: Ecto.UUID.generate()
        }
        |> Collection.insert_changeset()
        |> Repo.insert()
        |> case do
          {:ok, collection} ->
            {:ok, collection}

          {:error, %Ecto.Changeset{} = changeset} ->
            if event_id_conflict?(changeset) do
              case get_by_event_id(event.id) do
                %Collection{} = collection -> {:ok, collection}
                nil -> {:error, changeset}
              end
            else
              {:error, changeset}
            end
        end
    end
  end

  def ensure_collection_for_event(event_id) when is_binary(event_id) do
    case Repo.get(Event, event_id) do
      nil -> {:error, :not_found}
      event -> ensure_collection_for_event(event)
    end
  end

  @doc "Public upload page URL for a collection."
  def upload_url(%Collection{upload_token: token}) do
    Helpers.absolute_url("/events/photos/#{token}")
  end

  @doc "Persists the Google Photos album id after lazy creation."
  def set_google_album_id(%Collection{} = collection, album_id)
      when is_binary(album_id) do
    collection
    |> Collection.changeset(%{google_album_id: album_id})
    |> Repo.update()
  end

  @doc "Marks the post-event photo reminder as sent with the recipient count."
  def mark_reminder_sent(%Collection{} = collection, recipient_count) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    collection
    |> Collection.changeset(%{
      reminder_sent_at: now,
      reminder_recipient_count: recipient_count
    })
    |> Repo.update()
  end

  @doc """
  Calendar date when the event ends (for scheduling).

  `start_date`/`end_date` store the calendar date the admin picked, not a real
  instant (time-of-day lives in the separate `start_time`/`end_time` fields), so
  the date is read directly with no zone shift — matching how these dates are
  displayed everywhere else (e.g. `EventDateTime.combine/2`, `format_start_date/1`).
  """
  def effective_end_date(%Event{} = event) do
    date_field = event.end_date || event.start_date

    case date_field do
      %DateTime{} = dt ->
        DateTime.to_date(dt)

      %Date{} = date ->
        date

      nil ->
        nil
    end
  end

  @doc """
  UTC datetime for 9:00 AM America/Los_Angeles on the calendar day after the event ends.
  """
  def photo_reminder_scheduled_at(%Event{} = event) do
    case effective_end_date(event) do
      nil ->
        nil

      end_date ->
        reminder_date = Date.add(end_date, 1)

        reminder_date
        |> DateTime.new!(~T[09:00:00], @timezone)
        |> DateTime.shift_zone!("Etc/UTC")
    end
  end

  @doc """
  Sends photo reminder emails immediately (dev helper or forced resend).

  When `force: true`, clears `reminder_sent_at` and `reminder_recipient_count` before sending.
  """
  def deliver_reminder_now(event_or_id, opts \\ [])

  def deliver_reminder_now(%Event{} = event, opts) do
    force = Keyword.get(opts, :force, false)

    with {:ok, collection} <- ensure_collection_for_event(event) do
      collection =
        if force do
          collection
          |> Collection.changeset(%{
            reminder_sent_at: nil,
            reminder_recipient_count: nil
          })
          |> Repo.update!()
        else
          collection
        end

      YscWeb.Workers.EventPhotoReminderWorker.send_reminders(event, collection)
    end
  end

  def deliver_reminder_now(event_id, opts) when is_binary(event_id) do
    case Repo.get(Event, event_id) do
      nil -> {:error, :not_found}
      event -> deliver_reminder_now(event, opts)
    end
  end

  @doc """
  Returns true when the user's email is an event attendee (or user is full admin).
  """
  def authorized_to_upload?(%Event{} = event, user) do
    cond do
      user.role == :admin ->
        true

      is_binary(user.email) ->
        Events.event_update_recipient_email?(event.id, user.email)

      true ->
        false
    end
  end

  @doc "Album title for Google Photos: event title and formatted start date."
  def album_title(%Event{} = event) do
    date_label =
      case event.start_date do
        %DateTime{} = dt ->
          dt
          |> DateTime.to_date()
          |> Calendar.strftime("%b %-d, %Y")

        %Date{} = date ->
          Calendar.strftime(date, "%b %-d, %Y")

        _ ->
          nil
      end

    base =
      if date_label do
        "#{event.title} — #{date_label}"
      else
        event.title
      end

    Ysc.GooglePhotos.Limits.normalize_album_title(base)
  end

  @doc false
  def ci_query_explain_query do
    upload_token = Fixtures.uuid()

    Collection
    |> where([c], c.upload_token == ^upload_token)
    |> preload(:event)
  end

  defp event_id_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.constraints, fn
      %{
        constraint: :unique,
        constraint_name: "event_photo_collections_event_id_index"
      } ->
        true

      _ ->
        false
    end) or
      match?(
        [event_id: {"has already been taken", _}],
        changeset.errors
      )
  end
end
