defmodule YscWeb.Components.Events.AddToCalendarButton do
  @moduledoc """
  Renders the `add-to-calendar-button` web component for an event.

  Callers still decide whether to show the button (upcoming events, presence
  of `start_date`, layout wrapper). Pass `light_mode` for the surrounding
  theme (`"bodyScheme"` on light pages, `"dark"` on the ticket QR screen).
  """
  use Phoenix.Component

  alias Ysc.Events.AddToCalendar

  @calendar_options "'Apple','Google','iCal','Outlook.com','Yahoo'"

  attr :event, :map, required: true

  attr :id, :string,
    default: nil,
    doc: "Optional DOM id on the web component"

  attr :light_mode, :string,
    default: "bodyScheme",
    doc: "add-to-calendar-button `light-mode` (`bodyScheme` or `dark`)"

  attr :class, :any, default: nil

  def add_to_calendar_button(assigns) do
    event = assigns.event

    assigns =
      assigns
      |> assign(:start_date, AddToCalendar.date(Map.get(event, :start_date)))
      |> assign(:end_date, AddToCalendar.date(AddToCalendar.end_date(event)))
      |> assign(:end_time, AddToCalendar.end_time(event))
      |> assign(:time_zone, AddToCalendar.timezone())
      |> assign(:options, @calendar_options)

    ~H"""
    <add-to-calendar-button
      id={@id}
      class={@class}
      name={@event.title}
      start-date={@start_date}
      end-date={@end_date}
      options={@options}
      start-time={@event.start_time}
      end-time={@end_time}
      time-zone={@time_zone}
      location={@event.location_name}
      size="4"
      light-mode={@light_mode}
    ></add-to-calendar-button>
    """
  end
end
