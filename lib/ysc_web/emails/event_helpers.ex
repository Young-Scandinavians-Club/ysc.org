defmodule YscWeb.Emails.EventHelpers do
  @moduledoc """
  Shared event payload for notification, save-the-date, update, cancellation,
  and photo-upload reminder emails.

  Those templates all need the same preload + start datetime + cover image +
  public event URL. Call `event_display/2` for a nested `@event` map, or
  `event_headline/2` when the template uses a flat `@event_title`.

  Welcome-email event cards use a different shape (`date_str` / `url` /
  `image_url`) and should not use this helper.

  ## Examples

      event_display(event, organizer: true)

      event
      |> event_display(preload: [:cover_image], event_url: false)
      |> Map.merge(%{upcoming_events_url: upcoming_events_url()})

      event_headline(event)
      |> Map.merge(%{upload_url: upload_url})
  """

  import YscWeb.Emails.Helpers,
    only: [
      event_cover_image_url: 1,
      event_url: 1,
      format_event_start_datetime: 2,
      plain_text_from_html: 1,
      preload_event_associations: 2
    ]

  alias Ysc.Events.Event

  @full_fields [
    :id,
    :title,
    :description,
    :start_date,
    :start_time,
    :end_date,
    :end_time,
    :location_name,
    :address,
    :age_restriction
  ]

  @doc """
  Raises when `event` is nil so blast workers fail with a clear error.
  """
  def require_event!(nil) do
    raise ArgumentError, "Event cannot be nil"
  end

  def require_event!(%Event{} = event), do: event

  @doc """
  Nested event map used by MJML as `@event`.

  `:description` is converted to plain text. Pass `organizer: true` to include
  `{first_name, last_name}` when the association is loaded.
  """
  def event_summary(event, opts \\ []) do
    fields = Keyword.get(opts, :fields, @full_fields)

    summary = Map.new(fields, &{&1, summary_value(event, &1)})

    if Keyword.get(opts, :organizer, false) do
      Map.put(summary, :organizer, organizer_summary(event))
    else
      summary
    end
  end

  @doc """
  `{first_name, last_name}` when `event.organizer` is loaded, otherwise `nil`.
  """
  def organizer_summary(event) do
    if Ecto.assoc_loaded?(event.organizer) && event.organizer do
      %{
        first_name: event.organizer.first_name,
        last_name: event.organizer.last_name
      }
    else
      nil
    end
  end

  @doc """
  Shared assigns for templates that render `@event`.

  Options:

    * `:preload` — associations to load (default `[:organizer, :cover_image]`)
    * `:fields` — keys in the nested `event` map (default identity, schedule, location, age)
    * `:organizer` — include `event.organizer` (default `false`)
    * `:event_url` — include the public event URL (default `true`)
  """
  def event_display(event, opts \\ []) do
    event = preload_for_email(event, opts)

    event
    |> media_assigns()
    |> Map.put(:event, event_summary(event, opts))
    |> maybe_put_event_url(event, opts)
  end

  @doc """
  Flat title + datetime + cover URL for the photo-upload reminder.

  Does not nest an `event` map and does not load the organizer.
  """
  def event_headline(event, opts \\ []) do
    opts = Keyword.put_new(opts, :preload, [:cover_image])
    event = preload_for_email(event, opts)

    event
    |> media_assigns()
    |> Map.put(:event_title, event.title)
  end

  defp preload_for_email(event, opts) do
    preload = Keyword.get(opts, :preload, [:organizer, :cover_image])

    event
    |> require_event!()
    |> preload_event_associations(preload)
  end

  defp media_assigns(event) do
    %{
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time),
      event_image_url: event_cover_image_url(event)
    }
  end

  defp maybe_put_event_url(assigns, event, opts) do
    if Keyword.get(opts, :event_url, true) do
      Map.put(assigns, :event_url, event_url(event.id))
    else
      assigns
    end
  end

  defp summary_value(event, :description),
    do: plain_text_from_html(event.description)

  defp summary_value(event, field), do: Map.get(event, field)
end
