defmodule YscWeb.AdminEventsLive.TicketTierManagement do
  use YscWeb, :live_component

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"ticket-tier-management-#{@event_id}"} class="space-y-6">
      <div
        :if={@event.partiful_link not in [nil, ""]}
        class="border border-blue-100 rounded-lg p-4 bg-blue-50 flex items-center gap-3"
      >
        <.icon
          name="hero-information-circle"
          class="w-5 h-5 text-blue-600 flex-shrink-0"
        />
        <p class="text-sm text-blue-800">
          This event also has a
          <a
            href={@event.partiful_link}
            target="_blank"
            rel="noopener noreferrer"
            class="font-semibold underline"
          >
            Partiful link
          </a>
          set on the Details tab. It's shown to attendees alongside these ticket tiers.
        </p>
      </div>
      <%!-- Ticket Tiers List --%>
      <div class="border border-zinc-200 rounded p-4 sm:p-6">
        <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3 sm:gap-0 mb-4">
          <h3 class="text-lg font-semibold">Ticket Tiers</h3>
          <div class="flex items-center">
            <.button
              phx-click="open-add-ticket-tier-modal"
              phx-target={@myself}
              class="w-full sm:w-auto"
            >
              <.icon name="hero-plus" class="w-5 h-5" /> Add Ticket Tier
            </.button>
          </div>
        </div>

        <%= if length(@ticket_tiers) == 0 do %>
          <div class="flex items-center gap-2 mt-4 p-4 bg-amber-50 border border-amber-200 rounded-lg">
            <.icon
              name="hero-information-circle"
              class="w-5 h-5 text-amber-600 flex-shrink-0"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-amber-900">
                Tickets Coming Soon
              </p>
              <p class="text-xs text-amber-700">
                Enable this to show users that tickets will be available but details are not ready yet.
                The flag will automatically clear when you add your first ticket tier.
              </p>
            </div>
            <.toggle
              id="tickets-tbd-toggle"
              checked={@event.tickets_tbd}
              label={if @event.tickets_tbd, do: "TBD Enabled", else: "Set as TBD"}
              phx-click="toggle-tickets-tbd"
              phx-target={@myself}
              class="flex-shrink-0"
            />
          </div>
        <% end %>

        <div
          :if={length(@ticket_tiers) == 0}
          class="text-center py-8 text-zinc-500"
        >
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
                      {ticket_tier.name}
                    </h4>
                    <.badge
                      type={tier_status_badge_type(ticket_tier)}
                      class="text-xs uppercase tracking-wider font-bold rounded-full px-2 py-0.5 me-0"
                    >
                      {tier_status_text(ticket_tier)}
                    </.badge>
                    <.badge
                      :if={ticket_tier.member_only}
                      type="violet"
                      class="inline-flex items-center gap-1 text-xs uppercase tracking-wider font-bold rounded-full px-2 py-0.5 me-0"
                    >
                      <.icon name="hero-lock-closed" class="w-3 h-3" /> Member only
                    </.badge>
                  </div>
                  <p
                    :if={ticket_tier.description}
                    class="text-zinc-500 text-sm mb-3 min-h-[2.5rem] lg:min-h-[1.25rem]"
                  >
                    {ticket_tier.description}
                    <span class="text-zinc-400 italic text-xs">
                      — {String.capitalize(to_string(ticket_tier.type))} Tier
                    </span>
                  </p>
                  <p
                    :if={!ticket_tier.description}
                    class="text-zinc-400 text-sm italic mb-3 min-h-[2.5rem] lg:min-h-[1.25rem]"
                  >
                    {String.capitalize(to_string(ticket_tier.type))} Tier
                  </p>

                  <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 lg:gap-6">
                    <div>
                      <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-1">
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
                            {format_money_safe(ticket_tier.price)}
                        <% end %>
                      </p>
                    </div>

                    <div>
                      <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Sold
                      </p>
                      <div class="flex items-center gap-2">
                        <p class="text-sm font-bold text-zinc-800">
                          <%= case ticket_tier.quantity do %>
                            <% nil -> %>
                              {ticket_tier.sold_tickets_count} /
                              <span class="text-zinc-400">∞</span>
                            <% 0 -> %>
                              {ticket_tier.sold_tickets_count} /
                              <span class="text-zinc-400">∞</span>
                            <% quantity -> %>
                              {"#{ticket_tier.sold_tickets_count}/#{quantity}"}
                          <% end %>
                        </p>
                        <div
                          :if={ticket_tier.quantity && ticket_tier.quantity > 0}
                          class="hidden sm:block w-16 h-1.5 bg-zinc-100 rounded-full overflow-hidden shrink-0"
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
                          get_reserved_count(
                            ticket_tier.id,
                            @reservations_by_tier
                          ) %>
                        <%= if reserved_count > 0 do %>
                          <p class="text-xs text-amber-600 mt-1">
                            {reserved_count} reserved
                          </p>
                        <% end %>
                      <% end %>
                    </div>

                    <div>
                      <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Sales Period
                      </p>
                      <p class="text-sm text-zinc-700 leading-tight">
                        {format_sales_period(
                          ticket_tier.start_date,
                          ticket_tier.end_date
                        )}
                      </p>
                    </div>

                    <div>
                      <p class="text-xs uppercase tracking-wide text-zinc-400 font-semibold mb-1">
                        Registration
                      </p>
                      <p class="text-sm text-zinc-700">
                        {if ticket_tier.requires_registration,
                          do: "Required",
                          else: "Not Required"}
                      </p>
                    </div>
                  </div>
                </div>

                <div class="flex justify-end pt-4 lg:pt-0 border-t lg:border-t-0 border-zinc-100">
                  <.row_actions_dropdown
                    id={"ticket-tier-actions-#{ticket_tier.id}"}
                    label={"Actions for #{ticket_tier.name}"}
                  >
                    <.dropdown_menu_item
                      :if={!is_donation and @admin_role == :admin}
                      id={"ticket-tier-actions-#{ticket_tier.id}-grant"}
                      icon="hero-gift"
                      tone={:success}
                      phx-click="grant-tickets"
                      phx-value-id={ticket_tier.id}
                      phx-target={@myself}
                    >
                      Grant tickets
                    </.dropdown_menu_item>
                    <.dropdown_menu_item
                      :if={!is_donation and @admin_role == :admin}
                      id={"ticket-tier-actions-#{ticket_tier.id}-reserve"}
                      icon="hero-ticket"
                      tone={:info}
                      phx-click="reserve-tickets"
                      phx-value-id={ticket_tier.id}
                      phx-target={@myself}
                    >
                      Reserve tickets
                    </.dropdown_menu_item>
                    <.dropdown_menu_item
                      id={"ticket-tier-actions-#{ticket_tier.id}-edit"}
                      icon="hero-pencil-square"
                      phx-click="edit-ticket-tier"
                      phx-value-id={ticket_tier.id}
                      phx-target={@myself}
                    >
                      Edit tier
                    </.dropdown_menu_item>
                    <.dropdown_menu_item
                      id={"ticket-tier-actions-#{ticket_tier.id}-delete"}
                      icon="hero-trash"
                      tone={:danger}
                      phx-click="delete-ticket-tier"
                      phx-value-id={ticket_tier.id}
                      phx-target={@myself}
                      data-confirm="Are you sure you want to delete this ticket tier? This action cannot be undone."
                      disabled={ticket_tier.sold_tickets_count > 0}
                      class={
                        if ticket_tier.sold_tickets_count > 0,
                          do: "opacity-50 cursor-not-allowed hover:bg-transparent"
                      }
                    >
                      Delete tier
                    </.dropdown_menu_item>
                  </.row_actions_dropdown>
                </div>
              </div>
              <%!-- Reservations Section --%>
              <%= if !is_donation do %>
                <% reservations =
                  Map.get(@reservations_by_tier, ticket_tier.id, []) %>
                <% expired_reservations =
                  Map.get(@expired_reservations_by_tier, ticket_tier.id, []) %>
                <%= if length(reservations) > 0 do %>
                  <div class="mt-4 pt-4 border-t border-zinc-200">
                    <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-2">
                      Active Reservations
                    </p>
                    <div class="space-y-2">
                      <%= for reservation <- reservations do %>
                        <div class="flex items-start justify-between gap-3 p-3 bg-amber-50 rounded-lg border border-amber-200">
                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-zinc-900 truncate">
                              {reservation.user.first_name} {reservation.user.last_name}
                            </p>
                            <p class="text-xs text-zinc-600 truncate">
                              {reservation.user.email}
                            </p>
                            <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs text-zinc-600">
                              <span>
                                {reservation.quantity} ticket{if reservation.quantity !=
                                                                   1,
                                                                 do: "s"}
                              </span>
                              <%= if reservation.discount_percentage && Decimal.gt?(reservation.discount_percentage, 0) do %>
                                <span class="text-green-600 font-medium">
                                  {Decimal.to_float(reservation.discount_percentage)
                                  |> Float.round(2)}% off
                                </span>
                              <% end %>
                              <span
                                :if={reservation.expires_at}
                                class="text-amber-600"
                              >
                                Expires {format_date(reservation.expires_at)}
                              </span>
                            </div>
                          </div>
                          <button
                            :if={@admin_role == :admin}
                            id={"cancel-reservation-#{reservation.id}"}
                            phx-click="cancel-reservation"
                            phx-value-id={reservation.id}
                            phx-target={@myself}
                            phx-disable-with="Cancelling..."
                            data-confirm="Are you sure you want to cancel this reservation?"
                            class="shrink-0 p-1.5 text-amber-600 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
                          >
                            <.icon name="hero-x-mark" class="w-4 h-4" />
                          </button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                <%= if length(expired_reservations) > 0 do %>
                  <div class="mt-4 pt-4 border-t border-zinc-200">
                    <p class="text-xs font-semibold text-red-800 uppercase tracking-wide mb-1">
                      Expired Reservations
                    </p>
                    <p class="text-xs text-zinc-500 mb-2">
                      Past end date — no checkout discount until cancelled or reissued.
                    </p>
                    <div class="space-y-2">
                      <%= for reservation <- expired_reservations do %>
                        <div class="flex items-start justify-between gap-3 p-3 bg-zinc-100 rounded-lg border border-zinc-300">
                          <div class="flex-1 min-w-0">
                            <p class="text-sm font-medium text-zinc-900 truncate">
                              {reservation.user.first_name} {reservation.user.last_name}
                            </p>
                            <p class="text-xs text-zinc-600 truncate">
                              {reservation.user.email}
                            </p>
                            <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1 text-xs text-zinc-600">
                              <span>
                                {reservation.quantity} ticket{if reservation.quantity !=
                                                                   1,
                                                                 do: "s"}
                              </span>
                              <%= if reservation.discount_percentage && Decimal.gt?(reservation.discount_percentage, 0) do %>
                                <span class="text-green-600 font-medium">
                                  {Decimal.to_float(reservation.discount_percentage)
                                  |> Float.round(2)}% off
                                </span>
                              <% end %>
                              <span class="text-red-700 font-medium">
                                Ended {format_date(reservation.expires_at)}
                              </span>
                            </div>
                          </div>
                          <button
                            :if={@admin_role == :admin}
                            id={"cancel-reservation-#{reservation.id}"}
                            phx-click="cancel-reservation"
                            phx-value-id={reservation.id}
                            phx-target={@myself}
                            phx-disable-with="Cancelling..."
                            data-confirm="Are you sure you want to cancel this reservation?"
                            class="shrink-0 p-1.5 text-zinc-500 hover:text-red-600 hover:bg-red-50 rounded transition-colors"
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
      <.live_component
        id={"ticket-list-#{@event_id}"}
        module={YscWeb.AdminEventsLive.TicketList}
        event_id={@event_id}
        refresh_token={@ticket_list_refresh_token}
        admin_role={@admin_role}
      />
      <button
        id={"ticket-tier-grant-event-#{@event_id}"}
        type="button"
        class="hidden"
        phx-click="grant-tickets"
        phx-target={@myself}
      />
      <button
        id={"ticket-tier-reserve-event-#{@event_id}"}
        type="button"
        class="hidden"
        phx-click="reserve-tickets"
        phx-target={@myself}
      />
      <button
        id={"ticket-tier-cancel-reservation-event-#{@event_id}"}
        type="button"
        class="hidden"
        phx-click="cancel-reservation"
        phx-target={@myself}
      />
      <%!-- Add Ticket Tier Modal --%>
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
          dialog_id="add-ticket-tier-modal"
        />
      </.modal>
      <%!-- Edit Ticket Tier Modal --%>
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
          dialog_id="edit-ticket-tier-modal"
        />
      </.modal>
      <%!-- Reserve Tickets Modal --%>
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
          admin_role={@admin_role}
        />
      </.modal>
      <%!-- Grant Tickets Modal --%>
      <.modal
        :if={@show_grant_modal && @granting_tier}
        id="grant-tickets-modal"
        show
        on_cancel={JS.push("close-grant-tickets-modal", target: @myself)}
      >
        <.live_component
          id={"ticket-grant-form-#{@granting_tier.id}"}
          module={YscWeb.AdminEventsLive.TicketGrantForm}
          dialog_id="grant-tickets-modal"
          ticket_tier={@granting_tier}
          ticket_tier_id={@granting_tier.id}
          event_id={@event_id}
          current_user={@current_user}
          admin_role={@admin_role}
        />
      </.modal>
    </div>
    """
  end

  @reservation_update_keys [:id, :reservation_epoch, :close_reserve_modal]
  @grant_update_keys [:id, :grant_epoch, :close_grant_modal, :grant_success]
  @parent_passthrough_keys [:id, :event_id, :event, :current_user, :admin_role]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :ticket_list_refresh_token, 0)}
  end

  @impl true
  def update(incoming_assigns, socket) do
    socket = assign_new(socket, :admin_role, fn -> nil end)
    close_reserve_modal = Map.get(incoming_assigns, :close_reserve_modal, false)
    close_grant_modal = Map.get(incoming_assigns, :close_grant_modal, false)
    grant_success = Map.get(incoming_assigns, :grant_success)

    socket =
      cond do
        reservation_only_update?(incoming_assigns) and
            socket.assigns[:ticket_tiers] != nil ->
          ticket_tiers = socket.assigns.ticket_tiers

          {reservations_by_tier, expired_reservations_by_tier} =
            load_reservations_maps(ticket_tiers)

          socket
          |> assign(:reservations_by_tier, reservations_by_tier)
          |> assign(:expired_reservations_by_tier, expired_reservations_by_tier)

        parent_passthrough_only_update?(incoming_assigns) and
            socket.assigns[:ticket_tiers] != nil ->
          socket
          |> maybe_assign_parent_passthrough(incoming_assigns)

        true ->
          # Parent send_update/2 only passes a few keys; merge with prior component assigns
          # so required fields (e.g. event_id) are always present.
          assigns =
            socket.assigns
            |> Map.take([
              :event_id,
              :event,
              :current_user,
              :admin_role,
              :show_add_modal,
              :show_edit_modal,
              :show_reserve_modal,
              :reserving_tier,
              :show_grant_modal,
              :granting_tier,
              :editing_ticket_tier
            ])
            |> Map.merge(incoming_assigns)

          event =
            Map.get(assigns, :event) || Events.get_event!(assigns.event_id)

          ticket_tiers = Events.list_ticket_tiers_for_event(assigns.event_id)

          {reservations_by_tier, expired_reservations_by_tier} =
            load_reservations_maps(ticket_tiers)

          socket
          |> assign(assigns)
          |> assign(:event, event)
          |> assign(:ticket_tiers, ticket_tiers)
          |> assign(:reservations_by_tier, reservations_by_tier)
          |> assign(:expired_reservations_by_tier, expired_reservations_by_tier)
          |> assign(:editing_ticket_tier, nil)
          |> assign(:current_user, assigns[:current_user])
      end

    socket =
      cond do
        close_grant_modal ->
          socket
          |> refresh_ticket_data()
          |> bump_ticket_list_refresh_token()
          |> assign(:show_grant_modal, false)
          |> assign(:granting_tier, nil)
          |> maybe_toast_grant_success(grant_success)

        close_reserve_modal ->
          socket
          |> assign(:show_reserve_modal, false)
          |> assign(:reserving_tier, nil)
          |> assign(:show_add_modal, false)
          |> assign(:show_edit_modal, false)

        Map.has_key?(incoming_assigns, :grant_epoch) ->
          refresh_ticket_data(socket)

        true ->
          socket
          |> assign(
            :show_add_modal,
            Map.get(
              incoming_assigns,
              :show_add_modal,
              socket.assigns[:show_add_modal] || false
            )
          )
          |> assign(
            :show_edit_modal,
            Map.get(
              incoming_assigns,
              :show_edit_modal,
              socket.assigns[:show_edit_modal] || false
            )
          )
          |> assign(
            :show_reserve_modal,
            Map.get(
              incoming_assigns,
              :show_reserve_modal,
              socket.assigns[:show_reserve_modal] || false
            )
          )
          |> assign(
            :show_grant_modal,
            Map.get(
              incoming_assigns,
              :show_grant_modal,
              socket.assigns[:show_grant_modal] || false
            )
          )
      end

    {:ok, socket}
  end

  defp refresh_ticket_data(socket) do
    ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

    {reservations_by_tier, expired_reservations_by_tier} =
      load_reservations_maps(ticket_tiers)

    socket
    |> assign(:ticket_tiers, ticket_tiers)
    |> assign(:reservations_by_tier, reservations_by_tier)
    |> assign(:expired_reservations_by_tier, expired_reservations_by_tier)
  end

  # Forces the nested TicketList component to reload its ticket/order data.
  # Phoenix only re-invokes a live_component's update/2 when the assigns
  # passed to it change, so simply re-rendering this component's template
  # with the same static `event_id` prop wouldn't pick up tickets granted
  # via TicketGrantForm (a sibling component reached through send_update).
  # Nested live_components only get their update/2 re-invoked when the
  # assigns passed to them change -- re-rendering this component's template
  # with the same static `event_id` prop wouldn't pick up tickets granted
  # via TicketGrantForm (a sibling component reached through send_update).
  # Bumping a counter prop forces TicketList to see changed assigns and
  # refresh, synchronously as part of this same render.
  defp bump_ticket_list_refresh_token(socket) do
    assign(
      socket,
      :ticket_list_refresh_token,
      socket.assigns.ticket_list_refresh_token + 1
    )
  end

  defp maybe_toast_grant_success(socket, %{
         user_name: user_name,
         quantity: quantity
       }) do
    YscWeb.Flash.put_toast(
      socket,
      :info,
      "Granted #{quantity} ticket(s) to #{user_name}.",
      title: "Grant Tickets"
    )
  end

  defp maybe_toast_grant_success(socket, _), do: socket

  defp reservation_only_update?(assigns) do
    extra_keys =
      assigns
      |> Map.keys()
      |> Enum.reject(
        &(&1 in @reservation_update_keys or &1 in @grant_update_keys or
            &1 == :__changed__)
      )

    extra_keys == [] and
      (Map.has_key?(assigns, :reservation_epoch) or
         Map.get(assigns, :close_reserve_modal) == true or
         Map.has_key?(assigns, :grant_epoch) or
         Map.get(assigns, :close_grant_modal) == true)
  end

  defp parent_passthrough_only_update?(assigns) do
    extra_keys =
      assigns
      |> Map.keys()
      |> Enum.reject(
        &(&1 in @parent_passthrough_keys or &1 in @reservation_update_keys or
            &1 in @grant_update_keys or &1 == :__changed__)
      )

    extra_keys == []
  end

  defp maybe_assign_parent_passthrough(socket, incoming_assigns) do
    socket =
      case Map.get(incoming_assigns, :event) do
        nil -> socket
        event -> assign(socket, :event, event)
      end

    socket =
      case Map.get(incoming_assigns, :current_user) do
        nil -> socket
        current_user -> assign(socket, :current_user, current_user)
      end

    case Map.get(incoming_assigns, :admin_role) do
      nil -> socket
      admin_role -> assign(socket, :admin_role, admin_role)
    end
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
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "Cannot delete ticket tier with sold tickets",
         title: "Tickets"
       )}
    else
      case Events.delete_ticket_tier(ticket_tier) do
        {:ok, _ticket_tier} ->
          ticket_tiers =
            Events.list_ticket_tiers_for_event(socket.assigns.event_id)

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:info, "Ticket tier deleted successfully",
             title: "Tickets"
           )
           |> assign(:ticket_tiers, ticket_tiers)}

        {:error, _changeset} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Failed to delete ticket tier",
             title: "Tickets"
           )}
      end
    end
  end

  @impl true
  def handle_event("toggle-tickets-tbd", _params, socket) do
    new_value = !socket.assigns.event.tickets_tbd

    case Events.set_tickets_tbd(socket.assigns.event, new_value) do
      {:ok, updated_event} ->
        message =
          if new_value,
            do: "Event marked as 'Tickets TBD'",
            else: "Tickets TBD flag cleared"

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, message, title: "Tickets")
         |> assign(:event, updated_event)}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Failed to update event",
           title: "Event"
         )}
    end
  end

  @impl true
  def handle_event("set-tickets-tbd", _params, socket) do
    case Events.set_tickets_tbd(socket.assigns.event, true) do
      {:ok, updated_event} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Event marked as 'Tickets TBD'",
           title: "Tickets"
         )
         |> assign(:event, updated_event)}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Failed to update event",
           title: "Event"
         )}
    end
  end

  @impl true
  def handle_event("clear-tickets-tbd", _params, socket) do
    case Events.set_tickets_tbd(socket.assigns.event, false) do
      {:ok, updated_event} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Tickets TBD flag cleared",
           title: "Tickets"
         )
         |> assign(:event, updated_event)}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Failed to update event",
           title: "Event"
         )}
    end
  end

  @impl true
  def handle_event("close-grant-tickets-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_grant_modal, false)
     |> assign(:granting_tier, nil)}
  end

  @impl true
  def handle_event("close-reserve-tickets-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reserve_modal, false)
     |> assign(:reserving_tier, nil)}
  end

  @impl true
  def handle_event("grant-tickets", params, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket, "Grant Tickets")}
    else
      case tier_id_from_event_params(params) do
        nil ->
          {:noreply,
           YscWeb.Flash.put_toast(socket, :error, "Invalid ticket tier.",
             title: "Grant Tickets"
           )}

        tier_id ->
          case Events.get_ticket_tier(tier_id) do
            nil ->
              {:noreply,
               YscWeb.Flash.put_toast(socket, :error, "Ticket tier not found.",
                 title: "Grant Tickets"
               )}

            ticket_tier ->
              grant_tickets_for_tier(socket, ticket_tier)
          end
      end
    end
  end

  @impl true
  def handle_event("reserve-tickets", params, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket, "Reservation")}
    else
      case tier_id_from_event_params(params) do
        nil ->
          {:noreply,
           YscWeb.Flash.put_toast(socket, :error, "Invalid ticket tier.",
             title: "Reservation"
           )}

        tier_id ->
          case Events.get_ticket_tier(tier_id) do
            nil ->
              {:noreply,
               YscWeb.Flash.put_toast(socket, :error, "Ticket tier not found.",
                 title: "Reservation"
               )}

            ticket_tier ->
              reserve_tickets_for_tier(socket, ticket_tier)
          end
      end
    end
  end

  @impl true
  def handle_event("cancel-reservation", %{"id" => id}, socket) do
    # Finding 53: cancelling a hold is a money action (releases discounted
    # inventory / forces full price). Gate like grant/reserve after Findings
    # 46/50, and refuse ids that are not on this event's tiers.
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket, "Cancel Reservation")}
    else
      cancel_reservation_as_admin(socket, id)
    end
  end

  defp cancel_reservation_as_admin(socket, id) do
    reservation = Events.get_ticket_reservation!(id)

    if reservation_on_current_event?(reservation, socket.assigns.event_id) do
      case Events.cancel_ticket_reservation(reservation) do
        {:ok, _reservation} ->
          {reservations_by_tier, expired_reservations_by_tier} =
            load_reservations_maps(socket.assigns.ticket_tiers)

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :info,
             "Reservation cancelled successfully",
             title: "Reservation"
           )
           |> assign(:reservations_by_tier, reservations_by_tier)
           |> assign(
             :expired_reservations_by_tier,
             expired_reservations_by_tier
           )}

        {:error, _} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Failed to cancel reservation",
             title: "Reservation"
           )}
      end
    else
      {:noreply,
       YscWeb.Flash.put_toast(socket, :error, "Reservation not found",
         title: "Reservation"
       )}
    end
  end

  defp reservation_on_current_event?(reservation, event_id) do
    case reservation.ticket_tier do
      %{event_id: ^event_id} -> true
      _ -> false
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

  defp load_reservations_maps(ticket_tiers) do
    tier_ids = Enum.map(ticket_tiers, & &1.id)

    {
      Events.list_active_reservations_for_tiers(tier_ids),
      Events.list_expired_active_reservations_for_tiers(tier_ids)
    }
  end

  defp get_reserved_count(tier_id, reservations_by_tier) do
    reservations = Map.get(reservations_by_tier, tier_id, [])

    Enum.reduce(reservations, 0, fn reservation, acc ->
      acc + reservation.quantity
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
      {:ok, formatted} when formatted != "" -> formatted
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

  defp tier_id_from_event_params(%{"id" => id}), do: id
  defp tier_id_from_event_params(%{"tier-id" => id}), do: id
  defp tier_id_from_event_params(_), do: nil

  defp grant_tickets_for_tier(socket, ticket_tier) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket, "Grant Tickets")}
    else
      is_donation =
        ticket_tier.type == "donation" || ticket_tier.type == :donation

      if is_donation do
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Tickets cannot be granted for donation tiers",
           title: "Grant Tickets"
         )}
      else
        {:noreply,
         socket
         |> assign(:show_grant_modal, true)
         |> assign(:granting_tier, ticket_tier)}
      end
    end
  end

  defp deny_full_admin(socket, title) do
    YscWeb.Flash.put_toast(
      socket,
      :error,
      "You do not have permission to perform this action.",
      title: title
    )
  end

  defp reserve_tickets_for_tier(socket, ticket_tier) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket, "Reservation")}
    else
      reserve_tickets_for_tier_as_admin(socket, ticket_tier)
    end
  end

  defp reserve_tickets_for_tier_as_admin(socket, ticket_tier) do
    is_donation =
      ticket_tier.type == "donation" || ticket_tier.type == :donation

    if is_donation do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "Reservations are not available for donation tiers",
         title: "Reservation"
       )}
    else
      {:noreply,
       socket
       |> assign(:show_reserve_modal, true)
       |> assign(:reserving_tier, ticket_tier)}
    end
  end
end
