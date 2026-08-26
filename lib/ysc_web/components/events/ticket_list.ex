defmodule YscWeb.AdminEventsLive.TicketList do
  @moduledoc """
  Admin ticket list for an event: one collapsible group per ticket order
  (reference, purchaser, ticket count, total, purchased date), with that
  order's confirmed tickets listed indented underneath -- so it's clear at a
  glance which tickets belong to which order. Each ticket row has actions to
  add/edit the attendee's name and email, reassign the ticket to a different
  member, or refund it.
  """
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Accounts
  alias Ysc.Accounts.UserDisplay
  alias Ysc.Events
  alias Ysc.Events.TicketDetail
  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-zinc-200 rounded p-4 sm:p-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-4">
        <div class="flex items-center gap-3">
          <h3 class="text-lg font-semibold">Tickets</h3>
          <span class="text-sm text-zinc-600">
            {length(@tickets)} confirmed ticket{if length(@tickets) != 1, do: "s"} across {length(
              @order_groups
            )} order{if length(@order_groups) != 1, do: "s"}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <button
            id="ticket-orders-sort-purchased"
            type="button"
            phx-click="toggle-order-sort"
            phx-target={@myself}
            class="inline-flex items-center gap-1 text-sm text-zinc-600 hover:text-zinc-900 border border-zinc-200 rounded px-2.5 py-2"
          >
            Purchased
            <.icon
              name={
                if @order_sort_dir == :asc,
                  do: "hero-arrow-up",
                  else: "hero-arrow-down"
              }
              class="w-3.5 h-3.5 shrink-0"
            />
          </button>
          <.button
            id="export-tickets-csv"
            phx-click="export-tickets-csv"
            phx-target={@myself}
            phx-disable-with="Exporting..."
            color="blue"
            class="shrink-0"
          >
            <.icon name="hero-arrow-down-tray" class="w-5 h-5" /> Export CSV
          </.button>
        </div>
      </div>

      <div :if={@tickets == []} class="text-center py-8 text-zinc-500">
        <p class="font-semibold">No tickets yet.</p>
        <p class="text-sm">
          Tickets will appear here once users start buying tickets.
        </p>
      </div>

      <div
        :if={@tickets != []}
        class="divide-y divide-zinc-200 border border-zinc-100 rounded-lg"
      >
        <div :for={group <- @order_groups} id={"ticket-order-#{group.order_id}"}>
          <button
            id={"ticket-order-toggle-#{group.order_id}"}
            type="button"
            phx-click="toggle-order"
            phx-value-id={group.order_id}
            phx-target={@myself}
            class="w-full flex flex-wrap items-center gap-x-4 gap-y-1 px-3 py-2 bg-zinc-50 hover:bg-zinc-100 text-sm text-left transition-colors"
          >
            <.icon
              name={
                if order_collapsed?(@collapsed_order_ids, group.order_id),
                  do: "hero-chevron-right",
                  else: "hero-chevron-down"
              }
              class="w-3.5 h-3.5 text-zinc-400 shrink-0"
            />
            <.user_card user={group.order && group.order.user} class="h-auto" />
            <div class="flex items-center gap-1.5 text-xs font-semibold text-zinc-600 shrink-0">
              <.icon name="hero-shopping-bag" class="w-3.5 h-3.5 text-zinc-400" />
              {order_reference(group.order)}
            </div>
            <span class="text-xs text-zinc-500 shrink-0">
              {length(group.tickets)} ticket{if length(group.tickets) != 1, do: "s"}
            </span>
            <span class="sm:ml-auto text-sm font-medium text-zinc-800 shrink-0">
              {format_money_safe(order_total(group))}
            </span>
            <span class="text-xs text-zinc-500 whitespace-nowrap shrink-0">
              {format_datetime(order_purchased_at(group))}
            </span>
          </button>

          <div :if={!order_collapsed?(@collapsed_order_ids, group.order_id)}>
            <div
              :for={ticket <- group.tickets}
              id={"ticket-row-#{ticket.id}"}
              class="flex flex-wrap items-center gap-x-4 gap-y-2 py-3 pl-8 pr-3 border-t border-zinc-100"
            >
              <div class="flex-1 min-w-[180px]">
                <% {attendee_name, attendee_email} = attendee_display(ticket) %>
                <%= if attendee_name || attendee_email do %>
                  <div class="font-medium text-zinc-900 text-sm">
                    {attendee_name}
                  </div>
                  <div class="text-zinc-500 text-sm">{attendee_email}</div>
                <% else %>
                  <button
                    type="button"
                    phx-click="open-edit-detail"
                    phx-value-id={ticket.id}
                    phx-target={@myself}
                    class="text-blue-600 hover:underline text-sm"
                  >
                    + Add name &amp; email
                  </button>
                <% end %>
                <div
                  :if={reassigned?(ticket, group.order)}
                  class="text-xs text-amber-700 mt-0.5"
                >
                  <.icon name="hero-arrows-right-left" class="w-3 h-3 inline" />
                  Reassigned to {UserDisplay.full_name(ticket.user)}
                </div>
              </div>
              <div class="w-32 shrink-0">
                <.badge
                  :if={ticket.ticket_tier}
                  type={tier_badge_color(ticket.ticket_tier)}
                >
                  {ticket.ticket_tier.name}
                </.badge>
              </div>
              <div class="shrink-0">
                <.row_actions_dropdown
                  id={"ticket-actions-#{ticket.id}"}
                  label={"Actions for ticket #{ticket.reference_id}"}
                  drop_up={last_row?(ticket, group, @order_groups)}
                >
                  <.dropdown_menu_item
                    id={"ticket-actions-#{ticket.id}-edit"}
                    icon="hero-pencil-square"
                    phx-click="open-edit-detail"
                    phx-value-id={ticket.id}
                    phx-target={@myself}
                  >
                    {if ticket.registration,
                      do: "Edit attendee info",
                      else: "Add attendee info"}
                  </.dropdown_menu_item>
                  <.dropdown_menu_item
                    id={"ticket-actions-#{ticket.id}-reassign"}
                    icon="hero-arrows-right-left"
                    phx-click="open-reassign"
                    phx-value-id={ticket.id}
                    phx-target={@myself}
                  >
                    Reassign ticket
                  </.dropdown_menu_item>
                  <.dropdown_menu_item
                    id={"ticket-actions-#{ticket.id}-refund"}
                    icon="hero-banknotes"
                    tone={:danger}
                    phx-click="open-refund"
                    phx-value-id={ticket.id}
                    phx-target={@myself}
                  >
                    Refund ticket
                  </.dropdown_menu_item>
                </.row_actions_dropdown>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Add/Edit Attendee Info Modal --%>
      <.modal
        :if={@editing_ticket}
        id="edit-ticket-detail-modal"
        show
        on_cancel={JS.push("close-edit-detail-modal", target: @myself)}
      >
        <.header>
          {if @editing_ticket.registration,
            do: "Edit Attendee Info",
            else: "Add Attendee Info"}
        </.header>

        <.simple_form
          for={@detail_form}
          id="ticket-detail-form"
          phx-target={@myself}
          phx-submit="save-ticket-detail"
          class="mt-8"
        >
          <.input
            type="text"
            label="First name"
            field={@detail_form[:first_name]}
            required
          />
          <.input
            type="text"
            label="Last name"
            field={@detail_form[:last_name]}
            required
          />
          <.input type="email" label="Email" field={@detail_form[:email]} required />

          <:actions>
            <div class="flex justify-end gap-2 w-full">
              <.button
                type="button"
                variant="outline"
                phx-click="close-edit-detail-modal"
                phx-target={@myself}
              >
                Cancel
              </.button>
              <.button phx-disable-with="Saving...">Save</.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>

      <%!-- Reassign Ticket Modal --%>
      <.modal
        :if={@reassigning_ticket}
        id="reassign-ticket-modal"
        show
        on_cancel={JS.push("close-reassign-modal", target: @myself)}
      >
        <.header>
          Reassign Ticket
          <:subtitle>
            Currently assigned to {UserDisplay.full_name(@reassigning_ticket.user)}.
          </:subtitle>
        </.header>

        <div class="mt-8 space-y-4">
          <.admin_user_autocomplete
            id="ticket-reassign-user-autocomplete"
            label="New owner"
            name="reassign[user_id]"
            search_event="search-users"
            select_event="select-user"
            clear_event="clear-user"
            search_value={@user_search}
            results={@user_search_results}
            selected={@selected_user}
            target={@myself}
            required
          />

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              variant="outline"
              phx-click="close-reassign-modal"
              phx-target={@myself}
            >
              Cancel
            </.button>
            <.button
              type="button"
              phx-click="confirm-reassign"
              phx-target={@myself}
              phx-disable-with="Reassigning..."
              disabled={is_nil(@selected_user)}
            >
              Reassign
            </.button>
          </div>
        </div>
      </.modal>

      <%!-- Refund Ticket Modal --%>
      <.modal
        :if={@refunding_ticket}
        id="refund-ticket-modal"
        show
        on_cancel={JS.push("close-refund-modal", target: @myself)}
      >
        <.header>Refund Ticket</.header>

        <.simple_form
          for={to_form(%{"reason" => ""}, as: "refund")}
          id="refund-ticket-form"
          phx-target={@myself}
          phx-submit="confirm-refund"
          class="mt-8"
        >
          <p class="text-sm text-zinc-600">
            Refunding this ticket will issue a refund of
            <strong>{format_money_safe(@refund_amount)}</strong>
            back to the original payment method and cancel the ticket, releasing it back to stock.
          </p>

          <.input type="text" name="reason" label="Reason (optional)" value="" />

          <:actions>
            <div class="flex justify-end gap-2 w-full">
              <.button
                type="button"
                variant="outline"
                phx-click="close-refund-modal"
                phx-target={@myself}
              >
                Cancel
              </.button>
              <.button
                phx-disable-with="Refunding..."
                class="bg-red-600 hover:bg-red-700"
              >
                Refund Ticket
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:initialized?] do
      {:ok, refresh_data(socket)}
    else
      {:ok,
       socket
       |> assign(:initialized?, true)
       |> assign(:order_sort_dir, :desc)
       |> assign(:collapsed_order_ids, MapSet.new())
       |> refresh_data()
       |> assign(:editing_ticket, nil)
       |> assign(:detail_form, nil)
       |> assign(:reassigning_ticket, nil)
       |> assign(:user_search, "")
       |> assign(:user_search_results, [])
       |> assign(:selected_user, nil)
       |> assign(:refunding_ticket, nil)
       |> assign(:refund_amount, nil)}
    end
  end

  defp refresh_data(socket) do
    tickets = Tickets.list_tickets_for_admin(socket.assigns.event_id)

    socket
    |> assign(:tickets, tickets)
    |> assign(
      :order_groups,
      group_by_order(tickets, socket.assigns[:order_sort_dir] || :desc)
    )
  end

  # Enum.group_by/2's map doesn't guarantee order, so groups are explicitly
  # sorted by their order's purchased-at afterwards.
  defp group_by_order(tickets, sort_dir) do
    tickets
    |> Enum.group_by(& &1.ticket_order_id)
    |> Enum.map(fn {order_id, order_tickets} ->
      %{
        order_id: order_id,
        order: hd(order_tickets).ticket_order,
        tickets: order_tickets
      }
    end)
    |> Enum.sort_by(&order_purchased_at/1, {sort_dir, DateTime})
  end

  defp order_reference(nil), do: "No order"
  defp order_reference(order), do: order.reference_id

  defp order_total(%{order: nil}), do: nil
  defp order_total(%{order: order}), do: order.total_amount

  defp order_purchased_at(%{order: order, tickets: tickets}) do
    (order && order.completed_at) ||
      Enum.min_by(tickets, & &1.inserted_at).inserted_at
  end

  defp reassigned?(_ticket, nil), do: false

  defp reassigned?(ticket, order) do
    ticket.user_id && order.user_id && ticket.user_id != order.user_id
  end

  defp order_collapsed?(collapsed_order_ids, order_id),
    do: MapSet.member?(collapsed_order_ids, order_id)

  # Opens upward only for the very last ticket row on the page (last ticket
  # of the last group) -- there's nothing below it, so an upward menu reads
  # more naturally there. Every other row opens downward.
  defp last_row?(ticket, group, order_groups) do
    List.last(order_groups) == group and List.last(group.tickets) == ticket
  end

  # Deterministic per ticket tier (hashed from its id) so the same tier
  # always renders with the same badge color across every row and every
  # page load, while different tiers land on different colors.
  @tier_badge_colors ~w(sky green violet red yellow dark zinc default)

  defp tier_badge_color(ticket_tier) do
    Enum.at(
      @tier_badge_colors,
      :erlang.phash2(ticket_tier.id, length(@tier_badge_colors))
    )
  end

  @impl true
  def handle_event("toggle-order", %{"id" => order_id}, socket) do
    order_id = if order_id == "", do: nil, else: order_id
    collapsed = socket.assigns.collapsed_order_ids

    collapsed =
      if MapSet.member?(collapsed, order_id) do
        MapSet.delete(collapsed, order_id)
      else
        MapSet.put(collapsed, order_id)
      end

    {:noreply, assign(socket, :collapsed_order_ids, collapsed)}
  end

  @impl true
  def handle_event("toggle-order-sort", _params, socket) do
    sort_dir = if socket.assigns.order_sort_dir == :desc, do: :asc, else: :desc

    {:noreply,
     socket
     |> assign(:order_sort_dir, sort_dir)
     |> assign(:order_groups, group_by_order(socket.assigns.tickets, sort_dir))}
  end

  @impl true
  def handle_event("open-edit-detail", %{"id" => id}, socket) do
    ticket = find_ticket!(socket, id)

    changeset =
      case ticket.registration do
        nil -> TicketDetail.changeset(%TicketDetail{}, %{})
        registration -> TicketDetail.changeset(registration, %{})
      end

    {:noreply,
     socket
     |> assign(:editing_ticket, ticket)
     |> assign(:detail_form, to_form(changeset, as: "ticket_detail"))}
  end

  @impl true
  def handle_event("close-edit-detail-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_ticket, nil)
     |> assign(:detail_form, nil)}
  end

  @impl true
  def handle_event("save-ticket-detail", %{"ticket_detail" => params}, socket) do
    ticket = socket.assigns.editing_ticket
    attrs = Map.put(params, "ticket_id", ticket.id)

    result =
      case ticket.registration do
        nil -> Events.create_registration(attrs)
        registration -> Events.update_registration(registration, attrs)
      end

    case result do
      {:ok, _registration} ->
        {:noreply,
         socket
         |> assign(:editing_ticket, nil)
         |> assign(:detail_form, nil)
         |> refresh_data()
         |> YscWeb.Flash.put_toast(:info, "Attendee info saved.",
           title: "Ticket"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :detail_form, to_form(changeset, as: "ticket_detail"))}
    end
  end

  @impl true
  def handle_event("open-reassign", %{"id" => id}, socket) do
    ticket = find_ticket!(socket, id)

    {:noreply,
     socket
     |> assign(:reassigning_ticket, ticket)
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def handle_event("close-reassign-modal", _params, socket) do
    {:noreply, assign(socket, :reassigning_ticket, nil)}
  end

  @impl true
  def handle_event("search-users", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Accounts.search_users(query, limit: 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:user_search, query)
     |> assign(:user_search_results, results)}
  end

  @impl true
  def handle_event("select-user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def handle_event("clear-user", _params, socket) do
    {:noreply, assign(socket, :selected_user, nil)}
  end

  @impl true
  def handle_event("confirm-reassign", _params, socket) do
    ticket = socket.assigns.reassigning_ticket
    user = socket.assigns.selected_user

    cond do
      is_nil(user) ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Select a member to reassign this ticket to.",
           title: "Reassign Ticket"
         )}

      user.id == ticket.user_id ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Ticket is already assigned to this member.",
           title: "Reassign Ticket"
         )}

      true ->
        case Tickets.reassign_ticket(ticket, user.id) do
          {:ok, _ticket} ->
            {:noreply,
             socket
             |> assign(:reassigning_ticket, nil)
             |> refresh_data()
             |> YscWeb.Flash.put_toast(
               :info,
               "Ticket reassigned to #{UserDisplay.full_name(user)}.",
               title: "Reassign Ticket"
             )}

          {:error, _changeset} ->
            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "Failed to reassign ticket.",
               title: "Reassign Ticket"
             )}
        end
    end
  end

  @impl true
  def handle_event("open-refund", %{"id" => id}, socket) do
    ticket = find_ticket!(socket, id)

    amount_result =
      case ticket.ticket_order do
        nil ->
          {:error, :no_ticket_order}

        ticket_order ->
          Tickets.calculate_refund_amount(ticket_order, [ticket.id])
      end

    case amount_result do
      {:ok, amount} ->
        {:noreply,
         socket
         |> assign(:refunding_ticket, ticket)
         |> assign(:refund_amount, amount)}

      {:error, _reason} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "This ticket cannot be refunded.",
           title: "Refund Ticket"
         )}
    end
  end

  @impl true
  def handle_event("close-refund-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:refunding_ticket, nil)
     |> assign(:refund_amount, nil)}
  end

  @impl true
  def handle_event("confirm-refund", params, socket) do
    ticket = socket.assigns.refunding_ticket
    ticket_order = ticket.ticket_order
    amount = socket.assigns.refund_amount
    reason = blank_to_default(params["reason"], "Admin refund")

    stripe_result =
      cond do
        Money.zero?(amount) -> {:ok, :skipped_zero_amount}
        is_nil(ticket_order.payment) -> {:error, :no_stripe_payment}
        true -> Tickets.refund_via_stripe(ticket_order.payment, amount, reason)
      end

    case stripe_result do
      {:ok, _} ->
        case Tickets.refund_tickets(ticket_order, [ticket.id], reason) do
          {:ok, refund_info} ->
            {:noreply,
             socket
             |> assign(:refunding_ticket, nil)
             |> assign(:refund_amount, nil)
             |> refresh_data()
             |> YscWeb.Flash.put_toast(
               :info,
               "Refunded ticket successfully. Amount: #{Money.to_string!(refund_info.refund_amount)}",
               title: "Refund Ticket"
             )}

          {:error, reason} ->
            require Ysc.Logging

            Ysc.Logging.error(
              "Ticket refund issued in Stripe but ticket failed to cancel",
              ticket_id: ticket.id,
              ticket_order_id: ticket_order.id,
              error: inspect(reason)
            )

            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "Refund was processed in Stripe, but the ticket could not be marked cancelled. Please cancel it manually.",
               title: "Refund Ticket"
             )}
        end

      {:error, {:stripe_error, _msg}} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Stripe declined the refund. Check the payment in the Stripe dashboard, or contact engineering if this persists.",
           title: "Refund Ticket"
         )}

      {:error, :no_stripe_payment} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Cannot process refund: no Stripe payment found for this ticket order.",
           title: "Refund Ticket"
         )}
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
    encoded_content = Base.encode64(csv_content)

    {:noreply,
     socket
     |> push_event("download-csv", %{
       content: encoded_content,
       filename: filename
     })}
  end

  defp find_ticket!(socket, id) do
    Enum.find(socket.assigns.tickets, &(to_string(&1.id) == to_string(id)))
  end

  # The attendee is whoever the registration record names; when no separate
  # registration was collected (e.g. the tier doesn't require one), the
  # attendee is just the purchaser -- matches the CSV export's fallback.
  defp attendee_display(%{registration: %{} = registration}) do
    {[registration.first_name, registration.last_name]
     |> Enum.reject(&(&1 in [nil, ""]))
     |> Enum.join(" "), registration.email}
  end

  defp attendee_display(%{user: %{} = user}) do
    {[user.first_name, user.last_name]
     |> Enum.reject(&(&1 in [nil, ""]))
     |> Enum.join(" "), user.email}
  end

  defp attendee_display(_ticket), do: {nil, nil}

  defp blank_to_default(nil, default), do: default
  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{Mshort} {D}, {YYYY} at {h12}:{m}{am}")
  end

  defp format_money_safe(%Money{} = money), do: Money.to_string!(money)
  defp format_money_safe(_), do: "—"

  defp build_csv_rows(tickets) do
    Enum.map(tickets, fn ticket ->
      purchaser_first_name = ticket.user.first_name || ""
      purchaser_last_name = ticket.user.last_name || ""
      purchaser_email = ticket.user.email || ""

      phone =
        (ticket.user.phone_number &&
           Ysc.Extensions.PhoneNumber.format_for_display(
             ticket.user.phone_number
           )) ||
          ""

      {attendee_first_name, attendee_last_name, attendee_email} =
        if ticket.ticket_tier && ticket.ticket_tier.requires_registration &&
             ticket.ticket_detail do
          {
            ticket.ticket_detail.first_name || "",
            ticket.ticket_detail.last_name || "",
            ticket.ticket_detail.email || ""
          }
        else
          {purchaser_first_name, purchaser_last_name, purchaser_email}
        end

      base_row = %{
        "Ticket Reference" => ticket.reference_id || "",
        "Ticket Tier" => (ticket.ticket_tier && ticket.ticket_tier.name) || "",
        "Purchase Date" => format_datetime(ticket.inserted_at),
        "Purchaser First Name" => purchaser_first_name,
        "Purchaser Last Name" => purchaser_last_name,
        "Purchaser Email" => purchaser_email,
        "Purchaser Phone" => phone,
        "Attendee First Name" => attendee_first_name,
        "Attendee Last Name" => attendee_last_name,
        "Attendee Email" => attendee_email
      }

      if ticket.ticket_detail do
        Map.put(base_row, "Registration Provided", "Yes")
      else
        Map.put(base_row, "Registration Provided", "No")
      end
    end)
  end
end
