defmodule YscWeb.AdminNewslettersLive do
  use YscWeb, :admin_live_view

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS
  alias YscWeb.Admin.DateTimeDisplay
  alias YscWeb.AdminBadgeHelpers
  alias YscWeb.DateDisplay

  alias Ysc.Newsletter
  alias Ysc.Newsletter.Notice

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Newsletter.subscribe_to_edition_updates()

    socket =
      socket
      |> assign(:page_title, "Newsletters")
      |> assign(:active_page, :newsletters)
      |> assign(:subscriber_count, nil)
      |> assign(:creator_filter, [])
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
      |> assign(:notices_empty?, false)
      |> assign(:notices, [])
      |> assign(:show_notice_modal, false)
      |> assign(:notice_editor_key, "new")
      |> assign(:editing_notice, nil)
      |> assign(
        :notice_form,
        to_form(Notice.changeset(%Notice{}, %{}), as: :notice)
      )
      |> stream_configure(:editions, dom_id: &"edition-#{&1.id}")
      |> stream_configure(:subscribers, dom_id: &"subscriber-#{&1.id}")
      |> stream(:editions, [])
      |> stream(:subscribers, [])

    socket =
      if connected?(socket) do
        start_async(socket, :load_subscriber_count, fn ->
          Newsletter.count_subscribers(subscribed: true)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    current_tab = allowed_tab(Map.get(params, "tab"))

    socket =
      socket
      |> assign(:current_tab, current_tab)
      |> assign_newsletter_filter_params(params, current_tab)

    socket =
      if connected?(socket) do
        cond do
          current_tab == "subscribers" ->
            subscriber_params = build_subscriber_flop_params(params)

            socket
            |> stream(:subscribers, [], reset: true)
            |> start_async(:load_subscribers, fn ->
              Newsletter.list_paginated_subscribers(subscriber_params)
            end)

          current_tab == "notices" ->
            notices = Newsletter.list_notices()

            socket
            |> assign(:notices, notices)
            |> assign(:notices_empty?, notices == [])

          true ->
            date_from = Map.get(params, "date_from", "")
            date_to = Map.get(params, "date_to", "")

            socket
            |> stream(:editions, [], reset: true)
            |> start_async(:load_editions, fn ->
              Newsletter.list_paginated_editions(params,
                date_from: date_from,
                date_to: date_to
              )
            end)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  defp assign_newsletter_filter_params(socket, params, "subscribers") do
    socket
    |> assign(:params, params)
    |> assign(:sub_search, Map.get(params, "sub_q", ""))
    |> assign(:sub_filter, Map.get(params, "subscribed_filter", "all"))
  end

  defp assign_newsletter_filter_params(socket, params, "notices") do
    assign(socket, :params, params)
  end

  defp assign_newsletter_filter_params(socket, params, _current_tab) do
    socket
    |> assign(:params, params)
    |> assign(:search_query, "")
    |> assign(:date_from, Map.get(params, "date_from", ""))
    |> assign(:date_to, Map.get(params, "date_to", ""))
  end

  @impl true
  def handle_async(:load_subscriber_count, {:ok, count}, socket) do
    {:noreply, assign(socket, :subscriber_count, count)}
  end

  @impl true
  def handle_async(:load_subscriber_count, {:exit, _}, socket) do
    {:noreply, assign(socket, :subscriber_count, 0)}
  end

  @impl true
  def handle_async(:load_editions, {:ok, {:ok, {editions, meta}}}, socket) do
    title_filter = Enum.find(meta.flop.filters, &(&1.field == :title))
    search_query = if title_filter, do: title_filter.value, else: ""

    {:noreply,
     socket
     |> assign(:meta, meta)
     |> assign(:empty, editions == [])
     |> assign(:search_query, search_query)
     |> assign(:creator_filter, Newsletter.get_all_creators())
     |> stream(:editions, editions, reset: true)}
  end

  @impl true
  def handle_async(:load_editions, {:ok, {:error, _meta}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/newsletters")}
  end

  @impl true
  def handle_async(:load_editions, {:exit, _}, socket) do
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

  @impl true
  def handle_info({:edition_delivery_progress, edition}, socket) do
    {:noreply, stream_insert(socket, :editions, edition)}
  end

  def handle_info({:edition_sent, edition}, socket) do
    {:noreply,
     socket
     |> assign(:creator_filter, Newsletter.get_all_creators())
     |> stream_insert(:editions, edition)
     |> YscWeb.Flash.put_toast(:info, "\"#{edition.title}\" has been sent.",
       title: "Newsletter sent"
     )}
  end

  defp allowed_tab("subscribers"), do: "subscribers"
  defp allowed_tab("notices"), do: "notices"
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
      user={@current_user}
      role={@admin_role}
    >
      <div class="py-6">
        <div class="flex items-center gap-2">
          <.admin_page_title>Newsletters</.admin_page_title>
          <.admin_help_link
            topic="newsletters/compose"
            label="How to compose a newsletter"
            role={@admin_role}
          />
        </div>
        <p class="mt-0.5 text-sm text-zinc-500">
          <%= if is_nil(@subscriber_count) do %>
            Loading subscribers…
          <% else %>
            {@subscriber_count} subscriber{if @subscriber_count == 1,
              do: "",
              else: "s"}
          <% end %>
        </p>
      </div>

      <.admin_tabs
        id="newsletter-tabs"
        role="tablist"
        aria_label="Newsletter sections"
      >
        <.admin_tab
          active={@current_tab == "editions"}
          role="tab"
          aria-selected={@current_tab == "editions"}
          phx-click="switch-tab"
          phx-value-tab="editions"
        >
          Editions
        </.admin_tab>
        <.admin_tab
          active={@current_tab == "subscribers"}
          role="tab"
          aria-selected={@current_tab == "subscribers"}
          phx-click="switch-tab"
          phx-value-tab="subscribers"
        >
          Subscribers
        </.admin_tab>
        <.admin_tab
          active={@current_tab == "notices"}
          role="tab"
          aria-selected={@current_tab == "notices"}
          phx-click="switch-tab"
          phx-value-tab="notices"
        >
          Saved notices
        </.admin_tab>
      </.admin_tabs>

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
                <.admin_filter_dropdown
                  id="filter-newsletters-dropdown"
                  clear_patch={~p"/admin/newsletters"}
                  clear_id="admin-newsletters-clear-filters"
                >
                  <.filter_form
                    :if={@meta}
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
                </.admin_filter_dropdown>
              </div>
              <.link navigate={~p"/admin/newsletters/new"} class="inline-flex">
                <.button>
                  <.icon name="hero-document-plus" class="w-5 h-5" /> New Newsletter
                </.button>
              </.link>
            </div>
          </div>

          <%!-- Editions content --%>
          <.admin_table_skeleton :if={is_nil(@meta)} rows={6} columns={4} />

          <div :if={@meta} class="space-y-6">
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
                    <%= if edition.status == :sending do %>
                      <.admin_sending_badge />
                    <% else %>
                      <.badge type={
                        newsletter_edition_status_badge_type(edition.status)
                      }>
                        {newsletter_edition_status_label(edition.status)}
                      </.badge>
                    <% end %>
                    <span class="text-sm text-zinc-500">
                      <%= cond do %>
                        <% edition.sent_at -> %>
                          Sent {DateTimeDisplay.format_datetime_compact(
                            edition.sent_at
                          )}
                        <% edition.scheduled_at -> %>
                          Scheduled {DateTimeDisplay.format_datetime_compact(
                            edition.scheduled_at
                          )}
                        <% true -> %>
                          Created {DateTimeDisplay.format_datetime_compact(
                            edition.inserted_at
                          )}
                      <% end %>
                    </span>
                    <span
                      :if={edition.status == :sent && edition.sent_count > 0}
                      class="text-sm text-zinc-500"
                    >
                      {edition.sent_count} sent
                    </span>
                    <span
                      :if={creator_assigned?(edition)}
                      class="text-sm text-zinc-500"
                    >
                      by {creator_name(edition.creator)}
                    </span>
                  </div>

                  <div class="flex justify-end pt-3 mt-3 border-t border-zinc-200">
                    <.edition_actions_dropdown
                      edition={edition}
                      menu_id={"newsletter-actions-mob-#{edition.id}"}
                    />
                  </div>
                </div>
              <% end %>

              <.admin_list_empty_state
                :if={@empty}
                title="No newsletters yet"
                suggestion="Create one to get started."
              />

              <div :if={!@empty} class="pt-4">
                <.admin_flop_pagination
                  meta={@meta}
                  path={~p"/admin/newsletters?#{non_flop_params(@params)}"}
                  density={:compact}
                />
              </div>
            </div>
            <%!-- Desktop Table View --%>
            <div class="hidden md:block py-6 w-full">
              <Flop.Phoenix.table
                id="admin_newsletters_list"
                items={@streams.editions}
                meta={@meta}
                path={~p"/admin/newsletters?#{non_flop_params(@params)}"}
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
                  <%= if edition.status == :sending do %>
                    <.admin_sending_badge />
                  <% else %>
                    <.badge type={
                      newsletter_edition_status_badge_type(edition.status)
                    }>
                      {newsletter_edition_status_label(edition.status)}
                    </.badge>
                  <% end %>
                </:col>
                <:col :let={{_, edition}} label="Created" field={:inserted_at}>
                  <span class="text-zinc-600">
                    {format_date(edition.inserted_at)}
                  </span>
                </:col>
                <:col :let={{_, edition}} label="Sent" field={:sent_at}>
                  <%= cond do %>
                    <% edition.sent_at -> %>
                      <div class="text-zinc-600">
                        {format_date(edition.sent_at)}
                      </div>
                      <div
                        :if={edition.sent_count > 0}
                        class="text-xs text-zinc-400"
                      >
                        {edition.sent_count} recipients
                      </div>
                    <% edition.scheduled_at -> %>
                      <div class="text-zinc-500 text-xs font-medium">Scheduled</div>
                      <div class="text-zinc-600 text-xs">
                        {DateTimeDisplay.format_datetime_compact(
                          edition.scheduled_at
                        )}
                      </div>
                    <% true -> %>
                      <span class="text-zinc-400">—</span>
                  <% end %>
                </:col>
                <:col :let={{_, edition}} label="Creator">
                  <%= if creator_assigned?(edition) do %>
                    <span class="text-zinc-600">
                      {creator_name(edition.creator)}
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </:col>
                <:action :let={{_, edition}}>
                  <.edition_actions_dropdown
                    edition={edition}
                    menu_id={"newsletter-actions-dt-#{edition.id}"}
                  />
                </:action>
              </Flop.Phoenix.table>

              <.admin_list_empty_state
                :if={@empty}
                title="No newsletters yet"
                suggestion="Create one to get started."
              />

              <.admin_flop_pagination
                meta={@meta}
                path={~p"/admin/newsletters?#{non_flop_params(@params)}"}
                density={:comfortable}
              />
            </div>
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
                <.button type="submit" phx-disable-with="Adding...">Add</.button>
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
              <.admin_toggle_pill
                active={@sub_filter == "all"}
                phx-click="filter-subscribers"
                phx-value-filter="all"
              >
                All
              </.admin_toggle_pill>
              <.admin_toggle_pill
                active={@sub_filter == "active"}
                phx-click="filter-subscribers"
                phx-value-filter="active"
              >
                Active
              </.admin_toggle_pill>
              <.admin_toggle_pill
                active={@sub_filter == "inactive"}
                phx-click="filter-subscribers"
                phx-value-filter="inactive"
              >
                Inactive
              </.admin_toggle_pill>
              <.button
                type="button"
                phx-click="open-add-subscriber-modal"
                class="ms-0 sm:ms-2"
              >
                <.icon name="hero-user-plus" class="w-5 h-5" /> Add subscriber
              </.button>
            </div>
          </div>

          <%!-- Subscribers content --%>
          <.admin_table_skeleton
            :if={subscribers_loading?(@sub_meta)}
            rows={6}
            columns={4}
          />

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
                    <.badge type={
                      newsletter_subscriber_status_badge_type(subscriber.subscribed)
                    }>
                      {newsletter_subscriber_status_label(subscriber.subscribed)}
                    </.badge>
                    <.badge
                      :if={subscriber.source}
                      type={AdminBadgeHelpers.newsletter_source_badge_type(subscriber.source)}
                      class="me-0"
                    >
                      {AdminBadgeHelpers.newsletter_source_label(subscriber.source)}
                    </.badge>
                    <span
                      :if={subscriber.subscribed_at}
                      class="text-xs text-zinc-400"
                    >
                      Subscribed {format_date(subscriber.subscribed_at)}
                    </span>
                  </div>
                  <div class="flex justify-end pt-3 mt-3 border-t border-zinc-200">
                    <.subscriber_actions_dropdown
                      subscriber={subscriber}
                      menu_id={"subscriber-actions-mob-#{subscriber.id}"}
                    />
                  </div>
                </div>
              <% end %>

              <.admin_list_empty_state
                :if={subscribers_empty?(@streams.subscribers, @sub_meta)}
                title="No subscribers found"
                suggestion={
                  if @sub_search != "" or @sub_filter != "all",
                    do: "Try changing search or filter.",
                    else: "Subscribers will appear here when they sign up."
                }
              />

              <div
                :if={
                  @sub_meta && !subscribers_empty?(@streams.subscribers, @sub_meta)
                }
                class="pt-4"
              >
                <.admin_flop_pagination
                  meta={@sub_meta}
                  path={subscribers_list_path(@params)}
                  density={:compact}
                />
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
                  <.badge type={
                    newsletter_subscriber_status_badge_type(sub.subscribed)
                  }>
                    {newsletter_subscriber_status_label(sub.subscribed)}
                  </.badge>
                </:col>
                <:col :let={{_, sub}} label="Source" field={:source}>
                  <%= if sub.source do %>
                    <.badge type={AdminBadgeHelpers.newsletter_source_badge_type(sub.source)}>
                      {AdminBadgeHelpers.newsletter_source_label(sub.source)}
                    </.badge>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </:col>
                <:col :let={{_, sub}} label="Subscribed" field={:subscribed_at}>
                  <span class="text-zinc-600">
                    {if sub.subscribed_at,
                      do: format_date(sub.subscribed_at),
                      else: "—"}
                  </span>
                </:col>
                <:action :let={{_, sub}}>
                  <.subscriber_actions_dropdown
                    subscriber={sub}
                    menu_id={"subscriber-actions-dt-#{sub.id}"}
                  />
                </:action>
              </Flop.Phoenix.table>

              <.admin_list_empty_state
                :if={subscribers_empty?(@streams.subscribers, @sub_meta)}
                title="No subscribers found"
                suggestion={
                  if @sub_search != "" or @sub_filter != "all",
                    do: "Try changing search or filter.",
                    else: "Subscribers will appear here when they sign up."
                }
              />

              <.admin_flop_pagination
                :if={@sub_meta}
                meta={@sub_meta}
                path={subscribers_list_path(@params)}
                density={:comfortable}
              />
            </div>
          </div>
        </div>

        <%!-- Saved notices tab --%>
        <div :if={@current_tab == "notices"} class="space-y-6">
          <.modal
            :if={@show_notice_modal}
            id="notice-modal"
            on_cancel={JS.push("close-notice-modal")}
            show
          >
            <.header>
              {if @editing_notice, do: "Edit notice", else: "New notice"}
            </.header>
            <.form
              for={@notice_form}
              id="notice-form"
              phx-change="validate-notice"
              phx-submit="save-notice"
              class="mt-4 space-y-4"
            >
              <.input
                field={@notice_form[:name]}
                type="text"
                label="Name"
                placeholder="e.g. Parking reminder"
                id="notice-name"
              />
              <div>
                <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-1">
                  Body
                </label>
                <p class="text-sm text-zinc-500 mb-2">
                  Rich text inserted into the newsletter intro at the cursor.
                </p>
                <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none border border-zinc-200 rounded-lg overflow-hidden">
                  <.input
                    type="hidden"
                    id={"notice_body_#{@notice_editor_key}"}
                    field={@notice_form[:body]}
                    phx-hook="TrixHook"
                    phx-debounce="400"
                  />
                  <div
                    id={"notice-richtext-#{@notice_editor_key}"}
                    class="relative"
                    phx-update="ignore"
                  >
                    <trix-editor
                      input={"notice_body_#{@notice_editor_key}"}
                      class="trix-content block px-4 py-2 bg-white border-0 focus:ring-1 focus:ring-blue-400 transition text-wrap min-h-[160px]"
                      placeholder="Write the notice…"
                    >
                    </trix-editor>
                  </div>
                </div>
              </div>
              <div class="flex justify-end gap-2 mt-6">
                <button
                  type="button"
                  phx-click="close-notice-modal"
                  class="rounded-lg bg-zinc-100 px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-200"
                >
                  Cancel
                </button>
                <.button type="submit" phx-disable-with="Saving...">
                  Save notice
                </.button>
              </div>
            </.form>
          </.modal>

          <div class="flex items-center justify-end">
            <.button type="button" phx-click="open-notice-modal" id="new-notice-btn">
              <.icon name="hero-document-plus" class="w-5 h-5" /> New notice
            </.button>
          </div>

          <div class="block md:hidden space-y-4">
            <div
              :for={notice <- @notices}
              id={"notice-mob-#{notice.id}"}
              class="bg-white rounded-lg border border-zinc-200 p-4"
            >
              <button
                type="button"
                phx-click="edit-notice"
                phx-value-id={notice.id}
                class="block w-full text-left"
              >
                <h3 class="text-base font-semibold text-zinc-900 truncate">
                  {notice.name}
                </h3>
                <p class="text-sm text-zinc-500 mt-1">
                  Updated {format_date(notice.updated_at)}
                  <span :if={creator_assigned?(notice)}>
                    · by {creator_name(notice.creator)}
                  </span>
                </p>
              </button>
              <div class="flex justify-end pt-3 mt-3 border-t border-zinc-200">
                <.notice_actions_dropdown
                  notice={notice}
                  menu_id={"notice-actions-mob-#{notice.id}"}
                />
              </div>
            </div>

            <.admin_list_empty_state
              :if={@notices_empty?}
              title="No saved notices"
              suggestion="Create reusable notices to insert into newsletter intros."
            />
          </div>

          <div class="hidden md:block py-6 w-full">
            <table :if={!@notices_empty?} id="admin_notices_list">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Creator</th>
                  <th>Updated</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={notice <- @notices}
                  id={"notice-#{notice.id}"}
                  class="cursor-pointer"
                  phx-click="edit-notice"
                  phx-value-id={notice.id}
                >
                  <td>
                    <span class="font-semibold text-zinc-900">{notice.name}</span>
                  </td>
                  <td>
                    <%= if creator_assigned?(notice) do %>
                      <span class="text-zinc-600">
                        {creator_name(notice.creator)}
                      </span>
                    <% else %>
                      <span class="text-zinc-400">—</span>
                    <% end %>
                  </td>
                  <td>
                    <span class="text-zinc-600">
                      {format_date(notice.updated_at)}
                    </span>
                  </td>
                  <td>
                    <.notice_actions_dropdown
                      notice={notice}
                      menu_id={"notice-actions-dt-#{notice.id}"}
                    />
                  </td>
                </tr>
              </tbody>
            </table>

            <.admin_list_empty_state
              :if={@notices_empty?}
              title="No saved notices"
              suggestion="Create reusable notices to insert into newsletter intros."
            />
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  attr :edition, :map, required: true
  attr :menu_id, :string, required: true

  def edition_actions_dropdown(assigns) do
    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Newsletter actions">
      <.dropdown_menu_item
        id={"#{@menu_id}-open"}
        icon={
          if @edition.status == :sent, do: "hero-eye", else: "hero-pencil-square"
        }
        navigate={~p"/admin/newsletters/#{@edition.id}/edit"}
      >
        {if @edition.status == :sent, do: "View", else: "Edit"}
      </.dropdown_menu_item>
      <.dropdown_menu_item
        id={"#{@menu_id}-duplicate"}
        icon="hero-document-duplicate"
        phx-click="duplicate-edition"
        phx-value-id={@edition.id}
      >
        Duplicate
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={@edition.status == :sending}
        id={"#{@menu_id}-sending"}
        static
        tone={:info}
      >
        <:leading>
          <span class="inline-block h-5 w-5 shrink-0 rounded-full border-2 border-blue-400 border-t-transparent animate-spin"></span>
        </:leading>
        Sending…
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={@edition.status == :draft}
        id={"#{@menu_id}-send-now"}
        icon="hero-paper-airplane"
        tone={:success}
        phx-click="send-now"
        phx-value-id={@edition.id}
        data-confirm="Send this newsletter to all subscribers now? This cannot be undone."
      >
        Send now
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={@edition.status not in [:sent, :sending]}
        id={"#{@menu_id}-delete"}
        icon="hero-trash"
        tone={:danger}
        phx-click="delete-edition"
        phx-value-id={@edition.id}
        data-confirm="Delete this newsletter? This cannot be undone."
      >
        Delete
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  attr :subscriber, :map, required: true
  attr :menu_id, :string, required: true

  def subscriber_actions_dropdown(assigns) do
    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Subscriber actions">
      <.dropdown_menu_item
        :if={@subscriber.subscribed}
        id={"#{@menu_id}-remove"}
        icon="hero-user-minus"
        tone={:danger}
        phx-click="remove-subscriber"
        phx-value-email={@subscriber.email}
        data-confirm="Remove this subscriber? They will no longer receive newsletters."
      >
        Remove
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={!@subscriber.subscribed}
        id={"#{@menu_id}-re-add"}
        icon="hero-user-plus"
        tone={:success}
        phx-click="resubscribe"
        phx-value-email={@subscriber.email}
      >
        Re-add
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  attr :notice, :map, required: true
  attr :menu_id, :string, required: true

  def notice_actions_dropdown(assigns) do
    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Notice actions">
      <.dropdown_menu_item
        id={"#{@menu_id}-edit"}
        icon="hero-pencil-square"
        phx-click="edit-notice"
        phx-value-id={@notice.id}
      >
        Edit
      </.dropdown_menu_item>
      <.dropdown_menu_item
        id={"#{@menu_id}-delete"}
        icon="hero-trash"
        tone={:danger}
        phx-click="delete-notice"
        phx-value-id={@notice.id}
        data-confirm="Delete this saved notice? This cannot be undone."
      >
        Delete
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  def handle_event("send-now", %{"id" => id}, socket) do
    edition = Newsletter.get_edition!(id)

    case Newsletter.send_edition(edition) do
      {:ok, sending_edition} ->
        {:noreply,
         socket
         |> stream_insert(:editions, sending_edition)
         |> YscWeb.Flash.put_toast(:info, "Sending newsletter…",
           title: "Newsletter"
         )}

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

  def handle_event("duplicate-edition", %{"id" => id}, socket) do
    edition = Newsletter.get_edition!(id)

    case Newsletter.duplicate_edition(edition,
           created_by_id: socket.assigns.current_user.id
         ) do
      {:ok, new_edition} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Newsletter duplicated.",
           title: "Newsletter"
         )
         |> push_navigate(to: ~p"/admin/newsletters/#{new_edition.id}/edit")}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Could not duplicate newsletter."
         )}
    end
  end

  def handle_event("open-notice-modal", _params, socket) do
    {:noreply, assign_new_notice_modal(socket)}
  end

  def handle_event("close-notice-modal", _params, socket) do
    {:noreply, assign(socket, :show_notice_modal, false)}
  end

  def handle_event("edit-notice", %{"id" => id}, socket) do
    notice = Newsletter.get_notice!(id)

    {:noreply,
     socket
     |> assign(:editing_notice, notice)
     |> assign(:notice_editor_key, notice.id)
     |> assign(
       :notice_form,
       to_form(Notice.changeset(notice, %{}), as: :notice)
     )
     |> assign(:show_notice_modal, true)}
  end

  def handle_event("validate-notice", %{"notice" => params}, socket) do
    notice = socket.assigns.editing_notice || %Notice{}

    changeset =
      notice
      |> Notice.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :notice_form, to_form(changeset, as: :notice))}
  end

  def handle_event(
        "editor-update",
        %{"field" => field, "value" => value},
        socket
      )
      when field in ["notice[body]", "notice_body"] do
    params =
      (socket.assigns.notice_form.params || %{})
      |> Map.put("body", value)

    # Preserve name from current form params / data
    params =
      Map.put_new(params, "name", socket.assigns.notice_form[:name].value || "")

    notice = socket.assigns.editing_notice || %Notice{}

    changeset =
      notice
      |> Notice.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :notice_form, to_form(changeset, as: :notice))}
  end

  def handle_event("editor-update", _params, socket), do: {:noreply, socket}

  def handle_event("save-notice", %{"notice" => params}, socket) do
    case save_notice(socket, params) do
      {:ok, _notice, socket} ->
        notices = Newsletter.list_notices()

        {:noreply,
         socket
         |> assign(:show_notice_modal, false)
         |> assign(:notices, notices)
         |> assign(:notices_empty?, notices == [])
         |> YscWeb.Flash.put_toast(:info, "Notice saved.", title: "Newsletter")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :notice_form, to_form(changeset, as: :notice))}
    end
  end

  def handle_event("delete-notice", %{"id" => id}, socket) do
    notice = Newsletter.get_notice!(id)

    case Newsletter.delete_notice(notice) do
      {:ok, _} ->
        notices = Newsletter.list_notices()

        {:noreply,
         socket
         |> assign(:notices, notices)
         |> assign(:notices_empty?, notices == [])
         |> YscWeb.Flash.put_toast(:info, "Notice deleted.",
           title: "Newsletter"
         )}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Could not delete notice.")}
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

  defp assign_new_notice_modal(socket) do
    socket
    |> assign(:editing_notice, nil)
    |> assign(:notice_editor_key, "new-#{System.unique_integer([:positive])}")
    |> assign(
      :notice_form,
      to_form(Notice.changeset(%Notice{}, %{}), as: :notice)
    )
    |> assign(:show_notice_modal, true)
  end

  defp save_notice(
         %{assigns: %{editing_notice: %Notice{} = notice}} = socket,
         params
       ) do
    case Newsletter.update_notice(notice, params) do
      {:ok, updated} -> {:ok, updated, socket}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp save_notice(socket, params) do
    case Newsletter.create_notice(params,
           created_by_id: socket.assigns.current_user.id
         ) do
      {:ok, notice} -> {:ok, notice, socket}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_update_filter(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  defp maybe_update_filter(filter), do: filter

  defp format_date(nil), do: ""
  defp format_date(dt), do: DateDisplay.format_datetime_display(dt)

  defp creator_assigned?(%{creator: creator}),
    do: Ecto.assoc_loaded?(creator) && creator

  defp creator_name(%Ecto.Association.NotLoaded{}), do: nil

  defp creator_name(creator) do
    [creator.first_name, creator.last_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> then(fn name -> if name != "", do: name, else: creator.email end)
  end

  defp subscribers_loading?(nil), do: true
  defp subscribers_loading?(_meta), do: false

  defp subscribers_empty?(_streams, meta), do: meta.total_count == 0

  defp subscriber_name(sub) do
    [sub.first_name, sub.last_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  defp subscribers_list_path(params) do
    ~p"/admin/newsletters?#{Map.put(non_flop_params(params || %{}), "tab", "subscribers")}"
  end
end
