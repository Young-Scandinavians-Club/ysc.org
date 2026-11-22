defmodule YscWeb.GuestCheckoutLive do
  @moduledoc """
  Buy public-sale tickets without an account.

  The ticket picker on the event page hands over a signed selection
  (`Ysc.Tickets.GuestCheckout.sign_selection/2`). The visitor gives a name and
  email, the tickets are held for a few minutes, and they pay with Stripe. The
  tickets are then reached through a signed link (`/t/:token`) that is also
  emailed, so no account is needed.

  Two routes share this module: `:details` (contact details, then payment) and
  `:return` (where Stripe sends the visitor back after a redirect payment
  method).
  """
  use YscWeb, :live_view

  import Ecto.Query

  alias Ysc.Events.TicketTier
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.AccessToken
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Tickets.GuestCheckout
  alias Ysc.Tickets.StripeService
  alias Ysc.Tickets.TicketOrder

  require Ysc.Logging

  # How long the held tickets last; matches `BookingLocker.atomic_booking/4`.
  @hold_ms :timer.minutes(5)

  @impl true
  def mount(%{"id" => id} = params, session, socket) do
    event = Ysc.Events.get_event(id)

    cond do
      is_nil(event) ->
        {:ok, leave(socket, ~p"/events", :error, "Event not found.")}

      socket.assigns.current_user != nil ->
        # Signed-in visitors use the regular checkout on the event page.
        {:ok, push_navigate(socket, to: ~p"/events/#{event.id}/tickets")}

      socket.assigns.live_action == :return ->
        {:ok, mount_return(socket, event, params)}

      true ->
        {:ok, mount_details(socket, event, params, session)}
    end
  end

  defp mount_details(socket, event, params, session) do
    with {:ok, selections} <-
           GuestCheckout.verify_selection(params["s"], event.id),
         {:ok, tiers} <- load_selected_tiers(event.id, selections),
         :ok <- GuestCheckout.validate_tiers(tiers),
         {:ok, total, _discount} <-
           BookingLocker.estimate_order_total(nil, event.id, selections) do
      socket
      |> assign(:page_title, "Checkout · #{event.title}")
      |> assign(:event, event)
      |> assign(:selection_token, params["s"])
      |> assign(:selections, selections)
      |> assign(:tiers, Map.new(tiers, &{&1.id, &1}))
      |> assign(:total, total)
      |> assign(:remote_ip, YscWeb.ClientIP.from_socket(socket, session))
      |> assign(:load_turnstile, true)
      |> assign(:step, :details)
      |> assign(:ticket_order, nil)
      |> assign(:payment_intent, nil)
      |> assign(:payment_element_ready, false)
      |> assign(:form, guest_form(%{}))
    else
      _ ->
        leave(
          socket,
          ~p"/events/#{event.id}",
          :error,
          "That ticket selection expired or isn't available without an account. Please choose your tickets again."
        )
    end
  end

  defp mount_return(socket, event, params) do
    redirect_status = params["redirect_status"]
    payment_intent_id = params["payment_intent"]
    client_secret = params["payment_intent_client_secret"]

    socket =
      socket
      |> assign(:page_title, "Processing payment")
      |> assign(:event, event)
      |> assign(:step, :return)

    cond do
      redirect_status not in ["succeeded", "processing"] or
          not is_binary(payment_intent_id) ->
        leave(
          socket,
          ~p"/events/#{event.id}",
          :error,
          "Your payment didn't go through, so you weren't charged. Please try again."
        )

      connected?(socket) ->
        finish_return(socket, event, payment_intent_id, client_secret)

      true ->
        socket
    end
  end

  # The redirect carries the PaymentIntent's client secret; requiring it to
  # match keeps a guessed PaymentIntent id from opening someone else's tickets.
  defp finish_return(socket, event, payment_intent_id, client_secret) do
    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}),
         true <- secure_equal?(payment_intent.client_secret, client_secret),
         {:ok, %TicketOrder{} = order} <-
           StripeService.process_successful_payment(payment_intent) do
      redirect(socket, to: ~p"/t/#{AccessToken.sign_order(order.id)}")
    else
      _ ->
        leave(
          socket,
          ~p"/events/#{event.id}",
          :error,
          "We couldn't confirm your payment yet. If you were charged, your tickets will be emailed to you shortly."
        )
    end
  end

  @impl true
  def render(%{step: :return} = assigns) do
    ~H"""
    <div
      id="guest-checkout-return"
      class="py-8 lg:py-10 max-w-(--breakpoint-xl) mx-auto px-4"
    >
      <div class="text-center">
        <.async_section_loader
          id="guest-payment-processing"
          label="Processing your payment…"
          class="py-12"
        />
        <p class="text-sm text-zinc-500">
          This only takes a moment. Please keep this page open.
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="guest-checkout"
      class="py-6 lg:py-8 max-w-(--breakpoint-lg) mx-auto px-4"
    >
      <.page_masthead
        id="guest-checkout-masthead"
        size={:compact}
        eyebrow="Checkout"
        title={@event.title}
      />

      <div class="grid grid-cols-1 gap-8 lg:grid-cols-5">
        <div class="lg:col-span-3 space-y-6">
          <%= if @step == :details do %>
            <.form
              for={@form}
              id="guest-checkout-form"
              phx-change="validate"
              phx-submit="continue"
              class="space-y-4"
            >
              <h2 class="type-subhead text-lg">Your details</h2>
              <p class="text-sm text-zinc-600">
                No account needed. We'll email your tickets to this address.
              </p>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:first_name]}
                  type="text"
                  label="First name"
                  autocomplete="given-name"
                  required
                />
                <.input
                  field={@form[:last_name]}
                  type="text"
                  label="Last name"
                  autocomplete="family-name"
                  required
                />
              </div>
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="email"
                required
              />

              <div class="w-full flex">
                <Turnstile.widget theme="light" />
              </div>

              <.button
                id="guest-checkout-continue"
                type="submit"
                phx-disable-with="Holding your tickets…"
                class="w-full py-4"
              >
                {if Money.zero?(@total),
                  do: "Get my tickets",
                  else: "Continue to payment"}
              </.button>
              <p class="text-xs text-zinc-500 text-center">
                Already a member?
                <.link
                  id="guest-checkout-sign-in"
                  navigate={
                    ~p"/users/log-in?redirect_to=#{~p"/events/#{@event.id}/tickets"}"
                  }
                  class="font-semibold text-blue-700 underline underline-offset-2"
                >
                  Sign in
                </.link>
                for member tickets.
              </p>
            </.form>
          <% else %>
            <div class="space-y-4">
              <h2 class="type-subhead text-lg">Payment</h2>
              <p id="guest-checkout-hold" class="text-sm text-zinc-600">
                We're holding your tickets for 5 minutes. Receipt and tickets go to <strong>{@ticket_order.guest_email}</strong>.
              </p>
              <%= if @payment_intent do %>
                <div
                  id="payment-element"
                  phx-hook="StripeElements"
                  phx-update="ignore"
                  data-public-key={
                    Application.get_env(:stripity_stripe, :public_key)
                  }
                  data-client-secret={@payment_intent.client_secret}
                  data-return-path={~p"/events/#{@event.id}/checkout/return"}
                  data-billing-details={billing_details_json(@ticket_order)}
                >
                </div>
              <% else %>
                <.payment_element_loading id="guest-checkout-payment-loading" />
              <% end %>
              <div id="payment-message" class="hidden text-sm"></div>
              <.button
                id="submit-payment"
                class="w-full py-4"
                disabled={!@payment_element_ready}
              >
                Pay {Money.to_string!(@total)}
              </.button>
              <button
                id="guest-checkout-cancel"
                type="button"
                phx-click="cancel"
                class="w-full text-sm text-zinc-600 underline underline-offset-2"
              >
                Cancel and release my tickets
              </button>
            </div>
          <% end %>
        </div>

        <aside
          id="guest-checkout-summary"
          class="lg:col-span-2 space-y-3 rounded-xl bg-zinc-50 p-6 h-fit"
        >
          <h2 class="type-subhead text-lg">Order summary</h2>
          <ul class="space-y-2 text-sm">
            <li
              :for={{tier, quantity} <- summary_lines(@tiers, @selections)}
              class="flex justify-between gap-4"
            >
              <span>{tier.name} <span :if={!donation?(tier)}>× {quantity}</span></span>
              <span>{line_price(tier, quantity)}</span>
            </li>
          </ul>
          <div class="flex justify-between border-t border-zinc-200 pt-3 font-semibold">
            <span>Total</span>
            <span id="guest-checkout-total">{Money.to_string!(@total)}</span>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"guest" => params}, socket) do
    {:noreply, assign(socket, :form, guest_form(params))}
  end

  def handle_event("continue", %{"guest" => params} = values, socket) do
    with :ok <-
           YscWeb.GuestTurnstile.verify(socket, values, title: "Checkout"),
         {:ok, guest} <- GuestCheckout.validate_guest(guest_attrs(params)) do
      start_order(socket, guest)
    else
      {:error, {:invalid_guest, _changeset}} ->
        {:noreply,
         socket
         |> assign(:form, guest_form(params, errors?: true))
         |> put_toast(:error, "Please check your name and email.")}

      {:error, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, assign(socket, :form, guest_form(params))}
    end
  end

  def handle_event("cancel", _params, socket) do
    release_order(socket)

    {:noreply,
     push_navigate(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  def handle_event("stripe-payment-element-loading", _params, socket),
    do: {:noreply, assign(socket, :payment_element_ready, false)}

  def handle_event("stripe-payment-element-ready", _params, socket),
    do: {:noreply, assign(socket, :payment_element_ready, true)}

  def handle_event("payment-redirect-started", _params, socket),
    do: {:reply, %{}, socket}

  # Card payments finish in the browser; redirect methods come back through
  # the `:return` route instead.
  def handle_event("payment-success", %{"payment_intent_id" => pi_id}, socket) do
    case socket.assigns.ticket_order do
      %TicketOrder{} = order ->
        case StripeService.process_successful_payment(pi_id) do
          {:ok, %TicketOrder{id: id}} when id == order.id ->
            {:noreply,
             redirect(socket, to: ~p"/t/#{AccessToken.sign_order(id)}")}

          other ->
            Ysc.Logging.warning("Guest checkout payment-success not fulfilled",
              ticket_order_id: order.id,
              result: inspect(other)
            )

            {:noreply,
             put_toast(
               socket,
               :info,
               "Your payment is still processing. If you were charged, your tickets will be emailed to #{order.guest_email} shortly."
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:hold_expired, socket) do
    case socket.assigns do
      %{step: :payment, ticket_order: %TicketOrder{} = order} ->
        if Tickets.CheckoutCancel.pending_order_safe_to_cancel?(order,
             context: "guest_hold_expired"
           ) do
          Tickets.expire_ticket_order(order)

          {:noreply,
           socket
           |> put_toast(
             :error,
             "Time ran out, so we released your tickets. Please choose them again."
           )
           |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}")}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    # Closing the tab mid-checkout: the 5 minute timeout worker releases the
    # hold, so nothing to do here.
    {:ok, socket}
  end

  ## Private

  defp start_order(socket, guest) do
    %{event: event, selections: selections} = socket.assigns

    case GuestCheckout.create_order(guest, event.id, selections) do
      {:ok, order} ->
        begin_payment_or_finish(socket, order)

      {:error, reason} ->
        {:noreply, put_toast(socket, :error, order_error_message(reason))}
    end
  end

  defp begin_payment_or_finish(socket, order) do
    if Tickets.pending_order_still_complimentary?(order) do
      case Tickets.process_free_ticket_order(order) do
        {:ok, completed} ->
          {:noreply,
           redirect(socket, to: ~p"/t/#{AccessToken.sign_order(completed.id)}")}

        _ ->
          {:noreply, put_toast(socket, :error, order_error_message(:unknown))}
      end
    else
      case StripeService.create_payment_intent(order,
             receipt_email: order.guest_email
           ) do
        {:ok, payment_intent} ->
          Process.send_after(self(), :hold_expired, @hold_ms)

          {:noreply,
           socket
           |> assign(:step, :payment)
           |> assign(:ticket_order, order)
           |> assign(:payment_intent, payment_intent)}

        {:error, _reason} ->
          release_order(assign(socket, :ticket_order, order))

          {:noreply,
           put_toast(
             socket,
             :error,
             "We couldn't start your payment. Please try again in a moment."
           )}
      end
    end
  end

  defp release_order(%{assigns: %{ticket_order: %TicketOrder{} = order}}) do
    if Tickets.CheckoutCancel.pending_order_safe_to_cancel?(order,
         context: "guest_cancel"
       ) do
      Tickets.cancel_ticket_order(order, "Guest cancelled checkout",
        context: "guest_cancel"
      )
    end

    :ok
  end

  defp release_order(_socket), do: :ok

  defp load_selected_tiers(event_id, selections) do
    ids = Map.keys(selections)

    tiers =
      Repo.all(
        from(tt in TicketTier,
          where: tt.id in ^ids and tt.event_id == ^event_id
        )
      )

    if length(tiers) == length(ids), do: {:ok, tiers}, else: {:error, :tiers}
  end

  defp guest_attrs(params) do
    %{
      email: params["email"],
      first_name: params["first_name"],
      last_name: params["last_name"]
    }
  end

  defp guest_form(params, opts \\ []) do
    errors =
      if opts[:errors?] do
        case GuestCheckout.validate_guest(guest_attrs(params)) do
          {:error, {:invalid_guest, changeset}} ->
            for {field, {message, _}} <- changeset.errors,
                do: {contact_field(field), {message, []}}

          _ ->
            []
        end
      else
        []
      end

    to_form(params, as: :guest, errors: errors)
  end

  defp contact_field(:guest_email), do: :email
  defp contact_field(:guest_first_name), do: :first_name
  defp contact_field(:guest_last_name), do: :last_name

  defp billing_details_json(%TicketOrder{} = order) do
    Jason.encode!(%{
      name: TicketOrder.buyer_name(order),
      email: order.guest_email
    })
  end

  defp summary_lines(tiers, selections) do
    selections
    |> Enum.flat_map(fn {tier_id, quantity} ->
      case Map.get(tiers, tier_id) do
        nil -> []
        tier -> [{tier, quantity}]
      end
    end)
    |> Enum.sort_by(fn {tier, _} -> tier.name end)
  end

  defp donation?(%TicketTier{type: type}), do: type in [:donation, "donation"]

  defp line_price(%TicketTier{} = tier, quantity) do
    cond do
      donation?(tier) ->
        Money.to_string!(
          Money.new(Ysc.MoneyHelper.cents_to_dollars(quantity), :USD)
        )

      Money.zero?(tier.price) ->
        "Free"

      true ->
        tier.price |> Money.mult!(quantity) |> Money.to_string!()
    end
  end

  defp order_error_message({:invalid_guest, _}),
    do: "Please check your name and email."

  defp order_error_message(reason)
       when reason in [:overbooked, :event_capacity_exceeded, :stale_inventory],
       do: "Sorry, those tickets are no longer available."

  defp order_error_message(reason)
       when reason in [
              :event_in_past,
              :event_cancelled,
              :event_not_available,
              :event_not_found
            ],
       do: "Ticket sales for this event have closed."

  defp order_error_message(:tier_purchase_limit_exceeded),
    do:
      "That's more tickets of one type than a single buyer can get. Please reduce your selection."

  defp order_error_message(:checkout_payment_in_progress),
    do:
      "A payment for this email is still processing. If you were charged, your tickets will be emailed shortly."

  defp order_error_message(:guest_checkout_not_allowed),
    do: "Those tickets need a membership. Please sign in."

  defp order_error_message(reason) do
    Ysc.Logging.warning("Guest checkout could not create order",
      reason: inspect(reason)
    )

    "We couldn't hold your tickets. Please try again, or email #{Ysc.EmailConfig.contact_email()}."
  end

  defp put_toast(socket, kind, message),
    do: YscWeb.Flash.put_toast(socket, kind, message, title: "Tickets")

  defp leave(socket, path, kind, message) do
    socket |> put_toast(kind, message) |> push_navigate(to: path)
  end

  defp secure_equal?(a, b) when is_binary(a) and is_binary(b),
    do: Plug.Crypto.secure_compare(a, b)

  defp secure_equal?(_, _), do: false

  defp stripe_client,
    do: Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
end
