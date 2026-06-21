defmodule YscWeb.UserBookingDetailLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.Booking
  alias Ysc.EmailConfig
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias YscWeb.Authorization.Policy
  alias YscWeb.BookingActions
  import Ecto.Query

  @impl true
  def mount(%{"id" => booking_id}, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "You must be signed in to view this booking.",
         title: "Booking"
       )
       |> redirect(to: ~p"/")}
    else
      # SECURITY: Filter by user_id in the database query to prevent unauthorized access
      # This ensures we only fetch bookings that belong to the current user
      booking_query =
        from(b in Booking,
          where: b.id == ^booking_id and b.user_id == ^user.id,
          preload: [:user, rooms: :room_category]
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
          # Additional authorization check using LetMe policy
          case Policy.authorize(:booking_read, user, booking) do
            :ok ->
              connect_params =
                case get_connect_params(socket) do
                  nil -> %{}
                  v -> v
                end

              timezone =
                Map.get(connect_params, "timezone", "America/Los_Angeles")

              price_breakdown = calculate_price_breakdown(booking)
              can_cancel = BookingActions.can_cancel_booking?(booking)
              can_change = BookingActions.can_change_booking?(booking)

              socket =
                socket
                |> assign(:booking, booking)
                |> assign(:payment, nil)
                |> assign(:timezone, timezone)
                |> assign(:price_breakdown, price_breakdown)
                |> assign(:can_cancel, can_cancel)
                |> assign(:can_change, can_change)
                |> assign(:refund_info, nil)
                |> assign(:loading_booking_payment_details, !connected?(socket))
                |> assign(:show_cancel_modal, false)
                |> assign(:cancel_reason, "")
                |> assign(:page_title, "Booking Details")
                |> assign(
                  :meta_description,
                  "View the details of your cabin booking with Young Scandinavians Club."
                )

              socket =
                if connected?(socket) do
                  assign_booking_payment_details(socket, booking)
                else
                  socket
                end

              {:ok, socket}

            {:error, _} ->
              {:ok,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "You don't have permission to view this booking.",
                 title: "Booking"
               )
               |> redirect(to: ~p"/")}
          end
      end
    end
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
    user = socket.assigns.current_user

    # Verify authorization before cancellation
    case Policy.authorize(:booking_cancel, user, booking) do
      :ok ->
        case Bookings.cancel_booking(booking, Date.utc_today(), reason) do
          {:ok, updated_booking, refund_amount, refund_result} ->
            updated_booking =
              Repo.preload(updated_booking, [:user, rooms: :room_category])

            refund_info =
              get_refund_info(updated_booking, socket.assigns.payment)

            # Check if refund_result is a PendingRefund (partial refund) or LedgerTransaction (full refund)
            is_pending_refund =
              case refund_result do
                %Ysc.Bookings.PendingRefund{} -> true
                _ -> false
              end

            refund_message =
              if Money.positive?(refund_amount) do
                if is_pending_refund do
                  "Booking cancelled. We are reviewing your refund of #{MoneyHelper.format_money!(refund_amount)}. You will get an email when it is approved. No action is needed on your side."
                else
                  "Booking cancelled. A refund of #{MoneyHelper.format_money!(refund_amount)} will be processed."
                end
              else
                "Booking cancelled. No refund is available based on the cancellation policy."
              end

            {:noreply,
             socket
             |> assign(:booking, updated_booking)
             |> assign(:refund_info, refund_info)
             |> assign(:can_cancel, false)
             |> assign(:show_cancel_modal, false)
             |> YscWeb.Flash.put_toast(:info, refund_message, title: "Booking")}

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
             |> YscWeb.Flash.put_toast(:error, error_message, title: "Booking")}
        end

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_cancel_modal, false)
         |> YscWeb.Flash.put_toast(
           :error,
           "You don't have permission to cancel this booking.",
           title: "Booking"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-lg mx-auto px-4">
      <div class="max-w-xl mx-auto lg:mx-0">
        <div class="prose prose-zinc mb-6">
          <div class="flex items-start justify-between">
            <h1>Booking Details</h1>
            <div class="flex gap-2">
              <.button
                :if={@can_change}
                navigate={~p"/bookings/#{@booking.id}/change"}
                variant="outline"
                color="zinc"
                id="change-reservation-button"
              >
                <.icon name="hero-pencil-square" class="w-5 h-5 me-1 -mt-0.5" />
                Change Reservation
              </.button>
              <.button
                :if={@can_cancel}
                phx-click="show-cancel-modal"
                color="red"
              >
                <.icon name="hero-x-circle" class="w-5 h-5 me-1 -mt-0.5" />
                Cancel Booking
              </.button>
            </div>
          </div>
        </div>

        <div class="space-y-6">
          <!-- Cancellation Policy -->
          <%= if @refund_info && @can_cancel do %>
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-6">
              <h2 class="text-lg font-semibold text-blue-900 mb-3">
                Cancellation Policy
              </h2>
              <div class="text-sm text-blue-800 space-y-3">
                <%= if Map.get(@refund_info, :modified) do %>
                  <p class="font-medium text-amber-900">
                    This reservation was modified, so cancellation refunds no longer apply. You may still cancel, but you will not receive a refund.
                  </p>
                <% else %>
                  <%= if @refund_info.estimated_refund do %>
                    <p class="font-medium">
                      If you cancel today, you may be eligible for a refund of approximately <strong class="text-blue-900"><%= MoneyHelper.format_money!(@refund_info.estimated_refund) %></strong>.
                    </p>
                  <% else %>
                    <p>
                      Cancellation refunds are calculated based on how many days before check-in you cancel.
                    </p>
                  <% end %>
                  <%= if @refund_info.policy_rules && length(@refund_info.policy_rules) > 0 do %>
                    <div class="pt-3 border-t border-blue-200">
                      <p class="font-semibold mb-2">Cancellation Policy:</p>
                      <div class="text-sm text-blue-800 space-y-2">
                        {# Sort rules by days_before_checkin ascending (most restrictive first)
                        sorted_rules =
                          Enum.sort_by(
                            @refund_info.policy_rules,
                            fn rule -> rule.days_before_checkin end,
                            :asc
                          )

                        for rule <- sorted_rules do
                          refund_percentage =
                            rule.refund_percentage
                            |> Decimal.to_float()

                          cond do
                            refund_percentage == 0.0 ->
                              "Any reservation cancelled less than #{rule.days_before_checkin} days before your arrival date will not receive a refund."

                            refund_percentage > 0 and refund_percentage < 100.0 ->
                              refund_pct =
                                refund_percentage |> Float.round(0) |> trunc()

                              "Reservations cancelled less than #{rule.days_before_checkin} days before your arrival date receive a #{refund_pct}% refund."

                            true ->
                              "Reservations cancelled #{rule.days_before_checkin} or more days before your arrival date are eligible for a full refund."
                          end
                        end
                        |> Enum.map(fn text -> "<p>#{text}</p>" end)
                        |> Enum.join("")
                        |> raw()}
                      </div>
                    </div>
                  <% else %>
                    <div class="pt-3 border-t border-blue-200">
                      <p class="font-semibold mb-2">Cancellation Policy:</p>
                      <div class="text-sm text-blue-800">
                        <p>Full refund available for cancellations.</p>
                      </div>
                    </div>
                  <% end %>
                <% end %>

                <div class="pt-3 border-t border-blue-200 space-y-2">
                  <p class="font-medium">
                    Important: Even if the cancellation policy does not provide a refund, canceling your reservation will free up the room for other members to book.
                  </p>
                  <p>
                    If you need to cancel due to weather conditions or have other inquiries, please reach out to the cabin master at <.link
                      href={"mailto:#{get_cabin_master_email(@booking.property)}"}
                      class="text-blue-900 hover:text-blue-700 underline font-medium"
                    >
                    <%= get_cabin_master_email(@booking.property) %>
                  </.link>.
                  </p>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Booking Summary -->
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h2 class="text-xl font-semibold text-zinc-900 mb-4">
              Booking Summary
            </h2>

            <div class="space-y-4">
              <div>
                <div class="text-sm text-zinc-600 mb-0.5">Booking Reference</div>
                <.badge>
                  {@booking.reference_id}
                </.badge>
              </div>
              <!-- Status Badge -->
              <div>
                <div class="text-sm text-zinc-600 mb-0.5">Status</div>
                <.badge
                  type={
                    case @booking.status do
                      :complete -> "green"
                      :hold -> "yellow"
                      :canceled -> "red"
                      :refunded -> "red"
                      _ -> "gray"
                    end
                  }
                  class="text-sm"
                >
                  {booking_status_label(@booking.status)}
                </.badge>
                <%= if @booking.status == :hold do %>
                  <p class="mt-2 text-sm text-zinc-600">
                    Payment is still required to confirm this reservation.
                    <.link
                      navigate={~p"/bookings/checkout/#{@booking.id}"}
                      class="font-medium text-teal-600 hover:underline"
                    >
                      Complete checkout
                    </.link>
                  </p>
                <% end %>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Property</div>
                <div class="font-medium text-zinc-900">
                  {format_property_name(@booking.property)}
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-in</div>
                <div class="font-medium text-zinc-900">
                  {format_date(@booking.checkin_date, @timezone)}
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-out</div>
                <div class="font-medium text-zinc-900">
                  {format_date(@booking.checkout_date, @timezone)}
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Nights</div>
                <div class="font-medium text-zinc-900">
                  {Date.diff(@booking.checkout_date, @booking.checkin_date)}
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Guests</div>
                <div class="font-medium text-zinc-900">
                  {@booking.guests_count}
                  <%= if @booking.children_count > 0 do %>
                    ({@booking.children_count} children)
                  <% end %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Reservation type</div>
                <div class="font-medium text-zinc-900">
                  <%= if @booking.booking_mode == :buyout do %>
                    Entire cabin
                  <% else %>
                    <%= if @booking.booking_mode == :room do %>
                      Individual room(s)
                    <% else %>
                      Group booking (shared cabin)
                    <% end %>
                  <% end %>
                </div>
              </div>

              <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                <div>
                  <div class="text-sm text-zinc-600">
                    {if length(@booking.rooms) == 1, do: "Room", else: "Rooms"}
                  </div>
                  <div class="font-medium text-zinc-900">
                    {Enum.map_join(@booking.rooms, ", ", fn room -> room.name end)}
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          <.async_section_loader
            :if={@loading_booking_payment_details}
            id="booking-payment-loading"
            label="Loading payment details..."
          />
          <!-- Payment Summary -->
          <%= if @payment do %>
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <h2 class="text-xl font-semibold text-zinc-900 mb-4">
                Payment Summary
              </h2>

              <div class="space-y-3">
                <%= if @price_breakdown do %>
                  {render_price_breakdown(assigns)}
                <% end %>

                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Payment Method</span>
                  <span class="text-zinc-900">
                    {get_payment_method_description(@payment)}
                  </span>
                </div>

                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Payment Date</span>
                  <span class="text-zinc-900">
                    {format_datetime(
                      @payment.payment_date || @payment.inserted_at,
                      @timezone
                    )}
                  </span>
                </div>

                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Payment Status</span>
                  <span class="text-zinc-900">
                    <.badge type={
                      case @payment.status do
                        :completed -> "green"
                        :pending -> "yellow"
                        :refunded -> "red"
                        _ -> "gray"
                      end
                    }>
                      {String.capitalize(to_string(@payment.status))}
                    </.badge>
                  </span>
                </div>

                <div class="border-t border-zinc-200 pt-3">
                  <div class="flex justify-between items-center">
                    <span class="text-lg font-semibold text-zinc-900">
                      Total Paid
                    </span>
                    <span class="text-2xl font-bold text-zinc-900">
                      {MoneyHelper.format_money!(@payment.amount)}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <!-- Cancel Modal -->
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
                Cancel this reservation? This can't be undone.
              </p>

              <%= if Map.get(@refund_info, :modified) do %>
                <div class="bg-amber-50 border border-amber-200 rounded-md p-3">
                  <p class="text-sm text-amber-800">
                    This reservation was modified. You may cancel, but you will not receive a refund.
                  </p>
                </div>
              <% else %>
                <% estimated_refund = Map.get(@refund_info, :estimated_refund) %>
                <%= if match?(%Money{}, estimated_refund) && Money.positive?(estimated_refund) do %>
                  <div class="bg-blue-50 border border-blue-200 rounded-md p-3">
                    <p class="text-sm text-blue-800">
                      <strong>Estimated Refund:</strong>
                      {MoneyHelper.format_money!(estimated_refund)}
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
                  <.button
                    type="submit"
                    color="red"
                    phx-disable-with="Cancelling..."
                  >
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
      </div>
    </div>
    """
  end

  ## Helper Functions

  defp assign_booking_payment_details(socket, booking) do
    payment = get_booking_payment_info(booking)
    refund_info = get_refund_info(booking, payment)

    socket
    |> assign(:payment, payment)
    |> assign(:refund_info, refund_info)
    |> assign(:loading_booking_payment_details, false)
  end

  defp get_booking_payment_info(booking) do
    case Bookings.get_booking_payment(booking) do
      {:ok, payment} ->
        Repo.preload(payment, :payment_method)

      {:error, _} ->
        nil
    end
  end

  defp calculate_price_breakdown(booking) do
    if booking.pricing_items && is_map(booking.pricing_items) do
      booking.pricing_items
    else
      nil
    end
  end

  defp get_refund_info(booking, payment) do
    if BookingActions.can_cancel_booking?(booking) do
      if BookingActions.refund_forfeited?(booking) do
        %{
          estimated_refund: Money.new(0, :USD),
          applied_rule: nil,
          policy_rules: [],
          modified: true
        }
      else
        policy =
          Bookings.get_active_refund_policy(
            booking.property,
            booking.booking_mode
          )

        rules = if policy, do: policy.rules || [], else: []

        refund_opts =
          if payment && payment.amount do
            [original_amount: payment.amount]
          else
            []
          end

        case Bookings.calculate_refund(
               booking,
               YscWeb.BookingActions.get_today_pst(),
               refund_opts
             ) do
          {:ok, refund_amount, applied_rule} ->
            estimated_refund =
              if is_nil(refund_amount) and payment do
                payment.amount
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
    else
      nil
    end
  end

  defp format_property_name(:tahoe), do: "Lake Tahoe Cabin"
  defp format_property_name(:clear_lake), do: "Clear Lake Cabin"
  defp format_property_name(_), do: "Cabin"

  defp get_cabin_master_email(:tahoe), do: EmailConfig.tahoe_email()
  defp get_cabin_master_email(:clear_lake), do: EmailConfig.clear_lake_email()
  defp get_cabin_master_email(_), do: EmailConfig.contact_email()

  defp format_date(date, _timezone) do
    Timex.format!(date, "{WDfull}, {Mfull} {D}, {YYYY}")
  end

  defp format_datetime(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y at %I:%M %p %Z")
  end

  defp format_datetime(nil, _timezone), do: "—"
  defp format_datetime(_, _timezone), do: "—"

  defp get_payment_method_description(payment) do
    if Ecto.assoc_loaded?(payment.payment_method) && payment.payment_method do
      pm = payment.payment_method

      cond do
        pm.type == :card && pm.last_four ->
          "Card ending in #{pm.last_four}"

        pm.type == :bank_account && pm.last_four ->
          "Bank account ending in #{pm.last_four}"

        true ->
          "Payment method"
      end
    else
      "N/A"
    end
  end

  defp render_price_breakdown(assigns) do
    assigns = assign(assigns, :breakdown, assigns.price_breakdown)

    if assigns.breakdown && is_map(assigns.breakdown) do
      ~H"""
      <div class="space-y-2">
        <%= if @breakdown["type"] == "room" do %>
          <%= if @breakdown["rooms"] && is_list(@breakdown["rooms"]) do %>
            <%= for room_item <- @breakdown["rooms"] do %>
              <div class="flex justify-between text-sm">
                <span class="text-zinc-600">
                  {room_item["room_name"] || "Room"} ({room_item["nights"] ||
                    0} nights)
                </span>
                <span class="text-zinc-900">
                  {format_money_from_map(room_item["total"])}
                </span>
              </div>
            <% end %>
          <% else %>
            <div class="flex justify-between text-sm">
              <span class="text-zinc-600">
                Room Booking ({@breakdown["nights"] || 0} nights)
              </span>
              <span class="text-zinc-900">
                {format_money_from_map(@breakdown["total"])}
              </span>
            </div>
          <% end %>
        <% else %>
          <div class="flex justify-between text-sm">
            <span class="text-zinc-600">Booking Total</span>
            <span class="text-zinc-900">
              {format_money_from_map(@breakdown["total"])}
            </span>
          </div>
        <% end %>
      </div>
      """
    else
      ~H"""
      <div class="flex justify-between text-sm">
        <span class="text-zinc-600">Total</span>
        <span class="text-zinc-900">
          {MoneyHelper.format_money!(@booking.total_price)}
        </span>
      </div>
      """
    end
  end

  # Normalizes currency strings to atoms safely
  defp normalize_currency("USD"), do: :USD
  defp normalize_currency("EUR"), do: :EUR
  defp normalize_currency("GBP"), do: :GBP
  defp normalize_currency("CAD"), do: :CAD
  defp normalize_currency("AUD"), do: :AUD
  defp normalize_currency("JPY"), do: :JPY

  defp normalize_currency(currency) when is_binary(currency) do
    # Try to use existing atom, fallback to USD if not found
    String.to_existing_atom(currency)
  rescue
    ArgumentError -> :USD
  end

  defp normalize_currency(_), do: :USD

  defp format_money_from_map(money_map) when is_map(money_map) do
    amount = Map.get(money_map, "amount", "0")
    currency = Map.get(money_map, "currency", "USD")
    MoneyHelper.format_money!(Money.new(normalize_currency(currency), amount))
  end

  defp format_money_from_map(_), do: "N/A"

  defp booking_status_label(:hold), do: "Awaiting payment"
  defp booking_status_label(:complete), do: "Confirmed"
  defp booking_status_label(:canceled), do: "Cancelled"
  defp booking_status_label(:refunded), do: "Refunded"

  defp booking_status_label(status),
    do: status |> to_string() |> String.capitalize()
end
