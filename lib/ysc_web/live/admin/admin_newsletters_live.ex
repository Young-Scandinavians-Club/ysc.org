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
     |> assign(:current_tab, "editions")
     |> assign(:sub_meta, nil)
     |> assign(:sub_search, "")
     |> assign(:sub_filter, "all")
     |> assign(
       :add_subscriber_form,
       to_form(%{"email" => ""}, as: :add_subscriber)
     )
     |> assign(:show_add_subscriber_modal, false)
     |> stream_configure(:editions, dom_id: &"edition-#{&1.id}")
     |> stream_configure(:subscribers, dom_id: &"subscriber-#{&1.id}"),
     temporary_assigns: [creator_filter: []]}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    current_tab = allowed_tab(Map.get(params, "tab"))
    socket = assign(socket, :current_tab, current_tab)

    socket =
      if current_tab == "subscribers" do
        sub_search = Map.get(params, "sub_q", "")
        sub_filter = Map.get(params, "subscribed_filter", "all")

        socket
        |> assign(:params, params)
        |> assign(:sub_search, sub_search)
        |> assign(:sub_filter, sub_filter)
        |> stream(:subscribers, [], reset: true)
        |> then(fn s ->
          subscriber_params = build_subscriber_flop_params(params)

          start_async(s, :load_subscribers, fn ->
            Newsletter.list_paginated_subscribers(subscriber_params)
          end)
        end)
      else
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

            socket
            |> assign(:meta, meta)
            |> assign(:empty, editions == [])
            |> assign(:params, params)
            |> assign(:creator_filter, creator_filter)
            |> assign(:search_query, search_query)
            |> assign(:date_from, date_from)
            |> assign(:date_to, date_to)
            |> stream(:editions, editions, reset: true)

          {:error, _meta} ->
            push_patch(socket, to: ~p"/admin/newsletters")
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_subscribers, {:ok, {:ok, {subscribers, meta}}}, socket) do
    {:noreply,
     socket
     |> assign(:sub_meta, meta)
     |> stream(:subscribers, subscribers, reset: true)}
  end

  @impl true
  def handle_async(:load_subscribers, {:ok, {:error, meta}}, socket) do
    {:noreply,
     socket
     |> assign(:sub_meta, meta)
     |> stream(:subscribers, [], reset: true)}
  end

  @impl true
  def handle_async(:load_subscribers, {:exit, _}, socket) do
    {:noreply, socket}
  end

  defp allowed_tab("subscribers"), do: "subscribers"
  defp allowed_tab(_), do: "editions"

  defp build_subscriber_flop_params(params) do
    base = Map.take(params, ["page", "limit", "order_by", "order_directions"])

    filters =
      []
      |> maybe_add_email_filter(Map.get(params, "sub_q"))
      |> maybe_add_subscribed_filter(Map.get(params, "subscribed_filter"))
      |> Enum.with_index()
      |> Enum.into(%{}, fn {filter, idx} ->
        {"#{idx}",
         %{
           "field" => "#{filter.field}",
           "op" => "#{filter.op}",
           "value" => filter.value
         }}
      end)

    if map_size(filters) > 0 do
      Map.put(base, "filters", filters)
    else
      base
    end
  end

  defp maybe_add_email_filter(acc, nil), do: acc
  defp maybe_add_email_filter(acc, ""), do: acc

  defp maybe_add_email_filter(acc, q) do
    # Fuzzy (substring) match: Flop's :ilike adds % wildcards via add_wildcard/1
    [%{field: :email, op: :ilike, value: q} | acc]
  end

  defp maybe_add_subscribed_filter(acc, "active"),
    do: [%{field: :subscribed, op: :==, value: "true"} | acc]

  defp maybe_add_subscribed_filter(acc, "inactive"),
    do: [%{field: :subscribed, op: :==, value: "false"} | acc]

  defp maybe_add_subscribed_filter(acc, _), do: acc

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
      <div class="py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Newsletters
        </h1>
        <p class="mt-0.5 text-sm text-zinc-500">
          {@subscriber_count} subscriber{if @subscriber_count == 1,
            do: "",
            else: "s"}
        </p>
      </div>

      <div
        id="newsletter-tabs"
        role="tablist"
        aria-label="Newsletter sections"
        class="flex gap-0 border-b border-zinc-200 mb-6"
      >
        <button
          type="button"
          role="tab"
          aria-selected={@current_tab == "editions"}
          phx-click="switch-tab"
          phx-value-tab="editions"
          class={[
            "whitespace-nowrap py-3 px-4 -mb-px border-b-2 font-medium text-sm transition-colors rounded-t",
            if(@current_tab == "editions",
              do: "border-blue-500 text-blue-600 bg-white",
              else:
                "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
            )
          ]}
        >
          Editions
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={@current_tab == "subscribers"}
          phx-click="switch-tab"
          phx-value-tab="subscribers"
          class={[
            "whitespace-nowrap py-3 px-4 -mb-px border-b-2 font-medium text-sm transition-colors rounded-t",
            if(@current_tab == "subscribers",
              do: "border-blue-500 text-blue-600 bg-white",
              else:
                "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
            )
          ]}
        >
          Subscribers
        </button>
      </div>

      <div class="w-full">
        <%!-- Editions tab: toolbar + content --%>
        <div :if={@current_tab == "editions"} class="space-y-6">
          <div class="flex flex-col sm:flex-row sm:items-center gap-4 sm:gap-3">
            <div class="min-w-0 flex-1">
              <.admin_search_bar
                id="newsletters-search-form"
                input_id="newsletters-search-input"
                name="q"
                value={@search_query}
                placeholder="Search by title..."
                on_change="search"
                phx-submit="search"
              />
            </div>
            <div class="flex items-center gap-2 flex-shrink-0">
              <div id="admin-newsletter-filters">
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
                      phx-click={JS.patch(~p"/admin/newsletters")}
                    >
                      <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" />
                      Clear filters
                    </button>
                  </div>
                </.dropdown>
              </div>
              <.link navigate={~p"/admin/newsletters/new"} class="inline-flex">
                <.button>
                  <.icon name="hero-document-plus" class="w-5 h-5 -mt-0.5" />
                  <span class="ms-1.5">New Newsletter</span>
                </.button>
              </.link>
            </div>
          </div>

          <%!-- Editions content --%>
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
                class="flex items-center justify-center py-4 text-base"
                page_list_attrs={[
                  class: "flex gap-1 order-2 justify-center items-center"
                ]}
                page_list_item_attrs={[class: "list-none"]}
                page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
                ]}
                current_page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
                ]}
                page_links={3}
              >
                <:previous attrs={[
                  class:
                    "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-left" class="w-4 h-4" />
                </:previous>
                <:next attrs={[
                  class:
                    "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-right" class="w-4 h-4" />
                </:next>
              </Flop.Phoenix.pagination>
            </div>
          </div>
          <%!-- Desktop Table View --%>
          <div class="hidden md:block py-6 w-full">
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
              class="flex items-center justify-center py-10 text-base"
              page_list_attrs={[
                class: "flex gap-1 order-2 justify-center items-center"
              ]}
              page_list_item_attrs={[class: "list-none"]}
              page_link_attrs={[
                class:
                  "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
              ]}
              current_page_link_attrs={[
                class:
                  "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
              ]}
              page_links={5}
            >
              <:previous attrs={[
                class:
                  "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
              ]}>
                <.icon name="hero-chevron-left" class="w-4 h-4" />
              </:previous>
              <:next attrs={[
                class:
                  "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
              ]}>
                <.icon name="hero-chevron-right" class="w-4 h-4" />
              </:next>
            </Flop.Phoenix.pagination>
          </div>
        </div>

        <%!-- Subscribers tab: toolbar + content --%>
        <div :if={@current_tab == "subscribers"} class="space-y-6">
          <.modal
            :if={@show_add_subscriber_modal}
            id="add-subscriber-modal"
            on_cancel={JS.push("close-add-subscriber-modal")}
            show
          >
            <h2 class="text-lg font-semibold text-zinc-800 mb-4">Add subscriber</h2>
            <.form
              for={@add_subscriber_form}
              id="add-subscriber-form"
              phx-submit="add-subscriber"
              class="mt-4"
            >
              <.input
                field={@add_subscriber_form[:email]}
                type="email"
                label="Email"
                placeholder="email@example.com"
                id="add-subscriber-email"
              />
              <div class="flex justify-end gap-2 mt-6">
                <button
                  type="button"
                  phx-click="close-add-subscriber-modal"
                  class="rounded-lg bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-200"
                >
                  Cancel
                </button>
                <.button type="submit">Add</.button>
              </div>
            </.form>
          </.modal>

          <div class="flex flex-col sm:flex-row sm:items-center gap-4 sm:gap-3">
            <div class="min-w-0 flex-1">
              <.admin_search_bar
                id="subscribers-search-form"
                input_id="subscribers-search-input"
                name="sub_q"
                value={@sub_search}
                placeholder="Search by email..."
                on_change="search-subscribers"
                phx-submit="search-subscribers"
              />
            </div>
            <div class="flex items-center gap-2 flex-shrink-0 flex-wrap">
              <span class="text-sm font-medium text-zinc-600 sr-only sm:not-sr-only">
                Status:
              </span>
              <button
                type="button"
                phx-click="filter-subscribers"
                phx-value-filter="all"
                class={[
                  "rounded px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@sub_filter == "all",
                    do: "bg-zinc-200 text-zinc-800",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                All
              </button>
              <button
                type="button"
                phx-click="filter-subscribers"
                phx-value-filter="active"
                class={[
                  "rounded px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@sub_filter == "active",
                    do: "bg-zinc-200 text-zinc-800",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                Active
              </button>
              <button
                type="button"
                phx-click="filter-subscribers"
                phx-value-filter="inactive"
                class={[
                  "rounded px-3 py-1.5 text-sm font-medium transition-colors",
                  if(@sub_filter == "inactive",
                    do: "bg-zinc-200 text-zinc-800",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                Inactive
              </button>
              <.button
                type="button"
                phx-click="open-add-subscriber-modal"
                class="ms-0 sm:ms-2"
              >
                <.icon name="hero-user-plus" class="w-5 h-5 -mt-0.5" />
                <span class="ms-1.5">Add subscriber</span>
              </.button>
            </div>
          </div>

          <%!-- Subscribers content --%>
          <div
            :if={subscribers_loading?(@sub_meta)}
            class="py-12 flex justify-center"
          >
            <.spinner />
          </div>

          <div :if={!subscribers_loading?(@sub_meta)}>
            <%!-- Mobile card view --%>
            <div class="block md:hidden space-y-4">
              <%= for {_, subscriber} <- @streams.subscribers do %>
                <div class="bg-white rounded-lg border border-zinc-200 p-4">
                  <p class="text-base font-medium text-zinc-900 truncate">
                    {subscriber.email}
                  </p>
                  <p
                    :if={subscriber_name(subscriber) != ""}
                    class="text-sm text-zinc-500 mt-0.5"
                  >
                    {subscriber_name(subscriber)}
                  </p>
                  <div class="flex items-center gap-3 mt-2 flex-wrap">
                    <.badge type={subscriber_status_badge(subscriber.subscribed)}>
                      {if subscriber.subscribed, do: "Active", else: "Inactive"}
                    </.badge>
                    <span :if={subscriber.source} class="text-xs text-zinc-400">
                      {subscriber.source}
                    </span>
                    <span
                      :if={subscriber.subscribed_at}
                      class="text-xs text-zinc-400"
                    >
                      Subscribed {format_date(subscriber.subscribed_at)}
                    </span>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 pt-3 mt-3 border-t border-zinc-200">
                    <button
                      :if={subscriber.subscribed}
                      type="button"
                      class="text-red-600 font-semibold hover:underline text-sm"
                      phx-click="remove-subscriber"
                      phx-value-email={subscriber.email}
                      data-confirm="Remove this subscriber? They will no longer receive newsletters."
                    >
                      Remove
                    </button>
                    <button
                      :if={!subscriber.subscribed}
                      type="button"
                      class="text-green-600 font-semibold hover:underline text-sm"
                      phx-click="resubscribe"
                      phx-value-email={subscriber.email}
                    >
                      Re-add
                    </button>
                  </div>
                </div>
              <% end %>

              <div
                :if={subscribers_empty?(@streams.subscribers, @sub_meta)}
                class="py-16"
              >
                <.empty_viking_state
                  title="No subscribers found"
                  suggestion={
                    if @sub_search != "" or @sub_filter != "all",
                      do: "Try changing search or filter.",
                      else: "Subscribers will appear here when they sign up."
                  }
                />
              </div>

              <div
                :if={
                  @sub_meta && !subscribers_empty?(@streams.subscribers, @sub_meta)
                }
                class="pt-4"
              >
                <Flop.Phoenix.pagination
                  meta={@sub_meta}
                  path={subscribers_list_path(@params)}
                  class="flex items-center justify-center py-4 text-base"
                  page_list_attrs={[
                    class: "flex gap-1 order-2 justify-center items-center"
                  ]}
                  page_list_item_attrs={[class: "list-none"]}
                  page_link_attrs={[
                    class:
                      "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
                  ]}
                  current_page_link_attrs={[
                    class:
                      "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
                  ]}
                  page_links={3}
                >
                  <:previous attrs={[
                    class:
                      "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                  ]}>
                    <.icon name="hero-chevron-left" class="w-4 h-4" />
                  </:previous>
                  <:next attrs={[
                    class:
                      "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                  ]}>
                    <.icon name="hero-chevron-right" class="w-4 h-4" />
                  </:next>
                </Flop.Phoenix.pagination>
              </div>
            </div>

            <%!-- Desktop table view --%>
            <div class="hidden md:block py-6 w-full">
              <Flop.Phoenix.table
                id="admin_subscribers_list"
                items={@streams.subscribers}
                meta={@sub_meta}
                path={subscribers_list_path(@params)}
                opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
              >
                <:col :let={{_, sub}} label="Email" field={:email}>
                  <span class="font-medium text-zinc-900">{sub.email}</span>
                </:col>
                <:col :let={{_, sub}} label="Name" field={:last_name}>
                  <span class="text-zinc-600">{subscriber_name(sub)}</span>
                </:col>
                <:col :let={{_, sub}} label="Status" field={:subscribed}>
                  <.badge type={subscriber_status_badge(sub.subscribed)}>
                    {if sub.subscribed, do: "Active", else: "Inactive"}
                  </.badge>
                </:col>
                <:col :let={{_, sub}} label="Source" field={:source}>
                  <span class="text-zinc-600">{sub.source || "—"}</span>
                </:col>
                <:col :let={{_, sub}} label="Subscribed" field={:subscribed_at}>
                  <span class="text-zinc-600">
                    {if sub.subscribed_at,
                      do: format_date(sub.subscribed_at),
                      else: "—"}
                  </span>
                </:col>
                <:action :let={{_, sub}} label="Actions">
                  <button
                    :if={sub.subscribed}
                    type="button"
                    class="p-1.5 rounded text-red-600 hover:bg-red-50"
                    phx-click="remove-subscriber"
                    phx-value-email={sub.email}
                    phx-click-stop
                    data-confirm="Remove this subscriber? They will no longer receive newsletters."
                    title="Remove"
                  >
                    <.icon name="hero-user-minus" class="w-4 h-4" />
                  </button>
                  <button
                    :if={!sub.subscribed}
                    type="button"
                    class="p-1.5 rounded text-green-600 hover:bg-green-50"
                    phx-click="resubscribe"
                    phx-value-email={sub.email}
                    phx-click-stop
                    title="Re-add"
                  >
                    <.icon name="hero-user-plus" class="w-4 h-4" />
                  </button>
                </:action>
              </Flop.Phoenix.table>

              <div
                :if={subscribers_empty?(@streams.subscribers, @sub_meta)}
                class="py-16"
              >
                <.empty_viking_state
                  title="No subscribers found"
                  suggestion={
                    if @sub_search != "" or @sub_filter != "all",
                      do: "Try changing search or filter.",
                      else: "Subscribers will appear here when they sign up."
                  }
                />
              </div>

              <Flop.Phoenix.pagination
                :if={@sub_meta}
                meta={@sub_meta}
                path={subscribers_list_path(@params)}
                class="flex items-center justify-center py-10 text-base"
                page_list_attrs={[
                  class: "flex gap-1 order-2 justify-center items-center"
                ]}
                page_list_item_attrs={[class: "list-none"]}
                page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
                ]}
                current_page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
                ]}
                page_links={5}
              >
                <:previous attrs={[
                  class:
                    "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-left" class="w-4 h-4" />
                </:previous>
                <:next attrs={[
                  class:
                    "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-right" class="w-4 h-4" />
                </:next>
              </Flop.Phoenix.pagination>
            </div>
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
         |> push_patch(to: ~p"/admin/newsletters")}

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

  def handle_event("open-add-subscriber-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_subscriber_modal, true)}
  end

  def handle_event("close-add-subscriber-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_subscriber_modal, false)}
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    tab = allowed_tab(tab)
    params = socket.assigns.params |> Map.put("tab", tab)
    path = ~p"/admin/newsletters?#{params}"
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("search-subscribers", %{"sub_q" => q}, socket) do
    params =
      socket.assigns.params
      |> Map.put("sub_q", q)
      |> Map.put("tab", "subscribers")
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/admin/newsletters?#{params}")}
  end

  def handle_event("filter-subscribers", %{"filter" => filter}, socket) do
    params =
      socket.assigns.params
      |> Map.put("subscribed_filter", filter)
      |> Map.put("tab", "subscribers")
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/admin/newsletters?#{params}")}
  end

  def handle_event(
        "add-subscriber",
        %{"add_subscriber" => %{"email" => email}},
        socket
      ) do
    email = String.trim(email)

    case Newsletter.subscribe(email, source: "admin_added") do
      {:ok, _subscriber} ->
        params = socket.assigns.params |> Map.put("tab", "subscribers")

        {:noreply,
         socket
         |> assign(
           :add_subscriber_form,
           to_form(%{"email" => ""}, as: :add_subscriber)
         )
         |> assign(:show_add_subscriber_modal, false)
         |> YscWeb.Flash.put_toast(:info, "Subscriber added.",
           title: "Newsletter"
         )
         |> push_patch(to: ~p"/admin/newsletters?#{params}")}

      {:error, :invalid_email} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Please enter a valid email address."
         )}

      {:error, changeset} ->
        message =
          case changeset do
            %Ecto.Changeset{} -> "Could not add subscriber."
            _ -> "Could not add subscriber."
          end

        {:noreply, YscWeb.Flash.put_toast(socket, :error, message)}
    end
  end

  def handle_event("remove-subscriber", %{"email" => email}, socket) do
    case Newsletter.unsubscribe(email) do
      {:ok, _subscriber} ->
        params = socket.assigns.params |> Map.put("tab", "subscribers")

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Subscriber removed.",
           title: "Newsletter"
         )
         |> push_patch(to: ~p"/admin/newsletters?#{params}")}

      {:error, :not_found} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Subscriber not found.")}
    end
  end

  def handle_event("resubscribe", %{"email" => email}, socket) do
    case Newsletter.subscribe(email, source: "admin_added") do
      {:ok, _subscriber} ->
        params = socket.assigns.params |> Map.put("tab", "subscribers")

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Subscriber re-added.",
           title: "Newsletter"
         )
         |> push_patch(to: ~p"/admin/newsletters?#{params}")}

      {:error, :invalid_email} ->
        {:noreply, YscWeb.Flash.put_toast(socket, :error, "Invalid email.")}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Could not re-add subscriber.")}
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

  defp subscribers_loading?(nil), do: true
  defp subscribers_loading?(_meta), do: false

  defp subscribers_empty?(_streams, nil), do: false
  defp subscribers_empty?(_streams, meta), do: meta.total_count == 0

  defp subscriber_name(sub) do
    [sub.first_name, sub.last_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp subscriber_status_badge(true), do: "green"
  defp subscriber_status_badge(false), do: "zinc"

  defp subscribers_list_path(params) do
    ~p"/admin/newsletters?#{Map.put(params || %{}, "tab", "subscribers")}"
  end
end
