defmodule YscWeb.AdminNewslettersLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Newsletter

  @impl true
  def mount(_params, _session, socket) do
    subscriber_count =
      Newsletter.list_subscribers(subscribed: true) |> length()

    {:ok,
     socket
     |> assign(:page_title, "Newsletters")
     |> assign(:active_page, :newsletters)
     |> assign(:subscriber_count, subscriber_count)
     |> assign(:empty, false)
     |> assign(:meta, nil)
     |> assign(:params, %{})
     |> assign(:search_query, "")
     |> assign(:date_from, "")
     |> assign(:date_to, "")
     |> stream_configure(:editions, dom_id: &"edition-#{&1.id}"),
     temporary_assigns: [creator_filter: []]}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    date_from = Map.get(params, "date_from", "")
    date_to = Map.get(params, "date_to", "")

    case Newsletter.list_paginated_editions(params,
           date_from: date_from,
           date_to: date_to
         ) do
      {:ok, {editions, meta}} ->
        creator_filter = Newsletter.get_all_creators()
        title_filter = Enum.find(meta.flop.filters, &(&1.field == :title))
        search_query = if title_filter, do: title_filter.value, else: ""

        {:noreply,
         socket
         |> assign(:meta, meta)
         |> assign(:empty, editions == [])
         |> assign(:params, params)
         |> assign(:creator_filter, creator_filter)
         |> assign(:search_query, search_query)
         |> assign(:date_from, date_from)
         |> assign(:date_to, date_to)
         |> stream(:editions, editions, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/newsletters")}
    end
  end

  @impl true
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
          Newsletters ({@subscriber_count} subscriber{if @subscriber_count == 1,
            do: "",
            else: "s"})
        </h1>

        <.link navigate={~p"/admin/newsletters/new"} class="inline-flex">
          <.button>
            <.icon name="hero-document-plus" class="w-5 h-5 -mt-1" />
            <span class="ms-1">New Newsletter</span>
          </.button>
        </.link>
      </div>

      <div class="w-full pt-4">
        <div>
          <.admin_search_bar
            id="newsletters-search-form"
            input_id="newsletters-search-input"
            name="q"
            value={@search_query}
            placeholder="Search by newsletter title..."
            on_change="search"
            phx-submit="search"
          />
        </div>

        <div class="py-6 w-full">
          <div id="admin-newsletter-filters" class="pb-4 flex">
            <.dropdown
              id="filter-newsletters-dropdown"
              class="group hover:bg-zinc-100"
            >
              <:button_block>
                <.icon
                  name="hero-funnel"
                  class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
                /> Filters
              </:button_block>

              <div :if={@meta} class="w-full px-4 py-3">
                <.filter_form
                  fields={[
                    status: [
                      label: "Status",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Draft", :draft},
                        {"Scheduled", :scheduled},
                        {"Sent", :sent}
                      ]
                    ],
                    creator_id: [
                      label: "Creator",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: @creator_filter
                    ]
                  ]}
                  meta={@meta}
                  id="newsletters-filter-form"
                >
                  <div class="mt-4">
                    <p class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
                      Date Created
                    </p>
                    <div class="space-y-2">
                      <.input
                        type="date"
                        name="date_from"
                        value={@date_from}
                        label="From"
                        id="filter-newsletters-date-from"
                        phx-debounce="300"
                      />
                      <.input
                        type="date"
                        name="date_to"
                        value={@date_to}
                        label="To"
                        id="filter-newsletters-date-to"
                        phx-debounce="300"
                      />
                    </div>
                  </div>
                </.filter_form>
              </div>

              <div class="px-4 py-4">
                <button
                  class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80 w-full"
                  phx-click={JS.navigate(~p"/admin/newsletters")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </.dropdown>
          </div>
          <%!-- Mobile Card View --%>
          <div class="block md:hidden space-y-4">
            <%= for {_, edition} <- @streams.editions do %>
              <div class="bg-white rounded-lg border border-zinc-200 p-4 hover:shadow-md transition-shadow">
                <.link
                  navigate={~p"/admin/newsletters/#{edition.id}/edit"}
                  class="block"
                >
                  <h3 class="text-base font-semibold text-zinc-900 truncate">
                    {edition.title}
                  </h3>
                  <p class="text-sm text-zinc-500 truncate mt-0.5">
                    {edition.subject}
                  </p>
                </.link>

                <div class="flex items-center gap-3 mt-2 flex-wrap">
                  <.badge type={edition_status_badge(edition.status)}>
                    {format_status(edition.status)}
                  </.badge>
                  <span class="text-sm text-zinc-500">
                    <%= cond do %>
                      <% edition.sent_at -> %>
                        Sent {format_datetime(edition.sent_at)}
                      <% edition.scheduled_at -> %>
                        Scheduled {format_datetime(edition.scheduled_at)}
                      <% true -> %>
                        Created {format_datetime(edition.inserted_at)}
                    <% end %>
                  </span>
                  <span
                    :if={edition.status == :sent && edition.sent_count > 0}
                    class="text-sm text-zinc-500"
                  >
                    {edition.sent_count} sent
                  </span>
                  <span :if={edition.creator} class="text-sm text-zinc-500">
                    by {creator_name(edition.creator)}
                  </span>
                </div>

                <div class="flex flex-wrap items-center gap-2 pt-3 mt-3 border-t border-zinc-200">
                  <.link
                    navigate={~p"/admin/newsletters/#{edition.id}/edit"}
                    class="text-blue-600 font-semibold hover:underline text-sm"
                  >
                    Edit
                  </.link>
                  <button
                    :if={edition.status == :draft}
                    type="button"
                    class="text-green-600 font-semibold hover:underline text-sm"
                    phx-click="send-now"
                    phx-value-id={edition.id}
                    data-confirm="Send this newsletter to all subscribers now? This cannot be undone."
                  >
                    Send Now
                  </button>
                  <button
                    :if={edition.status != :sent}
                    type="button"
                    class="text-red-600 font-semibold hover:underline text-sm"
                    phx-click="delete-edition"
                    phx-value-id={edition.id}
                    data-confirm="Delete this newsletter? This cannot be undone."
                  >
                    Delete
                  </button>
                </div>
              </div>
            <% end %>

            <div :if={@empty} class="py-16">
              <.empty_viking_state
                title="No newsletters yet"
                suggestion="Create one to get started."
              />
            </div>

            <div :if={@meta && !@empty} class="pt-4">
              <Flop.Phoenix.pagination
                meta={@meta}
                path={~p"/admin/newsletters"}
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
          <div class="hidden md:block w-full overflow-x-auto">
            <Flop.Phoenix.table
              id="admin_newsletters_list"
              items={@streams.editions}
              meta={@meta}
              path={~p"/admin/newsletters"}
              row_click={
                fn {_, edition} ->
                  JS.navigate(~p"/admin/newsletters/#{edition.id}/edit")
                end
              }
              opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
            >
              <:col :let={{_, edition}} label="Title" field={:title}>
                <.link
                  navigate={~p"/admin/newsletters/#{edition.id}/edit"}
                  class="font-semibold text-zinc-900 hover:underline"
                >
                  {edition.title}
                </.link>
              </:col>
              <:col :let={{_, edition}} label="Subject" field={:subject}>
                <span class="text-zinc-600">{edition.subject}</span>
              </:col>
              <:col :let={{_, edition}} label="Status" field={:status}>
                <.badge type={edition_status_badge(edition.status)}>
                  {format_status(edition.status)}
                </.badge>
              </:col>
              <:col :let={{_, edition}} label="Created" field={:inserted_at}>
                <span class="text-zinc-600">
                  {format_date(edition.inserted_at)}
                </span>
              </:col>
              <:col :let={{_, edition}} label="Sent" field={:sent_at}>
                <%= cond do %>
                  <% edition.sent_at -> %>
                    <div class="text-zinc-600">{format_date(edition.sent_at)}</div>
                    <div :if={edition.sent_count > 0} class="text-xs text-zinc-400">
                      {edition.sent_count} recipients
                    </div>
                  <% edition.scheduled_at -> %>
                    <div class="text-zinc-500 text-xs font-medium">Scheduled</div>
                    <div class="text-zinc-600 text-xs">
                      {format_datetime(edition.scheduled_at)}
                    </div>
                  <% true -> %>
                    <span class="text-zinc-400">—</span>
                <% end %>
              </:col>
              <:col :let={{_, edition}} label="Creator">
                <%= if edition.creator do %>
                  <span class="text-zinc-600">{creator_name(edition.creator)}</span>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </:col>
              <:action :let={{_, edition}} label="Actions">
                <div class="flex items-center gap-2">
                  <.link
                    navigate={~p"/admin/newsletters/#{edition.id}/edit"}
                    class="p-1.5 rounded text-blue-600 hover:bg-blue-50"
                    title="Edit"
                  >
                    <.icon name="hero-pencil-square" class="w-4 h-4" />
                  </.link>
                  <button
                    :if={edition.status == :draft}
                    type="button"
                    class="p-1.5 rounded text-green-600 hover:bg-green-50"
                    phx-click="send-now"
                    phx-value-id={edition.id}
                    phx-click-stop
                    data-confirm="Send this newsletter to all subscribers now? This cannot be undone."
                    title="Send now"
                  >
                    <.icon name="hero-paper-airplane" class="w-4 h-4" />
                  </button>
                  <button
                    :if={edition.status != :sent}
                    type="button"
                    class="p-1.5 rounded text-red-600 hover:bg-red-50"
                    phx-click="delete-edition"
                    phx-value-id={edition.id}
                    phx-click-stop
                    data-confirm="Delete this newsletter? This cannot be undone."
                    title="Delete"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </:action>
            </Flop.Phoenix.table>

            <div :if={@empty} class="py-16">
              <.empty_viking_state
                title="No newsletters yet"
                suggestion="Create one to get started."
              />
            </div>

            <Flop.Phoenix.pagination
              :if={@meta}
              meta={@meta}
              path={~p"/admin/newsletters"}
              class="flex items-center justify-center py-10 h-10 text-base"
              page_list_attrs={[
                class: "flex gap-0 order-2 justify-center items-center"
              ]}
              page_links={5}
            >
              <:previous attrs={[
                class:
                  "order-1 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
              ]}>
              </:previous>
              <:next attrs={[
                class:
                  "order-3 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
              ]}>
              </:next>
            </Flop.Phoenix.pagination>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  def handle_event("send-now", %{"id" => id}, socket) do
    edition = Newsletter.get_edition!(id)

    case Newsletter.send_edition(edition) do
      :ok ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Newsletter send queued.",
           title: "Newsletter"
         )
         |> push_navigate(to: ~p"/admin/newsletters")}

      {:error, :already_sent} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "This newsletter has already been sent."
         )}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Failed to queue send.")}
    end
  end

  def handle_event("delete-edition", %{"id" => id}, socket) do
    edition = Newsletter.get_edition!(id)

    case Newsletter.delete_edition(edition) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:editions, edition)
         |> YscWeb.Flash.put_toast(:info, "Newsletter deleted.",
           title: "Newsletter"
         )}

      {:error, :already_sent} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Sent newsletters cannot be deleted."
         )}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Could not delete newsletter.")}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    existing_filters =
      ((socket.assigns.meta && socket.assigns.meta.flop.filters) || [])
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

    {:noreply, push_patch(socket, to: ~p"/admin/newsletters?#{new_params}")}
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
      socket.assigns.meta &&
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

    {:noreply, push_patch(socket, to: ~p"/admin/newsletters?#{new_params}")}
  end

  defp maybe_update_filter(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  defp maybe_update_filter(filter), do: filter

  defp edition_status_badge(:draft), do: "yellow"
  defp edition_status_badge(:scheduled), do: "sky"
  defp edition_status_badge(:sent), do: "green"

  defp format_status(:draft), do: "Draft"
  defp format_status(:scheduled), do: "Scheduled"
  defp format_status(:sent), do: "Sent"

  defp format_date(nil), do: ""
  defp format_date(dt), do: Calendar.strftime(dt, "%b %d, %Y")

  defp format_datetime(nil), do: ""

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp creator_name(creator) do
    [creator.first_name, creator.last_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> then(fn name -> if name != "", do: name, else: creator.email end)
  end
end
