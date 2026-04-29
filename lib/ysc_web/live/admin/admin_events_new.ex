defmodule YscWeb.AdminEventsNewLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  require Ysc.Logging

  alias Phoenix.LiveView.JS
  alias Ysc.Events.Event
  alias Ysc.Events

  alias Ysc.Events.Agenda
  alias Ysc.Agendas
  alias YscWeb.AdminEventsLive.TicketTierManagement

  alias HtmlSanitizeEx.Scrubber

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex py-6 flex-col">
        <.back navigate={~p"/admin/events?#{@list_params}"}>Back</.back>
        <div
          id="event-header-bar"
          phx-hook="StickyEventHeader"
          class="sticky top-0 z-30 pt-4 pb-2"
        >
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0 flex flex-1 flex-col space-y-1">
              <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
                <h1 class="event-header-title break-words text-xl font-semibold leading-8 text-zinc-800 sm:text-2xl">
                  {@event_title}
                </h1>

                <.badge type={event_state_to_badge_style(@state)}>
                  {String.capitalize("#{@state}")}
                </.badge>

                <.link
                  :if={@event.state == :published}
                  href={~p"/events/#{@event.id}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex shrink-0 items-center gap-1 text-sm text-zinc-500 transition hover:text-blue-700"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                  <span class="sr-only">View Event</span>
                </.link>
              </div>

              <div
                :if={@start_date != nil && @start_date != ""}
                class="event-header-date flex flex-row items-center gap-1"
              >
                <.icon name="hero-calendar-days" class="shrink-0 text-zinc-600" />
                <p class="text-sm text-zinc-600">
                  {Ysc.Events.DateTimeFormatter.format_datetime(%{
                    start_date: format_date(@start_date),
                    start_time: format_time(@start_time),
                    end_date: format_date(@end_date),
                    end_time: format_time(@end_time)
                  })}
                </p>
              </div>
            </div>

            <div class="flex flex-shrink-0 flex-row flex-wrap items-center gap-2 sm:justify-end">
              <div :if={@event.state in [:draft, :scheduled]}>
                <.tooltip
                  :if={!@can_publish}
                  tooltip_text="A title and event date must be set before publishing"
                >
                  <.button
                    class="whitespace-nowrap opacity-50 cursor-not-allowed"
                    color="blue"
                    disabled
                  >
                    <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1 me-1" />Publish
                  </.button>
                </.tooltip>
                <.button
                  :if={@can_publish}
                  class="whitespace-nowrap"
                  color="blue"
                  phx-click="publish-event"
                  phx-disable-with="Publishing..."
                >
                  <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1 me-1" />Publish
                </.button>
              </div>

              <div :if={@event.state in [:published]}>
                <.button
                  class="whitespace-nowrap"
                  color="red"
                  phx-click="unpublish-event"
                  phx-disable-with="Unpublishing..."
                >
                  <.icon name="hero-document-arrow-down" class="w-5 h-5 -mt-1 me-1" />Unpublish
                </.button>
              </div>

              <div :if={@event.state in [:published, :scheduled]}>
                <.button
                  class="whitespace-nowrap"
                  color="green"
                  phx-click={JS.navigate(~p"/admin/events/#{@event.id}/check-in")}
                >
                  <.icon
                    name="hero-clipboard-document-check"
                    class="w-4 h-4 -mt-0.5 me-1"
                  />Check In
                </.button>
              </div>

              <.dropdown
                :if={@event.state in [:draft, :scheduled] && @can_publish}
                id="edit-post-more"
                right={true}
                class={
                  Enum.join(
                    [
                      "text-zinc-100 px-3 leading-6 py-2 text-sm font-semibold transition duration-300",
                      @event.state == :scheduled &&
                        "bg-green-700 hover:bg-green-800",
                      @event.state != :scheduled && "bg-blue-700 hover:bg-blue-800"
                    ],
                    " "
                  )
                }
              >
                <:button_block>
                  <.icon name="hero-clock" class="w-5 h-5 me-1" />{schedule_button_text(
                    @event.state
                  )}
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
                    <li class="block py-2 px-3 transition ease-in-out duration-200 hover:bg-zinc-100">
                      <button
                        type="button"
                        class="w-full text-left px-1"
                        phx-click="copy-event"
                        data-confirm="Copy this event?"
                      >
                        <.icon
                          name="hero-document-duplicate"
                          class="me-1 -mt-1 w-5 h-5"
                        />Copy Event
                      </button>
                    </li>

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

          <div class="event-header-tabs pt-3 text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
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
                  navigate={
                    if @partiful_link_present,
                      do: "#",
                      else: ~p"/admin/events/#{@event.id}/tickets"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @partiful_link_present && "opacity-50 cursor-not-allowed",
                    !@partiful_link_present && @live_action == :tickets &&
                      "text-blue-600 border-blue-600 active",
                    !@partiful_link_present && @live_action != :tickets &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Tickets {if @partiful_link_present,
                    do: "(Disabled - Using Partiful)"}
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/events/#{@event.id}/updates"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :updates &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :updates &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Updates
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :edit} class="relative py-8">
          <div class="border max-w-3xl rounded border-zinc-200 py-6 px-4 space-y-4">
            <h2 class="text-xl font-bold">Cover Image</h2>

            <.live_component
              module={YscWeb.MediaPickerComponent}
              id={:event_cover}
              user_id={@current_user.id}
              image_id={@form[:image_id].value}
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
              <.input
                type="text"
                field={@form[:partiful_link]}
                label="Partiful Link (Optional)"
                placeholder="https://partiful.com/e/..."
                phx-debounce="300"
                disabled={@ticket_tier_count > 0}
              />
              <p
                :if={@ticket_tier_count > 0}
                class="text-xs text-amber-700 -mt-2 flex items-start gap-1.5"
              >
                <.icon name="hero-information-circle" class="w-4 h-4 flex-shrink-0" />
                Partiful cannot be used when this event has ticket tiers. Remove all ticket tiers on the Tickets tab to add a Partiful link.
              </p>
              <p
                :if={@ticket_tier_count == 0 && @partiful_link_present}
                class="text-xs text-zinc-500 -mt-2"
              >
                Using Partiful for registration. When a Partiful link is set, ticket tiers cannot be added.
              </p>
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
                <details class="group">
                  <summary class="cursor-pointer select-none inline-flex items-center gap-1.5 text-sm font-medium text-zinc-500 hover:text-zinc-800 transition-colors list-none">
                    <.icon
                      name="hero-chevron-right"
                      class="w-3.5 h-3.5 transition-transform duration-200 group-open:rotate-90"
                    /> Advanced (Coordinates)
                  </summary>
                  <div class="mt-3 flex flex-row space-x-4">
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
                </details>
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
                    Click on the map to set marker location.
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
                <.live_component
                  module={YscWeb.TrixImagePickerComponent}
                  id={:event_body_image_picker}
                  target_input_id="post[raw_body]"
                />
                <div id="richtext" phx-update="ignore">
                  <trix-editor
                    input="post[raw_body]"
                    class="trix-content block px-4 py-2 bg-white border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition border-l border-b border-r text-wrap"
                    placeholder="Write something delightful and nice..."
                  >
                  </trix-editor>
                </div>
              </div>
            </div>
          </.form>

          <div id="hosts-section" class="max-w-3xl mt-6">
            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Hosts</h2>
                <p class="text-zinc-600 text-sm">
                  Search and add members who will be listed as hosts of this event.
                </p>
              </div>

              <div id="event-hosts-manager" class="space-y-3">
                <%!-- Current hosts list --%>
                <div
                  :if={@hosts != []}
                  class="flex flex-wrap gap-2"
                  id="hosts-list"
                >
                  <div
                    :for={host <- @hosts}
                    id={"host-#{host.id}"}
                    class="flex items-center gap-2 bg-zinc-100 rounded-full pl-1 pr-3 py-1"
                  >
                    <.user_avatar_image
                      user={host}
                      class="w-7 h-7 rounded-full object-cover flex-shrink-0"
                    />
                    <span class="text-sm font-medium text-zinc-800">
                      {host.first_name} {host.last_name}
                    </span>
                    <button
                      type="button"
                      phx-click="remove-host"
                      phx-value-user-id={host.id}
                      class="text-zinc-400 hover:text-red-500 transition ml-0.5"
                      aria-label={"Remove #{host.first_name} as host"}
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4 -mt-1" />
                    </button>
                  </div>
                </div>

                <%!-- Search input --%>
                <div class="relative">
                  <div class="relative">
                    <label for="host-search-input" class="sr-only">
                      Search hosts by name or email
                    </label>
                    <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                      <.icon
                        name="hero-magnifying-glass"
                        class="w-4 h-4 text-zinc-400"
                      />
                    </div>
                    <input
                      id="host-search-input"
                      type="text"
                      value={@host_search_query}
                      placeholder="Search members by name or email..."
                      phx-keyup="search-hosts"
                      phx-debounce="250"
                      name="host_search"
                      autocomplete="off"
                      class="block w-full h-10 rounded border border-zinc-300 bg-white shadow-sm pl-9 pr-4 text-sm text-zinc-900 placeholder-zinc-400 focus:border-zinc-400 focus:outline-none focus:ring-0"
                    />
                  </div>

                  <%!-- Search results dropdown --%>
                  <div
                    :if={@host_search_results != [] && @host_search_query != ""}
                    id="host-search-results"
                    class="absolute z-10 mt-1 w-full rounded border border-zinc-200 bg-white shadow-lg overflow-hidden"
                  >
                    <ul class="max-h-56 overflow-y-auto py-1 divide-y divide-zinc-50">
                      <li
                        :for={user <- @host_search_results}
                        id={"host-result-#{user.id}"}
                      >
                        <button
                          type="button"
                          class="flex items-center gap-3 px-3 py-2.5 hover:bg-zinc-50 transition w-full text-left"
                          phx-click="add-host"
                          phx-value-user-id={user.id}
                          aria-label={"Add #{user.first_name} #{user.last_name} (#{user.email}) as host"}
                        >
                          <.user_avatar_image
                            user={user}
                            class="w-8 h-8 rounded-full object-cover flex-shrink-0"
                          />
                          <div class="min-w-0 flex-1">
                            <p class="text-sm font-medium text-zinc-900 truncate">
                              {user.first_name} {user.last_name}
                            </p>
                            <p class="text-xs text-zinc-500 truncate">
                              {user.email}
                            </p>
                          </div>
                          <.icon
                            :if={Enum.any?(@hosts, &(&1.id == user.id))}
                            name="hero-check-circle"
                            class="host-status-icon w-4 h-4 text-green-500 flex-shrink-0"
                          />
                          <.icon
                            :if={!Enum.any?(@hosts, &(&1.id == user.id))}
                            name="hero-plus-circle"
                            class="host-status-icon w-4 h-4 text-blue-400 flex-shrink-0"
                          />
                        </button>
                      </li>
                    </ul>
                  </div>

                  <p
                    :if={@host_search_query != "" && @host_search_results == []}
                    class="mt-2 text-sm text-zinc-500"
                  >
                    No members found for "{@host_search_query}".
                  </p>
                </div>
              </div>
            </div>
          </div>

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

              <%!-- Add Agenda button also appears at the bottom; defined again after the list --%>

              <ul
                id="agendas"
                phx-update="stream"
                phx-hook="Sortable"
                class="w-full flex gap-3 snap-x overflow-x-auto pb-2"
              >
                <li
                  :for={{id, agenda} <- @streams.agendas}
                  id={id}
                  data-id={agenda.id}
                  class="bg-zinc-100 rounded-lg flex-shrink-0 flex flex-col"
                >
                  <div
                    class="drag-handle flex items-center justify-center py-1.5 rounded-t-lg cursor-grab active:cursor-grabbing hover:bg-zinc-200 transition group"
                    title="Drag to reorder"
                  >
                    <div class="flex flex-col gap-0.5">
                      <div class="flex gap-0.5">
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                      </div>
                      <div class="flex gap-0.5">
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                        <div class="w-1 h-1 rounded-full bg-zinc-400 group-hover:bg-zinc-600 transition">
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="mx-auto max-w-7xl px-4 pt-2 pb-4 space-y-4">
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

              <.button
                type="button"
                phx-click="add-agenda"
                phx-disable-with="Adding..."
              >
                <.icon name="hero-plus" class="-mt-0.5" /> Add Agenda
              </.button>
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
              event={@event}
              current_user={@current_user}
            />
          </div>
        </div>

        <div :if={@live_action == :updates} class="relative py-8">
          <div class="max-w-3xl space-y-8">
            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Send Update to Attendees</h2>
                <p class="text-zinc-600 text-sm">
                  Send a branded email notification to everyone who has a ticket for this event.
                  This includes both ticket purchasers and registered attendees.
                </p>
                <p class="mt-2 text-sm font-medium text-blue-600">
                  {@recipient_count} recipient(s) will receive this update
                </p>
              </div>

              <.form
                for={@update_form}
                id="event-update-form"
                phx-submit="send-event-update"
                phx-change="validate-event-update"
                class="space-y-4"
              >
                <.input
                  field={@update_form[:title]}
                  type="text"
                  label="Title (optional)"
                  placeholder="e.g. Venue Change, Schedule Update..."
                />

                <div>
                  <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
                    Message
                  </label>
                  <.input
                    type="hidden"
                    id="update[raw_body]"
                    field={@update_form[:raw_body]}
                    phx-hook="TrixHook"
                    phx-debounce={200}
                  />
                  <div id="update-richtext" phx-update="ignore">
                    <trix-editor
                      input="update[raw_body]"
                      class="trix-content block px-4 py-2 bg-white border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition border rounded text-wrap min-h-[200px]"
                      placeholder="Write the update message to send to all attendees..."
                    >
                    </trix-editor>
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <.input
                    field={@update_form[:show_on_event_page]}
                    type="checkbox"
                    label="Also show this update on the public event page"
                  />
                </div>

                <div class="flex items-center gap-4 pt-2">
                  <.button
                    type="submit"
                    phx-disable-with="Sending..."
                    class="bg-blue-600 hover:bg-blue-700"
                    data-confirm={"Send this update to #{@recipient_count} recipient(s)? This cannot be undone."}
                  >
                    <.icon name="hero-paper-airplane" class="w-5 h-5 -mt-0.5 mr-1" />
                    Send Update
                  </.button>
                </div>
              </.form>
            </div>

            <div
              :if={@event_updates != []}
              class="border border-zinc-200 rounded py-6 px-4 space-y-4"
            >
              <h2 class="text-xl font-bold">Past Updates</h2>
              <div class="divide-y divide-zinc-100">
                <div
                  :for={update <- @event_updates}
                  class="py-4 first:pt-0 last:pb-0"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div class="min-w-0 flex-1">
                      <p :if={update.title} class="font-semibold text-zinc-900">
                        {update.title}
                      </p>
                      <div class="text-sm text-zinc-600 mt-1 prose prose-sm prose-zinc max-w-none line-clamp-3">
                        {Phoenix.HTML.raw(update.rendered_body)}
                      </div>
                    </div>
                    <div class="shrink-0 text-right text-xs text-zinc-500 space-y-1">
                      <p :if={update.sent_at}>
                        Sent {Calendar.strftime(
                          update.sent_at,
                          "%b %d, %Y %I:%M %p"
                        )}
                      </p>
                      <p :if={update.recipient_count}>
                        {update.recipient_count} recipient(s)
                      </p>
                      <p>
                        <span
                          :if={update.show_on_event_page}
                          class="inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700"
                        >
                          Visible on event page
                        </span>
                      </p>
                      <p :if={update.sent_by}>
                        by {update.sent_by.first_name} {update.sent_by.last_name}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
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
    hosts = Events.list_event_hosts(event)

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
     |> assign(:can_publish, can_publish?(event.start_date, event.title))
     |> assign(:ticket_count, length(tickets))
     |> assign(:ticket_tier_count, length(ticket_tiers))
     |> assign(:partiful_link_present, event.partiful_link not in [nil, ""])
     |> assign(trigger_submit: false, check_errors: false)
     |> assign(:hosts, hosts)
     |> assign(:host_search_query, "")
     |> assign(:host_search_results, [])
     |> stream(:agendas, agendas)
     |> assign(:list_params, Map.drop(params, ["id"]))
     |> assign(form: to_form(event_changeset, as: "event"))
     |> assign(
       :update_form,
       to_form(
         %{
           "title" => "",
           "raw_body" => "",
           "rendered_body" => "",
           "show_on_event_page" => false
         },
         as: "update"
       )
     )
     |> assign(:event_updates, Events.list_event_updates(event.id))
     |> assign(:recipient_count, Events.count_event_update_recipients(event.id))}
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
  def handle_params(%{"id" => incoming_id} = params, _uri, socket) do
    current_id = socket.assigns[:event] && socket.assigns.event.id

    socket =
      if incoming_id != current_id do
        load_event(socket, incoming_id)
      else
        socket
      end
      |> assign(:list_params, Map.drop(params, ["id"]))
      |> maybe_refresh_tab_data()

    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:list_params, Map.drop(params, ["id"]))
      |> maybe_refresh_tab_data()

    {:noreply, socket}
  end

  defp load_event(socket, id) do
    Agendas.subscribe(id)

    event = Events.get_event!(id)
    event_changeset = Event.changeset(event, %{})

    capacity_attrs = %{"unlimited_capacity" => is_nil(event.max_attendees)}
    capacity_changeset = Event.changeset(event, capacity_attrs)
    agendas = Agendas.list_agendas_for_event(event.id)
    ticket_tiers = Events.list_ticket_tiers_for_event(event.id)
    tickets = Events.list_tickets_for_event(event.id)
    hosts = Events.list_event_hosts(event)

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
    |> assign(:can_publish, can_publish?(event.start_date, event.title))
    |> assign(:ticket_count, length(tickets))
    |> assign(:ticket_tier_count, length(ticket_tiers))
    |> assign(:partiful_link_present, event.partiful_link not in [nil, ""])
    |> assign(trigger_submit: false, check_errors: false)
    |> assign(:hosts, hosts)
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> stream(:agendas, agendas, reset: true)
    |> assign(form: to_form(event_changeset, as: "event"))
    |> assign(
      :update_form,
      to_form(
        %{
          "title" => "",
          "raw_body" => "",
          "rendered_body" => "",
          "show_on_event_page" => false
        },
        as: "update"
      )
    )
    |> assign(:event_updates, Events.list_event_updates(event.id))
    |> assign(:recipient_count, Events.count_event_update_recipients(event.id))
  end

  defp maybe_refresh_tab_data(socket) do
    case socket.assigns[:event] do
      nil ->
        socket

      event ->
        case socket.assigns.live_action do
          :updates ->
            socket
            |> assign(:event_updates, Events.list_event_updates(event.id))
            |> assign(
              :recipient_count,
              Events.count_event_update_recipients(event.id)
            )

          :tickets ->
            ticket_tiers = Events.list_ticket_tiers_for_event(event.id)
            tickets = Events.list_tickets_for_event(event.id)

            socket
            |> assign(:ticket_tier_count, length(ticket_tiers))
            |> assign(:ticket_count, length(tickets))

          _ ->
            socket
        end
    end
  end

  @impl true
  def handle_event("copy-event", _, socket) do
    event = socket.assigns.event

    case Events.copy_event(event) do
      {:ok, new_event} ->
        {:noreply,
         push_patch(socket, to: ~p"/admin/events/#{new_event.id}/edit")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to copy event")
         |> push_navigate(to: ~p"/admin/events")}
    end
  end

  def handle_event("delete-event", _, socket) do
    Events.delete_event(socket.assigns.event)

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:info, "Event deleted.", title: "Event")
     |> push_navigate(to: "/admin/events")}
  end

  @impl true
  def handle_event("publish-event", _, socket) do
    if socket.assigns.can_publish do
      case Events.publish_event(socket.assigns.event) do
        {:ok, _event} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:info, "Event published.", title: "Event")
           |> push_navigate(to: "/admin/events")}

        {:error, :missing_title} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Event title is required before publishing.",
             title: "Event"
           )}

        {:error, :missing_start_date} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Event date is required before publishing.",
             title: "Event"
           )}

        {:error, :invalid_state} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Event cannot be published from its current state.",
             title: "Event"
           )}

        {:error, _reason} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Failed to publish event. Please try again.",
             title: "Event"
           )}
      end
    else
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "A title and event date must be set before publishing.",
         title: "Event"
       )}
    end
  end

  @impl true
  def handle_event("clear-cover-image", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("unpublish-event", _, socket) do
    Events.unpublish_event(socket.assigns.event)

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:info, "Event moved back to draft.",
       title: "Event"
     )
     |> push_patch(to: "/admin/events/#{socket.assigns.event.id}/edit")}
  end

  @impl true
  def handle_event("cancel-event", _, socket) do
    Events.cancel_event(socket.assigns.event)

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:info, "Event cancelled.", title: "Event")
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
    case Events.create_event(event_params) do
      {:ok, event} ->
        {:noreply, push_patch(socket, to: "/admin/events/#{event.id}/edit")}

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
       :partiful_link_present,
       updated_event.partiful_link not in [nil, ""]
     )
     |> assign(
       description_length: String.length(event_params["description"] || "")
     )
     |> assign(:event_title, event_params["title"])
     |> assign(:page_title, event_params["title"])
     |> assign(:start_date, event_params["start_date"])
     |> assign(:end_date, event_params["end_date"])
     |> assign(:start_time, event_params["start_time"])
     |> assign(:end_time, event_params["end_time"])
     |> assign(
       :can_publish,
       can_publish?(
         Ecto.Changeset.get_field(updated_changeset, :start_date),
         Ecto.Changeset.get_field(updated_changeset, :title)
       )
     )}
  end

  def handle_event(
        "editor-update",
        %{"field" => "update[raw_body]", "value" => raw_body},
        socket
      ) do
    current_form = socket.assigns.update_form.params || %{}
    rendered = Scrubber.scrub(raw_body, Ysc.TrixScrubber)

    updated_params =
      Map.merge(current_form, %{
        "raw_body" => raw_body,
        "rendered_body" => rendered
      })

    {:noreply,
     assign(socket, :update_form, to_form(updated_params, as: "update"))}
  end

  def handle_event(
        "editor-update",
        %{"field" => _field, "value" => raw_body},
        socket
      ) do
    # Reload event to get latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)
    rendered = Scrubber.scrub(raw_body, Ysc.TrixScrubber)
    update_attrs = %{"raw_details" => raw_body, "rendered_details" => rendered}
    changeset = Event.changeset(current_event, update_attrs)

    {updated_event, updated_changeset} =
      if changeset.valid? do
        case Events.update_event(current_event, update_attrs) do
          {:ok, updated_event} ->
            updated_changeset =
              Event.changeset(updated_event, update_attrs)

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

  def handle_event("validate-event-update", %{"update" => params}, socket) do
    {:noreply, assign(socket, :update_form, to_form(params, as: "update"))}
  end

  def handle_event("send-event-update", %{"update" => params}, socket) do
    event = socket.assigns.event
    raw_body = params["raw_body"] || ""
    rendered_body = Scrubber.scrub(raw_body, Ysc.TrixScrubber)

    if String.trim(raw_body) == "" do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Message body cannot be empty.",
         title: "Update"
       )}
    else
      attrs = %{
        title: params["title"],
        raw_body: raw_body,
        rendered_body: rendered_body,
        show_on_event_page: params["show_on_event_page"] == "true",
        sent_by_id: socket.assigns.current_user.id
      }

      case Events.create_event_update(event, attrs) do
        {:ok, event_update} ->
          oban_result =
            %{"event_update_id" => event_update.id}
            |> YscWeb.Workers.EventUpdateNotificationWorker.new()
            |> Oban.insert()

          socket =
            case oban_result do
              {:ok, _job} ->
                YscWeb.Flash.put_toast(
                  socket,
                  :info,
                  "Update queued for #{socket.assigns.recipient_count} recipient(s).",
                  title: "Event Update"
                )

              {:error, reason} ->
                Ysc.Logging.error("Failed to enqueue event update notification",
                  extra: %{
                    event_update_id: event_update.id,
                    reason: inspect(reason)
                  }
                )

                YscWeb.Flash.put_toast(
                  socket,
                  :warning,
                  "Update saved but notification delivery could not be scheduled. Please try again.",
                  title: "Event Update"
                )
            end

          {:noreply,
           socket
           |> assign(
             :update_form,
             to_form(
               %{
                 "title" => "",
                 "raw_body" => "",
                 "rendered_body" => "",
                 "show_on_event_page" => false
               },
               as: "update"
             )
           )
           |> assign(:event_updates, Events.list_event_updates(event.id))}

        {:error, changeset} ->
          message =
            changeset
            |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)
            |> Enum.map_join("; ", fn {field, errors} ->
              "#{Phoenix.Naming.humanize(field)}: #{Enum.join(errors, ", ")}"
            end)

          {:noreply,
           socket
           |> assign(:update_form, to_form(changeset, as: "update"))
           |> YscWeb.Flash.put_toast(
             :error,
             if(message == "",
               do: "Please correct the highlighted fields.",
               else: message
             ),
             title: "Update"
           )}
      end
    end
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
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)
    current_unlimited = socket.assigns.capacity_form[:unlimited_capacity].value

    # Toggle the unlimited_capacity virtual field
    new_unlimited = !current_unlimited

    # Create changeset with the new unlimited_capacity value
    # The handle_unlimited_capacity function will set max_attendees accordingly
    changeset =
      Event.changeset(current_event, %{
        "unlimited_capacity" => new_unlimited
      })

    updated_event =
      if changeset.valid? do
        # Extract the processed max_attendees value from the changeset
        new_max_attendees = Ecto.Changeset.get_field(changeset, :max_attendees)

        case Events.update_event(current_event, %{
               "max_attendees" => new_max_attendees
             }) do
          {:ok, event} -> event
          {:error, _} -> current_event
        end
      else
        current_event
      end

    {:noreply,
     socket
     |> assign(:event, updated_event)
     |> assign(:capacity_form, to_form(Event.changeset(updated_event, %{})))}
  end

  @impl true
  def handle_event("validate-capacity", params, socket) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    # Handle both expected and unexpected parameter formats
    capacity_params =
      case params do
        %{"event" => event_params} -> event_params
        # Handle target-only events
        %{"_target" => _} -> %{}
        other -> other
      end

    changeset =
      Event.changeset(current_event, capacity_params)
      |> Map.put(:action, :validate)

    {updated_event, updated_changeset} =
      if changeset.valid? do
        case Events.update_event(current_event, capacity_params) do
          {:ok, event} ->
            updated_changeset =
              Event.changeset(event, capacity_params)
              |> Map.put(:action, :validate)

            {event, updated_changeset}

          {:error, _} ->
            {current_event, changeset}
        end
      else
        {current_event, changeset}
      end

    {:noreply,
     socket
     |> assign(:event, updated_event)
     |> assign(:capacity_form, to_form(updated_changeset))}
  end

  @impl true
  def handle_event("save-capacity", params, socket) do
    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    # Handle both expected and unexpected parameter formats
    capacity_params =
      case params do
        %{"event" => event_params} -> event_params
        # Handle target-only events
        %{"_target" => _} -> %{}
        other -> other
      end

    case Events.update_event(current_event, capacity_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> assign(:event, event)
         |> assign(:capacity_form, to_form(Event.changeset(event, %{})))
         |> YscWeb.Flash.put_toast(
           :info,
           "Event capacity updated successfully."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :capacity_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("search-hosts", %{"value" => query}, socket) do
    query = String.trim(query)

    results =
      if query == "" do
        []
      else
        Ysc.Accounts.search_users(query, limit: 8)
      end

    {:noreply,
     socket
     |> assign(:host_search_query, query)
     |> assign(:host_search_results, results)}
  end

  @impl true
  def handle_event("add-host", %{"user-id" => user_id}, socket) do
    event = socket.assigns.event

    case Ysc.Accounts.get_user(user_id) do
      nil ->
        {:noreply, socket}

      user ->
        case Events.add_event_host(event, user) do
          {:ok, _} ->
            hosts = Events.list_event_hosts(event)

            {:noreply,
             socket
             |> assign(:hosts, hosts)
             |> assign(:host_search_query, "")
             |> assign(:host_search_results, [])}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("remove-host", %{"user-id" => user_id}, socket) do
    event = socket.assigns.event

    case Events.remove_event_host(event, user_id) do
      {:ok, _} ->
        hosts = Events.list_event_hosts(event)
        {:noreply, assign(socket, :hosts, hosts)}

      {:error, _} ->
        {:noreply, socket}
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
        {Ysc.Agendas,
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
       |> assign(:partiful_link_present, event.partiful_link not in [nil, ""])
       |> assign(:event_title, event.title)
       |> assign(:state, event.state)
       |> assign(:start_date, event.start_date)
       |> assign(:end_date, event.end_date)
       |> assign(:start_time, event.start_time)
       |> assign(:end_time, event.end_time)
       |> assign(:can_publish, can_publish?(event.start_date, event.title))
       |> assign(:capacity_form, to_form(changeset))
       |> assign_form(changeset)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.EventHostsUpdated{event_id: event_id}},
        socket
      ) do
    if event_id == socket.assigns[:event].id do
      hosts = Events.list_event_hosts_by_event_id(event_id)
      {:noreply, assign(socket, :hosts, hosts)}
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
  def handle_info(
        {YscWeb.MediaPickerComponent, _component_id, :cleared},
        socket
      ) do
    current_event = Events.get_event!(socket.assigns[:event].id)

    case Events.update_event(current_event, %{image_id: nil}) do
      {:ok, event} ->
        changeset = Event.changeset(event, %{"image_id" => nil})
        {:noreply, assign_form(socket, changeset) |> assign(:event, event)}

      {:error, _} ->
        reloaded_event = Events.get_event!(socket.assigns[:event].id)

        case Events.update_event(reloaded_event, %{image_id: nil}) do
          {:ok, event} ->
            changeset = Event.changeset(event, %{"image_id" => nil})
            {:noreply, assign_form(socket, changeset) |> assign(:event, event)}

          {:error, _} ->
            changeset = Event.changeset(reloaded_event, %{"image_id" => nil})

            {:noreply,
             assign_form(socket, changeset) |> assign(:event, reloaded_event)}
        end
    end
  end

  def handle_info(
        {YscWeb.MediaPickerComponent, _component_id, image_id},
        socket
      ) do
    current_event = Events.get_event!(socket.assigns[:event].id)
    changeset = Event.changeset(current_event, %{image_id: image_id})

    updated_event =
      if changeset.valid? do
        case Events.update_event(current_event, %{image_id: image_id}) do
          {:ok, event} -> event
          {:error, _} -> current_event
        end
      else
        current_event
      end

    {:noreply,
     socket |> assign_form(changeset) |> assign(:event, updated_event)}
  end

  def handle_info({YscWeb.TrixImagePickerComponent, _id, image}, socket) do
    url = image.optimized_image_path || image.raw_image_path

    {:noreply,
     push_event(socket, "insert-trix-image", %{
       url: url,
       href: "#{url}?content-disposition=attachment",
       alt: image.alt_text || image.title || "",
       target_input_id: "post[raw_body]"
     })}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation
         }},
        socket
      ) do
    socket =
      send_ticket_tier_management_reservation_update(
        socket,
        reservation.ticket_tier_id,
        close_reserve_modal: true,
        notify:
          {:info, "Ticket reservation created successfully",
           [title: "Reservation"]}
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    socket =
      send_ticket_tier_management_reservation_update(
        socket,
        reservation.ticket_tier_id,
        close_reserve_modal: false
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    socket =
      send_ticket_tier_management_reservation_update(
        socket,
        reservation.ticket_tier_id,
        close_reserve_modal: false
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.EventUpdateCreated{event_id: event_id}},
        socket
      ) do
    if socket.assigns[:event] && event_id == socket.assigns.event.id do
      {:noreply,
       assign(socket, :event_updates, Events.list_event_updates(event_id))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.EventUpdateSent{event_id: event_id}},
        socket
      ) do
    if socket.assigns[:event] && event_id == socket.assigns.event.id do
      {:noreply,
       assign(socket, :event_updates, Events.list_event_updates(event_id))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({Ysc.Events, _msg}, socket), do: {:noreply, socket}

  defp send_ticket_tier_management_reservation_update(socket, tier_id, opts) do
    close_reserve? = Keyword.get(opts, :close_reserve_modal, false)
    notify = Keyword.get(opts, :notify)

    with %{id: event_id} <- socket.assigns[:event],
         :tickets <- socket.assigns[:live_action],
         %{event_id: ^event_id} <- Events.get_ticket_tier(tier_id) do
      component_assigns =
        if close_reserve? do
          [
            id: "ticket-tier-management-#{event_id}",
            close_reserve_modal: true
          ]
        else
          [
            id: "ticket-tier-management-#{event_id}",
            reservation_epoch: :erlang.unique_integer([:positive])
          ]
        end

      send_update(TicketTierManagement, component_assigns)

      socket =
        case notify do
          {:info, msg, flash_opts} ->
            YscWeb.Flash.put_toast(socket, :info, msg, flash_opts)

          _ ->
            socket
        end

      socket
    else
      _ -> socket
    end
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

  defp can_publish?(start_date, title) do
    start_date not in [nil, ""] and title not in [nil, ""]
  end

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
