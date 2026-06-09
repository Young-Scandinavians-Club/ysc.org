defmodule YscWeb.AdminScannerLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  require Ysc.Logging

  alias Ysc.Events
  alias Ysc.Scanning
  alias Ysc.Scanning.QrToken

  # --- Render ---

  @impl true
  def render(%{live_action: :sessions} = assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-semibold text-zinc-800">Check-in Sessions</h1>
          <.link
            navigate={~p"/admin/scanner"}
            class="inline-flex items-center rounded py-2 px-3 text-sm font-semibold leading-6 bg-blue-700 hover:bg-blue-800 text-zinc-100 active:scale-[0.98] transition duration-150 ease-in-out"
          >
            <.icon name="hero-qr-code" class="w-4 h-4 -mt-0.5 me-1" />
            New Check-in Session
          </.link>
        </div>

        <.admin_icon_empty_state
          :if={@sessions == []}
          icon="hero-qr-code"
          title="No scan sessions yet"
          description="Start a new scan session to begin."
        />

        <div :if={@sessions != []} class="space-y-3">
          <div
            :for={session <- @sessions}
            class="bg-white border border-zinc-200 rounded-lg p-4 hover:shadow-sm transition-shadow"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  session_type_badge_class(session.type)
                ]}>
                  {session_type_label(session.type)}
                </span>
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  if(is_nil(session.closed_at),
                    do: "bg-green-100 text-green-800",
                    else: "bg-zinc-100 text-zinc-500"
                  )
                ]}>
                  {if is_nil(session.closed_at), do: "Active", else: "Closed"}
                </span>
                <h3 class="font-medium text-zinc-900">{session.name}</h3>
              </div>
              <div class="flex items-center gap-3">
                <.link
                  :if={
                    is_nil(session.closed_at) && session.type != :event_membership
                  }
                  navigate={~p"/admin/scanner?resume=#{session.id}"}
                  class="text-sm text-emerald-600 hover:text-emerald-800 font-medium"
                >
                  <.icon name="hero-play" class="w-3.5 h-3.5 inline -mt-0.5" />
                  Resume
                </.link>
                <.link
                  :if={
                    is_nil(session.closed_at) && session.type == :event_membership
                  }
                  navigate={~p"/admin/membership-check-in/#{session.id}"}
                  class="text-sm text-violet-600 hover:text-violet-800 font-medium"
                >
                  <.icon name="hero-play" class="w-3.5 h-3.5 inline -mt-0.5" />
                  Open Desk
                </.link>
                <.link
                  :if={session.type != :event_membership}
                  navigate={~p"/admin/scanner/sessions/#{session.id}"}
                  class="text-sm text-blue-600 hover:text-blue-800 font-medium"
                >
                  View
                </.link>
                <.link
                  :if={
                    session.type == :event_membership &&
                      not is_nil(session.closed_at) &&
                      session.created_by_id == @current_user.id
                  }
                  navigate={~p"/admin/membership-check-in/#{session.id}"}
                  class="text-sm text-violet-600 hover:text-violet-800 font-medium"
                >
                  View Desk
                </.link>
              </div>
            </div>
            <div class="mt-2 flex items-center gap-4 text-sm text-zinc-500">
              <span :if={session.event}>
                <.icon name="hero-calendar" class="w-4 h-4 inline -mt-0.5" />
                {session.event.title}
              </span>
              <span>
                <.icon name="hero-user" class="w-4 h-4 inline -mt-0.5" />
                {session.created_by.first_name} {session.created_by.last_name}
              </span>
              <span>
                <.icon name="hero-clock" class="w-4 h-4 inline -mt-0.5" />
                <span
                  id={"session-list-time-#{session.id}"}
                  phx-hook="LocalTime"
                  data-utc-time={DateTime.to_iso8601(session.inserted_at)}
                >
                  {Calendar.strftime(session.inserted_at, "%b %d, %Y %H:%M UTC")}
                </span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def render(%{live_action: :session_detail} = assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="py-6">
        <div class="flex items-start gap-2 mb-6">
          <.link
            navigate={~p"/admin/scanner/sessions"}
            class="text-zinc-500 hover:text-zinc-700 mt-1 shrink-0"
          >
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>
          <div class="flex flex-wrap items-center gap-2 min-w-0">
            <h1 class="text-2xl font-semibold text-zinc-800 leading-tight">
              {@detail_session.name}
            </h1>
            <span class={[
              "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium shrink-0",
              session_type_badge_class(@detail_session.type)
            ]}>
              {session_type_label(@detail_session.type)}
            </span>
          </div>
        </div>

        <%!-- Session meta + export — stacks on mobile, row on desktop --%>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-6">
          <div class="text-sm text-zinc-500 leading-relaxed">
            <span :if={@detail_session.event}>
              Event:
              <span class="font-medium text-zinc-700">
                {@detail_session.event.title}
              </span>
              &middot;
            </span>
            Created by
            <span class="font-medium text-zinc-700">
              {@detail_session.created_by.first_name} {@detail_session.created_by.last_name}
            </span>
            on
            <span
              id="detail-session-time"
              phx-hook="LocalTime"
              data-utc-time={DateTime.to_iso8601(@detail_session.inserted_at)}
              class="whitespace-nowrap"
            >
              {Calendar.strftime(
                @detail_session.inserted_at,
                "%b %d, %Y at %H:%M UTC"
              )}
            </span>
          </div>
          <.button
            phx-click="export-csv"
            phx-value-session-id={@detail_session.id}
            variant="outline"
            color="blue"
            class="shrink-0"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4 -mt-0.5 me-1" />
            Export CSV
          </.button>
        </div>

        <div :if={@detail_records == []} class="text-center py-12 text-zinc-500">
          <p>No scan records in this session.</p>
        </div>

        <div :if={@detail_records != []}>
          <%!-- Mobile: card list (hidden on sm+) --%>
          <div class="flex flex-col divide-y divide-zinc-200 sm:hidden">
            <div :for={record <- @detail_records} class="py-4 flex flex-col gap-1.5">
              <%!-- Row 1: name + result badge --%>
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-semibold text-zinc-900 truncate">
                  {if record.user,
                    do: "#{record.user.first_name} #{record.user.last_name}",
                    else: "—"}
                </p>
                <span class={[
                  "shrink-0 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                  result_badge_class(record.result)
                ]}>
                  {to_string(record.result)}
                </span>
              </div>
              <%!-- Row 2: email --%>
              <p class="text-xs text-zinc-500 truncate">
                {if record.user, do: record.user.email, else: "—"}
              </p>
              <%!-- Row 3: time + optional status/type badges --%>
              <div class="flex items-center flex-wrap gap-2">
                <span class="text-xs text-zinc-400">
                  <span
                    id={"record-time-#{record.id}"}
                    phx-hook="LocalTime"
                    data-utc-time={DateTime.to_iso8601(record.inserted_at)}
                  >
                    {Calendar.strftime(record.inserted_at, "%H:%M:%S UTC")}
                  </span>
                </span>
                <span
                  :if={@detail_session.type == :membership}
                  class={[
                    "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                    if(record.membership_status == "active",
                      do: "bg-emerald-100 text-emerald-800",
                      else: "bg-red-100 text-red-800"
                    )
                  ]}
                >
                  {record.membership_status || "—"}
                </span>
                <span
                  :if={
                    @detail_session.type == :membership && record.membership_type
                  }
                  class="text-xs text-zinc-500"
                >
                  {record.membership_type}
                </span>
                <span
                  :if={@detail_session.type == :event && record.checkin_type}
                  class="text-xs text-zinc-500"
                >
                  {to_string(record.checkin_type)}
                </span>
              </div>
            </div>
          </div>

          <%!-- Desktop: standard table (hidden below sm) --%>
          <div class="hidden sm:block overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase">
                    Email
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase">
                    Time
                  </th>
                  <th
                    :if={@detail_session.type == :membership}
                    class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase"
                  >
                    Status
                  </th>
                  <th
                    :if={@detail_session.type == :membership}
                    class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase"
                  >
                    Type
                  </th>
                  <th
                    :if={@detail_session.type == :event}
                    class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase"
                  >
                    Check-in
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase">
                    Result
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={record <- @detail_records} class="hover:bg-zinc-50">
                  <td class="px-4 py-3 text-sm text-zinc-900">
                    {if record.user,
                      do: "#{record.user.first_name} #{record.user.last_name}",
                      else: "—"}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-500">
                    {if record.user, do: record.user.email, else: "—"}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-500 whitespace-nowrap">
                    <span
                      id={"record-time-#{record.id}-desktop"}
                      phx-hook="LocalTime"
                      data-utc-time={DateTime.to_iso8601(record.inserted_at)}
                    >
                      {Calendar.strftime(record.inserted_at, "%H:%M:%S UTC")}
                    </span>
                  </td>
                  <td
                    :if={@detail_session.type == :membership}
                    class="px-4 py-3 text-sm"
                  >
                    <span class={[
                      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                      if(record.membership_status == "active",
                        do: "bg-emerald-100 text-emerald-800",
                        else: "bg-red-100 text-red-800"
                      )
                    ]}>
                      {record.membership_status || "—"}
                    </span>
                  </td>
                  <td
                    :if={@detail_session.type == :membership}
                    class="px-4 py-3 text-sm text-zinc-500"
                  >
                    {record.membership_type || "—"}
                  </td>
                  <td
                    :if={@detail_session.type == :event}
                    class="px-4 py-3 text-sm text-zinc-500"
                  >
                    {to_string(record.checkin_type || "—")}
                  </td>
                  <td class="px-4 py-3 text-sm">
                    <span class={[
                      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                      result_badge_class(record.result)
                    ]}>
                      {to_string(record.result)}
                    </span>
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

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-semibold text-zinc-800">Check-in &amp; Scan</h1>
          <.link
            navigate={~p"/admin/scanner/sessions"}
            class="inline-flex items-center rounded py-2 px-3 text-sm font-semibold leading-6 border border-zinc-200 hover:bg-zinc-50 text-zinc-700 bg-transparent transition duration-150 ease-in-out"
          >
            <.icon name="hero-clock" class="w-4 h-4 -mt-0.5 me-1" /> Past Sessions
          </.link>
        </div>

        <%!-- Session Setup --%>
        <div :if={@phase == :setup} class="max-w-lg mx-auto space-y-4">
          <%!-- Resume own open sessions --%>
          <div
            :if={@open_sessions != []}
            class="bg-white rounded-xl border border-green-200 p-4 shadow-sm"
          >
            <h2 class="text-sm font-semibold text-green-800 mb-3 flex items-center gap-1.5">
              <.icon name="hero-arrow-path" class="w-4 h-4" />
              Resume an Active Session
            </h2>
            <div class="space-y-2">
              <div
                :for={session <- @open_sessions}
                class="flex items-center justify-between bg-green-50 rounded-lg px-3 py-2.5"
              >
                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <span class={[
                      "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium shrink-0",
                      session_type_badge_class(session.type)
                    ]}>
                      {session_type_label(session.type)}
                    </span>
                    <span class="text-sm font-medium text-zinc-800 truncate">
                      {session.name}
                    </span>
                  </div>
                  <div class="text-xs text-zinc-500 mt-0.5">
                    <span :if={session.event}>
                      {session.event.title} &middot;
                    </span>
                    <span
                      id={"open-session-time-#{session.id}"}
                      phx-hook="LocalTime"
                      data-utc-time={DateTime.to_iso8601(session.inserted_at)}
                    >
                      {Calendar.strftime(session.inserted_at, "%b %d at %H:%M UTC")}
                    </span>
                  </div>
                </div>
                <%= if session.type == :event_membership do %>
                  <.link
                    navigate={~p"/admin/membership-check-in/#{session.id}"}
                    class="ml-3 shrink-0 inline-flex items-center rounded px-3 py-1.5 text-sm font-semibold bg-violet-600 hover:bg-violet-700 text-white transition-colors"
                  >
                    Open Desk
                  </.link>
                <% else %>
                  <.button
                    phx-click="resume_session"
                    phx-value-session-id={session.id}
                    color="green"
                    class="ml-3 shrink-0"
                  >
                    Resume
                  </.button>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Join open event_membership sessions from other admins --%>
          <div
            :if={@joinable_sessions != []}
            class="bg-white rounded-xl border border-violet-200 p-4 shadow-sm"
          >
            <h2 class="text-sm font-semibold text-violet-800 mb-3 flex items-center gap-1.5">
              <.icon name="hero-user-group" class="w-4 h-4" />
              Join a Membership Check-in Session
            </h2>
            <div class="space-y-2">
              <div
                :for={session <- @joinable_sessions}
                class="flex items-center justify-between bg-violet-50 rounded-lg px-3 py-2.5"
              >
                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium shrink-0 bg-violet-100 text-violet-800">
                      Event + Members
                    </span>
                    <span class="text-sm font-medium text-zinc-800 truncate">
                      {session.name}
                    </span>
                  </div>
                  <div class="text-xs text-zinc-500 mt-0.5">
                    <span :if={session.event}>
                      {session.event.title} &middot;
                    </span>
                    <span>
                      by {session.created_by.first_name} {session.created_by.last_name} &middot;
                    </span>
                    <span
                      id={"joinable-session-time-#{session.id}"}
                      phx-hook="LocalTime"
                      data-utc-time={DateTime.to_iso8601(session.inserted_at)}
                    >
                      {Calendar.strftime(session.inserted_at, "%b %d at %H:%M UTC")}
                    </span>
                  </div>
                </div>
                <.link
                  navigate={~p"/admin/membership-check-in/#{session.id}"}
                  class="ml-3 shrink-0 inline-flex items-center rounded px-3 py-1.5 text-sm font-semibold bg-violet-600 hover:bg-violet-700 text-white transition-colors"
                >
                  Join
                </.link>
              </div>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-zinc-200 p-6 shadow-sm">
            <h2 class="text-lg font-semibold text-zinc-800 mb-4">
              Start a Check-in Session
            </h2>

            <.form
              for={@setup_form}
              id="scan-setup-form"
              phx-submit="start_session"
              class="space-y-4"
            >
              <.input
                field={@setup_form[:name]}
                type="text"
                label="Session Name"
                placeholder="e.g. Annual Meeting 2026"
                required
              />

              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1">
                  Mode
                </label>
                <p class="text-sm text-zinc-500 mb-3">
                  Choose how attendees will be checked in at this session.
                </p>
                <div class="grid grid-cols-3 gap-3">
                  <button
                    type="button"
                    phx-click="select_mode"
                    phx-value-mode="membership"
                    class={[
                      "flex flex-col items-center p-4 rounded-lg border-2 transition-all",
                      if(@selected_mode == "membership",
                        do: "border-emerald-500 bg-emerald-50",
                        else: "border-zinc-200 hover:border-zinc-300"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-identification"
                      class={[
                        "w-8 h-8 mb-2",
                        if(@selected_mode == "membership",
                          do: "text-emerald-600",
                          else: "text-zinc-400"
                        )
                      ]}
                    />
                    <span class={[
                      "text-sm font-medium",
                      if(@selected_mode == "membership",
                        do: "text-emerald-700",
                        else: "text-zinc-600"
                      )
                    ]}>
                      Membership
                    </span>
                    <span class="text-xs text-zinc-400 mt-1 text-center">
                      Verify member status
                    </span>
                  </button>

                  <button
                    type="button"
                    phx-click="select_mode"
                    phx-value-mode="event"
                    class={[
                      "flex flex-col items-center p-4 rounded-lg border-2 transition-all",
                      if(@selected_mode == "event",
                        do: "border-blue-500 bg-blue-50",
                        else: "border-zinc-200 hover:border-zinc-300"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-ticket"
                      class={[
                        "w-8 h-8 mb-2",
                        if(@selected_mode == "event",
                          do: "text-blue-600",
                          else: "text-zinc-400"
                        )
                      ]}
                    />
                    <span class={[
                      "text-sm font-medium",
                      if(@selected_mode == "event",
                        do: "text-blue-700",
                        else: "text-zinc-600"
                      )
                    ]}>
                      Event
                    </span>
                    <span class="text-xs text-zinc-400 mt-1 text-center">
                      Check in ticket holders
                    </span>
                  </button>

                  <button
                    type="button"
                    phx-click="select_mode"
                    phx-value-mode="event_membership"
                    class={[
                      "flex flex-col items-center p-4 rounded-lg border-2 transition-all",
                      if(@selected_mode == "event_membership",
                        do: "border-violet-500 bg-violet-50",
                        else: "border-zinc-200 hover:border-zinc-300"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-calendar-days"
                      class={[
                        "w-8 h-8 mb-2",
                        if(@selected_mode == "event_membership",
                          do: "text-violet-600",
                          else: "text-zinc-400"
                        )
                      ]}
                    />
                    <span class={[
                      "text-sm font-medium",
                      if(@selected_mode == "event_membership",
                        do: "text-violet-700",
                        else: "text-zinc-600"
                      )
                    ]}>
                      Event + Members
                    </span>
                    <span class="text-xs text-zinc-400 mt-1 text-center">
                      Verify membership for event
                    </span>
                  </button>
                </div>

                <%!-- Mode description shown after selection --%>
                <%= cond do %>
                  <% @selected_mode == "membership" -> %>
                    <div class="mt-3 p-3 rounded-lg bg-emerald-50 border border-emerald-100 text-sm text-emerald-800 space-y-1">
                      <p class="font-medium">Membership-only check-in</p>
                      <p class="text-emerald-700">
                        Use this for standalone membership verification — e.g. a member meeting,
                        board session, or members-only gathering that is not tied to a ticketed event.
                        You scan or search for any member and the system confirms whether their
                        membership is currently active. No pre-sold tickets are required.
                        The session is not linked to a specific event and will appear under
                        general membership sessions.
                      </p>
                    </div>
                  <% @selected_mode == "event" -> %>
                    <div class="mt-3 p-3 rounded-lg bg-blue-50 border border-blue-100 text-sm text-blue-800 space-y-1">
                      <p class="font-medium">Event ticket check-in</p>
                      <p class="text-blue-700">
                        Use this for ticketed events where attendees have purchased a booking in
                        advance. The desk shows a live list of all ticket holders; you scan their
                        QR code or search by name to mark them as arrived. The session is linked
                        to the selected event and tracks each ticket redemption. Membership status
                        is not verified in this mode — only ticket ownership.
                      </p>
                    </div>
                  <% @selected_mode == "event_membership" -> %>
                    <div class="mt-3 p-3 rounded-lg bg-violet-50 border border-violet-100 text-sm text-violet-800 space-y-1">
                      <p class="font-medium">
                        Event attendance with membership verification
                      </p>
                      <p class="text-violet-700">
                        Use this when you want to track who shows up to an event and also confirm
                        they are active members — without relying on pre-sold tickets. Ideal for
                        events open only to members (e.g. a club night, holiday party, or AGM)
                        where guests simply arrive at the door. You search for the member by name
                        or email, the system checks their membership status, and logs them as
                        attended under the chosen event. Multiple admins can share the same session
                        and check in guests simultaneously from different devices.
                      </p>
                    </div>
                  <% true -> %>
                <% end %>
              </div>

              <div :if={@selected_mode in ["event", "event_membership"]}>
                <.input
                  field={@setup_form[:event_id]}
                  type="select"
                  label="Select Event"
                  options={@event_options}
                  prompt="Choose an event..."
                  required
                />
              </div>

              <.button
                type="submit"
                class="w-full"
                disabled={@selected_mode == nil}
                phx-disable-with="Starting..."
              >
                Start Session
              </.button>
            </.form>
          </div>
        </div>
        <%!-- end setup --%>

        <%!-- Scanning Phase — fullscreen overlay --%>
        <div
          :if={@phase == :scanning}
          class="fixed inset-0 z-50 bg-black flex flex-col overflow-hidden"
        >
          <%!-- Top gradient header --%>
          <div class={[
            "absolute top-0 inset-x-0 z-20 px-4 pt-4 pb-16",
            "bg-gradient-to-b",
            cond do
              @active_session.type == :membership ->
                "from-emerald-950/95 to-transparent"

              @active_session.type == :event_membership ->
                "from-violet-950/95 to-transparent"

              true ->
                "from-blue-950/95 to-transparent"
            end
          ]}>
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2.5 text-white min-w-0">
                <.icon
                  name={
                    cond do
                      @active_session.type == :membership ->
                        "hero-identification"

                      @active_session.type == :event_membership ->
                        "hero-calendar-days"

                      true ->
                        "hero-ticket"
                    end
                  }
                  class="w-5 h-5 shrink-0"
                />
                <div class="min-w-0">
                  <p class="font-semibold text-sm leading-tight truncate">
                    {@active_session.name}
                  </p>
                  <p
                    :if={
                      @active_session.type in [:event, :event_membership] &&
                        @active_session.event
                    }
                    class="text-xs text-white/55 truncate"
                  >
                    {@active_session.event.title}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-3 shrink-0 ml-3">
                <span class="text-white text-sm">
                  {@scan_count} {if(@scan_count == 1, do: "scan", else: "scans")}
                </span>
                <.link
                  :if={
                    @active_session.type == :event_membership ||
                      (@active_session.type == :event && @active_session.event)
                  }
                  navigate={desk_path(@active_session)}
                  class="bg-white/15 hover:bg-white/25 text-white text-xs font-semibold px-3 py-1.5 rounded-full transition-colors border border-white/20"
                >
                  Desk
                </.link>
                <button
                  phx-click="end_session"
                  class="bg-white/15 hover:bg-white/25 text-white text-xs font-semibold px-3 py-1.5 rounded-full transition-colors border border-white/20"
                >
                  Done
                </button>
              </div>
            </div>
          </div>

          <%!-- Camera container (fills entire screen) --%>
          <div
            id="qr-scanner-container"
            phx-hook="QrScanner"
            phx-update="ignore"
            class="absolute inset-0"
          >
            <%!-- Reconnecting overlay --%>
            <div
              id="reconnecting-overlay"
              class="hidden absolute inset-0 z-50 bg-black/80 items-center justify-center"
            >
              <div class="text-center text-white">
                <div class="animate-spin w-10 h-10 border-4 border-white/30 border-t-white rounded-full mx-auto mb-4">
                </div>
                <p class="text-lg font-semibold">Reconnecting...</p>
                <p class="text-sm text-white/60 mt-1">
                  Scanning paused until connection is restored
                </p>
              </div>
            </div>

            <%!-- Camera error state --%>
            <div
              :if={@camera_error}
              class="absolute inset-0 flex flex-col items-center justify-center bg-zinc-900 text-white p-8 text-center"
            >
              <.icon
                name="hero-video-camera-slash"
                class="w-16 h-16 mb-4 text-red-400"
              />
              <p class="text-xl font-semibold mb-2">Camera Not Available</p>
              <p class="text-sm text-white/55 mb-6">{@camera_error}</p>
              <p class="text-xs text-white/40">
                Use manual entry below to look up members.
              </p>
            </div>

            <%!-- QR reader — fills container via admin.css overrides --%>
            <div
              :if={!@camera_error}
              id="qr-reader"
              data-qr-reader
              class="absolute inset-0"
            >
            </div>

            <%!-- Viewfinder guide (hidden once a result is shown) --%>
            <div
              :if={!@camera_error && !@scan_result}
              class="absolute inset-0 flex items-center justify-center pointer-events-none"
            >
              <div class="relative w-64 h-64">
                <div class="absolute top-0 left-0 w-10 h-10 border-t-4 border-l-4 border-white/80 rounded-tl-xl">
                </div>
                <div class="absolute top-0 right-0 w-10 h-10 border-t-4 border-r-4 border-white/80 rounded-tr-xl">
                </div>
                <div class="absolute bottom-0 left-0 w-10 h-10 border-b-4 border-l-4 border-white/80 rounded-bl-xl">
                </div>
                <div class="absolute bottom-0 right-0 w-10 h-10 border-b-4 border-r-4 border-white/80 rounded-br-xl">
                </div>
              </div>
              <p class="absolute bottom-[calc(50%-160px)] inset-x-0 text-center text-white/50 text-xs tracking-wide">
                Point camera at a QR code
              </p>
            </div>
          </div>

          <%!-- Scan result bottom sheet --%>
          <div :if={@scan_result} class="absolute inset-x-0 bottom-0 z-30">
            {render_scan_result(assigns)}
          </div>

          <%!-- Group Check-in Modal --%>
          <.modal
            :if={@group_prompt}
            id="group-checkin-modal"
            show
            on_cancel={JS.push("dismiss_group")}
          >
            <div class="p-2">
              <h3 class="text-lg font-semibold text-zinc-800 mb-1">
                Group Check-in
              </h3>
              <p
                :if={@group_prompt.partially_scanned}
                class="text-sm text-amber-600 bg-amber-50 px-3 py-1.5 rounded-xl mb-3"
              >
                <.icon
                  name="hero-exclamation-triangle"
                  class="w-4 h-4 inline -mt-0.5"
                />
                This order is partially scanned — some guests have already been checked in.
              </p>
              <p class="text-sm text-zinc-600 mb-4">
                This ticket is part of an order with {length(
                  @group_prompt.unchecked_tickets
                )} unchecked guest(s).
              </p>

              <div class="space-y-2 mb-6">
                <div
                  :for={ticket <- @group_prompt.unchecked_tickets}
                  class="flex items-center justify-between bg-zinc-50 rounded-lg px-3 py-2"
                >
                  <div>
                    <span
                      :if={ticket.registration}
                      class="text-sm font-medium text-zinc-800"
                    >
                      {ticket.registration.first_name} {ticket.registration.last_name}
                    </span>
                    <span
                      :if={!ticket.registration}
                      class="text-sm text-zinc-500 italic"
                    >
                      No registration info
                    </span>
                  </div>
                  <.button
                    phx-click="check_in_single"
                    phx-value-ticket-id={ticket.id}
                    color="blue"
                  >
                    Check in only
                  </.button>
                </div>
              </div>

              <div :if={length(@group_prompt.checked_tickets) > 0} class="mb-4">
                <p class="text-xs text-zinc-400 mb-1">Already checked in:</p>
                <div
                  :for={ticket <- @group_prompt.checked_tickets}
                  class="flex items-center bg-zinc-100 rounded px-3 py-1.5 mb-1 text-sm text-zinc-400"
                >
                  <.icon
                    name="hero-check-circle"
                    class="w-4 h-4 mr-2 text-emerald-400"
                  />
                  <span :if={ticket.registration}>
                    {ticket.registration.first_name} {ticket.registration.last_name}
                  </span>
                  <span :if={!ticket.registration} class="italic">Guest</span>
                </div>
              </div>

              <div class="flex gap-3">
                <.button
                  phx-click="check_in_all"
                  phx-value-order-id={@group_prompt.order.id}
                  color="green"
                  class="flex-1"
                >
                  Check in ALL {length(@group_prompt.unchecked_tickets)} Guests
                </.button>
                <.button phx-click="dismiss_group" variant="outline" color="zinc">
                  Cancel
                </.button>
              </div>
            </div>
          </.modal>

          <%!-- Bottom controls: manual entry --%>
          <div class="absolute bottom-0 inset-x-0 z-20 pointer-events-none">
            <div class={[
              "px-4 pb-8 pt-32 bg-gradient-to-t from-black/75 to-transparent",
              "flex items-end justify-center",
              @scan_result && "opacity-0"
            ]}>
              <details class="group pointer-events-auto w-full max-w-sm">
                <summary class="cursor-pointer text-sm text-white/90 hover:text-white font-medium flex items-center justify-center gap-1.5 select-none">
                  <.icon name="hero-pencil-square" class="w-4 h-4" /> Manual Entry
                  <.icon
                    name="hero-chevron-up"
                    class="w-3 h-3 transition-transform group-open:rotate-180"
                  />
                </summary>
                <div class="mt-3 bg-zinc-900/95 backdrop-blur-sm border border-white/10 rounded-xl p-4">
                  <.form
                    for={@manual_form}
                    id="manual-entry-form"
                    phx-submit="manual_lookup"
                    class="flex gap-2"
                  >
                    <div class="flex-1">
                      <input
                        type="text"
                        name="manual[query]"
                        id="manual_query"
                        placeholder={
                          if(
                            @active_session.type in [:membership, :event_membership],
                            do: "Enter email address",
                            else: "Enter Order ID (e.g. ORD-XXXX)"
                          )
                        }
                        class="w-full bg-white/10 border border-white/20 text-white placeholder-white/35 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-white/30"
                      />
                    </div>
                    <button
                      type="submit"
                      class="shrink-0 bg-white text-zinc-900 hover:bg-white/90 px-4 py-2 rounded-lg text-sm font-semibold transition-colors"
                    >
                      Look Up
                    </button>
                  </.form>
                </div>
              </details>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  defp render_scan_result(%{scan_result: %{status: :active}} = assigns) do
    ~H"""
    <div class="scanner-result-sheet bg-emerald-600 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-4">
        <div class="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-check-badge" class="w-9 h-9 text-white" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-widest text-emerald-200 mb-0.5">
            Active Member
          </p>
          <p class="text-2xl font-bold leading-tight truncate">
            {@scan_result.user.first_name} {@scan_result.user.last_name}
          </p>
          <span
            :if={@scan_result.is_sub_account && @scan_result.primary_user}
            class="inline-flex items-center gap-1 text-xs text-emerald-200 mt-0.5"
          >
            <.icon name="hero-user-group" class="w-3 h-3" />
            Sub-account of {@scan_result.primary_user.first_name} {@scan_result.primary_user.last_name}
          </span>
        </div>
      </div>
      <div class="bg-white/15 rounded-2xl px-4 py-3 space-y-1 text-sm mb-5">
        <div class="flex justify-between">
          <span class="text-emerald-100">Membership</span>
          <span class="font-semibold">
            {format_membership_type(@scan_result.membership_type)}
          </span>
        </div>
        <div :if={@scan_result.member_since} class="flex justify-between">
          <span class="text-emerald-100">Member since</span>
          <span class="font-semibold">
            {Calendar.strftime(@scan_result.member_since, "%B %Y")}
          </span>
        </div>
        <div :if={@scan_result.renewal_date} class="flex justify-between">
          <span class="text-emerald-100">Renews</span>
          <span class="font-semibold">
            {Calendar.strftime(@scan_result.renewal_date, "%B %d, %Y")}
          </span>
        </div>
        <div
          :if={
            !@scan_result.renewal_date && @scan_result.membership_type == :lifetime
          }
          class="flex justify-between"
        >
          <span class="text-emerald-100">Expires</span>
          <span class="font-semibold">Never</span>
        </div>
      </div>
      <button
        phx-click="dismiss_scan_result"
        class="w-full bg-white/20 hover:bg-white/30 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
      >
        Scan Next
      </button>
    </div>
    """
  end

  defp render_scan_result(%{scan_result: %{status: :inactive}} = assigns) do
    ~H"""
    <div class="scanner-result-sheet bg-red-600 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-5">
        <div class="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-x-circle" class="w-9 h-9 text-white" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-widest text-red-200 mb-0.5">
            Inactive / Expired
          </p>
          <p class="text-2xl font-bold leading-tight truncate">
            {@scan_result.user.first_name} {@scan_result.user.last_name}
          </p>
          <span
            :if={@scan_result.is_sub_account && @scan_result.primary_user}
            class="inline-flex items-center gap-1 text-xs text-red-200 mt-0.5"
          >
            <.icon name="hero-user-group" class="w-3 h-3" />
            Sub-account of {@scan_result.primary_user.first_name} {@scan_result.primary_user.last_name}
          </span>
        </div>
      </div>
      <p class="text-sm text-red-100 bg-white/15 rounded-2xl px-4 py-3 mb-5">
        This member does not have an active membership.
      </p>
      <button
        phx-click="dismiss_scan_result"
        class="w-full bg-white/20 hover:bg-white/30 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
      >
        Scan Next
      </button>
    </div>
    """
  end

  defp render_scan_result(%{scan_result: %{status: :checked_in}} = assigns) do
    ~H"""
    <div class="scanner-result-sheet bg-emerald-600 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-5">
        <div class="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-check-circle" class="w-9 h-9 text-white" />
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-emerald-200 mb-0.5">
            Checked In
          </p>
          <p class="text-xl font-bold">{@scan_result.message}</p>
        </div>
      </div>
      <button
        phx-click="dismiss_scan_result"
        class="w-full bg-white/20 hover:bg-white/30 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
      >
        Scan Next
      </button>
    </div>
    """
  end

  defp render_scan_result(
         %{scan_result: %{status: :group_checked_in}} = assigns
       ) do
    ~H"""
    <div class="scanner-result-sheet bg-emerald-600 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-5">
        <div class="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-user-group" class="w-9 h-9 text-white" />
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-emerald-200 mb-0.5">
            Group Checked In
          </p>
          <p class="text-2xl font-bold">{@scan_result.count} guests</p>
        </div>
      </div>
      <button
        phx-click="dismiss_scan_result"
        class="w-full bg-white/20 hover:bg-white/30 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
      >
        Scan Next
      </button>
    </div>
    """
  end

  defp render_scan_result(%{scan_result: %{status: :already_scanned}} = assigns) do
    ~H"""
    <div class="scanner-result-sheet bg-amber-600 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-4">
        <div class="w-14 h-14 bg-white/20 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-exclamation-triangle" class="w-9 h-9 text-white" />
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-amber-200 mb-0.5">
            Already Scanned
          </p>
          <p class="text-xl font-bold">Duplicate Check-in</p>
        </div>
      </div>
      <p class="text-sm text-amber-100 bg-white/15 rounded-2xl px-4 py-3 mb-4">
        Originally checked in at:
        <span
          id="already-scanned-time"
          phx-hook="LocalTime"
          data-utc-time={DateTime.to_iso8601(@scan_result.checked_in_at)}
        >
          {Calendar.strftime(@scan_result.checked_in_at, "%B %d, %Y %H:%M:%S UTC")}
        </span>
      </p>
      <div class="flex gap-3 mb-0">
        <button
          phx-click="dismiss_scan_result"
          class="flex-1 bg-white/20 hover:bg-white/30 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
        >
          Scan Next
        </button>
        <.link
          :if={@scan_result.user_id}
          navigate={~p"/admin/users/#{@scan_result.user_id}/details/orders"}
          target="_blank"
          class="flex items-center gap-2 bg-white text-amber-700 hover:bg-amber-50 font-semibold py-3 px-4 rounded-2xl transition-colors text-sm shrink-0"
        >
          <.icon name="hero-document-text" class="w-4 h-4" /> View Order
        </.link>
      </div>
    </div>
    """
  end

  defp render_scan_result(%{scan_result: %{status: :error}} = assigns) do
    ~H"""
    <div class="scanner-result-sheet bg-zinc-800 rounded-t-3xl px-6 pt-5 pb-10 text-white">
      <div class="w-10 h-1 bg-white/30 rounded-full mx-auto mb-5"></div>
      <div class="flex items-center gap-4 mb-4">
        <div class="w-14 h-14 bg-white/15 rounded-2xl flex items-center justify-center shrink-0">
          <.icon name="hero-x-mark" class="w-9 h-9 text-white" />
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-0.5">
            Error
          </p>
          <p class="text-lg font-bold leading-snug">{@scan_result.message}</p>
        </div>
      </div>
      <button
        phx-click="dismiss_scan_result"
        class="w-full bg-white/15 hover:bg-white/25 text-white font-semibold py-3 rounded-2xl transition-colors text-sm"
      >
        Try Again
      </button>
    </div>
    """
  end

  defp render_scan_result(assigns) do
    ~H"""
    """
  end

  # --- Mount ---

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:active_page, :scanner)
      |> assign(:page_title, "Check-in & Scan")
      |> assign(:phase, :setup)
      |> assign(:selected_mode, nil)
      |> assign(:active_session, nil)
      |> assign(:scan_result, nil)
      |> assign(:scan_count, 0)
      |> assign(:camera_error, nil)
      |> assign(:group_prompt, nil)
      |> assign(
        :setup_form,
        to_form(%{"name" => "", "event_id" => ""}, as: :session)
      )
      |> assign(:manual_form, to_form(%{"query" => ""}, as: :manual))
      |> assign(:open_sessions, [])
      |> assign(:joinable_sessions, [])
      |> assign(:sessions, [])
      |> assign(:detail_session, nil)
      |> assign(:detail_records, [])
      |> assign(:event_options, [])

    socket =
      if connected?(socket) do
        load_event_options(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"resume" => session_id}) do
    session = Scanning.get_session!(session_id)

    if is_nil(session.closed_at) do
      scan_count = Scanning.get_session_scan_count(session_id)

      socket
      |> assign(:page_title, "Check-in & Scan")
      |> assign(:phase, :scanning)
      |> assign(:active_session, session)
      |> assign(:scan_count, scan_count)
      |> assign(:scan_result, nil)
      |> assign(:camera_error, nil)
      |> assign(:group_prompt, nil)
      |> assign(:open_sessions, [])
    else
      open_sessions = Scanning.get_open_sessions(socket.assigns.current_user.id)
      joinable_sessions = load_joinable_sessions(socket, open_sessions)

      socket
      |> assign(:page_title, "Check-in & Scan")
      |> assign(:phase, :setup)
      |> assign(:active_session, nil)
      |> assign(:scan_result, nil)
      |> assign(:open_sessions, open_sessions)
      |> assign(:joinable_sessions, joinable_sessions)
      |> put_flash(:error, "That session is already closed.")
    end
  end

  defp apply_action(socket, :index, _params) do
    open_sessions = Scanning.get_open_sessions(socket.assigns.current_user.id)
    joinable_sessions = load_joinable_sessions(socket, open_sessions)

    socket
    |> assign(:page_title, "Check-in & Scan")
    |> assign(:phase, :setup)
    |> assign(:active_session, nil)
    |> assign(:scan_result, nil)
    |> assign(:open_sessions, open_sessions)
    |> assign(:joinable_sessions, joinable_sessions)
  end

  defp apply_action(socket, :sessions, _params) do
    sessions = Scanning.list_sessions()

    socket
    |> assign(:page_title, "Scan Sessions")
    |> assign(:sessions, sessions)
  end

  defp apply_action(socket, :session_detail, %{"id" => id}) do
    session = Scanning.get_session!(id)

    if session.type == :event_membership do
      push_navigate(socket, to: ~p"/admin/membership-check-in/#{id}")
    else
      records = Scanning.list_scan_records(id)

      socket
      |> assign(:page_title, "Session: #{session.name}")
      |> assign(:detail_session, session)
      |> assign(:detail_records, records)
    end
  end

  # --- Events ---

  @impl true
  def handle_event("select_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :selected_mode, mode)}
  end

  def handle_event("start_session", %{"session" => params}, socket) do
    session_type_str = socket.assigns.selected_mode

    session_type =
      case session_type_str do
        "membership" -> :membership
        "event" -> :event
        "event_membership" -> :event_membership
        _ -> nil
      end

    if is_nil(session_type) do
      {:noreply,
       put_flash(socket, :error, "Please select a scan mode before starting.")}
    else
      needs_event_id = session_type in [:event, :event_membership]

      attrs = %{
        name: params["name"] || "Scan Session",
        type: session_type,
        event_id: if(needs_event_id, do: params["event_id"]),
        created_by_id: socket.assigns.current_user.id
      }

      case Scanning.create_session(attrs) do
        {:ok, session} ->
          if session_type == :event_membership do
            {:noreply,
             push_navigate(socket,
               to: ~p"/admin/membership-check-in/#{session.id}"
             )}
          else
            session = Scanning.get_session!(session.id)

            socket =
              socket
              |> assign(:phase, :scanning)
              |> assign(:active_session, session)
              |> assign(:scan_count, 0)
              |> assign(:scan_result, nil)
              |> assign(:camera_error, nil)
              |> assign(:group_prompt, nil)

            {:noreply, socket}
          end

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:setup_form, to_form(changeset, as: :session))
           |> YscWeb.Flash.put_toast(
             :error,
             "Could not start session. Check the form.",
             title: "Error"
           )}
      end
    end
  end

  def handle_event("scan_result", %{"data" => data}, socket) do
    user_id = socket.assigns.current_user.id

    case check_rate_limit(user_id) do
      :ok ->
        handle_scan(socket, data)

      :rate_limited ->
        {:noreply,
         assign(socket, :scan_result, %{
           status: :error,
           message: "Too many scans. Please slow down."
         })}
    end
  end

  def handle_event("camera_started", _params, socket) do
    Ysc.Logging.info("[QrScanner] camera started",
      user_id: socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("camera_error", %{"reason" => reason}, socket) do
    Ysc.Logging.warning("[QrScanner] camera error",
      reason: reason,
      user_id: socket.assigns.current_user.id
    )

    {:noreply, assign(socket, :camera_error, reason)}
  end

  def handle_event("scanner_debug", %{"message" => message} = params, socket) do
    extra = Map.get(params, "extra")

    Ysc.Logging.info("[QrScanner] #{message}",
      extra: extra,
      user_id: socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("check_in_single", %{"ticket-id" => ticket_id}, socket) do
    case Scanning.check_in_single(socket.assigns.active_session, ticket_id) do
      {:ok, {_ticket, _record}} ->
        {:noreply,
         socket
         |> assign(:group_prompt, nil)
         |> assign(:scan_count, socket.assigns.scan_count + 1)
         |> assign(:scan_result, %{
           status: :checked_in,
           message: "Guest checked in successfully"
         })}

      {:error, _reason, message} when is_binary(message) ->
        {:noreply,
         assign(socket, :scan_result, %{status: :error, message: message})}

      {:error, _} ->
        {:noreply,
         assign(socket, :scan_result, %{
           status: :error,
           message: "Failed to check in ticket."
         })}
    end
  end

  def handle_event("check_in_all", %{"order-id" => order_id}, socket) do
    case Scanning.check_in_order(socket.assigns.active_session, order_id) do
      {:ok, :group_checked_in, count} ->
        {:noreply,
         socket
         |> assign(:group_prompt, nil)
         |> assign(:scan_count, socket.assigns.scan_count + count)
         |> assign(:scan_result, %{status: :group_checked_in, count: count})}

      {:error, _type, message} ->
        {:noreply,
         assign(socket, :scan_result, %{status: :error, message: message})}
    end
  end

  def handle_event("dismiss_group", _params, socket) do
    {:noreply, assign(socket, :group_prompt, nil)}
  end

  def handle_event("dismiss_scan_result", _params, socket) do
    {:noreply, assign(socket, :scan_result, nil)}
  end

  def handle_event("manual_lookup", %{"manual" => %{"query" => query}}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, socket}
    else
      handle_manual_lookup(socket, query)
    end
  end

  def handle_event("resume_session", %{"session-id" => session_id}, socket) do
    current_user_id = socket.assigns.current_user.id

    socket =
      case Scanning.authorize_session_owner!(session_id, current_user_id) do
        :ok ->
          resume_session_socket(socket, session_id)

        {:error, :unauthorized} ->
          put_flash(
            socket,
            :error,
            "You can only resume scan sessions you created."
          )

        {:error, :not_found} ->
          put_flash(socket, :error, "Scan session not found.")
      end

    {:noreply, socket}
  end

  def handle_event("end_session", _params, socket) do
    session = socket.assigns.active_session

    socket = push_event(socket, "stop-camera", %{})

    if session && has_desk_view?(session) do
      {:noreply, push_navigate(socket, to: desk_path(session))}
    else
      if session do
        Scanning.close_session(session.id)
      end

      open_sessions = Scanning.get_open_sessions(socket.assigns.current_user.id)
      joinable_sessions = load_joinable_sessions(socket, open_sessions)

      socket =
        socket
        |> assign(:phase, :setup)
        |> assign(:active_session, nil)
        |> assign(:scan_result, nil)
        |> assign(:scan_count, 0)
        |> assign(:camera_error, nil)
        |> assign(:group_prompt, nil)
        |> assign(:open_sessions, open_sessions)
        |> assign(:joinable_sessions, joinable_sessions)

      {:noreply, socket}
    end
  end

  def handle_event("export-csv", %{"session-id" => session_id}, socket) do
    current_user_id = socket.assigns.current_user.id

    case Scanning.authorize_session_owner!(session_id, current_user_id) do
      :ok ->
        csv_content = Scanning.export_session_csv(session_id)
        encoded = Base.encode64(csv_content)

        filename =
          "scan_session_#{session_id}_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

        {:noreply,
         push_event(socket, "download-csv", %{
           content: encoded,
           filename: filename
         })}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You can only export scan sessions you created."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Scan session not found.")}
    end
  end

  # --- Private ---

  defp resume_session_socket(socket, session_id) do
    session = Scanning.get_session!(session_id)

    if is_nil(session.closed_at) do
      scan_count = Scanning.get_session_scan_count(session_id)

      socket
      |> assign(:phase, :scanning)
      |> assign(:active_session, session)
      |> assign(:scan_count, scan_count)
      |> assign(:scan_result, nil)
      |> assign(:camera_error, nil)
      |> assign(:group_prompt, nil)
    else
      put_flash(socket, :error, "That session is already closed.")
    end
  end

  defp handle_scan(socket, data) do
    session = socket.assigns.active_session

    case Scanning.process_scan(session, data) do
      {:ok, {_ticket, _record}} ->
        {:noreply,
         socket
         |> assign(:scan_count, socket.assigns.scan_count + 1)
         |> assign(:scan_result, %{
           status: :checked_in,
           message: "Guest checked in successfully"
         })
         |> assign(:group_prompt, nil)}

      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:scan_count, socket.assigns.scan_count + 1)
         |> assign(:scan_result, result)
         |> assign(:group_prompt, nil)}

      {:ok, :group_prompt, group_data} ->
        {:noreply,
         socket
         |> assign(:group_prompt, group_data)
         |> assign(:scan_result, nil)}

      {:error, :already_scanned, %{checked_in_at: checked_in_at} = info} ->
        {:noreply,
         assign(socket, :scan_result, %{
           status: :already_scanned,
           checked_in_at: checked_in_at,
           ticket_id: Map.get(info, :ticket_id),
           order_id: Map.get(info, :order_id),
           user_id: Map.get(info, :user_id)
         })}

      {:error, _type, message} ->
        {:noreply,
         assign(socket, :scan_result, %{status: :error, message: message})}
    end
  end

  defp handle_manual_lookup(socket, query) do
    session = socket.assigns.active_session

    case session.type do
      t when t in [:membership, :event_membership] ->
        case Scanning.manual_membership_lookup(query) do
          {:ok, user} ->
            token = QrToken.sign_membership(user.id)
            handle_scan(socket, token)

          {:error, _, message} ->
            {:noreply,
             assign(socket, :scan_result, %{status: :error, message: message})}
        end

      :event ->
        case Scanning.manual_ticket_lookup(query, session.event_id) do
          {:ok, order} ->
            case order.tickets do
              [ticket | _] ->
                token = QrToken.sign_ticket(ticket.id)
                handle_scan(socket, token)

              [] ->
                {:noreply,
                 assign(socket, :scan_result, %{
                   status: :error,
                   message: "No tickets found in this order."
                 })}
            end

          {:error, _, message} ->
            {:noreply,
             assign(socket, :scan_result, %{status: :error, message: message})}
        end
    end
  end

  defp load_event_options(socket) do
    events = Events.list_upcoming_events_with_preload(50, [])

    options =
      Enum.map(events, fn event ->
        date_str = Calendar.strftime(event.start_date, "%b %d")
        {"#{event.title} (#{date_str})", event.id}
      end)

    assign(socket, :event_options, options)
  end

  defp check_rate_limit(user_id) do
    Ysc.ScanRateLimit.check(user_id)
  end

  defp format_membership_type(nil), do: "Unknown"
  defp format_membership_type(:lifetime), do: "Lifetime Membership"
  defp format_membership_type(:single), do: "Single Membership"
  defp format_membership_type(:family), do: "Family Membership"

  defp format_membership_type(type) when is_atom(type) do
    type |> Atom.to_string() |> String.capitalize() |> then(&"#{&1} Membership")
  end

  defp format_membership_type(_), do: "Membership"

  defp result_badge_class(:success), do: "bg-emerald-100 text-emerald-800"
  defp result_badge_class(:already_scanned), do: "bg-red-100 text-red-800"
  defp result_badge_class(:invalid), do: "bg-red-100 text-red-800"
  defp result_badge_class(:expired), do: "bg-amber-100 text-amber-800"
  defp result_badge_class(:cross_mode), do: "bg-amber-100 text-amber-800"
  defp result_badge_class(_), do: "bg-zinc-100 text-zinc-800"

  defp session_type_label(:membership), do: "Membership"
  defp session_type_label(:event), do: "Event"
  defp session_type_label(:event_membership), do: "Event + Members"
  defp session_type_label(_), do: "Session"

  defp session_type_badge_class(:membership),
    do: "bg-emerald-100 text-emerald-800"

  defp session_type_badge_class(:event_membership),
    do: "bg-violet-100 text-violet-800"

  defp session_type_badge_class(_), do: "bg-blue-100 text-blue-800"

  defp has_desk_view?(%{type: :event_membership}), do: true

  defp has_desk_view?(%{type: :event, event_id: event_id})
       when not is_nil(event_id),
       do: true

  defp has_desk_view?(_), do: false

  defp desk_path(%{type: :event_membership, id: session_id}) do
    ~p"/admin/membership-check-in/#{session_id}"
  end

  defp desk_path(%{type: :event, id: session_id, event_id: event_id}) do
    ~p"/admin/events/#{event_id}/check-in?scan_session_id=#{session_id}"
  end

  defp load_joinable_sessions(socket, own_open_sessions) do
    current_user_id = socket.assigns.current_user.id
    own_ids = MapSet.new(own_open_sessions, & &1.id)

    Scanning.get_open_membership_sessions()
    |> Enum.reject(fn s ->
      s.created_by_id == current_user_id or MapSet.member?(own_ids, s.id)
    end)
  end
end
