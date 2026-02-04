defmodule YscWeb.BookingCheckoutLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  import Ecto.Query
  require Logger

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
    schedule_expiration_check(socket)
    user = socket.assigns.current_user
    timezone = get_timezone_from_connect_params(socket)

    result =
      with :ok <- validate_user_signed_in(user),
           {:ok, booking} <- load_booking(booking_id, user),
           booking <- preload_booking_rooms(booking),
           :ok <- validate_booking_status(booking),
           :ok <- validate_booking_not_expired(booking) do
        initialize_checkout(socket, booking, user, timezone)
      end

    case result do
      {:ok, _socket} = reply ->
        reply

      {:error, {:redirect, path, message}} ->
        {:ok, socket |> put_flash(:error, message) |> redirect(to: path)}
    end
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

  defp load_booking(booking_id, user) do
    # SECURITY: Filter by user_id in the database query to prevent unauthorized access
    # This ensures we only fetch bookings that belong to the current user
    booking_query =
      from(b in Booking,
        where: b.id == ^booking_id and b.user_id == ^user.id
      )

    case Repo.one(booking_query) do
      nil -> {:error, {:redirect, ~p"/", "Booking not found."}}
      booking -> {:ok, booking}
    end
  end

  defp preload_booking_rooms(booking) do
    Repo.preload(booking, [:rooms, rooms: :room_category])
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
        "This booking has expired and is no longer available for payment."}}
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

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Failed to calculate price: #{inspect(reason)}")
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
    booking = Repo.preload(booking, [:user, :booking_guests])
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
        is_expired: is_expired,
        timezone: timezone,
        checkout_step: checkout_step,
        guest_info_form: guest_info_form,
        guest_info_errors: %{},
        family_members: family_members,
        other_family_members: other_family_members,
        guests_for_me: %{},
        selected_family_members_for_guests: %{},
        show_price_details: false
      )

    if is_expired do
      {:ok,
       assign(socket,
         payment_error:
           "This booking has expired and is no longer available for payment."
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
    case create_payment_intent(booking, total_price, user) do
      {:ok, payment_intent} ->
        {:ok,
         assign(socket, payment_intent: payment_intent, show_payment_form: true)}

      {:error, reason} ->
        {:ok,
         assign(socket,
           payment_error: "Failed to initialize payment: #{reason}"
         )}
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

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
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
                <%= atom_to_readable(@booking.property) %> Cabin
              </h2>
              <p class="text-zinc-500 mt-1">
                <%= format_date_short(@booking.checkin_date, @timezone) %> — <%= format_date_short(
                  @booking.checkout_date,
                  @timezone
                ) %>, <%= Calendar.strftime(@booking.checkout_date, "%Y") %> (<%= Date.diff(
                  @booking.checkout_date,
                  @booking.checkin_date
                ) %> <%= if Date.diff(
                              @booking.checkout_date,
                              @booking.checkin_date
                            ) == 1,
                            do: "night",
                            else: "nights" %>)
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm">
                <span class="text-zinc-600">
                  <%= @booking.guests_count %> <%= if @booking.guests_count == 1,
                    do: "adult",
                    else: "adults" %>
                  <%= if @booking.children_count && @booking.children_count > 0 do %>
                    , <%= @booking.children_count %> <%= if @booking.children_count ==
                                                              1,
                                                            do: "child",
                                                            else: "children" %>
                  <% end %>
                </span>
                <%= if @booking.booking_mode == :room && Ecto.assoc_loaded?(@booking.rooms) &&
                      length(@booking.rooms) > 0 do %>
                  <span class="text-zinc-400">•</span>
                  <span class="text-zinc-600">
                    <%= Enum.map(@booking.rooms, & &1.name) |> Enum.join(", ") %>
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Guest Information Section (for room bookings) -->
          <div
            :if={@checkout_step == :guest_info}
            class="bg-white rounded-lg border border-zinc-200 p-8 shadow-sm"
          >
            <h2 class="text-xl font-bold mb-2">Guest Information</h2>
            <%!-- Capacity Summary --%>
            <% room_names =
              if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0,
                do: Enum.map(@booking.rooms, & &1.name) |> Enum.join(", "),
                else: "your selected room" %>
            <p class="text-sm text-zinc-600 mb-4">
              You are booking <%= room_names %> for <%= @booking.guests_count || 1 %> <%= if (@booking.guests_count ||
                                                                                                1) ==
                                                                                               1,
                                                                                             do:
                                                                                               "adult",
                                                                                             else:
                                                                                               "adults" %>
              <%= if @booking.children_count && @booking.children_count > 0 do %>
                and <%= @booking.children_count %> <%= if @booking.children_count ==
                                                            1,
                                                          do: "child",
                                                          else: "children" %>
              <% end %>.
            </p>
            <%!-- Booking Representative Header --%>
            <% booking_user_guest =
              if @guest_info_form do
                Enum.find(@guest_info_form.source, fn {_, guest_data} ->
                  Map.get(guest_data, "is_booking_user") == true
                end)
              end %>
            <%= if booking_user_guest do %>
              <% {_, booking_user_data} = booking_user_guest %>
              <div class="mb-6 p-4 bg-blue-50 border-l-4 border-blue-500 rounded-r-lg">
                <div class="flex items-start gap-3">
                  <div class="flex-shrink-0 w-10 h-10 rounded-full overflow-hidden ring-2 ring-blue-200">
                    <%= if assigns[:current_user] do %>
                      <.user_avatar_image
                        email={assigns[:current_user].email || ""}
                        user_id={to_string(assigns[:current_user].id)}
                        country={
                          assigns[:current_user].most_connected_country || "SE"
                        }
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <.icon
                        name="hero-user-circle"
                        class="w-full h-full text-blue-600 p-2"
                      />
                    <% end %>
                  </div>
                  <div class="flex-1">
                    <div class="flex items-center gap-2 mb-1">
                      <p class="text-sm font-semibold text-blue-900">
                        Booking Representative
                      </p>
                      <span class="px-2 py-0.5 bg-blue-100 text-blue-700 text-xs font-bold rounded">
                        Required
                      </span>
                    </div>
                    <p class="text-sm text-blue-700 font-medium mb-2">
                      <%= Map.get(booking_user_data, "first_name", "") %> <%= Map.get(
                        booking_user_data,
                        "last_name",
                        ""
                      ) %>
                    </p>
                    <p class="text-xs text-blue-600">
                      You as the booking member must be present. You are already included in the total count above.
                    </p>
                  </div>
                </div>
              </div>
            <% end %>
            <%!-- Error Summary (visible) --%>
            <%= if map_size(@guest_info_errors || %{}) > 0 do %>
              <% error_count =
                @guest_info_errors
                |> Enum.reject(fn {key, _} -> key == :general end)
                |> Enum.count() %>
              <%= if error_count > 0 do %>
                <div
                  id="guest-errors-summary"
                  role="alert"
                  aria-live="polite"
                  aria-atomic="true"
                  class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
                >
                  <p class="text-sm font-semibold text-red-800">
                    <%= error_count %> <%= if error_count == 1,
                      do: "guest is",
                      else: "guests are" %> missing required information.
                  </p>
                </div>
              <% end %>
            <% end %>
            <!-- General Errors -->
            <div
              :if={@guest_info_errors[:general]}
              class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
              role="alert"
            >
              <p class="text-sm text-red-800">
                <%= @guest_info_errors[:general] %>
              </p>
            </div>
            <!-- Guest Information Form -->
            <form
              phx-change="validate-guest-info"
              phx-submit="save-guest-info"
              phx-debounce="300"
              id="guest-info-form"
            >
              <div class="space-y-6">
                <%= if @guest_info_form do %>
                  <%!-- Filter to only show guests up to the expected total --%>
                  <% expected_total =
                    (@booking.guests_count || 1) + (@booking.children_count || 0) %>
                  <% guest_entries =
                    @guest_info_form.source
                    |> Enum.map(fn {index_str, guest_data} ->
                      {String.to_integer(index_str), {index_str, guest_data}}
                    end)
                    |> Enum.sort_by(fn {order_index, _} -> order_index end)
                    |> Enum.take(expected_total)
                    |> Enum.map(fn {_order_index, {index_str, guest_data}} ->
                      {index_str, guest_data}
                    end) %>
                  <%!-- Separate booking user from other guests --%>
                  <% {booking_user_entries, non_booking_guests} =
                    Enum.split_with(guest_entries, fn {_, guest_data} ->
                      Map.get(guest_data, "is_booking_user") == true
                    end) %>
                  <%!-- Hidden inputs for booking user (shown in header, but data still needs to be submitted) --%>
                  <%= for {index_str, guest_data} <- booking_user_entries do %>
                    <input
                      type="hidden"
                      name={"guests[#{index_str}][first_name]"}
                      value={Map.get(guest_data, "first_name", "")}
                    />
                    <input
                      type="hidden"
                      name={"guests[#{index_str}][last_name]"}
                      value={Map.get(guest_data, "last_name", "")}
                    />
                    <input
                      type="hidden"
                      name={"guests[#{index_str}][is_child]"}
                      value="false"
                    />
                    <input
                      type="hidden"
                      name={"guests[#{index_str}][is_booking_user]"}
                      value="true"
                    />
                    <input
                      type="hidden"
                      name={"guests[#{index_str}][order_index]"}
                      value={Map.get(guest_data, "order_index", 0)}
                    />
                  <% end %>
                  <%= for {index_str, guest_data} <- non_booking_guests do %>
                    <% index = String.to_integer(index_str) %>
                    <% is_booking_user =
                      Map.get(guest_data, "is_booking_user") == true %>
                    <% is_child = Map.get(guest_data, "is_child") == true %>
                    <% selected_family_members =
                      @selected_family_members_for_guests || %{} %>
                    <% selected_family_member_id =
                      Map.get(selected_family_members, index_str) %>
                    <% selected_family_member =
                      if selected_family_member_id,
                        do:
                          Enum.find(@other_family_members || [], fn u ->
                            to_string(u.id) == to_string(selected_family_member_id)
                          end),
                        else: nil %>
                    <% has_selected_family_member =
                      not is_nil(selected_family_member) %>
                    <% first_name =
                      cond do
                        is_booking_user ->
                          Map.get(guest_data, "first_name", "")

                        has_selected_family_member ->
                          selected_family_member.first_name || ""

                        true ->
                          Map.get(guest_data, "first_name", "")
                      end %>
                    <% last_name =
                      cond do
                        is_booking_user ->
                          Map.get(guest_data, "last_name", "")

                        has_selected_family_member ->
                          selected_family_member.last_name || ""

                        true ->
                          Map.get(guest_data, "last_name", "")
                      end %>
                    <div class={[
                      "flex items-start gap-4 p-4 rounded-r-lg shadow-sm",
                      if(is_child,
                        do: "bg-white border-l-4 border-green-500",
                        else: "bg-white border-l-4 border-blue-500"
                      )
                    ]}>
                      <div class={[
                        "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm",
                        if(is_child,
                          do: "bg-green-100 text-green-600",
                          else: "bg-blue-100 text-blue-600"
                        )
                      ]}>
                        <%= index %>
                      </div>
                      <div class="flex-1 space-y-3">
                        <div class="flex justify-between items-center">
                          <h3 class="font-bold text-zinc-800">
                            <%= if is_child do %>
                              Child Guest
                            <% else %>
                              Adult Guest
                            <% end %>
                          </h3>
                          <%= if !is_child && length(@other_family_members || []) > 0 do %>
                            <%!-- Family Member Selection Dropdown (only for adults) --%>
                            <select
                              id={"guest-#{index_str}-attendee-select"}
                              name={"guest-#{index_str}-attendee-select"}
                              phx-change="select-guest-attendee"
                              phx-debounce="100"
                              phx-value-guest-index={index_str}
                              value={
                                cond do
                                  has_selected_family_member ->
                                    "family_#{selected_family_member.id}"

                                  true ->
                                    "other"
                                end
                              }
                              class="text-xs border-none bg-zinc-100 rounded px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            >
                              <%= if length(@other_family_members) > 0 do %>
                                <optgroup label="Family Members">
                                  <%= for family_member <- @other_family_members do %>
                                    <option
                                      value={"family_#{family_member.id}"}
                                      selected={
                                        has_selected_family_member &&
                                          selected_family_member.id ==
                                            family_member.id
                                      }
                                    >
                                      <%= family_member.first_name %> <%= family_member.last_name %>
                                    </option>
                                  <% end %>
                                </optgroup>
                              <% end %>
                              <option
                                value="other"
                                selected={!has_selected_family_member}
                              >
                                Someone else (Enter details)
                              </option>
                            </select>
                          <% end %>
                        </div>
                        <%!-- Show badge when family member selected (only for adults), otherwise show form inputs --%>
                        <%= if !is_child && has_selected_family_member do %>
                          <div class="inline-flex items-center gap-2 px-3 py-1.5 bg-green-50 border border-green-200 rounded-lg">
                            <.icon
                              name="hero-check-circle"
                              class="w-5 h-5 text-green-600"
                            />
                            <span class="text-xs font-semibold text-green-800">
                              Applied: <%= selected_family_member.first_name %> <%= selected_family_member.last_name %>
                            </span>
                          </div>
                        <% else %>
                          <div class="grid grid-cols-2 gap-2">
                            <div class="relative">
                              <input
                                type="text"
                                id={"guest-#{index_str}-first-name"}
                                name={"guests[#{index_str}][first_name]"}
                                value={first_name}
                                required={true}
                                placeholder="First Name"
                                autocapitalize="words"
                                autocomplete="given-name"
                                phx-change="validate-guest-info"
                                phx-debounce="300"
                                class={[
                                  "w-full px-3 py-2 border rounded focus:ring-2 focus:ring-blue-500 focus:border-blue-500 placeholder:text-zinc-400",
                                  if(
                                    @guest_info_errors[index_str] &&
                                      @guest_info_errors[index_str][:first_name],
                                    do: "border-red-300 bg-red-50",
                                    else:
                                      if(first_name != "",
                                        do: "border-green-300 bg-green-50",
                                        else: "border-zinc-300 bg-white"
                                      )
                                  )
                                ]}
                              />
                              <%= if first_name != "" && (!@guest_info_errors[index_str] || !@guest_info_errors[index_str][:first_name]) do %>
                                <div class="absolute right-2 top-1/2 -translate-y-1/2">
                                  <.icon
                                    name="hero-check-circle"
                                    class="w-4 h-4 text-green-600"
                                  />
                                </div>
                              <% end %>
                            </div>
                            <div class="relative">
                              <input
                                type="text"
                                id={"guest-#{index_str}-last-name"}
                                name={"guests[#{index_str}][last_name]"}
                                value={last_name}
                                required={true}
                                placeholder="Last Name"
                                autocapitalize="words"
                                autocomplete="family-name"
                                phx-change="validate-guest-info"
                                phx-debounce="300"
                                class={[
                                  "w-full px-3 py-2 border rounded focus:ring-2 focus:ring-blue-500 focus:border-blue-500 placeholder:text-zinc-400",
                                  if(
                                    @guest_info_errors[index_str] &&
                                      @guest_info_errors[index_str][:last_name],
                                    do: "border-red-300 bg-red-50",
                                    else:
                                      if(last_name != "",
                                        do: "border-green-300 bg-green-50",
                                        else: "border-zinc-300 bg-white"
                                      )
                                  )
                                ]}
                              />
                              <%= if last_name != "" && (!@guest_info_errors[index_str] || !@guest_info_errors[index_str][:last_name]) do %>
                                <div class="absolute right-2 top-1/2 -translate-y-1/2">
                                  <.icon
                                    name="hero-check-circle"
                                    class="w-4 h-4 text-green-600"
                                  />
                                </div>
                              <% end %>
                            </div>
                          </div>
                          <%= if @guest_info_errors[index_str] do %>
                            <div class="text-xs text-red-600 space-y-0.5">
                              <%= if @guest_info_errors[index_str][:first_name] do %>
                                <p>
                                  First name: <%= Enum.join(
                                    @guest_info_errors[index_str][:first_name],
                                    ", "
                                  ) %>
                                </p>
                              <% end %>
                              <%= if @guest_info_errors[index_str][:last_name] do %>
                                <p>
                                  Last name: <%= Enum.join(
                                    @guest_info_errors[index_str][:last_name],
                                    ", "
                                  ) %>
                                </p>
                              <% end %>
                            </div>
                          <% end %>
                        <% end %>
                      </div>
                      <!-- Hidden fields for guest metadata -->
                      <input
                        type="hidden"
                        name={"guests[#{index_str}][is_child]"}
                        value={if is_child, do: "true", else: "false"}
                      />
                      <input
                        type="hidden"
                        name={"guests[#{index_str}][is_booking_user]"}
                        value={if is_booking_user, do: "true", else: "false"}
                      />
                      <input
                        type="hidden"
                        name={"guests[#{index_str}][order_index]"}
                        value={index}
                      />
                    </div>
                  <% end %>
                <% end %>
              </div>

              <div class="pt-6 border-t border-zinc-100 mt-6 space-y-4">
                <div class="flex flex-col sm:flex-row gap-4">
                  <.button
                    type="submit"
                    phx-disable-with="Processing..."
                    class="flex-1 w-full text-lg py-3.5"
                    disabled={!all_guests_valid?(@guest_info_form, @booking)}
                  >
                    <span class="text-lg font-semibold">Continue to Payment</span>
                    <.icon name="hero-arrow-right" class="w-5 h-5 -mt-1 ms-1" />
                  </.button>
                  <button
                    type="button"
                    phx-click="cancel-booking"
                    phx-disable-with="Cancelling..."
                    phx-confirm="Are you sure you want to cancel this booking? The availability will be released immediately."
                    class="px-6 py-3.5 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-300 rounded-lg hover:bg-zinc-50 transition-colors"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </form>
          </div>
          <!-- Payment Section -->
          <div
            :if={@checkout_step == :payment}
            class="bg-white rounded-lg border border-zinc-200 p-8 shadow-sm"
          >
            <h2 class="text-xl font-bold mb-6">Secure Payment</h2>
            <!-- Payment Error -->
            <div
              :if={@payment_error}
              class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
            >
              <p class="text-sm text-red-800"><%= @payment_error %></p>
            </div>
            <!-- Payment Form -->
            <div :if={@show_payment_form && @payment_intent && !@is_expired}>
              <div
                id="stripe-payment-container"
                phx-hook="StripeElements"
                data-client-secret={@payment_intent.client_secret}
                data-booking-id={@booking.id}
              >
                <div id="payment-element" class="mb-6 hidden">
                  <!-- Stripe Elements will mount here -->
                </div>
                <div id="payment-message" class="hidden mt-4"></div>
              </div>

              <div class="pt-6 border-t border-zinc-100 space-y-4">
                <div class="flex flex-col sm:flex-row gap-4">
                  <.button
                    id="submit-payment"
                    type="button"
                    class="flex-1 w-full text-lg py-3.5"
                    disabled={@is_expired}
                  >
                    <.icon name="hero-lock-closed" class="w-5 h-5 -mt-1 me-1" />
                    <span class="text-lg font-semibold">
                      Pay <%= MoneyHelper.format_money!(@total_price) %> Securely
                    </span>
                  </.button>
                  <button
                    type="button"
                    phx-click="cancel-booking"
                    phx-disable-with="Cancelling..."
                    phx-confirm="Are you sure you want to cancel this booking? The availability will be released immediately."
                    class="px-6 py-3.5 text-sm font-medium text-zinc-600 hover:text-zinc-900 border border-zinc-300 rounded-lg hover:bg-zinc-50 transition-colors"
                  >
                    Cancel
                  </button>
                </div>
                <%!-- Payment Icons --%>
                <div class="flex items-center justify-center gap-3 pt-2">
                  <span class="text-xs text-zinc-500 uppercase tracking-wide">
                    Secure Payment
                  </span>
                  <div class="flex items-center gap-2">
                    <%!-- Visa Logo --%>
                    <svg
                      class="w-10 h-6 opacity-70"
                      viewBox="0 0 40 24"
                      fill="none"
                      aria-label="Visa"
                    >
                      <rect width="40" height="24" rx="2" fill="#1A1F71" />
                      <path
                        d="M16.5 8.5h-2.5l-1.5 7h2.5l1.5-7zm8.5 4.5c0-1.5-2-2.5-2-3.5 0-.5.5-1 1.5-1 .5 0 1 .2 1.5.5l.5-2.5c-.5-.2-1-.5-2-.5-2.5 0-4 1.5-4 3.5 0 1.5 1.5 2.5 2.5 3 1 .5 1.5 1 1.5 1.5 0 1-1 1.5-2 1.5-.5 0-1-.2-1.5-.5l-.5 2.5c.5.2 1 .5 2 .5 2.5 0 4.5-1.5 4.5-3.5zm-6-4.5l-2 7h-2.5l2-7h2.5z"
                        fill="#F79E1B"
                      />
                    </svg>
                    <%!-- Mastercard Logo --%>
                    <svg
                      class="w-10 h-6 opacity-70"
                      viewBox="0 0 40 24"
                      fill="none"
                      aria-label="Mastercard"
                    >
                      <rect width="40" height="24" rx="2" fill="#EB001B" />
                      <circle cx="15" cy="12" r="4" fill="#F79E1B" />
                      <circle cx="25" cy="12" r="4" fill="#FF5F00" />
                    </svg>
                    <%!-- Stripe Logo --%>
                    <svg
                      class="w-10 h-6 opacity-70"
                      viewBox="0 0 40 24"
                      fill="none"
                      aria-label="Stripe"
                    >
                      <rect width="40" height="24" rx="2" fill="#635BFF" />
                      <path
                        d="M17 10.5c0 .8-.6 1.4-1.4 1.4h-2.2v2.8h-1.3V9.1h3.5c.8 0 1.4.6 1.4 1.4zm-1.4 0c0-.3-.2-.5-.5-.5h-2.2v1h2.2c.3 0 .5-.2.5-.5zm4.4 4.2h-1.3v-5.6h1.3v5.6zm3.5 0h-1.3v-3.9c0-.5-.3-.8-.8-.8s-.8.3-.8.8v3.9h-1.3v-3.9c0-1.1.9-2 2-2s2 .9 2 2v3.9zm5.5-2.1c0-1.1-.9-2-2-2h-1.5v5.6h1.3v-2.1h.2l1.5 2.1h1.6l-1.7-2.3c.8-.3 1.2-1 1.2-1.9zm-2.2 0c0 .4.3.7.7.7h1.3v-1.4h-1.3c-.4 0-.7.3-.7.7z"
                        fill="white"
                      />
                    </svg>
                  </div>
                </div>
              </div>
            </div>
            <!-- Expired Booking Message -->
            <div
              :if={assigns[:is_expired] && @is_expired}
              class="p-6 bg-red-50 border border-red-200 rounded-lg"
            >
              <p class="text-sm font-semibold text-red-800 mb-2">Booking Expired</p>
              <p class="text-sm text-red-700 mb-4">
                This booking has expired and is no longer available for payment. Please create a new booking.
              </p>
              <a
                href={get_property_redirect_path(@booking.property)}
                class="inline-block text-sm font-medium text-red-800 hover:text-red-900 underline"
              >
                Create New Booking →
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
            phx-hook="CountdownColor"
            data-expires-at={DateTime.to_iso8601(@booking.hold_expires_at)}
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
                Hold Expires
              </span>
            </div>
            <p class={[
              "text-sm leading-relaxed",
              if(remaining_minutes(@booking.hold_expires_at) < 5,
                do: "text-rose-700",
                else: "text-blue-700"
              )
            ]}>
              Complete payment within
              <span
                class="font-bold tabular-nums"
                id="hold-countdown"
                phx-hook="HoldCountdown"
                data-expires-at={DateTime.to_iso8601(@booking.hold_expires_at)}
                data-timezone={@timezone}
              >
                <%= calculate_remaining_time(@booking.hold_expires_at) %>
              </span>
              to secure your booking.
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
                <%= render_price_breakdown_sidebar(assigns) %>
              <% end %>
              <div class="pt-4 border-t border-zinc-700 flex justify-between items-baseline">
                <span class="text-lg font-bold">Total</span>
                <span class="text-3xl font-black text-blue-400">
                  <%= MoneyHelper.format_money!(@total_price) %>
                </span>
              </div>
            </div>
          </div>
          <!-- What Happens Next -->
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h3 class="text-lg font-bold text-zinc-900 mb-4">What Happens Next?</h3>
            <ol class="space-y-3 text-sm text-zinc-600">
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  1
                </span>
                <span>Complete your secure payment above</span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  2
                </span>
                <span>Receive instant confirmation email with booking details</span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  3
                </span>
                <span>
                  Get cabin access information (door code or key instructions) via email before check-in
                </span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  4
                </span>
                <span>
                  Access your booking details and manage your reservation anytime
                </span>
              </li>
            </ol>
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
              <%= MoneyHelper.format_money!(@total_price) %>
            </p>
          </div>
          <.button
            type="submit"
            form="guest-info-form"
            phx-disable-with="Processing..."
            class="flex-1"
            disabled={!all_guests_valid?(@guest_info_form, @booking)}
          >
            Continue to Payment<.icon
              name="hero-arrow-right"
              class="w-5 h-5 -mt-1 ms-1"
            />
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
    require Logger
    Logger.debug("[validate-guest-info] Event received")

    Logger.debug(
      "[validate-guest-info] Received guest_params: #{inspect(guest_params)}"
    )

    # Merge family member selections into guest_params before validation
    selected_family_members =
      socket.assigns.selected_family_members_for_guests || %{}

    other_family_members = socket.assigns.other_family_members || []

    Logger.debug(
      "[validate-guest-info] selected_family_members: #{inspect(selected_family_members)}"
    )

    Logger.debug(
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

    Logger.debug(
      "[validate-guest-info] updated_guest_params after family member merge: #{inspect(updated_guest_params)}"
    )

    # Find and include the booking user entry from form source (it's not in the submitted params)
    guest_info_form =
      socket.assigns.guest_info_form || to_form(%{}, as: "guests")

    Logger.debug(
      "[validate-guest-info] guest_info_form.source keys: #{inspect(Map.keys(guest_info_form.source))}"
    )

    Logger.debug(
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

    Logger.debug(
      "[validate-guest-info] After merging form source, updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Logger.debug(
      "[validate-guest-info] Final updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Logger.debug(
      "[validate-guest-info] Final updated_guest_params: #{inspect(updated_guest_params)}"
    )

    # Update the form with new params to preserve user input
    updated_form = to_form(updated_guest_params, as: "guests")

    Logger.debug(
      "[validate-guest-info] Building changesets for booking: #{socket.assigns.booking.id}"
    )

    Logger.debug(
      "[validate-guest-info] Booking guests_count: #{socket.assigns.booking.guests_count}, children_count: #{socket.assigns.booking.children_count}"
    )

    case build_guest_changesets(socket.assigns.booking, updated_guest_params) do
      {:ok, changesets} ->
        Logger.debug(
          "[validate-guest-info] Built #{length(changesets)} changesets"
        )

        Logger.debug(
          "[validate-guest-info] Changesets valid status: #{inspect(Enum.map(changesets, & &1.valid?))}"
        )

        # Check if all changesets are valid
        all_valid = Enum.all?(changesets, & &1.valid?)
        Logger.debug("[validate-guest-info] All valid: #{all_valid}")

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
                  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                    if is_binary(msg) do
                      Enum.reduce(opts, msg, fn {key, value}, acc ->
                        String.replace(acc, "%{#{key}}", to_string(value))
                      end)
                    else
                      to_string(msg)
                    end
                  end)

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
        Logger.error(
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
              changeset_errors =
                Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                  if is_binary(msg) do
                    Enum.reduce(opts, msg, fn {key, value}, acc ->
                      String.replace(acc, "%{#{key}}", to_string(value))
                    end)
                  else
                    to_string(msg)
                  end
                end)

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
    require Logger

    Logger.debug(
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

    Logger.debug(
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

              Logger.debug(
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

              Logger.debug(
                "[select-guest-attendee] Form data for index #{guest_index}: #{inspect(form_data)}"
              )

              updated_form_source =
                Map.put(guest_info_form.source, guest_index, form_data)

              updated_form = %{guest_info_form | source: updated_form_source}

              Logger.debug(
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

      Logger.debug(
        "[select-guest-attendee] Triggering validation with params: #{inspect(validate_params)}"
      )

      Logger.debug(
        "[select-guest-attendee] Form source before validation: #{inspect(updated_form.source)}"
      )

      Logger.debug(
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
          Logger.debug(
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

      Logger.debug(
        "[select-guest-attendee] After validation - selected_family_members: #{inspect(final_socket.assigns.selected_family_members_for_guests)}"
      )

      Logger.debug(
        "[select-guest-attendee] Form source after validation: #{inspect(final_socket.assigns.guest_info_form.source)}"
      )

      {:noreply, final_socket}
    else
      Logger.warning(
        "select-guest-attendee: Missing guest_index or selected_value. guest_index=#{inspect(guest_index)}, selected_value=#{inspect(selected_value)}, all_params=#{inspect(params)}"
      )

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save-guest-info", %{"guests" => guest_params}, socket) do
    require Logger
    Logger.debug("[save-guest-info] Event received")

    Logger.debug(
      "[save-guest-info] Received guest_params: #{inspect(guest_params)}"
    )

    # Merge family member selections into guest_params before saving
    selected_family_members =
      socket.assigns.selected_family_members_for_guests || %{}

    other_family_members = socket.assigns.other_family_members || []

    Logger.debug(
      "[save-guest-info] selected_family_members: #{inspect(selected_family_members)}"
    )

    Logger.debug(
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

    Logger.debug(
      "[save-guest-info] updated_guest_params after family member merge: #{inspect(updated_guest_params)}"
    )

    # Find and include the booking user entry from form source (it's not in the submitted params)
    guest_info_form =
      socket.assigns.guest_info_form || to_form(%{}, as: "guests")

    Logger.debug(
      "[save-guest-info] guest_info_form.source keys: #{inspect(Map.keys(guest_info_form.source))}"
    )

    Logger.debug(
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

    Logger.debug(
      "[save-guest-info] After merging form source, updated_guest_params keys: #{inspect(Map.keys(updated_guest_params))}"
    )

    Logger.debug(
      "[save-guest-info] Final updated_guest_params: #{inspect(updated_guest_params)}"
    )

    Logger.debug(
      "[save-guest-info] Building changesets for booking: #{socket.assigns.booking.id}"
    )

    Logger.debug(
      "[save-guest-info] Booking guests_count: #{socket.assigns.booking.guests_count}, children_count: #{socket.assigns.booking.children_count}"
    )

    case build_guest_changesets(socket.assigns.booking, updated_guest_params) do
      {:ok, changesets} ->
        Logger.debug("[save-guest-info] Built #{length(changesets)} changesets")

        Logger.debug(
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

            # Create payment intent now that guests are saved
            user = socket.assigns.current_user

            case create_payment_intent(
                   booking,
                   socket.assigns.total_price,
                   user
                 ) do
              {:ok, payment_intent} ->
                {:noreply,
                 socket
                 |> assign(
                   booking: booking,
                   checkout_step: :payment,
                   payment_intent: payment_intent,
                   show_payment_form: true,
                   guest_info_form: nil,
                   guest_info_errors: %{}
                 )
                 |> put_flash(
                   :info,
                   "Guest information saved. Please complete payment."
                 )}

              {:error, reason} ->
                {:noreply,
                 assign(socket,
                   payment_error: "Failed to initialize payment: #{reason}",
                   checkout_step: :payment
                 )}
            end

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                if is_binary(msg) do
                  Enum.reduce(opts, msg, fn {key, value}, acc ->
                    String.replace(acc, "%{#{key}}", to_string(value))
                  end)
                else
                  to_string(msg)
                end
              end)

            {:noreply,
             assign(socket,
               guest_info_errors: %{general: errors}
             )}
        end

      {:error, error_message} when is_binary(error_message) ->
        Logger.error(
          "[save-guest-info] Error building changesets: #{error_message}"
        )

        {:noreply,
         assign(socket,
           guest_info_errors: %{general: error_message}
         )
         |> put_flash(:error, error_message)}

      {:error, invalid_changesets} when is_list(invalid_changesets) ->
        errors =
          Enum.with_index(invalid_changesets)
          |> Enum.reduce(%{}, fn {changeset, index}, acc ->
            if changeset.valid? do
              acc
            else
              changeset_errors =
                Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
                  if is_binary(msg) do
                    Enum.reduce(opts, msg, fn {key, value}, acc ->
                      String.replace(acc, "%{#{key}}", to_string(value))
                    end)
                  else
                    to_string(msg)
                  end
                end)

              Map.put(acc, Integer.to_string(index), changeset_errors)
            end
          end)

        {:noreply,
         assign(socket, guest_info_errors: errors)
         |> put_flash(:error, "Please fix the errors below.")}
    end
  end

  def handle_event("save-guest-info", _params, socket) do
    {:noreply,
     assign(socket,
       guest_info_errors: %{general: "No guest information provided"}
     )
     |> put_flash(:error, "Please provide guest information.")}
  end

  @impl true
  def handle_event("cancel-booking", _params, socket) do
    case BookingLocker.release_hold(socket.assigns.booking.id) do
      {:ok, _canceled_booking} ->
        property = socket.assigns.booking.property
        redirect_path = get_property_redirect_path(property)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Your booking has been canceled and the availability has been released."
         )
         |> redirect(to: redirect_path)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to cancel booking: #{inspect(reason)}. Please try again or contact support."
         )}
    end
  end

  @impl true
  def handle_event("payment-redirect-started", _params, socket) do
    # Acknowledge that the payment redirect has started (no action needed)
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "payment-success",
        %{"payment_intent_id" => payment_intent_id},
        socket
      ) do
    # Check if booking has expired before processing payment
    if booking_expired?(socket.assigns.booking) do
      {:noreply,
       socket
       |> assign(
         payment_error:
           "This booking has expired and is no longer available for payment.",
         show_payment_form: false
       )
       |> put_flash(
         :error,
         "This booking has expired. Please create a new booking."
       )}
    else
      case process_payment_success(socket.assigns.booking, payment_intent_id) do
        {:ok, booking} ->
          {:noreply,
           socket
           |> put_flash(:info, "Payment successful! Your booking is confirmed.")
           |> push_navigate(
             to: ~p"/bookings/#{booking.id}/receipt?confetti=true"
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             payment_error: "Failed to process payment: #{inspect(reason)}"
           )}
      end
    end
  end

  @impl true
  def handle_info(:check_booking_expiration, socket) do
    # Check if booking has expired
    if booking_expired?(socket.assigns.booking) do
      # Reload booking to get latest status
      booking =
        Repo.get!(Booking, socket.assigns.booking.id)
        |> Repo.preload([:user, :rooms])

      {:noreply,
       socket
       |> assign(
         booking: booking,
         is_expired: true,
         show_payment_form: false,
         payment_error:
           "This booking has expired and is no longer available for payment."
       )
       |> put_flash(
         :error,
         "This booking has expired. Please create a new booking."
       )}
    else
      # Schedule next check in 5 seconds
      Process.send_after(self(), :check_booking_expiration, 5_000)
      {:noreply, socket}
    end
  end

  ## Private Functions

  defp calculate_booking_price(booking) do
    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    case booking.booking_mode do
      :buyout ->
        case Bookings.calculate_booking_price(
               booking.property,
               booking.checkin_date,
               booking.checkout_date,
               :buyout,
               guests_count: booking.guests_count,
               children_count: 0
             ) do
          {:ok, total, breakdown} ->
            # Use breakdown if available, otherwise create a simple one
            final_breakdown =
              if breakdown && is_map(breakdown) do
                Map.merge(breakdown, %{nights: nights})
              else
                %{
                  nights: nights,
                  price_per_night: Money.div(total, nights) |> elem(1)
                }
              end

            {:ok, total, final_breakdown}

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
                 nights
               ) do
            {:ok, recalculated_total, breakdown} ->
              {:ok, recalculated_total, breakdown}

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
               children_count: 0
             ) do
          {:ok, total, breakdown} ->
            # Use breakdown if available, otherwise create a simple one
            final_breakdown =
              if breakdown && is_map(breakdown) do
                Map.merge(breakdown, %{
                  nights: nights,
                  guests_count: booking.guests_count
                })
              else
                price_per_guest_per_night =
                  if nights > 0 and booking.guests_count > 0 do
                    Money.div(total, nights * booking.guests_count) |> elem(1)
                  else
                    Money.new(0, :USD)
                  end

                %{
                  nights: nights,
                  guests_count: booking.guests_count,
                  price_per_guest_per_night: price_per_guest_per_night
                }
              end

            {:ok, total, final_breakdown}

          error ->
            error
        end

      _ ->
        {:error, :invalid_booking_mode}
    end
  end

  defp create_payment_intent(booking, total_amount, user) do
    amount_cents = money_to_cents(total_amount)

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

    # Add customer if user has Stripe ID
    payment_intent_params =
      if user.stripe_id do
        Map.put(payment_intent_params, :customer, user.stripe_id)
      else
        payment_intent_params
      end

    # Use booking reference ID as idempotency key to prevent duplicate charges
    # If the same reference is used again, Stripe will return the existing payment intent
    idempotency_key = "booking_#{booking.reference_id}"

    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.create_payment_intent(payment_intent_params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, payment_intent} ->
        {:ok, payment_intent}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe payment intent creation failed: #{inspect(error)}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Payment intent creation failed: #{inspect(reason)}")
        {:error, "Payment initialization failed"}
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

    # Retrieve payment intent to verify (expand payment_method and charges)
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "charges"]
         }) do
      {:ok, payment_intent} ->
        if payment_intent.status == "succeeded" do
          # Reload booking to get latest status (webhook may have already confirmed it)
          reloaded_booking =
            Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

          # Check if booking is already confirmed (e.g., by webhook)
          if reloaded_booking.status == :complete do
            Logger.info(
              "Booking already confirmed (likely by webhook), returning existing booking",
              booking_id: booking.id,
              payment_intent_id: payment_intent_id
            )

            {:ok, reloaded_booking}
          else
            # Process payment in ledger (handles idempotency - returns existing payment if already processed)
            case process_ledger_payment(reloaded_booking, payment_intent) do
              {:ok, _payment} ->
                # Confirm booking (only if not already confirmed)
                case BookingLocker.confirm_booking(reloaded_booking.id) do
                  {:ok, confirmed_booking} ->
                    {:ok, confirmed_booking}

                  {:error, :invalid_status} ->
                    # Booking was confirmed between reload and confirm attempt (race condition)
                    # Reload again and return the confirmed booking
                    final_booking =
                      Repo.get!(Booking, reloaded_booking.id)
                      |> Repo.preload([:rooms, :user])

                    if final_booking.status == :complete do
                      Logger.info(
                        "Booking confirmed by another process, returning confirmed booking",
                        booking_id: booking.id
                      )

                      {:ok, final_booking}
                    else
                      Logger.error("Failed to confirm booking: invalid status",
                        booking_id: booking.id,
                        status: final_booking.status
                      )

                      {:error, :booking_confirmation_failed}
                    end

                  {:error, reason} ->
                    Logger.error(
                      "Failed to confirm booking: #{inspect(reason)}"
                    )

                    {:error, :booking_confirmation_failed}
                end

              {:error, reason} ->
                Logger.error(
                  "Failed to process ledger payment: #{inspect(reason)}"
                )

                {:error, :payment_processing_failed}
            end
          end
        else
          {:error, :payment_not_succeeded}
        end

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent: #{inspect(reason)}")
        {:error, :payment_verification_failed}
    end
  end

  defp process_ledger_payment(booking, payment_intent) do
    amount = cents_to_money(payment_intent.amount, :USD)
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
  defp calculate_multi_room_price_for_checkout(
         property,
         checkin_date,
         checkout_date,
         room_ids,
         guests_count,
         children_count,
         nights
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
           children_count: children_count
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

      {:ok, total, breakdown} ->
        final_breakdown =
          build_simple_breakdown(
            breakdown,
            nights,
            guests_count,
            children_count,
            room_ids
          )

        {:ok, total, final_breakdown}

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
      case Money.div(children_total, children_count * nights) do
        {:ok, per_night} -> per_night
        _ -> children_price_per_night
      end
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

  defp build_simple_breakdown(
         breakdown,
         nights,
         guests_count,
         children_count,
         room_ids
       ) do
    base_data = %{
      nights: nights,
      guests_count: guests_count,
      children_count: children_count,
      multi_room: true,
      room_count: length(room_ids)
    }

    if breakdown && is_map(breakdown) do
      Map.merge(breakdown, base_data)
    else
      base_data
    end
  end

  # Helper functions for money conversion
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_), do: 0

  defp cents_to_money(cents, currency)

  defp cents_to_money(cents, currency) when is_integer(cents) do
    cents_decimal = Decimal.new(cents)
    dollars = Decimal.div(cents_decimal, Decimal.new(100))
    Money.new(currency, dollars)
  end

  defp cents_to_money(_, _), do: Money.new(0, :USD)

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

        # Or get it from the first charge (charges is a List struct with data field)
        payment_intent.charges && payment_intent.charges.data &&
            payment_intent.charges.data != [] ->
          first_charge = List.first(payment_intent.charges.data)
          # Payment method might be a string ID or an expanded object
          cond do
            is_binary(first_charge.payment_method) ->
              first_charge.payment_method

            is_map(first_charge.payment_method) &&
                Map.has_key?(first_charge.payment_method, :id) ->
              first_charge.payment_method.id

            true ->
              nil
          end

        true ->
          nil
      end

    case stripe_payment_method_id do
      nil ->
        Logger.info("No payment method found in payment intent",
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
                Logger.info(
                  "Successfully synced payment method for booking payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: pm_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Logger.warning(
                  "Failed to sync payment method for booking payment",
                  stripe_payment_method_id: pm_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve payment method from Stripe",
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
      _ -> ~p"/images/ysc_logo.png"
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
            case Money.div(base_total, nights * billable_people) do
              {:ok, price} -> price
              _ -> nil
            end
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
                   case Money.mult(adult_price_per_night, billable_people * nights) do
                     {:ok, total} -> total
                     _ -> nil
                   end
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <div class="text-zinc-400">
              <%= billable_people %> <%= if billable_people == 1,
                do: "adult",
                else: "adults" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if adult_price_per_night do %>
                <%= MoneyHelper.format_money!(adult_price_per_night) %>/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_base_total do %>
                <%= MoneyHelper.format_money!(final_base_total) %>
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
              case Money.div(children_total, children_count * nights) do
                {:ok, price} -> price
                _ -> nil
              end
            else
              children_price_per_night
            end

          final_children_total =
            if children_total,
              do: children_total,
              else:
                (if calculated_children_price_per_night && children_count > 0 &&
                      nights > 0 do
                   case Money.mult(
                          calculated_children_price_per_night,
                          children_count * nights
                        ) do
                     {:ok, total} -> total
                     _ -> nil
                   end
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm mt-3">
            <div class="text-zinc-400">
              <%= children_count %> <%= if children_count == 1,
                do: "child",
                else: "children" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if calculated_children_price_per_night do %>
                <%= MoneyHelper.format_money!(calculated_children_price_per_night) %>/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_children_total do %>
                <%= MoneyHelper.format_money!(final_children_total) %>
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
        <%= if guests_count > 0 && price_per_guest_per_night do %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <div class="text-zinc-400">
              <%= guests_count %> <%= if guests_count == 1,
                do: "guest",
                else: "guests" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= MoneyHelper.format_money!(price_per_guest_per_night) %>/night
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= case Money.mult(price_per_guest_per_night, guests_count * nights) do
                {:ok, total} -> MoneyHelper.format_money!(total)
                _ -> MoneyHelper.format_money!(@total_price)
              end %>
            </div>
          </div>
        <% else %>
          <!-- Fallback if price_per_guest_per_night not available -->
          <div class="flex justify-between text-sm">
            <span class="text-zinc-400">
              <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </span>
            <span class="font-medium">
              <%= MoneyHelper.format_money!(@total_price) %>
            </span>
          </div>
        <% end %>
      <% else %>
        <!-- Buyout booking -->
        <%= if @price_breakdown[:nights] do %>
          <div class="flex justify-between text-sm">
            <span class="text-zinc-400">
              <%= @price_breakdown.nights %> <%= if @price_breakdown.nights == 1,
                do: "night",
                else: "nights" %>
            </span>
            <span class="font-medium">
              <%= MoneyHelper.format_money!(@total_price) %>
            </span>
          </div>
        <% end %>
      <% end %>
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

  defp atom_to_readable(nil), do: "—"
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
    require Logger

    Logger.info("Initializing guest forms",
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
    require Logger

    Logger.info("Built guest list",
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
      require Logger

      Logger.warning("Guest count mismatch - filtering form",
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
    require Logger

    Logger.debug(
      "[build_guest_changesets] Called with booking_id: #{booking.id}"
    )

    Logger.debug(
      "[build_guest_changesets] guest_params keys: #{inspect(Map.keys(guest_params))}"
    )

    Logger.debug(
      "[build_guest_changesets] guest_params: #{inspect(guest_params)}"
    )

    guests_count = booking.guests_count || 1
    children_count = booking.children_count || 0
    total_expected = guests_count + children_count

    Logger.debug(
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

    Logger.debug(
      "[build_guest_changesets] guests_list length: #{length(guests_list)}"
    )

    Logger.debug(
      "[build_guest_changesets] guests_list: #{inspect(guests_list)}"
    )

    if length(guests_list) != total_expected do
      error_msg =
        "Expected #{total_expected} guests, got #{length(guests_list)}"

      Logger.error("[build_guest_changesets] #{error_msg}")
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

      Logger.debug(
        "[build_guest_changesets] booking_user_count: #{booking_user_count}"
      )

      if booking_user_count != 1 do
        error_msg =
          "Exactly one guest must be marked as the booking user, got #{booking_user_count}"

        Logger.error("[build_guest_changesets] #{error_msg}")
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

        Logger.debug("[build_guest_changesets] child_count: #{child_count}")

        if child_count != children_count do
          error_msg = "Expected #{children_count} children, got #{child_count}"
          Logger.error("[build_guest_changesets] #{error_msg}")
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

          Logger.debug(
            "[build_guest_changesets] Built #{length(changesets)} changesets"
          )

          Logger.debug(
            "[build_guest_changesets] Changesets valid status: #{inspect(Enum.map(changesets, & &1.valid?))}"
          )

          # Check if all changesets are valid
          invalid_changesets =
            Enum.filter(changesets, fn changeset -> not changeset.valid? end)

          if invalid_changesets != [] do
            Logger.error(
              "[build_guest_changesets] Found #{length(invalid_changesets)} invalid changesets"
            )

            {:error, invalid_changesets}
          else
            Logger.debug("[build_guest_changesets] All changesets are valid")
            {:ok, changesets}
          end
        end
      end
    end
  end

  def all_guests_valid?(nil, _booking), do: false

  def all_guests_valid?(guest_info_form, booking) do
    guests_count = booking.guests_count || 1
    children_count = booking.children_count || 0
    total_expected = guests_count + children_count

    # Check if we have the expected number of guests
    if map_size(guest_info_form.source) != total_expected do
      false
    else
      # Check if all guests have valid first_name and last_name
      guest_info_form.source
      |> Enum.all?(fn {_index, guest_data} ->
        first_name =
          Map.get(guest_data, "first_name") || Map.get(guest_data, :first_name) ||
            ""

        last_name =
          Map.get(guest_data, "last_name") || Map.get(guest_data, :last_name) ||
            ""

        # Both first_name and last_name must be non-empty strings
        String.trim(first_name) != "" && String.trim(last_name) != ""
      end)
    end
  end

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
end
