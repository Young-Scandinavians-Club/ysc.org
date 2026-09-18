defmodule YscWeb.AdminEventsLive.CancellationRefundModal do
  @moduledoc """
  Modal shown to a full admin right after cancelling an event: lists every
  paid/granted ticket order for the event so they can refund whoever hasn't
  been refunded yet, without hunting through the Tickets tab order by order.

  Orders that can't be refunded here (already refunded, free/no payment
  collected, paid in person, or cancelled with no refund on record) are shown
  with a status badge explaining why instead of a checkbox, so the admin can
  see at a glance who still needs action.
  """
  use YscWeb, :live_component

  import YscWeb.Live.AsyncHelpers

  alias Ysc.Ledgers
  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"cancellation-refund-modal-wrapper-#{@event_id}"}>
      <.modal
        id="cancellation-refund-modal"
        show
        on_cancel={JS.push("close-cancellation-refund-modal")}
        max_width="max-w-2xl"
      >
        <.header>
          Event Cancelled
          <:subtitle>
            Review the ticket orders below and refund anyone who hasn't been refunded yet.
          </:subtitle>
        </.header>

        <div :if={@orders == []} class="mt-6 text-center py-8 text-zinc-500">
          <p class="font-semibold">No ticket orders for this event.</p>
          <p class="text-sm">There's nothing to refund.</p>
        </div>

        <div :if={@orders != []} class="mt-6 space-y-3">
          <div class="flex items-center justify-between">
            <.input
              type="checkbox"
              id="cancellation-refund-select-all"
              name="cancellation_refund_select_all"
              value="true"
              label="Select all refundable orders"
              checked={
                @refundable_order_ids != [] &&
                  MapSet.new(@refundable_order_ids) ==
                    MapSet.new(@selected_order_ids)
              }
              disabled={@refundable_order_ids == []}
              phx-click="toggle-select-all"
              phx-target={@myself}
            />
            <span class="text-xs text-zinc-500">
              {length(@orders)} order{if length(@orders) != 1, do: "s"}
            </span>
          </div>

          <div class="divide-y divide-zinc-200 border border-zinc-100 rounded-lg">
            <div
              :for={entry <- @orders}
              id={"cancellation-refund-order-#{entry.order.id}"}
              class="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-3"
            >
              <div class="shrink-0">
                <.input
                  :if={entry.state == :refundable}
                  type="checkbox"
                  id={"cancellation-refund-order-#{entry.order.id}-checkbox"}
                  name={"cancellation_refund_order_#{entry.order.id}"}
                  value="true"
                  aria-label={"Select order #{entry.order.reference_id} for refund"}
                  checked={MapSet.member?(@selected_order_ids, entry.order.id)}
                  phx-click="toggle-selection"
                  phx-value-id={entry.order.id}
                  phx-target={@myself}
                />
              </div>

              <.user_card
                user={entry.order.user}
                class="h-auto min-w-0 flex-1"
                truncate
              />

              <div class="hidden sm:flex items-center gap-1.5 text-xs font-semibold text-zinc-600 shrink-0">
                <.icon name="hero-shopping-bag" class="w-3.5 h-3.5 text-zinc-400" />
                {entry.order.reference_id}
              </div>

              <span class="hidden sm:inline text-xs text-zinc-500 shrink-0">
                {length(entry.order.tickets)} ticket{if length(entry.order.tickets) !=
                                                          1,
                                                        do: "s"}
              </span>

              <div class="shrink-0 text-right">
                <.badge :if={entry.state == :refunded} type="green">
                  Refunded
                </.badge>
                <.badge :if={entry.state == :no_payment} type="zinc">
                  No payment — nothing to refund
                </.badge>
                <.badge :if={entry.state == :offline_payment} type="yellow">
                  Paid in person ({offline_payment_label(
                    entry.order.payment_channel
                  )}) — refund manually
                </.badge>
                <.badge :if={entry.state == :unrefunded_cancelled} type="red">
                  Cancelled, no refund on record — check manually
                </.badge>
                <span
                  :if={entry.state == :refundable}
                  class="text-sm font-medium text-zinc-800"
                >
                  {Money.to_string!(entry.amount)}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-6 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <span class="text-sm text-zinc-600">
            <%= if MapSet.size(@selected_order_ids) > 0 do %>
              {MapSet.size(@selected_order_ids)} selected · {Money.to_string!(
                selected_total(@orders, @selected_order_ids)
              )} total
            <% end %>
          </span>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              variant="outline"
              phx-click="close-cancellation-refund-modal"
            >
              Done
            </.button>
            <.button
              type="button"
              phx-click="refund-selected"
              phx-target={@myself}
              phx-disable-with="Refunding..."
              disabled={MapSet.size(@selected_order_ids) == 0 || @refunding?}
              class="bg-red-600 hover:bg-red-700"
              data-confirm={
              "Refund #{MapSet.size(@selected_order_ids)} selected order(s) totaling #{Money.to_string!(selected_total(@orders, @selected_order_ids))}? This cannot be undone."
            }
            >
              Refund Selected
            </.button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:orders] do
        socket
      else
        socket
        |> assign(:selected_order_ids, MapSet.new())
        |> assign(:refunding?, false)
        |> refresh_orders()
      end

    {:ok, socket}
  end

  defp refresh_orders(socket) do
    orders =
      socket.assigns.event_id
      |> Tickets.list_orders_for_event_refund()
      |> Enum.map(&Map.merge(%{order: &1}, classify_order(&1)))

    refundable_order_ids =
      orders
      |> Enum.filter(&(&1.state == :refundable))
      |> Enum.map(& &1.order.id)

    selected =
      MapSet.intersection(
        socket.assigns[:selected_order_ids] || MapSet.new(),
        MapSet.new(refundable_order_ids)
      )

    socket
    |> assign(:orders, orders)
    |> assign(:refundable_order_ids, refundable_order_ids)
    |> assign(:selected_order_ids, selected)
  end

  # Classifies an order for the cancellation-refund flow:
  # - `:offline_payment` for in-person cash/check sales, which never touch
  #   Stripe and so can't be refunded from here (checked first: these orders
  #   also carry no `payment_id`, same as a free grant)
  # - for an order with no active tickets left, see `classify_cancelled_order/1`
  # - `:no_payment` for free/admin-granted orders and any order whose amount
  #   can't be resolved to a refundable ticket set
  # - `:refundable` otherwise, carrying the still-active ticket ids and the
  #   amount a refund of all of them would issue
  defp classify_order(order) do
    active_ticket_ids =
      order.tickets
      |> Enum.filter(&(&1.status in [:confirmed, :pending]))
      |> Enum.map(& &1.id)

    cond do
      order.payment_channel ->
        %{
          state: :offline_payment,
          active_ticket_ids: active_ticket_ids,
          amount: nil
        }

      active_ticket_ids == [] ->
        classify_cancelled_order(order)

      is_nil(order.payment_id) || is_nil(order.total_amount) ||
          Money.zero?(order.total_amount) ->
        %{state: :no_payment, active_ticket_ids: active_ticket_ids, amount: nil}

      true ->
        case Tickets.calculate_refund_amount(order, active_ticket_ids) do
          {:ok, amount} ->
            %{
              state: :refundable,
              active_ticket_ids: active_ticket_ids,
              amount: amount
            }

          {:error, _reason} ->
            %{
              state: :no_payment,
              active_ticket_ids: active_ticket_ids,
              amount: nil
            }
        end
    end
  end

  # An order with no active tickets left either never collected any money
  # (free/admin grant, or an abandoned unpaid checkout -- `payment_id` is nil
  # either way) or was fully refunded. `Tickets.refund_tickets/3` cancels
  # tickets without itself touching Stripe or the ledger, so don't infer
  # "refunded" just from the tickets being gone -- every current caller
  # refunds via `Tickets.refund_via_stripe/4` (which records a
  # `Ysc.Ledgers.Refund`) first, but trusting that call order would silently
  # hide a real gap if that ever changed. Check the ledger instead, and flag
  # a cancelled order with money on file but no recorded refund for manual
  # follow-up rather than mislabeling it "Refunded".
  defp classify_cancelled_order(%{payment_id: nil}) do
    %{state: :no_payment, active_ticket_ids: [], amount: nil}
  end

  defp classify_cancelled_order(%{payment_id: payment_id}) do
    if Ledgers.list_refunds_for_payment(payment_id) != [] do
      %{state: :refunded, active_ticket_ids: [], amount: nil}
    else
      %{state: :unrefunded_cancelled, active_ticket_ids: [], amount: nil}
    end
  end

  defp offline_payment_label("cash"), do: "cash"
  defp offline_payment_label("check"), do: "check"
  defp offline_payment_label(_), do: "in person"

  defp selected_total(orders, selected_order_ids) do
    orders
    |> Enum.filter(
      &(&1.state == :refundable &&
          MapSet.member?(selected_order_ids, &1.order.id))
    )
    |> Enum.reduce(Money.new(0, :USD), fn entry, acc ->
      case Money.add(acc, entry.amount) do
        {:ok, total} -> total
        {:error, _} -> acc
      end
    end)
  end

  @impl true
  def handle_event("toggle-selection", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_order_ids, id) do
        MapSet.delete(socket.assigns.selected_order_ids, id)
      else
        MapSet.put(socket.assigns.selected_order_ids, id)
      end

    {:noreply, assign(socket, :selected_order_ids, selected)}
  end

  @impl true
  def handle_event("toggle-select-all", _params, socket) do
    refundable = MapSet.new(socket.assigns.refundable_order_ids)

    selected =
      if MapSet.equal?(socket.assigns.selected_order_ids, refundable) do
        MapSet.new()
      else
        refundable
      end

    {:noreply, assign(socket, :selected_order_ids, selected)}
  end

  @impl true
  def handle_event("refund-selected", _params, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, deny_full_admin(socket)}
    else
      selected_entries =
        Enum.filter(
          socket.assigns.orders,
          &(&1.state == :refundable &&
              MapSet.member?(socket.assigns.selected_order_ids, &1.order.id))
        )

      # Each refund is a Stripe call (with its own retry backoff) followed by
      # a DB write, so refunding a large batch serially could block the
      # modal -- and the LiveView process itself -- for the sum of every
      # order's network round trip. Bounded concurrency keeps a big event
      # cancellation from stalling the toast/refresh for minutes.
      results =
        selected_entries
        |> async_stream_with_repo(&refund_order(&1, "Event cancelled"),
          max_concurrency: 5,
          timeout: :infinity
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, {:exited, reason}}
        end)

      succeeded = Enum.count(results, &match?({:ok, _}, &1))
      failed = length(results) - succeeded

      socket = refresh_orders(socket)

      {:noreply, put_refund_result_toast(socket, succeeded, failed)}
    end
  end

  defp put_refund_result_toast(socket, 0, 0), do: socket

  defp put_refund_result_toast(socket, succeeded, 0) do
    YscWeb.Flash.put_toast(
      socket,
      :info,
      "Refunded #{succeeded} order#{if succeeded != 1, do: "s"}.",
      title: "Refunds"
    )
  end

  defp put_refund_result_toast(socket, 0, failed) do
    YscWeb.Flash.put_toast(
      socket,
      :error,
      "Failed to refund #{failed} order#{if failed != 1, do: "s"}. Check the payments in the Stripe dashboard, or contact engineering if this persists.",
      title: "Refunds"
    )
  end

  defp put_refund_result_toast(socket, succeeded, failed) do
    YscWeb.Flash.put_toast(
      socket,
      :error,
      "Refunded #{succeeded} order#{if succeeded != 1, do: "s"}, but #{failed} failed. Check the payments in the Stripe dashboard.",
      title: "Refunds"
    )
  end

  # Mirrors AdminEventsLive.TicketList's confirm-refund flow, but for every
  # active ticket on the order at once: issue the Stripe refund first, then
  # cancel the tickets -- so a Stripe failure never leaves tickets cancelled
  # with no money actually refunded.
  defp refund_order(
         %{order: order, active_ticket_ids: ticket_ids, amount: amount},
         reason
       ) do
    stripe_result =
      cond do
        Money.zero?(amount) ->
          {:ok, :skipped_zero_amount}

        is_nil(order.payment_id) ->
          {:error, :no_stripe_payment}

        true ->
          case Tickets.get_payment_for_order(order) do
            nil ->
              {:error, :no_stripe_payment}

            payment ->
              Tickets.refund_via_stripe(payment, amount, reason,
                ticket_ids: ticket_ids
              )
          end
      end

    case stripe_result do
      {:ok, _} ->
        case Tickets.refund_tickets(order, ticket_ids, reason) do
          {:ok, refund_info} ->
            {:ok, refund_info}

          {:error, error_reason} ->
            require Ysc.Logging

            Ysc.Logging.error(
              "Ticket order refund issued in Stripe but tickets failed to cancel",
              ticket_order_id: order.id,
              ticket_ids: ticket_ids,
              error: inspect(error_reason)
            )

            {:error, error_reason}
        end

      {:error, error_reason} ->
        {:error, error_reason}
    end
  end

  defp deny_full_admin(socket) do
    YscWeb.Flash.put_toast(
      socket,
      :error,
      "You do not have permission to perform this action.",
      title: "Refunds"
    )
  end
end
