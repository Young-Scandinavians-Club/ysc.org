defmodule YscWeb.AdminMembershipCheckInLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  require Ysc.Logging

  alias Ysc.Scanning
  alias Ysc.MessagePassingEvents

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <%!-- Sticky top bar --%>
      <div class="bg-white border-b border-zinc-200 sticky top-0 z-10">
        <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex items-center justify-between h-16 gap-4">
            <%!-- Back + session title --%>
            <div class="flex items-center gap-3 min-w-0">
              <.back navigate={~p"/admin/scanner"}>Back</.back>
              <span class="text-zinc-300 select-none hidden sm:inline">/</span>
              <div class="min-w-0 hidden sm:block">
                <h1 class="text-base font-semibold text-zinc-900 truncate">
                  {@session.name}
                </h1>
                <p
                  :if={@session.event}
                  class="text-xs text-zinc-500 truncate leading-tight"
                >
                  {@session.event.title}
                </p>
              </div>
            </div>

            <%!-- Live checked-in counter --%>
            <div class="flex items-center gap-2 shrink-0">
              <span class="text-sm text-zinc-500 hidden sm:inline">
                Checked in:
              </span>
              <.badge type="green">
                <.icon name="hero-user-group" class="inline -mt-0.5" />
                {@checked_in_count}
              </.badge>
            </div>

            <%!-- Actions --%>
            <div class="shrink-0 flex items-center gap-2">
              <%= if @session.closed_at do %>
                <.badge type="zinc" class="hidden sm:inline-block">
                  <.icon
                    name="hero-lock-closed"
                    class="w-3 h-3 inline -mt-0.5 me-0.5"
                  /> Completed
                </.badge>
                <.button
                  id="export-csv-btn"
                  phx-click="export-csv"
                  variant="outline"
                  color="zinc"
                >
                  <.icon name="hero-arrow-down-tray" class="w-5 h-5 me-1 mt-0.5" />
                  Export CSV
                </.button>
              <% else %>
                <.button
                  id="launch-scanner-btn"
                  phx-click="launch-scanner"
                  variant="outline"
                  color="zinc"
                  class="hidden sm:inline-flex"
                >
                  <.icon name="hero-qr-code" class="w-5 h-5 me-1 mt-0.5" />
                  QR Scanner
                </.button>
                <button
                  phx-click="launch-scanner"
                  class="sm:hidden p-2 text-zinc-500 hover:text-zinc-700"
                  aria-label="Open QR Scanner"
                >
                  <.icon name="hero-qr-code" class="w-6 h-6" />
                </button>
                <.button
                  id="copy-url-btn"
                  phx-hook="ClipboardCopy"
                  data-copy={url(~p"/admin/membership-check-in/#{@session.id}")}
                  variant="outline"
                  color="zinc"
                  class="hidden sm:inline-flex"
                  title="Copy session link for other admins to join"
                >
                  <.icon name="hero-clipboard" class="w-5 h-5 me-1 mt-0.5" /> Share
                </.button>
                <.button
                  id="complete-session-btn"
                  phx-click="complete-session"
                  variant="outline"
                  color="zinc"
                  class="hidden sm:inline-flex"
                  data-confirm="Complete this session? It will be locked and no longer appear as active."
                >
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 mt-0.5" />
                  Complete
                </.button>
                <button
                  phx-click="complete-session"
                  class="sm:hidden p-2 text-zinc-500 hover:text-zinc-700"
                  aria-label="Complete session"
                  data-confirm="Complete this session? It will be locked and no longer appear as active."
                >
                  <.icon name="hero-check-circle" class="w-6 h-6" />
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- Search bar --%>
      <div class="bg-white border-b border-zinc-200">
        <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <.admin_search_bar
            id="member-search-form"
            input_id="member-search-input"
            name="q"
            value={@search_query}
            placeholder="Search by name or email…"
            on_change="search"
            debounce="300"
            clear_event="clear-search"
          />
        </div>
      </div>

      <%!-- Content --%>
      <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-8">
        <%= if @loading do %>
          <div class="flex items-center justify-center py-24">
            <.spinner class="w-8 h-8 text-zinc-400" />
          </div>
        <% else %>
          <%!-- Search results (only when searching) --%>
          <%= if @search_query != "" do %>
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500 mb-3">
                Search Results
              </h2>

              <div
                :if={@search_results == []}
                class="py-10 text-center text-zinc-500"
              >
                <.icon
                  name="hero-magnifying-glass"
                  class="w-10 h-10 mx-auto mb-2 text-zinc-300"
                />
                <p class="font-medium">No members found</p>
                <p class="text-sm mt-1 text-zinc-400">
                  Try a different name or email address
                </p>
              </div>

              <div
                :if={@search_results != []}
                class="bg-white rounded-xl border border-zinc-200 divide-y divide-zinc-100"
                id="search-results-list"
              >
                <div
                  :for={result <- @search_results}
                  id={"search-result-#{result.user.id}"}
                >
                  {render_search_result(assigns, result)}
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Checked-in list --%>
          <div>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">
                Checked In
                <span class="ml-1.5 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-700">
                  {@checked_in_count}
                </span>
              </h2>
            </div>

            <div
              id="checked-in-members"
              phx-update="stream"
              class="bg-white rounded-xl border border-zinc-200 divide-y divide-zinc-100"
            >
              <div
                id="checked-in-members-empty"
                class="hidden only:flex flex-col items-center py-12 text-zinc-500"
              >
                <.icon
                  name="hero-identification"
                  class="w-10 h-10 mb-2 text-zinc-300"
                />
                <p class="font-medium">No members checked in yet</p>
                <p class="text-sm mt-1 text-zinc-400">
                  Use the search bar above to find and check in members
                </p>
              </div>

              <div
                :for={{dom_id, check_in} <- @streams.checked_in_members}
                id={dom_id}
                class="flex items-center gap-4 px-4 py-3 hover:bg-zinc-50/60 transition-colors"
              >
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <p class="text-sm font-semibold text-zinc-900">
                      {check_in.user.first_name} {check_in.user.last_name}
                    </p>
                    {render_membership_badge(
                      assigns,
                      check_in.membership_status,
                      check_in.membership_type
                    )}
                  </div>
                  <p class="text-xs text-zinc-500 mt-0.5">
                    {check_in.user.email}
                  </p>
                  <p class="text-xs text-zinc-400 mt-0.5">
                    Checked in
                    <span
                      id={"checkin-time-#{dom_id}"}
                      phx-hook="LocalTime"
                      data-utc-time={DateTime.to_iso8601(check_in.inserted_at)}
                    >
                      {Calendar.strftime(check_in.inserted_at, "%b %d at %H:%M UTC")}
                    </span>
                    by {check_in.checked_in_by.first_name} {check_in.checked_in_by.last_name}
                  </p>
                </div>
                <button
                  phx-click="undo-check-in"
                  phx-value-user-id={check_in.user.id}
                  class="shrink-0 text-xs font-medium text-zinc-400 hover:text-red-600 border border-zinc-200 hover:border-red-200 hover:bg-red-50 px-2.5 py-1.5 rounded-lg transition-colors"
                  data-confirm="Remove this member's check-in?"
                >
                  Undo
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_search_result(assigns, result) do
    assigns = assign(assigns, result: result)

    ~H"""
    <div class={[
      "flex items-center gap-4 px-4 py-3 transition-colors",
      if(@result.membership_status == :inactive,
        do: "bg-red-50/30",
        else: "hover:bg-zinc-50/60"
      )
    ]}>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <p class="text-sm font-semibold text-zinc-900">
            {@result.user.first_name} {@result.user.last_name}
          </p>
          {render_membership_badge(
            assigns,
            @result.membership_status,
            @result.membership_type
          )}
          <span
            :if={@result.checked_in?}
            class="inline-flex items-center gap-1 text-xs font-semibold text-emerald-700 bg-emerald-100 px-2 py-0.5 rounded-full"
          >
            <.icon name="hero-check-circle" class="w-3 h-3" /> Checked In
          </span>
        </div>
        <p class="text-xs text-zinc-500 mt-0.5">{@result.user.email}</p>
        <p
          :if={@result.membership_status == :inactive}
          class="text-xs text-red-600 font-medium mt-0.5"
        >
          No active membership — cannot be checked in
        </p>
      </div>

      <div class="shrink-0">
        <%= cond do %>
          <% @result.checked_in? -> %>
            <button
              phx-click="undo-check-in"
              phx-value-user-id={@result.user.id}
              class="text-xs font-medium text-zinc-400 hover:text-red-600 border border-zinc-200 hover:border-red-200 hover:bg-red-50 px-2.5 py-1.5 rounded-lg transition-colors"
              data-confirm="Remove this member's check-in?"
            >
              Undo
            </button>
          <% @result.membership_status == :active -> %>
            <button
              phx-click="check-in-member"
              phx-value-user-id={@result.user.id}
              class="text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-700 px-4 py-2 rounded-lg transition-colors"
            >
              Check In
            </button>
          <% true -> %>
            <button
              disabled
              class="text-sm font-semibold text-zinc-400 bg-zinc-100 px-4 py-2 rounded-lg cursor-not-allowed"
              title="User does not have an active membership"
            >
              No Membership
            </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_membership_badge(assigns, status, membership_type) do
    assigns =
      assign(assigns,
        membership_status: status,
        membership_type: membership_type
      )

    ~H"""
    <%= cond do %>
      <% @membership_status == :active || @membership_status == "active" -> %>
        <span class="inline-flex items-center gap-1 text-xs font-semibold text-emerald-700 bg-emerald-100 px-2 py-0.5 rounded-full">
          <.icon name="hero-check-badge" class="w-3 h-3" />
          {format_membership_type(@membership_type)}
        </span>
      <% true -> %>
        <span class="inline-flex items-center gap-1 text-xs font-semibold text-red-700 bg-red-100 px-2 py-0.5 rounded-full">
          <.icon name="hero-x-circle" class="w-3 h-3" /> NO MEMBERSHIP
        </span>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Mount & Params
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    session = Scanning.get_session!(session_id)

    if connected?(socket) do
      Scanning.subscribe_membership_checkin(session_id)
    end

    checked_in_count = Scanning.membership_check_in_count(session_id)

    socket =
      socket
      |> assign(:active_page, :scanner)
      |> assign(:page_title, session.name)
      |> assign(:session, session)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:checked_in_count, checked_in_count)
      |> assign(:loading, true)
      |> stream(:checked_in_members, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_query = Map.get(params, "q", "")

    socket =
      socket
      |> assign(:search_query, search_query)
      |> reload_checked_in()
      |> then(fn s ->
        if search_query != "" do
          run_search(s, search_query)
        else
          assign(s, :search_results, [])
        end
      end)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/admin/membership-check-in/#{socket.assigns.session.id}?q=#{query}"
     )}
  end

  def handle_event("clear-search", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/membership-check-in/#{socket.assigns.session.id}"
     )}
  end

  def handle_event("check-in-member", %{"user-id" => user_id}, socket) do
    %{session: session, current_user: current_user} = socket.assigns

    user = Ysc.Accounts.get_user(user_id)

    case Scanning.check_in_member(session, user, current_user) do
      {:ok, _check_in} ->
        socket =
          socket
          |> assign(:search_query, "")
          |> assign(:search_results, [])
          |> reload_checked_in()
          |> push_event("focus-and-clear", %{id: "member-search-input"})

        {:noreply, socket}

      {:error, :already_checked_in, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _type, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("undo-check-in", %{"user-id" => user_id}, socket) do
    %{session: session} = socket.assigns

    case Scanning.undo_member_check_in(session.id, user_id) do
      {:ok, :removed} ->
        socket =
          socket
          |> reload_checked_in()
          |> run_search(socket.assigns.search_query)

        {:noreply, socket}

      {:error, _type, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("launch-scanner", _params, socket) do
    {:noreply,
     push_navigate(socket,
       to: ~p"/admin/scanner?resume=#{socket.assigns.session.id}"
     )}
  end

  def handle_event("complete-session", _params, socket) do
    session_id = socket.assigns.session.id

    case Scanning.close_session(session_id) do
      {:ok, _updated} ->
        closed_session = Scanning.get_session!(session_id)

        {:noreply,
         socket
         |> assign(:session, closed_session)
         |> put_flash(:info, "Session completed and locked.")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not complete the session. Please try again."
         )}
    end
  end

  def handle_event("export-csv", _params, socket) do
    session_id = socket.assigns.session.id
    csv_content = Scanning.export_membership_checkins_csv(session_id)
    encoded = Base.encode64(csv_content)

    filename =
      "membership_checkin_#{session_id}_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    {:noreply,
     push_event(socket, "download-csv", %{content: encoded, filename: filename})}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(
        {Scanning, %MessagePassingEvents.MemberCheckedIn{session_id: sid}},
        socket
      ) do
    socket =
      if sid == socket.assigns.session.id do
        socket
        |> reload_checked_in()
        |> run_search(socket.assigns.search_query)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {Scanning, %MessagePassingEvents.MemberCheckInUndone{session_id: sid}},
        socket
      ) do
    socket =
      if sid == socket.assigns.session.id do
        socket
        |> reload_checked_in()
        |> run_search(socket.assigns.search_query)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {Scanning,
         %MessagePassingEvents.MembershipSessionCompleted{session_id: sid}},
        socket
      ) do
    socket =
      if sid == socket.assigns.session.id do
        closed_session = Scanning.get_session!(sid)

        socket
        |> assign(:session, closed_session)
        |> put_flash(:info, "This session has been completed and locked.")
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp reload_checked_in(socket) do
    session_id = socket.assigns.session.id
    check_ins = Scanning.list_membership_check_ins(session_id)
    count = length(check_ins)

    socket
    |> assign(:loading, false)
    |> assign(:checked_in_count, count)
    |> stream(:checked_in_members, check_ins, reset: true)
  end

  defp run_search(socket, "") do
    assign(socket, :search_results, [])
  end

  defp run_search(socket, query) do
    results =
      Scanning.search_users_for_checkin(socket.assigns.session.id, query)

    assign(socket, :search_results, results)
  end

  defp format_membership_type(nil), do: "Member"
  defp format_membership_type("lifetime"), do: "Lifetime"
  defp format_membership_type(:lifetime), do: "Lifetime"
  defp format_membership_type("single"), do: "Single"
  defp format_membership_type(:single), do: "Single"
  defp format_membership_type("family"), do: "Family"
  defp format_membership_type(:family), do: "Family"

  defp format_membership_type(type) when is_atom(type),
    do: type |> Atom.to_string() |> String.capitalize()

  defp format_membership_type(type) when is_binary(type),
    do: String.capitalize(type)

  defp format_membership_type(_), do: "Member"
end
