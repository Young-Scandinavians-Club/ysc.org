defmodule YscWeb.BookingChangeLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, ModificationDateAvailability}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  alias YscWeb.BookingActions
  alias YscWeb.BookingGuestForm
  import YscWeb.Components.BookingGuestInfoForm
  import Ecto.Query

  @payment_finalize_retry_attempts 5
  @payment_finalize_retry_delay_ms 400

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "You must be signed in to change this booking."
       )
       |> redirect(to: ~p"/")}
    else
      case load_booking(booking_id, user) do
        {:ok, booking} ->
          if BookingActions.can_change_booking?(booking) do
            calendar =
              ModificationDateAvailability.calendar_placeholder(booking)

            form = modification_form(booking)

            socket =
              socket
              |> assign_change_page_shell(booking, calendar, form)

            if connected?(socket) do
              {:ok, load_change_data_async(socket, booking, form)}
            else
              {:ok, socket}
            end
          else
            {:ok,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "This booking can no longer be changed.",
               title: "Booking"
             )
             |> redirect(to: ~p"/bookings/#{booking_id}/receipt")}
          end

        {:error, :not_found} ->
          {:ok,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             YscWeb.BookingUserMessages.reservation_not_found(),
             title: "Booking"
           )
           |> redirect(to: ~p"/")}
      end
    end
  end

  @impl true
  def handle_info({:updated_event, attrs}, socket) do
    if Map.get(attrs, :id) == "modification-dates" and
         socket.assigns.change_data_loaded? do
      checkin_date = datetime_to_date(attrs.start_date)
      checkout_date = datetime_to_date(attrs.end_date)

      params =
        form_params(socket.assigns.form)
        |> Map.put(
          "checkin_date",
          if(checkin_date, do: Date.to_string(checkin_date), else: "")
        )
        |> Map.put(
          "checkout_date",
          if(checkout_date, do: Date.to_string(checkout_date), else: "")
        )
        |> normalize_modification_params()

      checkout_tooltips =
        if checkin_date do
          ModificationDateAvailability.checkout_date_tooltips(
            socket.assigns.booking,
            checkin_date,
            socket.assigns.calendar_max_date,
            socket.assigns.today,
            socket.assigns.seasons,
            socket.assigns.availability_snapshot
          )
        else
          %{}
        end

      form = modification_form(socket.assigns.booking, params)

      socket =
        socket
        |> assign(:form, form)
        |> assign(:checkout_date_tooltips, checkout_tooltips)
        |> run_preview_and_sync_payment(params)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:load_change_data, {:ok, data}, socket) do
    calendar = data.calendar

    socket =
      socket
      |> assign(:today, calendar.today)
      |> assign(:seasons, calendar.seasons)
      |> assign(:calendar_min_date, calendar.min_date)
      |> assign(:calendar_max_date, calendar.max_date)
      |> assign(:max_nights, calendar.max_nights)
      |> assign(:availability_snapshot, data.availability_snapshot)
      |> assign(:checkout_date_tooltips, data.checkout_tooltips)
      |> assign(:checkin_date_tooltips, data.checkin_tooltips)
      |> assign(:checkin_date_tooltips_loading?, false)
      |> assign(:change_data_loaded?, true)
      |> assign(:amount_paid, amount_paid_from_preview(data.preview_result))
      |> apply_preview_result(data.preview_result)

    {:noreply, socket}
  end

  def handle_async(:load_change_data, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:checkin_date_tooltips, %{})
     |> assign(:checkout_date_tooltips, %{})
     |> assign(:checkin_date_tooltips_loading?, false)
     |> assign(:change_data_loaded?, true)
     |> assign(
       :preview_error,
       "Unable to load availability. Please refresh the page."
     )}
  end

  @impl true
  def handle_async(:finalize_modification, {:ok, result}, socket) do
    payment_intent_id = socket.assigns[:finalize_payment_intent_id]

    handle_apply_modification_result(socket, result, payment_intent_id)
  end

  def handle_async(:finalize_modification, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:submitting, false)
     |> assign(:payment_processing, false)
     |> assign(:finalize_payment_intent_id, nil)
     |> assign(
       :payment_error,
       "Your payment was received but we could not update your reservation. Please open your confirmation page or contact support."
     )
     |> YscWeb.Flash.put_toast(
       :error,
       "Your payment was received but we could not update your reservation. Please open your confirmation page or contact support.",
       title: "Payment received"
     )}
  end

  @impl true
  def handle_event("validate", %{"modification" => params}, socket) do
    if socket.assigns.change_data_loaded? do
      params = normalize_modification_params(params)
      form = modification_form(socket.assigns.booking, params)

      socket =
        socket
        |> assign(:form, form)
        |> assign(
          :checkout_date_tooltips,
          checkout_tooltips_for_params(socket, params)
        )
        |> run_preview_and_sync_payment(params)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle-acknowledgment", _params, socket) do
    {:noreply, assign(socket, :acknowledged, not socket.assigns.acknowledged)}
  end

  @impl true
  def handle_event("submit-modification", %{"modification" => params}, socket) do
    booking = socket.assigns.booking
    params = normalize_modification_params(params)

    if socket.assigns.acknowledged do
      case Bookings.prepare_modification(booking, params, preview_opts(socket)) do
        {:ok, preview} ->
          socket =
            socket
            |> assign(:preview, preview)
            |> assign(:preview_error, nil)

          if BookingGuestForm.guest_info_required_for_modification?(
               booking,
               preview.attrs
             ) do
            user = socket.assigns.current_user

            {_family_members, other_family_members} =
              BookingGuestForm.load_family_members(user)

            preview_booking =
              BookingGuestForm.preview_booking(
                booking,
                preview.attrs.guests_count,
                preview.attrs.children_count
              )

            guest_form =
              BookingGuestForm.initialize_modification_guest_forms(
                booking,
                user,
                preview.attrs.guests_count,
                preview.attrs.children_count
              )

            {:noreply,
             socket
             |> assign(:step, :guest_info)
             |> assign(:preview_booking, preview_booking)
             |> assign(:guest_info_form, guest_form)
             |> assign(:guest_info_errors, %{})
             |> assign(:pending_modification_params, params)
             |> assign(:pending_guest_params, nil)
             |> assign(:other_family_members, other_family_members)
             |> assign(:selected_family_members_for_guests, %{})
             |> assign(:show_payment_form, false)}
          else
            case proceed_after_modification_details(socket, params, preview) do
              {:payment, updated_socket} ->
                {:noreply, updated_socket}

              {:apply, updated_socket} ->
                apply_modification_and_redirect(updated_socket, params, nil)

              {:error, updated_socket} ->
                {:noreply, updated_socket}
            end
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:form, to_form(changeset, as: "modification"))
           |> assign(:preview_error, format_changeset_errors(changeset))}

        {:error, :no_changes} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "No changes were made to your reservation."
           )}

        {:error, reason} ->
          {:noreply,
           assign(socket, :preview_error, modification_error_message(reason))}
      end
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         YscWeb.BookingUserMessages.modification_acknowledgment_required()
       )}
    end
  end

  @impl true
  def handle_event("back-to-modification", _params, socket) do
    {:noreply,
     socket
     |> dismiss_payment_form()
     |> assign(:step, :edit)
     |> assign(:guest_info_form, nil)
     |> assign(:guest_info_errors, %{})}
  end

  @impl true
  def handle_event("validate-guest-info", %{"guests" => guest_params}, socket) do
    {:noreply, validate_guest_info(socket, guest_params)}
  end

  def handle_event("validate-guest-info", _params, socket),
    do: {:noreply, socket}

  @impl true
  def handle_event("save-guest-info", %{"guests" => guest_params}, socket) do
    socket = validate_guest_info(socket, guest_params)

    if map_size(socket.assigns.guest_info_errors || %{}) == 0 &&
         BookingGuestForm.all_guests_valid?(
           socket.assigns.guest_info_form,
           socket.assigns.preview_booking
         ) do
      merged =
        BookingGuestForm.merge_guest_params(
          socket.assigns.guest_info_form,
          guest_params,
          socket.assigns.selected_family_members_for_guests,
          socket.assigns.other_family_members
        )

      params = socket.assigns.pending_modification_params

      socket = assign(socket, :pending_guest_params, merged)

      case proceed_after_guest_info(socket) do
        {:payment, updated_socket} ->
          {:noreply, updated_socket}

        {:apply, updated_socket} ->
          apply_modification_and_redirect(updated_socket, params, nil)

        {:error, updated_socket} ->
          {:noreply, updated_socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-guest-info", _params, socket) do
    {:noreply,
     assign(socket, :guest_info_errors, %{
       general: "Please complete guest information for all guests."
     })}
  end

  @impl true
  def handle_event("select-guest-attendee", params, socket) do
    guest_index = guest_index_from_params(params)

    selected_value =
      if guest_index do
        Map.get(params, "guest-#{guest_index}-attendee-select")
      else
        params
        |> Map.keys()
        |> Enum.find(&String.contains?(&1, "attendee-select"))
        |> then(fn key -> if key, do: Map.get(params, key) end)
      end

    if guest_index && selected_value do
      {updated_form, family_update} =
        BookingGuestForm.select_guest_attendee(
          socket.assigns.guest_info_form,
          guest_index,
          selected_value,
          socket.assigns.other_family_members
        )

      selected_family_members =
        Map.merge(
          socket.assigns.selected_family_members_for_guests || %{},
          family_update
        )

      validate_params =
        updated_form.source
        |> Enum.map(fn {index_str, guest_data} ->
          {index_str, Map.take(guest_data, ["first_name", "last_name"])}
        end)
        |> Map.new()

      socket =
        socket
        |> assign(:guest_info_form, updated_form)
        |> assign(:selected_family_members_for_guests, selected_family_members)
        |> validate_guest_info(validate_params)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("payment-redirect-started", _params, socket) do
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
    booking =
      Repo.get!(Booking, socket.assigns.booking.id)
      |> Repo.preload(:rooms)

    params = modification_params_for_payment_apply(socket, booking)

    {:noreply,
     socket
     |> assign(:booking, booking)
     |> assign(:payment_processing, true)
     |> assign(:payment_error, nil)
     |> assign(:submitting, true)
     |> assign(:finalize_payment_intent_id, payment_intent_id)
     |> start_async(:finalize_modification, fn ->
       apply_modification_after_payment(booking, params, payment_intent_id)
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <div class="mb-6">
        <.link
          navigate={~p"/bookings/#{@booking.id}/receipt"}
          class="text-sm text-blue-600 hover:text-blue-800 inline-flex items-center gap-1"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to your reservation
        </.link>
      </div>

      <h1 class="text-3xl font-bold text-zinc-900 mb-2">Change Reservation</h1>
      <p class="text-zinc-600 mb-6">
        Booking {@booking.reference_id} · {property_label(@booking.property)}
      </p>

      <div
        id="refund-forfeiture-notice"
        class="mb-6 p-4 rounded-lg border border-amber-300 bg-amber-50 text-amber-950"
      >
        <p class="font-semibold mb-2">
          {YscWeb.BookingUserMessages.modification_forfeiture_title()}
        </p>
        <p class="text-sm leading-relaxed">
          {YscWeb.BookingUserMessages.modification_forfeiture_body()}
        </p>
      </div>

      <div
        :if={@step == :edit}
        class="space-y-6 bg-white border border-zinc-200 rounded-xl p-6 shadow-sm"
      >
        <div
          :if={!@change_data_loaded?}
          id="change-data-loading"
          class="flex items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-4 py-3 text-sm text-zinc-600"
          role="status"
          aria-live="polite"
        >
          <.icon
            name="hero-arrow-path"
            class="w-4 h-4 shrink-0 text-blue-600 animate-spin"
            aria-hidden="true"
          /> Loading availability and price preview…
        </div>

        <.form
          for={@form}
          id="booking-change-form"
          phx-change="validate"
          phx-debounce="300"
          phx-submit="submit-modification"
          class={[
            "space-y-6",
            !@change_data_loaded? && "pointer-events-none opacity-50"
          ]}
        >
          <%= if @booking.rooms != [] do %>
            <div>
              <h2 class="text-sm font-semibold text-zinc-700 mb-1">
                Your rooms
              </h2>
              <p class="text-sm text-zinc-500 mb-2">
                Room assignments cannot be changed here. To change rooms, cancel this reservation and book again.
              </p>
              <ul class="text-sm text-zinc-600 list-disc list-inside">
                <%= for room <- @booking.rooms do %>
                  <li>{room.name}</li>
                <% end %>
              </ul>
            </div>
          <% end %>

          <div>
            <.date_range_picker
              id="modification-dates"
              label="Check-in & Check-out Dates"
              form={@form}
              start_date_field={@form[:checkin_date]}
              end_date_field={@form[:checkout_date]}
              min={@calendar_min_date}
              max={@calendar_max_date}
              required
              property={@booking.property}
              today={@today}
              seasons={@seasons}
              max_nights={@max_nights}
              date_tooltips={@checkin_date_tooltips}
              checkout_date_tooltips={@checkout_date_tooltips}
            />
            <%= if @checkin_date_tooltips_loading? do %>
              <p class="mt-2 flex items-center gap-1.5 text-xs text-zinc-500">
                <.icon
                  name="hero-arrow-path"
                  class="w-3 h-3 shrink-0 animate-spin"
                  aria-hidden="true"
                /> Loading available dates…
              </p>
            <% end %>
          </div>

          <%= if @booking.booking_mode != :buyout do %>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@form[:guests_count]}
                type="number"
                label="Number of guests"
                min="1"
                max={max_adults_for_modification(@booking, @form)}
                required
              />
              <%= if @booking.booking_mode == :room do %>
                <.input
                  field={@form[:children_count]}
                  type="number"
                  label="Number of children"
                  min="0"
                  max={max_children_for_modification(@booking, @form)}
                />
              <% end %>
            </div>
          <% end %>

          <%= if @preview_error do %>
            <div
              id="modification-preview-error"
              class="p-3 rounded-lg bg-red-50 border border-red-200 text-red-800 text-sm"
            >
              {@preview_error}
            </div>
          <% end %>

          <%= if @preview do %>
            <div
              id="modification-price-preview"
              class="p-4 rounded-lg bg-zinc-50 border border-zinc-200"
            >
              <h2 class="text-sm font-semibold text-zinc-800 mb-3">
                Price preview
              </h2>
              <dl class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <dt class="text-zinc-600">Previous reservation total</dt>
                  <dd>{MoneyHelper.format_money!(@preview.previous_total)}</dd>
                </div>
                <div class="flex justify-between">
                  <dt class="text-zinc-600">New reservation total</dt>
                  <dd class="font-medium">
                    {MoneyHelper.format_money!(@preview.new_total)}
                  </dd>
                </div>
                <div class="flex justify-between border-t border-zinc-200 pt-2">
                  <dt class="font-semibold text-zinc-800">Amount due now</dt>
                  <dd class="font-semibold text-zinc-900">
                    {MoneyHelper.format_money!(@preview.delta)}
                  </dd>
                </div>
              </dl>
              <%= if modification_is_downgrade?(@preview) do %>
                <div
                  id="modification-downgrade-notice"
                  class="mt-3 p-3 rounded-lg bg-amber-50 border border-amber-200 text-amber-900 text-sm"
                >
                  Shortening your stay reduces the reservation total, but we do not refund the difference.
                </div>
              <% end %>
            </div>
          <% end %>
        </.form>

        <div class="flex items-start gap-3">
          <input
            type="checkbox"
            id="acknowledge-forfeiture"
            phx-click="toggle-acknowledgment"
            checked={@acknowledged}
            class="mt-1 h-4 w-4 rounded border-zinc-300 text-blue-600 focus:ring-blue-500"
          />
          <label
            for="acknowledge-forfeiture"
            class="text-sm text-zinc-700 leading-relaxed"
          >
            {YscWeb.BookingUserMessages.modification_forfeiture_acknowledgment()}
          </label>
        </div>

        <%= if not @show_payment_form do %>
          <.button
            id="submit-modification-button"
            type="submit"
            form="booking-change-form"
            class="w-full py-3"
            disabled={!@acknowledged || @submitting || !@change_data_loaded?}
            phx-disable-with="Saving..."
          >
            {submit_button_label(@preview)}
          </.button>
        <% end %>
      </div>

      <%= if @step == :guest_info && @preview_booking && @guest_info_form do %>
        <div class="mt-8">
          <.booking_guest_info_form
            id="modification-guest-info-form"
            booking={@preview_booking}
            guest_info_form={@guest_info_form}
            guest_info_errors={@guest_info_errors}
            other_family_members={@other_family_members}
            selected_family_members_for_guests={@selected_family_members_for_guests}
            current_user={@current_user}
            intro_text={guest_info_intro(@booking, @preview_booking)}
            submit_label={guest_info_submit_label(@preview)}
          >
            <:actions>
              <.button
                type="button"
                phx-click="back-to-modification"
                variant="outline"
                color="zinc"
                class="px-6 py-3"
              >
                Back
              </.button>
            </:actions>
          </.booking_guest_info_form>
        </div>
      <% end %>

      <%= if @show_payment_form && @payment_intent && @payment_delta && Money.positive?(@payment_delta) do %>
        <div class="mt-8 bg-white border border-zinc-200 rounded-xl p-6 shadow-sm">
          <%= if @payment_processing do %>
            <div
              id="modification-payment-success"
              class="p-4 rounded-lg bg-green-50 border border-green-200 text-green-900"
            >
              <p class="font-semibold flex items-center gap-2">
                <.icon name="hero-check-circle" class="w-5 h-5" />
                Payment successful
              </p>
              <p class="text-sm mt-2 text-green-800">
                We're saving your reservation changes. You'll be redirected to your confirmation shortly.
              </p>
            </div>
          <% else %>
            <h2 class="text-lg font-semibold text-zinc-900 mb-2">
              Additional payment required
            </h2>
            <p class="text-sm text-zinc-600 mb-4">
              Pay {MoneyHelper.format_money!(@payment_delta)} to confirm your reservation changes.
            </p>

            <%= if @payment_error do %>
              <div
                id="modification-payment-error"
                class="mb-4 p-3 rounded-lg bg-red-50 border border-red-200 text-red-800 text-sm"
              >
                {@payment_error}
              </div>
            <% end %>

            <div
              id="stripe-payment-container"
              phx-hook="StripeElements"
              data-client-secret={@payment_intent.client_secret}
              data-booking-id={@booking.id}
              data-modification="true"
            >
              <.payment_element_loading :if={!@stripe_payment_element_ready} />
              <div
                id="payment-element"
                phx-update="ignore"
                class="mb-6 min-h-[12rem]"
              />
              <div id="payment-message" class="hidden mt-4" />
            </div>

            <.button
              id="submit-payment"
              type="button"
              class="w-full py-3"
              disabled={!@stripe_payment_element_ready || @submitting}
            >
              <.icon name="hero-lock-closed" class="w-5 h-5 -mt-0.5 me-1" />
              Pay {MoneyHelper.format_money!(@payment_delta)} and save changes
            </.button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp assign_change_page_shell(socket, booking, calendar, form) do
    socket
    |> assign(:page_title, "Change Reservation")
    |> assign(:booking, booking)
    |> assign(:form, form)
    |> assign(:availability_snapshot, nil)
    |> assign(:preview, nil)
    |> assign(:preview_error, nil)
    |> assign(:acknowledged, false)
    |> assign(:submitting, false)
    |> assign(:payment_intent, nil)
    |> assign(:payment_delta, nil)
    |> assign(:show_payment_form, false)
    |> assign(:stripe_payment_element_ready, false)
    |> assign(:payment_error, nil)
    |> assign(:payment_processing, false)
    |> assign(:today, calendar.today)
    |> assign(:seasons, calendar.seasons)
    |> assign(:calendar_min_date, calendar.min_date)
    |> assign(:calendar_max_date, calendar.max_date)
    |> assign(:max_nights, calendar.max_nights)
    |> assign(:checkin_date_tooltips, %{})
    |> assign(:checkout_date_tooltips, %{})
    |> assign(:checkin_date_tooltips_loading?, true)
    |> assign(:change_data_loaded?, false)
    |> assign(:step, :edit)
    |> assign(:guest_info_form, nil)
    |> assign(:guest_info_errors, %{})
    |> assign(:preview_booking, nil)
    |> assign(:pending_modification_params, nil)
    |> assign(:pending_guest_params, nil)
    |> assign(:amount_paid, nil)
    |> assign(:selected_family_members_for_guests, %{})
    |> assign(:other_family_members, [])
  end

  defp load_change_data_async(socket, booking, form) do
    params = form_params(form)

    start_async(socket, :load_change_data, fn ->
      calendar = ModificationDateAvailability.calendar_context(booking)

      availability_snapshot =
        ModificationDateAvailability.build_availability_snapshot(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons
        )

      checkout_tooltips =
        ModificationDateAvailability.checkout_date_tooltips(
          booking,
          booking.checkin_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons,
          availability_snapshot
        )

      checkin_tooltips =
        ModificationDateAvailability.checkin_date_tooltips(
          booking,
          calendar.min_date,
          calendar.max_date,
          calendar.today,
          calendar.seasons,
          availability_snapshot
        )

      preview_result =
        Bookings.prepare_modification(booking, params,
          availability_snapshot: availability_snapshot
        )

      %{
        calendar: calendar,
        availability_snapshot: availability_snapshot,
        checkout_tooltips: checkout_tooltips,
        checkin_tooltips: checkin_tooltips,
        preview_result: preview_result
      }
    end)
  end

  defp apply_preview_result(socket, preview_result) do
    if socket.assigns.show_payment_form do
      socket
    else
      do_apply_preview_result(socket, preview_result)
    end
  end

  defp do_apply_preview_result(socket, preview_result) do
    case preview_result do
      {:ok, preview} ->
        assign(socket, preview: preview, preview_error: nil)

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:preview, nil)
        |> assign(:preview_error, format_changeset_errors(changeset))

      {:error, :no_changes} ->
        assign(socket, preview: nil, preview_error: nil)

      {:error, reason} ->
        assign(socket,
          preview: nil,
          preview_error: modification_error_message(reason)
        )
    end
  end

  defp load_booking(booking_id, user) do
    booking_query =
      from(b in Booking,
        where: b.id == ^booking_id and b.user_id == ^user.id,
        preload: [rooms: :room_category, booking_guests: []]
      )

    case Repo.one(booking_query) do
      nil -> {:error, :not_found}
      booking -> {:ok, booking}
    end
  end

  defp modification_form(booking, params \\ %{}) do
    defaults = %{
      "checkin_date" => date_to_datetime_string(booking.checkin_date),
      "checkout_date" => date_to_datetime_string(booking.checkout_date),
      "guests_count" => to_string(booking.guests_count),
      "children_count" => to_string(booking.children_count || 0)
    }

    defaults
    |> Map.merge(params)
    |> Map.update("checkin_date", "", &ensure_datetime_string/1)
    |> Map.update("checkout_date", "", &ensure_datetime_string/1)
    |> then(&to_form(&1, as: "modification"))
  end

  defp form_params(%Phoenix.HTML.Form{} = form),
    do: normalize_modification_params(form.params)

  defp normalize_modification_params(params) when is_map(params) do
    params
    |> Map.update("checkin_date", "", &normalize_date_param/1)
    |> Map.update("checkout_date", "", &normalize_date_param/1)
  end

  defp ensure_datetime_string(value) when value in [nil, ""], do: ""

  defp ensure_datetime_string(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} ->
        value

      _ ->
        case parse_date_param(value) do
          %Date{} = date -> date_to_datetime_string(date)
          _ -> ""
        end
    end
  end

  defp ensure_datetime_string(%Date{} = date), do: date_to_datetime_string(date)

  defp parse_date_param(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date_to_datetime_string(nil), do: ""

  defp date_to_datetime_string(%Date{} = date) do
    Date.to_iso8601(date) <> "T00:00:00Z"
  end

  defp normalize_date_param(value) when value in [nil, ""], do: ""

  defp normalize_date_param(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime |> DateTime.to_date() |> Date.to_iso8601()
      _ -> value
    end
  end

  defp normalize_date_param(%Date{} = date), do: Date.to_iso8601(date)

  defp datetime_to_date(nil), do: nil
  defp datetime_to_date(""), do: nil

  defp datetime_to_date(%Date{} = date), do: date

  defp datetime_to_date(%DateTime{} = datetime) do
    DateTime.to_date(datetime)
  end

  defp datetime_to_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> DateTime.to_date(datetime)
      _ -> nil
    end
  end

  defp run_preview_and_sync_payment(socket, params) do
    socket
    |> run_preview(params)
    |> sync_payment_form_with_preview(params)
  end

  defp run_preview(socket, params) do
    case Bookings.prepare_modification(
           socket.assigns.booking,
           params,
           preview_opts(socket)
         ) do
      {:ok, preview} ->
        socket
        |> assign(preview: preview, preview_error: nil)
        |> assign(:amount_paid, preview.amount_paid)

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:preview, nil)
        |> assign(:preview_error, format_changeset_errors(changeset))

      {:error, :no_changes} ->
        assign(socket, preview: nil, preview_error: nil)

      {:error, reason} ->
        assign(socket,
          preview: nil,
          preview_error: modification_error_message(reason)
        )
    end
  end

  defp preview_opts(socket) do
    # Rebuild while the payment hold is active: inventory rows get buyout_held and
    # a cached snapshot from before the hold would block the member's own change.
    base_opts =
      if socket.assigns.show_payment_form or
           is_nil(socket.assigns.availability_snapshot) do
        []
      else
        [availability_snapshot: socket.assigns.availability_snapshot]
      end

    case socket.assigns[:amount_paid] do
      %Money{} = amount_paid ->
        Keyword.put(base_opts, :amount_paid, amount_paid)

      _ ->
        base_opts
    end
  end

  defp amount_paid_from_preview({:ok, %{amount_paid: %Money{} = amount_paid}}),
    do: amount_paid

  defp amount_paid_from_preview(_), do: nil

  defp refresh_availability_snapshot(socket) do
    if socket.assigns.change_data_loaded? do
      booking = socket.assigns.booking

      snapshot =
        ModificationDateAvailability.build_availability_snapshot(
          booking,
          socket.assigns.calendar_min_date,
          socket.assigns.calendar_max_date,
          socket.assigns.today,
          socket.assigns.seasons
        )

      assign(socket, :availability_snapshot, snapshot)
    else
      assign(socket, :availability_snapshot, nil)
    end
  end

  defp sync_payment_form_with_preview(socket, params) do
    if socket.assigns.show_payment_form do
      case socket.assigns.preview do
        %{delta: %Money{} = delta} = preview ->
          cond do
            not Money.positive?(delta) ->
              dismiss_payment_form(socket)

            Money.equal?(delta, socket.assigns.payment_delta) ->
              assign(socket, :pending_modification_params, params)

            true ->
              socket
              |> dismiss_payment_form()
              |> refresh_payment_for_preview(params, preview)
          end

        _ ->
          dismiss_payment_form(socket)
      end
    else
      socket
    end
  end

  defp refresh_payment_for_preview(socket, params, preview) do
    case proceed_after_modification_details(socket, params, preview) do
      {:payment, payment_socket} ->
        payment_socket

      {:apply, apply_socket} ->
        apply_socket

      {:error, error_socket} ->
        error_socket
    end
  end

  defp dismiss_payment_form(socket) do
    socket =
      if socket.assigns.show_payment_form do
        Bookings.release_modification_hold(socket.assigns.booking.id)
        socket
      else
        socket
      end

    socket =
      assign(socket,
        show_payment_form: false,
        payment_intent: nil,
        payment_delta: nil,
        stripe_payment_element_ready: false,
        payment_error: nil
      )

    refresh_availability_snapshot(socket)
  end

  defp modification_params_for_payment_apply(socket, booking) do
    Bookings.modification_hold_form_params(booking) ||
      socket.assigns.pending_modification_params ||
      form_params(socket.assigns.form)
  end

  defp apply_modification_and_redirect(socket, params, payment_intent_id) do
    result = Bookings.apply_modification(socket.assigns.booking, params, [])
    handle_apply_modification_result(socket, result, payment_intent_id)
  end

  defp handle_apply_modification_result(socket, result, payment_intent_id) do
    booking = socket.assigns.booking

    case result do
      {:ok, updated_booking} ->
        finalize_modification_redirect(
          assign(socket, :finalize_payment_intent_id, nil),
          updated_booking
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        if payment_intent_id do
          redirect_to_receipt_after_payment(
            assign(socket, :finalize_payment_intent_id, nil),
            booking.id,
            payment_intent_id
          )
        else
          {:noreply,
           socket
           |> assign(:submitting, false)
           |> assign(:payment_processing, false)
           |> assign(:finalize_payment_intent_id, nil)
           |> assign(:form, to_form(changeset, as: "modification"))
           |> assign(:preview_error, format_changeset_errors(changeset))}
        end

      {:error, reason} ->
        if payment_intent_id && recoverable_payment_finalize_error?(reason) do
          redirect_to_receipt_after_payment(
            assign(socket, :finalize_payment_intent_id, nil),
            booking.id,
            payment_intent_id
          )
        else
          error_message =
            if payment_intent_id,
              do: modification_error_message_after_payment(reason),
              else: modification_error_message(reason)

          {:noreply,
           socket
           |> assign(:submitting, false)
           |> assign(:payment_processing, false)
           |> assign(:finalize_payment_intent_id, nil)
           |> assign(:payment_error, error_message)
           |> YscWeb.Flash.put_toast(
             :error,
             error_message,
             title:
               if(payment_intent_id,
                 do: "Payment received",
                 else: "Unable to update"
               )
           )}
        end
    end
  end

  defp apply_modification_after_payment(
         booking,
         params,
         payment_intent_id,
         attempt \\ 1
       ) do
    case Bookings.apply_modification(booking, params,
           payment_intent_id: payment_intent_id
         ) do
      {:ok, _} = ok ->
        ok

      {:error, :payment_not_succeeded}
      when attempt < @payment_finalize_retry_attempts ->
        Process.sleep(@payment_finalize_retry_delay_ms)

        apply_modification_after_payment(
          booking,
          params,
          payment_intent_id,
          attempt + 1
        )

      other ->
        other
    end
  end

  defp finalize_modification_redirect(socket, booking) do
    case sync_guests_after_modification(socket, booking) do
      :ok ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Your reservation has been updated.",
           title: "Reservation updated"
         )
         |> push_navigate(
           to: ~p"/bookings/#{booking.id}/receipt?updated=true&confetti=true"
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> YscWeb.Flash.put_toast(
           :info,
           "Your reservation has been updated.",
           title: "Reservation updated"
         )
         |> YscWeb.Flash.put_toast(
           :warning,
           "Guest details could not be saved. Please contact support if needed.",
           title: "Guest details"
         )
         |> push_navigate(
           to: ~p"/bookings/#{booking.id}/receipt?updated=true&confetti=true"
         )}
    end
  end

  defp redirect_to_receipt_after_payment(socket, booking_id, payment_intent_id) do
    {:noreply,
     socket
     |> assign(:payment_processing, true)
     |> YscWeb.Flash.put_toast(
       :info,
       "Payment successful. Finishing your reservation update…",
       title: "Payment received"
     )
     |> push_navigate(
       to: receipt_after_modification_payment_url(booking_id, payment_intent_id)
     )}
  end

  defp receipt_after_modification_payment_url(booking_id, payment_intent_id) do
    ~p"/bookings/#{booking_id}/receipt?payment_intent=#{payment_intent_id}&redirect_status=succeeded&updated=true&confetti=true"
  end

  defp recoverable_payment_finalize_error?(reason) do
    reason in [
      :payment_not_succeeded,
      :modification_hold_expired,
      :modification_hold_mismatch,
      :inventory_update_failed,
      :payment_metadata_mismatch,
      :payment_amount_mismatch,
      :property_unavailable,
      :room_unavailable,
      :rooms_already_booked,
      :property_buyout_active,
      :blackout_conflict
    ] or
      match?({:payment_verification_failed, _}, reason) or
      match?({:ledger_payment_failed, _}, reason)
  end

  defp modification_error_message_after_payment(reason) do
    "Your payment was received. " <>
      modification_error_message(reason) <>
      " Please open your confirmation page or contact support if your dates did not update."
  end

  defp proceed_after_modification_details(socket, params, preview) do
    if Money.positive?(preview.delta) do
      booking = socket.assigns.booking

      hold_opts = modification_hold_guest_opts(socket)

      with {:ok, _booking} <-
             Bookings.place_modification_hold(booking, preview.attrs, hold_opts),
           {:ok, payment_intent} <-
             create_delta_payment_intent(
               booking,
               preview.delta,
               socket.assigns.current_user
             ) do
        {:payment,
         socket
         |> assign(:step, :edit)
         |> assign(:pending_modification_params, params)
         |> assign(:payment_intent, payment_intent)
         |> assign(:payment_delta, preview.delta)
         |> assign(:show_payment_form, true)
         |> assign(:availability_snapshot, nil)
         |> assign(:stripe_payment_element_ready, false)
         |> assign(:payment_error, nil)}
      else
        {:error, _reason} ->
          Bookings.release_modification_hold(booking.id)

          {:error,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "We couldn't start the payment form for your date change. Please try again, or email info@ysc.org if this keeps happening."
           )}
      end
    else
      {:apply, assign(socket, :pending_modification_params, params)}
    end
  end

  defp proceed_after_guest_info(socket) do
    params = socket.assigns.pending_modification_params
    preview = socket.assigns.preview
    proceed_after_modification_details(socket, params, preview)
  end

  defp validate_guest_info(socket, guest_params) do
    merged =
      BookingGuestForm.merge_guest_params(
        socket.assigns.guest_info_form,
        guest_params,
        socket.assigns.selected_family_members_for_guests,
        socket.assigns.other_family_members
      )

    case BookingGuestForm.validate_guest_params(
           socket.assigns.preview_booking,
           merged
         ) do
      {:ok, form, errors} ->
        socket
        |> assign(:guest_info_form, form)
        |> assign(:guest_info_errors, errors)

      {:error, form, errors} ->
        socket
        |> assign(:guest_info_form, form)
        |> assign(:guest_info_errors, errors)
    end
  end

  defp sync_guests_after_modification(socket, booking) do
    BookingGuestForm.sync_guests_after_modification_apply(
      booking,
      socket.assigns.booking.modification_hold_attrs,
      socket.assigns.booking,
      guest_params: socket.assigns.pending_guest_params
    )
  end

  defp modification_hold_guest_opts(socket) do
    case socket.assigns.pending_guest_params do
      params when is_map(params) and map_size(params) > 0 ->
        [guest_params: params]

      _ ->
        []
    end
  end

  defp guest_index_from_params(params) do
    params["guest_index"] ||
      params["guest-index"] ||
      params
      |> Map.keys()
      |> Enum.find(fn key -> String.contains?(key, "attendee-select") end)
      |> case do
        nil ->
          nil

        field_name ->
          field_name
          |> String.replace("guest-", "")
          |> String.replace("-attendee-select", "")
      end
  end

  defp guest_info_intro(booking, preview_booking) do
    room_names =
      if booking.rooms != [],
        do: Enum.map_join(booking.rooms, ", ", & &1.name),
        else: "your room"

    adults = preview_booking.guests_count || 1
    children = preview_booking.children_count || 0

    children_text =
      if children > 0 do
        " and #{children} #{if children == 1, do: "child", else: "children"}"
      else
        ""
      end

    "You added guests to #{room_names}. Please provide names for all #{adults} #{if adults == 1, do: "adult", else: "adults"}#{children_text}."
  end

  defp guest_info_submit_label(%{delta: delta}) when is_struct(delta, Money) do
    if Money.positive?(delta), do: "Continue to payment", else: "Save changes"
  end

  defp guest_info_submit_label(_), do: "Save changes"

  defp create_delta_payment_intent(booking, delta, user) do
    amount_cents = MoneyHelper.money_to_cents(delta)

    payment_intent_params = %{
      amount: amount_cents,
      currency: "usd",
      metadata: %{
        booking_id: booking.id,
        booking_reference: booking.reference_id,
        property: Atom.to_string(booking.property),
        user_id: user.id,
        modification: "true"
      },
      description: "Booking modification #{booking.reference_id}",
      automatic_payment_methods: %{enabled: true}
    }

    payment_intent_params =
      if user.stripe_id do
        Map.put(payment_intent_params, :customer, user.stripe_id)
      else
        payment_intent_params
      end

    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
    attempt_id = System.unique_integer([:positive])

    idempotency_key =
      "booking_modification_#{booking.id}_#{amount_cents}_#{attempt_id}"

    stripe_client.create_payment_intent(payment_intent_params,
      idempotency_key: idempotency_key
    )
  end

  defp format_changeset_errors(changeset) do
    YscWeb.FormHelpers.format_changeset_errors(changeset, style: :flat)
  end

  defp modification_error_message(:blackout_conflict),
    do: YscWeb.BookingUserMessages.unavailable_blackout_dates()

  defp modification_error_message(:property_unavailable),
    do: "The selected dates or guest count are not available."

  defp modification_error_message(:room_unavailable),
    do: "One or more of your rooms are not available for the selected dates."

  defp modification_error_message(:property_buyout_active),
    do:
      "The whole cabin is already reserved for those dates. Please choose different dates."

  defp modification_error_message(:rooms_already_booked),
    do: "Rooms are already booked for the selected dates."

  defp modification_error_message(:payment_required),
    do: "Additional payment is required to confirm these changes."

  defp modification_error_message(:payment_not_succeeded),
    do: "Payment was not completed. Please try again."

  defp modification_error_message(:payment_amount_mismatch),
    do:
      "We couldn't confirm your payment for these date changes. You have not been charged for the change yet. Please try again, or contact info@ysc.org if the problem continues."

  defp modification_error_message(:payment_metadata_mismatch),
    do:
      "We couldn't verify your payment. Your reservation has not been changed yet. Please try again."

  defp modification_error_message(:inventory_update_failed),
    do:
      "Availability changed while updating your reservation. Please try again."

  defp modification_error_message(:checkin_in_past),
    do: "Check-in date cannot be in the past."

  defp modification_error_message(:modification_hold_expired),
    do:
      "Time ran out before payment finished. Your original reservation is unchanged. Please start your date change again."

  defp modification_error_message(:modification_hold_mismatch),
    do:
      "Your reservation details changed while payment was in progress. Please start again."

  defp modification_error_message(reason) when is_atom(reason),
    do:
      "We couldn't update your reservation. Please try again. If this keeps happening, contact info@ysc.org."

  defp modification_error_message(_),
    do: "Unable to update reservation. Please try again."

  defp property_label(:tahoe), do: "Tahoe"
  defp property_label(:clear_lake), do: "Clear Lake"

  defp property_label(property),
    do: property |> to_string() |> String.capitalize()

  defp submit_button_label(%{delta: %Money{} = delta}) do
    if Money.positive?(delta), do: "Continue to payment", else: "Save changes"
  end

  defp submit_button_label(_), do: "Save changes"

  defp modification_is_downgrade?(%{
         new_total: new_total,
         previous_total: previous_total
       }) do
    case Money.sub(new_total, previous_total) do
      {:ok, delta} -> Money.negative?(delta)
      _ -> false
    end
  end

  defp modification_is_downgrade?(_), do: false

  defp room_total_capacity(%Booking{rooms: rooms}) when is_list(rooms) do
    Enum.reduce(rooms, 0, fn room, acc -> acc + (room.capacity_max || 0) end)
  end

  defp room_total_capacity(_), do: 0

  defp parse_form_count(%Phoenix.HTML.Form{} = form, field) do
    form.params
    |> Map.get(Atom.to_string(field), form[field].value)
    |> parse_form_count_value()
  end

  defp parse_form_count_value(value) when is_integer(value), do: max(0, value)

  defp parse_form_count_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> max(0, int)
      :error -> 0
    end
  end

  defp parse_form_count_value(_), do: 0

  defp max_adults_for_modification(
         %Booking{booking_mode: :room} = booking,
         form
       ) do
    capacity = room_total_capacity(booking)
    children = parse_form_count(form, :children_count)
    max(1, capacity - children)
  end

  defp max_adults_for_modification(_booking, _form), do: nil

  defp max_children_for_modification(
         %Booking{booking_mode: :room} = booking,
         form
       ) do
    capacity = room_total_capacity(booking)
    guests = parse_form_count(form, :guests_count)
    max(0, capacity - guests)
  end

  defp max_children_for_modification(_booking, _form), do: nil

  defp checkout_tooltips_for_params(socket, params) do
    checkin =
      params
      |> Map.get("checkin_date", "")
      |> parse_date_param()

    if checkin do
      ModificationDateAvailability.checkout_date_tooltips(
        socket.assigns.booking,
        checkin,
        socket.assigns.calendar_max_date,
        socket.assigns.today,
        socket.assigns.seasons,
        socket.assigns.availability_snapshot
      )
    else
      %{}
    end
  end
end
