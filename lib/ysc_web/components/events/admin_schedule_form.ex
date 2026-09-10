defmodule YscWeb.AdminEventsLive.ScheduleEventForm do
  use YscWeb, :live_component

  alias Ysc.Events.Event

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"schedule-drop-#{@event_id}"}>
      <.form
        for={@form}
        as={:event}
        id={"schedule_form-#{@event_id}"}
        phx-submit="save"
        phx-change="validate"
        phx-target={@myself}
        phx-value-event_id={@event.id}
        class="space-y-4"
      >
        <.input
          type="datetime-local"
          field={@form[:publish_at]}
          label="Scheduled At"
          phx-mounted={JS.focus()}
        />

        <div class="flex justify-end">
          <.button type="submit" phx-disable-with="Saving...">Set Schedule</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{event: event} = assigns, socket) do
    # Format publish_at from UTC to PST for datetime-local input
    # We need to pass it as a string so the datetime-local input displays correctly
    attrs =
      case event.publish_at do
        %DateTime{} = dt ->
          %{"publish_at" => format_datetime_local(dt)}

        _ ->
          %{}
      end

    # Create changeset with formatted string value
    # Note: We're not using the changeset to save, just for form display
    changeset =
      event
      |> Event.changeset(attrs)
      # Prevent Ecto from trying to cast the string back to DateTime
      |> Map.put(:action, nil)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  defp format_datetime_local(%DateTime{} = datetime) do
    # Convert UTC datetime to America/Los_Angeles for datetime-local input
    # datetime-local inputs expect a naive datetime string in local timezone
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      socket.assigns.event
      |> Event.changeset(event_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    # Hand the request up to the parent LiveView. Cabin events get a
    # "block the booking calendar?" prompt before the schedule is set; the
    # parent owns both that prompt and the call to `Events.schedule_event/2`.
    send(
      self(),
      {__MODULE__, {:schedule_requested, event_params["publish_at"]}}
    )

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
