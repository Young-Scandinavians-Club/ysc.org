defmodule YscWeb.AdminEventCheckInLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents

  require Ysc.Logging

  alias Ysc.Events
  alias Ysc.Scanning
  alias Ysc.MessagePassingEvents

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50">
      <.admin_check_in_sticky_bar width={:wide}>
        <%!-- Back + event title --%>
        <div class="flex items-center gap-3 min-w-0">
          <.back navigate={~p"/admin/events"}>Events</.back>
          <span class="text-zinc-300 select-none hidden sm:inline">/</span>
          <h1 class="text-base font-semibold text-zinc-900 truncate hidden sm:block">
            {@event.title}
          </h1>
          <.admin_help_link
            topic="day-of/check-in"
            label="Check-in help"
            role={@admin_role}
          />
        </div>

        <.admin_check_in_counter count={@checked_in_count} total={@total_count} />

        <div class="shrink-0 flex items-center gap-2">
          <.button
            phx-click="launch-membership-checkin"
            variant="outline"
            color="zinc"
            class="hidden sm:inline-flex"
          >
            <.icon name="hero-identification" class="w-5 h-5 me-1 mt-0.5" />
            Membership Check-in
          </.button>
          <.admin_check_in_qr_scanner />
        </div>
      </.admin_check_in_sticky_bar>

      <.admin_check_in_search_section width={:wide}>
        <.admin_search_bar
          id="check-in-search-form"
          input_id="check-in-search-input"
          name="q"
          value={@search_query}
          placeholder="Search by name, email, ORD-xxx, or TKT-xxx…"
          on_change="search"
          debounce="300"
          clear_event="clear-search"
          phx-hook="EventCheckInKeyboard"
        />
        <.admin_check_in_keyboard_hints />
      </.admin_check_in_search_section>

      <.admin_check_in_content width={:wide}>
        <%= if @loading do %>
          <.admin_loading_panel />
        <% else %>
          <%!-- Empty state --%>
          <.admin_icon_empty_state
            :if={@total_count == 0 || @filtered_total == 0}
            icon="hero-ticket"
            title={
              if @search_query != "",
                do: "No tickets match your search",
                else: "No confirmed tickets for this event"
            }
            description={
              if @search_query != "",
                do: "Try a different name, email, or reference ID",
                else: nil
            }
          />

          <%!-- Pending tickets --%>
          <div :if={@filtered_total > 0}>
            <div class="flex items-center justify-between mb-3">
              <.admin_section_heading
                count={@total_count - @checked_in_count}
                badge_tone={:zinc}
              >
                Pending
              </.admin_section_heading>
            </div>

            <div :if={@total_count - @checked_in_count == 0}>
              <.admin_icon_empty_state
                variant={:success}
                icon="hero-check-circle"
                title="All attendees checked in!"
              />
            </div>

            <%!-- Desktop: table with order grouping --%>
            <div
              :if={@total_count - @checked_in_count > 0}
              class="hidden md:block bg-white rounded border border-zinc-200"
            >
              <.admin_event_check_in_table_header />

              <div id="pending-groups" phx-update="stream">
                <div :for={{dom_id, group} <- @streams.pending_groups} id={dom_id}>
                  <.admin_event_check_in_order_group_header
                    order_ref={group.order_ref}
                    ticket_count={length(group.tickets)}
                    order_id={group.order_id}
                  />
                  <%!-- Ticket rows --%>
                  <div
                    :for={ticket <- group.tickets}
                    data-checkin-row
                    class="grid grid-cols-12 gap-4 px-4 py-3 border-b border-zinc-100 hover:bg-zinc-50/60 transition-all duration-100 ease-out items-center last:border-0"
                  >
                    <div class="col-span-1 flex items-center justify-center gap-1.5">
                      <button
                        phx-click="toggle-check-in"
                        phx-value-ticket-id={ticket.id}
                        data-checkin-btn
                        class="w-5 h-5 rounded border-2 border-zinc-300 hover:border-emerald-500 hover:bg-emerald-50 transition-colors flex items-center justify-center"
                        aria-label="Mark as checked in"
                      ></button>
                      <span
                        class="checkin-kbd-badge hidden select-none gap-0.5"
                        hidden
                      ></span>
                    </div>
                    <div class="col-span-3">
                      <p class="text-sm font-medium text-zinc-900">
                        {attendee_name(ticket)}
                      </p>
                    </div>
                    <div class="col-span-2">
                      <p class="text-sm text-zinc-600 truncate">
                        {attendee_email(ticket)}
                      </p>
                    </div>
                    <div class="col-span-2">
                      <.badge :if={ticket.ticket_tier} type="sky">
                        {ticket.ticket_tier.name}
                      </.badge>
                    </div>
                    <div class="col-span-2">
                      <span class="text-xs font-mono text-zinc-500 whitespace-nowrap">
                        {ticket.reference_id}
                      </span>
                    </div>
                    <div class="col-span-2">
                      <.tooltip
                        :if={ticket.ticket_order}
                        tooltip_text={ticket.ticket_order.reference_id}
                      >
                        <span class="text-xs font-mono text-zinc-400 hover:text-zinc-600 cursor-default whitespace-nowrap">
                          {short_ref(ticket.ticket_order.reference_id)}
                        </span>
                      </.tooltip>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Mobile: card list --%>
            <div
              :if={@total_count - @checked_in_count > 0}
              class="md:hidden space-y-3"
            >
              <div id="pending-groups-mobile" phx-update="stream">
                <div
                  :for={{dom_id, group} <- @streams.pending_groups}
                  id={"mobile-#{dom_id}"}
                  class="bg-white rounded border border-zinc-200 overflow-hidden"
                >
                  <.admin_event_check_in_order_group_header
                    variant={:mobile}
                    order_ref={group.order_ref}
                    ticket_count={length(group.tickets)}
                    order_id={group.order_id}
                  />
                  <div
                    :for={ticket <- group.tickets}
                    data-checkin-row
                    class="flex items-center justify-between px-4 py-3 border-b border-zinc-100 last:border-0 transition-all duration-100 ease-out"
                  >
                    <div class="min-w-0 flex-1 mr-3">
                      <p class="text-sm font-medium text-zinc-900">
                        {attendee_name(ticket)}
                      </p>
                      <p class="text-xs text-zinc-500 truncate">
                        {attendee_email(ticket)}
                      </p>
                      <div class="flex items-center gap-2 mt-1">
                        <.badge :if={ticket.ticket_tier} type="sky">
                          {ticket.ticket_tier.name}
                        </.badge>
                        <span class="text-xs font-mono text-zinc-400">
                          {ticket.reference_id}
                        </span>
                      </div>
                    </div>
                    <button
                      phx-click="toggle-check-in"
                      phx-value-ticket-id={ticket.id}
                      data-checkin-btn
                      class="shrink-0 border border-zinc-300 hover:border-emerald-500 hover:bg-emerald-50 hover:text-emerald-700 text-zinc-400 transition-colors rounded px-2.5 py-1.5 text-xs font-medium flex items-center gap-1"
                      aria-label="Mark as checked in"
                    >
                      <.icon name="hero-check" class="w-3.5 h-3.5" /> Check in
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Checked-in section --%>
          <div :if={@checked_in_count > 0}>
            <div class="flex items-center mb-3">
              <.admin_section_heading
                count={@checked_in_count}
                badge_tone={:emerald}
              >
                Checked In
              </.admin_section_heading>
            </div>

            <%!-- Desktop --%>
            <div class="hidden md:block bg-white rounded border border-zinc-200">
              <div id="checked-in-tickets" phx-update="stream">
                <div
                  :for={{dom_id, ticket} <- @streams.checked_in_tickets}
                  id={dom_id}
                  class="grid grid-cols-12 gap-4 px-4 py-3 border-b border-zinc-100 items-center last:border-0 opacity-60 bg-zinc-50/50"
                >
                  <div class="col-span-1 flex justify-center">
                    <.tooltip tooltip_text="Undo check-in">
                      <button
                        phx-click="toggle-check-in"
                        phx-value-ticket-id={ticket.id}
                        class="w-5 h-5 rounded border-2 border-emerald-500 bg-emerald-500 hover:bg-red-500 hover:border-red-500 transition-colors flex items-center justify-center group"
                        aria-label="Undo check-in"
                      >
                        <.icon
                          name="hero-check"
                          class="w-3 h-3 text-white group-hover:hidden"
                        />
                        <.icon
                          name="hero-x-mark"
                          class="w-3 h-3 text-white hidden group-hover:block"
                        />
                      </button>
                    </.tooltip>
                  </div>
                  <div class="col-span-3">
                    <p class="text-sm font-medium text-zinc-400 line-through">
                      {attendee_name(ticket)}
                    </p>
                  </div>
                  <div class="col-span-2">
                    <p class="text-sm text-zinc-400 truncate">
                      {attendee_email(ticket)}
                    </p>
                  </div>
                  <div class="col-span-2">
                    <.badge :if={ticket.ticket_tier} type="default">
                      {ticket.ticket_tier.name}
                    </.badge>
                  </div>
                  <div class="col-span-2">
                    <span class="text-xs font-mono text-zinc-400 whitespace-nowrap">
                      {ticket.reference_id}
                    </span>
                  </div>
                  <div class="col-span-2">
                    <.tooltip_special :if={ticket.checked_in_at}>
                      <.icon
                        name="hero-clock"
                        class="w-3.5 h-3.5 text-zinc-400 cursor-default"
                      />
                      <:tooltip_body>
                        Checked in:
                        <span
                          id={"checkin-time-#{ticket.id}"}
                          phx-hook="LocalTime"
                          phx-update="ignore"
                          data-utc-time={DateTime.to_iso8601(ticket.checked_in_at)}
                        >
                          {format_checkin_time(ticket.checked_in_at)}
                        </span>
                      </:tooltip_body>
                    </.tooltip_special>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Mobile --%>
            <div class="md:hidden space-y-2 opacity-60">
              <div id="checked-in-tickets-mobile" phx-update="stream">
                <div
                  :for={{dom_id, ticket} <- @streams.checked_in_tickets}
                  id={"mobile-checked-#{dom_id}"}
                  class="bg-white rounded border border-zinc-200 overflow-hidden"
                >
                  <div class="flex items-center justify-between px-4 py-3">
                    <div class="min-w-0 flex-1 mr-3">
                      <p class="text-sm font-medium text-zinc-400 line-through">
                        {attendee_name(ticket)}
                      </p>
                      <p class="text-xs text-zinc-400 truncate">
                        {attendee_email(ticket)}
                      </p>
                      <div class="flex items-center gap-2 mt-1">
                        <.badge :if={ticket.ticket_tier} type="default">
                          {ticket.ticket_tier.name}
                        </.badge>
                        <span class="text-xs font-mono text-zinc-400">
                          {ticket.reference_id}
                        </span>
                      </div>
                    </div>
                    <button
                      phx-click="toggle-check-in"
                      phx-value-ticket-id={ticket.id}
                      class="shrink-0 border border-emerald-300 bg-emerald-50 text-emerald-700 hover:bg-red-50 hover:border-red-300 hover:text-red-600 transition-colors rounded px-2.5 py-1.5 text-xs font-medium flex items-center gap-1"
                      aria-label="Undo check-in"
                    >
                      <.icon name="hero-check" class="w-3.5 h-3.5" /> Undo
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </.admin_check_in_content>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"id" => event_id}, _session, socket) do
    if connected?(socket) do
      Scanning.subscribe_checkin(event_id)
    end

    event = Events.get_event!(event_id)

    {:ok,
     socket
     |> assign(:page_title, "Check-in: #{event.title}")
     |> assign(:active_page, :events)
     |> assign(:event, event)
     |> assign(:search_query, "")
     |> assign(:loading, true)
     |> assign(:checked_in_count, 0)
     |> assign(:total_count, 0)
     |> assign(:filtered_total, 0)
     |> assign(:scan_session, nil)
     |> assign(:ticket_by_id, %{})
     |> assign(:pending_groups_by_id, %{})
     |> stream(:pending_groups, [])
     |> stream(:checked_in_tickets, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = Map.get(params, "q", "")

    socket =
      socket
      |> assign(:search_query, search)
      |> assign_scan_session_from_params(params)

    # Defer ticket loading until the WebSocket connects so the static HTML
    # response stays fast and the loading panel can render on first paint.
    if connected?(socket) do
      {:noreply, reload_tickets(socket, search)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("launch-scanner", _params, socket) do
    %{event: event, current_user: current_user} = socket.assigns

    session_name =
      "#{event.title} – #{Calendar.strftime(Date.utc_today(), "%b %-d, %Y")}"

    case Scanning.get_or_create_open_session_for_event(event.id, :event, %{
           name: session_name,
           type: :event,
           event_id: event.id,
           created_by_id: current_user.id
         }) do
      {:ok, session} ->
        {:noreply,
         push_navigate(socket, to: ~p"/admin/scanner?resume=#{session.id}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not start scan session. Please try again."
         )}
    end
  end

  def handle_event("launch-membership-checkin", _params, socket) do
    %{event: event, current_user: current_user} = socket.assigns

    session_name =
      "#{event.title} – Membership – #{Calendar.strftime(Date.utc_today(), "%b %-d, %Y")}"

    case Scanning.get_or_create_open_session_for_event(
           event.id,
           :event_membership,
           %{
             name: session_name,
             type: :event_membership,
             event_id: event.id,
             created_by_id: current_user.id
           }
         ) do
      {:ok, session} ->
        {:noreply,
         push_navigate(socket, to: ~p"/admin/membership-check-in/#{session.id}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not start membership check-in session. Please try again."
         )}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/events/#{socket.assigns.event.id}/check-in?q=#{q}"
     )}
  end

  def handle_event("clear-search", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/events/#{socket.assigns.event.id}/check-in"
     )}
  end

  def handle_event("toggle-check-in", %{"ticket-id" => ticket_id}, socket) do
    ticket = fetch_ticket(ticket_id, socket)

    cond do
      is_nil(ticket) ->
        {:noreply, put_flash(socket, :error, "Ticket not found.")}

      ticket.checked_in ->
        do_undo_check_in(socket, ticket)

      true ->
        do_check_in(socket, ticket)
    end
  end

  def handle_event("check-in-order", %{"order-id" => order_id}, socket) do
    {session, socket} = get_or_create_session(socket)

    if is_nil(session) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Could not start a check-in session. Please try again."
       )}
    else
      case Scanning.check_in_order(session, order_id) do
        {:ok, :group_checked_in, count} ->
          {:noreply,
           socket
           |> reload_tickets(socket.assigns.search_query)
           |> put_flash(
             :info,
             "Checked in #{count} ticket#{if count != 1, do: "s"}."
           )}

        {:error, _type, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(
        {Scanning, %MessagePassingEvents.TicketCheckedIn{ticket: ticket, event_id: eid}},
        socket
      ) do
    socket =
      if eid == socket.assigns.event.id do
        apply_ticket_checked_in(socket, ticket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {Scanning, %MessagePassingEvents.TicketCheckInUndone{ticket: ticket, event_id: eid}},
        socket
      ) do
    socket =
      if eid == socket.assigns.event.id do
        apply_ticket_unchecked(socket, ticket)
      else
        socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp reload_tickets(socket, search) do
    event_id = socket.assigns.event.id
    tickets = Scanning.list_event_checkin_tickets(event_id, search)

    {checked_in_count, total_count} =
      if search in [nil, ""] do
        {Enum.count(tickets, & &1.checked_in), length(tickets)}
      else
        Scanning.event_checkin_counts(event_id)
      end

    pending = Enum.filter(tickets, &(!&1.checked_in))
    checked_in = Enum.filter(tickets, & &1.checked_in)
    pending_groups = build_pending_groups(pending)

    socket
    |> assign(:loading, false)
    |> assign(:checked_in_count, checked_in_count)
    |> assign(:total_count, total_count)
    |> assign(:filtered_total, length(tickets))
    |> assign(:ticket_by_id, Map.new(tickets, &{&1.id, &1}))
    |> assign(:pending_groups_by_id, Map.new(pending_groups, &{&1.id, &1}))
    |> stream(:pending_groups, pending_groups, reset: true)
    |> stream(:checked_in_tickets, checked_in, reset: true)
  end

  defp build_pending_groups(pending_tickets) do
    pending_tickets
    |> Enum.group_by(& &1.ticket_order_id)
    |> Enum.map(fn {order_id, tickets} ->
      order_ref =
        case List.first(tickets) do
          %{ticket_order: %{reference_id: ref}} when not is_nil(ref) -> ref
          _ -> "Unknown order"
        end

      %{
        id: "group-#{order_id || :erlang.unique_integer([:positive])}",
        order_id: order_id,
        order_ref: order_ref,
        tickets: tickets
      }
    end)
    |> Enum.sort_by(& &1.order_ref)
  end

  defp do_check_in(socket, ticket) do
    {session, socket} = get_or_create_session(socket)

    if is_nil(session) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Could not start a check-in session. Please try again."
       )}
    else
      case Scanning.check_in_single(session, ticket.id) do
        {:ok, {db_ticket, _record}} ->
          updated_ticket = %{
            ticket
            | checked_in: true,
              checked_in_at: db_ticket.checked_in_at
          }

          {:noreply, apply_ticket_checked_in(socket, updated_ticket)}

        {:error, _type, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    end
  end

  defp do_undo_check_in(socket, ticket) do
    case Scanning.undo_check_in(ticket.id, socket.assigns.event.id) do
      {:ok, updated} ->
        updated_ticket = %{
          ticket
          | checked_in: false,
            checked_in_at: updated.checked_in_at
        }

        {:noreply, apply_ticket_unchecked(socket, updated_ticket)}

      {:error, _type, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to undo check-in.")}
    end
  end

  defp get_or_create_session(socket) do
    case socket.assigns.scan_session do
      nil ->
        event = socket.assigns.event
        user = socket.assigns.current_user

        case Scanning.get_or_create_open_session_for_event(event.id, :event, %{
               name: "Manual Check-in: #{event.title}",
               type: :event,
               event_id: event.id,
               created_by_id: user.id
             }) do
          {:ok, session} ->
            {session, assign(socket, :scan_session, session)}

          {:error, changeset} ->
            Ysc.Logging.error("Failed to create manual check-in session",
              extra: %{
                event_id: event.id,
                errors: inspect(changeset.errors)
              }
            )

            {nil, socket}
        end

      session ->
        {session, socket}
    end
  end

  defp assign_scan_session_from_params(socket, %{
         "scan_session_id" => session_id
       }) do
    event_id = socket.assigns.event.id

    case Scanning.get_session!(session_id) do
      %{event_id: ^event_id, type: :event, closed_at: nil} = session ->
        assign(socket, :scan_session, session)

      _ ->
        socket
    end
  rescue
    Ecto.NoResultsError ->
      socket
  end

  defp assign_scan_session_from_params(socket, _params), do: socket

  defp fetch_ticket(ticket_id, socket) do
    case Map.get(socket.assigns.ticket_by_id, ticket_id) do
      %{} = ticket ->
        ticket

      nil ->
        fetch_ticket_from_db(ticket_id)
    end
  end

  defp fetch_ticket_from_db(ticket_id) do
    case Ysc.Repo.get(Ysc.Events.Ticket, ticket_id) do
      nil ->
        nil

      ticket ->
        Ysc.Repo.preload(ticket, [
          :registration,
          :user,
          :ticket_tier,
          :ticket_order
        ])
    end
  end

  defp apply_ticket_checked_in(socket, ticket) do
    case Map.get(socket.assigns.ticket_by_id, ticket.id) do
      %{checked_in: true} ->
        socket

      _ ->
        do_apply_ticket_checked_in(socket, ticket)
    end
  end

  defp apply_ticket_unchecked(socket, ticket) do
    case Map.get(socket.assigns.ticket_by_id, ticket.id) do
      %{checked_in: false} ->
        socket

      _ ->
        do_apply_ticket_unchecked(socket, ticket)
    end
  end

  defp do_apply_ticket_checked_in(socket, ticket) do
    search = socket.assigns.search_query

    socket =
      if ticket_in_current_view?(socket, ticket, search) do
        socket
        |> remove_ticket_from_pending(ticket)
        |> stream_insert(:checked_in_tickets, ticket)
      else
        socket
      end

    socket
    |> bump_checked_in_count(1, search)
    |> assign(:ticket_by_id, Map.put(socket.assigns.ticket_by_id, ticket.id, ticket))
  end

  defp do_apply_ticket_unchecked(socket, ticket) do
    search = socket.assigns.search_query

    socket =
      if ticket_in_current_view?(socket, ticket, search) do
        socket
        |> stream_delete(:checked_in_tickets, ticket)
        |> add_ticket_to_pending(ticket)
      else
        socket
      end

    socket
    |> bump_checked_in_count(-1, search)
    |> assign(:ticket_by_id, Map.put(socket.assigns.ticket_by_id, ticket.id, ticket))
  end

  defp ticket_in_current_view?(socket, ticket, search) do
    Map.has_key?(socket.assigns.ticket_by_id, ticket.id) or
      ticket_matches_search?(ticket, search)
  end

  defp ticket_matches_search?(_ticket, search) when search in [nil, ""], do: true

  defp ticket_matches_search?(ticket, search) when is_binary(search) do
    search_term = String.downcase(search)

    fields =
      [
        attendee_name(ticket),
        attendee_email(ticket),
        ticket.reference_id,
        ticket.ticket_order && ticket.ticket_order.reference_id
      ]
      |> Enum.reject(&is_nil/1)

    Enum.any?(fields, fn field ->
      field
      |> String.downcase()
      |> String.contains?(search_term)
    end)
  end

  defp remove_ticket_from_pending(socket, ticket) do
    group_id = pending_group_id(ticket.ticket_order_id)

    case Map.get(socket.assigns.pending_groups_by_id, group_id) do
      nil ->
        socket

      group ->
        remaining = Enum.reject(group.tickets, &(&1.id == ticket.id))

        if remaining == [] do
          socket
          |> stream_delete(:pending_groups, group)
          |> assign(
            :pending_groups_by_id,
            Map.delete(socket.assigns.pending_groups_by_id, group_id)
          )
        else
          updated_group = %{group | tickets: remaining}

          socket
          |> stream_insert(:pending_groups, updated_group)
          |> assign(
            :pending_groups_by_id,
            Map.put(socket.assigns.pending_groups_by_id, group_id, updated_group)
          )
        end
    end
  end

  defp add_ticket_to_pending(socket, ticket) do
    group_id = pending_group_id(ticket.ticket_order_id)

    case Map.get(socket.assigns.pending_groups_by_id, group_id) do
      nil ->
        order_ref =
          case ticket.ticket_order do
            %{reference_id: ref} when not is_nil(ref) -> ref
            _ -> "Unknown order"
          end

        group = %{
          id: group_id,
          order_id: ticket.ticket_order_id,
          order_ref: order_ref,
          tickets: [ticket]
        }

        socket
        |> stream_insert(:pending_groups, group)
        |> assign(:pending_groups_by_id, Map.put(socket.assigns.pending_groups_by_id, group_id, group))

      group ->
        updated_group = %{group | tickets: [ticket | group.tickets]}

        socket
        |> stream_insert(:pending_groups, updated_group)
        |> assign(
          :pending_groups_by_id,
          Map.put(socket.assigns.pending_groups_by_id, group_id, updated_group)
        )
    end
  end

  defp pending_group_id(order_id),
    do: "group-#{order_id || :erlang.unique_integer([:positive])}"

  defp bump_checked_in_count(socket, delta, search)
       when search in [nil, ""] do
    assign(socket, :checked_in_count, socket.assigns.checked_in_count + delta)
  end

  defp bump_checked_in_count(socket, _delta, _search) do
    {checked_in_count, total_count} =
      Scanning.event_checkin_counts(socket.assigns.event.id)

    socket
    |> assign(:checked_in_count, checked_in_count)
    |> assign(:total_count, total_count)
  end

  defp attendee_name(%{
         registration: %Ysc.Events.TicketDetail{first_name: fn_, last_name: ln}
       })
       when not is_nil(fn_),
       do: "#{fn_} #{ln}"

  defp attendee_name(%{user: %{first_name: fn_, last_name: ln}})
       when not is_nil(fn_),
       do: "#{fn_} #{ln}"

  defp attendee_name(_), do: "Unknown"

  defp attendee_email(%{registration: %Ysc.Events.TicketDetail{email: email}})
       when not is_nil(email),
       do: email

  defp attendee_email(%{user: %{email: email}}) when not is_nil(email),
    do: email

  defp attendee_email(_), do: ""

  defp short_ref(nil), do: "—"
  defp short_ref(ref), do: ref

  defp format_checkin_time(dt) do
    Calendar.strftime(dt, "%b %-d, %H:%M UTC")
  end
end
