defmodule YscWeb.AdminMembershipsLive do
  @moduledoc """
  Admin view for monitoring and managing memberships.

  Shows membership counts by type and a list of all active memberships
  with their associated users.

  A "membership" is a primary account holder with active membership.
  Family/lifetime memberships include linked sub-accounts (spouse, children).
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    stats = Accounts.get_membership_stats()
    memberships = Accounts.list_memberships(limit: 200)

    {:ok,
     socket
     |> assign(:active_page, :memberships)
     |> assign(:page_title, "Memberships")
     |> assign(:stats, stats)
     |> assign(:memberships, memberships)
     |> assign(:type_filter, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    type_filter =
      case params["type"] do
        "single" -> :single
        "family" -> :family
        "lifetime" -> :lifetime
        _ -> nil
      end

    memberships =
      Accounts.list_memberships(
        limit: 200,
        type: type_filter
      )

    {:noreply,
     socket
     |> assign(:type_filter, type_filter)
     |> assign(:memberships, memberships)}
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
        </div>

        <%!-- Stats cards --%>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100">
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
              Total Memberships
            </p>
            <p class="text-3xl font-black text-zinc-900">
              {@stats.total}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              Active primary accounts
            </p>
          </div>

          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100">
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
              Single
            </p>
            <p class="text-3xl font-black text-zinc-900">
              {@stats.single}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              Individual memberships
            </p>
          </div>

          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100">
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
              Family
            </p>
            <p class="text-3xl font-black text-zinc-900">
              {@stats.family}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              Family plan memberships
            </p>
          </div>

          <div class="bg-white p-6 rounded-lg shadow-sm border border-zinc-100">
            <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-3">
              Lifetime
            </p>
            <p class="text-3xl font-black text-zinc-900">
              {@stats.lifetime}
            </p>
            <p class="text-xs text-zinc-500 mt-1 font-medium">
              Lifetime memberships
            </p>
          </div>
        </div>

        <%!-- Filter and membership list --%>
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 overflow-hidden">
          <div class="px-6 py-4 border-b border-zinc-100 flex flex-wrap items-center gap-4">
            <h2 class="text-lg font-bold text-zinc-900">All Memberships</h2>
            <div class="flex gap-2">
              <.link
                patch={~p"/admin/memberships"}
                class={[
                  "px-3 py-1.5 text-sm font-medium rounded transition-colors",
                  if(@type_filter == nil,
                    do: "bg-blue-600 text-white",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                All
              </.link>
              <.link
                patch={~p"/admin/memberships?type=single"}
                class={[
                  "px-3 py-1.5 text-sm font-medium rounded transition-colors",
                  if(@type_filter == :single,
                    do: "bg-blue-600 text-white",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                Single
              </.link>
              <.link
                patch={~p"/admin/memberships?type=family"}
                class={[
                  "px-3 py-1.5 text-sm font-medium rounded transition-colors",
                  if(@type_filter == :family,
                    do: "bg-blue-600 text-white",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                Family
              </.link>
              <.link
                patch={~p"/admin/memberships?type=lifetime"}
                class={[
                  "px-3 py-1.5 text-sm font-medium rounded transition-colors",
                  if(@type_filter == :lifetime,
                    do: "bg-blue-600 text-white",
                    else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  )
                ]}
              >
                Lifetime
              </.link>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Primary Holder
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Type
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Users
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Associated Users
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <%= for membership <- @memberships do %>
                  <tr class="hover:bg-zinc-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center gap-3">
                        <.user_avatar_image
                          email={membership.primary_user.email}
                          user_id={membership.primary_user.id}
                          country={membership.primary_user.most_connected_country}
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
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.badge type={membership_type_badge(membership.type)}>
                        {String.capitalize(to_string(membership.type))}
                      </.badge>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-700">
                      {membership.user_count}
                    </td>
                    <td class="px-6 py-4">
                      <div class="flex flex-wrap gap-3">
                        <%= for user <- membership.associated_users do %>
                          <.link
                            navigate={~p"/admin/users/#{user.id}/details"}
                            class="inline-flex items-center gap-1.5 text-sm text-blue-600 hover:underline"
                          >
                            <.user_avatar_image
                              email={user.email}
                              user_id={user.id}
                              country={user.most_connected_country}
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
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.link
                        navigate={
                          ~p"/admin/users/#{membership.primary_user.id}/details/membership"
                        }
                        class="text-sm font-medium text-blue-600 hover:text-blue-800"
                      >
                        Manage
                      </.link>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div :if={@memberships == []} class="py-16 text-center">
            <.icon
              name="hero-user-group"
              class="w-12 h-12 text-zinc-300 mx-auto mb-4"
            />
            <p class="text-zinc-500 font-medium">No memberships found</p>
            <p class="text-sm text-zinc-400 mt-1">
              <%= if @type_filter do %>
                No {String.downcase(to_string(@type_filter))} memberships.
              <% else %>
                No active memberships.
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  defp membership_type_badge(:single), do: :sky
  defp membership_type_badge(:family), do: :purple
  defp membership_type_badge(:lifetime), do: :green
  defp membership_type_badge(_), do: :default
end
