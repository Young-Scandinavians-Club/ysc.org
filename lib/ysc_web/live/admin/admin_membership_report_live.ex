defmodule YscWeb.AdminMembershipReportLive do
  @moduledoc """
  Admin LiveView for generating membership activity reports over a date range.

  Reports include applications submitted, accepted, rejected, pending,
  memberships expired, and memberships purchased. Each member appears in only
  one list (their highest state). Supports CSV download and emailing the
  summary to the board.
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  alias Ysc.Accounts.{MembershipReport, SignupApplication}

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    default_from = %Date{today | day: 1}

    {:ok,
     socket
     |> assign(:active_page, :memberships)
     |> assign(:page_title, "Membership Report")
     |> assign(:date_from, default_from)
     |> assign(:date_to, today)
     |> assign(:report, nil)
     |> assign(:generating?, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case parse_date_params(params) do
      {:ok, date_from, date_to} ->
        socket =
          socket
          |> assign(:date_from, date_from)
          |> assign(:date_to, date_to)
          |> assign(:generating?, true)
          |> assign(:report, nil)
          |> assign(:error, nil)

        if connected?(socket) do
          {:noreply,
           start_async(socket, :generate_report, fn ->
             MembershipReport.generate(date_from, date_to)
           end)}
        else
          {:noreply, socket}
        end

      :no_params ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Invalid date range. Please enter valid from/to dates."
         )}
    end
  end

  @impl true
  def handle_async(:generate_report, {:ok, report}, socket) do
    {:noreply,
     socket
     |> assign(:report, report)
     |> assign(:generating?, false)}
  end

  @impl true
  def handle_async(:generate_report, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating?, false)
     |> assign(:error, "Failed to generate report. Please try again.")}
  end

  @impl true
  def handle_event(
        "generate",
        %{"date_from" => from_str, "date_to" => to_str},
        socket
      ) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/memberships/report?from=#{from_str}&to=#{to_str}"
     )}
  end

  @impl true
  def handle_event("download_csv", _params, socket) do
    case socket.assigns.report do
      nil ->
        {:noreply, socket}

      report ->
        csv_content = MembershipReport.to_csv(report)
        encoded = Base.encode64(csv_content)

        filename =
          "membership-report-#{Date.to_iso8601(report.date_from)}-to-#{Date.to_iso8601(report.date_to)}.csv"

        {:noreply,
         push_event(socket, "download-csv", %{
           content: encoded,
           filename: filename
         })}
    end
  end

  @impl true
  def handle_event("email_report", _params, socket) do
    case socket.assigns.report do
      nil ->
        {:noreply, socket}

      report ->
        current_user = socket.assigns.current_user

        report_path =
          ~p"/admin/memberships/report?from=#{Date.to_iso8601(report.date_from)}&to=#{Date.to_iso8601(report.date_to)}"

        report_url = YscWeb.Endpoint.url() <> report_path

        Task.start(fn ->
          YscWeb.Emails.Notifier.send_email_to_board(
            "membership_report_#{report.date_from}_#{report.date_to}",
            "Membership Report: #{Date.to_iso8601(report.date_from)} to #{Date.to_iso8601(report.date_to)}",
            YscWeb.Emails.AdminMembershipReport,
            %{
              date_from: Date.to_iso8601(report.date_from),
              date_to: Date.to_iso8601(report.date_to),
              count_applied: report.counts.applied,
              count_accepted: report.counts.accepted,
              count_rejected: report.counts.rejected,
              count_pending: report.counts.pending,
              count_expired: report.counts.expired,
              count_purchased: report.counts.purchased,
              generated_by:
                "#{current_user.first_name} #{current_user.last_name}",
              report_url: report_url
            }
          )
        end)

        {:noreply, put_flash(socket, :info, "Report emailed to the board.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu active_page={@active_page} user={@current_user} role={@admin_role}>
      <div class="bg-zinc-50/80 min-h-screen -mx-4 lg:-mx-10 px-4 lg:px-10 py-8">
        <%!-- Page header --%>
        <div class="flex flex-col md:flex-row md:items-start justify-between gap-4 py-8 border-b border-zinc-100 mb-8">
          <div>
            <div class="mb-2">
              <.link
                navigate={~p"/admin/memberships"}
                class="text-sm text-zinc-500 hover:text-zinc-700 inline-flex items-center gap-1"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" /> Memberships
              </.link>
            </div>
            <h1 class="text-3xl font-black text-zinc-900 tracking-tight">
              Membership Report
            </h1>
            <p class="text-sm text-zinc-500 mt-1">
              Generate a summary of membership activity over a date range.
            </p>
          </div>
          <div :if={@report} class="flex gap-2 shrink-0 mt-2 md:mt-0">
            <.button
              phx-click="email_report"
              phx-disable-with="Sending..."
              variant="outline"
              color="zinc"
            >
              <.icon name="hero-envelope" class="w-4 h-4" /> Email to board
            </.button>
            <.button phx-click="download_csv" variant="outline" color="zinc">
              <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download CSV
            </.button>
          </div>
        </div>

        <%!-- Date range form --%>
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 px-6 py-5 mb-8">
          <form id="membership-report-form" phx-submit="generate" class="flex flex-wrap items-end gap-4">
            <div>
              <label
                for="date_from"
                class="block text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1"
              >
                From
              </label>
              <input
                type="date"
                id="date_from"
                name="date_from"
                value={Date.to_iso8601(@date_from)}
                required
                class="block rounded-md border-zinc-300 shadow-sm text-sm focus:border-blue-500 focus:ring-blue-500"
              />
            </div>
            <div>
              <label
                for="date_to"
                class="block text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1"
              >
                To
              </label>
              <input
                type="date"
                id="date_to"
                name="date_to"
                value={Date.to_iso8601(@date_to)}
                required
                class="block rounded-md border-zinc-300 shadow-sm text-sm focus:border-blue-500 focus:ring-blue-500"
              />
            </div>
            <.button type="submit" phx-disable-with="Generating…">
              Generate report
            </.button>
          </form>
        </div>

        <%!-- Error state --%>
        <div
          :if={@error}
          class="bg-red-50 border border-red-200 rounded-lg px-6 py-4 mb-6 text-sm text-red-700"
        >
          {@error}
        </div>

        <%!-- Loading state --%>
        <div
          :if={@generating?}
          class="bg-white rounded-lg shadow-sm border border-zinc-200 overflow-hidden mb-8"
        >
          <.admin_table_skeleton rows={6} columns={3} />
        </div>

        <%!-- Report content --%>
        <div :if={@report} class="space-y-8">
          <%!-- Summary stats --%>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            <.admin_stat_card
              id="report-stat-applied"
              label="Applied"
              value={@report.counts.applied}
              subtitle="Submitted in period"
            />
            <.admin_stat_card
              id="report-stat-accepted"
              label="Accepted"
              value={@report.counts.accepted}
              subtitle="Approved in period"
            />
            <.admin_stat_card
              id="report-stat-rejected"
              label="Rejected"
              value={@report.counts.rejected}
              subtitle="Rejected in period"
            />
            <.admin_stat_card
              id="report-stat-pending"
              label="Pending"
              value={@report.counts.pending}
              subtitle="Awaiting review"
            />
            <.admin_stat_card
              id="report-stat-expired"
              label="Expired"
              value={@report.counts.expired}
              subtitle="Memberships lapsed"
            />
            <.admin_stat_card
              id="report-stat-purchased"
              label="Purchased"
              value={@report.counts.purchased}
              subtitle="New memberships"
            />
          </div>

          <%!-- Pending Applications --%>
          <.report_section
            id="report-pending"
            title="Pending Applications"
            count={length(@report.pending)}
            empty_msg="No pending applications in this period."
          >
            <:card :for={app <- @report.pending}>
              <.application_card
                user={app.user}
                application={app}
                date={app.completed}
                badge_type={:yellow}
                badge_label="Pending"
                link={~p"/admin/users/#{app.user_id}/details/application"}
                link_label="View full application"
              />
            </:card>
          </.report_section>

          <%!-- Accepted --%>
          <.report_section
            id="report-accepted"
            title="Accepted"
            count={length(@report.accepted)}
            empty_msg="No applications were accepted in this period."
          >
            <:card :for={app <- @report.accepted}>
              <.application_card
                user={app.user}
                application={app}
                date={app.reviewed_at}
                badge_type={:green}
                badge_label="Accepted"
                link={~p"/admin/users/#{app.user_id}/details/application"}
                link_label="View full application"
              />
            </:card>
          </.report_section>

          <%!-- Rejected --%>
          <.report_section
            id="report-rejected"
            title="Rejected"
            count={length(@report.rejected)}
            empty_msg="No applications were rejected in this period."
          >
            <:card :for={app <- @report.rejected}>
              <.application_card
                user={app.user}
                application={app}
                date={app.reviewed_at}
                badge_type={:red}
                badge_label="Rejected"
                link={~p"/admin/users/#{app.user_id}/details/application"}
                link_label="View full application"
              />
            </:card>
          </.report_section>

          <%!-- Purchased --%>
          <.report_section
            id="report-purchased"
            title="Memberships Purchased"
            count={length(@report.purchased)}
            empty_msg="No memberships were purchased in this period."
          >
            <:card :for={sub <- @report.purchased}>
              <.application_card
                user={sub.user}
                application={sub.signup_application}
                date={sub.start_date}
                badge_type={:sky}
                badge_label="Purchased"
                link={~p"/admin/users/#{sub.user_id}/details/membership"}
                link_label="View membership"
              />
            </:card>
          </.report_section>

          <%!-- Expired (compact rows only) --%>
          <.report_section
            id="report-expired"
            title="Memberships Expired"
            count={length(@report.expired)}
            empty_msg="No memberships expired in this period."
          >
            <:card :for={sub <- @report.expired}>
              <.compact_row
                user={sub.user}
                date={sub.current_period_end}
                date_label="Expired on"
                link={~p"/admin/users/#{sub.user_id}/details/membership"}
              />
            </:card>
          </.report_section>
        </div>
      </div>
    </.side_menu>
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :empty_msg, :string, required: true
  slot :card

  defp report_section(assigns) do
    ~H"""
    <div
      id={@id}
      class="bg-white rounded-lg shadow-sm border border-zinc-200 overflow-hidden"
    >
      <div class="px-6 py-4 border-b border-zinc-100">
        <h2 class="text-lg font-bold text-zinc-900">
          {@title}
          <span class="ml-2 text-sm font-normal text-zinc-400">({@count})</span>
        </h2>
      </div>
      <div :if={@count == 0} class="py-12 text-center text-zinc-400 text-sm">
        {@empty_msg}
      </div>
      <div :if={@count > 0} class="divide-y divide-zinc-100">
        {render_slot(@card)}
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :application, :any, default: nil
  attr :date, :any, required: true
  attr :badge_type, :atom, required: true
  attr :badge_label, :string, required: true
  attr :link, :string, required: true
  attr :link_label, :string, required: true

  defp application_card(assigns) do
    ~H"""
    <div class="px-6 py-5">
      <%!-- Header --%>
      <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-2 mb-4">
        <div>
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-base font-semibold text-zinc-900">
              {@user.first_name} {@user.last_name}
            </span>
            <.badge type={@badge_type}>{@badge_label}</.badge>
          </div>
          <a
            href={"mailto:#{@user.email}"}
            class="text-sm text-blue-600 hover:underline"
          >
            {@user.email}
          </a>
        </div>
        <div class="text-sm text-zinc-400 shrink-0">
          {format_datetime(@date)}
        </div>
      </div>

      <%!-- Application details --%>
      <%= if @application do %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-3 text-sm">
          <div :if={@application.membership_type}>
            <span class="font-medium text-zinc-500">Membership type:</span>
            <span class="ml-1 text-zinc-800 capitalize">{@application.membership_type}</span>
          </div>
          <div :if={@application.membership_eligibility not in [nil, []]}>
            <span class="font-medium text-zinc-500">Eligibility:</span>
            <span class="ml-1 text-zinc-800">
              {format_eligibility(@application.membership_eligibility)}
            </span>
          </div>
          <div :if={@application.occupation}>
            <span class="font-medium text-zinc-500">Occupation:</span>
            <span class="ml-1 text-zinc-800">{@application.occupation}</span>
          </div>
          <div :if={@application.city || @application.country}>
            <span class="font-medium text-zinc-500">Location:</span>
            <span class="ml-1 text-zinc-800">
              {Enum.reject([@application.city, @application.country], &is_nil/1)
              |> Enum.join(", ")}
            </span>
          </div>
          <div :if={@application.link_to_scandinavia} class="sm:col-span-2">
            <span class="font-medium text-zinc-500">Link to Scandinavia:</span>
            <span class="ml-1 text-zinc-800">{@application.link_to_scandinavia}</span>
          </div>
          <div :if={@application.hear_about_the_club} class="sm:col-span-2">
            <span class="font-medium text-zinc-500">How they heard about us:</span>
            <span class="ml-1 text-zinc-800">{@application.hear_about_the_club}</span>
          </div>
        </div>
      <% else %>
        <p class="text-sm text-zinc-400 italic">No application on file.</p>
      <% end %>

      <div class="mt-3">
        <.link navigate={@link} class="text-xs text-blue-600 hover:underline">
          {@link_label} →
        </.link>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :date, :any, required: true
  attr :date_label, :string, required: true
  attr :link, :string, required: true

  defp compact_row(assigns) do
    ~H"""
    <div class="px-6 py-3 flex items-center justify-between gap-4">
      <div>
        <span class="text-sm font-semibold text-zinc-900">
          {@user.first_name} {@user.last_name}
        </span>
        <span class="text-sm text-zinc-500 ml-2">{@user.email}</span>
      </div>
      <div class="flex items-center gap-4 shrink-0">
        <span class="text-xs text-zinc-400">
          {@date_label} {format_datetime(@date)}
        </span>
        <.link navigate={@link} class="text-xs text-blue-600 hover:underline">
          View →
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_date_params(%{"from" => from_str, "to" => to_str})
       when is_binary(from_str) and from_str != "" and is_binary(to_str) and
              to_str != "" do
    with {:ok, date_from} <- Date.from_iso8601(from_str),
         {:ok, date_to} <- Date.from_iso8601(to_str),
         true <- Date.compare(date_from, date_to) in [:lt, :eq] do
      {:ok, date_from, date_to}
    else
      _ -> {:error, :invalid}
    end
  end

  defp parse_date_params(_), do: :no_params

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    local = DateTime.shift_zone!(dt, "America/Los_Angeles")
    Timex.format!(local, "%b %d, %Y", :strftime)
  end

  defp format_eligibility(eligibility) do
    lookup = SignupApplication.eligibility_lookup()

    Enum.map_join(eligibility, ", ", &Map.get(lookup, &1, to_string(&1)))
  end
end
