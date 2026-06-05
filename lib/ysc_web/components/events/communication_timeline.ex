defmodule YscWeb.Components.Events.CommunicationTimeline do
  @moduledoc """
  Unified communication history timeline for the admin event Updates tab.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  alias Ysc.EventPhotos
  alias Ysc.Events.Event
  alias Ysc.Events.EventUpdate

  attr :entries, :list, required: true

  def communication_timeline(assigns) do
    ~H"""
    <div
      id="communication-timeline"
      class="rounded p-6 border border-zinc-200"
    >
      <h2 class="text-lg font-bold text-zinc-800 mb-6">Communication History</h2>

      <p :if={@entries == []} class="text-sm text-zinc-500">
        No communications sent yet. Updates and automated emails will appear here.
      </p>

      <ol
        :if={@entries != []}
        class="relative border-l-2 border-zinc-200 ml-2.5 space-y-0"
      >
        <li
          :for={entry <- @entries}
          id={"timeline-item-#{entry.id}"}
          class="relative pl-10 pb-8 last:pb-0"
        >
          <span class={[
            "absolute -left-[17px] -top-1 z-10 flex items-center justify-center",
            "w-8 h-8 rounded-full border-2 border-zinc-50 shadow-sm",
            entry_icon_bg(entry)
          ]}>
            <.icon name={entry.icon} class={["w-4 h-4", entry_icon_color(entry)]} />
          </span>

          <h3 class="flex flex-wrap items-center gap-2 mb-1 text-sm font-semibold text-zinc-900 min-w-0">
            {entry.title}
            <span
              :for={badge <- entry.badges}
              class={badge_class(badge)}
            >
              {badge}
            </span>
          </h3>

          <time
            :if={entry.status != :pending and entry.status != :scheduled}
            class="block mb-2 text-xs font-normal leading-none text-zinc-400"
          >
            {format_datetime(entry.occurred_at)}
          </time>

          <p
            :if={entry.status == :pending}
            class="mb-2 text-xs font-medium text-amber-600"
          >
            Sending…
          </p>

          <p
            :if={entry.status == :scheduled}
            class="mb-2 text-xs font-medium text-zinc-500"
          >
            Scheduled for {format_datetime(entry.occurred_at)}
          </p>

          <p class="mb-2 text-sm font-normal text-zinc-600 line-clamp-2">
            {entry.preview}
          </p>

          <p :if={entry.recipient_label} class="text-xs text-zinc-500">
            {entry.recipient_label}
          </p>

          <p :if={entry.sent_by_name} class="text-xs text-zinc-500 mt-1">
            by {entry.sent_by_name}
          </p>
        </li>
      </ol>
    </div>
    """
  end

  @doc """
  Builds timeline entries from event updates, publication notifications, and photo reminders.
  """
  def build_entries(%Event{} = event, event_updates, photo_collection) do
    update_entries = Enum.map(event_updates, &event_update_entry/1)

    publication_entries =
      case publication_notification_entry(event) do
        nil -> []
        entry -> [entry]
      end

    photo_entries =
      case photo_reminder_entry(event, photo_collection) do
        nil -> []
        entry -> [entry]
      end

    all_entries = update_entries ++ publication_entries ++ photo_entries

    {sent, scheduled} = Enum.split_with(all_entries, &(&1.status != :scheduled))

    sent_sorted = Enum.sort_by(sent, & &1.sort_at, {:desc, DateTime})
    scheduled_sorted = Enum.sort_by(scheduled, & &1.sort_at, DateTime)

    sent_sorted ++ scheduled_sorted
  end

  defp event_update_entry(%EventUpdate{} = update) do
    preview =
      update.rendered_body
      |> HtmlSanitizeEx.strip_tags()
      |> String.trim()

    status =
      if update.sent_at do
        :sent
      else
        :pending
      end

    occurred_at = update.sent_at || update.inserted_at

    %{
      id: "update-#{update.id}",
      type: :event_update,
      status: status,
      occurred_at: occurred_at,
      sort_at: occurred_at,
      title:
        if(update.title in [nil, ""], do: "Event Update", else: update.title),
      preview: preview,
      icon: "hero-paper-airplane",
      badges: event_update_badges(update),
      recipient_label:
        if(update.recipient_count,
          do: "#{update.recipient_count} recipient(s)",
          else: nil
        ),
      sent_by_name: sent_by_name(update.sent_by)
    }
  end

  defp event_update_badges(%EventUpdate{show_on_event_page: true}) do
    ["Email", "Event Page"]
  end

  defp event_update_badges(%EventUpdate{}) do
    ["Email"]
  end

  defp publication_notification_entry(%Event{} = event) do
    published? = event.state in [:published, "published"]

    cond do
      not published? ->
        nil

      event.notification_sent_at ->
        %{
          id: "publication-#{event.id}",
          type: :event_published,
          status: :sent,
          occurred_at: event.notification_sent_at,
          sort_at: event.notification_sent_at,
          title: "New Event Announcement",
          preview:
            "Notified members that #{event.title} was added to the calendar.",
          icon: "hero-megaphone",
          badges: ["Automated Email"],
          recipient_label:
            if(event.notification_recipient_count != nil,
              do: "#{event.notification_recipient_count} member(s) notified",
              else: nil
            ),
          sent_by_name: nil
        }

      publication_notification_schedulable?(event) ->
        scheduled_at = DateTime.add(event.published_at, 3600, :second)

        %{
          id: "publication-scheduled-#{event.id}",
          type: :event_published,
          status: :scheduled,
          occurred_at: scheduled_at,
          sort_at: scheduled_at,
          title: "New Event Announcement",
          preview: "Members with event notifications enabled will be notified.",
          icon: "hero-megaphone",
          badges: ["Automated Email", "Scheduled"],
          recipient_label: nil,
          sent_by_name: nil
        }

      true ->
        nil
    end
  end

  defp publication_notification_schedulable?(%Event{} = event) do
    event.published_at != nil and event_in_future?(event)
  end

  defp photo_reminder_entry(%Event{} = event, photo_collection) do
    published? = event.state in [:published, "published"]

    cond do
      not published? or is_nil(photo_collection) ->
        nil

      photo_collection.reminder_sent_at ->
        count = photo_collection.reminder_recipient_count

        preview =
          if count != nil do
            "System sent photo upload links to #{count} attendee(s)."
          else
            "System sent photo upload links to attendees."
          end

        %{
          id: "photo-reminder-#{photo_collection.id}",
          type: :photo_reminder,
          status: :sent,
          occurred_at: photo_collection.reminder_sent_at,
          sort_at: photo_collection.reminder_sent_at,
          title: "Photo Upload Reminder",
          preview: preview,
          icon: "hero-camera",
          badges: ["Automated Email"],
          recipient_label:
            if(count != nil, do: "#{count} attendee(s)", else: nil),
          sent_by_name: nil
        }

      photo_reminder_schedulable?(event) ->
        scheduled_at = EventPhotos.photo_reminder_scheduled_at(event)

        %{
          id: "photo-reminder-scheduled-#{photo_collection.id}",
          type: :photo_reminder,
          status: :scheduled,
          occurred_at: scheduled_at,
          sort_at: scheduled_at,
          title: "Photo Upload Reminder",
          preview:
            "Attendees will receive photo upload links the morning after the event ends.",
          icon: "hero-camera",
          badges: ["Automated Email", "Scheduled"],
          recipient_label: nil,
          sent_by_name: nil
        }

      true ->
        nil
    end
  end

  defp photo_reminder_schedulable?(event) do
    case EventPhotos.photo_reminder_scheduled_at(event) do
      nil -> false
      scheduled_at -> DateTime.compare(scheduled_at, DateTime.utc_now()) == :gt
    end
  end

  defp event_in_future?(%Event{} = event) do
    case combine_date_time(event.start_date, event.start_time) do
      nil -> false
      datetime -> DateTime.compare(datetime, DateTime.utc_now()) == :gt
    end
  end

  defp combine_date_time(nil, _), do: nil
  defp combine_date_time(_, nil), do: nil

  defp combine_date_time(%DateTime{} = date, %Time{} = time) do
    date_part = date |> DateTime.to_naive() |> NaiveDateTime.to_date()
    NaiveDateTime.new!(date_part, time) |> DateTime.from_naive!("Etc/UTC")
  end

  defp combine_date_time(date, time)
       when not is_nil(date) and not is_nil(time) do
    NaiveDateTime.new!(date, time) |> DateTime.from_naive!("Etc/UTC")
  end

  defp sent_by_name(%{first_name: first, last_name: last})
       when is_binary(first) and is_binary(last) do
    "#{first} #{last}"
  end

  defp sent_by_name(_), do: nil

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y at %I:%M %p")
  end

  defp format_datetime(_), do: ""

  defp entry_icon_bg(%{type: :event_update}), do: "bg-blue-100"
  defp entry_icon_bg(%{type: :event_published}), do: "bg-violet-100"

  defp entry_icon_bg(%{type: :photo_reminder, status: :scheduled}),
    do: "bg-zinc-100"

  defp entry_icon_bg(%{type: :photo_reminder}), do: "bg-zinc-100"

  defp entry_icon_color(%{type: :event_update}), do: "text-blue-600"
  defp entry_icon_color(%{type: :event_published}), do: "text-violet-600"
  defp entry_icon_color(%{type: :photo_reminder}), do: "text-zinc-600"

  defp badge_class("Scheduled"),
    do: "bg-zinc-100 text-zinc-700 text-xs font-medium px-2.5 py-0.5 rounded"

  defp badge_class("Event Page"),
    do: "bg-green-100 text-green-800 text-xs font-medium px-2.5 py-0.5 rounded"

  defp badge_class("Email"),
    do: "bg-blue-100 text-blue-800 text-xs font-medium px-2.5 py-0.5 rounded"

  defp badge_class(_),
    do: "bg-zinc-100 text-zinc-800 text-xs font-medium px-2.5 py-0.5 rounded"
end
