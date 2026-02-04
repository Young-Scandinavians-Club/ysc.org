defmodule YscWeb.AdminBookingsLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import Phoenix.HTML
  import YscWeb.CoreComponents
  import YscWeb.Components.Autocomplete
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Bookings
  alias Ysc.MoneyHelper
  alias Ysc.Accounts
  alias Ysc.Ledgers.{Payment, Refund}
  alias Ysc.Repo
  import Ecto.Query
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <!-- New/Edit Blackout Modal -->
      <.modal
        :if={@live_action in [:new_blackout, :edit_blackout]}
        id="blackout-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
      >
        <.header>
          <%= if @live_action == :new_blackout,
            do: "New Blackout",
            else: "Edit Blackout" %>
        </.header>

        <.simple_form
          for={@blackout_form}
          id="blackout-form"
          phx-submit="save-blackout"
          phx-change="validate-blackout"
        >
          <.input
            type="hidden"
            field={@blackout_form[:property]}
            value={Atom.to_string(@selected_property)}
          />

          <.input
            type="text"
            field={@blackout_form[:reason]}
            label="Reason"
            placeholder="e.g., Maintenance, Event, etc."
            required
          />

          <.input
            type="date"
            field={@blackout_form[:start_date]}
            label="Start Date"
            required
          />

          <.input
            type="date"
            field={@blackout_form[:end_date]}
            label="End Date"
            required
          />

          <:actions>
            <div class="flex justify-between w-full">
              <div>
                <button
                  :if={@live_action == :edit_blackout}
                  type="button"
                  phx-click="delete-blackout"
                  phx-value-id={@blackout.id}
                  phx-disable-with="Deleting..."
                  data-confirm="Are you sure you want to delete this blackout?"
                  class="rounded bg-red-600 hover:bg-red-700 py-2 px-4 transition duration-200 text-sm font-semibold text-white active:text-white/80"
                >
                  <.icon name="hero-trash" class="w-4 h-4 -mt-0.5" /> Delete
                </button>
              </div>
              <div class="flex gap-2">
                <.button phx-click={
                  JS.navigate(
                    ~p"/admin/bookings?property=#{@selected_property}&from_date=#{Date.to_string(@calendar_start_date)}&to_date=#{Date.to_string(@calendar_end_date)}"
                  )
                }>
                  Cancel
                </.button>
                <.button
                  type="submit"
                  phx-disable-with={
                    if @live_action == :new_blackout,
                      do: "Creating...",
                      else: "Updating..."
                  }
                >
                  <%= if @live_action == :new_blackout, do: "Create", else: "Update" %>
                </.button>
              </div>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- New/Edit Pricing Rule Modal -->
      <.modal
        :if={@live_action in [:new_pricing_rule, :edit_pricing_rule]}
        id="pricing-rule-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
      >
        <.header>
          <%= if @live_action == :new_pricing_rule,
            do: "New Pricing Rule",
            else: "Edit Pricing Rule" %>
        </.header>

        <.simple_form
          for={@form}
          id="pricing-rule-form"
          phx-submit="save-pricing-rule"
          phx-change="validate-pricing-rule"
        >
          <.input
            type="hidden"
            field={@form[:property]}
            value={Atom.to_string(@selected_property)}
          />

          <.input
            type="select"
            field={@form[:booking_mode]}
            label="Booking Mode"
            options={[
              {"Room", "room"},
              {"Day", "day"},
              {"Buyout", "buyout"}
            ]}
            required
          />

          <.input
            type="select"
            field={@form[:price_unit]}
            label="Price Unit"
            options={[
              {"Per person/night", "per_person_per_night"},
              {"Per guest/day", "per_guest_per_day"},
              {"Buyout fixed", "buyout_fixed"}
            ]}
            required
          />

          <.input
            type="text"
            field={@form[:amount]}
            label="Adult Amount"
            placeholder="0.00"
            id="adult_amount_input"
            phx-hook="MoneyInput"
            value={format_money_for_input(@form[:amount].value)}
            required
          >
            <div class="text-zinc-800">$</div>
          </.input>

          <.input
            type="text"
            field={@form[:children_amount]}
            label="Children Amount (optional)"
            placeholder="0.00"
            id="children_amount_input"
            phx-hook="MoneyInput"
            value={format_money_for_input(@form[:children_amount].value)}
          >
            <div class="text-zinc-800">$</div>
          </.input>
          <p class="mt-1 text-sm text-zinc-600">
            Children pricing for this rule. If not set, falls back to $25/night for Tahoe room bookings.
          </p>

          <.input
            type="select"
            field={@form[:season_id]}
            label="Season (optional)"
            prompt="All seasons"
            options={season_options(@filtered_seasons)}
          />

          <.input
            type="select"
            field={@form[:room_category_id]}
            label="Room Category (optional)"
            prompt="None - property-level pricing"
            options={room_category_options(@room_categories)}
          />

          <.input
            type="select"
            field={@form[:room_id]}
            label="Room (optional - most specific)"
            prompt="None"
            options={room_options(@rooms, @selected_property)}
          />

          <:actions>
            <.button phx-click={
              JS.navigate(
                ~p"/admin/bookings?property=#{@selected_property}&section=#{@current_section}"
              )
            }>
              Cancel
            </.button>
            <.button
              type="submit"
              phx-disable-with={
                if @live_action == :new_pricing_rule,
                  do: "Creating...",
                  else: "Updating..."
              }
            >
              <%= if @live_action == :new_pricing_rule, do: "Create", else: "Update" %>
            </.button>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- Edit Season Modal -->
      <.modal
        :if={@live_action == :edit_season}
        id="season-modal"
        on_cancel={
          JS.navigate(
            ~p"/admin/bookings?property=#{@selected_property}&section=config"
          )
        }
        show
      >
        <.header>
          Edit Season
        </.header>

        <.simple_form
          for={@season_form}
          id="season-form"
          phx-submit="save-season"
          phx-change="validate-season"
        >
          <.input
            type="text"
            field={@season_form[:name]}
            label="Name"
            placeholder="e.g., Winter, Summer"
            required
          />

          <.input
            type="textarea"
            field={@season_form[:description]}
            label="Description"
            placeholder="Optional description of this season"
          />

          <.input
            type="select"
            field={@season_form[:property]}
            label="Property"
            options={[
              {"Lake Tahoe", "tahoe"},
              {"Clear Lake", "clear_lake"}
            ]}
            required
          />

          <.input
            type="date"
            field={@season_form[:start_date]}
            label="Start Date"
            required
          />

          <.input
            type="date"
            field={@season_form[:end_date]}
            label="End Date"
            required
          />

          <.input
            type="number"
            field={@season_form[:advance_booking_days]}
            label="Advance Booking Days"
            placeholder="Leave empty for no limit"
            min="0"
          >
            <p class="text-xs text-zinc-500 mt-1">
              Number of days in advance bookings can be made for this season. Leave empty or set to 0 for no limit.
            </p>
          </.input>

          <.input
            type="number"
            field={@season_form[:max_nights]}
            label="Maximum Nights"
            placeholder="Leave empty for property default"
            min="1"
          >
            <p class="text-xs text-zinc-500 mt-1">
              Maximum number of nights allowed for bookings in this season. Leave empty to use property default (4 for Tahoe, 30 for Clear Lake).
            </p>
          </.input>

          <.input
            type="checkbox"
            field={@season_form[:is_default]}
            label="Default Season"
          >
            <p class="text-xs text-zinc-500 mt-1">
              Only one default season allowed per property
            </p>
          </.input>

          <:actions>
            <div class="flex justify-between w-full">
              <div></div>
              <div class="flex gap-2">
                <.button phx-click={
                  JS.navigate(
                    ~p"/admin/bookings?property=#{@selected_property}&section=config"
                  )
                }>
                  Cancel
                </.button>
                <.button type="submit" phx-disable-with="Updating...">
                  Update
                </.button>
              </div>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- Approve Refund Modal -->
      <.modal
        :if={@selected_pending_refund && @approve_refund_form}
        id="approve-refund-modal"
        on_cancel={JS.push("close-approve-refund-modal")}
        show
      >
        <.header>Approve Refund - Custom Amount</.header>

        <.simple_form
          for={@approve_refund_form}
          id="approve-refund-form"
          phx-submit="approve-refund-custom"
        >
          <div class="mb-4 p-4 bg-zinc-50 rounded border border-zinc-200">
            <p class="text-sm text-zinc-600 mb-2">
              <span class="font-medium">Total Amount Paid:</span>
              <%= MoneyHelper.format_money!(@selected_pending_refund.payment.amount) %>
            </p>
            <p class="text-sm text-zinc-600 mb-2">
              <span class="font-medium">Policy Refund Amount:</span>
              <%= MoneyHelper.format_money!(
                @selected_pending_refund.policy_refund_amount
              ) %>
            </p>
            <p class="text-xs text-zinc-500">
              You can approve a different amount than the policy amount if needed.
            </p>
          </div>

          <.input
            type="text"
            name="approve_refund[admin_refund_amount]"
            label="Refund Amount"
            placeholder={
              MoneyHelper.format_money!(
                @selected_pending_refund.policy_refund_amount
              )
            }
            id="admin_refund_amount_input"
            phx-hook="MoneyInput"
            value=""
          >
            <div class="text-zinc-800">$</div>
          </.input>

          <.input
            type="textarea"
            name="approve_refund[admin_notes]"
            label="Admin Notes (Optional)"
            placeholder="Add any notes about this refund approval..."
            rows="3"
            value=""
          />

          <:actions>
            <div class="flex justify-end gap-2">
              <.button phx-click="close-approve-refund-modal" type="button">
                Cancel
              </.button>
              <.button
                type="submit"
                phx-disable-with="Approving..."
                class="bg-green-600 hover:bg-green-700 text-white"
              >
                Approve Refund
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- Reject Refund Modal -->
      <.modal
        :if={@selected_pending_refund && @reject_refund_form}
        id="reject-refund-modal"
        on_cancel={JS.push("close-reject-refund-modal")}
        show
      >
        <.header>Reject Refund</.header>

        <.simple_form
          for={@reject_refund_form}
          id="reject-refund-form"
          phx-submit="reject-refund"
        >
          <div class="mb-4 p-4 bg-red-50 rounded border border-red-200">
            <p class="text-sm text-red-800 mb-2">
              <span class="font-medium">Policy Refund Amount:</span>
              <%= MoneyHelper.format_money!(
                @selected_pending_refund.policy_refund_amount
              ) %>
            </p>
            <p class="text-xs text-red-600">
              This refund will be rejected and no payment will be processed.
            </p>
          </div>

          <.input
            type="textarea"
            name="reject_refund[admin_notes]"
            label="Rejection Reason (Required)"
            placeholder="Please explain why this refund is being rejected..."
            rows="3"
            required
            value=""
          />

          <:actions>
            <div class="flex justify-end gap-2">
              <.button phx-click="close-reject-refund-modal" type="button">
                Cancel
              </.button>
              <.button type="submit" phx-disable-with="Rejecting..." color="red">
                Reject Refund
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- View Booking Modal -->
      <.modal
        :if={@live_action == :view_booking}
        id="booking-modal"
        on_cancel={JS.push("close-booking-modal")}
        show
      >
        <.header>
          <div class="flex items-start justify-between w-full">
            <div>
              <div class="flex items-center gap-3">
                <span>Booking Details</span>
                <% badge_type =
                  case @booking.status do
                    :complete -> "green"
                    :canceled -> "red"
                    :refunded -> "yellow"
                    :hold -> "sky"
                    :draft -> "dark"
                    _ -> "dark"
                  end %>
                <.badge type={badge_type}>
                  <%= String.upcase(to_string(@booking.status)) %>
                </.badge>
              </div>
              <div :if={@booking.inserted_at} class="mt-1 text-xs text-zinc-500">
                Booked <%= format_datetime(@booking.inserted_at, @timezone) %>
              </div>
            </div>
          </div>
        </.header>

        <div :if={@booking} class="mt-6 space-y-6">
          <div class="grid grid-cols-3 gap-x-4 gap-y-5">
            <div class="col-span-2">
              <label class="block text-sm font-semibold text-zinc-700 mb-2">
                Guest Details
              </label>
              <div class="flex items-center gap-3">
                <% user_initials =
                  if @booking.user && @booking.user.first_name &&
                       @booking.user.last_name do
                    "#{String.first(@booking.user.first_name)}#{String.first(@booking.user.last_name)}"
                  else
                    "?"
                  end %>
                <div class="flex-shrink-0 w-10 h-10 rounded-full bg-blue-100 text-blue-700 flex items-center justify-center font-semibold text-sm">
                  <%= user_initials %>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-zinc-900 truncate">
                    <%= if @booking.user do
                      if @booking.user.first_name && @booking.user.last_name do
                        "#{@booking.user.first_name} #{@booking.user.last_name}"
                      else
                        @booking.user.email || "Unknown User"
                      end
                    else
                      "Unknown User"
                    end %>
                  </p>
                  <p
                    :if={@booking.user && @booking.user.email}
                    class="text-xs text-zinc-500 truncate"
                  >
                    <%= @booking.user.email %>
                  </p>
                </div>
              </div>
              <div class="mt-3 flex items-center gap-4 text-xs">
                <div class="flex items-center gap-1.5">
                  <span class="font-semibold text-zinc-700">
                    <%= @booking.guests_count %>
                  </span>
                  <span class="text-zinc-600">
                    <%= if @booking.guests_count == 1, do: "Adult", else: "Adults" %>
                  </span>
                </div>
                <div class="flex items-center gap-1.5">
                  <span class="font-semibold text-zinc-700">
                    <%= @booking.children_count || 0 %>
                  </span>
                  <span class="text-zinc-600">
                    <%= if (@booking.children_count || 0) == 1,
                      do: "Child",
                      else: "Children" %>
                  </span>
                </div>
              </div>
              <div
                :if={
                  Ecto.assoc_loaded?(@booking.booking_guests) &&
                    length(@booking.booking_guests) > 0
                }
                class="my-3 pt-3 border-t border-zinc-200"
              >
                <p class="text-xs font-semibold text-zinc-600 mb-2">
                  All Guests (<%= length(@booking.booking_guests) %>)
                </p>
                <div class="space-y-1.5">
                  <%= for guest <- Enum.sort_by(@booking.booking_guests, & &1.order_index) do %>
                    <div class="flex items-center gap-2 text-xs">
                      <div class="flex-shrink-0 w-6 h-6 rounded-full bg-zinc-100 text-zinc-600 flex items-center justify-center font-medium text-[10px]">
                        <%= "#{String.first(guest.first_name)}#{String.first(guest.last_name)}" %>
                      </div>
                      <span class="text-zinc-900">
                        <%= "#{guest.first_name} #{guest.last_name}" %>
                      </span>
                      <span :if={guest.is_child} class="text-zinc-500">
                        (Child)
                      </span>
                      <span
                        :if={guest.is_booking_user}
                        class="text-blue-600 font-medium"
                      >
                        (Booker)
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="bg-zinc-50/50 rounded-lg p-3 border border-zinc-200 space-y-4">
              <div>
                <label class="block text-sm font-semibold text-zinc-700 mb-2">
                  Property
                </label>
                <p class="text-base font-bold text-zinc-900">
                  <%= atom_to_readable(@booking.property) %>
                </p>
              </div>
              <div>
                <label class="block text-sm font-semibold text-zinc-700 mb-2">
                  Booking Mode
                </label>
                <.badge type="default">
                  <%= atom_to_readable(@booking.booking_mode) %>
                </.badge>
              </div>
            </div>

            <div class="col-span-2 bg-zinc-50 rounded-lg p-3 border border-zinc-200 mt-3">
              <div class="grid grid-cols-3 gap-4">
                <div>
                  <label class="block text-xs font-semibold text-zinc-600 mb-1">
                    Check-in
                  </label>
                  <p class="text-sm text-zinc-900">
                    <%= Calendar.strftime(@booking.checkin_date, "%B %d, %Y") %>
                  </p>
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-600 mb-1">
                    Check-out
                  </label>
                  <p class="text-sm text-zinc-900">
                    <%= Calendar.strftime(@booking.checkout_date, "%B %d, %Y") %>
                  </p>
                </div>

                <div>
                  <label class="block text-xs font-semibold text-zinc-600 mb-1">
                    Nights
                  </label>
                  <p class="text-sm text-zinc-900">
                    <%= Date.diff(@booking.checkout_date, @booking.checkin_date) %>
                  </p>
                </div>
              </div>
            </div>

            <div class="col-span-1"></div>

            <div
              :if={Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0}
              class="col-span-2 mt-3"
            >
              <label class="block text-sm font-semibold text-zinc-700 mb-2">
                <%= if length(@booking.rooms) == 1, do: "Room", else: "Rooms" %>
              </label>
              <div class="flex flex-wrap gap-2">
                <%= for room <- @booking.rooms do %>
                  <div class="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-zinc-100 border border-zinc-200">
                    <span class="text-sm font-semibold text-zinc-900">
                      <%= room.name %>
                    </span>
                    <span :if={room.room_category} class="text-xs text-zinc-600">
                      <%= atom_to_readable(room.room_category.name) %>
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Payments Section -->
          <div class="pt-4 border-t border-zinc-200">
            <h3 class="text-sm font-semibold text-zinc-700 mb-3">Payments</h3>
            <div :if={length(@booking_payments) > 0} class="space-y-3">
              <%= for payment <- @booking_payments do %>
                <% payment_status_type =
                  case payment.status do
                    :completed -> "green"
                    :pending -> "yellow"
                    :failed -> "red"
                    _ -> "dark"
                  end %>
                <div class="bg-zinc-50 rounded-lg p-3 border border-zinc-200">
                  <div class="flex justify-between items-start">
                    <div class="flex-1 space-y-2">
                      <div class="flex items-center gap-2">
                        <span class="text-sm font-medium text-zinc-900 font-mono">
                          <%= payment.reference_id %>
                        </span>
                        <button
                          type="button"
                          phx-hook="ClipboardCopy"
                          id={"copy-payment-ref-#{payment.id}"}
                          data-copy={payment.reference_id}
                          class="text-zinc-400 hover:text-zinc-600 transition-colors"
                          title="Copy reference ID"
                        >
                          <.icon name="hero-clipboard" class="w-4 h-4 -mt-1" />
                        </button>
                        <.badge type={payment_status_type}>
                          <%= String.capitalize(to_string(payment.status)) %>
                        </.badge>
                      </div>
                      <p class="text-sm font-semibold text-zinc-900">
                        <%= MoneyHelper.format_money!(payment.amount) %>
                      </p>
                      <p :if={payment.payment_date} class="text-xs text-zinc-500">
                        <%= format_datetime(payment.payment_date, @timezone) %>
                      </p>
                      <div
                        :if={payment.external_payment_id}
                        class="flex items-center gap-2"
                      >
                        <a
                          href={"https://dashboard.stripe.com/payments/#{payment.external_payment_id}"}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="text-xs text-zinc-400 hover:text-blue-600 font-mono transition-colors underline decoration-dotted"
                          title="View in Stripe Dashboard"
                        >
                          <%= payment.external_payment_id %>
                        </a>
                        <button
                          type="button"
                          phx-hook="ClipboardCopy"
                          id={"copy-stripe-payment-#{payment.id}"}
                          data-copy={payment.external_payment_id}
                          class="text-zinc-400 hover:text-zinc-600 transition-colors"
                          title="Copy Stripe ID"
                        >
                          <.icon name="hero-clipboard" class="w-4 h-4 -mt-1" />
                        </button>
                      </div>
                      <p
                        :if={payment.quickbooks_sales_receipt_id}
                        class="text-xs text-green-600"
                      >
                        QuickBooks: <%= payment.quickbooks_sales_receipt_id %>
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
            <div
              :if={length(@booking_payments) == 0}
              class="rounded-lg border-2 border-dashed border-zinc-300 p-4 text-center"
            >
              <p class="text-sm text-zinc-500">
                No payments found for this booking.
              </p>
            </div>
          </div>
          <!-- Refunds Section -->
          <div class="pt-4 border-t border-zinc-200">
            <h3 class="text-sm font-semibold text-zinc-700 mb-3">Refunds</h3>
            <div :if={length(@booking_refunds) > 0} class="space-y-3">
              <%= for refund <- @booking_refunds do %>
                <% refund_status_type =
                  case refund.status do
                    :completed -> "green"
                    :pending -> "yellow"
                    :failed -> "red"
                    _ -> "dark"
                  end %>
                <div class="bg-zinc-50 rounded-lg p-3 border border-zinc-200">
                  <div class="flex justify-between items-start">
                    <div class="flex-1 space-y-2">
                      <div class="flex items-center gap-2">
                        <span class="text-sm font-medium text-zinc-900 font-mono">
                          <%= refund.reference_id %>
                        </span>
                        <button
                          type="button"
                          phx-hook="ClipboardCopy"
                          id={"copy-refund-ref-#{refund.id}"}
                          data-copy={refund.reference_id}
                          class="text-zinc-400 hover:text-zinc-600 transition-colors"
                          title="Copy reference ID"
                        >
                          <.icon name="hero-clipboard" class="w-4 h-4 -mt-1" />
                        </button>
                        <.badge type={refund_status_type}>
                          <%= String.capitalize(to_string(refund.status)) %>
                        </.badge>
                      </div>
                      <p class="text-sm font-semibold text-zinc-900">
                        <%= MoneyHelper.format_money!(refund.amount) %>
                      </p>
                      <p :if={refund.reason} class="text-xs text-zinc-600">
                        Reason: <%= refund.reason %>
                      </p>
                      <p :if={refund.inserted_at} class="text-xs text-zinc-500">
                        <%= format_datetime(refund.inserted_at, @timezone) %>
                      </p>
                      <div
                        :if={refund.external_refund_id}
                        class="flex items-center gap-2"
                      >
                        <a
                          href={"https://dashboard.stripe.com/refunds/#{refund.external_refund_id}"}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="text-xs text-zinc-400 hover:text-blue-600 font-mono transition-colors underline decoration-dotted"
                          title="View in Stripe Dashboard"
                        >
                          <%= refund.external_refund_id %>
                        </a>
                        <button
                          type="button"
                          phx-hook="ClipboardCopy"
                          id={"copy-stripe-refund-#{refund.id}"}
                          data-copy={refund.external_refund_id}
                          class="text-zinc-400 hover:text-zinc-600 transition-colors"
                          title="Copy Stripe refund ID"
                        >
                          <.icon name="hero-clipboard" class="w-4.0 h-4.0 -mt-1" />
                        </button>
                      </div>
                      <p
                        :if={refund.quickbooks_sales_receipt_id}
                        class="text-xs text-green-600"
                      >
                        QuickBooks: <%= refund.quickbooks_sales_receipt_id %>
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
            <div
              :if={length(@booking_refunds) == 0}
              class="rounded-lg border-2 border-dashed border-zinc-300 p-4 text-center"
            >
              <p class="text-sm text-zinc-500">
                No refunds found for this booking.
              </p>
            </div>
          </div>
          <!-- Check-in Section -->
          <div class="pt-4 border-t border-zinc-200">
            <h3 class="text-sm font-semibold text-zinc-700 mb-3">
              Check-in Details
            </h3>
            <div
              :if={
                Ecto.assoc_loaded?(@booking.check_ins) &&
                  length(@booking.check_ins) > 0
              }
              class="space-y-3"
            >
              <%= for check_in <- @booking.check_ins do %>
                <div class="bg-green-50 rounded-lg p-3 border border-green-200">
                  <div class="flex items-center gap-2 mb-2">
                    <.icon name="hero-check-circle" class="w-5 h-5 text-green-600" />
                    <span class="text-sm font-semibold text-zinc-900">
                      Checked In
                    </span>
                  </div>
                  <div class="space-y-1 text-sm text-zinc-700">
                    <p>
                      <span class="font-medium">Time:</span>
                      <%= if check_in.checked_in_at do
                        format_datetime(check_in.checked_in_at, @timezone)
                      else
                        "—"
                      end %>
                    </p>
                    <p>
                      <span class="font-medium">Rules Agreed:</span>
                      <%= if check_in.rules_agreed, do: "Yes", else: "No" %>
                    </p>
                    <%= if Ecto.assoc_loaded?(check_in.check_in_vehicles) && length(check_in.check_in_vehicles) > 0 do %>
                      <div class="mt-2">
                        <p class="font-medium mb-1">Vehicles:</p>
                        <div class="space-y-1 ml-4">
                          <%= for vehicle <- check_in.check_in_vehicles do %>
                            <p class="text-xs">
                              <%= vehicle.type %> • <%= vehicle.color %> • <%= vehicle.make %>
                            </p>
                          <% end %>
                        </div>
                      </div>
                    <% else %>
                      <p class="text-xs text-zinc-500 mt-1">
                        No vehicles registered
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
            <div
              :if={
                !Ecto.assoc_loaded?(@booking.check_ins) ||
                  length(@booking.check_ins) == 0
              }
              class="rounded-lg border-2 border-dashed border-zinc-300 p-4 text-center"
            >
              <p class="text-sm text-zinc-500">
                No check-in recorded for this booking.
              </p>
            </div>
          </div>
        </div>

        <div class="flex justify-between items-center mt-6 pt-4 border-t border-zinc-200">
          <div class="flex gap-2">
            <.button
              :if={@primary_payment && length(@booking_refunds) == 0}
              phx-click="show-booking-refund-modal"
              phx-disable-with="Loading..."
              data-confirm="Are you sure you want to process a refund for this booking? This action will initiate a refund through Stripe."
              class="bg-red-600 hover:bg-red-700 text-white"
            >
              <.icon name="hero-arrow-uturn-left" class="w-4 h-4 -mt-0.5" />
              <span class="ms-1">Process Refund</span>
            </.button>
          </div>
          <div class="flex gap-2">
            <.button phx-click={
              query_params = %{
                "property" => Atom.to_string(@selected_property),
                "from_date" => Date.to_string(@calendar_start_date),
                "to_date" => Date.to_string(@calendar_end_date)
              }

              query_string = URI.encode_query(query_params)

              JS.navigate(
                "/admin/bookings/bookings/#{@booking.id}/edit?#{query_string}"
              )
            }>
              <.icon name="hero-pencil" class="w-4 h-4 -mt-0.5" />
              <span class="ms-1">Edit</span>
            </.button>
            <.button
              variant="outline"
              color="zinc"
              phx-click={
                query_params =
                  build_booking_modal_close_params(
                    @selected_property,
                    @calendar_start_date,
                    @calendar_end_date,
                    @current_section,
                    @reservation_params
                  )

                query_string = URI.encode_query(flatten_query_params(query_params))
                JS.navigate("/admin/bookings?#{query_string}")
              }
            >
              <.icon name="hero-x-mark" class="w-4 h-4 -mt-0.5" />
              <span class="ms-1">Done</span>
            </.button>
          </div>
        </div>
      </.modal>
      <!-- Refund Modal for Booking -->
      <.modal
        :if={@show_refund_modal && @primary_payment}
        id="booking-refund-modal"
        show
        on_cancel={JS.push("close-booking-refund-modal")}
        max_width="max-w-md"
        z_index="z-[60]"
      >
        <.header>
          Process Refund
        </.header>

        <div class="mb-4">
          <p class="text-sm text-zinc-600 mb-2">
            <strong>Payment:</strong> <%= @primary_payment.reference_id %>
          </p>
          <p class="text-sm text-zinc-600 mb-2">
            <strong>Amount:</strong> <%= MoneyHelper.format_money!(
              @primary_payment.amount
            ) %>
          </p>
          <p class="text-sm text-zinc-600 mb-2">
            <strong>Booking:</strong> <%= @booking.reference_id || @booking.id %>
          </p>
          <p :if={@booking.user} class="text-sm text-zinc-600">
            <strong>User:</strong> <%= @booking.user.email %>
          </p>
        </div>

        <.simple_form
          for={@refund_form}
          id="booking-refund-form"
          phx-submit="process-booking-refund"
          phx-change="validate-booking-refund"
        >
          <.input
            field={@refund_form[:amount]}
            type="text"
            label="Refund Amount"
            placeholder="e.g., 25.00"
            required
          />

          <.input
            field={@refund_form[:reason]}
            type="textarea"
            label="Reason for Refund"
            placeholder="Enter reason for refund..."
            required
          />

          <.input
            field={@refund_form[:release_availability]}
            type="checkbox"
            label="Release booking dates for others to book"
          />

          <:actions>
            <div class="flex justify-end gap-2 w-full">
              <.button type="button" phx-click="close-booking-refund-modal">
                Cancel
              </.button>
              <.button
                type="submit"
                phx-disable-with="Processing..."
                class="bg-red-600 hover:bg-red-700"
              >
                Process Refund
              </.button>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- New/Edit Refund Policy Modal -->
      <.modal
        :if={@live_action in [:new_refund_policy, :edit_refund_policy]}
        id="refund-policy-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
      >
        <.header>
          <%= if @live_action == :new_refund_policy,
            do: "New Refund Policy",
            else: "Edit Refund Policy" %>
        </.header>

        <.simple_form
          for={@refund_policy_form}
          id="refund-policy-form"
          phx-submit="save-refund-policy"
          phx-change="validate-refund-policy"
        >
          <.input
            type="hidden"
            field={@refund_policy_form[:property]}
            value={Atom.to_string(@selected_property)}
          />

          <.input
            type="text"
            field={@refund_policy_form[:name]}
            label="Policy Name"
            placeholder="e.g., Tahoe Full Cabin Cancellation Policy"
            required
          />

          <.input
            type="textarea"
            field={@refund_policy_form[:description]}
            label="Description"
            placeholder="Optional description of this refund policy"
          />

          <.input
            type="select"
            field={@refund_policy_form[:booking_mode]}
            label="Booking Mode"
            options={[
              {"Room", "room"},
              {"Day", "day"},
              {"Buyout", "buyout"}
            ]}
            required
          />

          <.input
            type="checkbox"
            field={@refund_policy_form[:is_active]}
            label="Active"
          >
            <p class="text-xs text-zinc-500 mt-1">
              Only one active policy allowed per property/booking mode combination
            </p>
          </.input>

          <:actions>
            <.button phx-click={
              JS.navigate(
                ~p"/admin/bookings?property=#{@selected_property}&section=#{@current_section}"
              )
            }>
              Cancel
            </.button>
            <.button
              type="submit"
              phx-disable-with={
                if @live_action == :new_refund_policy,
                  do: "Creating...",
                  else: "Updating..."
              }
            >
              <%= if @live_action == :new_refund_policy,
                do: "Create",
                else: "Update" %>
            </.button>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- Refund Policy Rules Modal -->
      <.modal
        :if={@live_action == :manage_refund_policy_rules}
        id="refund-policy-rules-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
      >
        <.header>
          Manage Refund Policy Rules
        </.header>

        <div :if={@refund_policy} class="space-y-4">
          <div class="bg-blue-50 rounded border border-blue-200 p-4 mb-4">
            <p class="text-sm font-semibold text-zinc-700 mb-1">
              <%= @refund_policy.name %>
            </p>
            <p class="text-xs text-zinc-600">
              <%= atom_to_readable(@refund_policy.property) %> • <%= atom_to_readable(
                @refund_policy.booking_mode
              ) %>
            </p>
          </div>
          <!-- Existing Rules -->
          <div class="mb-6">
            <h3 class="text-md font-semibold text-zinc-800 mb-3">Current Rules</h3>
            <div
              :if={@refund_policy_rules == []}
              class="text-sm text-zinc-500 italic py-4"
            >
              No rules configured. Add a rule below.
            </div>
            <div :if={@refund_policy_rules != []} class="space-y-2">
              <div
                :for={rule <- @refund_policy_rules}
                class="flex items-center justify-between p-3 bg-zinc-50 rounded border border-zinc-200"
              >
                <div class="flex-1">
                  <p class="text-sm font-semibold text-zinc-800">
                    <%= rule.days_before_checkin %> days before check-in
                  </p>
                  <p class="text-xs text-zinc-600">
                    <%= Decimal.to_float(rule.refund_percentage) %>% refund
                  </p>
                  <p :if={rule.description} class="text-xs text-zinc-500 mt-1">
                    <%= rule.description %>
                  </p>
                </div>
                <button
                  phx-click="delete-refund-policy-rule"
                  phx-value-rule-id={rule.id}
                  phx-disable-with="Deleting..."
                  data-confirm="Are you sure you want to delete this rule?"
                  class="text-red-600 hover:text-red-800 font-semibold text-sm"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
          <!-- Add New Rule Form -->
          <div class="border-t border-zinc-200 pt-4">
            <h3 class="text-md font-semibold text-zinc-800 mb-3">Add New Rule</h3>
            <.simple_form
              for={@refund_policy_rule_form}
              id="refund-policy-rule-form"
              phx-submit="save-refund-policy-rule"
              phx-change="validate-refund-policy-rule"
            >
              <.input
                type="number"
                field={@refund_policy_rule_form[:days_before_checkin]}
                label="Days Before Check-in"
                placeholder="e.g., 21"
                min="0"
                required
              >
                <p class="text-xs text-zinc-500 mt-1">
                  Cancellations within this many days before check-in will apply this rule
                </p>
              </.input>

              <.input
                type="number"
                field={@refund_policy_rule_form[:refund_percentage]}
                label="Refund Percentage"
                placeholder="e.g., 50"
                min="0"
                max="100"
                step="0.01"
                required
              >
                <p class="text-xs text-zinc-500 mt-1">
                  Percentage of original payment to refund (0-100)
                </p>
              </.input>

              <.input
                type="text"
                field={@refund_policy_rule_form[:description]}
                label="Description (optional)"
                placeholder="e.g., 50% forfeiture for late cancellation"
              />

              <.input
                type="number"
                field={@refund_policy_rule_form[:priority]}
                label="Priority"
                value={@refund_policy_rule_form[:priority].value || 0}
                min="0"
              >
                <p class="text-xs text-zinc-500 mt-1">
                  Lower number = higher priority when multiple rules match
                </p>
              </.input>

              <:actions>
                <.button type="submit" phx-disable-with="Adding...">
                  Add Rule
                </.button>
              </:actions>
            </.simple_form>
          </div>

          <div class="flex justify-end mt-6 pt-4 border-t border-zinc-200">
            <.button phx-click={
              query_params =
                build_booking_modal_close_params(
                  @selected_property,
                  @calendar_start_date,
                  @calendar_end_date,
                  @current_section,
                  @reservation_params
                )

              query_string = URI.encode_query(flatten_query_params(query_params))
              JS.navigate("/admin/bookings?#{query_string}")
            }>
              Close
            </.button>
          </div>
        </div>
      </.modal>
      <!-- New/Edit Booking Modal -->
      <.modal
        :if={@live_action in [:new_booking, :edit_booking]}
        id="booking-form-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
      >
        <.header>
          <%= if @live_action == :new_booking,
            do: "New Booking",
            else: "Edit Booking" %>
        </.header>

        <div
          :if={@live_action == :edit_booking && @booking}
          class="mb-4 p-3 bg-blue-50 rounded border border-blue-200"
        >
          <p class="text-sm text-blue-800">
            <span class="font-semibold">Reference:</span> <%= @booking.reference_id %>
          </p>
          <p class="text-xs text-blue-600 mt-1">
            Admin mode: Validation rules are bypassed
          </p>
        </div>

        <.simple_form
          for={@booking_form}
          id="booking-form"
          phx-submit="save-booking"
          phx-change="validate-booking"
        >
          <.input
            type="hidden"
            field={@booking_form[:property]}
            value={Atom.to_string(@selected_property)}
          />

          <.autocomplete
            id="booking-user-autocomplete"
            label="User"
            name="booking[user_id]"
            search_event="search-booking-users"
            select_event="select-booking-user"
            clear_event="clear-booking-user"
            search_value={@user_search}
            results={@user_search_results}
            selected={@selected_user}
            display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
            subtitle_fn={fn user -> user.email end}
            placeholder="Search by name or email..."
            required
          />

          <.input
            type="date"
            field={@booking_form[:checkin_date]}
            label="Check-in Date"
            required
          />

          <.input
            type="date"
            field={@booking_form[:checkout_date]}
            label="Check-out Date"
            required
          />

          <.input
            type="number"
            field={@booking_form[:guests_count]}
            label="Number of Adults"
            value={@booking_form[:guests_count].value || 1}
            min="1"
            required
          />

          <.input
            type="number"
            field={@booking_form[:children_count]}
            label="Number of Children (5-17 inclusive)"
            value={@booking_form[:children_count].value || 0}
            min="0"
          />

          <.input
            :if={@live_action == :edit_booking}
            type="select"
            field={@booking_form[:status]}
            label="Status"
            options={[
              {"Draft", "draft"},
              {"Hold", "hold"},
              {"Complete", "complete"},
              {"Refunded", "refunded"},
              {"Canceled", "canceled"}
            ]}
          />

          <input
            :if={@booking_type == :room}
            type="hidden"
            name="booking[room_id]"
            value={@booking_room_id}
          />

          <.input
            :if={@booking_type == :room}
            type="hidden"
            field={@booking_form[:booking_mode]}
            value="room"
          />

          <input
            :if={@booking_type == :buyout}
            type="hidden"
            name="booking[room_id]"
            value=""
          />

          <.input
            :if={@booking_type == :buyout}
            type="hidden"
            field={@booking_form[:booking_mode]}
            value="buyout"
          />

          <:actions>
            <div class="flex justify-between w-full">
              <div>
                <button
                  :if={@live_action == :edit_booking && @booking}
                  type="button"
                  phx-click="delete-booking"
                  phx-value-id={@booking.id}
                  phx-disable-with="Deleting..."
                  data-confirm="Are you sure you want to delete this booking? This action cannot be undone."
                  class="rounded bg-red-600 hover:bg-red-700 py-2 px-4 transition duration-200 text-sm font-semibold text-white active:text-white/80"
                >
                  <.icon name="hero-trash" class="w-4 h-4 -mt-0.5" /> Delete
                </button>
              </div>
              <div class="flex gap-2">
                <.button phx-click={
                  JS.navigate(
                    ~p"/admin/bookings?property=#{@selected_property}&from_date=#{Date.to_string(@calendar_start_date)}&to_date=#{Date.to_string(@calendar_end_date)}"
                  )
                }>
                  Cancel
                </.button>
                <.button
                  type="submit"
                  phx-disable-with={
                    if @live_action == :new_booking,
                      do: "Creating...",
                      else: "Updating..."
                  }
                >
                  <%= if @live_action == :new_booking,
                    do: "Create Booking",
                    else: "Update Booking" %>
                </.button>
              </div>
            </div>
          </:actions>
        </.simple_form>
      </.modal>
      <!-- New/Edit Room Modal -->
      <.modal
        :if={@live_action in [:new_room, :edit_room]}
        id="room-modal"
        on_cancel={
          query_params =
            build_booking_modal_close_params(
              @selected_property,
              @calendar_start_date,
              @calendar_end_date,
              @current_section,
              @reservation_params
            )

          query_string = URI.encode_query(flatten_query_params(query_params))
          JS.navigate("/admin/bookings?#{query_string}")
        }
        show
        max_width="max-w-4xl"
      >
        <.header>
          <%= if @live_action == :new_room, do: "New Room", else: "Edit Room" %>
        </.header>

        <.simple_form
          for={@room_form}
          id="room-form"
          phx-submit="save-room"
          phx-change="validate-room"
        >
          <.input
            type="hidden"
            field={@room_form[:property]}
            value={Atom.to_string(@selected_property)}
          />

          <.input
            type="text"
            field={@room_form[:name]}
            label="Room Name"
            placeholder="e.g., Master Bedroom, Guest Room"
            required
          />

          <.input
            type="textarea"
            field={@room_form[:description]}
            label="Description"
            placeholder="Optional description of the room"
            rows="3"
          />

          <.input
            type="select"
            field={@room_form[:room_category_id]}
            label="Room Category (optional)"
            prompt="None"
            options={room_category_options(@room_categories)}
          />

          <div class="grid grid-cols-2 gap-4">
            <.input
              type="number"
              field={@room_form[:capacity_max]}
              label="Maximum Capacity"
              value={@room_form[:capacity_max].value || 1}
              min="1"
              max="12"
              required
            />

            <.input
              type="number"
              field={@room_form[:min_billable_occupancy]}
              label="Minimum Billable Occupancy"
              value={@room_form[:min_billable_occupancy].value || 1}
              min="1"
            >
              <p class="text-xs text-zinc-500 mt-1">
                Minimum number of guests to bill for this room (e.g., family room = 2)
              </p>
            </.input>
          </div>

          <div class="grid grid-cols-3 gap-4">
            <.input
              type="number"
              field={@room_form[:single_beds]}
              label="Single Beds"
              value={@room_form[:single_beds].value || 0}
              min="0"
            />

            <.input
              type="number"
              field={@room_form[:queen_beds]}
              label="Queen Beds"
              value={@room_form[:queen_beds].value || 0}
              min="0"
            />

            <.input
              type="number"
              field={@room_form[:king_beds]}
              label="King Beds"
              value={@room_form[:king_beds].value || 0}
              min="0"
            />
          </div>

          <.input
            type="checkbox"
            field={@room_form[:is_single_bed]}
            label="Single Bed Room"
          >
            <p class="text-xs text-zinc-500 mt-1">
              Check if this room has only a single bed (max 1 person)
            </p>
          </.input>

          <.input type="checkbox" field={@room_form[:is_active]} label="Active">
            <p class="text-xs text-zinc-500 mt-1">
              Inactive rooms won't appear in booking options
            </p>
          </.input>
          <!-- Image Selection -->
          <div class="space-y-2">
            <label class="block text-sm font-semibold text-zinc-700">
              Display Image
            </label>
            <div :if={@selected_room_image} class="mb-4">
              <div class="relative inline-block">
                <img
                  src={
                    @selected_room_image.thumbnail_path ||
                      @selected_room_image.optimized_image_path ||
                      @selected_room_image.raw_image_path
                  }
                  alt={@selected_room_image.title || "Selected image"}
                  class="w-32 h-32 rounded-lg object-cover border border-zinc-200"
                />
                <button
                  type="button"
                  phx-click="clear-room-image"
                  class="absolute -top-2 -right-2 bg-red-600 text-white rounded-full w-6 h-6 flex items-center justify-center hover:bg-red-700"
                  title="Remove image"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            </div>
            <div :if={!@selected_room_image} class="mb-4">
              <p class="text-sm text-zinc-500 italic">No image selected</p>
            </div>
            <button
              type="button"
              phx-click="open-image-gallery"
              class="rounded bg-zinc-100 hover:bg-zinc-200 py-2 px-4 transition duration-200 text-sm font-semibold text-zinc-800"
            >
              <.icon name="hero-photo" class="w-4 h-4 -mt-0.5" />
              <span class="ms-1">Select from Image Library</span>
            </button>
            <input
              type="hidden"
              name="room[image_id]"
              value={if @selected_room_image, do: @selected_room_image.id, else: ""}
            />
          </div>
          <!-- Image Gallery Modal -->
          <div
            :if={@show_image_gallery}
            class="fixed inset-0 z-50 overflow-y-auto bg-black/50"
            phx-click="close-image-gallery"
            phx-click-away="close-image-gallery"
          >
            <div
              class="flex min-h-full items-center justify-center p-4"
              phx-click="close-image-gallery"
            >
              <div
                class="relative bg-white rounded-lg shadow-xl max-w-6xl w-full max-h-[90vh] overflow-hidden"
                phx-click-away="close-image-gallery"
              >
                <div class="flex items-center justify-between p-6 border-b border-zinc-200">
                  <h3 class="text-lg font-semibold text-zinc-800">Select Image</h3>
                  <button
                    type="button"
                    phx-click="close-image-gallery"
                    class="text-zinc-400 hover:text-zinc-600"
                  >
                    <.icon name="hero-x-mark" class="w-6 h-6" />
                  </button>
                </div>
                <div class="p-6 overflow-y-auto max-h-[calc(90vh-120px)]">
                  <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 gap-4">
                    <%= for image <- @image_gallery do %>
                      <button
                        type="button"
                        phx-click="select-room-image"
                        phx-value-image-id={image.id}
                        class="group relative w-full rounded-lg aspect-square border-2 border-zinc-200 cursor-pointer hover:border-blue-500 transition-all duration-200 overflow-hidden"
                      >
                        <img
                          src={
                            image.thumbnail_path || image.optimized_image_path ||
                              image.raw_image_path
                          }
                          alt={image.title || "Image"}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                        <div
                          :if={image.title || image.alt_text}
                          class="absolute z-[2] hidden group-hover:block inset-x-0 bottom-0 px-2 py-2 bg-gradient-to-t from-zinc-900/90 via-zinc-900/80 to-transparent"
                        >
                          <p
                            :if={image.title}
                            class="text-xs font-medium text-white truncate"
                            title={image.title}
                          >
                            <%= image.title %>
                          </p>
                        </div>
                      </button>
                    <% end %>
                  </div>
                  <div :if={@image_gallery == []} class="text-center py-12">
                    <p class="text-zinc-500">No images available</p>
                  </div>
                </div>
                <div class="flex justify-between items-center p-6 border-t border-zinc-200">
                  <div class="flex gap-2">
                    <.button
                      :if={@image_gallery_page > 1}
                      phx-click="prev-image-gallery-page"
                      type="button"
                    >
                      Previous
                    </.button>
                    <.button
                      :if={!@image_gallery_end?}
                      phx-click="next-image-gallery-page"
                      type="button"
                    >
                      Next
                    </.button>
                  </div>
                  <button
                    type="button"
                    phx-click="close-image-gallery"
                    class="rounded bg-zinc-100 hover:bg-zinc-200 py-2 px-4 transition duration-200 text-sm font-semibold text-zinc-800"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          </div>

          <:actions>
            <div class="flex justify-between w-full">
              <div>
                <button
                  :if={@live_action == :edit_room}
                  type="button"
                  phx-click="delete-room"
                  phx-value-id={@room.id}
                  phx-disable-with="Deleting..."
                  data-confirm="Are you sure you want to delete this room?"
                  class="rounded bg-red-600 hover:bg-red-700 py-2 px-4 transition duration-200 text-sm font-semibold text-white active:text-white/80"
                >
                  <.icon name="hero-trash" class="w-4 h-4 -mt-0.5" /> Delete
                </button>
              </div>
              <div class="flex gap-2">
                <.button phx-click={
                  JS.navigate(
                    ~p"/admin/bookings?property=#{@selected_property}&section=#{@current_section}"
                  )
                }>
                  Cancel
                </.button>
                <.button
                  type="submit"
                  phx-disable-with={
                    if @live_action == :new_room,
                      do: "Creating...",
                      else: "Updating..."
                  }
                >
                  <%= if @live_action == :new_room, do: "Create", else: "Update" %>
                </.button>
              </div>
            </div>
          </:actions>
        </.simple_form>
      </.modal>

      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          <%= atom_to_readable(@selected_property) %> Bookings
        </h1>
      </div>
      <!-- Property Tabs -->
      <div class="border-b border-zinc-200 mb-6">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <.notification_badge
            count={@tahoe_pending_refunds_count}
            badge_color="red"
          >
            <button
              phx-click={JS.navigate(~p"/admin/bookings?property=tahoe")}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_property == :tahoe,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Lake Tahoe
            </button>
          </.notification_badge>
          <.notification_badge
            count={@clear_lake_pending_refunds_count}
            badge_color="red"
          >
            <button
              phx-click={JS.navigate(~p"/admin/bookings?property=clear_lake")}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@selected_property == :clear_lake,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Clear Lake
            </button>
          </.notification_badge>
        </nav>
      </div>
      <!-- Section Tabs -->
      <div class="border-b border-zinc-200 mb-6">
        <nav class="-mb-px flex space-x-8" aria-label="Section Tabs">
          <button
            phx-click="select-section"
            phx-value-section="calendar"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
              if(@current_section == :calendar,
                do: "border-blue-500 text-blue-600",
                else:
                  "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
              )
            ]}
          >
            Calendar
          </button>
          <button
            phx-click="select-section"
            phx-value-section="reservations"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
              if(@current_section == :reservations,
                do: "border-blue-500 text-blue-600",
                else:
                  "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
              )
            ]}
          >
            Reservations
          </button>
          <button
            phx-click="select-section"
            phx-value-section="config"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
              if(@current_section == :config,
                do: "border-blue-500 text-blue-600",
                else:
                  "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
              )
            ]}
          >
            Configuration
          </button>
          <.notification_badge count={@pending_refunds_count} badge_color="red">
            <button
              phx-click="select-section"
              phx-value-section="pending_refunds"
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm transition-colors",
                if(@current_section == :pending_refunds,
                  do: "border-blue-500 text-blue-600",
                  else:
                    "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
                )
              ]}
            >
              Pending Refunds
            </button>
          </.notification_badge>
        </nav>
      </div>
      <!-- Calendar View -->
      <div :if={@current_section == :calendar} class="space-y-6 pb-16">
        <div class="bg-white rounded border p-3 sm:p-6">
          <div class="flex flex-col lg:flex-row lg:justify-between lg:items-center mb-4 sm:mb-6 gap-4">
            <div>
              <h2 class="text-base sm:text-lg font-semibold text-zinc-800">
                Calendar Overview
              </h2>
              <p class="text-xs sm:text-sm text-zinc-500 mt-1">
                Showing <%= Timex.format!(@calendar_start_date, "{Mshort} {D}") %> - <%= Timex.format!(
                  @calendar_end_date,
                  "{Mshort} {D}"
                ) %>
              </p>
            </div>
            <div class="flex flex-col lg:flex-row items-stretch lg:items-center gap-3 lg:gap-4">
              <!-- Date Range Inputs -->
              <form
                phx-change="update-calendar-range"
                phx-debounce="300"
                class="flex flex-row items-center gap-2"
              >
                <div class="flex items-center gap-2">
                  <.input
                    type="date"
                    value={Date.to_string(@calendar_start_date)}
                    name="from_date"
                    class="text-sm"
                  />
                </div>
                <div class="hidden sm:block">
                  <.icon name="hero-arrow-right" class="w-4 h-4 text-zinc-600 mt-1" />
                </div>
                <div class="flex items-center gap-2">
                  <.input
                    type="date"
                    value={Date.to_string(@calendar_end_date)}
                    name="to_date"
                    class="text-sm"
                  />
                </div>
              </form>
              <div class="flex gap-2">
                <.button
                  phx-click="prev-month"
                  title="Previous month"
                  class="flex-1 sm:flex-none mt-2"
                >
                  <.icon name="hero-arrow-left" class="w-5 h-5" />
                </.button>
                <.button
                  phx-click="today"
                  title="Go to current month"
                  class="flex-1 sm:flex-none mt-2"
                >
                  <span class="hidden sm:inline">Today</span>
                  <span class="sm:hidden">Now</span>
                </.button>
                <.button
                  phx-click="next-month"
                  title="Next month"
                  class="flex-1 sm:flex-none mt-2"
                >
                  <.icon name="hero-arrow-right" class="w-5 h-5" />
                </.button>
              </div>
            </div>
          </div>

          <div
            class="flex relative"
            id="calendar-container"
            phx-hook="CalendarHover"
          >
            <% total_days = length(@calendar_dates)
            total_cols = total_days * 2 %>
            <!-- Fixed Left Column: Row Titles -->
            <div class="flex-shrink-0 w-[120px] sm:w-[180px] lg:w-[220px] border-r border-zinc-200 bg-white">
              <!-- Header: Room label -->
              <div class="border-b border-zinc-200 px-2 sm:px-3 py-2.5 text-left font-semibold text-zinc-700 bg-white text-sm">
                Room
              </div>
              <!-- Available Slots Row Title (only for Clear Lake) -->
              <%= if @selected_property == :clear_lake do %>
                <div class="border-b border-zinc-200 flex items-center gap-1 sm:gap-2 px-2 sm:px-3 h-12 bg-white">
                  <div class="h-2 w-2 rounded-full bg-purple-500 flex-shrink-0">
                  </div>
                  <div class="text-xs sm:text-sm font-medium text-zinc-800 truncate">
                    Available Slots
                  </div>
                </div>
              <% end %>
              <!-- Blackouts Row Title -->
              <div class="border-b border-zinc-200 flex items-center gap-1 sm:gap-2 px-2 sm:px-3 h-12 bg-white">
                <div class="h-2 w-2 rounded-full bg-red-500 flex-shrink-0"></div>
                <div class="text-xs sm:text-sm font-medium text-zinc-800 truncate">
                  Blackouts
                </div>
              </div>
              <!-- Full Buyout Row Title -->
              <div class="border-b border-zinc-200 flex items-center gap-1 sm:gap-2 px-2 sm:px-3 h-12 bg-white">
                <div class="h-2 w-2 rounded-full bg-green-500 flex-shrink-0"></div>
                <div class="text-xs sm:text-sm font-medium text-zinc-800 truncate">
                  Full Buyout
                </div>
              </div>
              <!-- Room Row Titles -->
              <%= for room <- @filtered_rooms do %>
                <div class="border-b border-zinc-200 flex items-center gap-1 sm:gap-2 px-2 sm:px-3 h-12 bg-white">
                  <div class="h-2 w-2 rounded-full bg-blue-500 flex-shrink-0"></div>
                  <div class="text-xs sm:text-sm font-medium text-zinc-800 truncate">
                    <%= room.name %>
                    <span
                      :if={room.room_category}
                      class="text-xs text-zinc-500 hidden sm:inline"
                    >
                      (<%= atom_to_readable(room.room_category.name) %>)
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
            <!-- Scrollable Right Area: Date Columns -->
            <div class="flex-1 overflow-x-auto">
              <!-- Header: Date columns -->
              <div>
                <div
                  class="grid text-xs text-zinc-600 select-none"
                  style={"grid-template-columns: repeat(#{total_cols}, minmax(56px, 1fr));"}
                >
                  <%= for date <- @calendar_dates do %>
                    <div class="col-span-2 flex items-center justify-center border-r border-zinc-200 border-b">
                      <div class={"flex flex-col items-center justify-center h-10 w-full relative #{if Date.compare(date, @today) == :eq, do: "bg-blue-100/20", else: ""}"}>
                        <span class="font-medium text-center">
                          <%= Calendar.strftime(date, "%a") %>
                        </span>
                        <span class="text-zinc-500 text-center">
                          <%= Calendar.strftime(date, "%m/%d") %>
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
              <!-- Available Slots Row (only for Clear Lake) -->
              <%= if @selected_property == :clear_lake do %>
                <div
                  class="relative grid"
                  style={"grid-template-columns: repeat(#{total_cols}, minmax(56px, 1fr));"}
                >
                  <%= for i <- 0..(total_cols - 1) do %>
                    <% base_bg =
                      cond do
                        today_col?(i, @calendar_dates, @today) -> "bg-blue-100/20"
                        true -> "bg-white"
                      end %>
                    <div
                      class={"h-12 border-b #{if today_col?(i, @calendar_dates, @today), do: "border-blue-100", else: "border-zinc-100"} #{base_bg} #{if rem(i + 1, 2) == 0, do: "relative", else: ""}"}
                      style={"grid-column: #{i + 1}; grid-row: 1;"}
                    >
                      <%= if rem(i + 1, 2) == 0 do %>
                        <div class={"absolute right-0 top-0 bottom-0 w-px bg-zinc-200 #{if today_col?(i, @calendar_dates, @today), do: "bg-blue-200", else: ""}"}>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= for {date, day_idx} <- Enum.with_index(@calendar_dates) do %>
                    <% availability_info = Map.get(@daily_availability, date) %>
                    <% col_start = day_idx * 2 + 1 %>
                    <% col_end = col_start + 2 %>
                    <%= if availability_info do %>
                      <div
                        class="flex items-center justify-center h-12"
                        style={"grid-column: #{col_start} / #{col_end}; grid-row: 1; position: relative; z-index: 1;"}
                      >
                        <span class={"text-sm font-semibold #{if availability_info.spots_available > 0, do: "text-green-600", else: "text-red-600"}"}>
                          <%= availability_info.spots_available %>/<%= 12 %> slots
                        </span>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
              <!-- Blackouts Row -->
              <div
                class="relative grid"
                style={"grid-template-columns: repeat(#{total_cols}, minmax(56px, 1fr));"}
              >
                <%= for i <- 0..(total_cols - 1) do %>
                  <% date = get_date_from_col(i, @calendar_dates) %>
                  <% is_selected_start =
                    @date_selection_type == :blackout && @date_selection_start &&
                      date &&
                      Date.compare(date, @date_selection_start) == :eq %>
                  <% hover_end =
                    if @date_selection_type == :blackout,
                      do: @date_selection_hover_end,
                      else: nil %>
                  <% is_in_range =
                    @date_selection_type == :blackout && @date_selection_start &&
                      date &&
                      date_selection_in_range?(
                        date,
                        @date_selection_start,
                        hover_end
                      ) %>
                  <% base_bg =
                    cond do
                      is_selected_start -> "bg-red-200"
                      is_in_range && !is_selected_start -> "bg-red-100/60"
                      today_col?(i, @calendar_dates, @today) -> "bg-blue-100/20"
                      true -> "bg-white"
                    end %>
                  <div
                    class={"h-12 border-b #{if today_col?(i, @calendar_dates, @today), do: "border-blue-100", else: "border-zinc-100"} #{base_bg} #{if rem(i + 1, 2) == 0, do: "relative", else: ""} cursor-pointer hover:bg-red-50 transition-colors"}
                    style={"grid-column: #{i + 1}; grid-row: 1;"}
                    phx-click="select-date-blackout"
                    phx-value-date={if date, do: Date.to_string(date), else: ""}
                    data-date={if date, do: Date.to_string(date), else: ""}
                    data-selection-type={
                      if @date_selection_type == :blackout, do: "blackout", else: ""
                    }
                    title={
                      if date,
                        do: "Click to select date range for blackout",
                        else: ""
                    }
                  >
                    <%= if rem(i + 1, 2) == 0 do %>
                      <div class={"absolute right-0 top-0 bottom-0 w-px bg-zinc-200 #{if today_col?(i, @calendar_dates, @today), do: "bg-blue-200", else: ""}"}>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <%= for blackout <- @filtered_blackouts do
                  raw(
                    render_blackout_div(blackout, @calendar_start_date, total_days)
                  )
                end %>
              </div>
              <!-- Full Buyout Row -->
              <div
                class="relative grid"
                style={"grid-template-columns: repeat(#{total_cols}, minmax(56px, 1fr));"}
              >
                <%= for i <- 0..(total_cols - 1) do %>
                  <% date = get_date_from_col(i, @calendar_dates) %>
                  <% is_selected_start =
                    @date_selection_type == :buyout && @date_selection_start && date &&
                      Date.compare(date, @date_selection_start) == :eq %>
                  <% hover_end =
                    if @date_selection_type == :buyout,
                      do: @date_selection_hover_end,
                      else: nil %>
                  <% is_in_range =
                    @date_selection_type == :buyout && @date_selection_start && date &&
                      date_selection_in_range?(
                        date,
                        @date_selection_start,
                        hover_end
                      ) %>
                  <% base_bg =
                    cond do
                      is_selected_start -> "bg-green-200"
                      is_in_range && !is_selected_start -> "bg-green-100/60"
                      today_col?(i, @calendar_dates, @today) -> "bg-blue-100/20"
                      true -> "bg-white"
                    end %>
                  <div
                    class={"h-12 border-b #{if today_col?(i, @calendar_dates, @today), do: "border-blue-100", else: "border-zinc-100"} #{base_bg} #{if rem(i + 1, 2) == 0, do: "relative", else: ""} cursor-pointer hover:bg-green-50 transition-colors"}
                    style={"grid-column: #{i + 1}; grid-row: 1;"}
                    phx-click="select-date-buyout"
                    phx-value-date={if date, do: Date.to_string(date), else: ""}
                    data-date={if date, do: Date.to_string(date), else: ""}
                    data-selection-type={
                      if @date_selection_type == :buyout, do: "buyout", else: ""
                    }
                    title={
                      if date,
                        do: "Click to select date range for buyout booking",
                        else: ""
                    }
                  >
                    <%= if rem(i + 1, 2) == 0 do %>
                      <div class={"absolute right-0 top-0 bottom-0 w-px bg-zinc-200 #{if today_col?(i, @calendar_dates, @today), do: "bg-blue-200", else: ""}"}>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <%= for booking <- @buyout_bookings do
                  raw(render_booking_div(booking, @calendar_start_date, total_days))
                end %>
              </div>
              <!-- Room Rows -->
              <%= for room <- @filtered_rooms do %>
                <div
                  class="relative grid"
                  style={"grid-template-columns: repeat(#{total_cols}, minmax(56px, 1fr));"}
                >
                  <%= for i <- 0..(total_cols - 1) do %>
                    <% date = get_date_from_col(i, @calendar_dates) %>
                    <% room_id_str = to_string(room.id) %>
                    <% is_selected_start =
                      @date_selection_type == :room && @date_selection_start &&
                        @date_selection_room_id == room_id_str && date &&
                        Date.compare(date, @date_selection_start) == :eq %>
                    <% hover_end =
                      if @date_selection_type == :room &&
                           @date_selection_room_id == room_id_str,
                         do: @date_selection_hover_end,
                         else: nil %>
                    <% is_in_range =
                      @date_selection_type == :room && @date_selection_start &&
                        @date_selection_room_id == room_id_str && date &&
                        date_selection_in_range?(
                          date,
                          @date_selection_start,
                          hover_end
                        ) %>
                    <% base_bg =
                      cond do
                        is_selected_start -> "bg-blue-200"
                        is_in_range && !is_selected_start -> "bg-blue-100/60"
                        today_col?(i, @calendar_dates, @today) -> "bg-blue-100/20"
                        true -> "bg-white"
                      end %>
                    <div
                      class={"h-12 border-b #{if today_col?(i, @calendar_dates, @today), do: "border-blue-100", else: "border-zinc-100"} #{base_bg} #{if rem(i + 1, 2) == 0, do: "relative", else: ""} cursor-pointer hover:bg-blue-50 transition-colors"}
                      style={"grid-column: #{i + 1}; grid-row: 1;"}
                      phx-click="select-date-room"
                      phx-value-date={if date, do: Date.to_string(date), else: ""}
                      phx-value-room-id={room.id}
                      data-date={if date, do: Date.to_string(date), else: ""}
                      data-selection-type={
                        if @date_selection_type == :room &&
                             @date_selection_room_id == room_id_str,
                           do: "room",
                           else: ""
                      }
                      data-room-id={room_id_str}
                      title={
                        if date,
                          do: "Click to select date range for #{room.name} booking",
                          else: ""
                      }
                    >
                      <%= if rem(i + 1, 2) == 0 do %>
                        <div class={"absolute right-0 top-0 bottom-0 w-px bg-zinc-200 #{if today_col?(i, @calendar_dates, @today), do: "bg-blue-200", else: ""}"}>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <%= for booking <-
                            @room_bookings
                            |> Enum.filter(fn b ->
                              Ecto.assoc_loaded?(b.rooms) &&
                                Enum.any?(b.rooms, &(&1.id == room.id))
                            end) do
                    raw(
                      render_booking_div(booking, @calendar_start_date, total_days)
                    )
                  end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      <!-- Reservations View -->
      <div :if={@current_section == :reservations} class="space-y-6 pb-16">
        <div class="bg-white rounded border p-3 sm:p-6">
          <div class="flex flex-col lg:flex-row lg:justify-between lg:items-center mb-4 sm:mb-6 gap-4">
            <div>
              <h2 class="text-base sm:text-lg font-semibold text-zinc-800">
                All Reservations
              </h2>
              <p class="text-xs sm:text-sm text-zinc-500 mt-1">
                Search and filter reservations for <%= atom_to_readable(
                  @selected_property
                ) %>
              </p>
            </div>
          </div>

          <div class="w-full pt-4">
            <div>
              <form
                action=""
                novalidate=""
                role="search"
                phx-change="change-reservation-search"
                phx-submit="change-reservation-search"
                phx-submit-disable
                class="relative"
              >
                <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
                  <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500" />
                </div>
                <input
                  id="reservation-search"
                  type="search"
                  name="search[query]"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  enterkeyhint="search"
                  spellcheck="false"
                  placeholder="Search by name, email or booking reference"
                  value={
                    case @reservation_params["search"] do
                      %{"query" => query} -> query
                      query when is_binary(query) -> query
                      _ -> ""
                    end
                  }
                  tabindex="0"
                  phx-debounce="200"
                  class="block pt-3 pb-3 ps-10 text-sm text-zinc-800 border border-zinc-200 rounded w-full bg-zinc-50 focus:ring-blue-500 focus:border-blue-500"
                />
              </form>
            </div>
            <div class="py-6 w-full overflow-x-auto">
              <Flop.Phoenix.table
                id="admin_reservations_list"
                items={@streams.reservations}
                meta={@reservation_meta}
                path={~p"/admin/bookings"}
              >
                <:col :let={{_, booking}} label="Reference" field={:reference_id}>
                  <.badge type="default" class="whitespace-nowrap">
                    <span class="font-mono text-xs flex-shrink-0 whitespace-nowrap">
                      <%= booking.reference_id %>
                    </span>
                  </.badge>
                </:col>
                <:col :let={{_, booking}} label="Guest" field={:user_name}>
                  <%= if booking.user do %>
                    <div>
                      <div class="text-sm font-semibold text-zinc-800">
                        <%= if booking.user.first_name && booking.user.last_name do
                          "#{booking.user.first_name} #{booking.user.last_name}"
                        else
                          booking.user.email || "Unknown User"
                        end %>
                      </div>
                      <%= if booking.user.email && (booking.user.first_name || booking.user.last_name) do %>
                        <div class="text-xs text-zinc-500 mt-0.5">
                          <%= booking.user.email %>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </:col>
                <:col :let={{_, booking}} label="Check-in" field={:checkin_date}>
                  <span class="text-sm text-zinc-800">
                    <%= Calendar.strftime(booking.checkin_date, "%b %d, %Y") %>
                  </span>
                </:col>
                <:col :let={{_, booking}} label="Check-out" field={:checkout_date}>
                  <span class="text-sm text-zinc-800">
                    <%= Calendar.strftime(booking.checkout_date, "%b %d, %Y") %>
                  </span>
                </:col>
                <:col :let={{_, booking}} label="Nights">
                  <span class="text-sm text-zinc-600">
                    <%= Date.diff(booking.checkout_date, booking.checkin_date) %>
                  </span>
                </:col>
                <:col :let={{_, booking}} label="Guests" field={:guests_count}>
                  <% adults_count = booking.guests_count

                  total_guests =
                    booking.guests_count + (booking.children_count || 0) %>
                  <div class="text-sm text-zinc-600">
                    <%= if adults_count > 0 do %>
                      <%= adults_count %> <%= if adults_count == 1,
                        do: "adult",
                        else: "adults" %>
                    <% end %>
                    <%= if (booking.children_count || 0) > 0 do %>
                      <%= if adults_count > 0, do: ", ", else: "" %><%= booking.children_count %> <%= if booking.children_count ==
                                                                                                           1,
                                                                                                         do:
                                                                                                           "child",
                                                                                                         else:
                                                                                                           "children" %>
                    <% end %>
                    <span class="text-zinc-500 ml-1">
                      (Total: <%= total_guests %> <%= if total_guests == 1,
                        do: "guest",
                        else: "guests" %>)
                    </span>
                  </div>
                </:col>
                <:col :let={{_, booking}} label="Room" field={:booking_mode}>
                  <%= if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do %>
                    <div class="space-y-1">
                      <%= for room <- booking.rooms do %>
                        <div>
                          <div class="text-sm font-medium text-zinc-800">
                            <%= room.name %>
                          </div>
                          <%= if room.room_category do %>
                            <div class="text-xs text-zinc-500 mt-0.5">
                              <%= atom_to_readable(room.room_category.name) %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <.badge type="green" class="whitespace-nowrap flex-shrink-0">
                      Full Buyout
                    </.badge>
                  <% end %>
                </:col>
                <:col :let={{_, booking}} label="Status" field={:status}>
                  <%= case booking.status do %>
                    <% :draft -> %>
                      <.badge type="dark" class="whitespace-nowrap flex-shrink-0">
                        Draft
                      </.badge>
                    <% :hold -> %>
                      <.badge type="yellow" class="whitespace-nowrap flex-shrink-0">
                        Hold
                      </.badge>
                    <% :complete -> %>
                      <.badge type="green" class="whitespace-nowrap flex-shrink-0">
                        Complete
                      </.badge>
                    <% :refunded -> %>
                      <.badge type="sky" class="whitespace-nowrap flex-shrink-0">
                        Refunded
                      </.badge>
                    <% :canceled -> %>
                      <.badge type="red" class="whitespace-nowrap flex-shrink-0">
                        Canceled
                      </.badge>
                    <% _ -> %>
                      <.badge type="dark" class="whitespace-nowrap flex-shrink-0">
                        —
                      </.badge>
                  <% end %>
                </:col>
                <:col :let={{_, booking}} label="Checked In">
                  <%= if Ecto.assoc_loaded?(booking.check_ins) && length(booking.check_ins) > 0 do %>
                    <div class="flex items-center gap-1.5">
                      <.icon
                        name="hero-check-circle"
                        class="w-5 h-5 text-green-600"
                      />
                      <span class="text-sm text-green-700 font-medium">Yes</span>
                    </div>
                  <% else %>
                    <span class="text-sm text-zinc-400">—</span>
                  <% end %>
                </:col>
                <:col :let={{_, booking}} label="Booked" field={:inserted_at}>
                  <span class="text-sm text-zinc-600">
                    <%= if booking.inserted_at do
                      booking.inserted_at
                      |> DateTime.shift_zone!(@timezone)
                      |> Calendar.strftime("%b %d, %Y")
                    else
                      "—"
                    end %>
                  </span>
                </:col>
                <:action :let={{_, booking}} label="Actions">
                  <div class="flex gap-3 items-center">
                    <button
                      phx-click="view-booking"
                      phx-value-booking-id={booking.id}
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm whitespace-nowrap"
                    >
                      View
                    </button>
                    <button
                      phx-click={
                        query_params = %{
                          "property" => Atom.to_string(@selected_property),
                          "from_date" => Date.to_string(@calendar_start_date),
                          "to_date" => Date.to_string(@calendar_end_date)
                        }

                        query_string = URI.encode_query(query_params)

                        JS.navigate(
                          "/admin/bookings/bookings/#{booking.id}/edit?#{query_string}"
                        )
                      }
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm whitespace-nowrap"
                    >
                      Edit
                    </button>
                    <button
                      phx-click="delete-booking"
                      phx-value-id={booking.id}
                      phx-confirm="Are you sure you want to delete this booking?"
                      phx-disable-with="Deleting..."
                      class="text-red-600 font-semibold hover:underline cursor-pointer text-sm whitespace-nowrap"
                    >
                      Delete
                    </button>
                  </div>
                </:action>
              </Flop.Phoenix.table>

              <div :if={@reservation_empty} class="py-16">
                <.empty_viking_state
                  title="No reservations found"
                  suggestion="Try adjusting your search term and filters."
                />

                <div class="px-4 py-4 flex items-center align-center justify-center">
                  <button
                    class="rounded mx-auto hover:bg-zinc-100 w-36 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80"
                    phx-click="clear-reservation-filters"
                  >
                    <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" />
                    Clear filters
                  </button>
                </div>
              </div>

              <Flop.Phoenix.pagination
                meta={@reservation_meta}
                path={~p"/admin/bookings"}
                opts={[
                  wrapper_attrs: [
                    class: "flex items-center justify-center py-10 h-10 text-base"
                  ],
                  pagination_list_attrs: [
                    class: [
                      "flex gap-0 order-2 justify-center items-center"
                    ]
                  ],
                  previous_link_attrs: [
                    class:
                      "order-1 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                  ],
                  next_link_attrs: [
                    class:
                      "order-3 flex justify-center items-center px-3 py-3 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                  ],
                  page_links: {:ellipsis, 5}
                ]}
              />
            </div>
          </div>
        </div>
      </div>
      <!-- Configuration View -->
      <!-- Pending Refunds Section -->
      <div :if={@current_section == :pending_refunds} class="space-y-6 pb-16">
        <div class="bg-white rounded-lg border border-zinc-200 p-6">
          <h2 class="text-xl font-semibold text-zinc-900 mb-4">Pending Refunds</h2>
          <p class="text-sm text-zinc-600 mb-6">
            Review and process refunds for cancelled bookings that require admin approval.
          </p>

          <%= if Enum.empty?(@pending_refunds) do %>
            <div class="text-center py-12">
              <p class="text-zinc-500">No pending refunds at this time.</p>
            </div>
          <% else %>
            <div class="space-y-4">
              <%= for pending_refund <- @pending_refunds do %>
                <div class="border border-zinc-200 rounded-lg p-4 hover:bg-zinc-50 transition-colors">
                  <div class="flex items-start justify-between mb-4">
                    <div class="flex-1">
                      <div class="flex items-center gap-3 mb-2">
                        <.link
                          navigate={
                            ~p"/admin/bookings/#{pending_refund.booking.id}"
                          }
                          class="font-semibold text-zinc-900 hover:text-blue-600"
                        >
                          Booking: <%= pending_refund.booking.reference_id %>
                        </.link>
                        <span class="text-sm text-zinc-600">
                          <%= format_property_name(pending_refund.booking.property) %>
                        </span>
                      </div>
                      <div class="text-sm text-zinc-600 space-y-1">
                        <div>
                          <span class="font-medium">Check-in:</span>
                          <%= Calendar.strftime(
                            pending_refund.booking.checkin_date,
                            "%B %d, %Y"
                          ) %>
                        </div>
                        <div>
                          <span class="font-medium">Check-out:</span>
                          <%= Calendar.strftime(
                            pending_refund.booking.checkout_date,
                            "%B %d, %Y"
                          ) %>
                        </div>
                        <div>
                          <span class="font-medium">User:</span>
                          <%= if Ecto.assoc_loaded?(pending_refund.booking.user) do %>
                            <%= pending_refund.booking.user.email %>
                          <% else %>
                            N/A
                          <% end %>
                        </div>
                        <%= if pending_refund.cancellation_reason do %>
                          <div>
                            <span class="font-medium">Cancellation Reason:</span>
                            <%= pending_refund.cancellation_reason %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <div class="text-right ml-4">
                      <div class="text-lg font-semibold text-zinc-900 mb-1">
                        Policy Refund: <%= MoneyHelper.format_money!(
                          pending_refund.policy_refund_amount
                        ) %>
                      </div>
                      <%= if pending_refund.applied_rule_days_before_checkin do %>
                        <div class="text-xs text-zinc-500">
                          <%= pending_refund.applied_rule_days_before_checkin %>+ days before check-in: <%= Decimal.to_float(
                            pending_refund.applied_rule_refund_percentage
                          ) %>% refund
                        </div>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex gap-2 pt-4 border-t border-zinc-200">
                    <.button
                      phx-click="approve-refund"
                      phx-value-id={pending_refund.id}
                      class="bg-green-600 hover:bg-green-700 text-white"
                    >
                      <.icon name="hero-check" class="w-4 h-4 me-1" />
                      Approve Policy Amount
                    </.button>
                    <.button
                      phx-click="show-approve-refund-modal"
                      phx-value-id={pending_refund.id}
                      class="bg-blue-600 hover:bg-blue-700 text-white"
                    >
                      <.icon name="hero-pencil" class="w-4 h-4 me-1" />
                      Approve Custom Amount
                    </.button>
                    <.button
                      phx-click="show-reject-refund-modal"
                      phx-value-id={pending_refund.id}
                      color="red"
                    >
                      <.icon name="hero-x-circle" class="w-4 h-4 me-1" /> Reject
                    </.button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <div :if={@current_section == :config} class="space-y-8 pb-16 max-w-screen-lg">
        <!-- Door Codes Section -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-lg font-semibold text-zinc-800">Door Codes</h2>
              <p class="text-sm text-zinc-500">
                Manage door codes for <%= atom_to_readable(@selected_property) %>
              </p>
            </div>
          </div>
          <!-- Active Door Code -->
          <div class="mb-6 p-4 bg-blue-50 rounded border border-blue-200">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-semibold text-zinc-700 mb-1">
                  Current Active Code
                </p>
                <p
                  :if={@active_door_code}
                  class="text-2xl font-mono font-bold text-blue-700"
                >
                  <%= @active_door_code.code %>
                </p>
                <p :if={!@active_door_code} class="text-sm text-zinc-500 italic">
                  No active code set
                </p>
                <p :if={@active_door_code} class="text-xs text-zinc-500 mt-1">
                  Active since <%= format_datetime(
                    @active_door_code.active_from,
                    @timezone
                  ) %>
                </p>
              </div>
            </div>
          </div>
          <!-- New Door Code Form -->
          <div class="mb-6">
            <h3 class="text-md font-semibold text-zinc-800 mb-3">
              Set New Door Code
            </h3>
            <.simple_form
              for={@door_code_form}
              id="door-code-form"
              phx-submit="save-door-code"
              phx-change="validate-door-code"
            >
              <div class="flex gap-4 items-end">
                <div class="flex-1">
                  <.input
                    type="text"
                    field={@door_code_form[:code]}
                    label="Door Code"
                    placeholder="Enter 4-5 character code"
                    maxlength="5"
                    pattern="[A-Za-z0-9]{4,5}"
                    required
                    class="font-mono"
                  />
                </div>
                <input
                  type="hidden"
                  name="door_code[property]"
                  value={Atom.to_string(@selected_property)}
                />
                <div>
                  <.button type="submit" phx-disable-with="Setting...">
                    Set New Code
                  </.button>
                </div>
              </div>
            </.simple_form>
            <!-- Warning if code matches recent codes -->
            <div
              :if={@door_code_warning}
              class="mt-3 p-3 bg-yellow-50 border border-yellow-200 rounded text-sm text-yellow-800"
            >
              <div class="flex items-start">
                <.icon
                  name="hero-exclamation-triangle"
                  class="w-5 h-5 mr-2 flex-shrink-0 mt-0.5"
                />
                <div>
                  <p class="font-semibold mb-1">Warning: Code Reuse Detected</p>
                  <p><%= @door_code_warning %></p>
                </div>
              </div>
            </div>
          </div>
          <!-- Previous Door Codes List -->
          <div>
            <h3 class="text-md font-semibold text-zinc-800 mb-3">
              Previous Door Codes
            </h3>
            <div :if={@door_codes == []} class="text-sm text-zinc-500 italic py-4">
              No previous door codes
            </div>
            <div :if={@door_codes != []} class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="text-left border-b border-zinc-200">
                  <tr>
                    <th class="pb-3 pr-6 font-semibold text-zinc-700">Code</th>
                    <th class="pb-3 pr-6 font-semibold text-zinc-700">
                      Active From
                    </th>
                    <th class="pb-3 pr-6 font-semibold text-zinc-700">Active To</th>
                    <th class="pb-3 font-semibold text-zinc-700">Status</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-100">
                  <tr :for={door_code <- @door_codes} class="hover:bg-zinc-50">
                    <td class="py-3 pr-6 font-mono font-semibold text-zinc-800">
                      <%= door_code.code %>
                    </td>
                    <td class="py-3 pr-6 text-zinc-600">
                      <%= format_datetime(door_code.active_from, @timezone) %>
                    </td>
                    <td class="py-3 pr-6 text-zinc-600">
                      <%= if door_code.active_to do
                        format_datetime(door_code.active_to, @timezone)
                      else
                        "—"
                      end %>
                    </td>
                    <td class="py-3">
                      <span
                        :if={is_nil(door_code.active_to)}
                        class="text-xs font-semibold text-green-600"
                      >
                        Active
                      </span>
                      <span
                        :if={!is_nil(door_code.active_to)}
                        class="text-xs font-semibold text-zinc-400"
                      >
                        Inactive
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
        <!-- Seasons Table -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-lg font-semibold text-zinc-800">Seasons</h2>
              <p class="text-sm text-zinc-500">
                Seasons automatically recur every year based on month/day patterns
              </p>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="text-left border-b border-zinc-200">
                <tr>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Property</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Name</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Date Range</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">
                    Advance Booking
                  </th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Max Nights</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Default</th>
                  <th class="pb-3 font-semibold text-zinc-700">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-100">
                <tr :for={season <- @filtered_seasons} class="hover:bg-zinc-50">
                  <td class="py-3 pr-6">
                    <.badge type="sky">
                      <%= if season.property,
                        do: atom_to_readable(season.property),
                        else: "—" %>
                    </.badge>
                  </td>
                  <td class="py-3 pr-6 font-medium text-zinc-800">
                    <%= season.name %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600">
                    <%= if season.start_date && season.end_date do
                      format_season_dates(season.start_date, season.end_date)
                    else
                      "—"
                    end %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600">
                    <%= if season.advance_booking_days &&
                             season.advance_booking_days > 0 do
                      "#{season.advance_booking_days} days"
                    else
                      "No limit"
                    end %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600">
                    <%= if season.max_nights do
                      "#{season.max_nights} nights"
                    else
                      case season.property do
                        :tahoe -> "4 (default)"
                        :clear_lake -> "30 (default)"
                        _ -> "—"
                      end
                    end %>
                  </td>
                  <td class="py-3 pr-6">
                    <span
                      :if={season.is_default}
                      class="text-xs font-semibold text-green-600"
                    >
                      Default
                    </span>
                    <span :if={!season.is_default} class="text-zinc-400">—</span>
                  </td>
                  <td class="py-3">
                    <button
                      phx-click={
                        JS.navigate(
                          ~p"/admin/bookings/seasons/#{season.id}/edit?property=#{@selected_property}&section=config"
                        )
                      }
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Pricing Rules Table -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-lg font-semibold text-zinc-800">Pricing Rules</h2>
              <p class="text-sm text-zinc-500">
                Pricing rules use hierarchical specificity (room → category → property)
              </p>
            </div>
            <.button phx-click={
              JS.navigate(
                ~p"/admin/bookings/pricing-rules/new?property=#{@selected_property}&section=#{@current_section}"
              )
            }>
              <.icon name="hero-plus" class="w-5 h-5 -mt-1" />
              <span class="ms-1">
                New Pricing Rule
              </span>
            </.button>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="text-left border-b border-zinc-200">
                <tr>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Property</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Mode</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Price Unit</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Specificity</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Price</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">
                    Children Price
                  </th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Season</th>
                  <th class="pb-3 font-semibold text-zinc-700">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-100">
                <tr :for={rule <- @filtered_pricing_rules} class="hover:bg-zinc-50">
                  <td class="py-3 pr-6">
                    <span :if={rule.property}>
                      <.badge type="sky">
                        <%= atom_to_readable(rule.property) %>
                      </.badge>
                    </span>
                    <span :if={!rule.property} class="text-zinc-400">—</span>
                  </td>
                  <td class="py-3 pr-6">
                    <.badge type="gray">
                      <%= if rule.booking_mode do
                        atom_to_readable(rule.booking_mode)
                      else
                        "—"
                      end %>
                    </.badge>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= if rule.price_unit do
                      format_price_unit(rule.price_unit)
                    else
                      "—"
                    end %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= format_specificity(rule) %>
                  </td>
                  <td class="py-3 pr-6 font-semibold text-zinc-800">
                    <%= if rule.amount do
                      format_price(rule.amount)
                    else
                      "$0.00"
                    end %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= if rule.children_amount do
                      format_price(rule.children_amount)
                    else
                      "-"
                    end %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= if rule.season, do: rule.season.name, else: "All seasons" %>
                  </td>
                  <td class="py-3">
                    <button
                      phx-click={
                        JS.navigate(
                          ~p"/admin/bookings/pricing-rules/#{rule.id}/edit?property=#{@selected_property}&section=#{@current_section}"
                        )
                      }
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Refund Policies Table -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-lg font-semibold text-zinc-800">Refund Policies</h2>
              <p class="text-sm text-zinc-500">
                Configure cancellation and refund policies for bookings
              </p>
            </div>
            <.button phx-click={
              JS.navigate(
                ~p"/admin/bookings/refund-policies/new?property=#{@selected_property}&section=#{@current_section}"
              )
            }>
              <.icon name="hero-plus" class="w-5 h-5 -mt-1" />
              <span class="ms-1">
                New Refund Policy
              </span>
            </.button>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="text-left border-b border-zinc-200">
                <tr>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Property</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">
                    Booking Mode
                  </th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Name</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Rules</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Status</th>
                  <th class="pb-3 font-semibold text-zinc-700">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-100">
                <tr
                  :for={policy <- @filtered_refund_policies}
                  class="hover:bg-zinc-50"
                >
                  <td class="py-3 pr-6">
                    <.badge type="sky">
                      <%= atom_to_readable(policy.property) %>
                    </.badge>
                  </td>
                  <td class="py-3 pr-6">
                    <.badge type="gray">
                      <%= atom_to_readable(policy.booking_mode) %>
                    </.badge>
                  </td>
                  <td class="py-3 pr-6 font-medium text-zinc-800">
                    <%= policy.name %>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= length(policy.rules || []) %> rule(s)
                  </td>
                  <td class="py-3 pr-6">
                    <span
                      :if={policy.is_active}
                      class="text-xs font-semibold text-green-600"
                    >
                      Active
                    </span>
                    <span
                      :if={!policy.is_active}
                      class="text-xs font-semibold text-zinc-400"
                    >
                      Inactive
                    </span>
                  </td>
                  <td class="py-3">
                    <div class="flex gap-2">
                      <button
                        phx-click={
                          JS.navigate(
                            ~p"/admin/bookings/refund-policies/#{policy.id}/edit?property=#{@selected_property}&section=#{@current_section}"
                          )
                        }
                        class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                      >
                        Edit
                      </button>
                      <button
                        phx-click={
                          JS.navigate(
                            ~p"/admin/bookings/refund-policies/#{policy.id}/rules?property=#{@selected_property}&section=#{@current_section}"
                          )
                        }
                        class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                      >
                        Rules
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
            <div
              :if={@filtered_refund_policies == []}
              class="text-sm text-zinc-500 italic py-4 text-center"
            >
              No refund policies configured
            </div>
          </div>
        </div>
        <!-- Rooms Table -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <div>
              <h2 class="text-lg font-semibold text-zinc-800">Rooms</h2>
              <p class="text-sm text-zinc-500">
                Configure rooms for <%= atom_to_readable(@selected_property) %>
              </p>
            </div>
            <.button phx-click={
              JS.navigate(
                ~p"/admin/bookings/rooms/new?property=#{@selected_property}&section=#{@current_section}"
              )
            }>
              <.icon name="hero-plus" class="w-5 h-5 -mt-1" />
              <span class="ms-1">
                New Room
              </span>
            </.button>
          </div>

          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="text-left border-b border-zinc-200">
                <tr>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Image</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Name</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Category</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Capacity</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Beds</th>
                  <th class="pb-3 pr-6 font-semibold text-zinc-700">Status</th>
                  <th class="pb-3 font-semibold text-zinc-700">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-100">
                <tr :for={room <- @filtered_rooms} class="hover:bg-zinc-50">
                  <td class="py-3 pr-6">
                    <div
                      :if={room.image}
                      class="w-16 h-16 rounded overflow-hidden border border-zinc-200"
                    >
                      <img
                        src={
                          room.image.thumbnail_path ||
                            room.image.optimized_image_path ||
                            room.image.raw_image_path
                        }
                        alt={room.name}
                        class="w-full h-full object-cover"
                      />
                    </div>
                    <div
                      :if={!room.image}
                      class="w-16 h-16 rounded bg-zinc-100 border border-zinc-200 flex items-center justify-center"
                    >
                      <span class="text-xs text-zinc-400">No image</span>
                    </div>
                  </td>
                  <td class="py-3 pr-6">
                    <div class="font-medium text-zinc-800">
                      <%= room.name %>
                    </div>
                    <div
                      :if={room.description}
                      class="text-xs text-zinc-500 mt-0.5 line-clamp-2"
                    >
                      <%= room.description %>
                    </div>
                  </td>
                  <td class="py-3 pr-6">
                    <span :if={room.room_category} class="text-zinc-600">
                      <%= atom_to_readable(room.room_category.name) %>
                    </span>
                    <span :if={!room.room_category} class="text-zinc-400">—</span>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600">
                    Max: <%= room.capacity_max %>
                    <span
                      :if={
                        room.min_billable_occupancy &&
                          room.min_billable_occupancy > 1
                      }
                      class="text-xs text-zinc-500"
                    >
                      <br />Min billable: <%= room.min_billable_occupancy %>
                    </span>
                  </td>
                  <td class="py-3 pr-6 text-zinc-600 text-xs">
                    <%= if room.single_beds > 0 || room.queen_beds > 0 || room.king_beds > 0 do %>
                      <%= if room.single_beds > 0,
                        do:
                          "#{room.single_beds} Single#{if room.single_beds > 1, do: "s", else: ""}" %>
                      <%= if room.queen_beds > 0 do %>
                        <%= if room.single_beds > 0, do: ", " %><%= room.queen_beds %> Queen<%= if room.queen_beds >
                                                                                                     1,
                                                                                                   do:
                                                                                                     "s",
                                                                                                   else:
                                                                                                     "" %>
                      <% end %>
                      <%= if room.king_beds > 0 do %>
                        <%= if room.single_beds > 0 || room.queen_beds > 0, do: ", " %><%= room.king_beds %> King<%= if room.king_beds >
                                                                                                                          1,
                                                                                                                        do:
                                                                                                                          "s",
                                                                                                                        else:
                                                                                                                          "" %>
                      <% end %>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="py-3 pr-6">
                    <span
                      :if={room.is_active}
                      class="text-xs font-semibold text-green-600"
                    >
                      Active
                    </span>
                    <span
                      :if={!room.is_active}
                      class="text-xs font-semibold text-zinc-400"
                    >
                      Inactive
                    </span>
                  </td>
                  <td class="py-3">
                    <button
                      phx-click={
                        JS.navigate(
                          ~p"/admin/bookings/rooms/#{room.id}/edit?property=#{@selected_property}&section=#{@current_section}"
                        )
                      }
                      class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
            <div
              :if={@filtered_rooms == []}
              class="text-sm text-zinc-500 italic py-4 text-center"
            >
              No rooms configured
            </div>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # Parse query parameters (may be malformed if URL is double-encoded)
    parsed_params = parse_mount_params(params)

    # Get timezone from connect params
    connect_params =
      case get_connect_params(socket) do
        nil -> %{}
        v -> v
      end

    timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

    # Read property from params if available, otherwise default to :tahoe
    selected_property =
      if parsed_params["property"] do
        try do
          String.to_existing_atom(parsed_params["property"])
        rescue
          _ -> :tahoe
        end
      else
        :tahoe
      end

    current_section =
      if parsed_params["section"] do
        try do
          String.to_existing_atom(parsed_params["section"])
        rescue
          _ -> :calendar
        end
      else
        :calendar
      end

    today = Date.utc_today()

    # Read calendar dates from params if available, otherwise default to current month
    {calendar_start, calendar_end} =
      if parsed_params["from_date"] && parsed_params["to_date"] do
        try do
          start = Date.from_iso8601!(parsed_params["from_date"])
          ending = Date.from_iso8601!(parsed_params["to_date"])
          {start, ending}
        rescue
          _ ->
            {Date.beginning_of_month(today), Date.end_of_month(today)}
        end
      else
        {Date.beginning_of_month(today), Date.end_of_month(today)}
      end

    form_data = %{
      "from_date" => Date.to_string(calendar_start),
      "to_date" => Date.to_string(calendar_end)
    }

    changeset =
      {%{}, %{from_date: :date, to_date: :date}}
      |> Ecto.Changeset.cast(form_data, [:from_date, :to_date])
      |> to_form(as: "calendar_range")

    # Create initial door code form
    door_code_form =
      %Ysc.Bookings.DoorCode{}
      |> Ysc.Bookings.DoorCode.changeset(%{})
      |> to_form(as: "door_code")

    # Generate calendar dates for initial render (no DB needed)
    calendar_dates = generate_calendar_dates(calendar_start, calendar_end)

    # Initialize socket with placeholder values for fast initial render
    socket =
      socket
      |> assign(:page_title, "Bookings")
      |> assign(:active_page, :bookings)
      |> assign(:timezone, timezone)
      |> assign(:selected_property, selected_property)
      |> assign(:current_section, current_section)
      |> assign(:loading_bookings_data, true)
      # Placeholder values - will be populated when connected
      |> assign(:seasons, [])
      |> assign(:pricing_rules, [])
      |> assign(:room_categories, [])
      |> assign(:rooms, [])
      |> assign(:refund_policies, [])
      |> assign(:today, today)
      |> assign(:calendar_start_date, calendar_start)
      |> assign(:calendar_end_date, calendar_end)
      |> assign(:calendar_dates, calendar_dates)
      |> assign(:filtered_rooms, [])
      |> assign(:filtered_blackouts, [])
      |> assign(:room_bookings, [])
      |> assign(:buyout_bookings, [])
      |> assign(:booking_payments, [])
      |> assign(:booking_refunds, [])
      |> assign(:booking_room_id, nil)
      |> assign(:primary_payment, nil)
      |> assign(:show_refund_modal, false)
      |> assign(:refund_form, nil)
      |> assign(:calendar_range_form, changeset)
      |> assign(:user_search, "")
      |> assign(:user_search_results, [])
      |> assign(:selected_user, nil)
      |> assign(:date_selection_type, nil)
      |> assign(:date_selection_start, nil)
      |> assign(:date_selection_room_id, nil)
      |> assign(:date_selection_hover_end, nil)
      |> assign(:reservation_params, %{})
      |> assign(:reservation_meta, nil)
      |> assign(:reservation_empty, false)
      |> assign(:reservation_filter_start_date, nil)
      |> assign(:reservation_filter_end_date, nil)
      |> assign(:door_codes, [])
      |> assign(:active_door_code, nil)
      |> assign(:door_code_form, door_code_form)
      |> assign(:pending_refunds, [])
      |> assign(:pending_refunds_count, 0)
      |> assign(:tahoe_pending_refunds_count, 0)
      |> assign(:clear_lake_pending_refunds_count, 0)
      |> assign(:selected_pending_refund, nil)
      |> assign(:approve_refund_form, nil)
      |> assign(:reject_refund_form, nil)
      |> assign(:door_code_warning, nil)
      |> assign(:season, nil)
      |> assign(:season_form, nil)
      |> assign(:refund_policy, nil)
      |> assign(:refund_policy_form, nil)
      |> assign(:refund_policy_rules, [])
      |> assign(:refund_policy_rule_form, nil)
      |> assign(:room, nil)
      |> assign(:room_form, nil)
      |> assign(:selected_room_image, nil)
      |> assign(:show_image_gallery, false)
      |> assign(:image_gallery, [])
      |> assign(:image_gallery_page, 1)
      |> assign(:image_gallery_end?, false)
      |> assign(:daily_availability, %{})
      |> assign(
        :reservations_path,
        ~p"/admin/bookings?property=#{selected_property}&section=reservations"
      )
      # Initialize filtered data with empty values
      |> assign(:filtered_seasons, [])
      |> assign(:filtered_pricing_rules, [])
      |> assign(:filtered_refund_policies, [])

    # Schedule data loading only when connected (stateful mount)
    if connected?(socket) do
      send(self(), :load_bookings_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_bookings_data, socket) do
    selected_property = socket.assigns.selected_property

    # Load critical data first (needed for calendar view)
    # Parallelize independent queries for better performance
    tasks = [
      Task.async(fn -> Bookings.list_seasons() end),
      Task.async(fn -> Bookings.list_pricing_rules() end),
      Task.async(fn -> Bookings.list_refund_policies() end),
      Task.async(fn -> Bookings.list_room_categories() end),
      Task.async(fn -> Bookings.list_rooms() end),
      Task.async(fn -> Bookings.list_door_codes(selected_property) end),
      Task.async(fn -> Bookings.get_active_door_code(selected_property) end)
    ]

    # Await all tasks concurrently
    results = Task.await_many(tasks, :infinity)

    [
      seasons,
      pricing_rules,
      refund_policies,
      room_categories,
      rooms,
      door_codes,
      active_door_code
    ] =
      results

    {:noreply,
     socket
     |> assign(:loading_bookings_data, false)
     |> assign(:seasons, seasons)
     |> assign(:pricing_rules, pricing_rules)
     |> assign(:room_categories, room_categories)
     |> assign(:rooms, rooms)
     |> assign(:refund_policies, refund_policies)
     |> assign(:door_codes, door_codes)
     |> assign(:active_door_code, active_door_code)
     |> assign_filtered_data(
       selected_property,
       seasons,
       pricing_rules,
       refund_policies
     )
     |> update_calendar_view(selected_property)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse query string manually if params are malformed (e.g., double-encoded)
    params = parse_query_params(params, uri)

    # Ensure live_action is explicitly set based on the route
    # This prevents stale live_action values from blocking modal opens
    socket = assign(socket, :live_action, socket.assigns.live_action || :index)

    # Track if dates or property changed to avoid unnecessary calendar updates
    old_start_date = socket.assigns[:calendar_start_date]
    old_end_date = socket.assigns[:calendar_end_date]
    old_property = socket.assigns[:selected_property]

    # Update calendar date range first if provided in params, to preserve it when updating property
    {socket, dates_changed} =
      cond do
        params["from_date"] && params["to_date"] ->
          try do
            calendar_start = Date.from_iso8601!(params["from_date"])
            calendar_end = Date.from_iso8601!(params["to_date"])

            dates_changed =
              old_start_date != calendar_start || old_end_date != calendar_end

            form_data = %{
              "from_date" => Date.to_string(calendar_start),
              "to_date" => Date.to_string(calendar_end)
            }

            changeset =
              {%{}, %{from_date: :date, to_date: :date}}
              |> Ecto.Changeset.cast(form_data, [:from_date, :to_date])
              |> to_form(as: "calendar_range")

            socket =
              socket
              |> assign(:calendar_start_date, calendar_start)
              |> assign(:calendar_end_date, calendar_end)
              |> assign(:calendar_range_form, changeset)

            {socket, dates_changed}
          rescue
            _error ->
              # Fallback to existing dates or default
              if socket.assigns[:calendar_start_date] &&
                   socket.assigns[:calendar_end_date] do
                {socket, false}
              else
                {start_date, end_date} = default_date_range()

                socket =
                  socket
                  |> assign(:calendar_start_date, start_date)
                  |> assign(:calendar_end_date, end_date)

                {socket, true}
              end
          end

        socket.assigns[:calendar_start_date] &&
            socket.assigns[:calendar_end_date] ->
          {socket, false}

        true ->
          {start_date, end_date} = default_date_range()

          socket =
            socket
            |> assign(:calendar_start_date, start_date)
            |> assign(:calendar_end_date, end_date)

          {socket, true}
      end

    # Update section if provided in params
    socket =
      if params["section"] do
        section_atom =
          try do
            String.to_existing_atom(params["section"])
          rescue
            _ -> socket.assigns[:current_section] || :calendar
          end

        assign(socket, :current_section, section_atom)
      else
        socket
      end

    # Update selected_property if provided in params
    {socket, property_changed} =
      if params["property"] do
        property_atom = String.to_existing_atom(params["property"])
        property_changed = old_property != property_atom

        socket =
          socket
          |> assign(:selected_property, property_atom)
          |> assign_filtered_data(
            property_atom,
            socket.assigns.seasons,
            socket.assigns.pricing_rules,
            socket.assigns.refund_policies
          )

        {socket, property_changed}
      else
        {socket, false}
      end

    # Update calendar view only if dates or property changed (avoid duplicate queries on initial mount)
    socket =
      if (dates_changed || property_changed) &&
           socket.assigns.live_action == :index do
        update_calendar_view(socket, socket.assigns.selected_property)
      else
        socket
      end

    # Load reservations for the table only if on reservations section
    socket =
      if socket.assigns[:current_section] == :reservations do
        load_reservations(socket, params)
      else
        socket
      end

    # Load pending refunds count and list if on pending_refunds section
    # Parallelize pending refunds queries for better performance
    selected_property = socket.assigns.selected_property

    # Start both queries in parallel
    pending_refunds_count_task =
      if socket.assigns[:current_section] == :pending_refunds do
        nil
      else
        # Still load count for the badge (filtered by selected property at DB level)
        Task.async(fn ->
          from(pr in Ysc.Bookings.PendingRefund,
            join: b in assoc(pr, :booking),
            where: pr.status == :pending,
            where: b.property == ^selected_property,
            select: count(pr.id)
          )
          |> Repo.one() || 0
        end)
      end

    # Load pending refunds counts per property for tab badges (parallelize with property count)
    property_counts_task =
      Task.async(fn -> load_property_pending_refunds_counts_data() end)

    # Load full pending refunds list if on that section
    socket =
      if socket.assigns[:current_section] == :pending_refunds do
        load_pending_refunds(socket)
      else
        socket
      end

    # Await both tasks in parallel
    property_counts = Task.await(property_counts_task, :infinity)

    socket =
      socket
      |> assign(
        :tahoe_pending_refunds_count,
        Map.get(property_counts, :tahoe, 0)
      )
      |> assign(
        :clear_lake_pending_refunds_count,
        Map.get(property_counts, :clear_lake, 0)
      )

    # Await property-specific count if needed
    socket =
      if pending_refunds_count_task do
        pending_refunds_count =
          Task.await(pending_refunds_count_task, :infinity)

        assign(socket, :pending_refunds_count, pending_refunds_count)
      else
        socket
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Parse query parameters, handling malformed/double-encoded URLs
  defp parse_query_params(params, uri) do
    # Priority 1: Use uri.query if available (most reliable)
    # Priority 2: Check for malformed key in params
    # Priority 3: Use params as-is

    cond do
      is_struct(uri, URI) && uri.query && uri.query != "" ->
        # uri.query is the most reliable source - it's the raw query string from the URL
        parsed = parse_query_string(uri.query)
        # Merge with existing params (path params like "id" take precedence)
        # Path params like "id" should not be overwritten by query params
        Map.merge(parsed, params)

      find_malformed_query_key(params) ->
        malformed_key = find_malformed_query_key(params)
        # Params are malformed - the entire query string is the key
        # Parse it directly from the key
        parsed = parse_query_string(malformed_key)
        # Merge with existing params (path params like "id" take precedence)
        # Remove the malformed key from params before merging
        clean_params = Map.delete(params, malformed_key)
        Map.merge(parsed, clean_params)

      true ->
        # Params are already correctly parsed
        params
    end
  end

  # Find a key that looks like a malformed query string (contains & and =)
  defp find_malformed_query_key(params) when is_map(params) do
    Enum.find_value(params, fn {key, value} ->
      # Check if key looks like a query string (contains & and =)
      # Also check if value is empty string (which indicates malformed param)
      cond do
        is_binary(key) && String.contains?(key, "&") &&
            String.contains?(key, "=") ->
          # This looks like a malformed query string
          key

        is_binary(key) && String.contains?(key, "&") && value == "" ->
          # Key contains & and value is empty - likely malformed
          key

        true ->
          nil
      end
    end)
  end

  defp find_malformed_query_key(_), do: nil

  # Parse query string manually
  defp parse_query_string(query_string) when is_binary(query_string) do
    query_string
    |> String.split("&")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          key = URI.decode(key)
          value = URI.decode(value)
          Map.put(acc, key, value)

        [key] ->
          key = URI.decode(key)
          Map.put(acc, key, "")

        _ ->
          acc
      end
    end)
  end

  defp parse_query_string(_), do: %{}

  # Parse params in mount - handle malformed query strings
  defp parse_mount_params(params) when is_map(params) do
    # Check if params are malformed (single key with entire query string as value)
    case Map.keys(params) do
      [key] when is_binary(key) ->
        # Check if this looks like a malformed query string
        if String.contains?(key, "&") do
          # Params are malformed - the entire query string is the key
          parse_query_string(key)
        else
          # Single key but not malformed, use as-is
          params
        end

      _ ->
        # Params are already correctly parsed
        params
    end
  end

  defp parse_mount_params(_), do: %{}

  defp apply_action(socket, :new_pricing_rule, _params) do
    form =
      %Ysc.Bookings.PricingRule{}
      |> Ysc.Bookings.PricingRule.changeset(%{
        property: socket.assigns.selected_property,
        booking_mode: :room,
        price_unit: :per_person_per_night
      })
      |> to_form(as: "pricing_rule")

    socket
    |> assign(:page_title, "New Pricing Rule")
    |> assign(:pricing_rule, nil)
    |> assign(:form, form)
  end

  defp apply_action(socket, :edit_pricing_rule, %{"id" => id}) do
    pricing_rule = Bookings.get_pricing_rule!(id)

    form =
      pricing_rule
      |> Ysc.Bookings.PricingRule.changeset(%{})
      |> to_form(as: "pricing_rule")

    socket
    |> assign(:page_title, "Edit Pricing Rule")
    |> assign(:pricing_rule, pricing_rule)
    |> assign(:form, form)
  end

  defp apply_action(socket, :new_blackout, params) do
    # Get initial dates from params if provided (from two-click selection)
    {start_date, end_date} =
      if params["start_date"] && params["end_date"] do
        try do
          start = Date.from_iso8601!(params["start_date"])
          ending = Date.from_iso8601!(params["end_date"])
          {start, ending}
        rescue
          _ ->
            initial = socket.assigns.calendar_start_date
            {initial, initial}
        end
      else
        # Fallback to single date or current date
        initial_date =
          if params["date"] do
            try do
              Date.from_iso8601!(params["date"])
            rescue
              _ -> socket.assigns.calendar_start_date
            end
          else
            socket.assigns.calendar_start_date
          end

        {initial_date, initial_date}
      end

    form =
      %Ysc.Bookings.Blackout{}
      |> Ysc.Bookings.Blackout.changeset(%{
        property: socket.assigns.selected_property,
        start_date: start_date,
        end_date: end_date
      })
      |> to_form(as: "blackout")

    socket
    |> assign(:page_title, "New Blackout")
    |> assign(:blackout, nil)
    |> assign(:blackout_form, form)
  end

  defp apply_action(socket, :edit_blackout, %{"id" => id}) do
    blackout = Bookings.get_blackout!(id)

    form =
      blackout
      |> Ysc.Bookings.Blackout.changeset(%{})
      |> to_form(as: "blackout")

    # Ensure selected_property matches the blackout's property (if not already set from params)
    socket =
      if socket.assigns.selected_property != blackout.property do
        assign(socket, :selected_property, blackout.property)
      else
        socket
      end

    # Calendar dates should already be set from handle_params, but ensure they're preserved
    socket =
      if socket.assigns[:calendar_start_date] &&
           socket.assigns[:calendar_end_date] do
        socket
      else
        # Fallback to current month if dates aren't set
        today = Date.utc_today()
        start_date = Date.beginning_of_month(today)
        end_date = Date.end_of_month(today)

        socket
        |> assign(:calendar_start_date, start_date)
        |> assign(:calendar_end_date, end_date)
      end

    socket
    |> assign(:page_title, "Edit Blackout")
    |> assign(:blackout, blackout)
    |> assign(:blackout_form, form)
  end

  defp apply_action(socket, :view_booking, %{"id" => id}) do
    booking = Bookings.get_booking!(id)

    booking =
      Ysc.Repo.preload(booking, [
        :user,
        :booking_guests,
        rooms: :room_category,
        check_ins: :check_in_vehicles
      ])

    # Ensure selected_property matches the booking's property
    socket =
      if socket.assigns.selected_property != booking.property do
        assign(socket, :selected_property, booking.property)
      else
        socket
      end

    # Calendar dates should already be set from handle_params, but ensure they're preserved
    socket =
      if socket.assigns[:calendar_start_date] &&
           socket.assigns[:calendar_end_date] do
        socket
      else
        # Fallback to current month if dates aren't set
        today = Date.utc_today()
        start_date = Date.beginning_of_month(today)
        end_date = Date.end_of_month(today)

        socket
        |> assign(:calendar_start_date, start_date)
        |> assign(:calendar_end_date, end_date)
      end

    # Get payments and refunds related to this booking
    payments = get_booking_payments(booking.id)
    refunds = get_booking_refunds(booking.id)

    # Get the primary payment for refund processing
    primary_payment = List.first(payments)

    # Initialize refund form if there's a payment
    refund_form =
      if primary_payment do
        {%{},
         %{amount: :string, reason: :string, release_availability: :boolean}}
        |> Ecto.Changeset.cast(%{}, [:amount, :reason, :release_availability])
        |> to_form(as: "refund")
      else
        nil
      end

    socket
    |> assign(:page_title, "Booking Details")
    |> assign(:booking, booking)
    |> assign(:booking_payments, payments)
    |> assign(:booking_refunds, refunds)
    |> assign(:primary_payment, primary_payment)
    |> assign(:show_refund_modal, false)
    |> assign(:refund_form, refund_form)
  end

  defp apply_action(socket, :new_booking, params) do
    # Determine booking type from params
    booking_type =
      cond do
        params["type"] == "buyout" -> :buyout
        params["type"] == "room" -> :room
        params["room_id"] -> :room
        true -> :buyout
      end

    # Get initial dates from params (from two-click selection)
    {checkin_date, checkout_date} =
      if params["start_date"] && params["end_date"] do
        try do
          start = Date.from_iso8601!(params["start_date"])
          ending = Date.from_iso8601!(params["end_date"])
          {start, ending}
        rescue
          _ ->
            initial = socket.assigns.calendar_start_date
            {initial, initial}
        end
      else
        # Fallback to single date or current date
        initial_checkin =
          if params["date"] do
            try do
              Date.from_iso8601!(params["date"])
            rescue
              _ -> socket.assigns.calendar_start_date
            end
          else
            socket.assigns.calendar_start_date
          end

        {initial_checkin, initial_checkin}
      end

    # Get room_id if provided
    room_id = if params["room_id"], do: params["room_id"], else: nil

    form_data = %{
      "property" => Atom.to_string(socket.assigns.selected_property),
      "checkin_date" => Date.to_string(checkin_date),
      "checkout_date" => Date.to_string(checkout_date),
      "guests_count" => "1",
      "children_count" => "0",
      "booking_mode" => Atom.to_string(booking_type)
    }

    form =
      %Ysc.Bookings.Booking{}
      |> Ysc.Bookings.Booking.changeset(form_data, skip_validation: true)
      |> to_form(as: "booking")

    socket
    |> assign(:page_title, "New Booking")
    |> assign(:booking_type, booking_type)
    |> assign(:booking_form, form)
    |> assign(:booking, nil)
    |> assign(:booking_room_id, room_id)
    |> assign(:booking_payments, [])
    |> assign(:booking_refunds, [])
    |> assign(:user_search, "")
    |> assign(:user_search_results, [])
    |> assign(:selected_user, nil)
  end

  defp apply_action(socket, :edit_booking, %{"id" => id}) do
    booking = Bookings.get_booking!(id)
    booking = Ysc.Repo.preload(booking, [:user, rooms: :room_category])

    # Determine booking type from existing booking
    has_rooms = Ecto.assoc_loaded?(booking.rooms) && booking.rooms != []
    booking_type = if has_rooms, do: :room, else: :buyout

    # Get room_id if it's a room booking
    room_id = if has_rooms, do: List.first(booking.rooms).id, else: nil

    form_data = %{
      "property" => Atom.to_string(booking.property),
      "checkin_date" => Date.to_string(booking.checkin_date),
      "checkout_date" => Date.to_string(booking.checkout_date),
      "guests_count" => to_string(booking.guests_count),
      "children_count" => to_string(booking.children_count || 0),
      "booking_mode" => Atom.to_string(booking.booking_mode || booking_type),
      "user_id" => booking.user_id,
      "status" => Atom.to_string(booking.status || :draft)
    }

    form =
      booking
      |> Ysc.Bookings.Booking.changeset(form_data, skip_validation: true)
      |> to_form(as: "booking")

    # Ensure selected_property matches the booking's property
    socket =
      if socket.assigns.selected_property != booking.property do
        assign(socket, :selected_property, booking.property)
      else
        socket
      end

    socket
    |> assign(:page_title, "Edit Booking")
    |> assign(:booking_type, booking_type)
    |> assign(:booking_form, form)
    |> assign(:booking, booking)
    |> assign(:booking_room_id, room_id)
    |> assign(:booking_payments, [])
    |> assign(:booking_refunds, [])
    |> assign(:user_search, "")
    |> assign(:user_search_results, [])
    |> assign(:selected_user, booking.user)
  end

  defp apply_action(socket, :new_refund_policy, _params) do
    form =
      %Ysc.Bookings.RefundPolicy{}
      |> Ysc.Bookings.RefundPolicy.changeset(%{
        property: socket.assigns.selected_property,
        booking_mode: :room,
        is_active: true
      })
      |> to_form(as: "refund_policy")

    socket
    |> assign(:page_title, "New Refund Policy")
    |> assign(:refund_policy, nil)
    |> assign(:refund_policy_form, form)
  end

  defp apply_action(socket, :edit_refund_policy, %{"id" => id}) do
    refund_policy = Bookings.get_refund_policy!(id)

    form =
      refund_policy
      |> Ysc.Bookings.RefundPolicy.changeset(%{})
      |> to_form(as: "refund_policy")

    socket
    |> assign(:page_title, "Edit Refund Policy")
    |> assign(:refund_policy, refund_policy)
    |> assign(:refund_policy_form, form)
  end

  defp apply_action(socket, :manage_refund_policy_rules, %{"id" => id}) do
    refund_policy = Bookings.get_refund_policy!(id)
    refund_policy_rules = Bookings.list_refund_policy_rules(id)

    rule_form =
      %Ysc.Bookings.RefundPolicyRule{}
      |> Ysc.Bookings.RefundPolicyRule.changeset(%{
        refund_policy_id: refund_policy.id,
        priority: 0
      })
      |> to_form(as: "refund_policy_rule")

    socket
    |> assign(:page_title, "Manage Refund Policy Rules")
    |> assign(:refund_policy, refund_policy)
    |> assign(:refund_policy_rules, refund_policy_rules)
    |> assign(:refund_policy_rule_form, rule_form)
  end

  defp apply_action(socket, :edit_season, %{"id" => id}) do
    season = Bookings.get_season!(id)

    form =
      season
      |> Ysc.Bookings.Season.changeset(%{})
      |> to_form(as: "season")

    # Ensure selected_property matches the season's property
    socket =
      if socket.assigns.selected_property != season.property do
        assign(socket, :selected_property, season.property)
      else
        socket
      end

    socket
    |> assign(:page_title, "Edit Season")
    |> assign(:season, season)
    |> assign(:season_form, form)
  end

  defp apply_action(socket, :new_room, _params) do
    alias Ysc.Media

    # Load initial image gallery page
    images = Media.list_images(0, 20)

    form =
      %Ysc.Bookings.Room{}
      |> Ysc.Bookings.Room.changeset(%{
        property: socket.assigns.selected_property,
        capacity_max: 2,
        min_billable_occupancy: 1,
        is_active: true
      })
      |> to_form(as: "room")

    socket
    |> assign(:page_title, "New Room")
    |> assign(:room, nil)
    |> assign(:room_form, form)
    |> assign(:selected_room_image, nil)
    |> assign(:show_image_gallery, false)
    |> assign(:image_gallery, images)
    |> assign(:image_gallery_page, 1)
    |> assign(:image_gallery_end?, length(images) < 20)
  end

  defp apply_action(socket, :edit_room, %{"id" => id}) do
    alias Ysc.Media

    room = Bookings.get_room!(id)

    # Load initial image gallery page
    images = Media.list_images(0, 20)

    # Use preloaded image from room (already loaded by get_room!)
    selected_image = room.image

    form =
      room
      |> Ysc.Bookings.Room.changeset(%{})
      |> to_form(as: "room")

    # Ensure selected_property matches the room's property
    socket =
      if socket.assigns.selected_property != room.property do
        assign(socket, :selected_property, room.property)
      else
        socket
      end

    socket
    |> assign(:page_title, "Edit Room")
    |> assign(:room, room)
    |> assign(:room_form, form)
    |> assign(:selected_room_image, selected_image)
    |> assign(:show_image_gallery, false)
    |> assign(:image_gallery, images)
    |> assign(:image_gallery_page, 1)
    |> assign(:image_gallery_end?, length(images) < 20)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Bookings")
    |> assign(:pricing_rule, nil)
    |> assign(:form, nil)
    |> assign(:blackout, nil)
    |> assign(:blackout_form, nil)
    |> assign(:booking, nil)
    |> assign(:booking_form, nil)
    |> assign(:booking_type, nil)
    |> assign(:booking_payments, [])
    |> assign(:booking_refunds, [])
    |> assign(:primary_payment, nil)
    |> assign(:show_refund_modal, false)
    |> assign(:refund_form, nil)
    |> assign(:season, nil)
    |> assign(:season_form, nil)
    |> assign(:refund_policy, nil)
    |> assign(:refund_policy_form, nil)
    |> assign(:refund_policy_rules, [])
    |> assign(:refund_policy_rule_form, nil)
    |> assign(:selected_pending_refund, nil)
    |> assign(:approve_refund_form, nil)
    |> assign(:reject_refund_form, nil)
    |> assign(:room, nil)
    |> assign(:room_form, nil)
    |> assign(:selected_room_image, nil)
    |> assign(:show_image_gallery, false)
    |> assign(:image_gallery, [])
    |> assign(:image_gallery_page, 1)
    |> assign(:image_gallery_end?, false)
  end

  @impl true
  def handle_event("select-property", %{"property" => property}, socket) do
    property_atom = String.to_existing_atom(property)

    # Reload door codes for the new property
    door_codes = Bookings.list_door_codes(property_atom)
    active_door_code = Bookings.get_active_door_code(property_atom)

    {:noreply,
     socket
     |> assign(:selected_property, property_atom)
     |> assign(:door_codes, door_codes)
     |> assign(:active_door_code, active_door_code)
     |> assign(:door_code_warning, nil)
     |> assign_filtered_data(
       property_atom,
       socket.assigns.seasons,
       socket.assigns.pricing_rules,
       socket.assigns.refund_policies
     )
     |> update_calendar_view(property_atom)}
  end

  def handle_event(
        "validate-blackout",
        %{"blackout" => blackout_params},
        socket
      ) do
    changeset =
      (socket.assigns.blackout || %Ysc.Bookings.Blackout{})
      |> Ysc.Bookings.Blackout.changeset(blackout_params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, :blackout_form, to_form(changeset, as: "blackout"))}
  end

  def handle_event("save-blackout", %{"blackout" => blackout_params}, socket) do
    # Convert property string to atom
    blackout_params =
      if property_str = blackout_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(blackout_params, "property", property_atom)
      else
        blackout_params
      end

    result =
      if socket.assigns.blackout do
        Bookings.update_blackout(socket.assigns.blackout, blackout_params)
      else
        Bookings.create_blackout(blackout_params)
      end

    case result do
      {:ok, _blackout} ->
        # Preserve date range if available
        query_params = %{property: socket.assigns.selected_property}

        query_params =
          if socket.assigns[:calendar_start_date] &&
               socket.assigns[:calendar_end_date] do
            Map.merge(query_params, %{
              from_date: Date.to_string(socket.assigns.calendar_start_date),
              to_date: Date.to_string(socket.assigns.calendar_end_date)
            })
          else
            query_params
          end

        {:noreply,
         socket
         |> put_flash(:info, "Blackout saved successfully")
         |> push_navigate(
           to: ~p"/admin/bookings?#{URI.encode_query(query_params)}"
         )
         |> update_calendar_view(socket.assigns.selected_property)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :blackout_form, to_form(changeset, as: "blackout"))}
    end
  end

  def handle_event("delete-blackout", %{"id" => id}, socket) do
    blackout = Bookings.get_blackout!(id)
    Bookings.delete_blackout(blackout)

    # Preserve date range if available
    query_params = %{property: socket.assigns.selected_property}

    query_params =
      if socket.assigns[:calendar_start_date] &&
           socket.assigns[:calendar_end_date] do
        Map.merge(query_params, %{
          from_date: Date.to_string(socket.assigns.calendar_start_date),
          to_date: Date.to_string(socket.assigns.calendar_end_date)
        })
      else
        query_params
      end

    {:noreply,
     socket
     |> put_flash(:info, "Blackout deleted successfully")
     |> push_navigate(to: ~p"/admin/bookings?#{URI.encode_query(query_params)}")
     |> update_calendar_view(socket.assigns.selected_property)}
  end

  def handle_event("delete-booking", %{"id" => id}, socket) do
    booking = Bookings.get_booking!(id)
    Bookings.delete_booking(booking)

    # Remove from stream if we're on the reservations section
    socket =
      if socket.assigns[:current_section] == :reservations do
        socket
        |> stream_delete(:reservations, booking)
      else
        # If not on reservations section, preserve date range and navigate
        query_params = %{property: socket.assigns.selected_property}

        query_params =
          if socket.assigns[:calendar_start_date] &&
               socket.assigns[:calendar_end_date] do
            Map.merge(query_params, %{
              from_date: Date.to_string(socket.assigns.calendar_start_date),
              to_date: Date.to_string(socket.assigns.calendar_end_date)
            })
          else
            query_params
          end

        socket
        |> push_navigate(
          to: ~p"/admin/bookings?#{URI.encode_query(query_params)}"
        )
        |> update_calendar_view(socket.assigns.selected_property)
      end

    {:noreply, socket |> put_flash(:info, "Booking deleted successfully")}
  end

  def handle_event("view-booking", %{"booking-id" => booking_id}, socket) do
    # Ensure we have valid dates before building query params
    start_date =
      socket.assigns[:calendar_start_date] || Date.add(Date.utc_today(), -2)

    end_date =
      socket.assigns[:calendar_end_date] || Date.add(Date.utc_today(), 14)

    # Start with base query params
    base_query_params = %{
      "property" => Atom.to_string(socket.assigns.selected_property),
      "from_date" => Date.to_string(start_date),
      "to_date" => Date.to_string(end_date)
    }

    # Preserve section if on reservations tab
    query_params =
      if socket.assigns[:current_section] == :reservations do
        Map.put(base_query_params, "section", "reservations")
      else
        base_query_params
      end

    # Preserve search and filter parameters from reservation_params if on reservations tab
    query_params =
      if socket.assigns[:current_section] == :reservations &&
           socket.assigns[:reservation_params] do
        reservation_params = socket.assigns[:reservation_params]

        # Preserve search query if it exists
        query_params =
          if reservation_params["search"] do
            Map.put(query_params, "search", reservation_params["search"])
          else
            query_params
          end

        # Preserve date range filters if they exist
        query_params =
          if reservation_params["filter"] do
            filter_params = reservation_params["filter"]
            filter_map = %{}

            filter_map =
              if filter_params["filter_start_date"] do
                Map.put(
                  filter_map,
                  "filter_start_date",
                  filter_params["filter_start_date"]
                )
              else
                filter_map
              end

            filter_map =
              if filter_params["filter_end_date"] do
                Map.put(
                  filter_map,
                  "filter_end_date",
                  filter_params["filter_end_date"]
                )
              else
                filter_map
              end

            if map_size(filter_map) > 0 do
              Map.put(query_params, "filter", filter_map)
            else
              query_params
            end
          else
            query_params
          end

        query_params
      else
        query_params
      end

    # Build URL properly - combine path and query string
    base_path = ~p"/admin/bookings/#{booking_id}"
    query_string = URI.encode_query(flatten_query_params(query_params))

    # Combine path and query string for navigation
    full_path = "#{base_path}?#{query_string}"

    {:noreply, push_navigate(socket, to: full_path)}
  end

  def handle_event("view-blackout", %{"blackout-id" => blackout_id}, socket) do
    # Ensure we have valid dates before building query params
    start_date =
      socket.assigns[:calendar_start_date] || Date.add(Date.utc_today(), -2)

    end_date =
      socket.assigns[:calendar_end_date] || Date.add(Date.utc_today(), 14)

    query_params = [
      property: socket.assigns.selected_property,
      from_date: Date.to_string(start_date),
      to_date: Date.to_string(end_date)
    ]

    # Build URL properly - combine path and query string
    base_path = ~p"/admin/bookings/blackouts/#{blackout_id}/edit"
    query_string = URI.encode_query(query_params)

    # Combine path and query string for navigation
    full_path = "#{base_path}?#{query_string}"

    {:noreply, push_navigate(socket, to: full_path)}
  end

  def handle_event("select-date-blackout", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)

    # If we already have a start date selected, this is the end date
    if socket.assigns[:date_selection_type] == :blackout &&
         socket.assigns[:date_selection_start] do
      start_date_selected = socket.assigns.date_selection_start
      # Ensure end date is after start date
      {final_start, final_end} =
        if Date.compare(date, start_date_selected) == :lt do
          {date, start_date_selected}
        else
          {start_date_selected, date}
        end

      # Navigate to form with date range
      calendar_start =
        socket.assigns[:calendar_start_date] || Date.add(Date.utc_today(), -2)

      calendar_end =
        socket.assigns[:calendar_end_date] || Date.add(Date.utc_today(), 14)

      query_params = [
        property: socket.assigns.selected_property,
        from_date: Date.to_string(calendar_start),
        to_date: Date.to_string(calendar_end),
        start_date: Date.to_string(final_start),
        end_date: Date.to_string(final_end)
      ]

      {:noreply,
       socket
       |> assign(:date_selection_type, nil)
       |> assign(:date_selection_start, nil)
       |> push_navigate(
         to: ~p"/admin/bookings/blackouts/new?#{URI.encode_query(query_params)}"
       )}
    else
      # First click - set start date
      {:noreply,
       socket
       |> assign(:date_selection_type, :blackout)
       |> assign(:date_selection_start, date)
       |> assign(:date_selection_hover_end, nil)}
    end
  end

  def handle_event("select-date-buyout", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)

    # If we already have a start date selected, this is the end date
    if socket.assigns[:date_selection_type] == :buyout &&
         socket.assigns[:date_selection_start] do
      start_date_selected = socket.assigns.date_selection_start
      # Ensure end date is after start date
      {final_start, final_end} =
        if Date.compare(date, start_date_selected) == :lt do
          {date, start_date_selected}
        else
          {start_date_selected, date}
        end

      # Navigate to form with date range
      calendar_start =
        socket.assigns[:calendar_start_date] || Date.add(Date.utc_today(), -2)

      calendar_end =
        socket.assigns[:calendar_end_date] || Date.add(Date.utc_today(), 14)

      query_params = [
        property: socket.assigns.selected_property,
        from_date: Date.to_string(calendar_start),
        to_date: Date.to_string(calendar_end),
        type: "buyout",
        start_date: Date.to_string(final_start),
        end_date: Date.to_string(final_end)
      ]

      {:noreply,
       socket
       |> assign(:date_selection_type, nil)
       |> assign(:date_selection_start, nil)
       |> assign(:date_selection_hover_end, nil)
       |> push_navigate(
         to: ~p"/admin/bookings/bookings/new?#{URI.encode_query(query_params)}"
       )}
    else
      # First click - set start date
      {:noreply,
       socket
       |> assign(:date_selection_type, :buyout)
       |> assign(:date_selection_start, date)
       |> assign(:date_selection_hover_end, nil)}
    end
  end

  def handle_event(
        "select-date-room",
        %{"date" => date_str, "room-id" => room_id},
        socket
      ) do
    date = Date.from_iso8601!(date_str)

    # If we already have a start date selected for this room, this is the end date
    if socket.assigns[:date_selection_type] == :room &&
         socket.assigns[:date_selection_start] &&
         socket.assigns[:date_selection_room_id] == room_id do
      start_date_selected = socket.assigns.date_selection_start
      # Ensure end date is after start date
      {final_start, final_end} =
        if Date.compare(date, start_date_selected) == :lt do
          {date, start_date_selected}
        else
          {start_date_selected, date}
        end

      # Navigate to form with date range
      calendar_start =
        socket.assigns[:calendar_start_date] || Date.add(Date.utc_today(), -2)

      calendar_end =
        socket.assigns[:calendar_end_date] || Date.add(Date.utc_today(), 14)

      query_params = [
        property: socket.assigns.selected_property,
        from_date: Date.to_string(calendar_start),
        to_date: Date.to_string(calendar_end),
        type: "room",
        room_id: room_id,
        start_date: Date.to_string(final_start),
        end_date: Date.to_string(final_end)
      ]

      {:noreply,
       socket
       |> assign(:date_selection_type, nil)
       |> assign(:date_selection_start, nil)
       |> assign(:date_selection_room_id, nil)
       |> assign(:date_selection_hover_end, nil)
       |> push_navigate(
         to: ~p"/admin/bookings/bookings/new?#{URI.encode_query(query_params)}"
       )}
    else
      # First click - set start date and room
      {:noreply,
       socket
       |> assign(:date_selection_type, :room)
       |> assign(:date_selection_start, date)
       |> assign(:date_selection_room_id, room_id)
       |> assign(:date_selection_hover_end, nil)}
    end
  end

  # Cancel selection by clicking outside or pressing escape
  def handle_event("cancel-date-selection", _, socket) do
    {:noreply,
     socket
     |> assign(:date_selection_type, nil)
     |> assign(:date_selection_start, nil)
     |> assign(:date_selection_room_id, nil)
     |> assign(:date_selection_hover_end, nil)}
  end

  # Handle hover over calendar cells to show ghost preview
  def handle_event(
        "hover-date",
        %{
          "date" => date_str,
          "selection_type" => selection_type,
          "room_id" => room_id
        },
        socket
      ) do
    # Only show hover if we have a start date selected and the selection type matches
    if socket.assigns[:date_selection_type] &&
         String.to_existing_atom(selection_type) ==
           socket.assigns.date_selection_type &&
         (socket.assigns[:date_selection_type] != :room ||
            socket.assigns[:date_selection_room_id] == room_id) do
      date = Date.from_iso8601!(date_str)
      {:noreply, assign(socket, :date_selection_hover_end, date)}
    else
      {:noreply, assign(socket, :date_selection_hover_end, nil)}
    end
  end

  def handle_event(
        "hover-date",
        %{"date" => date_str, "selection_type" => selection_type},
        socket
      ) do
    # For blackout and buyout (no room_id)
    if socket.assigns[:date_selection_type] &&
         String.to_existing_atom(selection_type) ==
           socket.assigns.date_selection_type do
      date = Date.from_iso8601!(date_str)
      {:noreply, assign(socket, :date_selection_hover_end, date)}
    else
      {:noreply, assign(socket, :date_selection_hover_end, nil)}
    end
  end

  def handle_event("hover-date", _params, socket) do
    {:noreply, socket}
  end

  # Clear hover when mouse leaves calendar area
  def handle_event("clear-hover", _, socket) do
    {:noreply, assign(socket, :date_selection_hover_end, nil)}
  end

  def handle_event("select-section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)

    # Build query params preserving property and calendar dates
    query_params = %{
      "property" => Atom.to_string(socket.assigns.selected_property),
      "section" => section
    }

    query_params =
      if socket.assigns[:calendar_start_date] &&
           socket.assigns[:calendar_end_date] do
        Map.merge(query_params, %{
          "from_date" => Date.to_string(socket.assigns.calendar_start_date),
          "to_date" => Date.to_string(socket.assigns.calendar_end_date)
        })
      else
        query_params
      end

    # Preserve reservation params if switching to reservations section
    query_params =
      if section_atom == :reservations && socket.assigns[:reservation_params] do
        reservation_params = socket.assigns[:reservation_params]

        # Preserve search if it exists
        query_params =
          if reservation_params["search"] do
            Map.put(query_params, "search", reservation_params["search"])
          else
            query_params
          end

        # Preserve date range filters if they exist
        query_params =
          if reservation_params["filter"] do
            filter_params = reservation_params["filter"]
            filter_map = %{}

            filter_map =
              if filter_params["filter_start_date"] do
                Map.put(
                  filter_map,
                  "filter_start_date",
                  filter_params["filter_start_date"]
                )
              else
                filter_map
              end

            filter_map =
              if filter_params["filter_end_date"] do
                Map.put(
                  filter_map,
                  "filter_end_date",
                  filter_params["filter_end_date"]
                )
              else
                filter_map
              end

            if map_size(filter_map) > 0 do
              Map.put(query_params, "filter", filter_map)
            else
              query_params
            end
          else
            query_params
          end

        query_params
      else
        query_params
      end

    socket =
      socket
      |> assign(:current_section, section_atom)
      |> then(fn s ->
        if section_atom == :reservations do
          assign(
            s,
            :reservations_path,
            build_reservations_path(s, query_params)
          )
        else
          s
        end
      end)

    # Flatten nested maps before encoding
    flattened_params = flatten_query_params(query_params)
    query_string = URI.encode_query(flattened_params)

    {:noreply, push_patch(socket, to: "/admin/bookings?#{query_string}")}
  end

  def handle_event("approve-refund", %{"id" => id}, socket) do
    pending_refund = Bookings.get_pending_refund!(id)

    case Bookings.approve_pending_refund(
           pending_refund,
           nil,
           nil,
           socket.assigns.current_user
         ) do
      {:ok, _updated_refund, _stripe_refund_id} ->
        {:noreply,
         socket
         |> put_flash(:info, "Refund approved and processed successfully")
         |> load_pending_refunds()}

      {:error, reason} ->
        error_message =
          case reason do
            {:refund_failed, _} -> "Failed to process refund. Please try again."
            _ -> "Failed to approve refund. Please try again."
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  def handle_event("show-approve-refund-modal", %{"id" => id}, socket) do
    pending_refund = Bookings.get_pending_refund!(id)

    form =
      {%{}, %{admin_refund_amount: :string, admin_notes: :string}}
      |> Ecto.Changeset.cast(%{}, [:admin_refund_amount, :admin_notes])
      |> to_form(as: "approve_refund")

    {:noreply,
     socket
     |> assign(:selected_pending_refund, pending_refund)
     |> assign(:approve_refund_form, form)}
  end

  def handle_event("show-reject-refund-modal", %{"id" => id}, socket) do
    pending_refund = Bookings.get_pending_refund!(id)

    form =
      {%{}, %{admin_notes: :string}}
      |> Ecto.Changeset.cast(%{}, [:admin_notes])
      |> to_form(as: "reject_refund")

    {:noreply,
     socket
     |> assign(:selected_pending_refund, pending_refund)
     |> assign(:reject_refund_form, form)}
  end

  def handle_event(
        "approve-refund-custom",
        %{"approve_refund" => params},
        socket
      ) do
    pending_refund = socket.assigns.selected_pending_refund

    # Parse custom refund amount
    admin_refund_amount = MoneyHelper.parse_money(params["admin_refund_amount"])

    admin_notes = params["admin_notes"]

    case Bookings.approve_pending_refund(
           pending_refund,
           admin_refund_amount,
           admin_notes,
           socket.assigns.current_user
         ) do
      {:ok, _updated_refund, _stripe_refund_id} ->
        {:noreply,
         socket
         |> put_flash(:info, "Refund approved and processed successfully")
         |> assign(:selected_pending_refund, nil)
         |> assign(:approve_refund_form, nil)
         |> load_pending_refunds()}

      {:error, reason} ->
        error_message =
          case reason do
            {:refund_failed, _} -> "Failed to process refund. Please try again."
            _ -> "Failed to approve refund. Please try again."
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  def handle_event("reject-refund", %{"reject_refund" => params}, socket) do
    pending_refund = socket.assigns.selected_pending_refund
    admin_notes = params["admin_notes"]

    case Bookings.reject_pending_refund(
           pending_refund,
           admin_notes,
           socket.assigns.current_user
         ) do
      {:ok, _updated_refund} ->
        {:noreply,
         socket
         |> put_flash(:info, "Refund rejected")
         |> assign(:selected_pending_refund, nil)
         |> assign(:reject_refund_form, nil)
         |> load_pending_refunds()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to reject refund. Please try again.")
         |> assign(:reject_refund_form, to_form(changeset, as: "reject_refund"))}
    end
  end

  def handle_event("close-approve-refund-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_pending_refund, nil)
     |> assign(:approve_refund_form, nil)}
  end

  def handle_event("close-reject-refund-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_pending_refund, nil)
     |> assign(:reject_refund_form, nil)}
  end

  # Booking refund handlers
  def handle_event("show-booking-refund-modal", _params, socket) do
    {:noreply, assign(socket, :show_refund_modal, true)}
  end

  def handle_event("close-booking-modal", _params, socket) do
    # Don't close booking modal if refund modal is open
    if socket.assigns[:show_refund_modal] do
      {:noreply, socket}
    else
      query_params =
        build_booking_modal_close_params(
          socket.assigns.selected_property,
          socket.assigns.calendar_start_date,
          socket.assigns.calendar_end_date,
          socket.assigns.current_section,
          socket.assigns[:reservation_params]
        )

      query_string = URI.encode_query(flatten_query_params(query_params))
      {:noreply, push_navigate(socket, to: ~p"/admin/bookings?#{query_string}")}
    end
  end

  def handle_event("close-booking-refund-modal", _params, socket) do
    {:noreply, assign(socket, :show_refund_modal, false)}
  end

  def handle_event(
        "process-booking-refund",
        %{"refund" => refund_params},
        socket
      ) do
    booking = socket.assigns.booking
    primary_payment = socket.assigns.primary_payment

    # Parse refund amount
    refund_amount = MoneyHelper.parse_money(refund_params["amount"])
    reason = refund_params["reason"]
    release_availability = refund_params["release_availability"] == "true"

    if is_nil(refund_amount) do
      {:noreply, put_flash(socket, :error, "Invalid refund amount")}
    else
      # Convert Money to cents for Stripe
      refund_amount_cents = MoneyHelper.money_to_cents(refund_amount)

      # Process refund via Stripe first, then ledger
      result =
        if primary_payment.external_payment_id &&
             primary_payment.external_provider == :stripe do
          # Use the same create_stripe_refund approach as approve_pending_refund
          case Bookings.create_stripe_refund_for_admin(
                 primary_payment.external_payment_id,
                 refund_amount_cents,
                 reason
               ) do
            {:ok, stripe_refund} ->
              # Process refund in ledger
              Ysc.Ledgers.process_refund(%{
                payment_id: primary_payment.id,
                refund_amount: refund_amount,
                reason: reason,
                external_refund_id: stripe_refund.id
              })

            {:error, reason} ->
              {:error, {:stripe_error, reason}}
          end
        else
          {:error, :no_stripe_payment}
        end

      case result do
        {:ok, _refund} ->
          # Optionally release booking availability
          if release_availability do
            Bookings.update_booking(booking, %{status: :refunded})
          end

          # Preserve date range if available
          query_params = %{property: socket.assigns.selected_property}

          query_params =
            if socket.assigns[:calendar_start_date] &&
                 socket.assigns[:calendar_end_date] do
              Map.merge(query_params, %{
                from_date: Date.to_string(socket.assigns.calendar_start_date),
                to_date: Date.to_string(socket.assigns.calendar_end_date)
              })
            else
              query_params
            end

          {:noreply,
           socket
           |> put_flash(:info, "Refund processed successfully")
           |> assign(:show_refund_modal, false)
           |> push_navigate(
             to: ~p"/admin/bookings?#{URI.encode_query(query_params)}"
           )
           |> update_calendar_view(socket.assigns.selected_property)}

        {:error, {:already_processed, _, _}} ->
          {:noreply,
           put_flash(socket, :error, "Refund has already been processed.")}

        {:error, {:stripe_error, msg}} ->
          {:noreply, put_flash(socket, :error, "Stripe error: #{inspect(msg)}")}

        {:error, :no_stripe_payment} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Cannot process refund: No Stripe payment found."
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to process refund: #{inspect(reason)}"
           )}
      end
    end
  end

  def handle_event(
        "validate-booking-refund",
        %{"refund" => refund_params},
        socket
      ) do
    # Simple validation changeset for the form
    changeset =
      {%{}, %{amount: :string, reason: :string, release_availability: :boolean}}
      |> Ecto.Changeset.cast(refund_params, [
        :amount,
        :reason,
        :release_availability
      ])
      |> Ecto.Changeset.validate_required([:amount, :reason])
      |> Ecto.Changeset.validate_length(:reason, min: 1, max: 1000)
      |> validate_amount_format()
      |> Map.put(:action, :validate)

    # Ensure modal stays open during validation
    {:noreply,
     socket
     |> assign(:refund_form, to_form(changeset, as: "refund"))
     |> assign(:show_refund_modal, true)}
  end

  def handle_event("prev-month", _, socket) do
    current_date = socket.assigns.calendar_start_date

    new_start =
      if current_date.month == 1 do
        Date.new!(current_date.year - 1, 12, 1)
      else
        Date.new!(current_date.year, current_date.month - 1, 1)
      end

    new_end = Date.end_of_month(new_start)

    # Update URL to preserve date range
    query_params = %{
      property: socket.assigns.selected_property,
      from_date: Date.to_string(new_start),
      to_date: Date.to_string(new_end)
    }

    {:noreply,
     socket
     |> assign(:calendar_start_date, new_start)
     |> assign(:calendar_end_date, new_end)
     |> push_patch(to: ~p"/admin/bookings?#{URI.encode_query(query_params)}")
     |> update_calendar_view(socket.assigns.selected_property)}
  end

  def handle_event("next-month", _, socket) do
    current_date = socket.assigns.calendar_start_date

    new_start =
      if current_date.month == 12 do
        Date.new!(current_date.year + 1, 1, 1)
      else
        Date.new!(current_date.year, current_date.month + 1, 1)
      end

    new_end = Date.end_of_month(new_start)

    # Update URL to preserve date range
    query_params = %{
      property: socket.assigns.selected_property,
      from_date: Date.to_string(new_start),
      to_date: Date.to_string(new_end)
    }

    {:noreply,
     socket
     |> assign(:calendar_start_date, new_start)
     |> assign(:calendar_end_date, new_end)
     |> push_patch(to: ~p"/admin/bookings?#{URI.encode_query(query_params)}")
     |> update_calendar_view(socket.assigns.selected_property)}
  end

  def handle_event("today", _, socket) do
    today = Date.utc_today()
    calendar_start = Date.beginning_of_month(today)
    calendar_end = Date.end_of_month(today)

    # Update URL to preserve date range
    query_params = %{
      property: socket.assigns.selected_property,
      from_date: Date.to_string(calendar_start),
      to_date: Date.to_string(calendar_end)
    }

    {:noreply,
     socket
     |> assign(:calendar_start_date, calendar_start)
     |> assign(:calendar_end_date, calendar_end)
     |> push_patch(to: ~p"/admin/bookings?#{URI.encode_query(query_params)}")
     |> update_calendar_view(socket.assigns.selected_property)}
  end

  def handle_event("update-calendar-range", params, socket) do
    # Get date values from form params
    from_date_str = Map.get(params, "from_date")
    to_date_str = Map.get(params, "to_date")

    # Parse dates, fallback to current values if not provided or invalid
    calendar_start =
      if from_date_str && from_date_str != "" do
        case Date.from_iso8601(from_date_str) do
          {:ok, date} -> date
          _ -> socket.assigns.calendar_start_date
        end
      else
        socket.assigns.calendar_start_date
      end

    calendar_end =
      if to_date_str && to_date_str != "" do
        case Date.from_iso8601(to_date_str) do
          {:ok, date} -> date
          _ -> socket.assigns.calendar_end_date
        end
      else
        socket.assigns.calendar_end_date
      end

    # Ensure end date is after start date
    {final_start, final_end} =
      if Date.compare(calendar_start, calendar_end) == :gt do
        {calendar_end, calendar_start}
      else
        {calendar_start, calendar_end}
      end

    # Update URL to preserve date range
    query_params = %{
      property: socket.assigns.selected_property,
      from_date: Date.to_string(final_start),
      to_date: Date.to_string(final_end)
    }

    # Update assigns and regenerate calendar
    updated_socket =
      socket
      |> assign(:calendar_start_date, final_start)
      |> assign(:calendar_end_date, final_end)

    {:noreply,
     updated_socket
     |> push_patch(to: ~p"/admin/bookings?#{URI.encode_query(query_params)}")
     |> update_calendar_view(updated_socket.assigns.selected_property)}
  end

  def handle_event(
        "validate-pricing-rule",
        %{"pricing_rule" => pricing_rule_params},
        socket
      ) do
    changeset =
      (socket.assigns.pricing_rule || %Ysc.Bookings.PricingRule{})
      |> Ysc.Bookings.PricingRule.changeset(pricing_rule_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "pricing_rule"))}
  end

  def handle_event("validate-booking", %{"booking" => booking_params}, socket) do
    # Use existing booking if editing, otherwise new struct
    booking = socket.assigns[:booking] || %Ysc.Bookings.Booking{}

    changeset =
      booking
      |> Ysc.Bookings.Booking.changeset(booking_params, skip_validation: true)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :booking_form, to_form(changeset, as: "booking"))}
  end

  # User autocomplete handlers for booking form
  def handle_event("search-booking-users", %{"value" => query}, socket) do
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

  def handle_event("select-booking-user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  def handle_event("clear-booking-user", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  def handle_event("save-booking", %{"booking" => booking_params}, socket) do
    # Convert property string to atom
    booking_params =
      if property_str = booking_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(booking_params, "property", property_atom)
      else
        booking_params
      end

    # Convert booking_mode string to atom
    booking_params =
      if booking_mode_str = booking_params["booking_mode"] do
        booking_mode_atom = String.to_existing_atom(booking_mode_str)
        Map.put(booking_params, "booking_mode", booking_mode_atom)
      else
        booking_params
      end

    # Convert status string to atom if provided
    booking_params =
      if status_str = booking_params["status"] do
        status_atom = String.to_existing_atom(status_str)
        Map.put(booking_params, "status", status_atom)
      else
        booking_params
      end

    # Convert user_id string to proper format if needed
    booking_params =
      if user_id_str = booking_params["user_id"] do
        Map.put(booking_params, "user_id", user_id_str)
      else
        booking_params
      end

    # Get room_id from params (could be nil or empty string)
    room_id = booking_params["room_id"]
    room_id = if room_id == "" or is_nil(room_id), do: nil, else: room_id

    # Remove room_id from params as it's not a direct field on booking
    booking_params = Map.delete(booking_params, "room_id")

    # Fetch the room if room_id is provided (for room bookings)
    rooms =
      if room_id do
        room = Bookings.get_room!(room_id)
        [room]
      else
        []
      end

    # Determine if this is a create or update operation
    existing_booking = socket.assigns[:booking]

    # Build changeset opts - include rooms for new bookings or when changing booking type
    changeset_opts =
      if existing_booking do
        # For updates, only set rooms if explicitly changing to room booking
        if room_id && booking_params["booking_mode"] == :room do
          [skip_validation: true, rooms: rooms]
        else
          [skip_validation: true]
        end
      else
        # For new bookings, always include rooms (even if empty for buyouts)
        [skip_validation: true, rooms: rooms]
      end

    result =
      if existing_booking do
        # Update existing booking with validation skipped (admin override)
        changeset =
          existing_booking
          |> Ysc.Bookings.Booking.changeset(booking_params, changeset_opts)

        Ysc.Repo.update(changeset)
      else
        # Create new booking using BookingLocker which handles:
        # - Setting status to :complete
        # - Updating inventory
        # - Sending confirmation email
        # - Scheduling check-in/checkout reminders
        alias Ysc.Bookings.BookingLocker

        # Convert string keys to atoms for BookingLocker
        attrs = %{
          user_id: booking_params["user_id"],
          property: booking_params["property"],
          checkin_date: parse_date(booking_params["checkin_date"]),
          checkout_date: parse_date(booking_params["checkout_date"]),
          guests_count: parse_integer(booking_params["guests_count"], 1),
          children_count: parse_integer(booking_params["children_count"], 0),
          booking_mode: booking_params["booking_mode"]
        }

        BookingLocker.create_admin_booking(attrs, rooms: rooms)
      end

    case result do
      {:ok, _booking} ->
        # Preserve date range if available
        query_params = %{property: socket.assigns.selected_property}

        query_params =
          if socket.assigns[:calendar_start_date] &&
               socket.assigns[:calendar_end_date] do
            Map.merge(query_params, %{
              from_date: Date.to_string(socket.assigns.calendar_start_date),
              to_date: Date.to_string(socket.assigns.calendar_end_date)
            })
          else
            query_params
          end

        action_word = if existing_booking, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Booking #{action_word} successfully. Confirmation email sent to user."
         )
         |> push_navigate(
           to: ~p"/admin/bookings?#{URI.encode_query(query_params)}"
         )
         |> update_calendar_view(socket.assigns.selected_property)}

      {:error, {:error, changeset}} when is_struct(changeset, Ecto.Changeset) ->
        {:noreply,
         assign(socket, :booking_form, to_form(changeset, as: "booking"))}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:noreply,
         assign(socket, :booking_form, to_form(changeset, as: "booking"))}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Failed to create booking: #{inspect(reason)}"
         )}
    end
  end

  def handle_event(
        "change-reservation-search",
        %{"search" => %{"query" => search_query}},
        socket
      ) do
    # Prevent default form submission
    new_reservation_params =
      if search_query == "" do
        # Remove search from params if empty
        Map.delete(socket.assigns[:reservation_params] || %{}, "search")
      else
        Map.put(socket.assigns[:reservation_params] || %{}, "search", %{
          "query" => search_query
        })
      end

    updated_params =
      build_reservation_query_params(socket, new_reservation_params)

    query_string = URI.encode_query(updated_params)

    {:noreply,
     socket
     |> assign(:reservation_params, new_reservation_params)
     |> assign(
       :reservations_path,
       build_reservations_path(socket, updated_params)
     )
     |> push_patch(to: "/admin/bookings?#{query_string}")}
  end

  def handle_event(
        "change-reservation-search",
        %{"search" => search_query},
        socket
      )
      when is_binary(search_query) do
    # Prevent default form submission
    new_reservation_params =
      if search_query == "" do
        # Remove search from params if empty
        Map.delete(socket.assigns[:reservation_params] || %{}, "search")
      else
        Map.put(socket.assigns[:reservation_params] || %{}, "search", %{
          "query" => search_query
        })
      end

    updated_params =
      build_reservation_query_params(socket, new_reservation_params)

    query_string = URI.encode_query(updated_params)

    {:noreply,
     socket
     |> assign(:reservation_params, new_reservation_params)
     |> assign(
       :reservations_path,
       build_reservations_path(socket, updated_params)
     )
     |> push_patch(to: "/admin/bookings?#{query_string}")}
  end

  def handle_event("update-reservation-date-range", params, socket) do
    filter_start_date_str = Map.get(params, "filter_start_date")
    filter_end_date_str = Map.get(params, "filter_end_date")

    filter_start_date =
      if filter_start_date_str && filter_start_date_str != "" do
        case Date.from_iso8601(filter_start_date_str) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filter_end_date =
      if filter_end_date_str && filter_end_date_str != "" do
        case Date.from_iso8601(filter_end_date_str) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    new_params = socket.assigns[:reservation_params] || %{}
    filter_params = new_params["filter"] || %{}

    filter_params =
      filter_params
      |> (fn f ->
            if filter_start_date,
              do:
                Map.put(
                  f,
                  "filter_start_date",
                  Date.to_string(filter_start_date)
                ),
              else: Map.delete(f, "filter_start_date")
          end).()
      |> (fn f ->
            if filter_end_date,
              do:
                Map.put(f, "filter_end_date", Date.to_string(filter_end_date)),
              else: Map.delete(f, "filter_end_date")
          end).()

    new_params = Map.put(new_params, "filter", filter_params)
    updated_params = build_reservation_query_params(socket, new_params)
    query_string = URI.encode_query(updated_params)

    {:noreply,
     socket
     |> assign(:reservation_params, new_params)
     |> assign(:reservation_filter_start_date, filter_start_date)
     |> assign(:reservation_filter_end_date, filter_end_date)
     |> assign(
       :reservations_path,
       build_reservations_path(socket, updated_params)
     )
     |> push_patch(to: "/admin/bookings?#{query_string}")}
  end

  def handle_event("clear-reservation-filters", _, socket) do
    updated_params = build_reservation_query_params(socket, %{})
    query_string = URI.encode_query(updated_params)

    {:noreply,
     socket
     |> assign(:reservation_params, %{})
     |> assign(:reservation_filter_start_date, nil)
     |> assign(:reservation_filter_end_date, nil)
     |> assign(
       :reservations_path,
       build_reservations_path(socket, updated_params)
     )
     |> push_patch(to: "/admin/bookings?#{query_string}")}
  end

  def handle_event(
        "save-pricing-rule",
        %{"pricing_rule" => pricing_rule_params},
        socket
      ) do
    # Convert amount string to Money struct
    pricing_rule_params =
      if amount_str = pricing_rule_params["amount"] do
        case MoneyHelper.parse_money(amount_str) do
          %Money{} = money ->
            Map.put(pricing_rule_params, "amount", money)

          nil ->
            pricing_rule_params
        end
      else
        pricing_rule_params
      end

    # Convert children_amount string to Money struct (if provided)
    pricing_rule_params =
      if children_amount_str = pricing_rule_params["children_amount"] do
        case MoneyHelper.parse_money(children_amount_str) do
          %Money{} = money ->
            Map.put(pricing_rule_params, "children_amount", money)

          nil ->
            # If empty string, set to nil
            Map.put(pricing_rule_params, "children_amount", nil)
        end
      else
        # If not provided, set to nil
        Map.put(pricing_rule_params, "children_amount", nil)
      end

    # Convert property string to atom
    pricing_rule_params =
      if property_str = pricing_rule_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(pricing_rule_params, "property", property_atom)
      else
        pricing_rule_params
      end

    # Convert booking_mode and price_unit strings to atoms
    pricing_rule_params =
      pricing_rule_params
      |> maybe_convert_atom("booking_mode")
      |> maybe_convert_atom("price_unit")

    result =
      if socket.assigns.pricing_rule do
        Bookings.update_pricing_rule(
          socket.assigns.pricing_rule,
          pricing_rule_params
        )
      else
        Bookings.create_pricing_rule(pricing_rule_params)
      end

    case result do
      {:ok, _pricing_rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pricing rule saved successfully")
         |> push_navigate(
           to:
             ~p"/admin/bookings?property=#{socket.assigns.selected_property}&section=#{socket.assigns.current_section}"
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, to_form(changeset, as: "pricing_rule"))}
    end
  end

  def handle_event(
        "validate-door-code",
        %{"door_code" => door_code_params},
        socket
      ) do
    code = String.trim(door_code_params["code"] || "")
    property = socket.assigns.selected_property

    # Check for code reuse warning
    warning =
      if code != "" && String.length(code) >= 4 do
        # Get the last 3 codes (without excluding the current code)
        recent_codes = Bookings.get_recent_door_codes(property, nil)
        recent_codes_list = Enum.map(recent_codes, & &1.code)

        if code in recent_codes_list do
          "This code matches one of the last 3 used codes for this property. Are you sure you want to reuse it?"
        else
          nil
        end
      else
        nil
      end

    # Create a simple changeset for validation
    changeset =
      %Ysc.Bookings.DoorCode{}
      |> Ysc.Bookings.DoorCode.changeset(door_code_params)

    form = to_form(changeset, as: "door_code")

    {:noreply,
     socket
     |> assign(:door_code_form, form)
     |> assign(:door_code_warning, warning)}
  end

  def handle_event("validate-season", %{"season" => season_params}, socket) do
    changeset =
      (socket.assigns.season || %Ysc.Bookings.Season{})
      |> Ysc.Bookings.Season.changeset(season_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :season_form, to_form(changeset, as: "season"))}
  end

  def handle_event("save-season", %{"season" => season_params}, socket) do
    # Convert property string to atom
    season_params =
      if property_str = season_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(season_params, "property", property_atom)
      else
        season_params
      end

    # Convert advance_booking_days to integer or nil
    season_params =
      if advance_days_str = season_params["advance_booking_days"] do
        advance_days_str = String.trim(advance_days_str)

        if advance_days_str == "" do
          Map.put(season_params, "advance_booking_days", nil)
        else
          case Integer.parse(advance_days_str) do
            {days, _} when days > 0 ->
              Map.put(season_params, "advance_booking_days", days)

            _ ->
              Map.put(season_params, "advance_booking_days", nil)
          end
        end
      else
        Map.put(season_params, "advance_booking_days", nil)
      end

    # Convert max_nights to integer or nil
    season_params =
      if max_nights_str = season_params["max_nights"] do
        max_nights_str = String.trim(max_nights_str)

        if max_nights_str == "" do
          Map.put(season_params, "max_nights", nil)
        else
          case Integer.parse(max_nights_str) do
            {nights, _} when nights > 0 ->
              Map.put(season_params, "max_nights", nights)

            _ ->
              Map.put(season_params, "max_nights", nil)
          end
        end
      else
        Map.put(season_params, "max_nights", nil)
      end

    result = Bookings.update_season(socket.assigns.season, season_params)

    case result do
      {:ok, _season} ->
        # Reload seasons to reflect changes
        seasons = Bookings.list_seasons()

        {:noreply,
         socket
         |> put_flash(:info, "Season updated successfully")
         |> assign(:seasons, seasons)
         |> assign_filtered_data(
           socket.assigns.selected_property,
           seasons,
           socket.assigns.pricing_rules,
           socket.assigns.refund_policies
         )
         |> push_navigate(
           to:
             ~p"/admin/bookings?property=#{socket.assigns.selected_property}&section=config"
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :season_form, to_form(changeset, as: "season"))}
    end
  end

  def handle_event(
        "validate-refund-policy",
        %{"refund_policy" => refund_policy_params},
        socket
      ) do
    changeset =
      (socket.assigns.refund_policy || %Ysc.Bookings.RefundPolicy{})
      |> Ysc.Bookings.RefundPolicy.changeset(refund_policy_params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(
       socket,
       :refund_policy_form,
       to_form(changeset, as: "refund_policy")
     )}
  end

  def handle_event(
        "save-refund-policy",
        %{"refund_policy" => refund_policy_params},
        socket
      ) do
    # Convert property string to atom
    refund_policy_params =
      if property_str = refund_policy_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(refund_policy_params, "property", property_atom)
      else
        refund_policy_params
      end

    # Convert booking_mode string to atom
    refund_policy_params =
      refund_policy_params
      |> maybe_convert_atom("booking_mode")

    result =
      if socket.assigns.refund_policy do
        Bookings.update_refund_policy(
          socket.assigns.refund_policy,
          refund_policy_params
        )
      else
        Bookings.create_refund_policy(refund_policy_params)
      end

    case result do
      {:ok, _refund_policy} ->
        # Reload refund policies
        refund_policies = Bookings.list_refund_policies()

        {:noreply,
         socket
         |> put_flash(:info, "Refund policy saved successfully")
         |> assign(:refund_policies, refund_policies)
         |> assign_filtered_data(
           socket.assigns.selected_property,
           socket.assigns.seasons,
           socket.assigns.pricing_rules,
           refund_policies
         )
         |> push_navigate(
           to:
             ~p"/admin/bookings?property=#{socket.assigns.selected_property}&section=#{socket.assigns.current_section}"
         )}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :refund_policy_form,
           to_form(changeset, as: "refund_policy")
         )}
    end
  end

  def handle_event(
        "validate-refund-policy-rule",
        %{"refund_policy_rule" => rule_params},
        socket
      ) do
    changeset =
      %Ysc.Bookings.RefundPolicyRule{}
      |> Ysc.Bookings.RefundPolicyRule.changeset(rule_params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(
       socket,
       :refund_policy_rule_form,
       to_form(changeset, as: "refund_policy_rule")
     )}
  end

  def handle_event(
        "save-refund-policy-rule",
        %{"refund_policy_rule" => rule_params},
        socket
      ) do
    # Ensure refund_policy_id is included
    rule_params =
      Map.put(rule_params, "refund_policy_id", socket.assigns.refund_policy.id)

    # Convert refund_percentage to Decimal
    rule_params =
      if percentage_str = rule_params["refund_percentage"] do
        case Decimal.parse(percentage_str) do
          {decimal, _} -> Map.put(rule_params, "refund_percentage", decimal)
          _ -> rule_params
        end
      else
        rule_params
      end

    # Convert priority to integer
    rule_params =
      if priority_str = rule_params["priority"] do
        case Integer.parse(priority_str) do
          {priority, _} -> Map.put(rule_params, "priority", priority)
          _ -> Map.put(rule_params, "priority", 0)
        end
      else
        Map.put(rule_params, "priority", 0)
      end

    result = Bookings.create_refund_policy_rule(rule_params)

    case result do
      {:ok, _rule} ->
        # Reload rules
        refund_policy_rules =
          Bookings.list_refund_policy_rules(socket.assigns.refund_policy.id)

        # Reset form
        rule_form =
          %Ysc.Bookings.RefundPolicyRule{}
          |> Ysc.Bookings.RefundPolicyRule.changeset(%{
            refund_policy_id: socket.assigns.refund_policy.id,
            priority: 0
          })
          |> to_form(as: "refund_policy_rule")

        {:noreply,
         socket
         |> put_flash(:info, "Refund policy rule added successfully")
         |> assign(:refund_policy_rules, refund_policy_rules)
         |> assign(:refund_policy_rule_form, rule_form)}

      {:error, changeset} ->
        Logger.error("Failed to create refund policy rule",
          errors: inspect(changeset.errors),
          params: inspect(rule_params)
        )

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to save refund policy rule. Please check the form for errors."
         )
         |> assign(
           :refund_policy_rule_form,
           to_form(changeset, as: "refund_policy_rule")
         )}
    end
  end

  def handle_event("delete-refund-policy-rule", %{"rule-id" => rule_id}, socket) do
    rule = Bookings.get_refund_policy_rule!(rule_id)
    Bookings.delete_refund_policy_rule(rule)

    # Reload rules
    refund_policy_rules =
      Bookings.list_refund_policy_rules(socket.assigns.refund_policy.id)

    {:noreply,
     socket
     |> put_flash(:info, "Refund policy rule deleted successfully")
     |> assign(:refund_policy_rules, refund_policy_rules)}
  end

  def handle_event("save-door-code", %{"door_code" => door_code_params}, socket) do
    property = socket.assigns.selected_property
    code = String.trim(door_code_params["code"] || "")

    # Convert property to atom if it's a string
    door_code_params =
      door_code_params
      |> Map.put("property", property)
      |> Map.put("code", code)

    case Bookings.create_door_code(door_code_params) do
      {:ok, _door_code} ->
        # Reload door codes
        door_codes = Bookings.list_door_codes(property)
        active_door_code = Bookings.get_active_door_code(property)

        # Reset form
        door_code_form =
          %Ysc.Bookings.DoorCode{}
          |> Ysc.Bookings.DoorCode.changeset(%{})
          |> to_form(as: "door_code")

        {:noreply,
         socket
         |> put_flash(:info, "Door code set successfully")
         |> assign(:door_codes, door_codes)
         |> assign(:active_door_code, active_door_code)
         |> assign(:door_code_form, door_code_form)
         |> assign(:door_code_warning, nil)}

      {:error, :invalid_attributes} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Invalid door code. Please enter a 4-5 character alphanumeric code."
         )}

      {:error, changeset} ->
        errors = translate_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Failed to set door code: #{errors}")}
    end
  end

  def handle_event("validate-room", %{"room" => room_params}, socket) do
    alias Ysc.Media

    changeset =
      (socket.assigns.room || %Ysc.Bookings.Room{})
      |> Ysc.Bookings.Room.changeset(room_params)
      |> Map.put(:action, :validate)

    # Handle image_id if provided
    selected_image =
      if image_id_str = room_params["image_id"] do
        if image_id_str != "" do
          case Media.fetch_image(image_id_str) do
            nil -> socket.assigns[:selected_room_image]
            image -> image
          end
        else
          socket.assigns[:selected_room_image]
        end
      else
        socket.assigns[:selected_room_image]
      end

    {:noreply,
     socket
     |> assign(:room_form, to_form(changeset, as: "room"))
     |> assign(:selected_room_image, selected_image)}
  end

  def handle_event("save-room", %{"room" => room_params}, socket) do
    alias Ysc.Media

    # Convert property string to atom
    room_params =
      if property_str = room_params["property"] do
        property_atom = String.to_existing_atom(property_str)
        Map.put(room_params, "property", property_atom)
      else
        room_params
      end

    # Handle image_id - convert empty string to nil
    room_params =
      if image_id_str = room_params["image_id"] do
        if image_id_str == "" do
          Map.put(room_params, "image_id", nil)
        else
          room_params
        end
      else
        room_params
      end

    result =
      if socket.assigns.room do
        Bookings.update_room(socket.assigns.room, room_params)
      else
        Bookings.create_room(room_params)
      end

    case result do
      {:ok, _room} ->
        # Reload rooms to reflect changes
        rooms = Bookings.list_rooms()

        {:noreply,
         socket
         |> put_flash(:info, "Room saved successfully")
         |> assign(:rooms, rooms)
         |> assign_filtered_data(
           socket.assigns.selected_property,
           socket.assigns.seasons,
           socket.assigns.pricing_rules,
           socket.assigns.refund_policies
         )
         |> push_navigate(
           to:
             ~p"/admin/bookings?property=#{socket.assigns.selected_property}&section=#{socket.assigns.current_section}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :room_form, to_form(changeset, as: "room"))}
    end
  end

  def handle_event("delete-room", %{"id" => id}, socket) do
    room = Bookings.get_room!(id)
    Bookings.delete_room(room)

    # Reload rooms to reflect changes
    rooms = Bookings.list_rooms()

    {:noreply,
     socket
     |> put_flash(:info, "Room deleted successfully")
     |> assign(:rooms, rooms)
     |> assign_filtered_data(
       socket.assigns.selected_property,
       socket.assigns.seasons,
       socket.assigns.pricing_rules,
       socket.assigns.refund_policies
     )
     |> push_navigate(
       to:
         ~p"/admin/bookings?property=#{socket.assigns.selected_property}&section=#{socket.assigns.current_section}"
     )}
  end

  # Image gallery handlers
  def handle_event("open-image-gallery", _params, socket) do
    alias Ysc.Media

    # Load first page of images
    images = Media.list_images(0, 20)

    {:noreply,
     socket
     |> assign(:show_image_gallery, true)
     |> assign(:image_gallery, images)
     |> assign(:image_gallery_page, 1)
     |> assign(:image_gallery_end?, length(images) < 20)}
  end

  def handle_event("close-image-gallery", _params, socket) do
    {:noreply, assign(socket, :show_image_gallery, false)}
  end

  def handle_event("select-room-image", %{"image-id" => image_id}, socket) do
    alias Ysc.Media

    image = Media.fetch_image(image_id)

    # Update the form changeset with the new image_id
    current_params = socket.assigns.room_form.source.params || %{}
    updated_params = Map.put(current_params, "image_id", image_id)

    changeset =
      (socket.assigns.room || %Ysc.Bookings.Room{})
      |> Ysc.Bookings.Room.changeset(updated_params)

    {:noreply,
     socket
     |> assign(:selected_room_image, image)
     |> assign(:show_image_gallery, false)
     |> assign(:room_form, to_form(changeset, as: "room"))}
  end

  def handle_event("clear-room-image", _params, socket) do
    # Update the form changeset to clear the image_id
    current_params = socket.assigns.room_form.source.params || %{}
    updated_params = Map.put(current_params, "image_id", nil)

    changeset =
      (socket.assigns.room || %Ysc.Bookings.Room{})
      |> Ysc.Bookings.Room.changeset(updated_params)

    {:noreply,
     socket
     |> assign(:selected_room_image, nil)
     |> assign(:room_form, to_form(changeset, as: "room"))}
  end

  def handle_event("next-image-gallery-page", _params, socket) do
    alias Ysc.Media

    next_page = socket.assigns.image_gallery_page + 1
    per_page = 20
    images = Media.list_images((next_page - 1) * per_page, per_page)

    {:noreply,
     socket
     |> assign(:image_gallery, images)
     |> assign(:image_gallery_page, next_page)
     |> assign(:image_gallery_end?, length(images) < per_page)}
  end

  def handle_event("prev-image-gallery-page", _params, socket) do
    alias Ysc.Media

    prev_page = max(1, socket.assigns.image_gallery_page - 1)
    per_page = 20
    images = Media.list_images((prev_page - 1) * per_page, per_page)

    {:noreply,
     socket
     |> assign(:image_gallery, images)
     |> assign(:image_gallery_page, prev_page)
     |> assign(:image_gallery_end?, length(images) < per_page)}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
  end

  defp maybe_convert_atom(params, key) do
    if value = params[key] do
      try do
        atom_value = String.to_existing_atom(value)
        Map.put(params, key, atom_value)
      rescue
        ArgumentError -> params
      end
    else
      params
    end
  end

  defp assign_filtered_data(
         socket,
         property,
         seasons,
         pricing_rules,
         refund_policies
       ) do
    filtered_seasons =
      Enum.filter(seasons, fn season -> season.property == property end)

    filtered_pricing_rules =
      Enum.filter(pricing_rules, fn rule -> rule.property == property end)

    filtered_refund_policies =
      Enum.filter(refund_policies, fn policy -> policy.property == property end)

    # Filter rooms by property (rooms are already loaded in socket.assigns.rooms)
    filtered_rooms =
      if socket.assigns[:rooms] do
        Enum.filter(socket.assigns.rooms, fn room ->
          room.property == property
        end)
      else
        []
      end

    socket
    |> assign(:filtered_seasons, filtered_seasons)
    |> assign(:filtered_pricing_rules, filtered_pricing_rules)
    |> assign(:filtered_refund_policies, filtered_refund_policies)
    |> assign(:filtered_rooms, filtered_rooms)
  end

  defp season_options(seasons) do
    Enum.map(seasons, fn season ->
      {season.name, season.id}
    end)
  end

  defp room_category_options(categories) do
    Enum.map(categories, fn category ->
      {atom_to_readable(category.name), category.id}
    end)
  end

  defp room_options(rooms, property) do
    rooms
    |> Enum.filter(fn room -> room.property == property end)
    |> Enum.map(fn room ->
      {room.name, room.id}
    end)
  end

  defp format_money_for_input(nil), do: ""

  defp format_money_for_input(%Money{} = money),
    do: MoneyHelper.format_money!(money)

  defp format_money_for_input(_), do: ""

  defp format_season_dates(start_date, end_date) do
    start_str = "#{month_name(start_date.month)} #{start_date.day}"
    end_str = "#{month_name(end_date.month)} #{end_date.day}"

    # If it spans years, show both years
    if start_date.month > end_date.month do
      "#{start_str} - #{end_str} (recurring)"
    else
      "#{start_str} - #{end_str} (recurring)"
    end
  end

  defp month_name(month) do
    case month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end
  end

  defp format_price_unit(unit) do
    case unit do
      :per_person_per_night -> "Per person/night"
      :per_guest_per_day -> "Per guest/day"
      :buyout_fixed -> "Buyout fixed"
      _ -> "#{unit}"
    end
  end

  defp format_specificity(rule) do
    cond do
      rule.room_id && rule.room ->
        "Room: #{rule.room.name}"

      rule.room_category_id && rule.room_category ->
        "Category: #{atom_to_readable(rule.room_category.name)}"

      rule.property && rule.property != nil ->
        "Property: #{atom_to_readable(rule.property)}"

      true ->
        "General"
    end
  end

  defp format_price(%Money{} = money) do
    formatted = MoneyHelper.format_money!(money)
    "#{formatted}"
  end

  defp format_price(_), do: "$0.00"

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

  defp format_datetime(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y at %I:%M %p")
  end

  defp format_datetime(nil, _timezone), do: "—"
  defp format_datetime(_, _timezone), do: "—"

  # Helper to check if today is within a date range (for cells with colspan > 1)
  # Calculate day index in calendar (0-based)
  defp day_index(start_date, date) do
    Date.diff(date, start_date)
  end

  # Calculate grid column start and end for a booking
  # Each day has 2 columns (half-columns)
  # CSS Grid columns are 1-indexed
  # Day 0: columns 1-2, Day 1: columns 3-4, etc.
  # Bookings start on second half of check-in day, end on first half of check-out day
  # Returns {col_start, col_end, extends_before, extends_after}
  defp get_booking_grid_columns(
         start_date,
         checkin_date,
         checkout_date,
         total_days
       ) do
    total_cols = total_days * 2

    # Calculate actual day indices (not clamped)
    actual_checkin_idx = day_index(start_date, checkin_date)
    actual_checkout_idx = day_index(start_date, checkout_date)

    # Check if booking extends beyond visible range
    extends_before = actual_checkin_idx < 0
    extends_after = actual_checkout_idx >= total_days

    # Clamp indices to visible range
    checkin_idx = max(0, min(actual_checkin_idx, total_days - 1))
    checkout_idx = max(0, min(actual_checkout_idx, total_days - 1))

    # Each day has 2 columns: (day_idx * 2 + 1) and (day_idx * 2 + 2)
    # For a booking from Nov 6 (day 5) to Nov 7 (day 6):
    # - Day 5 spans columns 11-12 (day_idx * 2 + 1 to day_idx * 2 + 2)
    # - Day 6 spans columns 13-14
    # - Booking starts on second half of check-in day = column 12
    # - Booking ends on first half of checkout day = column 13
    # - So we want: col_start = 12, col_end = 14 (exclusive, so spans 12-13)
    # Second half of check-in day
    col_start = checkin_idx * 2 + 2
    # Just after first half of checkout day
    col_end = checkout_idx * 2 + 2

    # Ensure col_end doesn't exceed total columns
    col_end = min(col_end, total_cols + 1)

    {col_start, col_end, extends_before, extends_after}
  end

  # Check if a column index corresponds to today's date
  defp today_col?(col_idx, calendar_dates, today) do
    # Column index is 0-based, convert to day index (divide by 2, floor)
    day_idx = div(col_idx, 2)

    case Enum.at(calendar_dates, day_idx) do
      nil -> false
      date -> Date.compare(date, today) == :eq
    end
  end

  # Format user name for display
  defp format_user_name(nil), do: "Unknown User"

  defp format_user_name(user) do
    cond do
      user.first_name && user.last_name ->
        "#{user.first_name} #{user.last_name}"

      user.email ->
        user.email

      true ->
        "Unknown User"
    end
  end

  # Render a blackout div for the grid calendar
  # Blackouts cover full days (unlike bookings which have half-day coverage on check-in/check-out)
  # sobelow_skip ["XSS.Raw"]
  defp render_blackout_div(blackout, start_date, total_days) do
    total_cols = total_days * 2

    # Calculate actual day indices (not clamped) to detect if blackout extends beyond view
    actual_start_idx = day_index(start_date, blackout.start_date)
    actual_end_idx = day_index(start_date, blackout.end_date)

    # Check if blackout extends beyond visible range
    extends_before = actual_start_idx < 0
    extends_after = actual_end_idx >= total_days

    # Clamp indices to visible range for rendering
    start_idx = max(0, min(actual_start_idx, total_days - 1))
    end_idx = max(0, min(actual_end_idx, total_days - 1))

    # Blackouts cover full days: from first column of start day to last column of end day
    # Each day has 2 columns: (day_idx * 2 + 1) and (day_idx * 2 + 2)
    col_start = start_idx * 2 + 1
    # +3 to include the full last day (end_idx * 2 + 2 + 1)
    col_end = end_idx * 2 + 3
    # Clamp to grid bounds
    col_end = min(col_end, total_cols + 1)

    # Use CSS Grid positioning exactly like bookings to ensure proper alignment
    style_val =
      "grid-column: #{col_start} / #{col_end}; grid-row: 1; margin-left: 1px; margin-right: 1px; position: relative; z-index: 5;"

    title_val =
      "Blackout: #{blackout.reason} • #{blackout.start_date} → #{blackout.end_date}"

    {:safe, escaped_reason_str} = Phoenix.HTML.html_escape(blackout.reason)
    {:safe, escaped_title_str} = Phoenix.HTML.html_escape(title_val)

    # Add fade effect if blackout extends beyond visible range
    fade_class =
      cond do
        extends_before && extends_after ->
          "bg-gradient-to-r from-transparent via-red-100 to-transparent"

        extends_before ->
          "bg-gradient-to-r from-transparent to-red-100"

        extends_after ->
          "bg-gradient-to-l from-transparent to-red-100"

        true ->
          ""
      end

    # Add arrow indicator if extends past view
    right_indicator =
      if extends_after do
        "<div class=\"absolute right-1 top-1/2 -translate-y-1/2 text-red-600 opacity-75\">
        <span class=\"hero-arrow-right w-3 h-3\"></span>
      </div>"
      else
        ""
      end

    """
    <div
      class="h-10 rounded shadow-sm border text-xs font-medium flex flex-col items-start justify-center bg-red-100 border-red-400/50 text-red-900 cursor-pointer hover:bg-red-200 transition-colors duration-200 relative #{fade_class}"
      style="#{style_val}"
      title="#{escaped_title_str}"
      phx-click="view-blackout"
      phx-value-blackout-id="#{blackout.id}"
    >
      <div class="truncate px-2 font-semibold">#{escaped_reason_str}</div>
      #{right_indicator}
    </div>
    """
    |> Phoenix.HTML.raw()
  end

  # Render a booking div for the grid calendar
  # sobelow_skip ["XSS.Raw"]
  defp render_booking_div(booking, start_date, total_days) do
    {col_start, col_end, extends_before, extends_after} =
      get_booking_grid_columns(
        start_date,
        booking.checkin_date,
        booking.checkout_date,
        total_days
      )

    user_name = format_user_name(booking.user)

    # Use CSS Grid positioning instead of percentage-based absolute positioning
    # This ensures the booking aligns correctly with the grid columns
    style_val =
      "grid-column: #{col_start} / #{col_end}; grid-row: 1; margin-left: 1px; margin-right: 1px; position: relative; z-index: 5;"

    title_val =
      "#{user_name} - #{booking.checkin_date} - #{booking.checkout_date} (#{booking.guests_count} guests)"

    checkin_str = Calendar.strftime(booking.checkin_date, "%m/%d")
    checkout_str = Calendar.strftime(booking.checkout_date, "%m/%d")
    {:safe, escaped_user_name_str} = Phoenix.HTML.html_escape(user_name)
    {:safe, escaped_title_str} = Phoenix.HTML.html_escape(title_val)
    {:safe, escaped_checkin_str} = Phoenix.HTML.html_escape(checkin_str)
    {:safe, escaped_checkout_str} = Phoenix.HTML.html_escape(checkout_str)

    # Determine if this is a buyout booking (no rooms or booking_mode is :buyout)
    has_rooms = Ecto.assoc_loaded?(booking.rooms) && booking.rooms != []
    is_buyout = !has_rooms || booking.booking_mode == :buyout

    # Use green colors for buyout bookings, blue for regular room bookings
    {bg_color, border_color, text_color, hover_color} =
      if is_buyout do
        {"bg-green-100", "border-green-400/50", "text-green-900",
         "hover:bg-green-200"}
      else
        {"bg-blue-100", "border-blue-400/50", "text-blue-900",
         "hover:bg-blue-200"}
      end

    # Add fade effect if booking extends beyond visible range
    fade_class =
      cond do
        extends_before && extends_after ->
          if is_buyout,
            do:
              "bg-gradient-to-r from-transparent via-green-100 to-transparent",
            else:
              "bg-gradient-to-r from-transparent via-blue-100 to-transparent"

        extends_before ->
          if is_buyout,
            do: "bg-gradient-to-r from-transparent to-green-100",
            else: "bg-gradient-to-r from-transparent to-blue-100"

        extends_after ->
          if is_buyout,
            do: "bg-gradient-to-l from-transparent to-green-100",
            else: "bg-gradient-to-l from-transparent to-blue-100"

        true ->
          ""
      end

    # Add arrow indicator if extends past view
    right_indicator =
      if extends_after do
        arrow_color = if is_buyout, do: "text-green-600", else: "text-blue-600"

        "<div class=\"absolute right-1 top-1/2 -translate-y-1/2 #{arrow_color} opacity-75\">
        <span class=\"hero-arrow-right w-3 h-3\"></span>
      </div>"
      else
        ""
      end

    # Add checkmark if checked in (to the right of the name)
    checked_in_indicator =
      if Ecto.assoc_loaded?(booking.check_ins) && booking.check_ins != [] do
        "<svg class=\"w-3.5 h-3.5 text-green-600 flex-shrink-0 mt-0.5\" fill=\"currentColor\" viewBox=\"0 0 20 20\">
          <path fill-rule=\"evenodd\" d=\"M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z\" clip-rule=\"evenodd\" />
        </svg>"
      else
        ""
      end

    """
    <div
      class="h-10 rounded shadow-sm border text-xs font-medium flex flex-col items-start justify-center #{bg_color} #{border_color} #{text_color} cursor-pointer #{hover_color} transition-colors duration-200 relative #{fade_class}"
      style="#{style_val}"
      title="#{escaped_title_str}"
      phx-click="view-booking"
      phx-value-booking-id="#{booking.id}"
    >
      <div class="truncate px-2 font-semibold flex items-center gap-1.5">
        <span class="truncate">#{escaped_user_name_str}</span>
        #{checked_in_indicator}
      </div>
      <div class="truncate px-2 text-[10px] opacity-90">#{escaped_checkin_str} - #{escaped_checkout_str}</div>
      #{right_indicator}
    </div>
    """
    |> Phoenix.HTML.raw()
  end

  defp update_calendar_view(socket, property) do
    rooms = socket.assigns.rooms
    start_date = socket.assigns.calendar_start_date
    end_date = socket.assigns.calendar_end_date

    filtered_rooms =
      Enum.filter(rooms, fn room ->
        room.property == property && room.is_active
      end)
      |> Enum.sort_by(& &1.name)

    calendar_dates = generate_calendar_dates(start_date, end_date)

    # Parallelize blackouts and bookings queries for better performance
    [filtered_blackouts, bookings_in_range] =
      Task.await_many(
        [
          Task.async(fn ->
            Bookings.list_blackouts(property, start_date, end_date)
          end),
          Task.async(fn ->
            Bookings.list_bookings(property, start_date, end_date,
              preload: [:rooms, :user, check_ins: :check_in_vehicles]
            )
          end)
        ],
        :infinity
      )

    # Filter out canceled and refunded bookings (only show active bookings on calendar)
    # Note: This filtering in memory is acceptable since we're already loading a filtered set
    # and need to process bookings anyway to separate room vs buyout bookings
    active_bookings =
      Enum.filter(bookings_in_range, fn booking ->
        booking.status != :canceled && booking.status != :refunded
      end)

    # Separate room bookings from buyout bookings
    # Room bookings have rooms associated, buyout bookings have no rooms
    room_bookings =
      Enum.filter(active_bookings, fn booking ->
        Ecto.assoc_loaded?(booking.rooms) && booking.rooms != []
      end)

    buyout_bookings =
      Enum.filter(active_bookings, fn booking ->
        !Ecto.assoc_loaded?(booking.rooms) || booking.rooms == []
      end)

    # Calculate daily availability for Clear Lake (per guest/day mode)
    daily_availability =
      if property == :clear_lake do
        Bookings.get_clear_lake_daily_availability(start_date, end_date)
      else
        %{}
      end

    socket
    |> assign(:filtered_rooms, filtered_rooms)
    |> assign(:calendar_dates, calendar_dates)
    |> assign(:room_bookings, room_bookings)
    |> assign(:buyout_bookings, buyout_bookings)
    |> assign(:filtered_blackouts, filtered_blackouts)
    |> assign(:calendar_start_date, start_date)
    |> assign(:daily_availability, daily_availability)
  end

  defp generate_calendar_dates(start_date, end_date) do
    Date.range(start_date, end_date)
    |> Enum.to_list()
  end

  # Default date range: today - 2 days to today + 2 weeks
  defp default_date_range do
    today = Date.utc_today()
    start_date = Date.add(today, -2)
    end_date = Date.add(today, 14)
    {start_date, end_date}
  end

  # Get date from column index (0-based)
  # Each day has 2 columns, so day_index = col_idx / 2
  defp get_date_from_col(col_idx, calendar_dates) do
    day_idx = div(col_idx, 2)
    Enum.at(calendar_dates, day_idx)
  end

  # Check if a date is in the selected range (for visual feedback)
  defp date_selection_in_range?(_date, start_date, _hover_end)
       when is_nil(start_date), do: false

  defp date_selection_in_range?(date, start_date, hover_end) do
    # Use hover_end if available (for ghost preview), otherwise show all dates after start
    end_date = hover_end || start_date

    if end_date do
      # Ensure we have valid dates to compare - swap if end is before start
      {actual_start, actual_end} =
        if Date.compare(end_date, start_date) == :lt do
          {end_date, start_date}
        else
          {start_date, end_date}
        end

      Date.compare(date, actual_start) != :lt &&
        Date.compare(date, actual_end) != :gt
    else
      false
    end
  end

  # Load reservations for the table
  defp load_reservations(socket, params) do
    # Extract search term from params
    search = params["search"]

    search_term =
      case search do
        %{"query" => query} when is_binary(query) -> query
        query when is_binary(query) -> query
        _ -> nil
      end

    # Extract date range filters from params
    filter_start_date =
      if params["filter"] && params["filter"]["filter_start_date"] do
        case Date.from_iso8601(params["filter"]["filter_start_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    filter_end_date =
      if params["filter"] && params["filter"]["filter_end_date"] do
        case Date.from_iso8601(params["filter"]["filter_end_date"]) do
          {:ok, date} -> date
          _ -> nil
        end
      else
        nil
      end

    # Add property filter to params
    params_with_property =
      params
      |> Map.put(
        "filter",
        (params["filter"] || %{})
        |> Map.put("property", Atom.to_string(socket.assigns.selected_property))
      )
      # Ensure default ordering by most recently booked first if no order is specified
      |> then(fn p ->
        order_by = p["order_by"] || p[:order_by]

        if order_by == nil || order_by == [] do
          Map.merge(p, %{
            "order_by" => ["inserted_at"],
            "order_directions" => ["desc"]
          })
        else
          p
        end
      end)

    case Bookings.list_paginated_bookings(params_with_property, search_term) do
      {:ok, {reservations, meta}} ->
        socket
        |> assign(:reservation_params, params)
        |> assign(:reservation_meta, meta)
        |> assign(:reservation_empty, no_results?(reservations))
        |> assign(:reservation_filter_start_date, filter_start_date)
        |> assign(:reservation_filter_end_date, filter_end_date)
        |> assign(:reservations_path, build_reservations_path(socket, params))
        |> stream(:reservations, reservations, reset: true)

      {:error, _meta} ->
        socket
        |> assign(:reservation_params, params)
        |> assign(:reservation_meta, nil)
        |> assign(:reservation_empty, true)
        |> assign(:reservation_filter_start_date, filter_start_date)
        |> assign(:reservation_filter_end_date, filter_end_date)
        |> assign(:reservations_path, build_reservations_path(socket, params))
    end
  end

  # Load pending refunds (filtered by selected property)
  defp load_pending_refunds(socket) do
    selected_property = socket.assigns.selected_property

    # Query pending refunds with property filter at DB level and preload all associations in one query
    pending_refunds =
      from(pr in Ysc.Bookings.PendingRefund,
        join: b in assoc(pr, :booking),
        where: pr.status == :pending,
        where: b.property == ^selected_property,
        order_by: [asc: pr.inserted_at],
        preload: [booking: [:user, rooms: :room_category], payment: :user]
      )
      |> Repo.all()

    socket
    |> assign(:pending_refunds, pending_refunds)
    |> assign(:pending_refunds_count, length(pending_refunds))
  end

  # Load pending refunds counts for each property (for tab badges)
  # Extract data loading for async execution
  defp load_property_pending_refunds_counts_data do
    from(pr in Ysc.Bookings.PendingRefund,
      join: b in assoc(pr, :booking),
      where: pr.status == :pending,
      group_by: b.property,
      select: {b.property, count(pr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Helper to format property name
  defp format_property_name(:tahoe), do: "Lake Tahoe Cabin"
  defp format_property_name(:clear_lake), do: "Clear Lake Cabin"
  defp format_property_name(_), do: "Cabin"

  # Build query params for reservations while preserving calendar params
  defp build_reservation_query_params(socket, reservation_params) do
    base_params = %{
      "property" => Atom.to_string(socket.assigns.selected_property),
      "section" => "reservations"
    }

    # Add calendar date range if available
    params_with_calendar =
      if socket.assigns[:calendar_start_date] &&
           socket.assigns[:calendar_end_date] do
        Map.merge(base_params, %{
          "from_date" => Date.to_string(socket.assigns.calendar_start_date),
          "to_date" => Date.to_string(socket.assigns.calendar_end_date)
        })
      else
        base_params
      end

    # Flatten nested maps before merging
    flattened_reservation_params = flatten_query_params(reservation_params)
    Map.merge(params_with_calendar, flattened_reservation_params)
  end

  # Build path for Flop table/pagination that preserves all query params
  # Accepts either complete params (already includes property, section, etc.) or just reservation params
  defp build_reservations_path(socket, params) do
    # Check if params already includes base keys (means it's already complete)
    has_base_keys =
      Map.has_key?(params, "property") || Map.has_key?(params, :property)

    final_params =
      if has_base_keys && params != %{} do
        # Params are already complete (from build_reservation_query_params)
        # Just ensure they're flattened if needed
        flatten_query_params(params)
      else
        # Build base params and merge with reservation params
        base_params = %{
          "property" => Atom.to_string(socket.assigns.selected_property),
          "section" => "reservations"
        }

        # Add calendar date range if available
        params_with_calendar =
          if socket.assigns[:calendar_start_date] &&
               socket.assigns[:calendar_end_date] do
            Map.merge(base_params, %{
              from_date: Date.to_string(socket.assigns.calendar_start_date),
              to_date: Date.to_string(socket.assigns.calendar_end_date)
            })
          else
            base_params
          end

        # Use params if provided, otherwise use socket assigns
        reservation_params =
          if params != %{},
            do: params,
            else: socket.assigns[:reservation_params] || %{}

        # Flatten nested maps before merging
        flattened_params = flatten_query_params(reservation_params)
        Map.merge(params_with_calendar, flattened_params)
      end

    ~p"/admin/bookings?#{URI.encode_query(final_params)}"
  end

  # Build query params for closing booking modal, preserving all state
  defp build_booking_modal_close_params(
         property,
         start_date,
         end_date,
         current_section,
         reservation_params
       ) do
    query_params = %{
      "property" => Atom.to_string(property),
      "from_date" => Date.to_string(start_date),
      "to_date" => Date.to_string(end_date)
    }

    query_params =
      cond do
        current_section == :reservations ->
          Map.put(query_params, "section", "reservations")

        current_section == :config ->
          Map.put(query_params, "section", "config")

        current_section == :pending_refunds ->
          Map.put(query_params, "section", "pending_refunds")

        true ->
          query_params
      end

    # Preserve search and filter parameters from reservation_params if on reservations tab
    query_params =
      if current_section == :reservations && reservation_params do
        preserve_reservation_params(query_params, reservation_params)
      else
        query_params
      end

    query_params
  end

  # Flatten nested maps for URI encoding
  # Converts %{"search" => %{"query" => "test"}} to %{"search[query]" => "test"}
  # Filters out list values that have indexed equivalents (e.g., order_by list when order_by[0] exists)
  defp flatten_query_params(params, prefix \\ "")

  defp flatten_query_params(params, prefix) when is_map(params) do
    # First, filter out list values that have indexed equivalents
    filtered_params =
      Enum.reduce(params, %{}, fn {key, value}, acc ->
        # If value is a list and we have indexed keys for it, skip the list version
        if is_list(value) do
          has_indexed_keys =
            Enum.any?(params, fn {k, _v} ->
              is_binary(k) && String.starts_with?(k, "#{key}[") &&
                String.contains?(k, "]")
            end)

          if has_indexed_keys do
            # Skip the list, keep indexed versions
            acc
          else
            Map.put(acc, key, value)
          end
        else
          Map.put(acc, key, value)
        end
      end)

    Enum.reduce(filtered_params, %{}, fn {key, value}, acc ->
      flat_key = if prefix == "", do: key, else: "#{prefix}[#{key}]"

      flattened =
        cond do
          is_map(value) ->
            flatten_query_params(value, flat_key)

          is_list(value) ->
            # Handle lists - convert to indexed keys
            value
            |> Enum.with_index()
            |> Enum.reduce(%{}, fn {item, idx}, list_acc ->
              item_key = "#{flat_key}[#{idx}]"

              if is_map(item) do
                Map.merge(list_acc, flatten_query_params(item, item_key))
              else
                Map.put(list_acc, item_key, to_string(item))
              end
            end)

          true ->
            # Convert atoms to strings and ensure values are strings
            string_value =
              cond do
                is_atom(value) -> Atom.to_string(value)
                is_binary(value) -> value
                true -> to_string(value)
              end

            %{flat_key => string_value}
        end

      Map.merge(acc, flattened)
    end)
  end

  defp flatten_query_params(params, _prefix), do: params

  # Get all payments related to a booking via ledger entries
  defp get_booking_payments(booking_id) do
    from(p in Payment,
      join: e in Ysc.Ledgers.LedgerEntry,
      on: e.payment_id == p.id,
      where: e.related_entity_type == ^:booking,
      where: e.related_entity_id == ^booking_id,
      preload: [:user, :payment_method],
      order_by: [desc: p.payment_date],
      distinct: true
    )
    |> Repo.all()
  end

  # Get all refunds related to a booking via the payment's ledger entries
  defp get_booking_refunds(booking_id) do
    # First get the payment IDs for this booking
    payment_ids =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking_id,
        where: not is_nil(e.payment_id),
        select: e.payment_id,
        distinct: true
      )
      |> Repo.all()

    # Then get refunds for those payments
    if Enum.empty?(payment_ids) do
      []
    else
      from(r in Refund,
        where: r.payment_id in ^payment_ids,
        preload: [:payment, :user],
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
    end
  end

  # Check if there are no results
  defp no_results?([]), do: true
  defp no_results?(_), do: false

  defp validate_amount_format(changeset) do
    case Ecto.Changeset.get_change(changeset, :amount) do
      nil ->
        changeset

      amount_string ->
        case MoneyHelper.parse_money(amount_string) do
          nil ->
            Ecto.Changeset.add_error(
              changeset,
              :amount,
              "Invalid amount format"
            )

          _money ->
            changeset
        end
    end
  end

  # Parse a date from string or Date
  defp parse_date(%Date{} = date), do: date

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  # Parse an integer from string or integer with a default
  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(_, default), do: default

  defp preserve_reservation_params(query_params, reservation_params) do
    query_params
    |> preserve_search_param(reservation_params)
    |> preserve_filter_params(reservation_params)
  end

  defp preserve_search_param(query_params, reservation_params) do
    if reservation_params["search"] do
      Map.put(query_params, "search", reservation_params["search"])
    else
      query_params
    end
  end

  defp preserve_filter_params(query_params, reservation_params) do
    if reservation_params["filter"] do
      filter_map = build_filter_map(reservation_params["filter"])

      if map_size(filter_map) > 0 do
        Map.put(query_params, "filter", filter_map)
      else
        query_params
      end
    else
      query_params
    end
  end

  defp build_filter_map(filter_params) do
    filter_map = %{}

    filter_map =
      if filter_params["filter_start_date"] do
        Map.put(
          filter_map,
          "filter_start_date",
          filter_params["filter_start_date"]
        )
      else
        filter_map
      end

    if filter_params["filter_end_date"] do
      Map.put(filter_map, "filter_end_date", filter_params["filter_end_date"])
    else
      filter_map
    end
  end
end
