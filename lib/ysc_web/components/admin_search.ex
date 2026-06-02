defmodule YscWeb.AdminSearchComponent do
  @moduledoc """
  LiveComponent for the admin magic search box.
  Provides instant search across Events, Posts, Tickets, Users, and Bookings.
  """
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Search

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"admin-search-#{@id}"} class="relative w-full" phx-hook="AdminSearch">
      <form phx-change="search" phx-target={@myself} class="relative">
        <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
          <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500" />
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
          class="block pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded w-full bg-zinc-50 focus:ring-blue-500 focus:border-blue-500"
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
          <.admin_magic_search_section title="Events" show?={@results.events != []}>
            <.admin_magic_search_link
              :for={event <- @results.events}
              navigate={~p"/admin/events/#{event.id}/edit"}
            >
              <div class="font-medium">{event.title}</div>
              <div class="text-xs text-zinc-500">
                {if event.organizer,
                  do: "#{event.organizer.first_name} #{event.organizer.last_name}",
                  else: "No organizer"}
                <span :if={event.reference_id} class="ml-2">
                  • {event.reference_id}
                </span>
              </div>
            </.admin_magic_search_link>
          </.admin_magic_search_section>

          <.admin_magic_search_section title="Posts" show?={@results.posts != []}>
            <.admin_magic_search_link
              :for={post <- @results.posts}
              navigate={~p"/admin/posts/#{post.id}"}
            >
              <div class="font-medium">{post.title}</div>
              <div class="text-xs text-zinc-500">
                {if post.author,
                  do: "#{post.author.first_name} #{post.author.last_name}",
                  else: "No author"}
              </div>
            </.admin_magic_search_link>
          </.admin_magic_search_section>

          <.admin_magic_search_section
            title="Tickets"
            show?={@results.tickets != []}
          >
            <.admin_magic_search_link
              :for={ticket <- @results.tickets}
              navigate={~p"/admin/events/#{ticket.event_id}/tickets"}
            >
              <div class="font-medium">
                {ticket.reference_id}
              </div>
              <div class="text-xs text-zinc-500">
                {ticket.event.title}
                <span :if={ticket.user} class="ml-2">
                  • {ticket.user.first_name} {ticket.user.last_name}
                </span>
              </div>
            </.admin_magic_search_link>
          </.admin_magic_search_section>

          <.admin_magic_search_section title="Users" show?={@results.users != []}>
            <.admin_magic_search_link
              :for={user <- @results.users}
              navigate={~p"/admin/users/#{user.id}/details"}
            >
              <div class="font-medium">
                {user.first_name} {user.last_name}
              </div>
              <div class="text-xs text-zinc-500">{user.email}</div>
            </.admin_magic_search_link>
          </.admin_magic_search_section>

          <.admin_magic_search_section
            title="Bookings"
            show?={@results.bookings != []}
          >
            <.admin_magic_search_link
              :for={booking <- @results.bookings}
              navigate={~p"/admin/bookings/#{booking.id}"}
            >
              <div class="font-medium">
                {booking.reference_id}
              </div>
              <div class="text-xs text-zinc-500">
                {if booking.user do
                  "#{booking.user.first_name} #{booking.user.last_name} • #{booking.property}"
                else
                  "#{booking.property}"
                end}
                <span class="ml-2">
                  {Timex.format!(booking.checkin_date, "{YYYY}-{0M}-{0D}")} - {Timex.format!(
                    booking.checkout_date,
                    "{YYYY}-{0M}-{0D}"
                  )}
                </span>
              </div>
            </.admin_magic_search_link>
          </.admin_magic_search_section>
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
     |> assign(:results, empty_results())
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
       |> assign(:results, empty_results())
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

  defp empty_results do
    %{events: [], posts: [], tickets: [], users: [], bookings: []}
  end
end
