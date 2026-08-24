defmodule YscWeb.BookingCheckoutLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, Entitlements, SeasonCache}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias Ysc.Stripe.PaymentIntentHelpers
  alias YscWeb.BookingGuestForm
  alias YscWeb.BookingUserMessages
  import Ecto.Query
  import YscWeb.Components.BookingGuestInfoForm
  require Ysc.Logging

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
    user = socket.assigns.current_user
    timezone = get_timezone_from_connect_params(socket)

    case validate_user_signed_in(user) do
      :ok ->
        socket = assign_checkout_loading_shell(socket, booking_id, timezone)

        if connected?(socket) do
          case load_checkout(socket, booking_id, user, timezone) do
            {:ok, socket} ->
              schedule_expiration_check(socket)
              {:ok, socket}

            {:error, {:redirect, path, message}} ->
              {:ok,
               socket
               |> YscWeb.Flash.put_toast(:error, message, title: "Checkout")
               |> redirect(to: path)}
          end
        else
          {:ok, socket}
        end

      {:error, {:redirect, path, message}} ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(:error, message, title: "Checkout")
         |> redirect(to: path)}
    end
  end

  defp assign_checkout_loading_shell(socket, booking_id, timezone) do
    assign(socket,
      booking_id: booking_id,
      checkout_data_loaded?: false,
      booking: nil,
      total_price: nil,
      price_breakdown: nil,
      payment_intent: nil,
      payment_error: nil,
      show_payment_form: false,
      complimentary_checkout: false,
      is_expired: false,
      timezone: timezone,
      checkout_step: :payment,
      guest_info_form: nil,
      guest_info_errors: %{},
      family_members: [],
      other_family_members: [],
      guests_for_me: %{},
      selected_family_members_for_guests: %{},
      show_price_details: false,
      stripe_payment_element_ready: false,
      stripe_billing_details: "{}",
      page_title: "Booking Checkout",
      meta_description:
        "Complete your cabin booking with Young Scandinavians Club."
    )
  end

  defp schedule_expiration_check(socket) do
    if connected?(socket) do
      Process.send_after(self(), :check_booking_expiration, 5_000)
    end
  end

  defp get_timezone_from_connect_params(socket) do
    connect_params = get_connect_params(socket) || %{}
    Map.get(connect_params, "timezone", "America/Los_Angeles")
  end

  defp validate_user_signed_in(nil) do
    {:error,
     {:redirect, ~p"/", "You must be signed in to complete your booking."}}
  end

  defp validate_user_signed_in(_user), do: :ok

  defp load_checkout(socket, booking_id, user, timezone) do
    with :ok <- Bookings.ensure_user_may_book(user),
         {:ok, booking} <- load_booking(booking_id, user),
         :ok <- validate_booking_status(booking),
         :ok <- validate_booking_not_expired(booking) do
      initialize_checkout(socket, booking, user, timezone)
    else
      {:error, :application_pending_approval} ->
        {:error,
         {:redirect, ~p"/pending-review",
          YscWeb.BookingUserMessages.application_pending_approval_message()}}

      {:error, :membership_required} ->
        {:error,
         {:redirect, ~p"/users/membership",
          YscWeb.BookingUserMessages.membership_required_plain_message()}}

      {:error, {:redirect, _, _} = redirect} ->
        {:error, redirect}
    end
  end

  defp load_booking(booking_id, user) do
    # SECURITY: Filter by user_id in the database query to prevent unauthorized access
    # This ensures we only fetch bookings that belong to the current user
    booking_query =
      from(b in Booking,
        where: b.id == ^booking_id and b.user_id == ^user.id,
        preload: [:user, :booking_guests, rooms: :room_category]
      )

    case Repo.one(booking_query) do
      nil ->
        {:error,
         {:redirect, ~p"/", YscWeb.BookingUserMessages.checkout_not_found()}}

      booking ->
        {:ok, booking}
    end
  end

  defp validate_booking_status(booking) do
    if booking.status == :hold do
      :ok
    else
      {:error,
       {:redirect, get_property_redirect_path(booking.property),
        "This booking is no longer available for payment."}}
    end
  end

  defp validate_booking_not_expired(booking) do
    if booking_expired?(booking) do
      {:error,
       {:redirect, get_property_redirect_path(booking.property),
        BookingUserMessages.checkout_hold_expired()}}
    else
      :ok
    end
  end

  defp initialize_checkout(socket, booking, user, timezone) do
    case calculate_booking_price(booking) do
      {:ok, total_price, price_breakdown} ->
        setup_checkout_socket(
          socket,
          booking,
          user,
          total_price,
          price_breakdown,
          timezone
        )

      {:error, reason}
      when reason in [
             :entitlement_no_longer_valid,
             :entitlement_not_eligible_for_booking
           ] ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Your member discount or free night is no longer valid for this booking, so we can't finish checkout at this price. Please start a new booking from the cabin page — your previous dates may no longer be available.",
           title: "Checkout"
         )
         |> redirect(to: get_property_redirect_path(booking.property))}

      {:error, reason} ->
        Ysc.Logging.error("[BookingCheckout] Failed to calculate booking price",
          reason: inspect(reason),
          booking_id: booking.id
        )

        {:ok,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           YscWeb.BookingUserMessages.checkout_pricing_load_failed(),
           title: "Checkout"
         )
         |> redirect(to: get_property_redirect_path(booking.property))}
    end
  end

  defp setup_checkout_socket(
         socket,
         booking,
         user,
         total_price,
         price_breakdown,
         timezone
       ) do
    booking =
      case sync_checkout_hold_pricing(booking, total_price, price_breakdown) do
        {:ok, updated_booking} ->
          updated_booking

        {:error, reason} ->
          Ysc.Logging.warning(
            "[BookingCheckout] Failed to sync recalculated hold pricing",
            booking_id: booking.id,
            reason: inspect(reason)
          )

          booking
      end

    is_expired = booking_expired?(booking)
    {checkout_step, guest_info_form} = determine_checkout_step(booking, user)
    {family_members, other_family_members} = load_family_members(user)

    socket =
      assign(socket,
        booking: booking,
        total_price: total_price,
        price_breakdown: price_breakdown,
        payment_intent: nil,
        payment_error: nil,
        show_payment_form: false,
        complimentary_checkout: Money.zero?(total_price),
        is_expired: is_expired,
        timezone: timezone,
        checkout_step: checkout_step,
        guest_info_form: guest_info_form,
        guest_info_errors: %{},
        family_members: family_members,
        other_family_members: other_family_members,
        guests_for_me: %{},
        selected_family_members_for_guests: %{},
        show_price_details: false,
        stripe_payment_element_ready: false,
        stripe_billing_details:
          Ysc.Customers.payment_element_default_values_json(user),
        checkout_data_loaded?: true,
        page_title: "Booking Checkout",
        meta_description:
          "Complete your cabin booking with Young Scandinavians Club."
      )

    if is_expired do
      {:ok,
       assign(socket,
         payment_error: BookingUserMessages.checkout_hold_expired()
       )}
    else
      create_payment_intent_if_needed(
        socket,
        booking,
        total_price,
        user,
        checkout_step
      )
    end
  end

  defp determine_checkout_step(booking, user) do
    if booking.booking_mode == :room do
      existing_guests = booking.booking_guests || []

      if existing_guests != [] do
        {:payment, nil}
      else
        form = initialize_guest_forms(booking, user)
        {:guest_info, form}
      end
    else
      {:payment, nil}
    end
  end

  defp load_family_members(user) do
    family_members = Ysc.Accounts.get_family_group(user)

    other_family_members =
      Enum.reject(family_members, fn member -> member.id == user.id end)

    {family_members, other_family_members}
  end

  defp create_payment_intent_if_needed(
         socket,
         booking,
         total_price,
         user,
         :payment
       ) do
    if Money.zero?(total_price) do
      {:ok,
       assign(socket,
         payment_intent: nil,
         show_payment_form: false
       )}
    else
      case create_payment_intent(booking, total_price, user) do
        {:ok, payment_intent} ->
          {booking, payment_intent} =
            persist_checkout_payment_intent(booking, payment_intent)

          {:ok,
           assign(socket,
             booking: booking,
             payment_intent: payment_intent,
             show_payment_form: true,
             stripe_payment_element_ready: false
           )}

        {:error, message} ->
          {:ok,
           assign(socket,
             payment_error: message
           )}
      end
    end
  end

  defp create_payment_intent_if_needed(
         socket,
         _booking,
         _total_price,
         _user,
         _checkout_step
       ) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4">
      <div class="prose prose-zinc mb-8">
        <h1>Complete Your Booking</h1>
      </div>

      <div
        :if={!@checkout_data_loaded?}
        id="checkout-loading"
        class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start"
        role="status"
        aria-live="polite"
      >
        <span class="sr-only">Loading checkout details…</span>
        <div class="lg:col-span-2 space-y-6">
          <div class="flex items-center gap-6 p-6 bg-zinc-50 rounded-lg border border-zinc-200">
            <.skeleton_block class="h-20 w-20 rounded-lg shrink-0" />
            <div class="flex-1 space-y-2">
              <.skeleton_block class="h-6 w-1/2 rounded" />
              <.skeleton_block class="h-4 w-2/3 rounded" />
              <.skeleton_block class="h-4 w-1/3 rounded" />
            </div>
          </div>
          <div class="bg-white rounded-lg border border-zinc-200 p-8 space-y-4">
            <.skeleton_block class="h-6 w-40 rounded" />
            <.payment_element_loading />
          </div>
        </div>
        <aside class="space-y-6">
          <.skeleton_block class="h-20 w-full rounded-lg" />
          <div class="bg-white rounded-lg border border-zinc-200 p-6 space-y-3">
            <.skeleton_block class="h-4 w-1/3 rounded" />
            <.skeleton_block :for={_ <- 1..3} class="h-4 w-full rounded" />
          </div>
        </aside>
      </div>

      <div
        :if={@checkout_data_loaded?}
        class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start"
      >
        <!-- Left Column: Booking Summary and Payment -->
        <div class="lg:col-span-2 space-y-6">
          <!-- Visual Booking Summary -->
          <div class="flex items-center gap-6 p-6 bg-zinc-50 rounded-lg border border-zinc-200">
            <div class="h-20 w-20 bg-zinc-200 rounded-lg overflow-hidden flex-shrink-0">
              <img
                src={get_property_thumbnail(@booking.property)}
                alt={atom_to_readable(@booking.property) <> " Cabin"}
                class="object-cover h-full w-full"
              />
            </div>
            <div class="flex-1">
              <h2 class="text-2xl font-bold text-zinc-900">
                {atom_to_readable(@booking.property)} Cabin
              </h2>
              <p class="text-zinc-500 mt-1">
                {format_date_short(@booking.checkin_date, @timezone)} — {format_date_short(
                  @booking.checkout_date,
                  @timezone
                )}, {Calendar.strftime(@booking.checkout_date, "%Y")} ({Date.diff(
                  @booking.checkout_date,
                  @booking.checkin_date
                )} {if Date.diff(
                         @booking.checkout_date,
                         @booking.checkin_date
                       ) == 1,
                       do: "night",
                       else: "nights"})
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm">
                <span class="text-zinc-600">
                  {@booking.guests_count} {if @booking.guests_count == 1,
                    do: "adult",
                    else: "adults"}
                  <%= if @booking.children_count && @booking.children_count > 0 do %>
                    , {@booking.children_count} {if @booking.children_count ==
                                                      1,
                                                    do: "child",
                                                    else: "children"}
                  <% end %>
                </span>
                <%= if @booking.booking_mode == :room && Ecto.assoc_loaded?(@booking.rooms) &&
                      length(@booking.rooms) > 0 do %>
                  <span class="text-zinc-400">•</span>
                  <span class="text-zinc-600">
                    {Enum.map(@booking.rooms, & &1.name) |> Enum.join(", ")}
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          <.booking_guest_info_form
            :if={@checkout_step == :guest_info}
            id="guest-info-form"
            booking={@booking}
            guest_info_form={@guest_info_form}
            guest_info_errors={@guest_info_errors}
            other_family_members={@other_family_members}
            selected_family_members_for_guests={@selected_family_members_for_guests}
            current_user={@current_user}
            intro_text={checkout_guest_info_intro(@booking)}
            submit_label={checkout_guest_info_submit_label(@complimentary_checkout)}
          >
            <:actions>
              <button
                type="button"
                phx-click="cancel-booking"
                phx-disable-with="Cancelling..."
                phx-confirm={leave_checkout_confirm()}
                class="px-6 py-3.5 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-300 rounded-lg hover:bg-zinc-50 transition-colors"
              >
                Cancel
              </button>
            </:actions>
          </.booking_guest_info_form>
          <!-- Payment Section -->
          <div
            :if={@checkout_step == :payment}
            class="bg-white rounded-lg border border-zinc-200 p-8 shadow-sm"
          >
            <h2 class="text-xl font-bold mb-6">
              <%= if @complimentary_checkout do %>
                Confirm your booking
              <% else %>
                Secure Payment
              <% end %>
            </h2>
            <!-- Payment Error -->
            <div
              :if={@payment_error}
              id="checkout-payment-error"
              class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
            >
              <p class="text-sm text-red-800">{@payment_error}</p>
            </div>
            <!-- Complimentary checkout (entitlement / discount covers full amount) -->
            <div :if={@complimentary_checkout && !@is_expired}>
              <p class="text-sm text-zinc-600 mb-6">
                No payment is required. Your total after discounts is {MoneyHelper.format_money!(
                  @total_price
                )}.
                Click below to confirm your booking and secure these dates.
              </p>
              <div class="pt-2 border-t border-zinc-100 space-y-4">
                <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-4">
                  <button
                    type="button"
                    phx-click="cancel-booking"
                    phx-disable-with="Cancelling..."
                    phx-confirm={leave_checkout_confirm()}
                    class="w-full sm:w-auto px-6 py-3.5 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-300 rounded-lg hover:bg-zinc-50 transition-colors"
                  >
                    Cancel
                  </button>
                  <.button
                    id="confirm-complimentary-booking"
                    type="button"
                    phx-click="confirm-complimentary-booking"
                    phx-disable-with="Confirming..."
                    class="w-full sm:w-auto text-lg py-3.5"
                    disabled={@is_expired}
                  >
                    <.icon name="hero-check-circle" class="w-5 h-5" />
                    <span class="text-lg font-semibold">Confirm booking</span>
                  </.button>
                </div>
              </div>
            </div>
            <!-- Payment Form -->
            <div :if={@show_payment_form && @payment_intent && !@is_expired}>
              <div
                id="stripe-payment-container"
                phx-hook="StripeElements"
                data-client-secret={@payment_intent.client_secret}
                data-booking-id={@booking.id}
                data-billing-details={@stripe_billing_details}
              >
                <.payment_element_loading :if={!@stripe_payment_element_ready} />
                <%!-- phx-update="ignore" keeps LiveView from re-applying hidden on each assign --%>
                <div
                  id="payment-element"
                  phx-update="ignore"
                  class="mb-6 min-h-[12rem]"
                >
                </div>
                <div id="payment-message" class="hidden mt-4"></div>
              </div>

              <div class="pt-6 border-t border-zinc-100 space-y-4">
                <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-4">
                  <button
                    type="button"
                    phx-click="cancel-booking"
                    phx-disable-with="Cancelling..."
                    phx-confirm={leave_checkout_confirm()}
                    class="w-full sm:w-auto px-6 py-3.5 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-300 rounded-lg hover:bg-zinc-50 transition-colors"
                  >
                    Cancel
                  </button>
                  <.button
                    id="submit-payment"
                    type="button"
                    class="w-full sm:w-auto text-lg py-3.5"
                    disabled={!@stripe_payment_element_ready}
                  >
                    <.icon name="hero-lock-closed" class="w-5 h-5" />
                    <span class="text-lg font-semibold">
                      Pay {MoneyHelper.format_money!(@total_price)} Securely
                    </span>
                  </.button>
                </div>
              </div>
            </div>
            <!-- Expired Booking Message -->
            <div
              :if={assigns[:is_expired] && @is_expired}
              class="p-6 bg-red-50 border border-red-200 rounded-lg"
            >
              <p class="text-sm font-semibold text-red-800 mb-2">
                Your hold on these dates expired
              </p>
              <p class="text-sm text-red-700 mb-4">
                {BookingUserMessages.checkout_hold_expired()}
              </p>
              <a
                href={get_property_redirect_path(@booking.property)}
                class="inline-block text-sm font-medium text-red-800 hover:text-red-900 underline"
              >
                Start a new booking
              </a>
            </div>
          </div>
          <!-- Right Column: Countdown Timer and Price Details -->
        </div>
        <aside class="space-y-6 lg:sticky lg:top-24">
          <!-- Hold Expiry Countdown -->
          <div
            :if={
              @booking.hold_expires_at && (!assigns[:is_expired] || !@is_expired)
            }
            class={[
              "border rounded-lg p-4",
              if(remaining_minutes(@booking.hold_expires_at) < 5,
                do: "bg-rose-50 border-rose-200",
                else: "bg-blue-50 border-blue-200"
              )
            ]}
            id="hold-countdown-container"
            phx-hook="Countdown"
            data-expires-at={DateTime.to_iso8601(@booking.hold_expires_at)}
            data-countdown-target="#hold-countdown"
            data-color-container
          >
            <div class={[
              "flex items-center gap-2 mb-1",
              if(remaining_minutes(@booking.hold_expires_at) < 5,
                do: "text-rose-800",
                else: "text-blue-800"
              )
            ]}>
              <.icon name="hero-clock" class="w-4 h-4" />
              <span class="text-xs font-semibold uppercase tracking-wide">
                Time remaining
              </span>
            </div>
            <p class={[
              "text-base leading-relaxed",
              if(remaining_minutes(@booking.hold_expires_at) < 5,
                do: "text-rose-700",
                else: "text-blue-700"
              )
            ]}>
              These dates are held for
              <span
                class="font-bold tabular-nums"
                id="hold-countdown"
              >
                {calculate_remaining_time(@booking.hold_expires_at)}
              </span>
              — not confirmed yet. Pay now to complete your booking. If the timer runs out, the dates go back on the calendar and you'll need to book again.
            </p>
          </div>
          <!-- Price Details -->
          <div class="bg-zinc-900 text-white rounded-lg p-6 shadow-xl">
            <%!-- Mobile Collapsible Header --%>
            <button
              type="button"
              class="lg:hidden w-full flex items-center justify-between mb-4"
              phx-click="toggle-price-details"
              aria-expanded={
                if assigns[:show_price_details], do: "true", else: "false"
              }
            >
              <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest">
                Price Details
              </h3>
              <.icon
                name={
                  if assigns[:show_price_details],
                    do: "hero-chevron-up",
                    else: "hero-chevron-down"
                }
                class="w-5 h-5 text-zinc-400"
              />
            </button>
            <%!-- Desktop Header --%>
            <h3 class="hidden lg:block text-sm font-bold text-zinc-400 uppercase tracking-widest mb-4">
              Price Details
            </h3>
            <div class={[
              "space-y-3",
              if(assigns[:show_price_details] == false, do: "hidden lg:block")
            ]}>
              <%= if @price_breakdown do %>
                {render_price_breakdown_sidebar(assigns)}
              <% end %>
              <div class="pt-4 border-t border-zinc-700 flex justify-between items-baseline">
                <span class="text-lg font-bold">Total</span>
                <span class="text-3xl font-black text-blue-400">
                  {MoneyHelper.format_money!(@total_price)}
                </span>
              </div>
            </div>
          </div>
          <!-- What Happens Next -->
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h3
              id="checkout-next-steps-heading"
              class="text-lg font-bold text-zinc-900 mb-4"
            >
              What Happens Next?
            </h3>
            <.step_list
              id="checkout-next-steps"
              aria-labelledby="checkout-next-steps-heading"
            >
              <:step :if={@checkout_step == :guest_info}>
                {BookingUserMessages.checkout_guest_info_step_enter_guests()}
              </:step>
              <:step :if={@checkout_step == :guest_info}>
                <%= if @complimentary_checkout do %>
                  {BookingUserMessages.checkout_guest_info_step_continue_complimentary()}
                <% else %>
                  {BookingUserMessages.checkout_guest_info_step_continue_payment()}
                <% end %>
              </:step>
              <:step :if={@checkout_step != :guest_info}>
                <%= if @complimentary_checkout do %>
                  {BookingUserMessages.checkout_payment_step_confirm_complimentary()}
                <% else %>
                  {BookingUserMessages.checkout_payment_step_pay()}
                <% end %>
              </:step>
              <:step>
                {BookingUserMessages.checkout_confirmation_email_step()}
              </:step>
              <:step>
                {BookingUserMessages.checkout_cabin_access_step()}
              </:step>
              <:step :if={@checkout_step != :guest_info}>
                {BookingUserMessages.checkout_manage_booking_step()}
              </:step>
            </.step_list>
          </div>
        </aside>
      </div>
      <%!-- Mobile Sticky Footer --%>
      <div
        :if={@checkout_step == :guest_info}
        class="lg:hidden fixed bottom-0 left-0 right-0 bg-white border-t border-zinc-200 shadow-lg z-50 p-4"
      >
        <div class="max-w-screen-xl mx-auto flex items-center justify-between gap-4">
          <div>
            <p class="text-xs text-zinc-500 uppercase tracking-wide">Total</p>
            <p class="text-2xl font-black text-blue-600">
              {MoneyHelper.format_money!(@total_price)}
            </p>
          </div>
          <.button
            type="submit"
            form="guest-info-form"
            phx-disable-with="Processing..."
            class="flex-1"
            disabled={
              !BookingGuestForm.all_guests_valid?(@guest_info_form, @booking)
            }
          >
            <span class="font-semibold">
              <%= if @complimentary_checkout do %>
                Continue to confirmation
              <% else %>
                Continue to Payment
              <% end %>
            </span>
            <.icon name="hero-arrow-right" class="w-5 h-5" />
          </.button>
        </div>
      </div>
      <%!-- Spacer for mobile footer --%>
      <div :if={@checkout_step == :guest_info} class="lg:hidden h-24"></div>
    </div>
    """
  end

  @impl true
  def handle_event("validate-guest-info", %{"guests" => guest_params}, socket) do
    require Ysc.Logging
    Ysc.Logging.debug("[validate-guest-info] Event received")

    Ysc.Logging.debug(
      "[validate-guest-info] Received guest_params: #{inspect(guest_params)}"
    )

    # Merge family member selections into guest_params before validation
    selected_family_members =
      socket.assigns.selected_family_members_for_guests || %{}

    other_family_members = socket.assigns.other_family_members || []

    Ysc.Logging.debug(
      "[validate-guest-info] selected_family_members: #{inspect(selected_family_members)}"
    )

    Ysc.Logging.debug(
      "[validate-guest-info] other_family_members count: #{length(other_family_members)}"
    )

    # Update guest_params with family member data if selected
    updated_guest_params =
      guest_params
      |> Enum.map(fn {index_str, guest_data} ->
        selected_family_member_id = Map.get(selected_family_members, index_str)

        updated_guest_data =
          if selected_family_member_id do
            # Use selected family member's details
            selected_family_member =
              Enum.find(other_family_members, fn u ->
                to_string(u.id) == to_string(selected_family_member_id)
              end)

            if selected_family_member do
              Map.merge(guest_data, %{
                "first_name" => selected_family_member.first_name || "",
                "last_name" => selected_family_member.last_name || ""
              })
            else
              guest_data
            end
          else
            # Use form data as-is
            guest_data
          end

        {index_str, updated_guest_data}
      end)
      |> Map.new()

    Ysc.Logging.debug(
      "[validate-guest-info] updated_guest_params after family member merge: #{inspect(updated_guest_params)}"
    )

    # Find and include the booking user entry from form source (it's not in the submitted params)
    guest_info_form =
      socket.assigns.guest_info_form || to_form(%{}, as: "guests")

    Ysc.Logging.debug(
      "[validate-guest-info] guest_info_form.source keys: #{inspect(Map.keys(guest_info_form.source))}"
    )

    Ysc.Logging.debug(
      "[validate-guest-info] guest_info_form.source: #{inspect(guest_info_form.source)}"
    )

    # Merge all entries from form source, then update with submitted params
    # When a user types in a field, only that field's data is submitted via phx-change,
    # so we need to merge all entries from the form source to preserve all guest data
    # We need to do a deep merge to preserve nested fields within each guest entry
    # IMPORTANT: Normalize boolean values from strings to actual booleans
    updated_guest_params =
      guest_info_form.source
      |> Map.merge(updated_guest_params, fn _key, source_data, submitted_data ->
        # Deep merge: merge the nested maps so we preserve all fields
        merged = Map.merge(source_data, submitted_data)

        # Normalize boolean fields from strings to actual booleans
        # Form submissions send "true"/"false" as strings, but we need actual booleans
        merged
        |> Map.update("is_child", false, fn
          "true" -> true
          "false" -> false
          true -> true
          false -> false
          val -> val
        end)
        |> Map.update("is_booking_user", false, fn
          "true" -> true
          "false" -> false
          true -> true
          false -> false
          val -> val
        end)
        |> Map.update("order_index", 0, fn
          val when is_binary(val) -> String.to_integer(val)
          val when is_integer(val) -> val
          val -> val
        end)
      end)

    Ysc.Logging.debug(
      "[validate-guest-info] After merging form source, updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Ysc.Logging.debug(
      "[validate-guest-info] Final updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Ysc.Logging.debug(
      "[validate-guest-info] Final updated_guest_params: #{inspect(updated_guest_params)}"
    )

    # Update the form with new params to preserve user input
    updated_form = to_form(updated_guest_params, as: "guests")

    Ysc.Logging.debug(
      "[validate-guest-info] Building changesets for booking: #{socket.assigns.booking.id}"
    )

    Ysc.Logging.debug(
      "[validate-guest-info] Booking guests_count: #{socket.assigns.booking.guests_count}, children_count: #{socket.assigns.booking.children_count}"
    )

    case build_guest_changesets(socket.assigns.booking, updated_guest_params) do
      {:ok, changesets} ->
        Ysc.Logging.debug(
          "[validate-guest-info] Built #{length(changesets)} changesets"
        )

        Ysc.Logging.debug(
          "[validate-guest-info] Changesets valid status: #{inspect(Enum.map(changesets, & &1.valid?))}"
        )

        # Check if all changesets are valid
        all_valid = Enum.all?(changesets, & &1.valid?)
        Ysc.Logging.debug("[validate-guest-info] All valid: #{all_valid}")

        if all_valid do
          {:noreply,
           assign(socket,
             guest_info_form: updated_form,
             guest_info_errors: %{}
           )}
        else
          # Collect errors from all changesets
          # Use order_index from the changeset data to match the form keys
          # We need to pair changesets with their order_index from the original guest data
          errors =
            updated_guest_params
            |> Enum.map(fn {index_str, guest_attrs} ->
              {String.to_integer(index_str), guest_attrs}
            end)
            |> Enum.sort_by(fn {index, _} -> index end)
            |> Enum.with_index()
            |> Enum.reduce(%{}, fn {{original_index, _guest_attrs},
                                    changeset_index},
                                   acc ->
              changeset = Enum.at(changesets, changeset_index)

              if changeset && not changeset.valid? do
                changeset_errors =
                  YscWeb.FormHelpers.changeset_errors(changeset)

                # Use the original index_str from the form to match template keys
                Map.put(
                  acc,
                  Integer.to_string(original_index),
                  changeset_errors
                )
              else
                acc
              end
            end)

          {:noreply,
           assign(socket,
             guest_info_form: updated_form,
             guest_info_errors: errors
           )}
        end

      {:error, error_message} when is_binary(error_message) ->
        Ysc.Logging.error(
          "[validate-guest-info] Error building changesets: #{error_message}"
        )

        {:noreply,
         assign(socket,
           guest_info_form: updated_form,
           guest_info_errors: %{general: error_message}
         )}

      {:error, invalid_changesets} when is_list(invalid_changesets) ->
        errors =
          Enum.with_index(invalid_changesets)
          |> Enum.reduce(%{}, fn {changeset, index}, acc ->
            if changeset.valid? do
              acc
            else
              changeset_errors = YscWeb.FormHelpers.changeset_errors(changeset)

              Map.put(acc, Integer.to_string(index), changeset_errors)
            end
          end)

        {:noreply,
         assign(socket,
           guest_info_form: updated_form,
           guest_info_errors: errors
         )}
    end
  end

  def handle_event("validate-guest-info", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle-price-details", _params, socket) do
    current_value = socket.assigns[:show_price_details] || false
    {:noreply, assign(socket, :show_price_details, !current_value)}
  end

  @impl true
  def handle_event("select-guest-attendee", params, socket) do
    require Ysc.Logging

    Ysc.Logging.debug(
      "[select-guest-attendee] Event received with params: #{inspect(params)}"
    )

    # Get guest_index from params - try phx-value-guest-index first, then extract from field name
    guest_index =
      params["guest_index"] ||
        params["guest-index"] ||
        params
        |> Map.keys()
        |> Enum.find(fn key ->
          String.contains?(key, "attendee-select")
        end)
        |> case do
          nil ->
            nil

          field_name ->
            field_name
            |> String.replace("guest-", "")
            |> String.replace("-attendee-select", "")
        end

    # Get the selected value directly from the select field
    # The select field name is "guest-#{guest_index}-attendee-select"
    selected_value =
      if guest_index do
        select_field_name = "guest-#{guest_index}-attendee-select"
        params[select_field_name]
      else
        # Try to find any attendee-select field in params
        params
        |> Map.keys()
        |> Enum.find(&String.contains?(&1, "attendee-select"))
        |> case do
          nil -> nil
          field_name -> params[field_name]
        end
      end

    Ysc.Logging.debug(
      "[select-guest-attendee] guest_index: #{inspect(guest_index)}, selected_value: #{inspect(selected_value)}"
    )

    if guest_index && selected_value do
      guest_info_form =
        socket.assigns.guest_info_form || to_form(%{}, as: "guests")

      guests_for_me = socket.assigns.guests_for_me || %{}

      selected_family_members =
        socket.assigns.selected_family_members_for_guests || %{}

      other_family_members = socket.assigns.other_family_members || []

      {updated_guests_for_me, updated_selected_family_members, updated_form} =
        cond do
          selected_value == "other" ->
            # Select "Someone else" - clear selections and form data
            updated_form_source =
              Map.put(guest_info_form.source, guest_index, %{
                "first_name" => "",
                "last_name" => "",
                "is_child" =>
                  Map.get(
                    guest_info_form.source[guest_index] || %{},
                    "is_child",
                    false
                  ),
                "is_booking_user" =>
                  Map.get(
                    guest_info_form.source[guest_index] || %{},
                    "is_booking_user",
                    false
                  ),
                "order_index" =>
                  Map.get(
                    guest_info_form.source[guest_index] || %{},
                    "order_index",
                    String.to_integer(guest_index)
                  )
              })

            updated_form = %{guest_info_form | source: updated_form_source}

            {
              Map.put(guests_for_me, guest_index, false),
              Map.put(selected_family_members, guest_index, nil),
              updated_form
            }

          is_binary(selected_value) and
              String.starts_with?(selected_value, "family_") ->
            # Select a family member
            user_id_str = String.replace(selected_value, "family_", "")

            selected_user =
              Enum.find(other_family_members, fn u ->
                to_string(u.id) == user_id_str
              end)

            if selected_user do
              # Get existing guest data to preserve metadata
              existing_guest_data =
                Map.get(guest_info_form.source, guest_index, %{})

              Ysc.Logging.debug(
                "[select-guest-attendee] Existing guest data for index #{guest_index}: #{inspect(existing_guest_data)}"
              )

              form_data = %{
                "first_name" => selected_user.first_name || "",
                "last_name" => selected_user.last_name || "",
                "is_child" => Map.get(existing_guest_data, "is_child", false),
                "is_booking_user" =>
                  Map.get(existing_guest_data, "is_booking_user", false),
                "order_index" =>
                  Map.get(
                    existing_guest_data,
                    "order_index",
                    String.to_integer(guest_index)
                  )
              }

              Ysc.Logging.debug(
                "[select-guest-attendee] Form data for index #{guest_index}: #{inspect(form_data)}"
              )

              updated_form_source =
                Map.put(guest_info_form.source, guest_index, form_data)

              updated_form = %{guest_info_form | source: updated_form_source}

              Ysc.Logging.debug(
                "[select-guest-attendee] Updated form source keys: #{inspect(Map.keys(updated_form_source))}"
              )

              {
                Map.put(guests_for_me, guest_index, false),
                Map.put(selected_family_members, guest_index, selected_user.id),
                updated_form
              }
            else
              {guests_for_me, selected_family_members, guest_info_form}
            end

          true ->
            {guests_for_me, selected_family_members, guest_info_form}
        end

      # After updating the form, trigger validation to ensure all guest data is preserved
      # and errors are updated
      updated_socket =
        socket
        |> assign(:guest_info_form, updated_form)
        |> assign(:guests_for_me, updated_guests_for_me)
        |> assign(
          :selected_family_members_for_guests,
          updated_selected_family_members
        )

      # Trigger validation by simulating a validate event with the current form data
      # This ensures all guest entries are preserved and validated
      # Include all fields, not just first_name and last_name, to preserve metadata
      validate_params =
        updated_form.source
        |> Enum.map(fn {index_str, guest_data} ->
          # Only include the fields that would be submitted from the form inputs
          # The metadata (is_child, is_booking_user, order_index) will be preserved
          # from the form source during the merge in validate-guest-info
          {index_str, Map.take(guest_data, ["first_name", "last_name"])}
        end)
        |> Map.new()

      Ysc.Logging.debug(
        "[select-guest-attendee] Triggering validation with params: #{inspect(validate_params)}"
      )

      Ysc.Logging.debug(
        "[select-guest-attendee] Form source before validation: #{inspect(updated_form.source)}"
      )

      Ysc.Logging.debug(
        "[select-guest-attendee] Before validation - selected_family_members: #{inspect(updated_selected_family_members)}"
      )

      # Call validate handler to ensure all data is preserved and errors are updated
      # IMPORTANT: The validate handler should preserve selected_family_members_for_guests
      {:noreply, validated_socket} =
        handle_event(
          "validate-guest-info",
          %{"guests" => validate_params},
          updated_socket
        )

      # Ensure selected_family_members_for_guests is preserved after validation
      final_socket =
        if Map.get(
             validated_socket.assigns,
             :selected_family_members_for_guests
           ) !=
             updated_selected_family_members do
          Ysc.Logging.debug(
            "[select-guest-attendee] Restoring selected_family_members after validation was lost"
          )

          assign(
            validated_socket,
            :selected_family_members_for_guests,
            updated_selected_family_members
          )
        else
          validated_socket
        end

      Ysc.Logging.debug(
        "[select-guest-attendee] After validation - selected_family_members: #{inspect(final_socket.assigns.selected_family_members_for_guests)}"
      )

      Ysc.Logging.debug(
        "[select-guest-attendee] Form source after validation: #{inspect(final_socket.assigns.guest_info_form.source)}"
      )

      {:noreply, final_socket}
    else
      Ysc.Logging.warning(
        "select-guest-attendee: Missing guest_index or selected_value. guest_index=#{inspect(guest_index)}, selected_value=#{inspect(selected_value)}, all_params=#{inspect(params)}"
      )

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save-guest-info", %{"guests" => guest_params}, socket) do
    require Ysc.Logging
    Ysc.Logging.debug("[save-guest-info] Event received")

    Ysc.Logging.debug(
      "[save-guest-info] Received guest_params: #{inspect(guest_params)}"
    )

    # Merge family member selections into guest_params before saving
    selected_family_members =
      socket.assigns.selected_family_members_for_guests || %{}

    other_family_members = socket.assigns.other_family_members || []

    Ysc.Logging.debug(
      "[save-guest-info] selected_family_members: #{inspect(selected_family_members)}"
    )

    Ysc.Logging.debug(
      "[save-guest-info] other_family_members count: #{length(other_family_members)}"
    )

    # Update guest_params with family member data if selected
    updated_guest_params =
      guest_params
      |> Enum.map(fn {index_str, guest_data} ->
        selected_family_member_id = Map.get(selected_family_members, index_str)

        updated_guest_data =
          if selected_family_member_id do
            # Use selected family member's details
            selected_family_member =
              Enum.find(other_family_members, fn u ->
                to_string(u.id) == to_string(selected_family_member_id)
              end)

            if selected_family_member do
              Map.merge(guest_data, %{
                "first_name" => selected_family_member.first_name || "",
                "last_name" => selected_family_member.last_name || ""
              })
            else
              guest_data
            end
          else
            # Use form data as-is
            guest_data
          end

        {index_str, updated_guest_data}
      end)
      |> Map.new()

    Ysc.Logging.debug(
      "[save-guest-info] updated_guest_params after family member merge: #{inspect(updated_guest_params)}"
    )

    # Find and include the booking user entry from form source (it's not in the submitted params)
    guest_info_form =
      socket.assigns.guest_info_form || to_form(%{}, as: "guests")

    Ysc.Logging.debug(
      "[save-guest-info] guest_info_form.source keys: #{inspect(Map.keys(guest_info_form.source))}"
    )

    Ysc.Logging.debug(
      "[save-guest-info] guest_info_form.source: #{inspect(guest_info_form.source)}"
    )

    # Merge all entries from form source, then update with submitted params
    # When a user types in a field, only that field's data is submitted via phx-change,
    # so we need to merge all entries from the form source to preserve all guest data
    # We need to do a deep merge to preserve nested fields within each guest entry
    # IMPORTANT: Normalize boolean values from strings to actual booleans
    updated_guest_params =
      guest_info_form.source
      |> Map.merge(updated_guest_params, fn _key, source_data, submitted_data ->
        # Deep merge: merge the nested maps so we preserve all fields
        merged = Map.merge(source_data, submitted_data)

        # Normalize boolean fields from strings to actual booleans
        # Form submissions send "true"/"false" as strings, but we need actual booleans
        merged
        |> Map.update("is_child", false, fn
          "true" -> true
          "false" -> false
          true -> true
          false -> false
          val -> val
        end)
        |> Map.update("is_booking_user", false, fn
          "true" -> true
          "false" -> false
          true -> true
          false -> false
          val -> val
        end)
        |> Map.update("order_index", 0, fn
          val when is_binary(val) -> String.to_integer(val)
          val when is_integer(val) -> val
          val -> val
        end)
      end)

    Ysc.Logging.debug(
      "[save-guest-info] After merging form source, updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Ysc.Logging.debug(
      "[save-guest-info] Final updated_guest_params: #{inspect(updated_guest_params)}"
    )

    Ysc.Logging.debug(
      "[save-guest-info] Building changesets for booking: #{socket.assigns.booking.id}"
    )

    Ysc.Logging.debug(
      "[save-guest-info] Booking guests_count: #{socket.assigns.booking.guests_count}, children_count: #{socket.assigns.booking.children_count}"
    )

    case build_guest_changesets(socket.assigns.booking, updated_guest_params) do
      {:ok, changesets} ->
        Ysc.Logging.debug(
          "[save-guest-info] Built #{length(changesets)} changesets"
        )

        Ysc.Logging.debug(
          "[save-guest-info] Changesets valid status: #{inspect(Enum.map(changesets, & &1.valid?))}"
        )

        case save_guests(socket.assigns.booking, changesets) do
          {:ok, _guests} ->
            # Reload booking to get guests
            booking =
              Repo.get!(Booking, socket.assigns.booking.id)
              |> Repo.preload([
                :user,
                :booking_guests,
                :rooms,
                rooms: :room_category
              ])

            # Create payment intent now that guests are saved (skip Stripe when total is $0)
            user = socket.assigns.current_user

            if Money.zero?(socket.assigns.total_price) do
              {:noreply,
               socket
               |> assign(
                 booking: booking,
                 checkout_step: :payment,
                 payment_intent: nil,
                 show_payment_form: false,
                 stripe_payment_element_ready: false,
                 guest_info_form: nil,
                 guest_info_errors: %{}
               )
               |> YscWeb.Flash.put_toast(
                 :info,
                 "Guest information saved. No payment is required for this booking.",
                 title: "Checkout"
               )}
            else
              case create_payment_intent(
                     booking,
                     socket.assigns.total_price,
                     user
                   ) do
                {:ok, payment_intent} ->
                  {booking, payment_intent} =
                    persist_checkout_payment_intent(booking, payment_intent)

                  {:noreply,
                   socket
                   |> assign(
                     booking: booking,
                     checkout_step: :payment,
                     payment_intent: payment_intent,
                     show_payment_form: true,
                     stripe_payment_element_ready: false,
                     guest_info_form: nil,
                     guest_info_errors: %{}
                   )
                   |> YscWeb.Flash.put_toast(
                     :info,
                     "Guest information saved. Please complete payment.",
                     title: "Checkout"
                   )}

                {:error, message} ->
                  {:noreply,
                   assign(socket,
                     payment_error: message,
                     checkout_step: :payment
                   )}
              end
            end

          {:error, changeset} ->
            errors = YscWeb.FormHelpers.changeset_errors(changeset)

            {:noreply,
             assign(socket,
               guest_info_errors: %{general: errors}
             )}
        end

      {:error, error_message} when is_binary(error_message) ->
        Ysc.Logging.error(
          "[save-guest-info] Error building changesets: #{error_message}"
        )

        {:noreply,
         assign(socket,
           guest_info_errors: %{general: error_message}
         )
         |> YscWeb.Flash.put_toast(:error, error_message, title: "Checkout")}

      {:error, invalid_changesets} when is_list(invalid_changesets) ->
        errors =
          Enum.with_index(invalid_changesets)
          |> Enum.reduce(%{}, fn {changeset, index}, acc ->
            if changeset.valid? do
              acc
            else
              changeset_errors = YscWeb.FormHelpers.changeset_errors(changeset)

              Map.put(acc, Integer.to_string(index), changeset_errors)
            end
          end)

        {:noreply,
         assign(socket, guest_info_errors: errors)
         |> YscWeb.Flash.error_with_title(
           "Form errors",
           "Please fix the errors below."
         )}
    end
  end

  def handle_event("save-guest-info", _params, socket) do
    {:noreply,
     assign(socket,
       guest_info_errors: %{general: "No guest information provided"}
     )
     |> YscWeb.Flash.put_toast(:error, "Guest information is required.",
       title: "Checkout"
     )}
  end

  @impl true
  def handle_event("confirm-complimentary-booking", _params, socket) do
    booking = reload_checkout_booking(socket.assigns.booking.id)

    cond do
      socket.assigns.checkout_step != :payment ->
        {:noreply, socket}

      booking_expired?(booking) ->
        {:noreply,
         socket
         |> assign(
           payment_error: BookingUserMessages.checkout_hold_expired(),
           show_payment_form: false,
           stripe_payment_element_ready: false
         )
         |> YscWeb.Flash.put_toast(
           :error,
           BookingUserMessages.checkout_hold_expired_toast(),
           title: "Checkout"
         )}

      true ->
        confirm_complimentary_checkout(socket, booking)
    end
  end

  @impl true
  def handle_event("cancel-booking", _params, socket) do
    case BookingLocker.release_hold(socket.assigns.booking.id) do
      {:ok, _canceled_booking} ->
        property = socket.assigns.booking.property
        redirect_path = get_property_redirect_path(property)

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Your booking has been canceled and the availability has been released.",
           title: "Checkout"
         )
         |> redirect(to: redirect_path)}

      {:error, reason} ->
        Ysc.Logging.error("[BookingCheckout] Failed to cancel booking hold",
          reason: inspect(reason),
          booking_id: socket.assigns.booking.id
        )

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           YscWeb.BookingUserMessages.checkout_cancel_failed(),
           title: "Checkout"
         )}
    end
  end

  @impl true
  def handle_event("payment-redirect-started", _params, socket) do
    # Acknowledge that the payment redirect has started (no action needed)
    {:noreply, socket}
  end

  @impl true
  def handle_event("stripe-payment-element-loading", _params, socket) do
    {:noreply, assign(socket, :stripe_payment_element_ready, false)}
  end

  @impl true
  def handle_event("stripe-payment-element-ready", _params, socket) do
    {:noreply, assign(socket, :stripe_payment_element_ready, true)}
  end

  @impl true
  def handle_event(
        "payment-success",
        %{"payment_intent_id" => payment_intent_id},
        socket
      ) do
    booking = reload_checkout_booking(socket.assigns.booking.id)

    case process_payment_success(booking, payment_intent_id) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Payment successful! Your booking is confirmed.",
           title: "Booking confirmed",
           icon: &YscWeb.CoreComponents.flash_toast_icon_calendar/1
         )
         |> push_navigate(to: ~p"/bookings/#{booking.id}/receipt?confetti=true")}

      {:error, reason} ->
        Ysc.Logging.error(
          "[BookingCheckout] Payment succeeded but booking confirmation failed",
          reason: inspect(reason),
          booking_id: socket.assigns.booking.id
        )

        {:noreply,
         assign(socket,
           payment_error:
             YscWeb.BookingUserMessages.checkout_payment_confirmation_failed()
         )}
    end
  end

  @impl true
  def handle_info(:check_booking_expiration, socket) do
    if socket.assigns[:checkout_data_loaded?] && socket.assigns.booking do
      handle_booking_expiration_check(socket)
    else
      {:noreply, socket}
    end
  end

  defp handle_booking_expiration_check(socket) do
    booking = reload_checkout_booking(socket.assigns.booking.id)

    if booking_payable?(booking) do
      Process.send_after(self(), :check_booking_expiration, 5_000)

      {:noreply,
       assign(socket,
         booking: booking,
         is_expired: false
       )}
    else
      {:noreply,
       socket
       |> assign(
         booking: booking,
         is_expired: true,
         show_payment_form: false,
         stripe_payment_element_ready: false,
         payment_error: BookingUserMessages.checkout_hold_expired()
       )
       |> YscWeb.Flash.put_toast(
         :error,
         BookingUserMessages.checkout_hold_expired_toast(),
         title: "Checkout"
       )}
    end
  end

  ## Private Functions

  defp confirm_complimentary_checkout(socket, booking) do
    case calculate_booking_price(booking) do
      {:ok, total_price, price_breakdown} ->
        if Money.zero?(total_price) do
          case sync_checkout_hold_pricing(booking, total_price, price_breakdown) do
            {:ok, synced_booking} ->
              confirm_synced_complimentary_booking(
                socket,
                synced_booking,
                total_price,
                price_breakdown
              )

            {:error, reason} ->
              Ysc.Logging.warning(
                "[BookingCheckout] Failed to sync recalculated hold pricing before complimentary confirmation",
                booking_id: booking.id,
                reason: inspect(reason)
              )

              return_complimentary_pricing_error(socket)
          end
        else
          {:noreply,
           socket
           |> assign(
             booking: booking,
             total_price: total_price,
             price_breakdown: price_breakdown,
             complimentary_checkout: false,
             payment_error: nil,
             show_payment_form: false,
             stripe_payment_element_ready: false
           )
           |> YscWeb.Flash.put_toast(:error, "This booking requires payment.",
             title: "Checkout"
           )}
        end

      {:error, reason}
      when reason in [
             :entitlement_no_longer_valid,
             :entitlement_not_eligible_for_booking
           ] ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Your member discount or free night is no longer valid for this booking, so we can't finish checkout at this price. Please start a new booking from the cabin page — your previous dates may no longer be available.",
           title: "Checkout"
         )
         |> redirect(to: get_property_redirect_path(booking.property))}

      {:error, reason} ->
        Ysc.Logging.error(
          "[BookingCheckout] Failed to recalculate price for complimentary confirmation",
          reason: inspect(reason),
          booking_id: booking.id
        )

        return_complimentary_pricing_error(socket)
    end
  end

  defp confirm_synced_complimentary_booking(
         socket,
         booking,
         total_price,
         price_breakdown
       ) do
    case process_complimentary_booking_confirmation(booking) do
      {:ok, confirmed} ->
        {:noreply,
         socket
         |> assign(
           booking: confirmed,
           total_price: total_price,
           price_breakdown: price_breakdown,
           complimentary_checkout: true
         )
         |> YscWeb.Flash.put_toast(
           :info,
           "Your booking is confirmed.",
           title: "Booking confirmed",
           icon: &YscWeb.CoreComponents.flash_toast_icon_calendar/1
         )
         |> push_navigate(
           to: ~p"/bookings/#{confirmed.id}/receipt?confetti=true"
         )}

      {:error, reason} ->
        Ysc.Logging.error(
          "[BookingCheckout] Complimentary booking confirmation failed",
          reason: inspect(reason),
          booking_id: booking.id
        )

        {:noreply,
         assign(socket,
           payment_error:
             YscWeb.BookingUserMessages.checkout_booking_confirmation_failed()
         )}
    end
  end

  defp return_complimentary_pricing_error(socket) do
    {:noreply,
     assign(socket,
       payment_error:
         "We couldn't verify the current price for this booking. Please refresh the page or start a new booking."
     )}
  end

  defp sync_checkout_hold_pricing(booking, total_price, price_breakdown) do
    Bookings.sync_hold_checkout_pricing(booking, %{
      total_price: total_price,
      subtotal_price: price_breakdown[:entitlement_subtotal],
      discount_total: price_breakdown[:entitlement_discount]
    })
  end

  @dialyzer {:nowarn_function, calculate_booking_price: 1}
  defp calculate_booking_price(booking) do
    nights = Date.diff(booking.checkout_date, booking.checkin_date)
    seasons = SeasonCache.get_all_for_property(booking.property)

    room_opts = fn ->
      room_ids =
        if Ecto.assoc_loaded?(booking.rooms) && booking.rooms != [] do
          Enum.map(booking.rooms, & &1.id)
        else
          []
        end

      [
        guests_count: booking.guests_count,
        children_count: booking.children_count || 0,
        room_ids: room_ids
      ]
    end

    case booking.booking_mode do
      :buyout ->
        case Bookings.calculate_booking_price(
               booking.property,
               booking.checkin_date,
               booking.checkout_date,
               :buyout,
               guests_count: booking.guests_count,
               children_count: 0,
               seasons: seasons
             ) do
          {:ok, total, breakdown} ->
            with {:ok, priced} <-
                   Entitlements.price_with_locked_entitlement(
                     booking,
                     total,
                     :buyout,
                     room_opts.()
                   ) do
              final_breakdown =
                Map.merge(breakdown, %{
                  nights: nights,
                  entitlement_discount: priced.discount,
                  entitlement_subtotal: priced.subtotal,
                  entitlement_summary:
                    priced.breakdown_additions[:entitlement_summary]
                })

              {:ok, priced.total, final_breakdown}
            end

          error ->
            error
        end

      :room ->
        # For room bookings, always recalculate to ensure correct pricing
        # (stored pricing may be incorrect if calculated per-room instead of per-guest)
        children_count = booking.children_count || 0

        room_ids =
          if Ecto.assoc_loaded?(booking.rooms) && booking.rooms != [] do
            Enum.map(booking.rooms, & &1.id)
          else
            []
          end

        if room_ids == [] do
          {:error, :rooms_required}
        else
          # Always recalculate price correctly for per-guest pricing
          # For per-guest pricing, calculate once for total guests regardless of room count
          case calculate_multi_room_price_for_checkout(
                 booking.property,
                 booking.checkin_date,
                 booking.checkout_date,
                 room_ids,
                 booking.guests_count,
                 children_count,
                 nights,
                 seasons
               ) do
            {:ok, recalculated_total, breakdown} ->
              with {:ok, priced} <-
                     Entitlements.price_with_locked_entitlement(
                       booking,
                       recalculated_total,
                       :room,
                       room_opts.()
                     ) do
                {:ok, priced.total,
                 Map.merge(breakdown, %{
                   entitlement_discount: priced.discount,
                   entitlement_subtotal: priced.subtotal,
                   entitlement_summary:
                     priced.breakdown_additions[:entitlement_summary]
                 })}
              end

            error ->
              # Fallback to stored pricing if recalculation fails
              if booking.total_price && booking.pricing_items do
                {:ok, booking.total_price,
                 extract_price_breakdown_from_pricing_items(
                   booking.pricing_items,
                   nights
                 )}
              else
                error
              end
          end
        end

      :day ->
        case Bookings.calculate_booking_price(
               booking.property,
               booking.checkin_date,
               booking.checkout_date,
               :day,
               guests_count: booking.guests_count,
               children_count: 0,
               seasons: seasons
             ) do
          {:ok, total, breakdown} ->
            with {:ok, priced} <-
                   Entitlements.price_with_locked_entitlement(
                     booking,
                     total,
                     :day,
                     room_opts.()
                   ) do
              final_breakdown =
                Map.merge(breakdown, %{
                  nights: nights,
                  guests_count: booking.guests_count,
                  entitlement_discount: priced.discount,
                  entitlement_subtotal: priced.subtotal,
                  entitlement_summary:
                    priced.breakdown_additions[:entitlement_summary]
                })

              {:ok, priced.total, final_breakdown}
            end

          error ->
            error
        end

      _ ->
        {:error, :invalid_booking_mode}
    end
  end

  defp persist_checkout_payment_intent(booking, payment_intent) do
    case Bookings.attach_payment_intent(booking, payment_intent.id) do
      {:ok, updated} ->
        {updated, payment_intent}

      {:error, reason} ->
        Ysc.Logging.error(
          "Failed to persist booking payment_intent_id",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )

        {booking, payment_intent}
    end
  end

  defp create_payment_intent(booking, total_amount, user) do
    amount_cents = MoneyHelper.money_to_cents(total_amount)

    # Note: Stripe PaymentIntents don't support expires_at parameter.
    # The expires_at parameter is only available for Checkout Sessions, not PaymentIntents.
    # Since we're using PaymentIntents with Stripe Elements (embedded form), we handle
    # expiration server-side via HoldExpiryWorker that cancels expired bookings and releases inventory.
    payment_intent_params = %{
      amount: amount_cents,
      currency: "usd",
      metadata: %{
        booking_id: booking.id,
        booking_reference: booking.reference_id,
        property: Atom.to_string(booking.property),
        user_id: user.id
      },
      description:
        "Booking #{booking.reference_id} - #{String.capitalize(Atom.to_string(booking.property))}",
      automatic_payment_methods: %{
        enabled: true
      }
    }

    {payment_intent_params, _user} =
      Ysc.Customers.attach_customer_to_payment_intent_params(
        payment_intent_params,
        user
      )

    # Include amount in the idempotency key so repriced holds get a fresh PI.
    # A reference-only key caused Stripe to return a stale PI after checkout
    # recalculated entitlements or min-occupancy pricing.
    idempotency_key =
      Ysc.Stripe.Idempotency.key(
        "booking_#{booking.reference_id}_#{amount_cents}"
      )

    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.create_payment_intent(payment_intent_params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, payment_intent} ->
        if payment_intent.amount == amount_cents do
          {:ok, payment_intent}
        else
          Ysc.Logging.warning(
            "[BookingCheckout] Stripe returned payment intent with stale amount",
            booking_id: booking.id,
            expected_amount_cents: amount_cents,
            payment_intent_id: payment_intent.id,
            payment_intent_amount_cents: payment_intent.amount
          )

          {:error, YscWeb.BookingUserMessages.checkout_payment_setup_failed()}
        end

      {:error, %Stripe.Error{} = error} ->
        Ysc.Logging.error(
          "Stripe payment intent creation failed: #{inspect(error)}"
        )

        {:error, Ysc.PaymentUserMessages.format_stripe_error(error)}

      {:error, reason} ->
        Ysc.Logging.error("Payment intent creation failed: #{inspect(reason)}")
        {:error, Ysc.PaymentUserMessages.payment_setup_failed()}
    end
  end

  defp process_complimentary_booking_confirmation(booking) do
    reloaded_booking =
      Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

    cond do
      reloaded_booking.status == :complete ->
        post_complimentary_ledger_payment(booking, reloaded_booking)

      true ->
        case BookingLocker.confirm_booking(reloaded_booking.id) do
          {:ok, confirmed_booking} ->
            post_complimentary_ledger_payment(booking, confirmed_booking)

          {:error, :invalid_status} ->
            final_booking =
              Repo.get!(Booking, reloaded_booking.id)
              |> Repo.preload([:rooms, :user])

            if final_booking.status == :complete do
              post_complimentary_ledger_payment(booking, final_booking)
            else
              {:error, :booking_confirmation_failed}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp post_complimentary_ledger_payment(booking, confirmed_booking) do
    zero = Money.new(0, :USD)
    external_payment_id = "booking_complimentary_#{booking.reference_id}"

    case Ysc.Ledgers.process_payment(%{
           user_id: booking.user_id,
           amount: zero,
           entity_type: :booking,
           entity_id: booking.id,
           external_payment_id: external_payment_id,
           stripe_fee: nil,
           description: "Complimentary booking - #{booking.reference_id}",
           property: booking.property,
           payment_method_id: nil
         }) do
      {:ok, _} ->
        {:ok, confirmed_booking}

      {:error, reason} ->
        Ysc.Logging.error(
          "Complimentary booking confirmed but ledger payment recording failed",
          booking_id: booking.id,
          error: inspect(reason)
        )

        {:error, {:ledger_payment_failed, reason}}
    end
  end

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

    # Retrieve payment intent to verify. Stripe rejects expanding
    # `latest_charge.payment_method`; use top-level `payment_method` and
    # `latest_charge` (charge may still expose `payment_method` as an id string).
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "latest_charge"]
         }) do
      {:ok, payment_intent} ->
        if payment_intent.status == "succeeded" do
          case Bookings.maybe_sync_hold_pricing_from_calculation(booking) do
            {:ok, synced_booking} ->
              case Bookings.verify_booking_payment_intent(
                     payment_intent,
                     synced_booking
                   ) do
                :ok ->
                  process_verified_booking_payment_success(
                    synced_booking,
                    payment_intent,
                    payment_intent_id
                  )

                {:error, reason} ->
                  Bookings.maybe_refund_unfulfilled_checkout_payment(
                    synced_booking,
                    payment_intent,
                    reason
                  )

                  {:error, reason}
              end

            {:error, reason} ->
              Ysc.Logging.warning(
                "[BookingCheckout] Failed to sync recalculated hold pricing before payment verification",
                booking_id: booking.id,
                reason: inspect(reason)
              )

              Bookings.maybe_refund_unfulfilled_checkout_payment(
                booking,
                payment_intent,
                reason
              )

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
    # Reload booking to get latest status (webhook may have already confirmed it)
    reloaded_booking =
      Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

    # Booking may already be :complete after a prior confirm; still record ledger
    # (idempotent on payment_intent id) so retries recover from ledger failures.
    if reloaded_booking.status == :complete do
      Ysc.Logging.info(
        "Booking already confirmed, ensuring ledger payment is recorded",
        booking_id: booking.id,
        payment_intent_id: payment_intent_id
      )

      finalize_paid_ledger_payment(reloaded_booking, payment_intent)
    else
      # Confirm before ledger: Stripe may already be captured, but we must not
      # record a ledger payment for a booking that failed to confirm (e.g.
      # entitlement already consumed by another hold).
      case BookingLocker.confirm_booking(reloaded_booking.id) do
        {:ok, confirmed_booking} ->
          case process_ledger_payment(confirmed_booking, payment_intent) do
            {:ok, _payment} ->
              {:ok, confirmed_booking}

            {:error, reason} ->
              Ysc.Logging.error(
                "Booking confirmed but ledger payment recording failed",
                booking_id: confirmed_booking.id,
                error: inspect(reason)
              )

              {:error, :payment_processing_failed}
          end

        {:error, :invalid_status} ->
          # Booking was confirmed between reload and confirm attempt (race condition)
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

            Bookings.maybe_refund_unfulfilled_checkout_payment(
              final_booking,
              payment_intent,
              :booking_confirmation_failed
            )

            {:error, :booking_confirmation_failed}
          end

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to confirm booking: #{inspect(reason)}",
            booking_id: reloaded_booking.id
          )

          Bookings.maybe_refund_unfulfilled_checkout_payment(
            reloaded_booking,
            payment_intent,
            reason
          )

          {:error, :booking_confirmation_failed}
      end
    end
  end

  defp finalize_paid_ledger_payment(booking, payment_intent) do
    case process_ledger_payment(booking, payment_intent) do
      {:ok, _payment} ->
        {:ok, booking}

      {:error, reason} ->
        {:error, {:ledger_payment_failed, reason}}
    end
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

  # Helper to extract price breakdown from stored pricing_items (fallback only)
  # For per-guest pricing with multiple rooms, aggregate into single line item
  defp extract_price_breakdown_from_pricing_items(pricing_items, nights)
       when is_map(pricing_items) do
    case pricing_items do
      %{"type" => "room", "rooms" => rooms}
      when is_list(rooms) and rooms != [] ->
        # Multiple rooms - for per-guest pricing, show single aggregated line item
        guests_count = pricing_items["guests_count"] || 0
        children_count = pricing_items["children_count"] || 0

        %{
          nights: nights,
          guests_count: guests_count,
          children_count: children_count,
          multi_room: true,
          room_count: length(rooms)
        }

      %{"type" => "room"} ->
        # Single room (legacy format)
        %{
          nights: nights,
          guests_count: pricing_items["guests_count"] || 0,
          children_count: pricing_items["children_count"] || 0
        }

      _ ->
        %{nights: nights}
    end
  end

  defp extract_price_breakdown_from_pricing_items(_, nights),
    do: %{nights: nights}

  # Helper to calculate price for multiple rooms (fallback)
  # For per-guest pricing, calculate once for total guests regardless of room count
  @dialyzer {:nowarn_function, calculate_multi_room_price_for_checkout: 8}
  defp calculate_multi_room_price_for_checkout(
         property,
         checkin_date,
         checkout_date,
         room_ids,
         guests_count,
         children_count,
         nights,
         seasons
       ) do
    # For per-guest pricing, calculate price once using the first room
    # The number of rooms doesn't affect the price - only total guests matter
    first_room_id = List.first(room_ids)

    case Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :room,
           room_id: first_room_id,
           guests_count: guests_count,
           children_count: children_count,
           seasons: seasons
         ) do
      {:ok, total, breakdown} when is_map(breakdown) ->
        breakdown_map =
          build_multi_room_breakdown(
            breakdown,
            nights,
            guests_count,
            children_count,
            room_ids
          )

        {:ok, total, breakdown_map}

      error ->
        error
    end
  end

  defp build_multi_room_breakdown(
         breakdown,
         nights,
         guests_count,
         children_count,
         room_ids
       ) do
    base_total = breakdown[:base]
    children_total = breakdown[:children]
    billable_people = breakdown[:billable_people] || guests_count
    adult_price_per_night = breakdown[:adult_price_per_night]
    children_price_per_night = breakdown[:children_price_per_night]

    base_per_night =
      calculate_base_per_night(base_total, nights, adult_price_per_night)

    children_per_night =
      calculate_children_per_night(
        children_total,
        nights,
        children_count,
        children_price_per_night
      )

    base_breakdown = %{
      nights: nights,
      guests_count: guests_count,
      children_count: children_count,
      billable_people: billable_people,
      multi_room: true,
      room_count: length(room_ids)
    }

    base_breakdown
    |> add_if_present(:base, base_total)
    |> add_if_present(:children, children_total)
    |> add_if_present(:base_per_night, base_per_night)
    |> add_if_present(:adult_price_per_night, adult_price_per_night)
    |> add_if_positive(:children_per_night, children_per_night)
  end

  defp calculate_base_per_night(base_total, nights, adult_price_per_night) do
    if base_total && nights > 0 do
      case Money.div(base_total, nights) do
        {:ok, per_night} -> per_night
        _ -> adult_price_per_night
      end
    else
      adult_price_per_night
    end
  end

  defp calculate_children_per_night(
         children_total,
         nights,
         children_count,
         children_price_per_night
       ) do
    if children_total && nights > 0 && children_count > 0 do
      {:ok, per_night} = Money.div(children_total, children_count * nights)
      per_night
    else
      children_price_per_night
    end
  end

  defp add_if_present(map, key, value) do
    if value do
      Map.put(map, key, value)
    else
      map
    end
  end

  defp add_if_positive(map, key, value) do
    if value && Money.positive?(value) do
      Map.put(map, key, value)
    else
      map
    end
  end

  # Extract and sync payment method from Stripe
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
        stripe_client =
          Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

        case stripe_client.retrieve_payment_method(pm_id) do
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

  # Timezone-aware formatting functions
  defp format_date_short(%Date{} = date, _timezone) do
    # Shorter format for visual summaries: "Dec 23"
    Calendar.strftime(date, "%b %d")
  end

  defp format_date_short(nil, _timezone), do: "—"
  defp format_date_short(_, _timezone), do: "—"

  defp get_property_redirect_path(property) do
    case property do
      :tahoe -> ~p"/bookings/tahoe"
      :clear_lake -> ~p"/bookings/clear-lake"
      _ -> ~p"/"
    end
  end

  defp get_property_thumbnail(property) do
    case property do
      :tahoe -> ~p"/images/tahoe/tahoe_cabin_main.webp"
      :clear_lake -> ~p"/images/clear_lake/clear_lake_dock.webp"
      _ -> ~p"/images/ysc_logo.webp"
    end
  end

  defp render_price_breakdown_sidebar(assigns) do
    ~H"""
    <%= if @booking.booking_mode == :room do %>
      <%= if @price_breakdown[:nights] do %>
        <% nights = @price_breakdown.nights %>
        <% guests_count = @price_breakdown[:guests_count] || 0 %>
        <% children_count = @price_breakdown[:children_count] || 0 %>
        <% billable_people = @price_breakdown[:billable_people] || guests_count %>
        <% adult_price_per_night =
          @price_breakdown[:adult_price_per_night] ||
            @price_breakdown[:base_per_night] %>
        <% children_price_per_night = @price_breakdown[:children_price_per_night] %>
        <% base_total = @price_breakdown[:base] %>
        <% children_total = @price_breakdown[:children] %>
        <!-- Calculate adult_price_per_night from base_total if not available -->
        <% adult_price_per_night =
          if !adult_price_per_night && base_total && nights > 0 &&
               billable_people > 0 do
            {:ok, price} = Money.div(base_total, nights * billable_people)
            price
          else
            adult_price_per_night
          end %>
        <!-- Adults pricing -->
        <%= if billable_people > 0 && (base_total || adult_price_per_night) do %>
          <% final_base_total =
            if base_total,
              do: base_total,
              else:
                (if adult_price_per_night && billable_people > 0 && nights > 0 do
                   {:ok, total} =
                     Money.mult(adult_price_per_night, billable_people * nights)

                   total
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <div class="text-zinc-400">
              {billable_people} {if billable_people == 1,
                do: "adult",
                else: "adults"}
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if adult_price_per_night do %>
                {MoneyHelper.format_money!(adult_price_per_night)}/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × {nights} {if nights == 1, do: "night", else: "nights"}
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_base_total do %>
                {MoneyHelper.format_money!(final_base_total)}
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- Children pricing -->
        <%= if children_count > 0 && (children_total || children_price_per_night) do %>
          <% # Calculate children_price_per_night from children_total if not available
          calculated_children_price_per_night =
            if !children_price_per_night && children_total && children_count > 0 &&
                 nights > 0 do
              {:ok, price} = Money.div(children_total, children_count * nights)
              price
            else
              children_price_per_night
            end

          final_children_total =
            if children_total,
              do: children_total,
              else:
                (if calculated_children_price_per_night && children_count > 0 &&
                      nights > 0 do
                   {:ok, total} =
                     Money.mult(
                       calculated_children_price_per_night,
                       children_count * nights
                     )

                   total
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm mt-3">
            <div class="text-zinc-400">
              {children_count} {if children_count == 1,
                do: "child",
                else: "children"}
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if calculated_children_price_per_night do %>
                {MoneyHelper.format_money!(calculated_children_price_per_night)}/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × {nights} {if nights == 1, do: "night", else: "nights"}
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_children_total do %>
                {MoneyHelper.format_money!(final_children_total)}
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    <% else %>
      <!-- Day booking (per guest per night) -->
      <%= if @booking.booking_mode == :day && @price_breakdown[:nights] do %>
        <% nights = @price_breakdown.nights %>
        <% guests_count = @price_breakdown[:guests_count] || 0 %>
        <% price_per_guest_per_night = @price_breakdown[:price_per_guest_per_night] %>
        <% segments = @price_breakdown[:segments] || [] %>
        <%= if guests_count > 0 && length(segments) > 1 do %>
          <!-- Stay spans more than one season: show a line per season -->
          <div class="text-xs text-zinc-500 mb-1">
            {guests_count} {if guests_count == 1, do: "guest", else: "guests"} · rate varies by season
          </div>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <%= for segment <- segments do %>
              <div class="text-zinc-400">
                {segment.season_name || "Unnamed season"}
              </div>
              <div class="text-right text-zinc-500 text-xs tabular-nums">
                {MoneyHelper.format_money!(segment.price_per_guest_per_night)}/guest/night
              </div>
              <div class="text-zinc-400 text-xs">
                × {segment.nights} {if segment.nights == 1,
                  do: "night",
                  else: "nights"}
              </div>
              <div class="text-right font-medium tabular-nums">
                {MoneyHelper.format_money!(segment.total)}
              </div>
            <% end %>
          </div>
        <% else %>
          <%= if guests_count > 0 && price_per_guest_per_night do %>
            <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
              <div class="text-zinc-400">
                {guests_count} {if guests_count == 1,
                  do: "guest",
                  else: "guests"}
              </div>
              <div class="text-right text-zinc-500 text-xs tabular-nums">
                {MoneyHelper.format_money!(price_per_guest_per_night)}/night
              </div>
              <div class="text-zinc-400 text-xs">
                × {nights} {if nights == 1, do: "night", else: "nights"}
              </div>
              <div class="text-right font-medium tabular-nums">
                <% {:ok, total} =
                  Money.mult(price_per_guest_per_night, guests_count * nights) %>
                {MoneyHelper.format_money!(total)}
              </div>
            </div>
          <% else %>
            <!-- Fallback if price_per_guest_per_night not available -->
            <div class="flex justify-between text-sm">
              <span class="text-zinc-400">
                {nights} {if nights == 1, do: "night", else: "nights"}
              </span>
              <span class="font-medium">
                {MoneyHelper.format_money!(@total_price)}
              </span>
            </div>
          <% end %>
        <% end %>
      <% else %>
        <!-- Buyout booking -->
        <% buyout_segments = @price_breakdown[:segments] || [] %>
        <%= if length(buyout_segments) > 1 do %>
          <!-- Stay spans more than one season: show a line per season -->
          <div class="text-xs text-zinc-500 mb-1">
            Entire cabin · rate varies by season
          </div>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <%= for segment <- buyout_segments do %>
              <div class="text-zinc-400">
                {segment.season_name || "Unnamed season"}
              </div>
              <div class="text-right text-zinc-500 text-xs tabular-nums">
                <%= if segment.price_per_night do %>
                  {MoneyHelper.format_money!(segment.price_per_night)}/night
                <% end %>
              </div>
              <div class="text-zinc-400 text-xs">
                × {segment.nights} {if segment.nights == 1,
                  do: "night",
                  else: "nights"}
              </div>
              <div class="text-right font-medium tabular-nums">
                {MoneyHelper.format_money!(segment.total)}
              </div>
            <% end %>
          </div>
        <% else %>
          <%= if @price_breakdown[:nights] do %>
            <div class="flex justify-between text-sm">
              <span class="text-zinc-400">
                {@price_breakdown.nights} {if @price_breakdown.nights == 1,
                  do: "night",
                  else: "nights"}
              </span>
              <span class="font-medium">
                {MoneyHelper.format_money!(
                  if(
                    @price_breakdown[:entitlement_discount] &&
                      Money.positive?(@price_breakdown[:entitlement_discount]),
                    do: @price_breakdown[:entitlement_subtotal] || @total_price,
                    else: @total_price
                  )
                )}
              </span>
            </div>
          <% end %>
        <% end %>
      <% end %>
    <% end %>
    <%= if @price_breakdown[:entitlement_discount] &&
          Money.positive?(@price_breakdown[:entitlement_discount]) do %>
      <div class="flex justify-between text-sm text-emerald-800 mt-3 pt-3 border-t border-zinc-100">
        <span>
          {@price_breakdown[:entitlement_summary] || "Member discount"}
        </span>
        <span class="tabular-nums">
          −{MoneyHelper.format_money!(@price_breakdown[:entitlement_discount])}
        </span>
      </div>
    <% end %>
    """
  end

  defp calculate_remaining_time(%DateTime{} = expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now, :second)

    if diff_seconds > 0 do
      hours = div(diff_seconds, 3600)
      minutes = div(rem(diff_seconds, 3600), 60)
      seconds = rem(diff_seconds, 60)

      if hours > 0 do
        "#{String.pad_leading(Integer.to_string(hours), 2, "0")}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
      else
        "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
      end
    else
      "00:00"
    end
  end

  defp calculate_remaining_time(_), do: "—"

  defp remaining_minutes(%DateTime{} = expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now, :second)

    if diff_seconds > 0 do
      div(diff_seconds, 60)
    else
      0
    end
  end

  defp remaining_minutes(_), do: 0

  defp reload_checkout_booking(booking_id) do
    Repo.get!(Booking, booking_id)
    |> Repo.preload([:user, :booking_guests, rooms: :room_category])
  end

  defp booking_payable?(%Booking{status: :hold} = booking) do
    not booking_expired?(booking)
  end

  defp booking_payable?(_booking), do: false

  defp booking_expired?(booking) do
    case booking do
      %{status: :hold, hold_expires_at: hold_expires_at}
      when not is_nil(hold_expires_at) ->
        DateTime.compare(DateTime.utc_now(), hold_expires_at) == :gt

      %{status: :hold} ->
        # No hold_expires_at set, consider it not expired (shouldn't happen, but be safe)
        false

      _ ->
        # Not in hold status, consider it expired for payment purposes
        true
    end
  end

  defp atom_to_readable(atom) when is_binary(atom) do
    atom
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp atom_to_readable(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp atom_to_readable(_), do: "—"

  ## Guest Information Helpers

  defp initialize_guest_forms(booking, user) do
    # Get guest counts from booking - ensure they're valid integers
    guests_count =
      cond do
        is_integer(booking.guests_count) && booking.guests_count > 0 ->
          booking.guests_count

        is_binary(booking.guests_count) ->
          String.to_integer(booking.guests_count)

        true ->
          1
      end

    children_count =
      cond do
        is_integer(booking.children_count) && booking.children_count >= 0 ->
          booking.children_count

        is_binary(booking.children_count) ->
          String.to_integer(booking.children_count)

        true ->
          0
      end

    # Log for debugging
    require Ysc.Logging

    Ysc.Logging.info("Initializing guest forms",
      booking_id: booking.id,
      guests_count: guests_count,
      children_count: children_count,
      booking_guests_count: booking.guests_count,
      booking_children_count: booking.children_count
    )

    # Pre-fill user as first guest (adult, booking user)
    user_guest = %{
      "first_name" => user.first_name || "",
      "last_name" => user.last_name || "",
      "is_child" => false,
      "is_booking_user" => true,
      "order_index" => 0
    }

    # Calculate remaining adults and children
    # The user is always the first adult, so we need (guests_count - 1) more adults
    remaining_adults = max(0, guests_count - 1)
    remaining_children = children_count

    # Build list of all guests
    additional_guests =
      build_guest_list(remaining_adults, remaining_children, 1)

    guests = [user_guest] ++ additional_guests

    # Log the guest list for debugging
    require Ysc.Logging

    Ysc.Logging.info("Built guest list",
      total_guests: length(guests),
      user_guest: true,
      additional_adults: remaining_adults,
      additional_children: remaining_children,
      guest_list_length: length(additional_guests)
    )

    # Create a map structure for form params
    # Use the order_index as the key to ensure correct ordering
    guest_params =
      guests
      |> Enum.map(fn guest ->
        order_index = Map.get(guest, "order_index") || 0
        {Integer.to_string(order_index), guest}
      end)
      |> Map.new()

    # Verify we have the correct number of guests
    expected_total = guests_count + children_count
    actual_total = map_size(guest_params)

    # Filter to only include the expected number of guests (sorted by order_index)
    filtered_guest_params =
      guest_params
      |> Enum.map(fn {index_str, guest} ->
        order_index =
          Map.get(guest, "order_index") || String.to_integer(index_str)

        {order_index, {index_str, guest}}
      end)
      |> Enum.sort_by(fn {order_index, _} -> order_index end)
      |> Enum.take(expected_total)
      |> Enum.map(fn {_order_index, {index_str, guest}} ->
        {index_str, guest}
      end)
      |> Map.new()

    if actual_total != expected_total do
      require Ysc.Logging

      Ysc.Logging.warning("Guest count mismatch - filtering form",
        expected: expected_total,
        actual: actual_total,
        guests_count: guests_count,
        children_count: children_count,
        filtered_count: map_size(filtered_guest_params)
      )
    end

    # Create a simple form from the params map
    to_form(filtered_guest_params, as: "guests")
  end

  defp build_guest_list(remaining_adults, remaining_children, start_index) do
    # Ensure we don't create negative ranges
    adults =
      if remaining_adults > 0 do
        Enum.map(0..(remaining_adults - 1), fn i ->
          %{
            "first_name" => "",
            "last_name" => "",
            "is_child" => false,
            "is_booking_user" => false,
            "order_index" => start_index + i
          }
        end)
      else
        []
      end

    children =
      if remaining_children > 0 do
        Enum.map(0..(remaining_children - 1), fn i ->
          %{
            "first_name" => "",
            "last_name" => "",
            "is_child" => true,
            "is_booking_user" => false,
            "order_index" => start_index + remaining_adults + i
          }
        end)
      else
        []
      end

    adults ++ children
  end

  defp build_guest_changesets(booking, guest_params)
       when is_map(guest_params) do
    require Ysc.Logging

    Ysc.Logging.debug(
      "[build_guest_changesets] Called with booking_id: #{booking.id}"
    )

    Ysc.Logging.debug(
      "[build_guest_changesets] guest_params keys: #{inspect(Map.keys(guest_params))}"
    )

    Ysc.Logging.debug(
      "[build_guest_changesets] guest_params: #{inspect(guest_params)}"
    )

    guests_count = booking.guests_count || 1
    children_count = booking.children_count || 0
    total_expected = guests_count + children_count

    Ysc.Logging.debug(
      "[build_guest_changesets] guests_count: #{guests_count}, children_count: #{children_count}, total_expected: #{total_expected}"
    )

    # Convert guest_params map to list and sort by index
    guests_list =
      guest_params
      |> Enum.map(fn {index_str, guest_attrs} ->
        {String.to_integer(index_str), guest_attrs}
      end)
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_index, attrs} -> attrs end)

    Ysc.Logging.debug(
      "[build_guest_changesets] guests_list length: #{length(guests_list)}"
    )

    Ysc.Logging.debug(
      "[build_guest_changesets] guests_list: #{inspect(guests_list)}"
    )

    if length(guests_list) != total_expected do
      error_msg =
        "Expected #{total_expected} guests, got #{length(guests_list)}"

      Ysc.Logging.error("[build_guest_changesets] #{error_msg}")
      {:error, error_msg}
    else
      # Validate that exactly one guest is marked as booking user
      # Normalize boolean values (form submissions send "true"/"false" as strings)
      booking_user_count =
        Enum.count(guests_list, fn guest ->
          is_booking_user =
            case Map.get(guest, "is_booking_user") ||
                   Map.get(guest, :is_booking_user) do
              "true" -> true
              "false" -> false
              true -> true
              false -> false
              _ -> false
            end

          is_booking_user == true
        end)

      Ysc.Logging.debug(
        "[build_guest_changesets] booking_user_count: #{booking_user_count}"
      )

      if booking_user_count != 1 do
        error_msg =
          "Exactly one guest must be marked as the booking user, got #{booking_user_count}"

        Ysc.Logging.error("[build_guest_changesets] #{error_msg}")
        {:error, error_msg}
      else
        # Validate child count
        # Normalize boolean values (form submissions send "true"/"false" as strings)
        child_count =
          Enum.count(guests_list, fn guest ->
            is_child =
              case Map.get(guest, "is_child") || Map.get(guest, :is_child) do
                "true" -> true
                "false" -> false
                true -> true
                false -> false
                _ -> false
              end

            is_child == true
          end)

        Ysc.Logging.debug(
          "[build_guest_changesets] child_count: #{child_count}"
        )

        if child_count != children_count do
          error_msg = "Expected #{children_count} children, got #{child_count}"
          Ysc.Logging.error("[build_guest_changesets] #{error_msg}")
          {:error, error_msg}
        else
          # Build changesets
          changesets =
            Enum.map(guests_list, fn guest_attrs ->
              attrs_with_booking =
                Map.merge(guest_attrs, %{"booking_id" => booking.id})

              Ysc.Bookings.BookingGuest.changeset(
                %Ysc.Bookings.BookingGuest{},
                attrs_with_booking
              )
            end)

          Ysc.Logging.debug(
            "[build_guest_changesets] Built #{length(changesets)} changesets"
          )

          Ysc.Logging.debug(
            "[build_guest_changesets] Changesets valid status: #{inspect(Enum.map(changesets, & &1.valid?))}"
          )

          # Check if all changesets are valid
          invalid_changesets =
            Enum.filter(changesets, fn changeset -> not changeset.valid? end)

          if invalid_changesets != [] do
            Ysc.Logging.error(
              "[build_guest_changesets] Found #{length(invalid_changesets)} invalid changesets"
            )

            {:error, invalid_changesets}
          else
            Ysc.Logging.debug(
              "[build_guest_changesets] All changesets are valid"
            )

            {:ok, changesets}
          end
        end
      end
    end
  end

  defp checkout_guest_info_intro(booking) do
    room_names =
      if Ecto.assoc_loaded?(booking.rooms) && booking.rooms != [],
        do: Enum.map_join(booking.rooms, ", ", & &1.name),
        else: "your selected room"

    adults = booking.guests_count || 1
    children = booking.children_count || 0

    children_text =
      if children > 0 do
        " and #{children} #{if children == 1, do: "child", else: "children"}"
      else
        ""
      end

    "You are booking #{room_names} for #{adults} #{if adults == 1, do: "adult", else: "adults"}#{children_text}."
  end

  defp checkout_guest_info_submit_label(true), do: "Continue to confirmation"
  defp checkout_guest_info_submit_label(false), do: "Continue to Payment"

  defp save_guests(booking, guest_changesets) when is_list(guest_changesets) do
    # Delete existing guests first (in case of re-submission)
    Bookings.delete_booking_guests(booking.id)

    # Create all guests atomically
    # Convert changesets to attrs maps, preserving order_index
    guests_attrs =
      Enum.map(guest_changesets, fn changeset ->
        changes = Ecto.Changeset.apply_changes(changeset)
        order_index = Map.get(changes, :order_index) || 0

        # Convert struct to map with string keys for consistency
        attrs_map =
          changes
          |> Map.from_struct()
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          # Remove order_index from attrs since it's passed as tuple key
          |> Map.delete("order_index")

        {order_index, attrs_map}
      end)

    case Bookings.create_booking_guests(booking.id, guests_attrs) do
      {:ok, guests} -> {:ok, guests}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp leave_checkout_confirm do
    "Leave checkout and release these dates? Your booking is not confirmed until payment is complete."
  end
end
