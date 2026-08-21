defmodule YscWeb.AdminEventsLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Ysc.Accounts.UserDisplay
  alias Phoenix.LiveView.JS

  alias Ysc.Events
  alias Ysc.Scanning
  alias YscWeb.Admin.EditingPresence
  alias YscWeb.AdminCheckInPaths

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex justify-between py-6">
        <div class="flex items-center gap-2">
          <.admin_page_title>Events</.admin_page_title>
          <.admin_help_link
            topic="events/create"
            label="How to create an event"
            role={@admin_role}
          />
        </div>

        <div class="flex items-center gap-3">
          <.button navigate={~p"/admin/scanner"}>
            <.icon name="hero-qr-code" class="w-5 h-5" /> Check-in &amp; Scan
          </.button>

          <.button navigate={~p"/admin/events/new"}>
            <.icon name="hero-calendar" class="w-5 h-5" /> New Event
          </.button>
        </div>
      </div>

      <div class="w-full pt-4">
        <%!-- Tab navigation --%>
        <.admin_tabs id="events-tabs" aria_label="Events tabs">
          <%= for {label, tab_key} <- [{"Upcoming", :upcoming}, {"Drafts", :drafts}, {"Past", :past}, {"All", :all}] do %>
            <.admin_tab
              active={@active_tab == tab_key}
              patch={~p"/admin/events?#{Map.put(@params, "tab", tab_key)}"}
            >
              {label}
            </.admin_tab>
          <% end %>
        </.admin_tabs>

        <div>
          <.admin_search_bar
            id="events-search-form"
            input_id="events-search-input"
            name="q"
            value={@search_query}
            placeholder="Search by event name..."
            on_change="search"
            phx-submit="search"
          />
        </div>
        <div class="py-6 w-full">
          <div id="admin-event-filters" class="pb-4 flex">
            <.admin_filter_dropdown
              id="filter-events-dropdown"
              clear_patch={~p"/admin/events"}
              clear_id="admin-events-clear-filters"
            >
              <.filter_form
                :if={@meta}
                fields={[
                  state: [
                    label: "State",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: [
                      {"Published", :published},
                      {"Draft", :draft},
                      {"Scheduled", :scheduled},
                      {"Cancelled", :cancelled}
                    ]
                  ],
                  organizer_id: [
                    label: "Organizer",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: @author_filter
                  ]
                ]}
                meta={@meta}
                id="events-filter-form"
              >
                <.admin_filter_date_range
                  id="filter-events"
                  label="Event Date Range"
                  date_from={@date_from}
                  date_to={@date_to}
                />
              </.filter_form>
            </.admin_filter_dropdown>
          </div>

          <.admin_table_skeleton
            :if={is_nil(@meta)}
            id="admin-events-loading"
            rows={8}
            columns={5}
          />

          <div :if={@meta}>
            <%!-- Mobile Card View --%>
            <.admin_mobile_list id="admin-events-mobile">
              <.admin_mobile_list_card
                :for={{_, event} <- @streams.events}
                id={"admin-event-card-#{event.id}"}
                footer_align={:between}
              >
                <.link
                  navigate={~p"/admin/events/#{event.id}/edit"}
                  class="mb-3 cursor-pointer block"
                >
                  <div class="mb-2 flex items-center gap-1.5">
                    <h3 class="text-base font-semibold text-zinc-900 min-w-0 flex-1 truncate">
                      {event.title}
                    </h3>
                    <.presence_avatars editors={@editors_by_event[event.id] || []} />
                  </div>
                  <div class="space-y-1.5">
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Event Date:</span>
                      <span class="text-sm font-medium text-zinc-900">
                        {format_date(event.start_date)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Capacity:</span>
                      <span class="text-sm font-medium text-zinc-900">
                        {format_capacity(event)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Organizer:</span>
                      <span class="text-sm text-zinc-900">
                        {UserDisplay.full_name(event.organizer)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Created:</span>
                      <span class="text-sm text-zinc-900">
                        {format_date(event.inserted_at)}
                      </span>
                    </div>
                  </div>
                </.link>

                <:footer>
                  <div>
                    <%= if event.state == :scheduled && event.publish_at do %>
                      <.tooltip tooltip_text={"Publishes on #{format_publish_at(event.publish_at)}"}>
                        <.badge type={event_state_to_badge_style(event.state)}>
                          {String.capitalize("#{event.state}")}
                        </.badge>
                      </.tooltip>
                    <% else %>
                      <.badge type={event_state_to_badge_style(event.state)}>
                        {String.capitalize("#{event.state}")}
                      </.badge>
                    <% end %>
                  </div>

                  <.event_actions_dropdown
                    event={event}
                    menu_id={"event-actions-mob-#{event.id}"}
                    check_in_path={
                      AdminCheckInPaths.path_for_event(
                        event.id,
                        @open_check_in_sessions
                      )
                    }
                  />
                </:footer>
              </.admin_mobile_list_card>
              <%!-- Mobile Pagination --%>
              <div class="pt-4">
                <.admin_flop_pagination
                  meta={@meta}
                  path={~p"/admin/events?#{non_flop_params(@params)}"}
                  density={:compact}
                />
              </div>
            </.admin_mobile_list>
            <%!-- Desktop Table View --%>
            <div class="hidden md:block">
              <Flop.Phoenix.table
                id="admin_events_list"
                items={@streams.events}
                meta={@meta}
                path={~p"/admin/events?#{non_flop_params(@params)}"}
                row_click={
                  fn {_, event} ->
                    JS.navigate(~p"/admin/events/#{event.id}/edit")
                  end
                }
                opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
              >
                <:col :let={{_, event}} label="Title" field={:title}>
                  <div class="text-sm font-semibold flex items-center gap-1.5">
                    <span>{event.title}</span>
                    <.presence_avatars editors={@editors_by_event[event.id] || []} />
                  </div>
                </:col>

                <:col :let={{_, event}} label="Date" field={:start_date}>
                  {format_date(event.start_date)}
                </:col>

                <:col :let={{_, event}} label="Registrations" field={:capacity}>
                  {format_capacity(event)}
                </:col>

                <:col :let={{_, event}} label="Author" field={:author_name}>
                  {UserDisplay.full_name(event.organizer)}
                </:col>

                <:col :let={{_, event}} label="State" field={:state}>
                  <%= if event.state == :scheduled && event.publish_at do %>
                    <.tooltip tooltip_text={"Publishes on #{format_publish_at(event.publish_at)}"}>
                      <.badge type={event_state_to_badge_style(event.state)}>
                        {String.capitalize("#{event.state}")}
                      </.badge>
                    </.tooltip>
                  <% else %>
                    <.badge type={event_state_to_badge_style(event.state)}>
                      {String.capitalize("#{event.state}")}
                    </.badge>
                  <% end %>
                </:col>

                <:col :let={{_, event}} label="Created" field={:inserted_at}>
                  {format_date(event.inserted_at)}
                </:col>

                <:action :let={{_, event}}>
                  <.event_actions_dropdown
                    event={event}
                    menu_id={"event-actions-dt-#{event.id}"}
                    check_in_path={
                      AdminCheckInPaths.path_for_event(
                        event.id,
                        @open_check_in_sessions
                      )
                    }
                  />
                </:action>
              </Flop.Phoenix.table>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  attr :event, :map, required: true
  attr :menu_id, :string, required: true
  attr :check_in_path, :string, required: true

  def event_actions_dropdown(assigns) do
    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Event actions">
      <.dropdown_menu_item
        :if={@event.state in [:published, :scheduled]}
        id={"#{@menu_id}-view-live"}
        icon="hero-arrow-top-right-on-square"
        href={~p"/events/#{@event.id}"}
        target="_blank"
        rel="noopener noreferrer"
      >
        View live
      </.dropdown_menu_item>
      <.dropdown_menu_item
        id={"#{@menu_id}-copy"}
        icon="hero-document-duplicate"
        phx-click="copy-event"
        phx-value-id={@event.id}
        data-confirm="Copy this event?"
      >
        Copy
      </.dropdown_menu_item>
      <.dropdown_menu_item
        id={"#{@menu_id}-edit"}
        icon="hero-pencil-square"
        navigate={~p"/admin/events/#{@event.id}/edit"}
      >
        Edit
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={@event.state in [:published, :scheduled]}
        id={"#{@menu_id}-check-in"}
        icon="hero-qr-code"
        tone={:success}
        navigate={@check_in_path}
      >
        Check in
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  def mount(_params, _session, socket) do
    editors_by_event =
      if connected?(socket) do
        EditingPresence.subscribe(:event)

        EditingPresence.editors_by_resource(
          :event,
          socket.assigns.current_user.id
        )
      else
        %{}
      end

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:active_page, :events)
     |> assign(:active_tab, :upcoming)
     |> assign(:params, %{})
     |> assign(:search_query, "")
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> assign(:open_check_in_sessions, %{})
     |> assign(:meta, nil)
     |> assign(:author_filter, [])
     |> assign(:editors_by_event, editors_by_event)
     |> assign(:events_by_id, %{})
     |> stream(:events, [], reset: true)}
  end

  # Content inside a `phx-update="stream"` container only updates via
  # explicit stream operations. `editors_by_event` is cheap to recompute
  # (in-memory Presence.list, no DB), but we only force a row re-render for
  # events whose presence actually changed *and* are currently visible on
  # this page — everything else needs neither a DB hit nor a stream touch.
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload},
        socket
      ) do
    editors_by_event =
      EditingPresence.editors_by_resource(
        :event,
        socket.assigns.current_user.id
      )

    changed_ids =
      payload
      |> EditingPresence.diff_resource_ids()
      |> Enum.filter(&Map.has_key?(socket.assigns.events_by_id, &1))

    socket =
      changed_ids
      |> Enum.reduce(socket, fn event_id, acc ->
        stream_insert(
          acc,
          :events,
          Map.fetch!(acc.assigns.events_by_id, event_id)
        )
      end)
      |> assign(:editors_by_event, editors_by_event)

    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")
    active_tab = parse_tab(Map.get(params, "tab", "upcoming"))

    if connected?(socket) do
      case Events.list_events_paginated(params,
             date_from: date_from,
             date_to: date_to,
             tab: active_tab
           ) do
        {:ok, {events, meta}} ->
          search_query = title_search_query(meta)

          event_ids = Enum.map(events, & &1.id)

          open_check_in_sessions =
            Scanning.get_open_check_in_sessions_by_event_id(event_ids)

          {:noreply,
           socket
           |> assign_new(:author_filter, &Events.get_all_authors/0)
           |> assign(:meta, meta)
           |> assign(:params, params)
           |> assign(:active_tab, active_tab)
           |> assign(:search_query, search_query)
           |> assign(:date_from, date_from)
           |> assign(:date_to, date_to)
           |> assign(:open_check_in_sessions, open_check_in_sessions)
           |> assign(:events_by_id, Map.new(events, &{&1.id, &1}))
           |> stream(:events, events, reset: true)}

        {:error, _meta} ->
          {:noreply, push_patch(socket, to: ~p"/admin/events")}
      end
    else
      {:noreply,
       socket
       |> assign(:params, params)
       |> assign(:active_tab, active_tab)
       |> assign(:date_from, date_from)
       |> assign(:date_to, date_to)}
    end
  end

  def handle_event("copy-event", %{"id" => id}, socket) do
    event = Events.get_event!(id)

    case Events.copy_event(event) do
      {:ok, new_event} ->
        {:noreply,
         push_navigate(socket, to: ~p"/admin/events/#{new_event.id}/edit")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to copy event")
         |> push_patch(to: ~p"/admin/events")}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    new_params =
      %{
        "filters" => build_title_search_filter_params(socket.assigns.meta, q),
        "tab" => socket.assigns.active_tab
      }
      |> merge_date_range_into_params(
        socket.assigns.date_from,
        socket.assigns.date_to
      )

    {:noreply,
     socket
     |> assign(:focus_search_input, nil)
     |> push_patch(to: ~p"/admin/events?#{new_params}")}
  end

  def handle_event("clear-search", %{"input-id" => input_id}, socket) do
    do_clear_search(socket, input_id)
  end

  def handle_event("clear-search", %{"input_id" => input_id}, socket) do
    do_clear_search(socket, input_id)
  end

  def handle_event("update-filter", params, socket) do
    new_params =
      list_filter_params(params, socket.assigns.meta, %{
        "tab" => socket.assigns.active_tab
      })

    {:noreply, push_patch(socket, to: ~p"/admin/events?#{new_params}")}
  end

  defp event_state_to_badge_style(:draft), do: "sky"
  defp event_state_to_badge_style(:scheduled), do: "yellow"
  defp event_state_to_badge_style(:published), do: "green"
  defp event_state_to_badge_style(:cancelled), do: "dark"
  defp event_state_to_badge_style(:deleted), do: "red"
  defp event_state_to_badge_style(_), do: "default"

  defp format_date(nil), do: "n/a"
  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp format_capacity(event) do
    capacity_info =
      event.capacity_info || %{registrations: 0, capacity: :unlimited}

    registrations = capacity_info.registrations || 0
    capacity = capacity_info.capacity

    case capacity do
      :unlimited -> "#{registrations} / ∞"
      cap when is_integer(cap) -> "#{registrations} / #{cap}"
      _ -> "#{registrations} / ∞"
    end
  end

  defp format_publish_at(%DateTime{} = publish_at) do
    publish_at
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  defp format_publish_at(_), do: nil

  defp do_clear_search(socket, input_id) do
    new_params = Map.delete(socket.assigns[:params], "search")

    {:noreply,
     socket
     |> assign(:focus_search_input, input_id)
     |> push_patch(to: ~p"/admin/events?#{new_params}")}
  end

  defp parse_tab("drafts"), do: :drafts
  defp parse_tab("past"), do: :past
  defp parse_tab("all"), do: :all
  defp parse_tab(_), do: :upcoming
end
