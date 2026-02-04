defmodule YscWeb.UserBookingDetailLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.Booking
  alias Ysc.EmailConfig
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias YscWeb.Authorization.Policy
  import Ecto.Query

  @impl true
  def mount(%{"id" => booking_id}, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be signed in to view this booking.")
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
           |> put_flash(:error, "Booking not found.")
           |> redirect(to: ~p"/")}

        booking ->
          # Additional authorization check using LetMe policy
          case Policy.authorize(:booking_read, user, booking) do
            :ok ->
              # Get payment information
              payment = get_booking_payment_info(booking)

              # Get timezone from connect params
              connect_params =
                case get_connect_params(socket) do
                  nil -> %{}
                  v -> v
                end

              timezone =
                Map.get(connect_params, "timezone", "America/Los_Angeles")

              # Calculate price breakdown
              price_breakdown = calculate_price_breakdown(booking)

              # Check if booking can be cancelled
              can_cancel = can_cancel_booking?(booking)

              # Get refund policy info for cancellation
              refund_info = get_refund_info(booking)

              {:ok,
               socket
               |> assign(:booking, booking)
               |> assign(:payment, payment)
               |> assign(:timezone, timezone)
               |> assign(:price_breakdown, price_breakdown)
               |> assign(:can_cancel, can_cancel)
               |> assign(:refund_info, refund_info)
               |> assign(:show_cancel_modal, false)
               |> assign(:cancel_reason, "")
               |> assign(:page_title, "Booking Details")}

            {:error, _reason} ->
              {:ok,
               socket
               |> put_flash(
                 :error,
                 "You don't have permission to view this booking."
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

            refund_info = get_refund_info(updated_booking)

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
             |> assign(:booking, updated_booking)
             |> assign(:refund_info, refund_info)
             |> assign(:can_cancel, false)
             |> assign(:show_cancel_modal, false)
             |> put_flash(:info, refund_message)}

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

                _ ->
                  "Failed to cancel booking. Please try again or contact support."
              end

            {:noreply,
             socket
             |> assign(:show_cancel_modal, false)
             |> put_flash(:error, error_message)}
        end

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_cancel_modal, false)
         |> put_flash(
           :error,
           "You don't have permission to cancel this booking."
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
                :if={@can_cancel}
                phx-click="show-cancel-modal"
                color="red"
                data-confirm="Are you sure you want to cancel this booking?"
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
                      <%= # Sort rules by days_before_checkin ascending (most restrictive first)
                      sorted_rules =
                        Enum.sort_by(
                          @refund_info.policy_rules,
                          fn rule -> rule.days_before_checkin end,
                          :asc
                        )

                      # Calculate forfeiture percentage (100 - refund_percentage)
                      for rule <- sorted_rules do
                        forfeiture_percentage =
                          Decimal.sub(Decimal.new(100), rule.refund_percentage)
                          |> Decimal.to_float()

                        cond do
                          forfeiture_percentage == 100.0 ->
                            # 100% forfeiture (0% refund)
                            "Any reservation cancelled less than #{rule.days_before_checkin} days prior to date of arrival will result in forfeiture of 100% of the cost."

                          forfeiture_percentage > 0 ->
                            # Partial forfeiture
                            "Reservations cancelled less than #{rule.days_before_checkin} days prior to date of arrival are subject to forfeiture of #{forfeiture_percentage |> Float.round(0) |> trunc()}% of the cost."

                          true ->
                            # 0% forfeiture (100% refund) - shouldn't happen but handle it
                            "Reservations cancelled #{rule.days_before_checkin} or more days prior to date of arrival are eligible for a full refund."
                        end
                      end
                      |> Enum.map(fn text -> "<p>#{text}</p>" end)
                      |> Enum.join("")
                      |> raw() %>
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
                  <%= @booking.reference_id %>
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
                  <%= String.capitalize(to_string(@booking.status)) %>
                </.badge>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Property</div>
                <div class="font-medium text-zinc-900">
                  <%= format_property_name(@booking.property) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-in</div>
                <div class="font-medium text-zinc-900">
                  <%= format_date(@booking.checkin_date, @timezone) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-out</div>
                <div class="font-medium text-zinc-900">
                  <%= format_date(@booking.checkout_date, @timezone) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Nights</div>
                <div class="font-medium text-zinc-900">
                  <%= Date.diff(@booking.checkout_date, @booking.checkin_date) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Guests</div>
                <div class="font-medium text-zinc-900">
                  <%= @booking.guests_count %>
                  <%= if @booking.children_count > 0 do %>
                    (<%= @booking.children_count %> children)
                  <% end %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Booking Mode</div>
                <div class="font-medium text-zinc-900">
                  <%= if @booking.booking_mode == :buyout do %>
                    Full Buyout
                  <% else %>
                    <%= if @booking.booking_mode == :room do %>
                      Per Room
                    <% else %>
                      Per Guest
                    <% end %>
                  <% end %>
                </div>
              </div>

              <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                <div>
                  <div class="text-sm text-zinc-600">
                    <%= if length(@booking.rooms) == 1, do: "Room", else: "Rooms" %>
                  </div>
                  <div class="font-medium text-zinc-900">
                    <%= Enum.map_join(@booking.rooms, ", ", fn room -> room.name end) %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Payment Summary -->
          <%= if @payment do %>
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <h2 class="text-xl font-semibold text-zinc-900 mb-4">
                Payment Summary
              </h2>

              <div class="space-y-3">
                <%= if @price_breakdown do %>
                  <%= render_price_breakdown(assigns) %>
                <% end %>

                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Payment Method</span>
                  <span class="text-zinc-900">
                    <%= get_payment_method_description(@payment) %>
                  </span>
                </div>

                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Payment Date</span>
                  <span class="text-zinc-900">
                    <%= format_datetime(
                      @payment.payment_date || @payment.inserted_at,
                      @timezone
                    ) %>
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
                      <%= String.capitalize(to_string(@payment.status)) %>
                    </.badge>
                  </span>
                </div>

                <div class="border-t border-zinc-200 pt-3">
                  <div class="flex justify-between items-center">
                    <span class="text-lg font-semibold text-zinc-900">
                      Total Paid
                    </span>
                    <span class="text-2xl font-bold text-zinc-900">
                      <%= MoneyHelper.format_money!(@payment.amount) %>
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
            <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
              Cancel Booking
            </h2>

            <div class="space-y-4">
              <p class="text-zinc-600">
                Are you sure you want to cancel this booking? This action cannot be undone.
              </p>

              <%= if @refund_info && @refund_info.estimated_refund do %>
                <div class="bg-blue-50 border border-blue-200 rounded-md p-3">
                  <p class="text-sm text-blue-800">
                    <strong>Estimated Refund:</strong>
                    <%= MoneyHelper.format_money!(@refund_info.estimated_refund) %>
                  </p>
                </div>
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

  defp can_cancel_booking?(booking) do
    # Can cancel if booking is complete or hold, and check-in is in the future
    # OR if check-in is today (in PST) and it's before 3PM PST
    today_pst = get_today_pst()

    booking.status in [:complete, :hold] &&
      (Date.compare(booking.checkin_date, today_pst) == :gt ||
         (Date.compare(booking.checkin_date, today_pst) == :eq &&
            before_checkin_time_today?()))
  end

  defp get_today_pst do
    DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
  end

  defp before_checkin_time_today? do
    # Check if current time (in PST) is before 3PM (15:00)
    now_pst = DateTime.now!("America/Los_Angeles")
    today_pst = DateTime.to_date(now_pst)
    checkin_time = ~T[15:00:00]

    checkin_datetime_today =
      DateTime.new!(today_pst, checkin_time, "America/Los_Angeles")

    DateTime.compare(now_pst, checkin_datetime_today) == :lt
  end

  defp get_refund_info(booking) do
    if can_cancel_booking?(booking) do
      case Bookings.calculate_refund(booking, Date.utc_today()) do
        {:ok, refund_amount, applied_rule} ->
          policy =
            Bookings.get_active_refund_policy(
              booking.property,
              booking.booking_mode
            )

          rules = if policy, do: policy.rules || [], else: []

          %{
            estimated_refund: refund_amount,
            applied_rule: applied_rule,
            policy_rules: rules
          }

        _ ->
          %{estimated_refund: nil, applied_rule: nil, policy_rules: []}
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
                  <%= room_item["room_name"] || "Room" %> (<%= room_item["nights"] ||
                    0 %> nights)
                </span>
                <span class="text-zinc-900">
                  <%= format_money_from_map(room_item["total"]) %>
                </span>
              </div>
            <% end %>
          <% else %>
            <div class="flex justify-between text-sm">
              <span class="text-zinc-600">
                Room Booking (<%= @breakdown["nights"] || 0 %> nights)
              </span>
              <span class="text-zinc-900">
                <%= format_money_from_map(@breakdown["total"]) %>
              </span>
            </div>
          <% end %>
        <% else %>
          <div class="flex justify-between text-sm">
            <span class="text-zinc-600">Booking Total</span>
            <span class="text-zinc-900">
              <%= format_money_from_map(@breakdown["total"]) %>
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
          <%= MoneyHelper.format_money!(@booking.total_price) %>
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
end
