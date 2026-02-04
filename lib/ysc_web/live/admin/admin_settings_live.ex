defmodule YscWeb.AdminSettingsLive do
  alias Ysc.Settings
  alias Ysc.Repo
  alias Oban.Job

  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  import Ecto.Query

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
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Settings
        </h1>
      </div>

      <div class="w-full">
        <div id="admin-settings" class="max-w-screen-md">
          <.form for={@form} id="admin-settings-form" phx-submit="update-settings">
            <div :for={scope <- @scopes}>
              <h2 class="text-lg leading-8 font-semibold text-zinc-800">
                <%= String.capitalize(scope) %>
              </h2>
              <div>
                <ul>
                  <li :for={entry <- Map.get(@grouped_settings, scope)} class="py-2">
                    <label
                      class="leading-6 text-zinc-800 font-semibold"
                      for={entry.id}
                    >
                      <%= entry.name
                      |> String.replace("_", " ")
                      |> String.capitalize() %>:
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
        <!-- Recent Oban Jobs -->
        <div class="w-full py-4">
          <h2 class="text-lg leading-8 font-semibold text-zinc-800 mb-4">
            Recent Oban Jobs
          </h2>
          <div class="bg-white shadow rounded-lg overflow-hidden">
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
                    Attempts
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={job <- @recent_jobs}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                    <%= String.slice(to_string(job.id), 0..20) %>...
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <span class="font-medium"><%= job.worker %></span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <%= job.queue %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_job_state_color(job.state)}"}>
                      <%= job.state %>
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
                        <%= Calendar.strftime(
                          job.completed_at,
                          "%Y-%m-%d %H:%M:%S UTC"
                        ) %>
                      </span>
                    <% else %>
                      <%= if job.scheduled_at do %>
                        <span
                          id={"job-time-#{job.id}-scheduled"}
                          phx-hook="LocalTime"
                          data-utc-time={DateTime.to_iso8601(job.scheduled_at)}
                          data-prefix="Scheduled: "
                        >
                          Scheduled: <%= Calendar.strftime(
                            job.scheduled_at,
                            "%Y-%m-%d %H:%M:%S UTC"
                          ) %>
                        </span>
                      <% else %>
                        <%= if job.inserted_at do %>
                          <span
                            id={"job-time-#{job.id}-inserted"}
                            phx-hook="LocalTime"
                            data-utc-time={DateTime.to_iso8601(job.inserted_at)}
                            data-prefix=""
                          >
                            <%= Calendar.strftime(
                              job.inserted_at,
                              "%Y-%m-%d %H:%M:%S UTC"
                            ) %>
                          </span>
                        <% else %>
                          N/A
                        <% end %>
                      <% end %>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <%= job.attempt %>/<%= job.max_attempts %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <.button
                      phx-click="reschedule_job"
                      phx-value-job_id={job.id}
                      class="bg-green-600 hover:bg-green-700"
                    >
                      Re-schedule
                    </.button>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@recent_jobs)}>
                  <td
                    colspan="7"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No jobs found.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(_params, _session, socket) do
    scopes = Settings.setting_scopes()
    all_settings = Settings.settings_grouped_by_scope()

    form = to_form(all_settings, as: "settings")
    recent_jobs = list_recent_jobs(limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Admin Settings")
     |> assign(:active_page, :admin_settings)
     |> assign(:grouped_settings, all_settings)
     |> assign(:scopes, scopes)
     |> assign(:recent_jobs, recent_jobs)
     |> assign(form: form),
     temporary_assigns: [
       scopes: [],
       grouped_settings: %{},
       form: nil,
       recent_jobs: []
     ]}
  end

  def handle_event("update-settings", %{"settings" => settings}, socket) do
    for {k, v} <- settings do
      Settings.update_setting(k, Map.get(v, "value"))
    end

    {:noreply,
     socket
     |> put_flash(:info, "Settings Updated")
     |> redirect(to: ~p"/admin/settings")}
  end

  def handle_event("reschedule_job", %{"job_id" => job_id}, socket) do
    case reschedule_job(job_id) do
      {:ok, _new_job} ->
        recent_jobs = list_recent_jobs(limit: 50)

        {:noreply,
         socket
         |> put_flash(:info, "Job re-scheduled successfully")
         |> assign(:recent_jobs, recent_jobs)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to re-schedule job: #{inspect(reason)}")}
    end
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
end
