defmodule YscWeb.AdminMembershipCheckInLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  alias Ysc.Scanning
  alias Ysc.MessagePassingEvents

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <.admin_check_in_sticky_bar>
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

        <.admin_check_in_counter count={@checked_in_count} />

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
              <.icon name="hero-arrow-down-tray" class="w-5 h-5" /> Export CSV
            </.button>
          <% else %>
            <.admin_check_in_qr_scanner id="launch-scanner-btn" />
            <.admin_responsive_clipboard_button
              id="copy-url-btn"
              copy={url(~p"/admin/membership-check-in/#{@session.id}")}
              icon="hero-clipboard"
              label="Share"
              aria_label="Copy session link for other admins to join"
              title="Copy session link for other admins to join"
              variant="outline"
              color="zinc"
              mobile_tone={:zinc}
            />
            <.admin_responsive_icon_button
              id="complete-session-btn"
              icon="hero-check-circle"
              label="Complete"
              aria_label="Complete session"
              phx_click="complete-session"
              variant="outline"
              color="zinc"
              mobile_tone={:zinc}
              data-confirm="Complete this session? It will be locked and no longer appear as active."
            />
          <% end %>
        </div>
      </.admin_check_in_sticky_bar>

      <.admin_check_in_search_section :if={is_nil(@session.closed_at)}>
        <.admin_search_bar
          id="member-search-form"
          input_id="member-search-input"
          name="q"
          value={@search_query}
          placeholder="Search by name or email…"
          on_change="search"
          debounce="300"
          clear_event="clear-search"
          phx-hook="MembershipCheckInKeyboard"
        />
        <.admin_check_in_keyboard_hints show={searching?(@search_query)} />
      </.admin_check_in_search_section>

      <.admin_check_in_content>
        <%= if @loading do %>
          <.admin_loading_panel />
        <% else %>
          <%!-- Search results (only when searching) --%>
          <%= if searching?(@search_query) do %>
            <div>
              <.admin_section_heading class="mb-3">
                Search Results
              </.admin_section_heading>

              <.admin_icon_empty_state
                :if={@search_results == []}
                variant={:compact}
                icon="hero-magnifying-glass"
                title="No members found"
                description="Try a different name or email address"
              />

              <div
                :if={@search_results != []}
                class="bg-white rounded border border-zinc-200 divide-y divide-zinc-100"
                id="search-results-list"
              >
                <div
                  :for={{result, index} <- Enum.with_index(@search_results)}
                  id={"search-result-#{result.user.id}"}
                  data-checkin-index={index}
                  data-checked-in={if result.checked_in?, do: "true"}
                >
                  {render_search_result(
                    assigns,
                    result,
                    index,
                    is_nil(@session.closed_at),
                    searching?(@search_query)
                  )}
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Checked-in list --%>
          <div>
            <div class="flex items-center justify-between mb-3">
              <.admin_section_heading
                count={@checked_in_count}
                badge_tone={:emerald}
              >
                Checked In
              </.admin_section_heading>
            </div>

            <div
              id="checked-in-members"
              phx-update="stream"
              class="bg-white rounded border border-zinc-200 divide-y divide-zinc-100"
            >
              <.admin_icon_empty_state
                id="checked-in-members-empty"
                variant={:compact}
                icon="hero-identification"
                title="No members checked in yet"
                description="Use the search bar above to find and check in members"
                class="hidden only:flex flex-col items-center py-12"
                icon_class="w-10 h-10 mb-2 text-zinc-300"
              />

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
                  class="shrink-0 text-xs font-medium text-zinc-400 hover:text-red-600 border border-zinc-200 hover:border-red-200 hover:bg-red-50 px-2.5 py-1.5 rounded transition-colors"
                  data-confirm="Remove this member's check-in?"
                >
                  Undo
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </.admin_check_in_content>
    </div>
    """
  end

  defp render_search_result(assigns, result, index, session_open?, searching?) do
    assigns =
      assign(assigns,
        result: result,
        result_index: index,
        session_open?: session_open?,
        show_shortcuts?: searching?
      )

    ~H"""
    <div class={[
      "flex items-center gap-4 px-4 py-3 transition-all duration-100 ease-out",
      if(@result.membership_status == :inactive,
        do: "bg-red-50/30",
        else: "hover:bg-zinc-50/60"
      )
    ]}>
      <%!-- Keyboard shortcut badge for the first 3 results (only while searching) --%>
      <div
        :if={@show_shortcuts? && @result_index < 3}
        class="shrink-0 hidden sm:flex items-center justify-center w-14"
      >
        <span
          class="inline-flex items-center gap-0.5 select-none"
          title={"Alt+#{@result_index + 1} to check in"}
        >
          <.admin_kbd size={:inline} tone={:muted} data-key="alt">alt</.admin_kbd>
          <.admin_kbd size={:compact} tone={:muted}>
            {@result_index + 1}
          </.admin_kbd>
        </span>
      </div>

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

      <div :if={@session_open?} class="shrink-0">
        <%= cond do %>
          <% @result.checked_in? -> %>
            <button
              phx-click="undo-check-in"
              phx-value-user-id={@result.user.id}
              data-checkin-btn
              class="text-xs font-medium text-zinc-400 hover:text-red-600 border border-zinc-200 hover:border-red-200 hover:bg-red-50 px-2.5 py-1.5 rounded transition-colors"
              data-confirm="Remove this member's check-in?"
            >
              Undo
            </button>
          <% @result.membership_status == :active -> %>
            <button
              phx-click="check-in-member"
              phx-value-user-id={@result.user.id}
              data-checkin-btn
              class="text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-700 px-4 py-2 rounded transition-colors"
            >
              Check In
            </button>
          <% true -> %>
            <button
              disabled
              class="text-sm font-semibold text-zinc-400 bg-zinc-100 px-4 py-2 rounded cursor-not-allowed"
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
    user_id = socket.assigns.current_user.id

    case Scanning.fetch_membership_checkin_session(session_id, user_id) do
      {:ok, session} ->
        mount_desk(session, socket)

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "You can only view closed membership check-in sessions you created."
         )
         |> push_navigate(to: ~p"/admin/scanner/sessions")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Check-in session not found.")
         |> push_navigate(to: ~p"/admin/scanner/sessions")}
    end
  end

  defp mount_desk(session, socket) do
    session_id = session.id

    if connected?(socket) do
      Scanning.subscribe_membership_checkin(session_id)
    end

    socket =
      socket
      |> assign(:active_page, :scanner)
      |> assign(:page_title, session.name)
      |> assign(:session, session)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:checked_in_count, 0)
      |> assign(:loading, true)
      |> stream(:checked_in_members, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_query = normalize_search_query(Map.get(params, "q", ""))

    socket = assign(socket, :search_query, search_query)

    # Defer check-in list and search until the WebSocket connects so the
    # static HTML response stays fast and the loading panel can render.
    socket =
      if connected?(socket) do
        socket
        |> reload_checked_in()
        |> then(fn s ->
          if searching?(search_query) do
            run_search(s, search_query)
          else
            assign(s, :search_results, [])
          end
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = normalize_search_query(query)

    path =
      if searching?(query) do
        ~p"/admin/membership-check-in/#{socket.assigns.session.id}?q=#{query}"
      else
        ~p"/admin/membership-check-in/#{socket.assigns.session.id}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear-search", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/membership-check-in/#{socket.assigns.session.id}"
     )}
  end

  def handle_event("check-in-member", %{"user-id" => user_id}, socket) do
    %{session: session, current_user: current_user} = socket.assigns

    case Ysc.Accounts.get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Member not found.")}

      user ->
        do_check_in_member(socket, session, user, current_user)
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
    user_id = socket.assigns.current_user.id

    case Scanning.authorize_membership_checkin_access!(session_id, user_id) do
      :ok ->
        csv_content = Scanning.export_membership_checkins_csv(session_id)
        encoded = Base.encode64(csv_content)

        filename =
          "membership_checkin_#{session_id}_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

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
           "You can only export membership check-in sessions you created after they are closed."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Check-in session not found.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_check_in_member(socket, session, user, current_user) do
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

  defp normalize_search_query(query) when is_binary(query),
    do: String.trim(query)

  defp normalize_search_query(_), do: ""

  defp searching?(query), do: normalize_search_query(query) != ""

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
