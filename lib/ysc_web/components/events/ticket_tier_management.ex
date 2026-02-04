defmodule YscWeb.AdminEventsLive.TicketTierManagement do
  use YscWeb, :live_component

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Ticket Tiers List -->
      <div class="border border-zinc-200 rounded p-4 sm:p-6">
        <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3 sm:gap-0 mb-4">
          <h3 class="text-lg font-semibold">Ticket Tiers</h3>
          <div class="flex items-center">
            <.button
              phx-click="open-add-ticket-tier-modal"
              phx-target={@myself}
              class="w-full sm:w-auto"
            >
              <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add Ticket Tier
            </.button>
          </div>
        </div>

        <div :if={length(@ticket_tiers) == 0} class="text-center py-8 text-zinc-500">
          <p class="font-semibold">No ticket tiers created yet.</p>
          <p class="text-sm">
            Click "Add Ticket Tier" to create your first ticket tier.
          </p>
        </div>

        <div :if={length(@ticket_tiers) > 0} class="space-y-3 sm:space-y-4">
          <%= for ticket_tier <- @ticket_tiers do %>
            <% is_donation =
              ticket_tier.type == "donation" || ticket_tier.type == :donation %>
            <div class="group border border-zinc-200 rounded-lg p-4 hover:border-blue-300 hover:shadow-sm transition-all bg-white">
              <div class="flex flex-col lg:flex-row lg:items-center gap-4">
                <div class="flex-1">
                  <div class="flex items-center gap-3 mb-1">
                    <h4 class="font-bold text-zinc-900 text-lg">
                      <%= ticket_tier.name %>
                    </h4>
                    <.badge
                      type={tier_status_badge_type(ticket_tier)}
                      class="text-[10px] uppercase tracking-wider font-bold rounded-full px-2 py-0.5 me-0"
                    >
                      <%= tier_status_text(ticket_tier) %>
                    </.badge>
                  </div>
                  <p
                    :if={ticket_tier.description}
                    class="text-zinc-500 text-sm mb-3 min-h-[2.5rem] lg:min-h-[1.25rem]"
                  >
                    <%= ticket_tier.description %>
                    <span class="text-zinc-400 italic text-xs">
                      — <%= String.capitalize(to_string(ticket_tier.type)) %> Tier
                    </span>
                  </p>
                  <p
                    :if={!ticket_tier.description}
                    class="text-zinc-400 text-sm italic mb-3 min-h-[2.5rem] lg:min-h-[1.25rem]"
                  >
                    <%= String.capitalize(to_string(ticket_tier.type)) %> Tier
                  </p>

                  <div class="grid grid-cols-2 md:grid-cols-4 gap-6 lg:gap-8">
                    <div>
                      <p class="text-[10px] uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Price
                      </p>
                      <p class="text-sm font-bold text-zinc-800">
                        <%= case ticket_tier.type do %>
                          <% "free" -> %>
                            Free
                          <% "donation" -> %>
                            User sets amount
                          <% :donation -> %>
                            User sets amount
                          <% _ -> %>
                            <%= format_money_safe(ticket_tier.price) %>
                        <% end %>
                      </p>
                    </div>

                    <div>
                      <p class="text-[10px] uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Sold
                      </p>
                      <div class="flex items-center gap-2">
                        <p class="text-sm font-bold text-zinc-800">
                          <%= case ticket_tier.quantity do %>
                            <% nil -> %>
                              <%= ticket_tier.sold_tickets_count %> /
                              <span class="text-zinc-400">∞</span>
                            <% 0 -> %>
                              <%= ticket_tier.sold_tickets_count %> /
                              <span class="text-zinc-400">∞</span>
                            <% quantity -> %>
                              <%= "#{ticket_tier.sold_tickets_count}/#{quantity}" %>
                          <% end %>
                        </p>
                        <div
                          :if={ticket_tier.quantity && ticket_tier.quantity > 0}
                          class="hidden sm:block w-16 h-1.5 bg-zinc-100 rounded-full overflow-hidden"
                        >
                          <div
                            class={[
                              "h-full rounded-full transition-all",
                              tier_progress_bar_classes(ticket_tier)
                            ]}
                            style={"width: #{tier_progress_percentage(ticket_tier)}%"}
                          >
                          </div>
                        </div>
                      </div>
                      <%= if !is_donation do %>
                        <% reserved_count =
                          get_reserved_count(ticket_tier.id, @reservations_by_tier) %>
                        <%= if reserved_count > 0 do %>
                          <p class="text-xs text-amber-600 mt-1">
                            <%= reserved_count %> reserved
                          </p>
                        <% end %>
                      <% end %>
                    </div>

                    <div>
                      <p class="text-[10px] uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Sales Period
                      </p>
                      <p class="text-sm text-zinc-700 whitespace-nowrap">
                        <%= format_sales_period(
                          ticket_tier.start_date,
                          ticket_tier.end_date
                        ) %>
                      </p>
                    </div>

                    <div>
                      <p class="text-[10px] uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Registration
                      </p>
                      <p class="text-sm text-zinc-700">
                        <%= if ticket_tier.requires_registration,
                          do: "Required",
                          else: "Not Required" %>
                      </p>
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-2 pt-4 lg:pt-0 border-t lg:border-t-0 border-zinc-100">
                  <%= if !is_donation do %>
                    <button
                      phx-click="reserve-tickets"
                      phx-value-tier-id={ticket_tier.id}
                      phx-target={@myself}
                      phx-disable-with="Loading..."
                      class="p-2 text-zinc-400 hover:text-amber-600 hover:bg-amber-50 rounded-md transition-colors"
                    >
                      <.icon name="hero-ticket" class="w-5 h-5" />
                    </button>
                  <% end %>
                  <button
                    phx-click="edit-ticket-tier"
                    phx-value-id={ticket_tier.id}
                    phx-target={@myself}
                    phx-disable-with="Loading..."
                    class="p-2 text-zinc-400 hover:text-blue-600 hover:bg-blue-50 rounded-md transition-colors"
                  >
                    <.icon name="hero-pencil" class="w-5 h-5" />
                  </button>
                  <button
                    phx-click="delete-ticket-tier"
                    phx-value-id={ticket_tier.id}
                    phx-target={@myself}
                    phx-disable-with="Deleting..."
                    data-confirm="Are you sure you want to delete this ticket tier? This action cannot be undone."
                    disabled={ticket_tier.sold_tickets_count > 0}
                    class={[
                      "p-2 rounded-md transition-colors",
                      if ticket_tier.sold_tickets_count > 0 do
                        "text-zinc-300 cursor-not-allowed"
                      else
                        "text-zinc-400 hover:text-red-600 hover:bg-red-50"
                      end
                    ]}
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              </div>
              <!-- Reservations Section -->
              <%= if !is_donation do %>
                <% reservations = Map.get(@reservations_by_tier, ticket_tier.id, []) %>
                <%= if length(reservations) > 0 do %>
                  <div class="mt-4 pt-4 border-t border-zinc-200">
                    <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-2">
                      Active Reservations
                    </p>
                    <div class="space-y-2">
                      <%= for reservation <- reservations do %>
                        <div class="flex items-center justify-between p-2 bg-amber-50 rounded border border-amber-200">
                          <div class="flex-1">
                            <p class="text-sm font-medium text-zinc-900">
                              <%= reservation.user.first_name %> <%= reservation.user.last_name %>
                            </p>
                            <p class="text-xs text-zinc-600">
                              <%= reservation.user.email %> • <%= reservation.quantity %> ticket<%= if reservation.quantity !=
                                                                                                         1,
                                                                                                       do:
                                                                                                         "s" %>
                              <%= if reservation.discount_percentage && Decimal.gt?(reservation.discount_percentage, 0) do %>
                                <span class="text-green-600 font-medium">
                                  • <%= Decimal.to_float(
                                    reservation.discount_percentage
                                  )
                                  |> Float.round(2) %>% off
                                </span>
                              <% end %>
                              <span
                                :if={reservation.expires_at}
                                class="text-amber-600"
                              >
                                • Expires <%= format_date(reservation.expires_at) %>
                              </span>
                            </p>
                          </div>
                          <button
                            phx-click="cancel-reservation"
                            phx-value-id={reservation.id}
                            phx-target={@myself}
                            phx-disable-with="Cancelling..."
                            data-confirm="Are you sure you want to cancel this reservation?"
                            class="p-1.5 text-amber-600 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
                          >
                            <.icon name="hero-x-mark" class="w-4 h-4" />
                          </button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Ticket Purchases Summary -->
      <div class="border border-zinc-200 rounded p-4 sm:p-6">
        <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-2 sm:gap-0 mb-4">
          <h3 class="text-lg font-semibold">Ticket Purchases</h3>
          <div class="flex items-center gap-3">
            <span class="text-sm text-zinc-600">
              <%= length(@ticket_purchases) %> purchase<%= if length(
                                                                @ticket_purchases
                                                              ) != 1, do: "s" %>
            </span>
            <.button
              phx-click="export-tickets-csv"
              phx-target={@myself}
              phx-disable-with="Exporting..."
              color="blue"
              class="w-full sm:w-auto"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4 me-1" /> Export CSV
            </.button>
          </div>
        </div>

        <div
          :if={length(@ticket_purchases) == 0}
          class="text-center py-8 text-zinc-500"
        >
          <p class="font-semibold">No tickets purchased yet.</p>
          <p class="text-sm">
            Ticket purchases will appear here once users start buying tickets.
          </p>
        </div>

        <div :if={length(@ticket_purchases) > 0} class="space-y-3 sm:space-y-4">
          <%= for purchase <- @ticket_purchases do %>
            <div class="border border-zinc-200 rounded p-3 sm:p-4">
              <div class="flex flex-col sm:flex-row sm:justify-between sm:items-start gap-3 sm:gap-0">
                <div class="flex-1">
                  <div class="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-3 mb-2">
                    <h4 class="font-semibold"><%= purchase.user_name %></h4>
                    <span class="text-sm text-zinc-600">
                      <%= purchase.user_email %>
                    </span>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4 text-sm">
                    <div>
                      <span class="font-medium text-zinc-700">Ticket Tier:</span>
                      <span class="ml-1"><%= purchase.ticket_tier_name %></span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Quantity:</span>
                      <span class="ml-1"><%= purchase.ticket_count %></span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Total:</span>
                      <span class="ml-1">
                        <%= case purchase.total_amount do %>
                          <% %Money{amount: 0} -> %>
                            Free
                          <% amount -> %>
                            <%= format_money_safe(amount) %>
                        <% end %>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Add Ticket Tier Modal -->
      <.modal
        :if={@show_add_modal}
        id="add-ticket-tier-modal"
        show
        on_cancel={JS.push("close-add-ticket-tier-modal", target: @myself)}
      >
        <.live_component
          id={"ticket-tier-form-#{@event_id}"}
          module={YscWeb.AdminEventsLive.TicketTierForm}
          event_id={@event_id}
        />
      </.modal>
      <!-- Edit Ticket Tier Modal -->
      <.modal
        :if={@show_edit_modal}
        id="edit-ticket-tier-modal"
        show
        on_cancel={JS.push("close-edit-ticket-tier-modal", target: @myself)}
      >
        <.live_component
          :if={@editing_ticket_tier}
          id={"edit-ticket-tier-form-#{@editing_ticket_tier.id}"}
          module={YscWeb.AdminEventsLive.TicketTierForm}
          event_id={@event_id}
          ticket_tier={@editing_ticket_tier}
        />
      </.modal>
      <!-- Reserve Tickets Modal -->
      <.modal
        :if={@show_reserve_modal && @reserving_tier}
        id="reserve-tickets-modal"
        show
        on_cancel={JS.push("close-reserve-tickets-modal", target: @myself)}
      >
        <.live_component
          id={"ticket-reservation-form-#{@reserving_tier.id}"}
          module={YscWeb.AdminEventsLive.TicketReservationForm}
          ticket_tier={@reserving_tier}
          ticket_tier_id={@reserving_tier.id}
          event_id={@event_id}
          current_user={@current_user}
        />
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    # Check if this is an update to close the reserve modal
    close_modal = Map.get(assigns, :close_reserve_modal, false)

    ticket_tiers = Events.list_ticket_tiers_for_event(assigns.event_id)
    ticket_purchases = Events.get_ticket_purchase_summary(assigns.event_id)

    # Load reservations for each tier
    reservations_by_tier =
      ticket_tiers
      |> Enum.map(fn tier ->
        reservations = Events.list_active_reservations_for_tier(tier.id)
        {tier.id, reservations}
      end)
      |> Map.new()

    socket =
      socket
      |> assign(assigns)
      |> assign(:ticket_tiers, ticket_tiers)
      |> assign(:ticket_purchases, ticket_purchases)
      |> assign(:reservations_by_tier, reservations_by_tier)
      |> assign(:editing_ticket_tier, nil)
      |> assign(:current_user, assigns[:current_user])

    socket =
      if close_modal do
        # Explicitly close the reserve modal
        socket
        |> assign(:show_reserve_modal, false)
        |> assign(:reserving_tier, nil)
        |> assign(:show_add_modal, false)
        |> assign(:show_edit_modal, false)
      else
        # Normal update - preserve modal states unless explicitly set in assigns
        socket
        |> assign(
          :show_add_modal,
          Map.get(
            assigns,
            :show_add_modal,
            socket.assigns[:show_add_modal] || false
          )
        )
        |> assign(
          :show_edit_modal,
          Map.get(
            assigns,
            :show_edit_modal,
            socket.assigns[:show_edit_modal] || false
          )
        )
        |> assign(
          :show_reserve_modal,
          Map.get(
            assigns,
            :show_reserve_modal,
            socket.assigns[:show_reserve_modal] || false
          )
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("open-add-ticket-tier-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  @impl true
  def handle_event("close-add-ticket-tier-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  @impl true
  def handle_event("close-edit-ticket-tier-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:editing_ticket_tier, nil)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    # Refresh the ticket tier list when modal closes (in case a new tier was added or updated)
    ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:editing_ticket_tier, nil)
     |> assign(:ticket_tiers, ticket_tiers)}
  end

  @impl true
  def handle_event("edit-ticket-tier", %{"id" => id}, socket) do
    ticket_tier = Events.get_ticket_tier!(id)

    {:noreply,
     socket
     |> assign(:show_edit_modal, true)
     |> assign(:editing_ticket_tier, ticket_tier)}
  end

  @impl true
  def handle_event("delete-ticket-tier", %{"id" => id}, socket) do
    ticket_tier = Events.get_ticket_tier!(id)

    # Check if any tickets have been sold for this tier
    sold_count = Events.count_tickets_for_tier(id)

    if sold_count > 0 do
      {:noreply,
       put_flash(socket, :error, "Cannot delete ticket tier with sold tickets")}
    else
      case Events.delete_ticket_tier(ticket_tier) do
        {:ok, _ticket_tier} ->
          ticket_tiers =
            Events.list_ticket_tiers_for_event(socket.assigns.event_id)

          {:noreply,
           socket
           |> put_flash(:info, "Ticket tier deleted successfully")
           |> assign(:ticket_tiers, ticket_tiers)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete ticket tier")}
      end
    end
  end

  @impl true
  def handle_event("export-tickets-csv", _params, socket) do
    tickets = Events.list_tickets_for_export(socket.assigns.event_id)

    csv_content =
      tickets
      |> build_csv_rows()
      |> CSV.encode(headers: true)
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    filename = "tickets_export_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    # Base64 encode the content for download
    encoded_content = Base.encode64(csv_content)

    {:noreply,
     socket
     |> push_event("download-csv", %{
       content: encoded_content,
       filename: filename
     })}
  end

  @impl true
  def handle_event("reserve-tickets", %{"tier-id" => tier_id}, socket) do
    ticket_tier = Events.get_ticket_tier!(tier_id)

    # Don't allow reservations for donation tiers
    is_donation =
      ticket_tier.type == "donation" || ticket_tier.type == :donation

    if is_donation do
      {:noreply,
       socket
       |> put_flash(:error, "Reservations are not available for donation tiers")}
    else
      {:noreply,
       socket
       |> assign(:show_reserve_modal, true)
       |> assign(:reserving_tier, ticket_tier)}
    end
  end

  @impl true
  def handle_event("close-reserve-tickets-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reserve_modal, false)
     |> assign(:reserving_tier, nil)}
  end

  @impl true
  def handle_event("cancel-reservation", %{"id" => id}, socket) do
    reservation = Events.get_ticket_reservation!(id)

    case Events.cancel_ticket_reservation(reservation) do
      {:ok, _reservation} ->
        # Refresh reservations
        reservations_by_tier = refresh_reservations(socket.assigns.event_id)

        ticket_tiers =
          Events.list_ticket_tiers_for_event(socket.assigns.event_id)

        {:noreply,
         socket
         |> put_flash(:info, "Reservation cancelled successfully")
         |> assign(:ticket_tiers, ticket_tiers)
         |> assign(:reservations_by_tier, reservations_by_tier)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel reservation")}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ticket_reservation_created, event_id}, socket) do
    if event_id == socket.assigns.event_id do
      reservations_by_tier = refresh_reservations(event_id)
      ticket_tiers = Events.list_ticket_tiers_for_event(event_id)

      {:noreply,
       socket
       |> put_flash(:info, "Ticket reservation created successfully")
       |> assign(:show_reserve_modal, false)
       |> assign(:reserving_tier, nil)
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:reservations_by_tier, reservations_by_tier)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation
         }},
        socket
      ) do
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event_id do
      reservations_by_tier = refresh_reservations(socket.assigns.event_id)
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:reservations_by_tier, reservations_by_tier)
       |> assign(:show_reserve_modal, false)
       |> assign(:reserving_tier, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event_id do
      reservations_by_tier = refresh_reservations(socket.assigns.event_id)
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:reservations_by_tier, reservations_by_tier)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events,
         %Ysc.MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation
         }},
        socket
      ) do
    ticket_tier = Events.get_ticket_tier(reservation.ticket_tier_id)

    if ticket_tier && ticket_tier.event_id == socket.assigns.event_id do
      reservations_by_tier = refresh_reservations(socket.assigns.event_id)
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

      {:noreply,
       socket
       |> assign(:ticket_tiers, ticket_tiers)
       |> assign(:reservations_by_tier, reservations_by_tier)}
    else
      {:noreply, socket}
    end
  end

  defp refresh_reservations(event_id) do
    ticket_tiers = Events.list_ticket_tiers_for_event(event_id)

    ticket_tiers
    |> Enum.map(fn tier ->
      reservations = Events.list_active_reservations_for_tier(tier.id)
      {tier.id, reservations}
    end)
    |> Map.new()
  end

  defp get_reserved_count(tier_id, reservations_by_tier) do
    reservations = Map.get(reservations_by_tier, tier_id, [])

    Enum.reduce(reservations, 0, fn reservation, acc ->
      acc + reservation.quantity
    end)
  end

  defp build_csv_rows(tickets) do
    Enum.map(tickets, fn ticket ->
      # Purchaser information (user who bought the ticket)
      purchaser_first_name = ticket.user.first_name || ""
      purchaser_last_name = ticket.user.last_name || ""
      purchaser_email = ticket.user.email || ""
      phone = ticket.user.phone_number || ""

      # Attendee information (from ticket_detail if registration was required)
      {attendee_first_name, attendee_last_name, attendee_email} =
        if ticket.ticket_tier && ticket.ticket_tier.requires_registration &&
             ticket.ticket_detail do
          {
            ticket.ticket_detail.first_name || "",
            ticket.ticket_detail.last_name || "",
            ticket.ticket_detail.email || ""
          }
        else
          # If no registration required, attendee is the same as purchaser
          {purchaser_first_name, purchaser_last_name, purchaser_email}
        end

      # Build CSV row with both purchaser and attendee information
      base_row = %{
        "Ticket Reference" => ticket.reference_id || "",
        "Ticket Tier" => (ticket.ticket_tier && ticket.ticket_tier.name) || "",
        "Purchaser First Name" => purchaser_first_name,
        "Purchaser Last Name" => purchaser_last_name,
        "Purchaser Email" => purchaser_email,
        "Purchaser Phone" => phone,
        "Attendee First Name" => attendee_first_name,
        "Attendee Last Name" => attendee_last_name,
        "Attendee Email" => attendee_email
      }

      # If ticket details exist, add a note that registration was provided
      if ticket.ticket_detail do
        Map.put(base_row, "Registration Provided", "Yes")
      else
        Map.put(base_row, "Registration Provided", "No")
      end
    end)
  end

  defp format_sales_period(nil, nil), do: "Always available"

  defp format_sales_period(start_date, nil),
    do: "From #{format_date(start_date)}"

  defp format_sales_period(nil, end_date), do: "Until #{format_date(end_date)}"

  defp format_sales_period(start_date, end_date),
    do: "#{format_date(start_date)} - #{format_date(end_date)}"

  defp format_date(nil), do: ""

  defp format_date(date) when is_binary(date) do
    case Timex.parse(date, "{ISO:Extended}") do
      {:ok, parsed_date} -> Timex.format!(parsed_date, "{Mshort} {D}, {YYYY}")
      {:error, _} -> date
    end
  end

  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp format_money_safe(nil), do: "—"
  defp format_money_safe(""), do: "—"

  defp format_money_safe(%Money{} = money) do
    case Ysc.MoneyHelper.format_money(money) do
      formatted when is_binary(formatted) and formatted != "" -> formatted
      {:ok, formatted} when is_binary(formatted) -> formatted
      {:error, _} -> "Invalid amount"
      _ -> "—"
    end
  end

  defp format_money_safe(_), do: "—"

  # Check if ticket tier is currently active (on sale)
  defp tier_is_active?(ticket_tier) do
    now = DateTime.utc_now()

    # Check if sale has started
    sale_started =
      case ticket_tier.start_date do
        nil -> true
        start_date -> DateTime.compare(now, start_date) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case ticket_tier.end_date do
        nil -> false
        end_date -> DateTime.compare(now, end_date) == :gt
      end

    sale_started && !sale_ended
  end

  # Check if ticket tier is scheduled (not yet started)
  defp tier_is_scheduled?(ticket_tier) do
    case ticket_tier.start_date do
      nil -> false
      start_date -> DateTime.compare(DateTime.utc_now(), start_date) == :lt
    end
  end

  # Get status badge type based on tier state
  defp tier_status_badge_type(ticket_tier) do
    cond do
      tier_is_active?(ticket_tier) -> "green"
      tier_is_scheduled?(ticket_tier) -> "yellow"
      true -> "dark"
    end
  end

  # Get status text based on tier state
  defp tier_status_text(ticket_tier) do
    cond do
      tier_is_active?(ticket_tier) -> "Active"
      tier_is_scheduled?(ticket_tier) -> "Scheduled"
      true -> "Ended"
    end
  end

  # Calculate progress percentage for sold tickets
  defp tier_progress_percentage(ticket_tier) do
    case ticket_tier.quantity do
      nil ->
        0

      0 ->
        0

      quantity when quantity > 0 ->
        sold = ticket_tier.sold_tickets_count || 0
        min(100, round(sold / quantity * 100))

      _ ->
        0
    end
  end

  # Get progress bar color classes based on percentage
  defp tier_progress_bar_classes(ticket_tier) do
    percentage = tier_progress_percentage(ticket_tier)

    cond do
      percentage >= 100 -> "bg-zinc-400"
      percentage >= 90 -> "bg-amber-500"
      true -> "bg-blue-600"
    end
  end
end
