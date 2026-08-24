defmodule YscWeb.AdminSettingsLive do
  alias Ysc.GooglePhotos
  alias Ysc.Settings
  alias Ysc.Repo
  alias Oban.Job
  alias Phoenix.LiveView.JS
  alias YscWeb.Admin.DateTimeDisplay
  alias Ysc.PropertyOutages.Queries, as: OutageQueries
  alias Ysc.Bookings.PropertyDisplay

  use YscWeb, :admin_live_view

  require Ysc.Logging

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents

  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex justify-between py-6">
        <.admin_page_title>Settings</.admin_page_title>
      </div>

      <div class="w-full">
        <div
          :if={@loading_settings?}
          id="admin-settings-loading"
          class="max-w-screen-md space-y-6 animate-pulse"
        >
          <%= for _i <- 1..2 do %>
            <div class="space-y-3">
              <.skeleton_block class="h-6 w-32 rounded" />
              <div class="space-y-4">
                <%= for _j <- 1..3 do %>
                  <div class="space-y-2">
                    <.skeleton_block class="h-4 w-40 rounded" />
                    <.skeleton_block class="h-10 w-full rounded" />
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <.skeleton_block class="h-10 w-24 rounded" />
        </div>

        <div :if={!@loading_settings?} id="admin-settings" class="max-w-screen-md">
          <.form for={@form} id="admin-settings-form" phx-submit="update-settings">
            <div :for={scope <- @scopes}>
              <h2 class="text-lg leading-8 font-semibold text-zinc-800">
                {String.capitalize(scope)}
              </h2>
              <div>
                <ul>
                  <li :for={entry <- Map.get(@grouped_settings, scope)} class="py-2">
                    <label
                      class="leading-6 text-zinc-800 font-semibold"
                      for={entry.id}
                    >
                      {entry.name
                      |> String.replace("_", " ")
                      |> String.capitalize()}:
                    </label>
                    <input
                      id={entry.id}
                      type="text"
                      class="mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"
                      name={"settings[#{entry.name}][value]"}
                      value={entry.value}
                    />
                    <input
                      name={"settings[#{entry.name}][name]"}
                      type="hidden"
                      value={entry.name}
                    />
                    <input
                      name={"settings[#{entry.name}][group]"}
                      type="hidden"
                      value={entry.group}
                    />
                  </li>
                </ul>
              </div>
            </div>
            <button
              class="mt-4 phx-submit-loading:opacity-75 rounded bg-blue-700 hover:bg-blue-800 py-2 px-6 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
              phx-disable-with="Saving..."
              type="submit"
            >
              Save
            </button>
          </.form>
        </div>

        <div id="google-photos-integration" class="w-full py-4 max-w-screen-md">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-3">
            Google Photos
          </h2>
          <div
            :if={@loading_settings?}
            class="bg-white shadow rounded-lg p-4 space-y-4 animate-pulse"
          >
            <.skeleton_block class="h-4 w-64 rounded" />
            <.skeleton_block class="h-10 w-48 rounded" />
          </div>
          <div
            :if={!@loading_settings?}
            class="bg-white shadow rounded-lg p-4 space-y-4"
          >
            <%= if !@google_photos_status.oauth_configured do %>
              <p class="text-sm text-zinc-600">
                Set
                <code class="text-xs bg-zinc-100 px-1 rounded">
                  GOOGLE_PHOTOS_CLIENT_ID
                </code>
                and
                <code class="text-xs bg-zinc-100 px-1 rounded">
                  GOOGLE_PHOTOS_CLIENT_SECRET
                </code>
                to enable this integration.
              </p>
            <% else %>
              <%= if @google_photos_status.connected do %>
                <div class="space-y-2">
                  <p class="text-sm text-zinc-800">
                    <span class="font-semibold">Status:</span>
                    <.badge type="green" class="!me-0 ms-2">Connected</.badge>
                  </p>
                  <p
                    :if={@google_photos_status.account_email}
                    class="text-sm text-zinc-600"
                  >
                    <span class="font-semibold text-zinc-800">Account:</span>
                    {@google_photos_status.account_email}
                  </p>
                  <p
                    :if={@google_photos_status.connected_at}
                    class="text-sm text-zinc-600"
                  >
                    <span class="font-semibold text-zinc-800">Connected:</span>
                    <span
                      id="google-photos-connected-at"
                      phx-hook="LocalTime"
                      data-utc-time={
                        DateTime.to_iso8601(@google_photos_status.connected_at)
                      }
                      data-prefix=""
                    >
                      {DateTimeDisplay.format_utc_iso_minute(
                        @google_photos_status.connected_at
                      )}
                    </span>
                  </p>
                  <p
                    :if={@google_photos_scopes_preview}
                    class="text-sm text-zinc-600"
                  >
                    <span class="font-semibold text-zinc-800">Scopes:</span>
                    <span class="break-all">{@google_photos_scopes_preview}</span>
                  </p>
                  <p
                    :if={google_photos_scopes_stale?(@google_photos_status.scopes)}
                    class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded px-3 py-2"
                  >
                    Missing upload, read, or edit permissions for app-created albums. Disconnect and connect again to grant all required Google Photos scopes.
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <button
                    id="google-photos-test-connection"
                    type="button"
                    phx-click="google-photos-test-connection"
                    class="rounded px-4 py-2 bg-blue-700 hover:bg-blue-800 text-sm font-semibold text-zinc-100"
                    phx-disable-with="Testing..."
                  >
                    Test connection
                  </button>
                  <.link
                    id="google-photos-disconnect"
                    href={~p"/admin/integrations/google-photos"}
                    method="delete"
                    class="rounded px-4 py-2 bg-zinc-100 hover:bg-zinc-200 text-sm font-semibold text-zinc-800"
                    data-confirm="Disconnect Google Photos? Upload features will stop working until you reconnect."
                  >
                    Disconnect
                  </.link>
                </div>
              <% else %>
                <p class="text-sm text-zinc-600">
                  Connect the organization's Google account used for event photo albums and backups.
                </p>
                <.link
                  id="google-photos-connect"
                  href={~p"/admin/integrations/google-photos/connect"}
                  class="inline-flex rounded px-4 py-2 bg-blue-700 hover:bg-blue-800 text-sm font-semibold text-zinc-100"
                >
                  Connect Google Photos
                </.link>
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-3">Misc</h2>
          <.link
            class="rounded px-4 py-3 bg-blue-700 hover:bg-blue-800 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-100"
            navigate={~p"/admin/dashboard"}
          >
            <.icon
              name="hero-arrow-top-right-on-square"
              class=" text-zinc-100 w-4 h-4 -mt-1 mr-2"
            /> System Dashboard
          </.link>
        </div>
        <!-- Reported Outages -->
        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-4">
            Reported Outages
          </h2>
          <div
            :if={!@outages_loaded}
            class="bg-white shadow rounded-lg overflow-hidden animate-pulse"
          >
            <div class="h-12 bg-zinc-100"></div>
            <%= for _i <- 1..3 do %>
              <div class="h-14 border-t border-zinc-200 flex items-center px-6 gap-4">
                <div class="h-4 bg-zinc-200 rounded w-24"></div>
                <div class="h-4 bg-zinc-200 rounded w-20"></div>
                <div class="h-4 bg-zinc-200 rounded w-40"></div>
                <div class="h-4 bg-zinc-200 rounded w-32"></div>
              </div>
            <% end %>
          </div>
          <div
            :if={@outages_loaded}
            class="bg-white shadow rounded-lg overflow-hidden"
          >
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Property
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Type
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Company
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Description
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Incident Date
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Reported
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={outage <- @recent_outages}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {PropertyDisplay.short_name(outage.property)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <.badge
                      type={get_outage_type_color(outage.incident_type)}
                      class="!me-0"
                    >
                      {outage.incident_type
                      |> to_string()
                      |> String.replace("_", " ")}
                    </.badge>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {outage.company_name || "—"}
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-900">
                    {outage.description || "—"}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {DateTimeDisplay.format_calendar_date_long(outage.incident_date)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <span
                      id={"outage-time-#{outage.id}"}
                      phx-hook="LocalTime"
                      data-utc-time={DateTime.to_iso8601(outage.inserted_at)}
                      data-prefix=""
                    >
                      {DateTimeDisplay.format_utc_iso(outage.inserted_at)}
                    </span>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@recent_outages)}>
                  <td
                    colspan="6"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No outages reported.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Queue Statistics -->
        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-4">
            Queue Statistics
          </h2>
          <div
            :if={!@oban_data_loaded}
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <%= for _i <- 1..3 do %>
              <div class="bg-white shadow rounded-lg p-4 animate-pulse">
                <div class="h-5 bg-zinc-200 rounded w-24 mb-3"></div>
                <div class="space-y-2">
                  <%= for _j <- 1..6 do %>
                    <div class="flex justify-between">
                      <div class="h-4 bg-zinc-100 rounded w-20"></div>
                      <div class="h-4 bg-zinc-100 rounded w-8"></div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
          <div
            :if={@oban_data_loaded}
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <%= for {queue, stats} <- @queue_stats do %>
              <div class="bg-white shadow rounded-lg p-4">
                <h3 class="font-semibold text-zinc-900 mb-3">{queue}</h3>
                <div class="space-y-2 text-sm">
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Available</span>
                    <.badge type="default" class="!me-0">
                      {Map.get(stats, "available", 0)}
                    </.badge>
                  </div>
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Executing</span>
                    <.badge type="yellow" class="!me-0">
                      {Map.get(stats, "executing", 0)}
                    </.badge>
                  </div>
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Scheduled</span>
                    <.badge type="sky" class="!me-0">
                      {Map.get(stats, "scheduled", 0)}
                    </.badge>
                  </div>
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Retryable</span>
                    <.badge type="yellow" class="!me-0">
                      {Map.get(stats, "retryable", 0)}
                    </.badge>
                  </div>
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Completed</span>
                    <.badge type="green" class="!me-0">
                      {Map.get(stats, "completed", 0)}
                    </.badge>
                  </div>
                  <div class="flex justify-between items-center gap-2">
                    <span class="text-zinc-600">Discarded</span>
                    <.badge type="red" class="!me-0">
                      {Map.get(stats, "discarded", 0)}
                    </.badge>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Recent Oban Jobs -->
        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-4">
            Recent Oban Jobs
          </h2>
          <div
            :if={!@oban_data_loaded}
            class="bg-white shadow rounded-lg overflow-hidden animate-pulse"
          >
            <div class="h-12 bg-zinc-100"></div>
            <%= for _i <- 1..5 do %>
              <div class="h-14 border-t border-zinc-200 flex items-center px-6 gap-4">
                <div class="h-4 bg-zinc-200 rounded w-32"></div>
                <div class="h-4 bg-zinc-200 rounded w-40"></div>
                <div class="h-4 bg-zinc-200 rounded w-16"></div>
                <div class="h-4 bg-zinc-200 rounded w-24"></div>
              </div>
            <% end %>
          </div>
          <div
            :if={@oban_data_loaded}
            class="bg-white shadow rounded-lg overflow-hidden"
          >
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Job ID
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Worker
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Queue
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    State
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Processed At
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Execution
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Attempts
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr
                  :for={job <- @recent_jobs}
                  phx-click="show_job_details"
                  phx-value-job_id={job.id}
                  class={[
                    "cursor-pointer transition-colors",
                    if(job.state == "executing",
                      do:
                        "bg-orange-50/70 hover:bg-orange-100/70 border-l-4 border-orange-500",
                      else: "hover:bg-zinc-50"
                    )
                  ]}
                >
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                    {String.slice(to_string(job.id), 0..20)}...
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <span class="font-medium">{job.worker}</span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {job.queue}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "px-2 inline-flex items-center gap-1.5 text-xs leading-5 font-semibold rounded-full",
                      get_job_state_color(job.state),
                      job.state == "executing" && "animate-pulse"
                    ]}>
                      <%= if job.state == "executing" do %>
                        <span
                          class="inline-block w-3 h-3 border-2 border-orange-600 border-t-transparent rounded-full animate-spin"
                          aria-hidden="true"
                        ></span>
                      <% end %>
                      {job.state}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <%= if job.completed_at do %>
                      <span
                        id={"job-time-#{job.id}-completed"}
                        phx-hook="LocalTime"
                        data-utc-time={DateTime.to_iso8601(job.completed_at)}
                        data-prefix=""
                      >
                        {DateTimeDisplay.format_utc_iso(job.completed_at)}
                      </span>
                    <% else %>
                      <%= if job.scheduled_at do %>
                        <span
                          id={"job-time-#{job.id}-scheduled"}
                          phx-hook="LocalTime"
                          data-utc-time={DateTime.to_iso8601(job.scheduled_at)}
                          data-prefix="Scheduled: "
                        >
                          Scheduled: {DateTimeDisplay.format_utc_iso(
                            job.scheduled_at
                          )}
                        </span>
                      <% else %>
                        <%= if job.inserted_at do %>
                          <span
                            id={"job-time-#{job.id}-inserted"}
                            phx-hook="LocalTime"
                            data-utc-time={DateTime.to_iso8601(job.inserted_at)}
                            data-prefix=""
                          >
                            {DateTimeDisplay.format_utc_iso(job.inserted_at)}
                          </span>
                        <% else %>
                          N/A
                        <% end %>
                      <% end %>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <%= if job.completed_at && job.attempted_at do %>
                      {format_duration(
                        DateTime.diff(
                          job.completed_at,
                          job.attempted_at,
                          :millisecond
                        )
                      )}
                    <% else %>
                      N/A
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {job.attempt}/{job.max_attempts}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-sm font-medium"
                    phx-click="reschedule_job"
                    phx-value-job_id={job.id}
                    onclick="event.stopPropagation()"
                  >
                    <.button class="bg-green-600 hover:bg-green-700">
                      Re-schedule
                    </.button>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@recent_jobs)}>
                  <td
                    colspan="8"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No jobs found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <.modal
          :if={@show_job_modal}
          id="job-details-modal"
          show={true}
          on_cancel={JS.push("close_job_modal")}
        >
          <div :if={@selected_job} class="space-y-4">
            <h2 class="text-xl font-semibold text-zinc-900">Job Details</h2>
            <div>
              <h3 class="text-sm font-semibold text-zinc-700 mb-2">Worker</h3>
              <p class="text-sm text-zinc-900 font-mono">
                {@selected_job.worker}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-700 mb-2">Arguments</h3>
              <pre
                phx-no-curly-interpolation
                class="text-xs bg-zinc-50 p-3 rounded border border-zinc-200 overflow-x-auto"
              ><%= Jason.encode!(@selected_job.args, pretty: true) %></pre>
            </div>
            <div :if={@selected_job.meta != %{} && @selected_job.meta != nil}>
              <h3 class="text-sm font-semibold text-zinc-700 mb-2">Metadata</h3>
              <pre
                phx-no-curly-interpolation
                class="text-xs bg-zinc-50 p-3 rounded border border-zinc-200 overflow-x-auto"
              ><%= Jason.encode!(@selected_job.meta, pretty: true) %></pre>
            </div>
            <div :if={@selected_job.errors != [] && @selected_job.errors != nil}>
              <h3 class="text-sm font-semibold text-zinc-700 mb-2">Errors</h3>
              <div class="space-y-2">
                <%= for error <- @selected_job.errors do %>
                  <div class="bg-red-50 p-3 rounded border border-red-200">
                    <p class="text-xs text-red-900 font-mono">
                      {Map.get(error, :error) || Map.get(error, "error")}
                    </p>
                    <p class="text-xs text-red-600 mt-1">
                      Attempt {Map.get(error, :attempt) ||
                        Map.get(error, "attempt")}
                      <%= if at = Map.get(error, :at) || Map.get(error, "at") do %>
                        at {if is_struct(at),
                          do: DateTime.to_iso8601(at),
                          else: to_string(at)}
                      <% end %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span class="font-semibold text-zinc-700">Queue:</span>
                <span class="text-zinc-900">{@selected_job.queue}</span>
              </div>
              <div>
                <span class="font-semibold text-zinc-700">Priority:</span>
                <span class="text-zinc-900">{@selected_job.priority}</span>
              </div>
              <div>
                <span class="font-semibold text-zinc-700">Attempts:</span>
                <span class="text-zinc-900">
                  {@selected_job.attempt}/{@selected_job.max_attempts}
                </span>
              </div>
              <div>
                <span class="font-semibold text-zinc-700">State:</span>
                <span class={[
                  "inline-flex items-center gap-1.5 px-2 text-xs leading-5 font-semibold rounded-full",
                  get_job_state_color(@selected_job.state),
                  @selected_job.state == "executing" && "animate-pulse"
                ]}>
                  <%= if @selected_job.state == "executing" do %>
                    <span
                      class="inline-block w-3 h-3 border-2 border-orange-600 border-t-transparent rounded-full animate-spin"
                      aria-hidden="true"
                    ></span>
                  <% end %>
                  {@selected_job.state}
                </span>
              </div>
            </div>
          </div>
        </.modal>
      </div>
    </.side_menu>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Settings")
      |> assign(:active_page, :admin_settings)
      |> assign(:loading_settings?, true)
      |> assign(:google_photos_status, nil)
      |> assign(:google_photos_scopes_preview, nil)
      |> assign(:grouped_settings, %{})
      |> assign(:scopes, [])
      |> assign(:recent_jobs, [])
      |> assign(:queue_stats, %{})
      |> assign(:oban_data_loaded, false)
      |> assign(:recent_outages, [])
      |> assign(:outages_loaded, false)
      |> assign(:selected_job, nil)
      |> assign(:show_job_modal, false)
      |> assign(:form, nil)
      |> then(fn s ->
        if connected?(s) do
          Oban.Notifier.listen([:insert, :gossip])

          s
          |> start_async(:load_settings_data, fn ->
            all_settings = Settings.settings_grouped_by_scope()
            scopes = Settings.setting_scopes()
            google_photos_status = GooglePhotos.connection_status()

            %{
              grouped_settings: all_settings,
              scopes: scopes,
              form: to_form(all_settings, as: "settings"),
              google_photos_status: google_photos_status
            }
          end)
          |> start_async(:load_oban_data, fn ->
            %{
              recent_jobs: list_recent_jobs(limit: 50),
              queue_stats: get_queue_stats()
            }
          end)
          |> start_async(:load_outages, fn -> OutageQueries.recent(20) end)
        else
          s
        end
      end)

    # Only recent_jobs is temporary — it is re-assigned on Oban notifications. Settings
    # form assigns must persist across re-renders (e.g. queue stats updates) or inputs
    # disappear from the DOM after the first connected render.
    {:ok, socket, temporary_assigns: [recent_jobs: []]}
  end

  @impl true
  def handle_async(:load_settings_data, {:ok, data}, socket) do
    google_photos_status = data.google_photos_status

    {:noreply,
     socket
     |> assign(:loading_settings?, false)
     |> assign(:grouped_settings, data.grouped_settings)
     |> assign(:scopes, data.scopes)
     |> assign(:form, data.form)
     |> assign(:google_photos_status, google_photos_status)
     |> assign(
       :google_photos_scopes_preview,
       scopes_preview(google_photos_status.scopes)
     )}
  end

  def handle_async(:load_settings_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load admin settings async", error: reason)

    {:noreply,
     socket
     |> assign(:loading_settings?, false)
     |> assign(:google_photos_status, %{
       oauth_configured: false,
       connected: false
     })
     |> YscWeb.Flash.put_toast(:error, "Failed to load settings",
       title: "Settings"
     )}
  end

  @impl true
  def handle_async(
        :load_oban_data,
        {:ok, %{recent_jobs: recent_jobs, queue_stats: queue_stats}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:queue_stats, queue_stats)
     |> assign(:oban_data_loaded, true)}
  end

  def handle_async(:load_oban_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load Oban data async", error: reason)

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:error, "Failed to load job statistics",
       title: "Settings"
     )
     |> assign(:oban_data_loaded, true)}
  end

  @impl true
  def handle_async(:load_outages, {:ok, outages}, socket) do
    {:noreply,
     socket
     |> assign(:recent_outages, outages)
     |> assign(:outages_loaded, true)}
  end

  def handle_async(:load_outages, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load outages async", error: reason)

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:error, "Failed to load reported outages",
       title: "Settings"
     )
     |> assign(:outages_loaded, true)}
  end

  @impl true
  def handle_event("google-photos-test-connection", _params, socket) do
    case GooglePhotos.test_connection() do
      {:ok, %{email: email}} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Connection OK (#{email}).",
           title: "Google Photos"
         )}

      {:error, :not_connected} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Not connected. Use Connect Google Photos first.",
           title: "Google Photos"
         )}

      {:error, :not_configured} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Google Photos OAuth is not configured.",
           title: "Google Photos"
         )}

      {:error, :token_refresh_failed} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Token refresh failed. Try disconnecting and connecting again.",
           title: "Google Photos"
         )}

      {:error, :insufficient_scopes} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Google rejected the Photos API call (outdated scopes). Disconnect, then connect again to re-authorize.",
           title: "Google Photos"
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Connection test failed. Check logs for details.",
           title: "Google Photos"
         )}
    end
  end

  def handle_event("update-settings", %{"settings" => settings}, socket) do
    for {k, v} <- settings do
      case Settings.update_setting(k, Map.get(v, "value")) do
        {:ok, _} -> :ok
        {:error, :not_found} -> :skip
        {:error, _} -> :ok
      end
    end

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:info, "Settings updated.", title: "Settings")
     |> redirect(to: ~p"/admin/settings")}
  end

  def handle_event("reschedule_job", %{"job_id" => job_id}, socket) do
    case reschedule_job(job_id) do
      {:ok, _new_job} ->
        recent_jobs = list_recent_jobs(limit: 50)
        queue_stats = get_queue_stats()

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Job rescheduled.", title: "Job")
         |> assign(:recent_jobs, recent_jobs)
         |> assign(:queue_stats, queue_stats)}

      {:error, reason} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Failed to re-schedule job: #{inspect(reason)}"
         )}
    end
  end

  def handle_event("show_job_details", %{"job_id" => job_id_raw}, socket) do
    job_id = parse_job_id(job_id_raw)

    case Repo.get(Job, job_id) do
      nil ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Job not found", title: "Job")
         |> assign(:show_job_modal, false)
         |> assign(:selected_job, nil)}

      job ->
        {:noreply,
         socket
         |> assign(:selected_job, job)
         |> assign(:show_job_modal, true)}
    end
  end

  def handle_event("close_job_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_job_modal, false)
     |> assign(:selected_job, nil)}
  end

  @impl true
  def handle_info({:notification, :insert, _payload}, socket) do
    recent_jobs = list_recent_jobs(limit: 50)
    queue_stats = get_queue_stats()

    {:noreply,
     socket
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:queue_stats, queue_stats)
     |> assign(:oban_data_loaded, true)}
  end

  def handle_info({:notification, :gossip, _payload}, socket) do
    recent_jobs = list_recent_jobs(limit: 50)
    queue_stats = get_queue_stats()

    {:noreply,
     socket
     |> assign(:recent_jobs, recent_jobs)
     |> assign(:queue_stats, queue_stats)
     |> assign(:oban_data_loaded, true)}
  end

  defp list_recent_jobs(opts) do
    limit = Keyword.get(opts, :limit, 50)

    # Show jobs from all states, ordered by most recent first
    # Use completed_at for completed jobs, scheduled_at for scheduled jobs,
    # and inserted_at as fallback for other states
    from(j in Job,
      order_by: [
        desc:
          fragment(
            "COALESCE(?, ?, ?)",
            j.completed_at,
            j.scheduled_at,
            j.inserted_at
          )
      ],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp get_queue_stats do
    from(j in Job,
      group_by: [j.queue, j.state],
      select: {j.queue, j.state, count(j.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_queue, state, count} ->
      {state, count}
    end)
    |> Enum.map(fn {queue, state_counts} ->
      stats =
        Enum.into(state_counts, %{}, fn {state, count} -> {state, count} end)

      {queue, stats}
    end)
    |> Enum.into(%{})
  end

  defp parse_job_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> id
    end
  end

  defp parse_job_id(id) when is_integer(id), do: id

  defp format_duration(ms) when is_number(ms) and ms < 1000,
    do: "#{round(ms)}ms"

  defp format_duration(ms) when is_number(ms) and ms < 60_000,
    do: "#{Float.round(ms / 1000, 2)}s"

  defp format_duration(ms) when is_number(ms) and ms < 3_600_000,
    do: "#{Float.round(ms / 60_000, 2)}m"

  @dialyzer {:nowarn_function, format_duration: 1}
  defp format_duration(ms) when is_number(ms),
    do: "#{Float.round(ms / 3_600_000, 2)}h"

  defp reschedule_job(job_id) do
    case Repo.get(Job, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        # Get the worker module from the job.worker string
        worker_module =
          job.worker
          |> String.split(".")
          |> Module.concat()

        # Check if the module exists and has the new/1 function
        if Code.ensure_loaded?(worker_module) and
             function_exported?(worker_module, :new, 1) do
          # Create a new job with the same args
          try do
            new_job = apply(worker_module, :new, [job.args])

            case Oban.insert(new_job) do
              {:ok, inserted_job} ->
                {:ok, inserted_job}

              {:error, changeset} ->
                {:error, changeset}
            end
          rescue
            error ->
              {:error, Exception.message(error)}
          end
        else
          {:error,
           "Worker module #{job.worker} not found or does not export new/1"}
        end
    end
  end

  defp get_job_state_color(state) do
    case state do
      "completed" -> "bg-green-100 text-green-800"
      "discarded" -> "bg-red-100 text-red-800"
      "retryable" -> "bg-yellow-100 text-yellow-800"
      "available" -> "bg-blue-100 text-blue-800"
      "scheduled" -> "bg-purple-100 text-purple-800"
      "executing" -> "bg-orange-100 text-orange-800"
      _ -> "bg-zinc-100 text-zinc-800"
    end
  end

  defp get_outage_type_color(:power_outage), do: "yellow"
  defp get_outage_type_color(:water_outage), do: "sky"
  defp get_outage_type_color(:internet_outage), do: "violet"
  defp get_outage_type_color(_), do: "zinc"

  defp google_photos_scopes_stale?(scopes),
    do: not Ysc.GooglePhotos.OAuth.scopes_grant_complete?(scopes)

  defp scopes_preview(nil), do: nil

  defp scopes_preview(scopes) when is_binary(scopes) do
    if String.length(scopes) > 120 do
      String.slice(scopes, 0, 117) <> "..."
    else
      scopes
    end
  end
end
