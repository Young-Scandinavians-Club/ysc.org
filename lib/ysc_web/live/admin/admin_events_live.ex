defmodule YscWeb.AdminEventsLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Events

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
      board_position={@current_user.board_position}
    >
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Events
        </h1>

        <.button phx-click={JS.navigate(~p"/admin/events/new")}>
          <.icon name="hero-calendar" class="w-5 h-5 -mt-1" />
          <span class="ms-1">
            New Event
          </span>
        </.button>
      </div>

      <div class="w-full pt-4">
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
            <.dropdown id="filter-events-dropdown" class="group hover:bg-zinc-100">
              <:button_block>
                <.icon
                  name="hero-funnel"
                  class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
                /> Filters
              </:button_block>

              <div class="w-full px-4 py-3">
                <.filter_form
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
                  <div class="mt-4">
                    <p class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
                      Event Date Range
                    </p>
                    <div class="space-y-2">
                      <.input
                        type="date"
                        name="date_from"
                        value={@date_from}
                        label="From"
                        id="filter-date-from"
                        phx-debounce="300"
                      />
                      <.input
                        type="date"
                        name="date_to"
                        value={@date_to}
                        label="To"
                        id="filter-date-to"
                        phx-debounce="300"
                      />
                    </div>
                  </div>
                </.filter_form>
              </div>

              <div class="px-4 py-4">
                <button
                  class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80 w-full"
                  phx-click={JS.navigate(~p"/admin/events")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </.dropdown>
          </div>
          <%!-- Mobile Card View --%>
          <div class="block md:hidden space-y-4">
            <%= for {_, event} <- @streams.events do %>
              <div class="bg-white rounded-lg border border-zinc-200 p-4 hover:shadow-md transition-shadow">
                <div
                  class="mb-3 cursor-pointer"
                  phx-click={JS.navigate(~p"/admin/events/#{event.id}/edit")}
                >
                  <h3 class="text-base font-semibold text-zinc-900 mb-2">
                    {event.title}
                  </h3>
                  <div class="space-y-1.5">
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Event Date:</span>
                      <span class="text-sm font-medium text-zinc-900">
                        {format_date(event.start_date)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Organizer:</span>
                      <span class="text-sm text-zinc-900">
                        {"#{String.capitalize(event.organizer.first_name)} #{String.capitalize(event.organizer.last_name)}"}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-zinc-600">Created:</span>
                      <span class="text-sm text-zinc-900">
                        {format_date(event.inserted_at)}
                      </span>
                    </div>
                  </div>
                </div>

                <div class="flex items-center justify-between pt-3 border-t border-zinc-200">
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

                  <div class="flex items-center gap-2">
                    <button
                      phx-click="copy-event"
                      phx-value-id={event.id}
                      data-confirm="Copy this event?"
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                    >
                      Copy
                    </button>
                    <button
                      phx-click={JS.navigate(~p"/admin/events/#{event.id}/edit")}
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                    >
                      Edit
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Mobile Pagination --%>
            <div :if={@meta} class="pt-4">
              <Flop.Phoenix.pagination
                meta={@meta}
                path={~p"/admin/events"}
                class="flex items-center justify-center py-4"
                page_list_attrs={[
                  class: "flex gap-0 order-2 justify-center items-center"
                ]}
                page_links={3}
              >
                <:previous attrs={[
                  class:
                    "order-1 flex justify-center items-center px-3 py-2 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                ]}>
                </:previous>
                <:next attrs={[
                  class:
                    "order-3 flex justify-center items-center px-3 py-2 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                ]}>
                </:next>
              </Flop.Phoenix.pagination>
            </div>
          </div>
          <%!-- Desktop Table View --%>
          <div class="hidden md:block">
            <Flop.Phoenix.table
              id="admin_events_list"
              items={@streams.events}
              meta={@meta}
              path={~p"/admin/events"}
              row_click={
                fn {_, event} -> JS.navigate(~p"/admin/events/#{event.id}/edit") end
              }
              opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
            >
              <:col :let={{_, event}} label="Title" field={:title}>
                <p class="text-sm font-semibold">
                  {event.title}
                </p>
              </:col>

              <:col :let={{_, event}} label="Event Date" field={:start_date}>
                {format_date(event.start_date)}
              </:col>

              <:col :let={{_, event}} label="Author" field={:author_name}>
                {"#{String.capitalize(event.organizer.first_name)} #{String.capitalize(event.organizer.last_name)}"}
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

              <:action :let={{_, event}} label="Action">
                <div class="flex items-center gap-3">
                  <button
                    phx-click="copy-event"
                    phx-value-id={event.id}
                    data-confirm="Copy this event?"
                    class="text-blue-600 font-semibold hover:underline cursor-pointer"
                  >
                    Copy
                  </button>
                  <button
                    phx-click={JS.navigate(~p"/admin/events/#{event.id}/edit")}
                    class="text-blue-600 font-semibold hover:underline cursor-pointer"
                  >
                    Edit
                  </button>
                </div>
              </:action>
            </Flop.Phoenix.table>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:active_page, :events)
     |> assign(:search_query, "")
     |> assign(:date_from, "")
     |> assign(:date_to, ""), temporary_assigns: [author_filter: []]}
  end

  def handle_params(params, _uri, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")

    case Events.list_events_paginated(params,
           date_from: date_from,
           date_to: date_to
         ) do
      {:ok, {events, meta}} ->
        author_filter = Events.get_all_authors()
        title_filter = Enum.find(meta.flop.filters, &(&1.field == :title))
        search_query = if title_filter, do: title_filter.value, else: ""

        {:noreply,
         socket
         |> assign(:meta, meta)
         |> assign(:author_filter, author_filter)
         |> assign(:search_query, search_query)
         |> assign(:date_from, date_from)
         |> assign(:date_to, date_to)
         |> stream(:events, events, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/events")}
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
         |> push_navigate(to: ~p"/admin/events")}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    existing_filters =
      socket.assigns.meta.flop.filters
      |> Enum.reject(&(&1.field == :title))

    new_filters =
      if q != "" do
        [%Flop.Filter{field: :title, op: :ilike, value: q} | existing_filters]
      else
        existing_filters
      end

    filter_params =
      new_filters
      |> Enum.with_index()
      |> Enum.into(%{}, fn {filter, idx} ->
        {"#{idx}",
         %{
           "field" => "#{filter.field}",
           "op" => "#{filter.op}",
           "value" => "#{filter.value}"
         }}
      end)

    date_from = socket.assigns.date_from
    date_to = socket.assigns.date_to

    new_params =
      %{"filters" => filter_params}
      |> then(fn p ->
        if date_from != "", do: Map.put(p, "date_from", date_from), else: p
      end)
      |> then(fn p ->
        if date_to != "", do: Map.put(p, "date_to", date_to), else: p
      end)

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

  defp do_clear_search(socket, input_id) do
    new_params = Map.delete(socket.assigns[:params], "search")

    {:noreply,
     socket
     |> assign(:focus_search_input, input_id)
     |> push_patch(to: ~p"/admin/events?#{new_params}")}
  end

  def handle_event("update-filter", params, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")

    params =
      params
      |> Map.delete("_target")
      |> Map.delete("date_from")
      |> Map.delete("date_to")

    updated_filters =
      Enum.reduce(params["filters"] || %{}, %{}, fn {k, v}, acc ->
        updated = maybe_update_filter(v)

        if updated["value"] in ["", nil] do
          acc
        else
          Map.put(acc, k, updated)
        end
      end)

    title_filter =
      Enum.find(socket.assigns.meta.flop.filters, &(&1.field == :title))

    final_filters =
      if title_filter && title_filter.value != "" do
        next_idx = map_size(updated_filters)

        Map.put(updated_filters, "#{next_idx}", %{
          "field" => "title",
          "op" => "ilike",
          "value" => title_filter.value
        })
      else
        updated_filters
      end

    new_params =
      Map.merge(params, %{"filters" => final_filters})
      |> then(fn p ->
        if date_from != "", do: Map.put(p, "date_from", date_from), else: p
      end)
      |> then(fn p ->
        if date_to != "", do: Map.put(p, "date_to", date_to), else: p
      end)

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

  defp format_publish_at(%DateTime{} = publish_at) do
    publish_at
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  defp format_publish_at(_), do: nil

  defp maybe_update_filter(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  defp maybe_update_filter(filter), do: filter
end
