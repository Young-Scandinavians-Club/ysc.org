defmodule YscWeb.AdminEventsNewLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Events.Event
  alias Ysc.Events

  alias Ysc.Events.Agenda
  alias Ysc.Agendas

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <div class="flex py-6 flex-col">
        <div class="flex flex-row justify-between">
          <div class="flex flex-col space-y-1">
            <div class="flex flex-row items-center space-x-3">
              <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
                <%= @event_title %>
              </h1>

              <div>
                <.badge type={event_state_to_badge_style(@state)}>
                  <%= String.capitalize("#{@state}") %>
                </.badge>
              </div>
            </div>

            <div
              :if={@start_date != nil && @start_date != ""}
              class="flex flex-row space-x-1 items-center"
            >
              <.icon name="hero-calendar-days" class="text-zinc-600" />
              <p class="text-sm text-zinc-600">
                <%= Ysc.Events.DateTimeFormatter.format_datetime(%{
                  start_date: format_date(@start_date),
                  start_time: format_time(@start_time),
                  end_date: format_date(@end_date),
                  end_time: format_time(@end_time)
                }) %>
              </p>
            </div>
          </div>

          <div class="pl-4 space-x-1 flex flex-row">
            <div :if={@event.state in [:draft, :scheduled]}>
              <.button
                color="blue"
                phx-click="publish-event"
                phx-disable-with="Publishing..."
              >
                <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1 me-1" />Publish
              </.button>
            </div>

            <div :if={@event.state in [:published]}>
              <.button
                color="red"
                phx-click="unpublish-event"
                phx-disable-with="Unpublishing..."
              >
                <.icon name="hero-document-arrow-down" class="w-5 h-5 -mt-1 me-1" />Unpublish
              </.button>
            </div>

            <.dropdown
              :if={@event.state in [:draft, :scheduled]}
              id="edit-post-more"
              right={true}
              class={
                Enum.join(
                  [
                    "text-zinc-100 px-3 leading-6 py-2 text-sm font-semibold transition duration-300",
                    @event.state == :scheduled && "bg-green-700 hover:bg-green-800",
                    @event.state != :scheduled && "bg-blue-700 hover:bg-blue-800"
                  ],
                  " "
                )
              }
            >
              <:button_block>
                <.icon name="hero-clock" class="w-5 h-5 me-1" /><%= schedule_button_text(
                  @event.state
                ) %>
                <.icon name="hero-chevron-down" class="ms-2" />
              </:button_block>

              <div class="w-full px-2 py-4">
                <.live_component
                  id={@event.id}
                  event={@event}
                  module={YscWeb.AdminEventsLive.ScheduleEventForm}
                  event_id={@event.id}
                />
              </div>
            </.dropdown>

            <.dropdown
              id="edit-event-more"
              right={true}
              class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
            >
              <:button_block>
                <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
              </:button_block>

              <div class="w-full divide-y divide-zinc-100 text-sm text-zinc-700">
                <ul class="py-2 text-sm font-medium text-zinc-800 px-2">
                  <li
                    :if={@event.state == :published}
                    class="block py-2 px-3 transition ease-in-out duration-200 hover:bg-zinc-100"
                  >
                    <button
                      type="button"
                      class="w-full text-left px-1"
                      phx-click="cancel-event"
                    >
                      <.icon name="hero-minus-circle" class="me-1 -mt-1 w-5 h-5" />Cancel Event
                    </button>
                  </li>

                  <li class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100">
                    <button
                      type="button"
                      class="w-full text-left px-1"
                      phx-click="delete-event"
                    >
                      <.icon name="hero-trash" class="w-5 h-5 -mt-1" />
                      <span>Delete Event</span>
                    </button>
                  </li>
                </ul>
              </div>
            </.dropdown>
          </div>
        </div>

        <div class="pt-4">
          <div class="text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
            <ul class="flex flex-wrap -mb-px">
              <li class="me-2">
                <.link
                  navigate={~p"/admin/events/#{@event.id}/edit"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :edit && "text-blue-600 border-blue-600 active",
                    @live_action != :edit &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Event Details
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/events/#{@event.id}/tickets"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :tickets &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :tickets &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Tickets
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :edit} class="relative py-8">
          <div class="border max-w-3xl rounded border-zinc-200 py-6 px-4 space-y-4">
            <h2 class="text-xl font-bold">Cover Image</h2>

            <div
              :if={@form[:image_id].value != nil && @form[:image_id].value != ""}
              class="w-full"
            >
              <button class="group relative w-full" phx-click="clear-cover-image">
                <div class="absolute flex items-center justify-center opacity-0 w-full h-full z-10 m-auto left-0 right-0 group-hover:opacity-100 transition duration-200 ease-in-out">
                  <.icon
                    name="hero-x-circle"
                    class="w-20 h-20 text-red-500 fill-red-500"
                  />
                </div>
                <div class="w-full group-hover:opacity-50 transition duration-200 ease-in-out">
                  <.live_component
                    id="cover-preview"
                    module={YscWeb.Components.Image}
                    image_id={@form[:image_id].value}
                    preferred_type={:optimized}
                  />
                </div>
              </button>
            </div>

            <.live_component
              :if={@form[:image_id].value == nil || @form[:image_id].value == ""}
              module={YscWeb.UploadComponent}
              id={:file}
              user_id={@current_user.id}
            />
          </div>

          <.form
            for={@form}
            id="new_event_form"
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            method="post"
            class="space-y-6 max-w-3xl"
          >
            <.input
              type="hidden"
              field={@form[:organizer_id]}
              value={@current_user.id}
            />
            <.input type="hidden" field={@form[:image_id]} />

            <div class="border rounded border-zinc-200 py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Basics</h2>
                <p class="text-zinc-600 text-sm">
                  Give your event a nice title and summary to attract attendees.
                </p>
              </div>
              <.input
                type="text"
                field={@form[:title]}
                label="Event Title*"
                phx-debounce="300"
                required
              />
              <.input
                type="text"
                field={@form[:description]}
                label={"Summary (#{@description_length}/200)*"}
                phx-debounce="300"
                required
              />
            </div>

            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <h2 class="text-xl font-bold mb-2">Date and Location</h2>

              <h3 class="text-lg font-medium">Date and Time</h3>
              <div class="flex flex-row w-full space-x-4">
                <div class="flex">
                  <.date_range_picker
                    label="Date*"
                    id="event_date"
                    form={@form}
                    start_date_field={@form[:start_date]}
                    end_date_field={@form[:end_date]}
                    min={Date.utc_today()}
                    allow_saturdays={true}
                  />
                </div>

                <.input
                  type="time"
                  id="start_time"
                  step="60"
                  field={@form[:start_time]}
                  label="Start Time*"
                />
                <.input
                  type="time"
                  id="end_time"
                  step="60"
                  field={@form[:end_time]}
                  label="End Time"
                />
              </div>

              <h3 class="text-lg pt-4 font-medium">Location</h3>
              <div class="space-y-4">
                <.input
                  type="text"
                  field={@form[:location_name]}
                  label="Location Name"
                  phx-debounce="300"
                />
                <.input
                  type="text"
                  field={@form[:address]}
                  label="Address"
                  phx-debounce="300"
                />
                <div class="flex flex-row space-x-4">
                  <.input
                    type="number"
                    step="any"
                    field={@form[:latitude]}
                    label="Latitude"
                  />
                  <.input
                    type="number"
                    step="any"
                    field={@form[:longitude]}
                    label="Longitude"
                  />
                </div>
                <div class="space-y-2">
                  <.live_component
                    id={"#{@event.id}-map"}
                    module={YscWeb.Components.MapComponent}
                    event_id={@event.id}
                    latitude={@form[:latitude].value}
                    longitude={@form[:longitude].value}
                    locked={false}
                  />
                  <p class="text-zinc-700 text-sm">
                    Click on the map to set marker to set or move the marker to set the location.
                  </p>
                </div>
              </div>
            </div>

            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Overview</h2>
                <p class="text-zinc-600 text-sm">
                  Add more details about the event to help attendees understand what to expect.
                </p>
              </div>

              <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none">
                <.input
                  type="hidden"
                  id="post[raw_body]"
                  field={@form[:raw_details]}
                  data-post-id={@event.id}
                  phx-hook="TrixHook"
                  phx-debounce={200}
                />
                <div id="richtext" phx-update="ignore">
                  <trix-editor
                    input="post[raw_body]"
                    class="trix-content block px-4 py-2 bg-white border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition border-l border-b border-r focus:ring-0 text-wrap"
                    placeholder="Write something delightful and nice..."
                  >
                  </trix-editor>
                </div>
              </div>
            </div>
          </.form>

          <div class="max-w-3xl mt-6">
            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Agenda</h2>
                <p class="text-zinc-600 text-sm">
                  Add schedules or itineraries to help attendees plan their day.
                </p>
              </div>

              <.button
                type="button"
                phx-click="add-agenda"
                phx-disable-with="Adding..."
              >
                <.icon name="hero-plus" class="-mt-0.5" /> Add Agenda
              </.button>

              <ul
                id="agendas"
                phx-update="stream"
                phx-hook="Sortable"
                class="w-full flex gap-3 snap-x overflow-x-auto"
              >
                <li
                  :for={{id, agenda} <- @streams.agendas}
                  id={id}
                  data-id={agenda.id}
                  class="py-4 bg-zinc-100 rounded-lg flex-shrink-0"
                >
                  <div class="mx-auto max-w-7xl px-4 space-y-4">
                    <div class="flex flex-row justify-between space-x-4">
                      <div class="w-full">
                        <.live_component
                          id={"edit-agenda-title-#{agenda.id}"}
                          module={YscWeb.AgendasLive.FormComponent}
                          agenda_id={agenda.id}
                          event_id={@event.id}
                          agenda={agenda}
                        />
                      </div>

                      <.link
                        phx-click="delete-agenda"
                        phx-value-id={agenda.id}
                        alt="delete agenda"
                      >
                        <.icon
                          name="hero-trash"
                          class="px-2 py-2 hover:bg-red-600 rounded transition duration-200"
                        />
                      </.link>
                    </div>

                    <.live_component
                      id={agenda.id}
                      module={YscWeb.AgendaEditComponent}
                      agenda={agenda}
                      event_id={@event.id}
                    />
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div :if={@live_action == :tickets} class="relative py-8">
          <div class="max-w-3xl">
            <div class="mb-6">
              <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
                <div>
                  <h2 class="text-xl font-bold">Event Capacity</h2>
                  <p class="text-zinc-600 text-sm">
                    Set the maximum number of attendees for this event. This limit applies across all ticket tiers.
                  </p>
                </div>

                <.form
                  for={@capacity_form}
                  id="capacity_form"
                  phx-submit="save-capacity"
                  phx-change="validate-capacity"
                  class="space-y-4"
                >
                  <div class="space-y-4">
                    <div class="flex items-center space-x-3">
                      <.input
                        type="checkbox"
                        field={@capacity_form[:unlimited_capacity]}
                        label="Unlimited capacity"
                        checked={
                          is_nil(@capacity_form[:max_attendees].value) ||
                            @capacity_form[:max_attendees].value == ""
                        }
                        phx-click="toggle-unlimited-capacity"
                      />
                    </div>

                    <div
                      :if={
                        !is_nil(@capacity_form[:max_attendees].value) &&
                          @capacity_form[:max_attendees].value != ""
                      }
                      class="space-y-2"
                    >
                      <.input
                        type="number"
                        field={@capacity_form[:max_attendees]}
                        label="Maximum Attendees"
                        min="1"
                      />
                    </div>
                  </div>
                </.form>
              </div>
            </div>

            <.live_component
              id={"ticket-tier-management-#{@event.id}"}
              module={YscWeb.AdminEventsLive.TicketTierManagement}
              event_id={@event.id}
              current_user={@current_user}
            />
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    if connected?(socket) do
      Agendas.subscribe(id)
      Events.subscribe()
    end

    event = Events.get_event!(id)
    event_changeset = Event.changeset(event, %{})

    # Initialize capacity form with unlimited_capacity virtual field
    capacity_attrs = %{
      "unlimited_capacity" => is_nil(event.max_attendees)
    }

    capacity_changeset = Event.changeset(event, capacity_attrs)
    agendas = Agendas.list_agendas_for_event(event.id)
    ticket_tiers = Events.list_ticket_tiers_for_event(event.id)
    tickets = Events.list_tickets_for_event(event.id)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:active_page, :events)
     |> assign(:capacity_form, to_form(capacity_changeset))
     |> assign(:page_title, event.title)
     |> assign(:description_length, description_length(event.description))
     |> assign(:event_title, event.title)
     |> assign(:state, event.state)
     |> assign(:start_date, event.start_date)
     |> assign(:end_date, event.end_date)
     |> assign(:start_time, event.start_time)
     |> assign(:end_time, event.end_time)
     |> assign(:ticket_count, length(tickets))
     |> assign(:ticket_tier_count, length(ticket_tiers))
     |> assign(trigger_submit: false, check_errors: false)
     |> stream(:agendas, agendas)
     |> assign(form: to_form(event_changeset, as: "event"))
     |> allow_upload(:file,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       auto_upload: true
     )}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, inserted_event} =
      Events.create_event(%{
        title: "New Event",
        description: "",
        state: :draft,
        organizer_id: socket.assigns.current_user.id
      })

    {:ok, push_navigate(socket, to: "/admin/events/#{inserted_event.id}/edit")}
  end

  @impl true
  def handle_event("delete-event", _, socket) do
    Events.delete_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event deleted.")
     |> push_navigate(to: "/admin/events")}
  end

  @impl true
  def handle_event("publish-event", _, socket) do
    Events.publish_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event published.")
     |> push_navigate(to: "/admin/events")}
  end

  @impl true
  def handle_event("clear-cover-image", _, socket) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    case Events.update_event(current_event, %{image_id: nil}) do
      {:ok, event} ->
        event_changeset = Event.changeset(event, %{"image_id" => nil})

        {:noreply,
         assign_form(socket, event_changeset) |> assign(:event, event)}

      {:error, _} ->
        # If update fails, reload and try again
        reloaded_event = Events.get_event!(socket.assigns[:event].id)

        case Events.update_event(reloaded_event, %{image_id: nil}) do
          {:ok, event} ->
            event_changeset = Event.changeset(event, %{"image_id" => nil})

            {:noreply,
             assign_form(socket, event_changeset) |> assign(:event, event)}

          {:error, _} ->
            # If it still fails, just reload the event
            event_changeset =
              Event.changeset(reloaded_event, %{"image_id" => nil})

            {:noreply,
             assign_form(socket, event_changeset)
             |> assign(:event, reloaded_event)}
        end
    end
  end

  @impl true
  def handle_event("unpublish-event", _, socket) do
    Events.unpublish_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event moved back to draft.")
     |> push_navigate(to: "/admin/events/#{socket.assigns.event.id}/edit")}
  end

  @impl true
  def handle_event("cancel-event", _, socket) do
    Events.cancel_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event cancelled.")
     |> push_navigate(to: "/admin/events")}
  end

  @impl true
  def handle_event(
        "reposition",
        %{"id" => id, "new" => new_idx, "old" => _old_idx},
        socket
      ) do
    agenda = Agendas.get_agenda!(id)
    Agendas.update_agenda_position(socket.assigns.event.id, agenda, new_idx)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add-agenda", _, socket) do
    Agendas.create_agenda(socket.assigns[:event], %{
      title: "Agenda",
      event_id: socket.assigns[:event].id
    })

    {:noreply, socket}
  end

  def handle_event("delete-agenda", %{"id" => id}, socket) do
    agenda = %Agenda{id: id}
    Agendas.delete_agenda(socket.assigns[:event], agenda)
    {:noreply, socket}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    event_changeset =
      %Event{}
      |> Event.changeset(event_params)

    case Events.create_event(event_changeset) do
      {:ok, event} ->
        {:noreply, redirect(socket, to: "/admin/events/#{event.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"event" => event_params}, socket) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    event_changeset =
      Event.changeset(current_event, event_params)
      |> Map.put(:action, :validate)

    {updated_event, updated_changeset} =
      if event_changeset.valid? do
        case Events.update_event(current_event, event_params) do
          {:ok, updated_event} ->
            # Update succeeded, rebuild changeset with updated event
            updated_changeset =
              Event.changeset(updated_event, event_params)
              |> Map.put(:action, :validate)

            {updated_event, updated_changeset}

          {:error, _changeset} ->
            # If update fails, keep using current_event
            {current_event, event_changeset}
        end
      else
        {current_event, event_changeset}
      end

    {:noreply,
     assign_form(socket, updated_changeset)
     |> assign(:event, updated_event)
     |> assign(
       description_length: String.length(event_params["description"] || "")
     )
     |> assign(:event_title, event_params["title"])
     |> assign(:page_title, event_params["title"])
     |> assign(:start_date, event_params["start_date"])
     |> assign(:end_date, event_params["end_date"])
     |> assign(:start_time, event_params["start_time"])
     |> assign(:end_time, event_params["end_time"])}
  end

  def handle_event("editor-update", %{"raw_body" => raw_body}, socket) do
    # Reload event to get latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)
    changeset = Event.changeset(current_event, %{"raw_details" => raw_body})

    {updated_event, updated_changeset} =
      if changeset.valid? do
        case Events.update_event(current_event, %{"raw_details" => raw_body}) do
          {:ok, updated_event} ->
            updated_changeset =
              Event.changeset(updated_event, %{"raw_details" => raw_body})

            {updated_event, updated_changeset}

          {:error, _} ->
            # If update fails, keep using current_event
            {current_event, changeset}
        end
      else
        {current_event, changeset}
      end

    {:noreply,
     assign_form(socket, updated_changeset) |> assign(:event, updated_event)}
  end

  def handle_event(
        "map-new-marker",
        %{"lat" => latitude, "long" => longitude},
        socket
      ) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    changeset =
      Event.changeset(current_event, %{latitude: latitude, longitude: longitude})

    updated_event =
      if changeset.valid? do
        case Events.update_event(current_event, %{
               latitude: latitude,
               longitude: longitude
             }) do
          {:ok, event} -> event
          {:error, _} -> current_event
        end
      else
        current_event
      end

    {:noreply, assign_form(socket, changeset) |> assign(:event, updated_event)}
  end

  @impl true
  def handle_event("toggle-unlimited-capacity", _, socket) do
    current_unlimited = socket.assigns.capacity_form[:unlimited_capacity].value

    # Toggle the unlimited_capacity virtual field
    new_unlimited = !current_unlimited

    # Create changeset with the new unlimited_capacity value
    # The handle_unlimited_capacity function will set max_attendees accordingly
    changeset =
      Event.changeset(socket.assigns[:event], %{
        "unlimited_capacity" => new_unlimited
      })

    if changeset.valid? do
      # Extract the processed max_attendees value from the changeset
      new_max_attendees = Ecto.Changeset.get_field(changeset, :max_attendees)

      Events.update_event(socket.assigns[:event], %{
        "max_attendees" => new_max_attendees
      })
    end

    {:noreply, assign(socket, :capacity_form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate-capacity", params, socket) do
    # Handle both expected and unexpected parameter formats
    capacity_params =
      case params do
        %{"event" => event_params} -> event_params
        # Handle target-only events
        %{"_target" => _} -> %{}
        other -> other
      end

    changeset =
      Event.changeset(socket.assigns[:event], capacity_params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      Events.update_event(socket.assigns[:event], capacity_params)
    end

    {:noreply, assign(socket, :capacity_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save-capacity", params, socket) do
    # Handle both expected and unexpected parameter formats
    capacity_params =
      case params do
        %{"event" => event_params} -> event_params
        # Handle target-only events
        %{"_target" => _} -> %{}
        other -> other
      end

    case Events.update_event(socket.assigns[:event], capacity_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> assign(:event, event)
         |> assign(:capacity_form, to_form(Event.changeset(event, %{})))
         |> put_flash(:info, "Event capacity updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :capacity_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaAdded{agenda: agenda}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaUpdated{agenda: agenda}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaDeleted{agenda: agenda}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_delete(:agendas, agenda)}
  end

  @impl true
  def handle_info(
        {YscWeb.Agendas,
         %Ysc.MessagePassingEvents.AgendaRepositioned{agenda: agenda}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda, at: agenda.position)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %_event{agenda_item: agenda_item} = event},
        socket
      ) do
    send_update(YscWeb.AgendaEditComponent,
      id: agenda_item.agenda_id,
      event: event
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: event}},
        socket
      ) do
    if event.id == socket.assigns[:event].id do
      changeset = Event.changeset(event, %{})

      {:noreply,
       socket
       |> assign(:event, event)
       |> assign(:event_title, event.title)
       |> assign(:state, event.state)
       |> assign(:start_date, event.start_date)
       |> assign(:end_date, event.end_date)
       |> assign(:start_time, event.start_time)
       |> assign(:end_time, event.end_time)
       |> assign_form(changeset)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns[:event].id do
      ticket_tiers =
        Events.list_ticket_tiers_for_event(socket.assigns[:event].id)

      tickets = Events.list_tickets_for_event(socket.assigns[:event].id)

      {:noreply,
       socket
       |> assign(:ticket_tier_count, length(ticket_tiers))
       |> assign(:ticket_count, length(tickets))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns[:event].id do
      ticket_tiers =
        Events.list_ticket_tiers_for_event(socket.assigns[:event].id)

      tickets = Events.list_tickets_for_event(socket.assigns[:event].id)

      {:noreply,
       socket
       |> assign(:ticket_tier_count, length(ticket_tiers))
       |> assign(:ticket_count, length(tickets))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:updated_event, data}, socket) do
    # Handle the message and update the socket as needed
    # For example, you might want to update the event changeset
    changeset = Event.changeset(socket.assigns[:event], data)

    if changeset.valid? do
      Events.update_event(socket.assigns[:event], data)
    end

    {:noreply,
     assign(socket, start_date: data[:start_date], end_date: data[:end_date])
     |> assign_form(changeset)}
  end

  @impl true
  def handle_info({YscWeb.UploadComponent, :file, file_id}, socket) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)
    changeset = Event.changeset(current_event, %{image_id: file_id})

    updated_event =
      if changeset.valid? do
        case Events.update_event(current_event, %{image_id: file_id}) do
          {:ok, event} -> event
          {:error, _} -> current_event
        end
      else
        current_event
      end

    {:noreply,
     socket |> assign_form(changeset) |> assign(:event, updated_event)}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: _reservation
         }},
        socket
      ) do
    # Component handles this, but we need to catch it to prevent crashes
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: _reservation
         }},
        socket
      ) do
    # Component handles this, but we need to catch it to prevent crashes
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: _reservation
         }},
        socket
      ) do
    # Component handles this, but we need to catch it to prevent crashes
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ticket_reservation_created, event_id}, socket) do
    # Component handles this, but we need to catch it to prevent crashes
    # Only process if it's for the current event
    if socket.assigns[:event] && socket.assigns.event.id == event_id do
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:redirect_to_tickets, event_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Ticket reservation created successfully")
     |> push_navigate(to: ~p"/admin/events/#{event_id}/tickets")}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "event")
    capacity_form = to_form(changeset, as: "event")

    if changeset.valid? do
      assign(socket,
        form: form,
        capacity_form: capacity_form,
        check_errors: false
      )
    else
      assign(socket, form: form, capacity_form: capacity_form)
    end
  end

  defp format_date(nil), do: ""
  defp format_date(""), do: ""

  defp format_date(dt) when is_binary(dt) do
    Timex.parse!(dt, "{ISO:Extended}")
  end

  defp format_date(dt), do: dt

  defp format_time(nil), do: nil
  defp format_time(""), do: nil

  defp format_time(time) when is_binary(time) do
    case Timex.parse(time, "%H:%M:%S", :strftime) do
      {:ok, time} -> time
      {:error, _} -> Timex.parse!(time, "%H:%M", :strftime)
    end
  end

  defp format_time(time), do: time

  defp description_length(nil), do: 0
  defp description_length(description), do: String.length(description)

  defp event_state_to_badge_style(:draft), do: "sky"
  defp event_state_to_badge_style(:scheduled), do: "yellow"
  defp event_state_to_badge_style(:published), do: "green"
  defp event_state_to_badge_style(:cancelled), do: "orange"
  defp event_state_to_badge_style(:deleted), do: "red"
  defp event_state_to_badge_style(_), do: "default"

  defp schedule_button_text(:scheduled), do: "Scheduled"
  defp schedule_button_text(_), do: "Schedule"
end
