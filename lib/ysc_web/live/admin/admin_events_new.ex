defmodule YscWeb.AdminEventsNewLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  import YscWeb.Live.AsyncHelpers

  require Ysc.Logging

  alias Ysc.EventLocationConfig
  alias Ysc.EventPhotos
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Events.EventUpdate
  alias Ysc.ExpenseReports
  alias YscWeb.Admin.EditingPresence
  alias YscWeb.AdminBadgeHelpers
  alias YscWeb.AdminCheckInPaths
  alias Ysc.Media.Image

  alias Ysc.Events.Agenda
  alias Ysc.Agendas
  alias YscWeb.AdminEventsLive.TicketTierManagement
  alias YscWeb.Components.Events.CommunicationTimeline
  alias YscWeb.Emails.EventUpdateNotification
  alias YscWeb.Sms.Segment

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
          :if={@loading_event?}
          id="admin-event-loading"
          class="flex flex-col pt-4 space-y-6"
          role="status"
          aria-live="polite"
        >
          <span class="sr-only">Loading event…</span>
          <.skeleton_block class="h-9 w-64 rounded" />
          <.skeleton_block class="h-5 w-40 rounded" />
          <div class="flex flex-wrap gap-2">
            <.skeleton_block :for={_ <- 1..5} class="h-9 w-24 rounded-full" />
          </div>
          <div class="bg-white rounded-lg border border-zinc-200 p-6 space-y-4">
            <.skeleton_block :for={_ <- 1..6} class="h-4 w-full rounded" />
          </div>
        </div>

        <div :if={!@loading_event?}>
          <div id="event-header-bar" class="pt-4 pb-2">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div class="min-w-0 flex flex-1 flex-col space-y-1">
                <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
                  <h1 class="event-header-title break-words text-xl font-semibold leading-8 text-zinc-800 sm:text-2xl">
                    {@event_title}
                  </h1>

                  <.badge type={event_state_to_badge_style(@state)}>
                    {String.capitalize("#{@state}")}
                  </.badge>

                  <.presence_avatars editors={@editors} size={:md} />

                  <.admin_help_link
                    topic={event_help_topic(@live_action)}
                    label="Guide for this tab"
                    role={@admin_role}
                  />

                  <.link
                    :if={
                      @event.state in [:published, :cancelled, :draft, :scheduled]
                    }
                    href={~p"/events/#{@event.id}"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex shrink-0 items-center gap-1 text-sm text-zinc-500 transition hover:text-blue-700"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                    {if @event.state in [:published, :cancelled],
                      do: "View Event",
                      else: "Preview"}
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

                <.last_edited_by
                  user={@event.updated_by || @event.organizer}
                  at={@event.updated_at}
                  formatter={
                    &(&1
                      |> DateTime.shift_zone!("America/Los_Angeles")
                      |> Timex.format!("{Mshort} {D}, {YYYY} at {h12}:{m}{am}"))
                  }
                />
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
                      <.icon
                        name="hero-document-arrow-up"
                        class="w-5 h-5"
                      />Publish
                    </.button>
                  </.tooltip>
                  <.button
                    :if={@can_publish}
                    class="whitespace-nowrap"
                    color="blue"
                    phx-click="publish-event"
                    phx-disable-with="Publishing..."
                  >
                    <.icon name="hero-document-arrow-up" class="w-5 h-5" />Publish
                  </.button>
                </div>

                <div :if={@event.state in [:published]} class="hidden sm:block">
                  <.button
                    class="whitespace-nowrap"
                    color="red"
                    phx-click="unpublish-event"
                    phx-disable-with="Unpublishing..."
                  >
                    <.icon
                      name="hero-document-arrow-down"
                      class="w-5 h-5"
                    />Unpublish
                  </.button>
                </div>

                <div :if={@event.state in [:published, :scheduled]}>
                  <.button
                    class="whitespace-nowrap"
                    color="green"
                    navigate={@check_in_path}
                  >
                    <.icon
                      name="hero-clipboard-document-check"
                      class="w-5 h-5"
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
                        "min-h-[44px] text-zinc-100 px-3 leading-6 py-2 text-sm font-semibold transition duration-300",
                        @event.state == :scheduled &&
                          "bg-green-700 hover:bg-green-800",
                        @event.state != :scheduled &&
                          "bg-blue-700 hover:bg-blue-800"
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
                  class="text-zinc-800 hover:bg-zinc-100 hover:text-black min-h-[44px]"
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
                        class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100 sm:hidden"
                      >
                        <button
                          type="button"
                          class="w-full text-left px-1"
                          phx-click="unpublish-event"
                        >
                          <.icon
                            name="hero-document-arrow-down"
                            class="me-1 -mt-1 w-5 h-5"
                          />Unpublish
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
                          <.icon
                            name="hero-minus-circle"
                            class="me-1 -mt-1 w-5 h-5"
                          />Cancel Event
                        </button>
                      </li>

                      <li class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100">
                        <button
                          type="button"
                          class="w-full text-left px-1"
                          phx-click="delete-event"
                        >
                          <.icon name="hero-trash" class="w-5 h-5" /> Delete Event
                        </button>
                      </li>
                    </ul>
                  </div>
                </.dropdown>
              </div>
            </div>

            <.admin_tabs
              id="event-detail-tabs"
              aria_label="Event sections"
              class="event-header-tabs pt-3 text-sm font-medium text-zinc-500 !mb-0"
            >
              <.admin_tab
                active={@live_action == :edit}
                patch={~p"/admin/events/#{@event.id}/edit"}
              >
                Event Details
              </.admin_tab>
              <.admin_tab
                active={@live_action == :tickets}
                patch={~p"/admin/events/#{@event.id}/tickets"}
              >
                Tickets
              </.admin_tab>
              <.admin_tab
                active={@live_action == :updates}
                patch={~p"/admin/events/#{@event.id}/updates"}
              >
                Updates
              </.admin_tab>
              <.admin_tab
                active={@live_action == :statistics}
                patch={~p"/admin/events/#{@event.id}/statistics"}
              >
                Statistics
              </.admin_tab>
            </.admin_tabs>
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
                />
                <p
                  :if={@partiful_link_present}
                  class="text-xs text-zinc-500 -mt-2"
                >
                  Shown to attendees as an RSVP callout on the event page, alongside any ticket tiers.
                </p>
              </div>

              <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
                <h2 class="text-xl font-bold mb-2">Date and Location</h2>

                <h3 class="text-lg font-medium">Date and Time</h3>
                <div class="flex flex-row w-full space-x-4">
                  <div class="flex">
                    <%!-- Events: min_nights 0 = single day or multi-day range.
                         Booking calendars keep the default of 1 night minimum. --%>
                    <.date_range_picker
                      label="Date*"
                      id="event_date"
                      form={@form}
                      start_date_field={@form[:start_date]}
                      end_date_field={@form[:end_date]}
                      min={Date.add(@pacific_today, -365)}
                      today={@pacific_today}
                      allow_saturdays={true}
                      min_nights={0}
                      max_nights={365}
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
                  <div class="space-y-2">
                    <span class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                      Frequent Venues
                    </span>
                    <div class="flex flex-wrap gap-2" id="location-presets">
                      <button
                        :for={preset <- @location_presets}
                        type="button"
                        id={"location-preset-#{preset.id}"}
                        phx-click="apply-location-preset"
                        phx-value-id={preset.id}
                        class="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50 hover:border-zinc-300 transition"
                      >
                        <.icon name="hero-map-pin" class="w-4 h-4 flex-shrink-0" />
                        {preset.label}
                      </button>
                    </div>
                  </div>

                  <div
                    id="event-location-search"
                    phx-update="ignore"
                    phx-hook="RadarLocationAutocomplete"
                    data-presets={
                      Jason.encode!(EventLocationConfig.presets_for_search())
                    }
                    class="w-full"
                  />

                  <div
                    :if={location_set?(@form)}
                    class="bg-zinc-50 border border-zinc-200 rounded-lg p-4 space-y-4"
                    id="location-display-details"
                  >
                    <div class="flex items-center justify-between">
                      <h4 class="text-sm font-medium text-zinc-700">
                        Display Details
                      </h4>
                      <p class="text-xs text-zinc-500">Publicly visible</p>
                    </div>

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
                  </div>

                  <.input type="hidden" field={@form[:latitude]} />
                  <.input type="hidden" field={@form[:longitude]} />

                  <div class="space-y-2">
                    <.live_component
                      id={"#{@event.id}-map"}
                      module={YscWeb.Components.MapComponent}
                      event_id={@event.id}
                      latitude={@form[:latitude].value}
                      longitude={@form[:longitude].value}
                      locked={false}
                      cooperative_gestures={false}
                    />
                    <p class="text-zinc-500 text-xs flex items-center gap-1.5 mt-2">
                      <.icon
                        name="hero-information-circle"
                        class="w-4 h-4 flex-shrink-0"
                      />
                      Double-check the pin on the map. You can click anywhere on the map to manually adjust it.
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
                              :if={MapSet.member?(@host_ids, user.id)}
                              name="hero-check-circle"
                              class="host-status-icon w-4 h-4 text-green-500 flex-shrink-0"
                            />
                            <.icon
                              :if={!MapSet.member?(@host_ids, user.id)}
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
              <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-4 border border-zinc-200 rounded p-6 bg-white">
                <div>
                  <h2 class="text-xl font-bold">Agenda</h2>
                  <p class="text-zinc-600 text-sm mt-1">
                    Design your event schedule exactly as attendees will see it.
                  </p>
                </div>

                <.button
                  id="add-agenda-button"
                  type="button"
                  phx-click="add-agenda"
                  phx-disable-with="Adding..."
                  class="shrink-0"
                >
                  <.icon name="hero-plus" /> Add Agenda Track
                </.button>
              </div>

              <div class="relative mt-6">
                <button
                  type="button"
                  data-scroll-left
                  aria-label="Scroll to previous agenda track"
                  class="absolute left-2 top-1/2 z-20 flex h-9 w-9 shrink-0 -translate-y-1/2 items-center justify-center rounded-full border border-zinc-200 bg-white p-0 text-zinc-600 shadow-md transition hover:bg-zinc-50 hover:text-zinc-900 opacity-0 pointer-events-none"
                >
                  <.icon name="hero-chevron-left" class="h-5 w-5" />
                </button>
                <button
                  type="button"
                  data-scroll-right
                  aria-label="Scroll to next agenda track"
                  class="absolute right-2 top-1/2 z-20 flex h-9 w-9 shrink-0 -translate-y-1/2 items-center justify-center rounded-full border border-zinc-200 bg-white p-0 text-zinc-600 shadow-md transition hover:bg-zinc-50 hover:text-zinc-900 opacity-0 pointer-events-none"
                >
                  <.icon name="hero-chevron-right" class="h-5 w-5" />
                </button>

                <div
                  id="agendas-scroll"
                  phx-hook="AgendaTracksScroller"
                  class="agenda-tracks-scroll overflow-x-auto pb-4 snap-x snap-mandatory scroll-smooth"
                >
                  <ul
                    id="agendas"
                    phx-update="stream"
                    phx-hook="Sortable"
                    class="flex gap-6 w-max min-w-full"
                  >
                    <li
                      :for={{id, agenda} <- @streams.agendas}
                      id={id}
                      data-id={agenda.id}
                      class="group/agenda flex-shrink-0 w-[450px] sm:w-[500px] snap-start flex flex-col bg-white border border-zinc-200 shadow-sm rounded overflow-hidden drag-item:scale-[1.02] drag-item:shadow-xl drag-item:z-10 drag-ghost:opacity-100 drag-ghost:bg-blue-50 drag-ghost:border-2 drag-ghost:border-dashed drag-ghost:border-blue-400"
                    >
                      <div class="flex items-center justify-between border-b border-zinc-100 bg-zinc-50/80 px-4 py-3 drag-ghost:opacity-0">
                        <div class="flex items-center gap-2 flex-1">
                          <div
                            class="drag-handle cursor-grab active:cursor-grabbing text-zinc-400 hover:text-zinc-600 p-1"
                            title="Drag to reorder tracks"
                          >
                            <.icon
                              name="hero-arrows-right-left"
                              class="w-5 h-5 block"
                            />
                          </div>

                          <div class="flex-1">
                            <.live_component
                              id={"edit-agenda-title-#{agenda.id}"}
                              module={YscWeb.AgendasLive.FormComponent}
                              agenda_id={agenda.id}
                              event_id={@event.id}
                              agenda={agenda}
                            />
                          </div>
                        </div>

                        <.link
                          phx-click="delete-agenda"
                          phx-value-id={agenda.id}
                          aria-label="delete agenda"
                          class="text-zinc-400 hover:text-red-600 p-2 hover:bg-red-50 rounded-md transition ml-2"
                          data-confirm="Are you sure you want to delete this agenda?"
                        >
                          <.icon name="hero-trash" class="w-4 h-4 block" />
                        </.link>
                      </div>

                      <div class="p-6 bg-white relative drag-ghost:opacity-0">
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
                    phx-debounce="300"
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
            <div class="grid grid-cols-1 lg:grid-cols-12 gap-8">
              <div class="lg:col-span-7 space-y-8">
                <div
                  :if={
                    @event.state in [:published, "published"] and @photo_upload_url
                  }
                  class="border border-zinc-200 rounded py-6 px-4 space-y-4"
                  id="event-photo-upload-link-card"
                >
                  <div>
                    <h2 class="text-xl font-bold">Event photo uploads</h2>
                    <p class="text-zinc-600 text-sm mt-1">
                      Share this link with attendees so they can contribute photos after the event.
                      Reminder emails are sent automatically the morning after the event ends.
                    </p>
                  </div>
                  <.admin_readonly_copy_field
                    id="event-photo-upload-url"
                    copy_button_id="copy-photo-upload-url-btn"
                    value={@photo_upload_url}
                  />
                  <div
                    :if={@dev_routes?}
                    class="pt-2 border-t border-zinc-100 space-y-2"
                  >
                    <p class="text-sm text-zinc-600">
                      Development: send reminder emails now or preview in the mailbox.
                    </p>
                    <div class="flex flex-wrap gap-2">
                      <.button
                        type="button"
                        id="send-photo-reminder-btn"
                        phx-click="send-photo-reminder"
                        variant="outline"
                        data-confirm={"Send photo reminder emails to #{@recipient_count} recipient(s) now?"}
                      >
                        Send photo reminder emails now
                      </.button>
                      <.link
                        href="/dev/mailbox"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center text-sm text-blue-600 hover:text-blue-800"
                      >
                        Open dev mailbox
                        <.icon
                          name="hero-arrow-top-right-on-square"
                          class="w-4 h-4 ml-1"
                        />
                      </.link>
                    </div>
                  </div>
                </div>

                <div class="bg-white border border-zinc-200 rounded py-6 px-4 space-y-4">
                  <div>
                    <h2 class="text-xl font-bold">Send Update to Attendees</h2>
                    <p class="text-zinc-600 text-sm">
                      Send a branded email notification to everyone who has a ticket for this event.
                      This includes both ticket purchasers and registered attendees.
                    </p>
                    <p class="mt-2 text-sm font-medium text-blue-600">
                      {@recipient_count} email recipient(s) will receive this update
                    </p>
                    <p
                      :if={sms_checked?(@update_form)}
                      class="mt-1 text-sm font-medium text-blue-600"
                      id="sms-recipient-count"
                    >
                      {@sms_recipient_count} SMS recipient(s) with event SMS notifications enabled
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
                      <span
                        id="update-message-label"
                        class="block text-sm font-semibold leading-6 text-zinc-800 mb-2"
                      >
                        Message
                      </span>
                      <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none">
                        <.input
                          type="hidden"
                          id="update[raw_body]"
                          field={@update_form[:raw_body]}
                          phx-hook="TrixHook"
                          phx-debounce={200}
                        />
                        <.live_component
                          module={YscWeb.TrixImagePickerComponent}
                          id={:event_update_body_image_picker}
                          target_input_id="update[raw_body]"
                        />
                        <div id="update-richtext" phx-update="ignore">
                          <trix-editor
                            input="update[raw_body]"
                            aria-labelledby="update-message-label"
                            class="trix-content block px-4 py-2 bg-white border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition border rounded text-wrap min-h-[200px] max-h-[400px] overflow-y-auto resize-y"
                            placeholder="Write the update message to send to all attendees..."
                          >
                          </trix-editor>
                        </div>
                      </div>
                    </div>

                    <div class="flex items-center gap-2">
                      <.input
                        field={@update_form[:show_on_event_page]}
                        type="checkbox"
                        label="Also show this update on the public event page"
                      />
                    </div>

                    <div class="flex items-center gap-2">
                      <.input
                        field={@update_form[:send_sms]}
                        type="checkbox"
                        label="Also send SMS to attendees with SMS event notifications enabled"
                      />
                    </div>

                    <div
                      :if={sms_checked?(@update_form) and @sms_preview}
                      id="event-update-sms-preview"
                      class="rounded border border-zinc-200 bg-zinc-50 p-4 space-y-2"
                    >
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <h3 class="text-sm font-semibold text-zinc-800">
                          SMS preview
                        </h3>
                        <p class="text-xs text-zinc-500">
                          {@sms_preview.char_count}/{@sms_preview.single_limit} units · {@sms_preview.segment_count} SMS segment(s) · {sms_encoding_label(
                            @sms_preview.encoding
                          )}
                        </p>
                      </div>
                      <pre
                        id="event-update-sms-preview-body"
                        class="whitespace-pre-wrap break-words text-sm font-mono text-zinc-800 bg-white border border-zinc-200 rounded p-3"
                      >{@sms_preview.body}</pre>
                      <p
                        :if={@sms_preview.multi_segment?}
                        id="event-update-sms-segment-warning"
                        class="text-sm text-amber-700"
                      >
                        This message will send as {@sms_preview.segment_count} SMS messages per recipient (extra cost).
                        <%= if @sms_preview.truncated? do %>
                          It was truncated to fit a 2-segment limit.
                        <% end %>
                      </p>
                      <p
                        :if={
                          @sms_preview.truncated? and
                            not @sms_preview.multi_segment?
                        }
                        id="event-update-sms-truncated-note"
                        class="text-sm text-amber-700"
                      >
                        The SMS body was truncated to fit the length limit.
                      </p>
                    </div>

                    <div class="flex flex-wrap items-center gap-4 pt-2">
                      <.button
                        type="submit"
                        phx-disable-with="Sending..."
                        class="bg-blue-600 hover:bg-blue-700"
                        data-confirm={
                          event_update_confirm_message(
                            @recipient_count,
                            @sms_recipient_count,
                            @update_form,
                            @sms_preview
                          )
                        }
                      >
                        <.icon
                          name="hero-paper-airplane"
                          class="w-5 h-5"
                        /> Send Update
                      </.button>
                      <.button
                        type="button"
                        id="preview-event-update-btn"
                        variant="outline"
                        phx-click="open-update-preview"
                      >
                        <.icon name="hero-eye" class="w-5 h-5" /> Preview
                      </.button>
                    </div>
                  </.form>
                </div>
              </div>

              <div class="lg:col-span-5 lg:sticky lg:top-8 self-start">
                <CommunicationTimeline.communication_timeline entries={
                  @communication_timeline
                } />
              </div>
            </div>

            <.modal
              :if={@show_update_preview_modal}
              id="event-update-preview-modal"
              show
              on_cancel={JS.push("close-update-preview")}
              max_width="max-w-4xl"
            >
              <.header>
                Email preview
                <:subtitle :if={@update_preview_subject}>
                  Subject: {@update_preview_subject}
                </:subtitle>
              </.header>
              <iframe
                id="event-update-preview-iframe"
                phx-hook="EmailPreview"
                class="w-full border border-zinc-200 rounded min-h-[400px]"
              />
            </.modal>
          </div>

          <div :if={@live_action == :statistics} class="relative py-8 space-y-8">
            <div
              :if={@statistics_loading?}
              id="event-statistics-loading"
              class="space-y-8"
              role="status"
              aria-live="polite"
            >
              <span class="sr-only">Loading event statistics…</span>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <.skeleton_block :for={_ <- 1..7} class="h-28 rounded-lg" />
              </div>
              <.skeleton_block class="h-64 rounded-lg" />
            </div>

            <div
              :if={!@statistics_loading?}
              id="event-statistics-content"
              class="space-y-8"
            >
              <div
                id="event-stats-kpis"
                class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
              >
                <.admin_stat_card
                  id="stat-net-revenue"
                  label="Net Revenue"
                  value={money_display(@net_event_revenue)}
                  value_class={
                    if Money.negative?(@net_event_revenue),
                      do: "text-red-600",
                      else: "text-green-600"
                  }
                  subtitle="Ticket sales + other income − costs"
                  class="lg:col-span-3"
                />
                <.admin_stat_card
                  id="stat-ticket-sales"
                  label="Ticket Sales"
                  value={money_display(@sales_stats.total_revenue)}
                  subtitle={"#{@sales_stats.total_tickets_sold} ticket(s) sold"}
                />
                <.admin_stat_card
                  id="stat-other-income"
                  label="Other Income"
                  value={money_display(@expense_report_totals.income_total)}
                  subtitle="Income items on expense reports"
                />
                <.admin_stat_card
                  id="stat-total-revenue"
                  label="Total Revenue"
                  value={money_display(@total_event_revenue)}
                  subtitle="Ticket sales + other income"
                />
                <.admin_stat_card
                  id="stat-stripe-fees"
                  label="Stripe Fees"
                  value={money_display(@stripe_fees_total)}
                  subtitle="Processing fees on ticket payments"
                />
                <.admin_stat_card
                  id="stat-expense-reports"
                  label="Expense Reports"
                  value={money_display(@expense_report_totals.expense_total)}
                  subtitle="Gross costs (approved + paid)"
                />
                <.admin_stat_card
                  id="stat-total-costs"
                  label="Total Costs"
                  value={money_display(@total_event_costs)}
                  subtitle="Stripe fees + expense reports"
                />
              </div>

              <div
                :if={Money.positive?(@donations_total)}
                id="stat-donations"
                class="bg-purple-50 shadow-sm border border-purple-100 rounded-lg p-6"
              >
                <p class="text-xs font-black text-purple-400 uppercase tracking-[0.2em] mb-3">
                  Donations Collected
                </p>
                <p class="text-3xl font-black text-purple-900">
                  {money_display(@donations_total)}
                </p>
                <p class="text-xs text-purple-700 mt-1 font-medium">
                  Via donation ticket tiers — a bonus to the club as a whole, not counted in event revenue above.
                </p>
              </div>

              <div class="bg-white shadow-sm border border-zinc-100 rounded-lg p-6 space-y-4">
                <div>
                  <h2 class="text-xl font-bold">Sales Over Time</h2>
                  <p class="text-zinc-600 text-sm">
                    Confirmed ticket revenue by day.
                    <span :if={ticket_sale_window_label(@ticket_sale_window)}>
                      {ticket_sale_window_label(@ticket_sale_window)}.
                    </span>
                  </p>
                  <p
                    :if={@event_update_markers != %{}}
                    class="text-xs text-amber-700 flex items-center gap-1 mt-1"
                  >
                    <.icon name="hero-envelope" class="w-3.5 h-3.5" />
                    marks a day an event update email was sent — hover a bar for details
                  </p>
                </div>

                <p :if={@sales_over_time == []} class="text-sm text-zinc-500">
                  No ticket sales yet.
                </p>

                <div :if={@sales_over_time != []} class="flex gap-2">
                  <div class="flex flex-col justify-between shrink-0 w-14 h-40 pb-6 text-right text-[10px] text-zinc-400 tabular-nums">
                    <span>{money_display(@sales_chart_max_revenue)}</span>
                    <span>{money_display(money_half(@sales_chart_max_revenue))}</span>
                    <span>$0</span>
                  </div>

                  <div
                    id="sales-over-time-chart"
                    phx-hook="SalesChartTooltip"
                    data-tooltip-target="sales-chart-tooltip-popup"
                    class="flex-1 flex items-end gap-1 h-40 overflow-x-auto border-l border-zinc-100 pl-2 pb-2"
                  >
                    <div
                      :for={point <- @sales_over_time}
                      class="flex flex-col items-center justify-end shrink-0 w-9 h-full cursor-default"
                      data-tooltip={
                        sales_point_tooltip(point, @event_update_markers)
                      }
                    >
                      <.icon
                        :if={Map.has_key?(@event_update_markers, point.date)}
                        name="hero-envelope-solid"
                        class="w-3 h-3 text-amber-500 mb-0.5 shrink-0 pointer-events-none"
                      />
                      <div
                        class="w-5 bg-blue-500 hover:bg-blue-600 rounded-t transition-colors pointer-events-none"
                        style={"height: #{sales_bar_height_pct(point, @sales_chart_max_revenue)}%"}
                      />
                      <span class="text-[10px] text-zinc-400 mt-1 whitespace-nowrap pointer-events-none">
                        {Calendar.strftime(point.date, "%-m/%-d")}
                      </span>
                    </div>
                  </div>
                </div>

                <div
                  id="sales-chart-tooltip-popup"
                  class="fixed z-50 hidden max-w-xs rounded-md bg-zinc-900 px-3 py-2 text-xs text-zinc-100 shadow-lg whitespace-pre-line"
                  style="display: none;"
                >
                </div>
              </div>

              <div class="bg-white shadow-sm border border-zinc-100 rounded-lg p-6 space-y-4">
                <div>
                  <h2 class="text-xl font-bold">Sales by Ticket Tier</h2>
                  <p class="text-zinc-600 text-sm">
                    Confirmed tickets, net of discounts.
                  </p>
                </div>

                <p
                  :if={@sales_stats.by_tier == []}
                  class="text-sm text-zinc-500"
                >
                  No ticket tiers with sales yet.
                </p>

                <table
                  :if={@sales_stats.by_tier != []}
                  class="min-w-full divide-y divide-zinc-200 text-sm"
                >
                  <thead>
                    <tr class="text-left text-zinc-500">
                      <th class="py-2 pr-4 font-medium">Tier</th>
                      <th class="py-2 pr-4 font-medium">Tickets Sold</th>
                      <th class="py-2 pr-4 font-medium">Revenue</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-zinc-100">
                    <tr
                      :for={tier <- @sales_stats.by_tier}
                      id={"tier-sales-#{tier.ticket_tier_id}"}
                    >
                      <td class="py-2 pr-4 text-zinc-800">{tier.name}</td>
                      <td class="py-2 pr-4 text-zinc-800">
                        {tier.tickets_sold}
                      </td>
                      <td class="py-2 pr-4 text-zinc-800">
                        {money_display(tier.revenue)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div class="bg-white shadow-sm border border-zinc-100 rounded-lg p-6 space-y-4">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h2 class="text-xl font-bold">Expense Reports</h2>
                    <p class="text-zinc-600 text-sm">
                      Costs linked to this event, net of any income items logged against the report. Only approved and paid reports count toward totals.
                    </p>
                  </div>
                  <.link
                    navigate={~p"/admin/money?tab=expenses"}
                    class="text-sm font-medium text-blue-600 hover:text-blue-800 whitespace-nowrap"
                  >
                    Open Money → Expenses
                  </.link>
                </div>

                <p
                  :if={@event_expense_reports == []}
                  class="text-sm text-zinc-500"
                >
                  No expense reports linked to this event.
                </p>

                <table
                  :if={@event_expense_reports != []}
                  class="min-w-full divide-y divide-zinc-200 text-sm"
                >
                  <thead>
                    <tr class="text-left text-zinc-500">
                      <th class="py-2 pr-4 font-medium">Submitted By</th>
                      <th class="py-2 pr-4 font-medium">Purpose</th>
                      <th class="py-2 pr-4 font-medium">Status</th>
                      <th class="py-2 pr-4 font-medium">Net Cost</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-zinc-100">
                    <tr
                      :for={report <- @event_expense_reports}
                      id={"expense-report-#{report.id}"}
                    >
                      <td class="py-2 pr-4 text-zinc-800">
                        {expense_report_submitter_name(report.user)}
                      </td>
                      <td class="py-2 pr-4 text-zinc-800">{report.purpose}</td>
                      <td class="py-2 pr-4">
                        <.badge type={
                          AdminBadgeHelpers.expense_report_status_badge_type(
                            report.status
                          )
                        }>
                          {String.capitalize(report.status || "unknown")}
                        </.badge>
                      </td>
                      <td class="py-2 pr-4 text-zinc-800">
                        {money_display(
                          ExpenseReports.calculate_totals(report).net_total
                        )}
                      </td>
                    </tr>
                  </tbody>
                </table>

                <p class="text-sm font-medium text-zinc-700 pt-2 border-t border-zinc-100">
                  Net total (approved + paid): {money_display(
                    @expense_report_totals.net_total
                  )}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
    # Subscribe outside `connected?/1`: static mount runs first (disconnected) and
    # handle_params skips `load_event/2` when the URL id matches the mounted event,
    # so agenda PubSub updates would otherwise never be received.
    Agendas.subscribe(id)
    EditingPresence.subscribe(:event)

    if connected?(socket) do
      Events.subscribe()
    end

    connected_remount? =
      connected?(socket) &&
        socket.assigns[:loading_event?] == false &&
        match?(%{id: ^id}, socket.assigns[:event])

    socket =
      if connected_remount? do
        assign(socket, :list_params, Map.drop(params, ["id"]))
      else
        assign_event_loading_shell(socket, params, id)
      end

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    # Defer the draft INSERT until the WebSocket is connected. A disconnected
    # mount (HTTP GET /admin/events/new) used to insert + invalidate public
    # event caches before first paint, and `push_navigate` on dead render is
    # an extra round-trip. Posts/newsletters already create in-memory until save.
    if connected?(socket) do
      {:ok, inserted_event} =
        Events.create_event(%{
          title: "New Event",
          description: "",
          state: :draft,
          organizer_id: socket.assigns.current_user.id
        })

      {:ok,
       push_navigate(socket, to: "/admin/events/#{inserted_event.id}/edit")}
    else
      {:ok, assign_new_event_loading_shell(socket)}
    end
  end

  @impl true
  def handle_params(%{"id" => incoming_id} = params, _uri, socket) do
    current_id = socket.assigns[:event] && socket.assigns.event.id

    socket =
      socket
      |> assign(:list_params, Map.drop(params, ["id"]))
      |> then(fn socket ->
        if connected?(socket) do
          socket
          |> then(fn socket ->
            if incoming_id != current_id or socket.assigns[:loading_event?] do
              load_event(socket, incoming_id)
            else
              socket
            end
          end)
          |> maybe_refresh_tab_data()
        else
          socket
        end
      end)

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
    case socket.assigns[:event] do
      %{id: old_id} when old_id != id ->
        Agendas.unsubscribe(old_id)
        EditingPresence.untrack(socket, :event)

      _ ->
        :ok
    end

    Agendas.subscribe(id)
    EditingPresence.track(socket, :event, id, socket.assigns.current_user)

    event = Events.get_event!(id) |> Ysc.Repo.preload([:organizer, :updated_by])
    event_changeset = Event.changeset(event, %{})

    capacity_attrs = %{"unlimited_capacity" => is_nil(event.max_attendees)}
    capacity_changeset = Event.changeset(event, capacity_attrs)
    pacific_today = pacific_today()

    socket
    |> assign(:event, event)
    |> assign(:active_page, :events)
    |> assign(:capacity_form, to_form(capacity_changeset))
    |> assign(:page_title, event.title)
    |> assign(:description_length, description_length(event.description))
    |> assign(:event_title, event.title)
    |> assign(:state, event.state)
    |> assign(:pacific_today, pacific_today)
    |> assign(:start_date, event.start_date)
    |> assign(:end_date, event.end_date)
    |> assign(:start_time, event.start_time)
    |> assign(:end_time, event.end_time)
    |> assign(:can_publish, can_publish?(event.start_date, event.title))
    |> assign(:partiful_link_present, event.partiful_link not in [nil, ""])
    |> assign(trigger_submit: false, check_errors: false)
    |> assign(:hosts, [])
    |> assign(:host_ids, MapSet.new())
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> stream(:agendas, [], reset: true)
    |> assign(form: to_form(event_changeset, as: "event"))
    |> assign(
      :update_form,
      to_form(
        %{
          "title" => "",
          "raw_body" => "",
          "rendered_body" => "",
          "show_on_event_page" => false,
          "send_sms" => false
        },
        as: "update"
      )
    )
    |> assign_updates_tab_defaults()
    |> assign_statistics_tab_defaults()
    |> assign(:show_update_preview_modal, false)
    |> assign(:update_preview_subject, nil)
    |> assign(:location_presets, EventLocationConfig.presets())
    |> assign_check_in_path(event)
    |> assign(:loading_event?, false)
    |> assign(
      :editors,
      EditingPresence.editors(:event, id, socket.assigns.current_user.id)
    )
  end

  defp assign_new_event_loading_shell(socket) do
    socket
    |> assign(:loading_event?, true)
    |> assign(:event, nil)
    |> assign(:active_page, :events)
    |> assign(:page_title, "New Event")
    |> assign(:list_params, %{})
    |> assign(:event_title, "New Event")
    |> assign(:state, :draft)
    |> assign(:editors, [])
  end

  defp assign_event_loading_shell(socket, params, id) do
    socket
    |> assign(:loading_event?, true)
    |> assign(:event, %Event{id: id, state: :draft, title: ""})
    |> assign(:active_page, :events)
    |> assign(:page_title, "Event")
    |> assign(:list_params, Map.drop(params, ["id"]))
    |> assign(:event_title, "")
    |> assign(:state, :draft)
    |> assign(:pacific_today, pacific_today())
    |> assign(:start_date, nil)
    |> assign(:end_date, nil)
    |> assign(:start_time, nil)
    |> assign(:end_time, nil)
    |> assign(:can_publish, false)
    |> assign(:partiful_link_present, false)
    |> assign(trigger_submit: false, check_errors: false)
    |> assign(:hosts, [])
    |> assign(:host_ids, MapSet.new())
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> stream(:agendas, [], reset: true)
    |> assign_updates_tab_defaults()
    |> assign_statistics_tab_defaults()
    |> assign(:show_update_preview_modal, false)
    |> assign(:update_preview_subject, nil)
    |> assign(:check_in_path, nil)
    |> assign(:editors, [])
  end

  defp assign_updates_tab_defaults(socket) do
    dev_routes? = Application.get_env(:ysc, :dev_routes, false)

    socket
    |> assign(:event_updates, [])
    |> assign(:recipient_count, 0)
    |> assign(:sms_recipient_count, 0)
    |> assign(:sms_preview, nil)
    |> assign(:photo_collection, nil)
    |> assign(:photo_upload_url, nil)
    |> assign(:communication_timeline, [])
    |> assign(:dev_routes?, dev_routes?)
  end

  defp assign_statistics_tab_defaults(socket) do
    socket
    |> assign(:statistics_loading?, false)
    |> assign(:sales_stats, %{
      by_tier: [],
      total_revenue: Money.new(0, :USD),
      total_tickets_sold: 0
    })
    |> assign(:sales_over_time, [])
    |> assign(:sales_chart_max_revenue, Money.new(0, :USD))
    |> assign(:ticket_sale_window, %{start_date: nil, end_date: nil})
    |> assign(:event_update_markers, %{})
    |> assign(:stripe_fees_total, Money.new(0, :USD))
    |> assign(:event_expense_reports, [])
    |> assign(:expense_report_totals, %{
      expense_total: Money.new(0, :USD),
      income_total: Money.new(0, :USD),
      net_total: Money.new(0, :USD)
    })
    |> assign(:total_event_revenue, Money.new(0, :USD))
    |> assign(:total_event_costs, Money.new(0, :USD))
    |> assign(:net_event_revenue, Money.new(0, :USD))
    |> assign(:donations_total, Money.new(0, :USD))
  end

  defp assign_edit_tab_data(socket, event) do
    agendas = Agendas.list_agendas_for_event(event.id)
    hosts = Events.list_event_hosts(event)

    socket
    |> assign(:hosts, hosts)
    |> assign(:host_ids, host_ids_from(hosts))
    |> stream(:agendas, agendas, reset: true)
  end

  defp assign_updates_tab_data(socket, event) do
    event_updates = Events.list_event_updates(event.id)

    socket
    |> assign(:event_updates, event_updates)
    |> assign(:recipient_count, Events.count_event_update_recipients(event.id))
    |> assign(
      :sms_recipient_count,
      Events.count_event_update_sms_recipients(event.id)
    )
    |> assign_sms_preview()
    |> assign_photo_upload(event)
    |> then(fn socket ->
      assign_communication_timeline(
        socket,
        event,
        event_updates,
        socket.assigns.photo_collection
      )
    end)
  end

  defp assign_statistics_tab_data(socket, data) do
    sales_stats = data.sales_stats
    sales_over_time = data.sales_over_time
    stripe_fees_total = data.stripe_fees_total
    expense_reports = data.expense_reports
    expense_report_totals = data.expense_report_totals

    # Revenue = ticket sales plus any other income logged on expense reports
    # (e.g. cash collected at the door). Costs = Stripe fees plus the gross
    # expense total, so income isn't silently netted out of "costs" — it's
    # its own visible line item, and the two roll up to the same net figure.
    total_revenue =
      money_add(sales_stats.total_revenue, expense_report_totals.income_total)

    total_costs =
      money_add(stripe_fees_total, expense_report_totals.expense_total)

    net_revenue = money_sub(total_revenue, total_costs)

    socket
    |> assign(:statistics_loading?, false)
    |> assign(:sales_stats, sales_stats)
    |> assign(:sales_over_time, sales_over_time)
    |> assign(
      :sales_chart_max_revenue,
      sales_chart_max_revenue(sales_over_time)
    )
    |> assign(:ticket_sale_window, data.ticket_sale_window)
    |> assign(:event_update_markers, data.event_update_markers)
    |> assign(:stripe_fees_total, stripe_fees_total)
    |> assign(:event_expense_reports, expense_reports)
    |> assign(:expense_report_totals, expense_report_totals)
    |> assign(:total_event_revenue, total_revenue)
    |> assign(:total_event_costs, total_costs)
    |> assign(:net_event_revenue, net_revenue)
    |> assign(:donations_total, data.donations_total)
  end

  defp fetch_statistics_tab_data(event_id) do
    tasks = [
      {:sales_stats, fn -> Events.get_event_sales_stats(event_id) end},
      {:sales_over_time, fn -> Events.get_event_sales_over_time(event_id) end},
      {:stripe_fees_total,
       fn -> Events.get_event_stripe_fees_total(event_id) end},
      {:expense_reports,
       fn -> ExpenseReports.list_expense_reports_for_event(event_id) end},
      {:expense_report_totals,
       fn -> ExpenseReports.totals_for_event(event_id) end},
      {:ticket_sale_window,
       fn -> Events.get_event_ticket_sale_window(event_id) end},
      {:event_updates, fn -> Events.list_event_updates(event_id) end},
      {:donations_total, fn -> Events.get_event_donations_total(event_id) end}
    ]

    results =
      tasks
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        timeout: :infinity,
        ordered: true
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    event_updates = Map.fetch!(results, :event_updates)

    Map.put(
      results,
      :event_update_markers,
      event_update_markers_from(event_updates)
    )
    |> Map.delete(:event_updates)
  end

  defp event_update_markers_from(event_updates) when is_list(event_updates) do
    event_updates
    |> Enum.filter(& &1.sent_at)
    |> Enum.group_by(&DateTime.to_date(&1.sent_at))
  end

  defp sales_chart_max_revenue(points) do
    Enum.reduce(points, Money.new(0, :USD), fn point, max_so_far ->
      if Decimal.compare(point.revenue.amount, max_so_far.amount) == :gt,
        do: point.revenue,
        else: max_so_far
    end)
  end

  defp money_add(%Money{} = a, %Money{} = b) do
    case Money.add(a, b) do
      {:ok, sum} -> sum
      _ -> a
    end
  end

  defp money_sub(%Money{} = a, %Money{} = b) do
    case Money.sub(a, b) do
      {:ok, diff} -> diff
      _ -> a
    end
  end

  defp money_half(%Money{} = m) do
    Money.new(Decimal.div(m.amount, Decimal.new(2)), :USD)
  end

  # Money.to_string!/1 renders negative amounts as "$-1.00"; this renders them
  # the conventional way ("-$1.00") for anything shown to admins on this tab.
  defp money_display(%Money{} = m), do: Ysc.MoneyHelper.format_money!(m)

  defp sales_bar_height_pct(%{revenue: revenue}, %Money{} = max_revenue) do
    if Decimal.compare(max_revenue.amount, Decimal.new(0)) == :gt do
      pct =
        revenue.amount
        |> Decimal.div(max_revenue.amount)
        |> Decimal.mult(100)
        |> Decimal.to_float()

      max(pct, 4.0)
    else
      4.0
    end
  end

  defp ticket_sale_window_label(%{start_date: nil, end_date: nil}), do: nil

  defp ticket_sale_window_label(%{start_date: start_date, end_date: end_date}) do
    case {start_date, end_date} do
      {%DateTime{}, %DateTime{}} ->
        "Tickets on sale #{format_short_date(start_date)} – #{format_short_date(end_date)}"

      {%DateTime{}, nil} ->
        "Tickets on sale since #{format_short_date(start_date)}"

      {nil, %DateTime{}} ->
        "Ticket sales end #{format_short_date(end_date)}"
    end
  end

  defp format_short_date(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%b %-d, %Y")

  defp sales_point_tooltip(point, event_update_markers) do
    header = Calendar.strftime(point.date, "%b %-d, %Y")

    summary =
      "#{money_display(point.revenue)} · #{point.tickets_sold} ticket(s)"

    tier_lines =
      Enum.map(point.by_tier, fn tier ->
        "  #{tier.name}: #{tier.tickets_sold} · #{money_display(tier.revenue)}"
      end)

    update_lines =
      case event_update_marker_title(event_update_markers, point.date) do
        nil -> []
        title -> [title]
      end

    Enum.join([header, summary] ++ tier_lines ++ update_lines, "\n")
  end

  defp event_update_marker_title(event_update_markers, date) do
    case Map.get(event_update_markers, date) do
      nil ->
        nil

      updates ->
        titles = Enum.map_join(updates, ", ", &(&1.title || "Event update"))

        "Update sent: #{titles} (#{Calendar.strftime(date, "%b %-d, %Y")})"
    end
  end

  defp expense_report_submitter_name(%{first_name: first, last_name: last}) do
    String.trim("#{first} #{last}")
  end

  defp expense_report_submitter_name(_), do: "—"

  defp host_ids_from(hosts), do: hosts |> Enum.map(& &1.id) |> MapSet.new()

  defp assign_communication_timeline(
         socket,
         event,
         event_updates,
         photo_collection
       ) do
    collection =
      photo_collection ||
        if event.state in [:published, "published"],
          do: EventPhotos.get_by_event_id(event.id),
          else: nil

    assign(
      socket,
      :communication_timeline,
      CommunicationTimeline.build_entries(event, event_updates, collection)
    )
  end

  defp assign_photo_upload(socket, event) do
    dev_routes? = Application.get_env(:ysc, :dev_routes, false)

    cached_collection =
      case socket.assigns[:photo_collection] do
        %EventPhotos.Collection{event_id: id} when id == event.id ->
          socket.assigns.photo_collection

        _ ->
          nil
      end

    {collection, upload_url} =
      if event.state in [:published, "published"] do
        collection =
          cached_collection || EventPhotos.get_by_event_id(event.id)

        {collection,
         if(collection, do: EventPhotos.upload_url(collection), else: nil)}
      else
        {nil, nil}
      end

    socket
    |> assign(:photo_collection, collection)
    |> assign(:photo_upload_url, upload_url)
    |> assign(:dev_routes?, dev_routes?)
  end

  defp assign_check_in_path(socket, event) do
    assign(socket, :check_in_path, AdminCheckInPaths.path_for_event(event.id))
  end

  defp maybe_refresh_tab_data(socket) do
    if connected?(socket) do
      case socket.assigns[:event] do
        nil ->
          socket

        event ->
          case socket.assigns.live_action do
            :updates ->
              assign_updates_tab_data(socket, event)

            :edit ->
              assign_edit_tab_data(socket, event)

            :statistics ->
              socket
              |> assign(:statistics_loading?, true)
              |> start_async(:load_statistics, fn ->
                fetch_statistics_tab_data(event.id)
              end)

            _ ->
              socket
          end
      end
    else
      socket
    end
  end

  # Compatibility for clients that loaded the former EmailPreview handshake.
  @impl true
  def handle_event("preview-ready", _params, socket), do: {:noreply, socket}

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
    event = socket.assigns.event

    case Agendas.create_agenda(event, %{title: "Agenda", event_id: event.id}) do
      {:ok, _agenda} ->
        # `create_agenda/2` broadcasts `AgendaAdded`; `handle_info/2` performs
        # `stream_insert`. Do not insert here or the same row appears twice.
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Could not add agenda.",
           title: "Agenda"
         )}
    end
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
    # rendered_details is computed server-side on editor-update; never trust client params.
    event_params =
      Map.drop(event_params, ["rendered_details", :rendered_details])

    # Reload event to ensure we have the latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    event_changeset =
      Event.editor_changeset(current_event, event_params)
      |> Map.put(:action, :validate)

    {updated_event, updated_changeset} =
      if event_changeset.valid? do
        case Events.update_event_editor(current_event, event_params,
               updated_by_id: socket.assigns.current_user.id
             ) do
          {:ok, updated_event} ->
            # Update succeeded, rebuild changeset with updated event
            updated_changeset =
              Event.editor_changeset(updated_event, event_params)
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
     # Prefer typed values from the event/changeset so header formatting and
     # the date picker do not receive raw form strings.
     |> assign(
       :start_date,
       Ecto.Changeset.get_field(updated_changeset, :start_date)
     )
     |> assign(
       :end_date,
       Ecto.Changeset.get_field(updated_changeset, :end_date)
     )
     |> assign(
       :start_time,
       Ecto.Changeset.get_field(updated_changeset, :start_time)
     )
     |> assign(
       :end_time,
       Ecto.Changeset.get_field(updated_changeset, :end_time)
     )
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

    socket =
      socket
      |> assign(:update_form, to_form(updated_params, as: "update"))
      |> assign_sms_preview()
      |> maybe_refresh_update_preview()

    {:noreply, socket}
  end

  def handle_event(
        "editor-update",
        %{"field" => _field, "value" => raw_body},
        socket
      ) do
    # Reload event to get latest lock_version
    current_event = Events.get_event!(socket.assigns[:event].id)

    rendered =
      raw_body
      |> Scrubber.scrub(Ysc.TrixScrubber)
      |> Ysc.Html.Links.open_in_new_tab()

    update_attrs = %{"raw_details" => raw_body, "rendered_details" => rendered}
    changeset = Event.editor_changeset(current_event, update_attrs)

    {updated_event, updated_changeset} =
      if changeset.valid? do
        case Events.update_event_editor(current_event, update_attrs,
               updated_by_id: socket.assigns.current_user.id
             ) do
          {:ok, updated_event} ->
            updated_changeset =
              Event.editor_changeset(updated_event, update_attrs)

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
    socket =
      socket
      |> assign(:update_form, to_form(params, as: "update"))
      |> assign_sms_preview()
      |> maybe_refresh_update_preview()

    {:noreply, socket}
  end

  def handle_event("open-update-preview", _params, socket) do
    case build_update_preview(socket) do
      {:ok, socket} ->
        {:noreply, assign(socket, :show_update_preview_modal, true)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("close-update-preview", _params, socket) do
    {:noreply, assign(socket, :show_update_preview_modal, false)}
  end

  def handle_event("send-photo-reminder", _params, socket) do
    event = socket.assigns.event

    if Application.get_env(:ysc, :dev_routes, false) do
      do_send_photo_reminder(event, socket)
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "This dev-only action is not available in this environment.",
         title: "Event photos"
       )}
    end
  end

  def handle_event("send-event-update", %{"update" => params}, socket) do
    event = socket.assigns.event
    raw_body = params["raw_body"] || ""
    rendered_body = Scrubber.scrub(raw_body, Ysc.TrixScrubber)
    send_sms = params["send_sms"] == "true"

    if String.trim(raw_body) == "" do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Message body cannot be empty.",
         title: "Update"
       )}
    else
      sms_body =
        if send_sms do
          Segment.build_event_update_sms(
            event.title || "",
            params["title"],
            rendered_body
          ).body
        else
          nil
        end

      attrs = %{
        title: params["title"],
        raw_body: raw_body,
        rendered_body: rendered_body,
        show_on_event_page: params["show_on_event_page"] == "true",
        send_sms: send_sms,
        sms_body: sms_body,
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
                flash_msg =
                  if send_sms do
                    "Update queued for #{socket.assigns.recipient_count} email(s) and #{socket.assigns.sms_recipient_count} SMS recipient(s)."
                  else
                    "Update queued for #{socket.assigns.recipient_count} recipient(s)."
                  end

                YscWeb.Flash.put_toast(
                  socket,
                  :info,
                  flash_msg,
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
                 "show_on_event_page" => false,
                 "send_sms" => false
               },
               as: "update"
             )
           )
           |> assign(:sms_preview, nil)
           |> assign_updates_tab_data(event)}

        {:error, changeset} ->
          message =
            YscWeb.FormHelpers.format_changeset_errors(changeset,
              field_format: :humanize
            )

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

  def handle_event("location-selected", params, socket) do
    {:noreply, apply_location(socket, params)}
  end

  def handle_event("apply-location-preset", %{"id" => id}, socket) do
    case EventLocationConfig.get(id) do
      {:ok, preset} ->
        attrs =
          preset
          |> Map.drop([:id, :label])
          |> Map.new(fn {key, value} -> {to_string(key), value} end)
          |> Map.put("place_id", nil)

        {:noreply, apply_location(socket, attrs)}

      :error ->
        {:noreply, socket}
    end
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

        case Events.update_event_editor(
               current_event,
               %{"max_attendees" => new_max_attendees},
               updated_by_id: socket.assigns.current_user.id
             ) do
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
        case Events.update_event_editor(current_event, capacity_params,
               updated_by_id: socket.assigns.current_user.id
             ) do
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

    case Events.update_event_editor(current_event, capacity_params,
           updated_by_id: socket.assigns.current_user.id
         ) do
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
             |> assign(:host_ids, host_ids_from(hosts))
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

        {:noreply,
         socket
         |> assign(:hosts, hosts)
         |> assign(:host_ids, host_ids_from(hosts))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:load_statistics, {:ok, data}, socket) do
    {:noreply, assign_statistics_tab_data(socket, data)}
  end

  def handle_async(:load_statistics, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load event statistics: #{inspect(reason)}")

    {:noreply, assign(socket, :statistics_loading?, false)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaAdded{agenda: agenda}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda)
     |> push_event("scroll-agenda-into-view", %{id: "agendas-#{agenda.id}"})}
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

      {:noreply,
       socket
       |> assign(:hosts, hosts)
       |> assign(:host_ids, host_ids_from(hosts))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierAdded{}},
        socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierDeleted{}},
        socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:updated_event, %{id: "event_date"} = data}, socket) do
    current_event = Events.get_event!(socket.assigns.event.id)

    {attrs, cleared_end_time?} =
      %{
        start_date: data[:start_date],
        end_date: data[:end_date]
      }
      |> maybe_clear_end_time_for_single_day(current_event)

    changeset = Event.editor_changeset(current_event, attrs)

    {updated_event, updated_changeset, save_error?} =
      if changeset.valid? do
        case Events.update_event_editor(current_event, attrs,
               updated_by_id: socket.assigns.current_user.id
             ) do
          {:ok, event} ->
            {event, Event.editor_changeset(event, attrs), false}

          {:error, error_changeset} ->
            {current_event, error_changeset, true}
        end
      else
        {current_event, changeset, true}
      end

    socket =
      socket
      |> assign(:event, updated_event)
      |> assign(:start_date, updated_event.start_date)
      |> assign(:end_date, updated_event.end_date)
      |> assign(:start_time, updated_event.start_time)
      |> assign(:end_time, updated_event.end_time)
      |> assign(
        :can_publish,
        can_publish?(updated_event.start_date, updated_event.title)
      )
      |> assign_form(updated_changeset)

    socket =
      cond do
        save_error? ->
          YscWeb.Flash.put_toast(
            socket,
            :error,
            "Could not save event dates. Check the form for errors.",
            title: "Event"
          )

        cleared_end_time? ->
          YscWeb.Flash.put_toast(
            socket,
            :info,
            "End time was cleared because it was overnight or after the start time on a single-day event.",
            title: "Event"
          )

        true ->
          socket
      end

    {:noreply, socket}
  end

  # Ticket-tier sale date pickers (and any other date pickers) send the same
  # message shape; ignore them here so they do not overwrite event dates.
  def handle_info({:updated_event, _data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {YscWeb.MediaPickerComponent, _component_id, :cleared},
        socket
      ) do
    current_event = Events.get_event!(socket.assigns[:event].id)

    case Events.update_event_editor(current_event, %{image_id: nil},
           updated_by_id: socket.assigns.current_user.id
         ) do
      {:ok, event} ->
        changeset = Event.changeset(event, %{"image_id" => nil})
        {:noreply, assign_form(socket, changeset) |> assign(:event, event)}

      {:error, _} ->
        reloaded_event = Events.get_event!(socket.assigns[:event].id)

        case Events.update_event_editor(reloaded_event, %{image_id: nil},
               updated_by_id: socket.assigns.current_user.id
             ) do
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
        case Events.update_event_editor(
               current_event,
               %{image_id: image_id},
               updated_by_id: socket.assigns.current_user.id
             ) do
          {:ok, event} -> event
          {:error, _} -> current_event
        end
      else
        current_event
      end

    {:noreply,
     socket |> assign_form(changeset) |> assign(:event, updated_event)}
  end

  def handle_info({YscWeb.TrixImagePickerComponent, id, image}, socket) do
    url = Image.display_path(image)

    target_input_id =
      case id do
        :event_update_body_image_picker -> "update[raw_body]"
        _ -> "post[raw_body]"
      end

    {:noreply,
     push_event(socket, "insert-trix-image", %{
       url: url,
       href: "#{url}?content-disposition=attachment",
       alt: image.alt_text || image.title || "",
       target_input_id: target_input_id
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
      {:noreply, refresh_event_updates(socket, event_id)}
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
      {:noreply, refresh_event_updates(socket, event_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({Ysc.Events, _msg}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    editors =
      EditingPresence.editors(
        :event,
        socket.assigns.event.id,
        socket.assigns.current_user.id
      )

    {:noreply, assign(socket, :editors, editors)}
  end

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

  defp refresh_event_updates(socket, event_id) do
    event = socket.assigns.event
    event_updates = Events.list_event_updates(event_id)

    photo_collection = socket.assigns[:photo_collection]

    socket
    |> assign(:event, event)
    |> assign(:event_updates, event_updates)
    |> assign_communication_timeline(event, event_updates, photo_collection)
  end

  defp build_update_preview(socket) do
    params = socket.assigns.update_form.params || %{}
    raw_body = params["raw_body"] || ""

    if String.trim(raw_body) == "" do
      {:error,
       YscWeb.Flash.put_toast(socket, :error, "Message body cannot be empty.",
         title: "Preview"
       )}
    else
      event = socket.assigns.event

      rendered_body = Scrubber.scrub(raw_body, Ysc.TrixScrubber)

      preview_update = %EventUpdate{
        title: params["title"],
        rendered_body: rendered_body
      }

      recipient = %{
        first_name: socket.assigns.current_user.first_name,
        email: socket.assigns.current_user.email
      }

      preview_html =
        try do
          event
          |> EventUpdateNotification.prepare_email_data(
            preview_update,
            recipient
          )
          |> EventUpdateNotification.render()
        rescue
          _ ->
            "<p style=\"padding: 1rem; color: #71717a;\">Preview unavailable.</p>"
        end

      prev_hash = Map.get(socket.assigns, :_update_preview_hash)
      new_hash = :erlang.phash2(preview_html)

      socket =
        socket
        |> assign(
          :update_preview_subject,
          EventUpdateNotification.get_subject(event, preview_update)
        )

      socket =
        if new_hash != prev_hash do
          socket
          |> assign(:_update_preview_hash, new_hash)
          |> push_event("preview-html", %{html: preview_html})
        else
          socket
        end

      {:ok, socket}
    end
  end

  defp do_send_photo_reminder(event, socket) do
    case EventPhotos.deliver_reminder_now(event,
           force: true,
           allow_future: true
         ) do
      :ok ->
        event = Events.get_event!(event.id)
        collection = EventPhotos.get_by_event_id(event.id)
        event_updates = Events.list_event_updates(event.id)

        {:noreply,
         socket
         |> assign(:event, event)
         |> assign(:photo_collection, collection)
         |> assign_communication_timeline(event, event_updates, collection)
         |> YscWeb.Flash.put_toast(
           :info,
           "Photo reminder emails have been queued.",
           title: "Event photos"
         )}

      {:error, :not_found} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Event not found.",
           title: "Event photos"
         )}

      {:error, :event_not_ended} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "This event hasn't ended yet, so there won't be any photos to remind attendees about.",
           title: "Event photos"
         )}
    end
  end

  defp maybe_refresh_update_preview(socket) do
    if socket.assigns[:show_update_preview_modal] do
      case build_update_preview(socket) do
        {:ok, socket} -> socket
        {:error, socket} -> assign(socket, :show_update_preview_modal, false)
      end
    else
      socket
    end
  end

  defp assign_sms_preview(socket) do
    form = socket.assigns[:update_form]
    event = socket.assigns[:event]

    if sms_checked?(form) and event do
      params = form_params(form)
      raw_body = params["raw_body"] || ""
      rendered_body = Scrubber.scrub(raw_body, Ysc.TrixScrubber)

      preview =
        Segment.build_event_update_sms(
          event.title || "",
          params["title"],
          rendered_body
        )

      assign(socket, :sms_preview, preview)
    else
      assign(socket, :sms_preview, nil)
    end
  end

  defp sms_checked?(nil), do: false

  defp sms_checked?(%Phoenix.HTML.Form{} = form) do
    value =
      case form[:send_sms] do
        %{value: value} -> value
        _ -> form_params(form)["send_sms"]
      end

    value in [true, "true"]
  end

  defp sms_checked?(_), do: false

  defp form_params(%Phoenix.HTML.Form{params: params}) when is_map(params),
    do: params

  defp form_params(_), do: %{}

  defp event_update_confirm_message(
         recipient_count,
         sms_recipient_count,
         form,
         sms_preview
       ) do
    if sms_checked?(form) do
      segments =
        case sms_preview do
          %{segment_count: count} -> count
          _ -> 1
        end

      "Send this update to #{recipient_count} email recipient(s) and #{sms_recipient_count} SMS recipient(s) (#{segments} SMS segment(s) each)? This cannot be undone."
    else
      "Send this update to #{recipient_count} recipient(s)? This cannot be undone."
    end
  end

  defp sms_encoding_label(:gsm7), do: "GSM-7"
  defp sms_encoding_label(:ucs2), do: "UCS-2"
  defp sms_encoding_label(_), do: "SMS"

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

  defp apply_location(socket, params) do
    current_event = Events.get_event!(socket.assigns.event.id)
    attrs = build_location_attrs(params)

    if attrs == %{} do
      socket
    else
      changeset = Event.changeset(current_event, attrs)

      updated_event =
        if changeset.valid? do
          case Events.update_event_editor(current_event, attrs,
                 updated_by_id: socket.assigns.current_user.id
               ) do
            {:ok, event} -> event
            {:error, _} -> current_event
          end
        else
          current_event
        end

      updated_changeset =
        Event.changeset(updated_event, attrs)
        |> Map.put(:action, :validate)

      assign_form(socket, updated_changeset)
      |> assign(:event, updated_event)
    end
  end

  # Multi-day events often keep an overnight end_time (e.g. 18:00 → 02:00).
  # Collapsing to a single calendar day would make start > end and silently
  # fail validation — clear the end time so the date change can persist.
  defp maybe_clear_end_time_for_single_day(attrs, event) do
    start_date = date_only(attrs[:start_date])
    end_date = date_only(attrs[:end_date])

    same_day? = start_date != nil and end_date != nil and start_date == end_date

    if same_day? and overnight_or_inverted_times?(event) do
      {Map.put(attrs, :end_time, nil), true}
    else
      {attrs, false}
    end
  end

  # Equality is intentional: a zero-length same-day window (end == start) is
  # treated as inverted / invalid for a single-day event, same as overnight.
  defp overnight_or_inverted_times?(%{
         start_time: start_time,
         end_time: end_time
       })
       when not is_nil(start_time) and not is_nil(end_time) do
    Time.compare(end_time, start_time) != :gt
  end

  defp overnight_or_inverted_times?(_), do: false

  defp date_only(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp date_only(%Date{} = date), do: date
  defp date_only(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp date_only(_), do: nil

  defp pacific_today do
    DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
  end

  defp build_location_attrs(params) do
    params
    |> Map.take([
      "location_name",
      "address",
      "latitude",
      "longitude",
      "place_id"
    ])
    |> Enum.reject(fn
      {"place_id", nil} -> false
      {_key, value} -> value in [nil, ""]
    end)
    |> Map.new()
  end

  defp location_set?(form) do
    form[:location_name].value not in [nil, ""] or
      form[:address].value not in [nil, ""] or
      present_coordinate?(form[:latitude].value) or
      present_coordinate?(form[:longitude].value)
  end

  defp present_coordinate?(nil), do: false
  defp present_coordinate?(""), do: false
  defp present_coordinate?(_), do: true

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

  defp event_help_topic(:tickets), do: "events/tickets"
  defp event_help_topic(:updates), do: "events/updates"
  defp event_help_topic(_), do: "events/create"
end
