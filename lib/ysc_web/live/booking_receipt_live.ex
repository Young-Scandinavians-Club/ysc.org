defmodule YscWeb.BookingReceiptLive do
  use YscWeb, :live_view

  alias YscWeb.BookingGuestForm
  alias YscWeb.PaymentMethodFormatter
  alias YscWeb.PaymentMethodLogo
  alias YscWeb.BookingActions
  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, PendingRefund}
  alias Ysc.Ledgers.Refund
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias Ysc.Stripe.PaymentIntentHelpers
  require Ysc.Logging
  import Ecto.Query
  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{"booking_id" => booking_id} = params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "You must be signed in to view this receipt."
       )
       |> redirect(to: ~p"/")}
    else
      # SECURITY: Filter by user_id in the database query to prevent unauthorized access
      # This ensures we only fetch bookings that belong to the current user
      # PERFORMANCE: Preload all associations in a single query to avoid N+1
      booking_query =
        from(b in Booking,
          where: b.id == ^booking_id and b.user_id == ^user.id,
          preload: [
            {:user, :current_avatar},
            :booking_guests,
            rooms: :room_category
          ]
        )

      case Repo.one(booking_query) do
        nil ->
          {:ok,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             YscWeb.BookingUserMessages.reservation_not_found(),
             title: "Booking"
           )
           |> redirect(to: ~p"/")}

        booking ->
          # Handle Stripe redirect parameters (may update booking status)
          # Track if booking was actually updated to avoid unnecessary reload
          {socket, booking_updated, reservation_updated_from_redirect} =
            handle_stripe_redirect(params, booking, socket)

          show_reservation_updated =
            Map.get(params, "updated") == "true" or
              reservation_updated_from_redirect

          # PERFORMANCE: Only reload booking if redirect handling actually changed it
          booking =
            if booking_updated do
              from(b in Booking,
                where: b.id == ^booking_id and b.user_id == ^user.id,
                preload: [
                  {:user, :current_avatar},
                  :booking_guests,
                  rooms: :room_category
                ]
              )
              |> Repo.one!()
            else
              booking
            end

          # Get timezone from connect params
          connect_params =
            case get_connect_params(socket) do
              nil -> %{}
              v -> v
            end

          timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

          # Parse saved pricing items (saved at booking time) - no query needed
          price_breakdown = parse_pricing_items(booking.pricing_items)

          # Check if booking can be cancelled - no query needed
          can_cancel = BookingActions.can_cancel_booking?(booking)
          can_change = BookingActions.can_change_booking?(booking)

          # Check if confetti should be shown (only when coming from payment)
          show_confetti =
            Map.get(params, "confetti") == "true" ||
              Map.get(params, "redirect_status") == "succeeded"

          Ysc.Logging.debug(
            "Confetti check: params=#{inspect(params)}, show_confetti=#{show_confetti}"
          )

          # PERFORMANCE: Essential data for initial render
          # - booking, price_breakdown, can_cancel are needed immediately
          # - payment, refund_info, door_code, refund_data can be loaded after connection

          socket =
            socket
            |> assign(:booking, booking)
            |> assign(:timezone, timezone)
            |> assign(:price_breakdown, price_breakdown)
            |> assign(:user_first_name, user.first_name || "Member")
            |> assign(:booking_in_past, booking_checkout_in_past?(booking))
            |> assign(:can_cancel, can_cancel)
            |> assign(:can_change, can_change)
            |> assign(:show_cancel_modal, false)
            |> assign(:cancel_reason, "")
            |> assign(:show_confetti, show_confetti)
            |> assign(:show_reservation_updated, show_reservation_updated)
            |> assign(:page_title, "Booking Confirmation")
            |> assign(
              :meta_description,
              "Your cabin booking confirmation from Young Scandinavians Club."
            )
            # Placeholders for async-loaded data
            |> assign(:payment, nil)
            |> assign(:booking_payments, [])
            |> assign(:booking_payment_entries, [])
            |> assign(:total_paid_amount, nil)
            |> assign(:multiple_payments?, false)
            |> assign(:refund_info, nil)
            |> assign(:door_code, nil)
            |> assign(:show_door_code, false)
            |> assign(:refund_data, nil)
            |> assign(:payment_method_description, nil)
            |> assign(:payment_method_logo, nil)
            |> assign(:async_data_loaded, false)

          if connected?(socket) do
            # Load secondary data asynchronously after WebSocket connection
            {:ok, load_receipt_data_async(socket, booking)}
          else
            {:ok, socket}
          end
      end
    end
  end

  @impl true
  def handle_event("view-bookings", _params, socket) do
    property = socket.assigns.booking.property

    path =
      if property == :tahoe,
        do: ~p"/bookings/tahoe",
        else: ~p"/bookings/clear-lake"

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("go-home", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("show-cancel-modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, true)}
  end

  @impl true
  def handle_event("hide-cancel-modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, false)}
  end

  @impl true
  def handle_event("update-cancel-reason", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :cancel_reason, reason)}
  end

  @impl true
  def handle_event("update-cancel-reason", %{"value" => value}, socket) do
    {:noreply, assign(socket, :cancel_reason, value)}
  end

  @impl true
  def handle_event("confirm-cancel", %{"reason" => reason}, socket) do
    booking = socket.assigns.booking

    if can_cancel_booking?(booking) do
      case Bookings.cancel_booking(booking, get_today_pst(), reason) do
        {:ok, _canceled_booking, refund_amount, refund_result} ->
          # Check if refund_result is a PendingRefund (partial refund) or LedgerTransaction (full refund)
          is_pending_refund =
            case refund_result do
              %Ysc.Bookings.PendingRefund{} -> true
              _ -> false
            end

          refund_message =
            if Money.positive?(refund_amount) do
              if is_pending_refund do
                "Booking cancelled. Your refund of #{MoneyHelper.format_money!(refund_amount)} is pending admin review and will be processed once approved."
              else
                "Booking cancelled. A refund of #{MoneyHelper.format_money!(refund_amount)} will be processed."
              end
            else
              "Booking cancelled. No refund is available based on the cancellation policy."
            end

          {:noreply,
           socket
           |> assign(:show_cancel_modal, false)
           |> YscWeb.Flash.put_toast(:info, refund_message, title: "Booking")
           |> push_navigate(to: ~p"/bookings/#{booking.id}/receipt")}

        {:error, reason} ->
          error_message =
            case reason do
              {:payment_not_found, _} ->
                "Unable to process cancellation: payment not found."

              {:calculation_failed, _} ->
                "Unable to calculate refund amount."

              {:refund_failed, _} ->
                "Booking cancelled but refund processing failed. Please contact support."

              {:pending_refund_failed, _} ->
                "Booking cancelled but could not create pending refund. Please contact support."

              {:cancellation_failed, _} ->
                "Failed to cancel booking. Please try again or contact support."
            end

          {:noreply,
           socket
           |> assign(:show_cancel_modal, false)
           |> YscWeb.Flash.put_toast(:error, error_message)}
      end
    else
      {:noreply,
       socket
       |> assign(:show_cancel_modal, false)
       |> assign(:can_cancel, false)
       |> YscWeb.Flash.put_toast(
         :error,
         "This booking can no longer be cancelled.",
         title: "Cancellation"
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="booking-receipt"
      phx-hook="Confetti"
      data-show-confetti={if @show_confetti, do: "true", else: "false"}
      class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4"
    >
      <!-- Header -->
      <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-zinc-100 pb-8">
        <div>
          <%= if @booking.status == :canceled do %>
            <div class="flex items-center gap-2 text-red-600 mb-2">
              <.icon name="hero-x-circle" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">
                Reservation Cancelled
              </span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              Booking Cancelled
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              Your booking at
              <strong>{format_property_name(@booking.property)}</strong>
              has been cancelled.
              <%= if @refund_data && @refund_data.total_refunded do %>
                <%= if @refund_data.has_pending_refund do %>
                  A refund of
                  <strong>
                    {MoneyHelper.format_money!(@refund_data.total_refunded)}
                  </strong>
                  is pending admin review.
                <% else %>
                  A refund of
                  <strong>
                    {MoneyHelper.format_money!(@refund_data.total_refunded)}
                  </strong>
                  has been processed.
                <% end %>
              <% else %>
                No refund is available based on the cancellation policy.
              <% end %>
            </p>
          <% else %>
            <div class="flex items-center gap-2 text-green-600 mb-2">
              <.icon name="hero-check-circle-solid" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">
                {if @show_reservation_updated,
                  do: "Reservation Updated",
                  else: "Reservation Confirmed"}
              </span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              <%= cond do %>
                <% @show_reservation_updated -> %>
                  Your reservation has been updated, {@user_first_name}!
                <% @booking_in_past -> %>
                  What a stay, {@user_first_name}!
                <% true -> %>
                  See you at the Cabin, {@user_first_name}!
              <% end %>
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              <%= cond do %>
                <% @show_reservation_updated -> %>
                  Your updated stay at
                  <strong>{format_property_name(@booking.property)}</strong>
                  is confirmed. We've sent an email with your new reservation details.
                <% @booking_in_past -> %>
                  Hope you had an amazing time at <strong>{format_property_name(@booking.property)}</strong>.
                  See you next time!
                <% true -> %>
                  Your stay at
                  <strong>{format_property_name(@booking.property)}</strong>
                  is all set.
                  We've sent a copy of these details to your email.
              <% end %>
            </p>
          <% end %>
        </div>
        <div class="text-left md:text-right">
          <p class="text-xs font-bold text-zinc-400 uppercase tracking-widest">
            Booking Reference
          </p>
          <p class="font-mono text-lg font-semibold text-zinc-900 whitespace-nowrap">
            {@booking.reference_id}
          </p>
        </div>
      </div>
      <!-- Door Code Banner (if applicable) -->
      <%= if @show_door_code && @door_code do %>
        <div class={[
          "mb-8 rounded-lg p-8 shadow-xl border-4",
          if(@booking.property == :clear_lake,
            do:
              "bg-gradient-to-r from-teal-600 to-teal-700 border-teal-400 text-white",
            else:
              "bg-gradient-to-r from-blue-600 to-blue-700 border-blue-400 text-white"
          )
        ]}>
          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
            <div class="flex-1">
              <div class="flex items-center gap-3 mb-3">
                <.icon
                  name="hero-key"
                  class={[
                    "w-8 h-8",
                    if(@booking.property == :clear_lake,
                      do: "text-teal-200",
                      else: "text-blue-200"
                    )
                  ]}
                />
                <h2 class="text-2xl font-bold">Your Door Code</h2>
              </div>
              <p class={[
                "text-sm md:text-base",
                if(@booking.property == :clear_lake,
                  do: "text-teal-100",
                  else: "text-blue-100"
                )
              ]}>
                <%= if booking_is_active?(@booking) do %>
                  Your booking is currently active. Use this code to access the property.
                <% else %>
                  Your check-in is approaching. Save this code — you'll need it to access the property.
                <% end %>
              </p>
            </div>
            <div class="flex-shrink-0">
              <div class="bg-white/20 backdrop-blur-sm rounded-lg px-8 py-6 border-2 border-white/30">
                <p class={[
                  "text-xs font-bold uppercase tracking-widest mb-2 text-center",
                  if(@booking.property == :clear_lake,
                    do: "text-teal-200",
                    else: "text-blue-200"
                  )
                ]}>
                  Door Code
                </p>
                <p class="text-5xl font-mono font-black text-white text-center tracking-wider">
                  {@door_code.code}
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
        <!-- Left Column: Main Content -->
        <div class="lg:col-span-2 space-y-8">
          <%= if @booking.status == :canceled do %>
            <!-- Cancelled Booking Notice -->
            <div class="bg-red-50 border-2 border-red-300 rounded-lg p-6 mb-6">
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-exclamation-triangle"
                  class="w-8 h-8 text-red-600 flex-shrink-0 mt-1"
                />
                <div class="flex-1">
                  <h3 class="text-lg font-bold text-red-900 mb-2">
                    This Booking Has Been Cancelled
                  </h3>
                  <p class="text-sm text-red-800 leading-relaxed">
                    This reservation is no longer active. You will not have access to the property for these dates.
                    <%= if @refund_data && @refund_data.total_refunded do %>
                      Your refund information is shown in the payment summary on the right.
                    <% end %>
                  </p>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Stay Details Card -->
          <div class={[
            "rounded-lg border overflow-hidden",
            if(@booking.status == :canceled,
              do: "bg-zinc-100 border-zinc-300 opacity-60",
              else: "bg-zinc-50 border-zinc-200"
            )
          ]}>
            <!-- Property Image -->
            <div class={[
              "h-48 bg-zinc-200 relative",
              if(@booking.status == :canceled, do: "opacity-50 grayscale")
            ]}>
              <img
                src={get_property_thumbnail(@booking.property)}
                alt={format_property_name(@booking.property)}
                class="w-full h-full object-cover"
              />
              <%= if @booking.status == :canceled do %>
                <div class="absolute inset-0 bg-red-500/20 flex items-center justify-center">
                  <div class="bg-white/90 rounded-lg px-6 py-3 shadow-lg">
                    <p class="text-red-700 font-bold text-lg uppercase tracking-wider">
                      Cancelled
                    </p>
                  </div>
                </div>
              <% end %>
              <div class="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent flex items-end p-6">
                <div class="flex items-center justify-between w-full">
                  <h2 class={[
                    "text-xl font-bold flex items-center gap-2",
                    if(@booking.status == :canceled,
                      do: "text-zinc-300 line-through",
                      else: "text-white"
                    )
                  ]}>
                    <.icon name="hero-information-circle" class="w-8 h-8" />
                    Stay Details
                  </h2>
                  <span class={[
                    "text-sm font-medium px-3 py-1 rounded-full",
                    if(@booking.status == :canceled,
                      do: "bg-zinc-300 text-zinc-600",
                      else: "bg-blue-100 text-blue-700"
                    )
                  ]}>
                    {Date.diff(@booking.checkout_date, @booking.checkin_date)} {if Date.diff(
                                                                                     @booking.checkout_date,
                                                                                     @booking.checkin_date
                                                                                   ) ==
                                                                                     1,
                                                                                   do:
                                                                                     "Night",
                                                                                   else:
                                                                                     "Nights"}
                  </span>
                </div>
              </div>
            </div>
            <div class="p-8 grid grid-cols-1 md:grid-cols-3 gap-8">
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500",
                    else: "text-zinc-400"
                  )
                ]}>
                  Check-in
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  {format_date(@booking.checkin_date, @timezone)}
                </p>
                <p class={[
                  "text-sm",
                  if(@booking.status == :canceled,
                    do: "text-zinc-400",
                    else: "text-zinc-500"
                  )
                ]}>
                  After 3:00 PM
                </p>
              </div>
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500",
                    else: "text-zinc-400"
                  )
                ]}>
                  Check-out
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  {format_date(@booking.checkout_date, @timezone)}
                </p>
                <p class={[
                  "text-sm",
                  if(@booking.status == :canceled,
                    do: "text-zinc-400",
                    else: "text-zinc-500"
                  )
                ]}>
                  Before 11:00 AM
                </p>
              </div>
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500",
                    else: "text-zinc-400"
                  )
                ]}>
                  <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                    {if length(@booking.rooms) == 1, do: "Room", else: "Rooms"}
                  <% else %>
                    Reservation type
                  <% end %>
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                    {Enum.map_join(@booking.rooms, ", ", fn room -> room.name end)}
                  <% else %>
                    <%= if @booking.booking_mode == :buyout do %>
                      Entire cabin
                    <% else %>
                      Individual room(s)
                    <% end %>
                  <% end %>
                </p>
                <p
                  :if={@booking.booking_mode != :buyout}
                  class={[
                    "text-sm",
                    if(@booking.status == :canceled,
                      do: "text-zinc-400",
                      else: "text-zinc-500"
                    )
                  ]}
                >
                  {@booking.guests_count} {if @booking.guests_count == 1,
                    do: "Adult",
                    else: "Adults"}
                  <%= if @booking.children_count > 0 do %>
                    , {@booking.children_count} {if @booking.children_count ==
                                                      1,
                                                    do: "Child",
                                                    else: "Children"}
                  <% end %>
                </p>
              </div>
            </div>
          </div>
          <!-- Guest Information (if booking guests exist) -->
          <%= if Ecto.assoc_loaded?(@booking.booking_guests) && length(@booking.booking_guests) > 0 do %>
            <div class={[
              "rounded-lg border overflow-hidden",
              if(@booking.status == :canceled,
                do: "bg-zinc-100 border-zinc-300 opacity-60",
                else: "bg-white border-zinc-200"
              )
            ]}>
              <div class="p-8">
                <h2 class={[
                  "text-xl font-bold mb-6 flex items-center gap-2",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  <.icon name="hero-users" class="w-6 h-6" /> Guest Information
                </h2>
                <div class="space-y-4">
                  <%= for guest <- Enum.sort_by(@booking.booking_guests, & &1.order_index) do %>
                    <div class={[
                      "flex items-center gap-4 p-4 rounded-lg border-l-4",
                      if(guest.is_child,
                        do: "bg-green-50 border-green-300",
                        else: "bg-blue-50 border-blue-300"
                      )
                    ]}>
                      <div class={[
                        "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm overflow-hidden",
                        if(guest.is_child,
                          do: "bg-green-100 text-green-700",
                          else: "bg-blue-100 text-blue-700"
                        )
                      ]}>
                        <%= if guest.is_booking_user do %>
                          <%= if Ecto.assoc_loaded?(@booking.user) && @booking.user do %>
                            <.user_avatar_image
                              user={@booking.user}
                              class="w-full h-full object-cover"
                            />
                          <% else %>
                            <.icon name="hero-user-circle" class="w-5 h-5" />
                          <% end %>
                        <% else %>
                          {guest.order_index + 1}
                        <% end %>
                      </div>
                      <div class="flex-1">
                        <div class="flex items-center justify-between mb-1">
                          <h3 class={[
                            "font-semibold",
                            if(@booking.status == :canceled,
                              do: "text-zinc-500 line-through",
                              else: "text-zinc-900"
                            )
                          ]}>
                            <%= if guest.is_booking_user do %>
                              {guest.first_name} {guest.last_name}
                              <span class="text-xs font-normal text-zinc-500 ml-2">
                                (Booking Member)
                              </span>
                            <% else %>
                              {guest.first_name} {guest.last_name}
                            <% end %>
                          </h3>
                          <span class={[
                            "text-xs font-medium px-2 py-1 rounded",
                            if(guest.is_child,
                              do: "bg-green-200 text-green-800",
                              else: "bg-blue-200 text-blue-800"
                            )
                          ]}>
                            {if guest.is_child, do: "Child", else: "Adult"}
                          </span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Utility Cards (Hidden for cancelled bookings) -->
          <%= if @booking.status != :canceled do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <!-- Cabin Access -->
              <div class="p-6 bg-white border border-zinc-200 rounded-lg">
                <h3 class="font-bold text-zinc-900 mb-3 flex items-center gap-2">
                  <.icon name="hero-key" class="w-5 h-5" /> Cabin Access
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Door codes and key instructions are sent via email 24 hours before your check-in.
                </p>
                <a
                  href={get_cabin_access_url(@booking.property)}
                  class="text-sm font-semibold text-blue-600 hover:underline"
                >
                  View Door Code Info →
                </a>
              </div>
              <!-- Cabin Rules -->
              <div class="p-6 bg-white border border-zinc-200 rounded-lg">
                <h3 class="font-bold text-zinc-900 mb-3 flex items-center gap-2">
                  <.icon name="hero-document-check" class="w-5 h-5" /> Cabin Rules
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Reminder: Bring your own bed sheets and comforters and ensure the kitchen is cleaned before departure.
                </p>
                <a
                  href={get_cabin_rules_url(@booking.property)}
                  class="text-sm font-semibold text-blue-600 hover:underline"
                >
                  Read Cabin Rules →
                </a>
              </div>
            </div>
          <% end %>
        </div>
        <!-- Right Column: Sidebar -->
        <aside class="space-y-6">
          <!-- Payment Summary Loading Skeleton -->
          <div
            :if={!@async_data_loaded}
            class="rounded-lg p-8 shadow-xl bg-zinc-900 animate-pulse"
          >
            <div class="h-3 w-32 bg-zinc-700 rounded mb-6"></div>
            <div class="space-y-4">
              <div class="flex justify-between">
                <div class="h-4 w-24 bg-zinc-700 rounded"></div>
                <div class="h-4 w-16 bg-zinc-700 rounded"></div>
              </div>
              <div class="border-t border-zinc-700 pt-4 flex justify-between">
                <div class="h-4 w-20 bg-zinc-700 rounded"></div>
                <div class="h-6 w-24 bg-zinc-700 rounded"></div>
              </div>
              <div class="border-t border-zinc-700 pt-4 space-y-2">
                <div class="h-3 w-28 bg-zinc-700 rounded"></div>
                <div class="h-3 w-40 bg-zinc-700 rounded"></div>
              </div>
            </div>
          </div>
          <!-- Payment Summary -->
          <%= if @async_data_loaded && @payment do %>
            <div class={[
              "rounded-lg p-8 shadow-xl",
              if(@booking.status == :canceled,
                do: "bg-red-50 border-2 border-red-200",
                else: "bg-zinc-900 text-white"
              )
            ]}>
              <h3 class={[
                "text-xs font-bold uppercase tracking-widest mb-6",
                if(@booking.status == :canceled,
                  do: "text-red-700",
                  else: "text-zinc-400"
                )
              ]}>
                {if @booking.status == :canceled,
                  do: "Payment & Refund Summary",
                  else: "Payment Summary"}
              </h3>
              <%= if @show_reservation_updated && @booking.status != :canceled do %>
                <div
                  id="reservation-updated-notice"
                  class="mb-6 rounded-lg border border-emerald-500/40 bg-emerald-500/10 p-4"
                >
                  <div class="flex items-start gap-3">
                    <.icon
                      name="hero-check-circle"
                      class="w-5 h-5 text-emerald-400 shrink-0 mt-0.5"
                    />
                    <div>
                      <p class="font-semibold text-emerald-300">
                        Reservation updated
                      </p>
                      <p class="text-sm text-zinc-400 mt-1">
                        Your changes are saved. The details below reflect your updated reservation.
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
              <div class={[
                "space-y-4 text-sm",
                if(@booking.status == :canceled, do: "text-zinc-900", else: "")
              ]}>
                <!-- Price Breakdown -->
                <%= if @price_breakdown do %>
                  <%= case @booking.booking_mode do %>
                    <% :buyout -> %>
                      <%= if @price_breakdown.nights && @price_breakdown.price_per_night do %>
                        <div
                          id="payment-summary-buyout-line"
                          class="flex justify-between"
                        >
                          <span class={
                            if(@booking.status == :canceled,
                              do: "text-zinc-600",
                              else: "text-zinc-400"
                            )
                          }>
                            Entire cabin
                            ({MoneyHelper.format_money!(
                              @price_breakdown.price_per_night
                            )} × {@price_breakdown.nights} {if @price_breakdown.nights ==
                                                                 1,
                                                               do: "night",
                                                               else: "nights"})
                          </span>
                          <span class={
                            if(@booking.status == :canceled,
                              do: "text-zinc-700",
                              else: "text-zinc-300"
                            )
                          }>
                            {MoneyHelper.format_money!(
                              buyout_line_amount(@price_breakdown, @booking)
                            )}
                          </span>
                        </div>
                      <% end %>
                    <% :day -> %>
                      <%= if @price_breakdown.nights && @price_breakdown.price_per_guest_per_night && @price_breakdown.guests_count do %>
                        <% total_guest_nights =
                          @price_breakdown.nights * @price_breakdown.guests_count %>
                        <div class="flex justify-between">
                          <span class={
                            if(@booking.status == :canceled,
                              do: "text-zinc-600",
                              else: "text-zinc-400"
                            )
                          }>
                            Spot Rental
                            ({@price_breakdown.guests_count} {if @price_breakdown.guests_count ==
                                                                   1,
                                                                 do: "adult",
                                                                 else: "adults"} × {@price_breakdown.nights} {if @price_breakdown.nights ==
                                                                                                                   1,
                                                                                                                 do:
                                                                                                                   "night",
                                                                                                                 else:
                                                                                                                   "nights"})
                          </span>
                          <span class={
                            if(@booking.status == :canceled,
                              do: "text-zinc-700",
                              else: "text-zinc-300"
                            )
                          }>
                            {MoneyHelper.format_money!(
                              Money.mult(
                                @price_breakdown.price_per_guest_per_night,
                                total_guest_nights
                              )
                              |> elem(1)
                            )}
                          </span>
                        </div>
                      <% end %>
                    <% :room -> %>
                      <%= if @price_breakdown.nights do %>
                        <%= if @price_breakdown[:base] do %>
                          <div class="flex justify-between">
                            <span class={
                              if(@booking.status == :canceled,
                                do: "text-zinc-600",
                                else: "text-zinc-400"
                              )
                            }>
                              Base Price
                              <%= if @price_breakdown[:adult_price_per_night] do %>
                                <% adult_count =
                                  @price_breakdown[:billable_people] ||
                                    @price_breakdown[:guests_count] || 0 %> ({adult_count} {if adult_count ==
                                                                                                 1,
                                                                                               do:
                                                                                                 "adult",
                                                                                               else:
                                                                                                 "adults"} × {@price_breakdown.nights} {if @price_breakdown.nights ==
                                                                                                                                             1,
                                                                                                                                           do:
                                                                                                                                             "night",
                                                                                                                                           else:
                                                                                                                                             "nights"})
                              <% end %>
                            </span>
                            <span class={
                              if(@booking.status == :canceled,
                                do: "text-zinc-700",
                                else: "text-zinc-300"
                              )
                            }>
                              {MoneyHelper.format_money!(@price_breakdown.base)}
                            </span>
                          </div>
                        <% end %>
                        <%= if @price_breakdown[:children] && @price_breakdown[:children_count] && @price_breakdown[:children_count] > 0 do %>
                          <div class="flex justify-between">
                            <span class={
                              if(@booking.status == :canceled,
                                do: "text-zinc-600",
                                else: "text-zinc-400"
                              )
                            }>
                              Children
                              ({@price_breakdown[:children_count]} {if @price_breakdown[
                                                                         :children_count
                                                                       ] ==
                                                                         1,
                                                                       do: "child",
                                                                       else:
                                                                         "children"} × {@price_breakdown.nights} {if @price_breakdown.nights ==
                                                                                                                       1,
                                                                                                                     do:
                                                                                                                       "night",
                                                                                                                     else:
                                                                                                                       "nights"})
                            </span>
                            <span class={
                              if(@booking.status == :canceled,
                                do: "text-zinc-700",
                                else: "text-zinc-300"
                              )
                            }>
                              {MoneyHelper.format_money!(@price_breakdown.children)}
                            </span>
                          </div>
                        <% end %>
                      <% end %>
                  <% end %>
                <% end %>
                <%= if @multiple_payments? && @booking.total_price do %>
                  <div class="flex justify-between">
                    <span class={
                      if(@booking.status == :canceled,
                        do: "text-zinc-600",
                        else: "text-zinc-400"
                      )
                    }>
                      Reservation total
                    </span>
                    <span class={
                      if(@booking.status == :canceled,
                        do: "text-zinc-700",
                        else: "text-zinc-300"
                      )
                    }>
                      {MoneyHelper.format_money!(@booking.total_price)}
                    </span>
                  </div>
                  <div
                    id="booking-payment-history"
                    class="space-y-2 border-t border-zinc-800 pt-4"
                  >
                    <p class={
                      if(@booking.status == :canceled,
                        do:
                          "text-xs font-semibold text-zinc-600 uppercase tracking-wider",
                        else:
                          "text-xs font-semibold text-zinc-500 uppercase tracking-wider"
                      )
                    }>
                      Payments
                    </p>
                    <%= for entry <- @booking_payment_entries do %>
                      <div
                        id={"payment-history-#{entry.payment.id}"}
                        class="flex justify-between gap-3 text-xs"
                      >
                        <div class="min-w-0">
                          <p class={
                            if(@booking.status == :canceled,
                              do: "text-zinc-500",
                              else: "text-zinc-400"
                            )
                          }>
                            {format_payment_date(
                              entry.payment.payment_date,
                              @timezone
                            )}
                          </p>
                          <%= if entry.method_description do %>
                            <p class="inline-flex items-center gap-1.5 text-zinc-300 mt-0.5 min-w-0">
                              <%= if entry.method_logo do %>
                                <img
                                  src={entry.method_logo}
                                  alt=""
                                  class="h-4 w-auto max-w-[2.5rem] object-contain shrink-0"
                                  loading="lazy"
                                  decoding="async"
                                />
                              <% end %>
                              <span class="min-w-0">
                                {entry.method_description}
                              </span>
                            </p>
                          <% end %>
                        </div>
                        <span class={
                          if(@booking.status == :canceled,
                            do: "text-zinc-700 shrink-0",
                            else: "text-zinc-300 shrink-0"
                          )
                        }>
                          {MoneyHelper.format_money!(entry.payment.amount)}
                        </span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <div class={[
                  "flex justify-between",
                  if(@booking.status == :canceled,
                    do: "border-t border-red-200 pt-4",
                    else: "border-t border-zinc-800 pt-4"
                  )
                ]}>
                  <span class={
                    if(@booking.status == :canceled,
                      do: "text-zinc-600",
                      else: "text-zinc-400"
                    )
                  }>
                    Total Paid
                  </span>
                  <span class={[
                    "font-bold text-xl",
                    if(@booking.status == :canceled,
                      do: "text-zinc-900",
                      else: "text-blue-400"
                    )
                  ]}>
                    {MoneyHelper.format_money!(receipt_total_paid_amount(assigns))}
                  </span>
                </div>
                <%= if @booking.status == :canceled && @refund_data do %>
                  <%= if @refund_data.total_refunded do %>
                    <div class="flex justify-between border-t border-red-200 pt-4">
                      <span class="text-zinc-600">Refunded</span>
                      <span class="font-bold text-green-600 text-xl">
                        {MoneyHelper.format_money!(@refund_data.total_refunded)}
                      </span>
                    </div>
                    <%= if @refund_data.has_pending_refund do %>
                      <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mt-2">
                        <div class="flex items-start gap-2">
                          <.icon
                            name="hero-clock"
                            class="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0"
                          />
                          <p class="text-xs text-amber-800">
                            <strong>Pending Review:</strong>
                            This refund is pending admin approval and will be processed once approved.
                          </p>
                        </div>
                      </div>
                    <% end %>
                    <%= if @refund_data.processed_refunds && length(@refund_data.processed_refunds) > 0 do %>
                      <div class="border-t border-red-200 pt-4 space-y-2">
                        <p class="text-xs font-semibold text-zinc-600 uppercase tracking-wider">
                          Refund Details
                        </p>
                        <%= for refund <- @refund_data.processed_refunds do %>
                          <div class="flex justify-between text-xs">
                            <span class="text-zinc-500">
                              {MoneyHelper.format_money!(refund.amount)}
                              <%= if refund.reason do %>
                                <span class="text-zinc-400">
                                  • {String.slice(refund.reason, 0, 30)}{if String.length(
                                                                              refund.reason
                                                                            ) >
                                                                              30,
                                                                            do:
                                                                              "..."}
                                </span>
                              <% end %>
                            </span>
                            <span class={[
                              "font-medium",
                              if(refund.status == :completed,
                                do: "text-green-600",
                                else: "text-amber-600"
                              )
                            ]}>
                              {if refund.status == :completed,
                                do: "Processed",
                                else:
                                  String.capitalize(Atom.to_string(refund.status))}
                            </span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    <div class="flex justify-between border-t-2 border-red-300 pt-4 mt-4">
                      <span class="font-semibold text-zinc-900">Net Amount</span>
                      <span class="font-bold text-red-600 text-xl">
                        {case Money.sub(
                                receipt_total_paid_amount(assigns),
                                @refund_data.total_refunded
                              ) do
                          {:ok, net} ->
                            MoneyHelper.format_money!(net)

                          _ ->
                            MoneyHelper.format_money!(
                              receipt_total_paid_amount(assigns)
                            )
                        end}
                      </span>
                    </div>
                  <% else %>
                    <div class="bg-zinc-100 border border-zinc-300 rounded-lg p-3 mt-2">
                      <p class="text-xs text-zinc-700">
                        No refund is available based on the cancellation policy.
                      </p>
                    </div>
                  <% end %>
                <% end %>
                <%= unless @multiple_payments? do %>
                  <div
                    id="payment-method-summary"
                    class={[
                      "flex justify-between items-center gap-2",
                      if(@booking.status == :canceled,
                        do: "border-t border-red-200 pt-4",
                        else: "border-t border-zinc-800 pt-4"
                      )
                    ]}
                  >
                    <span class={
                      if(@booking.status == :canceled,
                        do: "text-zinc-600",
                        else: "text-zinc-400"
                      )
                    }>
                      Method
                    </span>
                    <span class="inline-flex items-center gap-2 justify-end text-right min-w-0">
                      <%= if @payment_method_logo do %>
                        <img
                          src={@payment_method_logo}
                          alt=""
                          class="h-5 w-auto max-w-[3rem] object-contain shrink-0"
                          loading="lazy"
                          decoding="async"
                        />
                      <% end %>
                      <span class="min-w-0">{@payment_method_description}</span>
                    </span>
                  </div>
                  <div id="payment-date-summary" class="flex justify-between">
                    <span class={
                      if(@booking.status == :canceled,
                        do: "text-zinc-600",
                        else: "text-zinc-400"
                      )
                    }>
                      Date
                    </span>
                    <span>
                      {format_payment_date(@payment.payment_date, @timezone)}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <!-- Action Buttons -->
          <div class="space-y-3">
            <%= if @booking.status == :complete && @can_change do %>
              <.button
                navigate={~p"/bookings/#{@booking.id}/change"}
                class="w-full py-3"
                id="change-reservation-button"
              >
                <.icon name="hero-pencil-square" class="w-5 h-5 -mt-0.5 me-2" />Change Reservation
              </.button>
            <% end %>
            <%= if @booking.status != :canceled && @can_cancel do %>
              <.button phx-click="show-cancel-modal" class="w-full py-3" color="red">
                <.icon name="hero-x-circle" class="w-5 h-5 -mt-0.5 me-2" />Cancel Reservation
              </.button>
            <% end %>
            <.button
              phx-click="go-home"
              class="w-full py-3"
              color="zinc"
              variant="outline"
            >
              <.icon name="hero-arrow-left" class="w-5 h-5 -mt-0.5 me-2" />Return to Dashboard
            </.button>
          </div>
        </aside>
      </div>
      <!-- Cancel Booking Modal -->
      <%= if @show_cancel_modal do %>
        <.modal
          id="cancel-booking-modal"
          on_cancel={JS.push("hide-cancel-modal")}
          show
        >
          <.modal_title id="cancel-booking-modal-title">
            Cancel Booking
          </.modal_title>

          <div class="space-y-4">
            <p class="text-zinc-600">
              Are you sure you want to cancel this booking? This action cannot be undone.
            </p>
            <!-- Refund Information -->
            <%= if @refund_info && Map.get(@refund_info, :modified) do %>
              <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                <div class="flex items-center gap-2 text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
                  <p class="font-semibold">No Refund Available</p>
                </div>
                <p class="text-sm text-amber-700 mt-2 pl-7">
                  This reservation was modified, so cancellation refunds no longer apply. You may still cancel, but you will not receive a refund.
                </p>
              </div>
            <% else %>
              <%= if @refund_info && @refund_info.estimated_refund do %>
                <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 space-y-3">
                  <div class="flex items-center gap-2 text-blue-800">
                    <.icon name="hero-information-circle" class="w-5 h-5" />
                    <p class="font-semibold">Estimated Refund</p>
                  </div>
                  <div class="pl-7 space-y-2">
                    <div class="flex justify-between items-baseline">
                      <span class="text-sm text-blue-700">Original Payment:</span>
                      <span class="text-sm font-medium text-blue-900">
                        <%= if receipt_total_paid_amount(assigns) do %>
                          {MoneyHelper.format_money!(
                            receipt_total_paid_amount(assigns)
                          )}
                        <% else %>
                          —
                        <% end %>
                      </span>
                    </div>
                    <div class="flex justify-between items-baseline">
                      <span class="text-sm text-blue-700">Estimated Refund:</span>
                      <span class="text-lg font-bold text-blue-900">
                        {MoneyHelper.format_money!(@refund_info.estimated_refund)}
                      </span>
                    </div>
                    <%= if @refund_info.applied_rule do %>
                      <% refund_percent =
                        Decimal.to_float(
                          @refund_info.applied_rule.refund_percentage
                        )
                        |> Float.round(0)
                        |> trunc() %>
                      <p class="text-xs text-blue-600 mt-2 pt-2 border-t border-blue-200">
                        Based on cancellation policy: {refund_percent}% refund if cancelled {@refund_info.applied_rule.days_before_checkin} days or more before check-in.
                      </p>
                    <% else %>
                      <p class="text-xs text-blue-600 mt-2 pt-2 border-t border-blue-200">
                        Full refund based on cancellation policy.
                      </p>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                  <div class="flex items-center gap-2 text-amber-800">
                    <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
                    <p class="font-semibold">No Refund Available</p>
                  </div>
                  <p class="text-sm text-amber-700 mt-2 pl-7">
                    Based on the cancellation policy and timing of your cancellation, no refund is available for this booking.
                  </p>
                </div>
              <% end %>
            <% end %>

            <.simple_form
              for={%{}}
              id="cancel-booking-form"
              phx-submit="confirm-cancel"
            >
              <.input
                type="textarea"
                name="reason"
                label="Cancellation Reason (Optional)"
                value={@cancel_reason}
                phx-blur="update-cancel-reason"
                phx-debounce="300"
                rows="3"
              />

              <:actions>
                <.button type="submit" color="red" phx-disable-with="Cancelling...">
                  Cancel Booking
                </.button>
                <.button
                  type="button"
                  phx-click="hide-cancel-modal"
                  class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
                >
                  Keep Booking
                </.button>
              </:actions>
            </.simple_form>
          </div>
        </.modal>
      <% end %>
      <!-- Footer Note -->
      <div class="mt-12 pt-8 border-t border-zinc-100">
        <p class="text-sm text-zinc-500 text-center">
          The YSC is run by members like you. If you have questions about your stay, contact the {format_property_name(
            @booking.property
          )} Cabin Master at
          <a
            href={"mailto:#{get_cabin_master_email(@booking.property)}"}
            class="text-blue-600 hover:text-blue-500 underline"
          >
            {get_cabin_master_email(@booking.property)}
          </a>
          .
        </p>
      </div>
    </div>
    """
  end

  ## Private Functions

  @dialyzer {:nowarn_function, handle_stripe_redirect: 3}
  defp handle_stripe_redirect(params, booking, socket) do
    redirect_status = Map.get(params, "redirect_status")
    payment_intent_id = Map.get(params, "payment_intent")

    case {redirect_status, payment_intent_id} do
      {"succeeded", payment_intent_id} when not is_nil(payment_intent_id) ->
        # Payment succeeded via redirect - process it
        case process_payment_from_redirect(booking, payment_intent_id) do
          {:ok, _confirmed_booking, payment_intent} ->
            reservation_updated = modification_payment_intent?(payment_intent)

            socket =
              if reservation_updated do
                YscWeb.Flash.put_toast(
                  socket,
                  :info,
                  "Your reservation has been updated.",
                  title: "Reservation updated"
                )
              else
                YscWeb.Flash.put_toast(
                  socket,
                  :info,
                  "Payment successful! Your booking is confirmed."
                )
              end

            {socket, true, reservation_updated}

          {:error, reason} ->
            Ysc.Logging.error("Failed to process payment from redirect",
              booking_id: booking.id,
              payment_intent_id: payment_intent_id,
              error: reason
            )

            {socket
             |> YscWeb.Flash.put_toast(
               :error,
               modification_redirect_error_message(reason)
             ), false, false}
        end

      {"failed", _payment_intent_id} ->
        {socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Payment failed. Please try again or contact support if the problem persists."
         ), false, false}

      _ ->
        # No redirect parameters or unknown status
        {socket, false, false}
    end
  end

  defp process_payment_from_redirect(booking, payment_intent_id) do
    process_payment_success(booking, payment_intent_id)
  end

  @dialyzer {:nowarn_function, process_payment_success: 2}
  defp process_payment_success(booking, payment_intent_id_or_secret) do
    # Extract payment intent ID if a client secret was passed
    payment_intent_id =
      if String.contains?(payment_intent_id_or_secret, "_secret_") do
        payment_intent_id_or_secret
        |> String.split("_secret_")
        |> List.first()
      else
        payment_intent_id_or_secret
      end

    # Stripe rejects `expand[]=latest_charge.payment_method` on PaymentIntent retrieve.
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "latest_charge"]
         }) do
      {:ok, payment_intent} ->
        if payment_intent.status == "succeeded" do
          verification_result =
            if modification_payment_intent?(payment_intent) do
              :ok
            else
              Bookings.verify_booking_payment_intent(payment_intent, booking)
            end

          case verification_result do
            :ok ->
              process_verified_booking_payment_success(
                booking,
                payment_intent,
                payment_intent_id
              )

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :payment_not_succeeded}
        end

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to retrieve payment intent: #{inspect(reason)}"
        )

        {:error, :payment_verification_failed}
    end
  end

  defp process_verified_booking_payment_success(
         booking,
         payment_intent,
         payment_intent_id
       ) do
    reloaded_booking =
      Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

    if reloaded_booking.status == :complete do
      if modification_payment_intent?(payment_intent) do
        finalize_modification_redirect_payment(
          reloaded_booking,
          payment_intent_id,
          payment_intent
        )
      else
        finalize_paid_ledger_payment(reloaded_booking, payment_intent)
      end
    else
      case BookingLocker.confirm_booking(reloaded_booking.id) do
        {:ok, confirmed_booking} ->
          case process_ledger_payment(confirmed_booking, payment_intent) do
            {:ok, _payment} ->
              {:ok, confirmed_booking, payment_intent}

            {:error, reason} ->
              Ysc.Logging.error(
                "Booking confirmed but ledger payment recording failed",
                booking_id: confirmed_booking.id,
                error: inspect(reason)
              )

              {:error, :payment_processing_failed}
          end

        {:error, :invalid_status} ->
          final_booking =
            Repo.get!(Booking, reloaded_booking.id)
            |> Repo.preload([:rooms, :user])

          if final_booking.status == :complete do
            Ysc.Logging.info(
              "Booking confirmed by another process, ensuring ledger payment",
              booking_id: booking.id
            )

            finalize_paid_ledger_payment(final_booking, payment_intent)
          else
            Ysc.Logging.error(
              "Failed to confirm booking: invalid status",
              booking_id: booking.id,
              status: final_booking.status
            )

            {:error, :booking_confirmation_failed}
          end

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to confirm booking: #{inspect(reason)}",
            booking_id: reloaded_booking.id
          )

          {:error, :booking_confirmation_failed}
      end
    end
  end

  defp finalize_paid_ledger_payment(booking, payment_intent) do
    case process_ledger_payment(booking, payment_intent) do
      {:ok, _payment} ->
        {:ok, booking, payment_intent}

      {:error, reason} ->
        {:error, {:ledger_payment_failed, reason}}
    end
  end

  defp finalize_modification_redirect_payment(
         booking,
         payment_intent_id,
         payment_intent
       ) do
    hold_attrs = booking.modification_hold_attrs
    original_booking = booking

    cond do
      Bookings.modification_ledger_recorded?(booking.id, payment_intent_id) ->
        {:ok, reload_booking_for_receipt(booking.id), payment_intent}

      true ->
        case modification_params_from_hold(booking) do
          nil ->
            finalize_modification_ledger_only(
              booking,
              payment_intent_id,
              payment_intent
            )

          attrs ->
            case Bookings.apply_modification(booking, attrs,
                   payment_intent_id: payment_intent_id
                 ) do
              {:ok, updated_booking} ->
                sync_guests_after_modification_redirect(
                  updated_booking,
                  hold_attrs,
                  original_booking
                )

                {:ok, reload_booking_for_receipt(updated_booking.id),
                 payment_intent}

              {:error, :no_changes} ->
                finalize_modification_ledger_only(
                  booking,
                  payment_intent_id,
                  payment_intent
                )

              {:error, {:ledger_payment_failed, _reason}} ->
                finalize_modification_ledger_only(
                  booking,
                  payment_intent_id,
                  payment_intent
                )

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  defp sync_guests_after_modification_redirect(
         updated_booking,
         hold_attrs,
         original_booking
       ) do
    case BookingGuestForm.sync_guests_after_modification_apply(
           updated_booking,
           hold_attrs,
           original_booking
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Modification applied but guest details could not be saved",
          booking_id: updated_booking.id,
          error: inspect(reason)
        )
    end
  end

  defp finalize_modification_ledger_only(
         booking,
         payment_intent_id,
         payment_intent
       ) do
    case Bookings.ensure_modification_ledger_recorded(
           booking,
           payment_intent_id
         ) do
      :ok ->
        {:ok, reload_booking_for_receipt(booking.id), payment_intent}

      {:error, :modification_not_applied} ->
        {:error, :modification_hold_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp modification_params_from_hold(%Booking{modification_hold_attrs: attrs})
       when is_map(attrs) do
    if is_binary(attrs["checkin_date"]) and is_binary(attrs["checkout_date"]) do
      %{
        "checkin_date" => attrs["checkin_date"],
        "checkout_date" => attrs["checkout_date"],
        "guests_count" => attrs["guests_count"] |> to_string(),
        "children_count" => Map.get(attrs, "children_count", 0) |> to_string()
      }
    else
      nil
    end
  end

  defp modification_params_from_hold(_), do: nil

  defp reload_booking_for_receipt(booking_id) do
    Repo.get!(Booking, booking_id) |> Repo.preload([:rooms, :user])
  end

  defp modification_redirect_error_message(:modification_hold_expired) do
    "Payment was successful, but your reservation hold expired before the change could be saved. Please contact support with your booking reference."
  end

  defp modification_redirect_error_message({:ledger_payment_failed, _reason}) do
    "Payment was successful, but we could not record it for your updated reservation. Please contact support with your booking reference."
  end

  defp modification_redirect_error_message(_reason) do
    "Payment was successful, but there was an issue updating your reservation. Please contact support with your booking reference."
  end

  defp modification_payment_intent?(payment_intent) do
    metadata = payment_intent.metadata || %{}

    Map.get(metadata, "modification") == "true" ||
      Map.get(metadata, :modification) == "true"
  end

  defp process_ledger_payment(booking, payment_intent) do
    amount = MoneyHelper.cents_to_money(payment_intent.amount, :USD)
    # Use consolidated fee extraction from Stripe.WebhookHandler
    stripe_fee =
      Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent(
        payment_intent
      )

    # Extract and sync payment method to get our internal ULID
    payment_method_id =
      extract_and_sync_payment_method(payment_intent, booking.user_id)

    attrs = %{
      user_id: booking.user_id,
      amount: amount,
      entity_type: :booking,
      entity_id: booking.id,
      external_payment_id: payment_intent.id,
      stripe_fee: stripe_fee,
      description: "Booking payment - #{booking.reference_id}",
      property: booking.property,
      payment_method_id: payment_method_id
    }

    case Ysc.Ledgers.process_payment(attrs) do
      {:ok, {payment, _transaction, _entries}} ->
        {:ok, payment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_and_sync_payment_method(payment_intent, user_id) do
    # Try to get payment method from payment intent
    stripe_payment_method_id =
      cond do
        # Payment intent might have payment_method as a string ID
        is_binary(payment_intent.payment_method) ->
          payment_intent.payment_method

        # Or it might be expanded as an object
        is_map(payment_intent.payment_method) ->
          payment_intent.payment_method.id

        # Or get it from the expanded latest charge
        (first_charge =
           PaymentIntentHelpers.first_expanded_charge(payment_intent)) !=
            nil ->
          pm_on_charge =
            Map.get(first_charge, :payment_method) ||
              Map.get(first_charge, "payment_method")

          cond do
            is_binary(pm_on_charge) ->
              pm_on_charge

            is_map(pm_on_charge) &&
                (Map.has_key?(pm_on_charge, :id) ||
                   Map.has_key?(pm_on_charge, "id")) ->
              Map.get(pm_on_charge, :id) || Map.get(pm_on_charge, "id")

            true ->
              nil
          end

        true ->
          nil
      end

    case stripe_payment_method_id do
      nil ->
        Ysc.Logging.info("No payment method found in payment intent",
          payment_intent_id: payment_intent.id
        )

        nil

      pm_id when is_binary(pm_id) ->
        # Retrieve the full payment method from Stripe
        case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
               stripe_payment_method_module().retrieve(pm_id)
             end) do
          {:ok, stripe_payment_method} ->
            # Get the user to sync the payment method
            user = Ysc.Accounts.get_user!(user_id)

            # Sync the payment method to our database
            case Ysc.Payments.sync_payment_method_from_stripe(
                   user,
                   stripe_payment_method
                 ) do
              {:ok, payment_method} ->
                Ysc.Logging.info(
                  "Successfully synced payment method for booking payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: pm_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Ysc.Logging.warning(
                  "Failed to sync payment method for booking payment",
                  stripe_payment_method_id: pm_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Ysc.Logging.warning("Failed to retrieve payment method from Stripe",
              payment_method_id: pm_id,
              payment_intent_id: payment_intent.id,
              error: error.message
            )

            nil
        end
    end
  end

  # Load receipt data asynchronously after WebSocket connection
  defp load_receipt_data_async(socket, booking) do
    start_async(socket, :load_receipt_data, fn ->
      load_receipt_data(booking)
    end)
  end

  # Load all secondary receipt data in one function to minimize context switches
  defp load_receipt_data(booking) do
    payment_summary = get_booking_payment_summary(booking)
    payment = payment_summary.latest

    # Get refund info - pass payment to avoid duplicate query
    refund_info =
      get_refund_info_with_payment(booking, payment, payment_summary.total_paid)

    # Get door code if booking is within 48 hours of check-in or currently active
    {door_code, show_door_code} =
      if booking.status == :canceled do
        {nil, false}
      else
        get_door_code_for_booking(booking)
      end

    # Get refund data for cancelled bookings
    refund_data = get_refund_data_for_booking(booking, payment)

    payment_method_summary =
      if payment do
        build_payment_method_summary(payment)
      else
        %{description: nil, logo_path: nil}
      end

    Map.merge(payment_summary, %{
      refund_info: refund_info,
      door_code: door_code,
      show_door_code: show_door_code,
      refund_data: refund_data,
      payment_method_description: payment_method_summary.description,
      payment_method_logo: payment_method_summary.logo_path
    })
  end

  @impl true
  def handle_async(:load_receipt_data, {:ok, results}, socket) do
    {:noreply,
     socket
     |> assign(:payment, results.latest)
     |> assign(:booking_payments, results.payments)
     |> assign(:booking_payment_entries, results.payment_entries)
     |> assign(:total_paid_amount, results.total_paid)
     |> assign(:multiple_payments?, results.multiple_payments?)
     |> assign(:refund_info, results.refund_info)
     |> assign(:door_code, results.door_code)
     |> assign(:show_door_code, results.show_door_code)
     |> assign(:refund_data, results.refund_data)
     |> assign(:payment_method_description, results.payment_method_description)
     |> assign(:payment_method_logo, results.payment_method_logo)
     |> assign(:async_data_loaded, true)}
  end

  def handle_async(:load_receipt_data, {:exit, reason}, socket) do
    Ysc.Logging.warning("Failed to load receipt data async: #{inspect(reason)}")
    {:noreply, assign(socket, :async_data_loaded, true)}
  end

  defp get_booking_payment_summary(booking) do
    entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: a in Ysc.Ledgers.LedgerAccount,
        on: e.account_id == a.id,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        where: e.debit_credit == "debit",
        where: a.name == "stripe_account",
        where: not is_nil(e.payment_id),
        preload: [payment: :payment_method],
        order_by: [asc: e.inserted_at]
      )
      |> Repo.all()

    payments =
      entries
      |> Enum.map(& &1.payment)
      |> Enum.reject(&is_nil/1)
      |> dedupe_payments_chronologically()

    total_paid = sum_ledger_entry_amounts(entries, booking)

    latest = List.last(payments)

    payment_entries = build_payment_entries(payments)

    %{
      payments: payments,
      payment_entries: payment_entries,
      latest: latest,
      total_paid: total_paid,
      multiple_payments?: length(payments) > 1
    }
  end

  defp sum_ledger_entry_amounts(entries, booking) do
    case entries do
      [] ->
        booking.total_price

      entries ->
        Enum.reduce(entries, Money.new(0, :USD), fn entry, acc ->
          case Money.add(acc, entry.amount) do
            {:ok, sum} -> sum
            {:error, _} -> acc
          end
        end)
    end
  end

  defp dedupe_payments_chronologically(payments) do
    payments
    |> Enum.reduce(%{}, fn payment, acc ->
      Map.put(acc, payment.id, payment)
    end)
    |> Map.values()
    |> Enum.sort_by(
      fn payment ->
        payment.payment_date || payment.inserted_at || ~U[1970-01-01 00:00:00Z]
      end,
      DateTime
    )
  end

  defp build_payment_entries(payments) do
    Enum.map(payments, fn payment ->
      summary = build_payment_method_summary(payment)

      %{
        payment: payment,
        method_description: summary.description,
        method_logo: summary.logo_path
      }
    end)
  end

  defp receipt_total_paid_amount(assigns) do
    cond do
      assigns.multiple_payments? && assigns.total_paid_amount ->
        assigns.total_paid_amount

      assigns.payment ->
        assigns.payment.amount

      true ->
        nil
    end
  end

  defp buyout_line_amount(
         %{price_per_night: price_per_night, nights: nights},
         _booking
       )
       when not is_nil(price_per_night) and is_integer(nights) and nights > 0 do
    Money.mult!(price_per_night, nights)
  end

  defp buyout_line_amount(_price_breakdown, booking) do
    booking.subtotal_price || booking.total_price
  end

  defp parse_pricing_items(nil), do: nil

  defp parse_pricing_items(pricing_items) when is_map(pricing_items) do
    case Map.get(pricing_items, "type") do
      "buyout" ->
        %{
          nights: Map.get(pricing_items, "nights"),
          price_per_night:
            parse_money_from_map(Map.get(pricing_items, "price_per_night"))
        }

      "per_guest" ->
        %{
          nights: Map.get(pricing_items, "nights"),
          guests_count: Map.get(pricing_items, "guests_count"),
          price_per_guest_per_night:
            parse_money_from_map(
              Map.get(pricing_items, "price_per_guest_per_night")
            )
        }

      "room" ->
        # For room bookings, extract breakdown from the first room or aggregate
        rooms = Map.get(pricing_items, "rooms", [])
        nights = Map.get(pricing_items, "nights")
        guests_count = Map.get(pricing_items, "guests_count")
        children_count = Map.get(pricing_items, "children_count", 0)

        # If there are room items, extract breakdown from first room
        # Otherwise use top-level fields
        breakdown =
          if rooms != [] do
            first_room = List.first(rooms)

            base_breakdown = %{
              nights: nights,
              guests_count: guests_count,
              children_count: children_count
            }

            # Extract breakdown fields if they exist (base, children, etc.)
            breakdown_fields =
              first_room
              |> Map.drop([
                "type",
                "room_id",
                "room_name",
                "nights",
                "guests_count",
                "children_count",
                "total"
              ])
              |> Enum.map(fn {key, value} ->
                # Convert money maps to Money structs, keep other values as-is
                parsed_value =
                  if is_map(value) && Map.has_key?(value, "amount") &&
                       Map.has_key?(value, "currency") do
                    parse_money_from_map(value)
                  else
                    value
                  end

                # Use existing atom if available, otherwise keep as string to prevent atom exhaustion
                atom_key =
                  try do
                    String.to_existing_atom(key)
                  rescue
                    ArgumentError -> key
                  end

                {atom_key, parsed_value}
              end)
              |> Enum.into(%{})

            Map.merge(base_breakdown, breakdown_fields)
          else
            %{
              nights: nights,
              guests_count: guests_count,
              children_count: children_count
            }
          end

        breakdown

      _ ->
        nil
    end
  end

  defp parse_pricing_items(_), do: nil

  # Helper to convert money map (with string amount) back to Money struct
  defp parse_money_from_map(nil), do: nil

  defp parse_money_from_map(%{
         "amount" => amount_str,
         "currency" => currency_str
       }) do
    try do
      amount = Decimal.new(amount_str)
      currency = String.to_existing_atom(currency_str)
      Money.new(currency, amount)
    rescue
      _ -> nil
    end
  end

  defp parse_money_from_map(_), do: nil

  defp build_payment_method_summary(payment) do
    summary = payment_method_summary_from_db(payment)

    if payment_method_summary_needs_stripe_enrichment?(summary, payment) do
      payment
      |> get_payment_method_from_stripe()
      |> merge_stripe_payment_summary(summary)
    else
      summary
    end
  end

  @dialyzer {:nowarn_function, merge_stripe_payment_summary: 2}
  defp merge_stripe_payment_summary(
         %{description: stripe_desc} = stripe_summary,
         summary
       ) do
    cond do
      stripe_desc in [nil, "Credit Card (Stripe)", "Credit Card"] ->
        summary

      payment_method_description_blank?(summary.description) ->
        apply_stripe_payment_summary(summary, stripe_summary)

      stripe_desc_has_card_mask?(stripe_desc) and
          not stripe_desc_has_card_mask?(summary.description) ->
        apply_stripe_payment_summary(summary, stripe_summary)

      true ->
        summary
    end
  end

  defp apply_stripe_payment_summary(summary, stripe_summary) do
    %{
      summary
      | description: stripe_summary.description,
        logo_path: stripe_summary.logo_path || summary.logo_path
    }
  end

  defp payment_method_description_blank?(desc),
    do: desc in [nil, ""]

  defp stripe_desc_has_card_mask?(desc) when is_binary(desc),
    do: String.contains?(desc, "****")

  defp stripe_desc_has_card_mask?(_), do: false

  defp payment_method_summary_from_db(payment) do
    local_logo = PaymentMethodLogo.path_for_payment(payment)

    case payment.payment_method do
      nil ->
        %{description: nil, logo_path: local_logo}

      payment_method ->
        payment_type =
          case payment_method.type do
            nil -> nil
            type -> PaymentMethodFormatter.normalize_payment_type(type)
          end

        desc =
          case payment_type do
            type when type in [:card, :link] ->
              PaymentMethodFormatter.format_payment_method_for_receipt(
                type,
                payment_method.last_four,
                payment_method.display_brand
              )

            type when not is_nil(type) ->
              PaymentMethodFormatter.format_alternative_payment_method(
                type,
                payment_method
              )

            _ ->
              nil
          end

        %{description: desc, logo_path: local_logo}
    end
  end

  defp payment_method_summary_needs_stripe_enrichment?(
         %{description: desc},
         payment
       ) do
    pm = payment.payment_method

    cond do
      is_nil(pm) ->
        not is_nil(payment.external_payment_id)

      pm.type in [:link, :card] and is_nil(pm.last_four) ->
        true

      desc in ["Link", "Credit Card", "Bank Account", "Payment Method", nil] ->
        not is_nil(payment.external_payment_id)

      true ->
        false
    end
  end

  defp get_payment_method_from_stripe(payment) do
    get_payment_method_from_stripe_id(payment.external_payment_id)
  end

  defp get_payment_method_from_stripe_id(nil),
    do: %{description: "Credit Card (Stripe)", logo_path: nil}

  defp get_payment_method_from_stripe_id(payment_intent_id) do
    stripe_fallback = %{description: "Credit Card (Stripe)", logo_path: nil}
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "latest_charge"]
         }) do
      {:ok, payment_intent} ->
        {payment_method_type, last_four, display_brand} =
          PaymentMethodFormatter.payment_details_from_payment_intent(
            payment_intent,
            stripe_client
          )

        case payment_method_type do
          nil ->
            stripe_fallback

          type ->
            normalized = PaymentMethodFormatter.normalize_payment_type(type)

            %{
              description:
                PaymentMethodFormatter.format_payment_method_for_receipt(
                  normalized,
                  last_four,
                  display_brand
                ),
              logo_path:
                PaymentMethodLogo.path_for_stripe_summary(
                  normalized,
                  display_brand
                )
            }
        end

      {:error, _} ->
        stripe_fallback
    end
  end

  defp format_property_name(:tahoe), do: "Lake Tahoe Cabin"
  defp format_property_name(:clear_lake), do: "Clear Lake Cabin"
  defp format_property_name(_), do: "Unknown"

  defp get_property_thumbnail(property) do
    case property do
      :tahoe -> ~p"/images/tahoe/tahoe_cabin_main.webp"
      :clear_lake -> ~p"/images/clear_lake/clear_lake_dock.webp"
      _ -> ~p"/images/ysc_logo.webp"
    end
  end

  defp get_cabin_access_url(property) do
    case property do
      :tahoe ->
        ~p"/bookings/tahoe?tab=information&info_tab=general#door-code-access"

      :clear_lake ->
        ~p"/bookings/clear-lake?tab=information#door-code-access"

      _ ->
        ~p"/"
    end
  end

  defp get_cabin_rules_url(property) do
    case property do
      :tahoe -> ~p"/bookings/tahoe?tab=information&info_tab=rules#cabin-rules"
      :clear_lake -> ~p"/bookings/clear-lake?tab=information#cabin-rules"
      _ -> ~p"/"
    end
  end

  # Timezone-aware formatting functions
  defp format_date(%Date{} = date, _timezone) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_date(nil, _timezone), do: "—"
  defp format_date(_, _timezone), do: "—"

  @dialyzer {:nowarn_function, format_datetime: 2}
  defp format_datetime(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  defp format_payment_date(%DateTime{} = datetime, timezone) do
    format_datetime(datetime, timezone)
  end

  defp format_payment_date(%Date{} = date, timezone) do
    format_date(date, timezone)
  end

  defp get_cabin_master_email(property) do
    case property do
      :tahoe -> Ysc.EmailConfig.tahoe_email()
      :clear_lake -> Ysc.EmailConfig.clear_lake_email()
      _ -> "info@ysc.org"
    end
  end

  defp can_cancel_booking?(booking) do
    BookingActions.can_cancel_booking?(booking)
  end

  defp get_today_pst do
    BookingActions.get_today_pst()
  end

  # Accepts pre-fetched payment and total paid to avoid duplicate ledger queries
  defp get_refund_info_with_payment(booking, payment, total_paid) do
    if BookingActions.can_cancel_booking?(booking) do
      if BookingActions.refund_forfeited?(booking) do
        %{
          estimated_refund: Money.new(0, :USD),
          applied_rule: nil,
          policy_rules: [],
          modified: true
        }
      else
        get_refund_info_from_policy(booking, payment, total_paid)
      end
    else
      nil
    end
  end

  defp get_refund_info_from_policy(booking, payment, total_paid) do
    refund_opts =
      case total_paid do
        %Money{} = amount -> [original_amount: amount]
        _ -> []
      end

    case Bookings.calculate_refund(
           booking,
           BookingActions.get_today_pst(),
           refund_opts
         ) do
      {:ok, refund_amount, applied_rule} ->
        policy =
          Bookings.get_active_refund_policy(
            booking.property,
            booking.booking_mode
          )

        rules = if policy, do: policy.rules || [], else: []

        # If refund_amount is nil, it means full refund (no policy)
        # Use pre-fetched payment to get amount (avoiding duplicate query)
        estimated_refund =
          if is_nil(refund_amount) do
            if payment, do: payment.amount, else: nil
          else
            refund_amount
          end

        %{
          estimated_refund: estimated_refund,
          applied_rule: applied_rule,
          policy_rules: rules,
          modified: false
        }

      _ ->
        %{
          estimated_refund: nil,
          applied_rule: nil,
          policy_rules: [],
          modified: false
        }
    end
  end

  defp get_door_code_for_booking(booking) do
    is_active = booking_is_active?(booking)

    hours_until_checkin =
      if booking.checkin_date do
        checkin_datetime =
          DateTime.new!(
            booking.checkin_date,
            ~T[15:00:00],
            "America/Los_Angeles"
          )

        now = DateTime.utc_now()
        DateTime.diff(checkin_datetime, now, :hour)
      else
        nil
      end

    within_48_hours =
      hours_until_checkin != nil && hours_until_checkin >= 0 &&
        hours_until_checkin <= 48

    if is_active || within_48_hours do
      door_code = Bookings.get_active_door_code(booking.property)
      {door_code, true}
    else
      {nil, false}
    end
  end

  defp booking_checkout_in_past?(booking) do
    today = get_today_pst()

    booking.checkout_date != nil &&
      Date.compare(booking.checkout_date, today) == :lt
  end

  defp booking_is_active?(booking) do
    today = get_today_pst()

    if booking.checkin_date && booking.checkout_date do
      Date.compare(today, booking.checkin_date) != :lt &&
        Date.compare(today, booking.checkout_date) == :lt
    else
      false
    end
  end

  defp get_refund_data_for_booking(booking, payment) do
    if booking.status == :canceled && payment do
      # Get processed refunds for this payment
      processed_refunds =
        from(r in Refund,
          where: r.payment_id == ^payment.id,
          order_by: [desc: r.inserted_at]
        )
        |> Repo.all()

      # Get pending refund for this booking
      pending_refund =
        from(pr in PendingRefund,
          where: pr.booking_id == ^booking.id,
          where: pr.status == :pending,
          order_by: [desc: pr.inserted_at],
          limit: 1
        )
        |> Repo.one()

      # Calculate total refunded amount
      processed_total =
        Enum.reduce(processed_refunds, Money.new(0, :USD), fn refund, acc ->
          case Money.add(acc, refund.amount) do
            {:ok, sum} -> sum
            _ -> acc
          end
        end)

      pending_amount =
        if pending_refund do
          # Use admin_refund_amount if set, otherwise use policy_refund_amount
          pending_refund.admin_refund_amount ||
            pending_refund.policy_refund_amount
        else
          nil
        end

      total_refunded =
        if pending_amount do
          case Money.add(processed_total, pending_amount) do
            {:ok, total} -> total
            _ -> processed_total
          end
        else
          processed_total
        end

      %{
        processed_refunds: processed_refunds,
        pending_refund: pending_refund,
        total_refunded:
          if(Money.positive?(total_refunded), do: total_refunded, else: nil),
        has_pending_refund: not is_nil(pending_refund)
      }
    else
      nil
    end
  end

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end
end
