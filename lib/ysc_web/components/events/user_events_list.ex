defmodule YscWeb.UserEventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@ticket_count > 0} class="space-y-4">
        <div
          :for={{id, ticket} <- @streams.tickets}
          class="flex flex-col md:flex-row gap-4 p-4 border border-zinc-200 rounded-lg hover:bg-zinc-50 transition-colors"
          id={id}
        >
          <div :if={ticket.event.image_id} class="flex-shrink-0 w-full md:w-32">
            <.live_component
              id={"user-event-image-#{ticket.event.id}"}
              module={YscWeb.Components.Image}
              image_id={ticket.event.image_id}
              aspect_class="aspect-[4/3]"
            />
          </div>

          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center text-sm text-zinc-500">
                <time>
                  <%= Timex.format!(
                    ticket.event.start_date,
                    "{WDshort}, {Mshort} {D}"
                  ) %>
                </time>
                <span
                  :if={
                    ticket.event.start_time != nil && ticket.event.start_time != ""
                  }
                  class="ml-2"
                >
                  • <%= format_start_time(ticket.event.start_time) %>
                </span>
              </div>
              <div class="flex items-center space-x-2">
                <.badge :if={ticket.event.state == :cancelled} type="red">
                  Cancelled
                </.badge>
                <.badge :if={ticket.status == :confirmed} type="green">
                  Confirmed
                </.badge>
                <.badge :if={ticket.status == :pending} type="yellow">
                  Pending
                </.badge>
              </div>
            </div>

            <.link navigate={~p"/events/#{ticket.event.id}"} class="block">
              <h3 class="text-lg font-semibold text-zinc-900 hover:text-blue-600 transition-colors mb-2">
                <%= ticket.event.title %>
              </h3>
            </.link>

            <div class="flex items-center justify-between">
              <div class="text-sm text-zinc-600">
                <p :if={ticket.event.location_name} class="mb-1">
                  <.icon name="hero-map-pin" class="w-4 h-4 inline mr-1" />
                  <%= ticket.event.location_name %>
                </p>
                <p class="font-medium">
                  Ticket: <%= ticket.ticket_tier.name %>
                  <span :if={
                    ticket.ticket_tier.price && ticket.ticket_tier.price.amount > 0
                  }>
                    • <%= Ysc.MoneyHelper.format_money!(ticket.ticket_tier.price) %>
                  </span>
                </p>
              </div>
              <div class="text-xs text-zinc-500">
                <p>Ref: <%= ticket.reference_id %></p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@ticket_count == 0} class="text-center py-8">
        <div class="text-zinc-500">
          <.icon name="hero-ticket" class="w-12 h-12 mx-auto mb-4 text-zinc-400" />
          <p class="text-lg font-medium text-zinc-600">No upcoming events</p>
          <p class="text-sm text-zinc-500">
            You haven't registered for any events yet.
          </p>
          <.link
            navigate={~p"/events"}
            class="inline-flex items-center mt-4 text-blue-600 hover:text-blue-800 text-sm font-medium"
          >
            Browse events →
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    user_id = assigns.current_user.id
    tickets = Events.list_upcoming_events_for_user(user_id)
    ticket_count = length(tickets)

    {:ok,
     socket |> stream(:tickets, tickets) |> assign(:ticket_count, ticket_count)}
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
  end
end
