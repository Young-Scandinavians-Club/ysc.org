defmodule YscWeb.AdminSearchComponent do
  @moduledoc """
  LiveComponent for the admin magic search box.
  Provides instant search across Events, Posts, Tickets, Users, and Bookings.
  """
  use YscWeb, :live_component

  alias Ysc.Search

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"admin-search-#{@id}"} class="relative w-full" phx-hook="AdminSearch">
      <form phx-change="search" phx-target={@myself} class="relative">
        <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500 z-10" />
        </div>
        <input
          type="search"
          name="query"
          value={@query}
          phx-debounce="300"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
          enterkeyhint="search"
          spellcheck="false"
          placeholder="Search events, posts, tickets, users, bookings..."
          tabindex="0"
          class="block pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200/50 rounded w-full bg-white/60 backdrop-blur-md shadow-sm focus:ring-blue-500 focus:border-blue-500 focus:bg-white transition-all"
        />
      </form>

      <div
        :if={@query != "" && @show_results}
        data-results-container
        class="absolute z-50 w-full mt-2 bg-white border border-zinc-200 rounded-lg shadow-lg max-h-96 overflow-y-auto"
        phx-click-away="close_results"
        phx-target={@myself}
      >
        <div :if={@loading} class="p-4 text-center text-sm text-zinc-500">
          Searching...
        </div>

        <div
          :if={!@loading && has_results?(@results)}
          class="divide-y divide-zinc-200"
        >
          <!-- Events -->
          <div :if={length(@results.events) > 0} class="p-2">
            <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
              Events
            </div>
            <div class="space-y-1">
              <.link
                :for={event <- @results.events}
                data-result-item
                navigate={~p"/admin/events/#{event.id}/edit"}
                class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
              >
                <div class="font-medium"><%= event.title %></div>
                <div class="text-xs text-zinc-500">
                  <%= if event.organizer,
                    do:
                      "#{event.organizer.first_name} #{event.organizer.last_name}",
                    else: "No organizer" %>
                  <span :if={event.reference_id} class="ml-2">
                    • <%= event.reference_id %>
                  </span>
                </div>
              </.link>
            </div>
          </div>
          <!-- Posts -->
          <div :if={length(@results.posts) > 0} class="p-2">
            <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
              Posts
            </div>
            <div class="space-y-1">
              <.link
                :for={post <- @results.posts}
                data-result-item
                navigate={~p"/admin/posts/#{post.id}"}
                class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
              >
                <div class="font-medium"><%= post.title %></div>
                <div class="text-xs text-zinc-500">
                  <%= if post.author,
                    do: "#{post.author.first_name} #{post.author.last_name}",
                    else: "No author" %>
                </div>
              </.link>
            </div>
          </div>
          <!-- Tickets -->
          <div :if={length(@results.tickets) > 0} class="p-2">
            <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
              Tickets
            </div>
            <div class="space-y-1">
              <.link
                :for={ticket <- @results.tickets}
                data-result-item
                navigate={~p"/admin/events/#{ticket.event_id}/tickets"}
                class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
              >
                <div class="font-medium">
                  <%= ticket.reference_id %>
                </div>
                <div class="text-xs text-zinc-500">
                  <%= ticket.event.title %>
                  <span :if={ticket.user} class="ml-2">
                    • <%= ticket.user.first_name %> <%= ticket.user.last_name %>
                  </span>
                </div>
              </.link>
            </div>
          </div>
          <!-- Users -->
          <div :if={length(@results.users) > 0} class="p-2">
            <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
              Users
            </div>
            <div class="space-y-1">
              <.link
                :for={user <- @results.users}
                data-result-item
                navigate={~p"/admin/users/#{user.id}/details"}
                class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
              >
                <div class="font-medium">
                  <%= user.first_name %> <%= user.last_name %>
                </div>
                <div class="text-xs text-zinc-500"><%= user.email %></div>
              </.link>
            </div>
          </div>
          <!-- Bookings -->
          <div :if={length(@results.bookings) > 0} class="p-2">
            <div class="px-3 py-2 text-xs font-semibold text-zinc-500 uppercase tracking-wider">
              Bookings
            </div>
            <div class="space-y-1">
              <.link
                :for={booking <- @results.bookings}
                data-result-item
                navigate={~p"/admin/bookings/#{booking.id}"}
                class="block px-3 py-2 text-sm text-zinc-800 hover:bg-zinc-50 rounded"
              >
                <div class="font-medium">
                  <%= booking.reference_id %>
                </div>
                <div class="text-xs text-zinc-500">
                  <%= if booking.user do
                    "#{booking.user.first_name} #{booking.user.last_name} • #{booking.property}"
                  else
                    "#{booking.property}"
                  end %>
                  <span class="ml-2">
                    <%= Timex.format!(booking.checkin_date, "{YYYY}-{0M}-{0D}") %> - <%= Timex.format!(
                      booking.checkout_date,
                      "{YYYY}-{0M}-{0D}"
                    ) %>
                  </span>
                </div>
              </.link>
            </div>
          </div>
        </div>

        <div
          :if={!@loading && !has_results?(@results)}
          class="p-4 text-center text-sm text-zinc-500"
        >
          No results found
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:results, %{
       events: [],
       posts: [],
       tickets: [],
       users: [],
       bookings: []
     })
     |> assign(:loading, false)
     |> assign(:show_results, false)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:query, "")
       |> assign(:results, %{
         events: [],
         posts: [],
         tickets: [],
         users: [],
         bookings: []
       })
       |> assign(:show_results, false)
       |> assign(:loading, false)}
    else
      results = Search.global_search(query, 5)

      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, results)
       |> assign(:show_results, true)
       |> assign(:loading, false)}
    end
  end

  def handle_event("close_results", _params, socket) do
    {:noreply, assign(socket, :show_results, false)}
  end

  defp has_results?(results) do
    results.events != [] ||
      results.posts != [] ||
      results.tickets != [] ||
      results.users != [] ||
      results.bookings != []
  end
end
