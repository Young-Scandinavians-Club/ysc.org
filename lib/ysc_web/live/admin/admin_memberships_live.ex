defmodule YscWeb.AdminMembershipsLive do
  @moduledoc """
  Admin view for monitoring and managing memberships.

  Shows membership counts by type and a sortable, searchable list of all
  active memberships with their associated users.

  A "membership" is a primary account holder with active membership.
  Family/lifetime memberships include linked sub-accounts (spouse, children).
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  alias Ysc.Accounts
  alias Ysc.Accounts.UserDisplay
  alias Ysc.Subscriptions
  alias YscWeb.Admin.DateTimeDisplay

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:active_page, :memberships)
      |> assign(:page_title, "Memberships")
      |> assign(:stats, %{total: 0, single: 0, family: 0, lifetime: 0})
      |> assign(:loading_stats?, true)
      |> assign(:type_filter, nil)
      |> assign(:params, %{})
      |> assign(:meta, nil)
      |> assign(:empty, false)
      |> stream_configure(:memberships,
        dom_id: &"membership-#{&1.primary_user.id}"
      )
      |> stream(:memberships, [], reset: true)

    if connected?(socket) do
      send(self(), :load_membership_stats)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    type_filter = membership_type_filter(params)

    search_term =
      case params["search"] do
        %{"query" => query} when is_binary(query) -> query
        _ -> nil
      end

    socket =
      socket
      |> assign(:type_filter, type_filter)
      |> assign(:params, params)

    if connected?(socket) do
      case Accounts.list_paginated_memberships(params, search_term,
             type: type_filter
           ) do
        {:ok, {memberships, meta}} ->
          {:noreply,
           socket
           |> assign(:meta, meta)
           |> assign(:empty, memberships == [])
           |> stream(:memberships, memberships, reset: true)}

        {:error, _meta} ->
          {:noreply, push_patch(socket, to: ~p"/admin/memberships")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "change",
        %{"search" => %{"query" => search_query}},
        socket
      ) do
    new_params =
      Map.put(socket.assigns[:params], "search", %{"query" => search_query})

    {:noreply, push_patch(socket, to: ~p"/admin/memberships?#{new_params}")}
  end

  def handle_event("clear-search", %{"input-id" => _input_id}, socket) do
    new_params = Map.delete(socket.assigns[:params], "search")

    {:noreply, push_patch(socket, to: ~p"/admin/memberships?#{new_params}")}
  end

  @impl true
  def handle_info(:load_membership_stats, socket) do
    {:noreply,
     socket
     |> assign(:stats, Accounts.get_membership_stats())
     |> assign(:loading_stats?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="bg-zinc-50/80 min-h-screen -mx-4 lg:-mx-10 px-4 lg:px-10 py-8">
        <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 py-8 border-b border-zinc-100 mb-8">
          <div>
            <h1 class="text-3xl font-black text-zinc-900 tracking-tight">
              Memberships
            </h1>
            <p class="text-sm text-zinc-500 mt-1">
              Monitor active memberships and associated users. Each membership represents a primary
              account holder; family/lifetime memberships include linked sub-accounts.
            </p>
          </div>
          <.link
            navigate={~p"/admin/memberships/report"}
            class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 transition-colors"
          >
            <.icon name="hero-document-chart-bar" class="w-4 h-4" /> Generate report
          </.link>
        </div>

        <%!-- Stats cards --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          <.admin_stat_card
            id="memberships-stat-total"
            label="Total Memberships"
            value={stat_value(@stats.total, @loading_stats?)}
            subtitle="Active primary accounts"
          />
          <.admin_stat_card
            id="memberships-stat-single"
            label="Single"
            value={stat_value(@stats.single, @loading_stats?)}
            subtitle="Individual memberships"
          />
          <.admin_stat_card
            id="memberships-stat-family"
            label="Family"
            value={stat_value(@stats.family, @loading_stats?)}
            subtitle="Family plan memberships"
          />
          <.admin_stat_card
            id="memberships-stat-lifetime"
            label="Lifetime"
            value={stat_value(@stats.lifetime, @loading_stats?)}
            subtitle="Lifetime memberships"
          />
        </div>

        <%!-- Search, filter and membership list --%>
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 overflow-hidden">
          <div class="px-6 py-4 border-b border-zinc-100 space-y-4">
            <h2 class="text-lg font-bold text-zinc-900">All Memberships</h2>

            <.admin_search_bar
              id="membership-search-form"
              input_id="membership-search"
              name="search[query]"
              value={
                case @params["search"] do
                  %{"query" => query} -> query
                  query when is_binary(query) -> query
                  _ -> ""
                end
              }
              placeholder="Search by name, email or phone number"
              on_change="change"
            />

            <div class="flex gap-2">
              <.admin_toggle_pill
                id="memberships-filter-all"
                variant={:primary}
                active={@type_filter == nil}
                patch={
                  ~p"/admin/memberships?#{Map.delete(non_flop_params(@params), "type")}"
                }
              >
                All
              </.admin_toggle_pill>
              <.admin_toggle_pill
                id="memberships-filter-single"
                variant={:primary}
                active={@type_filter == :single}
                patch={
                  ~p"/admin/memberships?#{Map.put(non_flop_params(@params), "type", "single")}"
                }
              >
                Single
              </.admin_toggle_pill>
              <.admin_toggle_pill
                id="memberships-filter-family"
                variant={:primary}
                active={@type_filter == :family}
                patch={
                  ~p"/admin/memberships?#{Map.put(non_flop_params(@params), "type", "family")}"
                }
              >
                Family
              </.admin_toggle_pill>
              <.admin_toggle_pill
                id="memberships-filter-lifetime"
                variant={:primary}
                active={@type_filter == :lifetime}
                patch={
                  ~p"/admin/memberships?#{Map.put(non_flop_params(@params), "type", "lifetime")}"
                }
              >
                Lifetime
              </.admin_toggle_pill>
            </div>
          </div>

          <.admin_table_skeleton
            :if={is_nil(@meta)}
            id="admin-memberships-loading"
            rows={8}
            columns={6}
          />

          <div :if={@meta} class="overflow-x-auto">
            <Flop.Phoenix.table
              id="admin_memberships_list"
              items={@streams.memberships}
              meta={@meta}
              path={~p"/admin/memberships?#{non_flop_params(@params)}"}
              opts={[
                table_attrs: [class: "min-w-full divide-y divide-zinc-200"],
                thead_attrs: [class: "bg-zinc-50"],
                thead_th_attrs: [
                  class:
                    "px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider whitespace-nowrap"
                ],
                tbody_attrs: [class: "bg-white divide-y divide-zinc-200"],
                tbody_tr_attrs: [class: "hover:bg-zinc-50"],
                tbody_td_attrs: [
                  class: "px-6 py-4 whitespace-nowrap text-sm text-zinc-700"
                ],
                symbol_attrs: [class: "ms-1 text-zinc-400"]
              ]}
            >
              <:col
                :let={{_, membership}}
                label="Primary Holder"
                field={:first_name}
              >
                <div class="flex items-center gap-3">
                  <.user_avatar_image
                    user={membership.primary_user}
                    class="w-8 h-8 rounded-full"
                  />
                  <div>
                    <p class="text-sm font-semibold text-zinc-900">
                      {membership.primary_user.first_name} {membership.primary_user.last_name}
                    </p>
                    <p class="text-xs text-zinc-500">
                      {membership.primary_user.email}
                    </p>
                  </div>
                </div>
              </:col>
              <:col :let={{_, membership}} label="Type">
                <.badge type={membership_type_badge(membership.type)}>
                  {String.capitalize(to_string(membership.type))}
                </.badge>
              </:col>
              <:col :let={{_, membership}} label="Users">
                {membership.user_count}
              </:col>
              <:col
                :let={{_, membership}}
                label="Membership Started"
                field={:subscription_start}
              >
                {DateTimeDisplay.format_utc_date(
                  active_subscription_started_at(membership.primary_user)
                )}
              </:col>
              <:col
                :let={{_, membership}}
                label="Applied"
                field={:application_date}
              >
                {DateTimeDisplay.format_utc_date(
                  UserDisplay.application_submitted_at(membership.primary_user)
                )}
              </:col>
              <:col
                :let={{_, membership}}
                label="Associated Users"
                tbody_td_attrs={[class: "px-6 py-4 text-sm text-zinc-700"]}
              >
                <div class="flex flex-wrap gap-3">
                  <%= for user <- membership.associated_users do %>
                    <.link
                      navigate={~p"/admin/users/#{user.id}/details"}
                      class="inline-flex items-center gap-1.5 text-sm text-blue-600 hover:underline"
                    >
                      <.user_avatar_image
                        user={user}
                        class="w-6 h-6 rounded-full"
                      />
                      <span>
                        {user.first_name} {user.last_name}
                        <%= if user.id == membership.primary_user.id do %>
                          <span class="text-zinc-400 text-xs">(primary)</span>
                        <% end %>
                      </span>
                    </.link>
                  <% end %>
                </div>
              </:col>
              <:action
                :let={{_, membership}}
                tbody_td_attrs={[
                  class: "px-6 py-4 whitespace-nowrap text-sm font-medium"
                ]}
              >
                <.link
                  navigate={
                    ~p"/admin/users/#{membership.primary_user.id}/details/membership"
                  }
                  class="text-sm font-medium text-blue-600 hover:text-blue-800"
                >
                  Manage
                </.link>
              </:action>
            </Flop.Phoenix.table>

            <.admin_list_empty_state
              :if={@empty}
              title="No memberships found"
              suggestion="Try adjusting your search term and filters."
              clear_id="admin-memberships-clear-filters-empty"
              clear_patch={~p"/admin/memberships"}
            />

            <.admin_flop_pagination
              meta={@meta}
              path={~p"/admin/memberships?#{non_flop_params(@params)}"}
              density={:comfortable}
            />
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  defp stat_value(_value, true), do: "—"
  defp stat_value(value, false), do: value

  defp membership_type_filter(params) do
    case params["type"] do
      "single" -> :single
      "family" -> :family
      "lifetime" -> :lifetime
      _ -> nil
    end
  end

  defp membership_type_badge(:single), do: :sky
  defp membership_type_badge(:family), do: :purple
  defp membership_type_badge(:lifetime), do: :green
  defp membership_type_badge(_), do: :default

  defp active_subscription_started_at(user) do
    subscriptions =
      case user.subscriptions do
        %Ecto.Association.NotLoaded{} -> []
        list when is_list(list) -> list
        _ -> []
      end

    case Enum.find(subscriptions, &Subscriptions.active?/1) do
      %{current_period_start: current_period_start} -> current_period_start
      nil -> nil
    end
  end
end
