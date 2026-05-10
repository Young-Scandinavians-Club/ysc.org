defmodule YscWeb.AdminUserDetailsLive do
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  alias Ysc.Accounts
  alias Ysc.Accounts.{FamilyInvites, MembershipCache}
  alias Ysc.Bookings
  alias Ysc.Bookings.Entitlements
  alias Ysc.ExpenseReports
  alias Ysc.Ledgers
  alias Ysc.Messages
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Tickets
  alias YscWeb.Workers.MembershipRenewalReminderWorker

  require Ysc.Logging

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex flex-col justify-between py-6">
        <.back navigate={~p"/admin/users?#{@list_params}"}>Back</.back>

        <div class="flex flex-row items-center justify-between pt-4">
          <.admin_page_title>
            {"#{Ysc.title_case(@first_name)} #{Ysc.title_case(@last_name)}"}
          </.admin_page_title>
          <form
            id="admin-impersonate-form"
            action={~p"/admin/impersonate/#{@user_id}"}
            method="post"
            class="inline-block m-0"
          >
            <input
              type="hidden"
              name="_csrf_token"
              value={Phoenix.Controller.get_csrf_token()}
            />
            <button
              type="submit"
              class="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors font-semibold"
            >
              <.icon name="hero-user-circle" class="w-5 h-5" /> Sign in as User
            </button>
          </form>
        </div>

        <div class="w-full py-4">
          <div class="h-24">
            <.user_avatar_image
              user={@selected_user}
              class="w-24 h-24 rounded-full"
            />
          </div>
        </div>

        <div class="pt-4">
          <div class="text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
            <ul class="flex flex-wrap -mb-px">
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details?#{@list_params}"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :profile &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :profile &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Profile
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/orders?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :orders &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :orders &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Tickets
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/bookings?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :bookings &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :bookings &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Bookings
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/application?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :application &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :application &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Application
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/membership?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :membership &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :membership &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Membership
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/notifications?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :notifications &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :notifications &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Notifications
                </.link>
              </li>
              <li :if={@is_treasurer} class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/bank-accounts?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :bank_accounts &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :bank_accounts &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Bank Accounts
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/family?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :family &&
                      "text-blue-600 border-blue-600 active",
                    @live_action != :family &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Family
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={
                    ~p"/admin/users/#{@user_id}/details/logs?#{@list_params}"
                  }
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :logs && "text-blue-600 border-blue-600 active",
                    @live_action != :logs &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Notes
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :profile} class="max-w-lg px-2 space-y-8">
          <.simple_form
            for={@form}
            id="user-profile-form"
            phx-change="validate"
            phx-submit="save"
            class="py-8"
          >
            <!-- Personal Information -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
                Personal Information
              </h3>
              <div class="relative">
                <.input field={@form[:email]} label="Email" />
                <%= if @selected_user.email_verified_at != nil do %>
                  <.icon
                    name="hero-check-circle"
                    class="absolute right-3 mt-[16px] top-1/2 -translate-y-1/2 h-5 w-5 text-green-500 pointer-events-none"
                  />
                <% end %>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <.input field={@form[:first_name]} label="First Name" />
                <.input field={@form[:last_name]} label="Last Name" />
              </div>
              <.input
                field={@form[:date_of_birth]}
                type="date"
                label="Date of Birth"
                max={@today_max}
              />
              <.input
                field={@form[:most_connected_country]}
                label="Most connected Nordic country:"
                type="select"
                options={[
                  Sweden: "SE",
                  Norway: "NO",
                  Finland: "FI",
                  Denmark: "DK",
                  Iceland: "IS"
                ]}
              />
            </div>
            <!-- Contact Information -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
                Contact Information
              </h3>
              <div class="relative">
                <.input
                  type="phone-input"
                  label="Phone Number"
                  id="phone_number"
                  value={@form[:phone_number].value}
                  field={@form[:phone_number]}
                />
                <%= if @selected_user.phone_verified_at != nil do %>
                  <.icon
                    name="hero-check-circle"
                    class="absolute right-3 mt-[16px] top-1/2 -translate-y-1/2 h-5 w-5 text-green-500 pointer-events-none"
                  />
                <% end %>
              </div>
              <p class="text-xs text-zinc-600 mt-1">
                By voluntarily providing your phone number and explicitly opting in to text messaging, you consent to receive SMS notifications from Young Scandinavians Club (YSC). Message and data rates may apply. Users can opt out in their notification settings. See our
                <.link
                  navigate={~p"/privacy-policy"}
                  class="text-blue-600 hover:underline"
                >
                  Privacy Policy
                </.link>
                for more information.
              </p>
            </div>
            <!-- Account Settings -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
                Account Settings
              </h3>
              <.input
                type="select"
                field={@form[:state]}
                options={[
                  Active: "active",
                  "Pending Approval": "pending_approval",
                  Rejected: "rejected",
                  Suspended: "suspended",
                  Deleted: "deleted"
                ]}
                label="Account Status"
              />
              <.input
                type="select"
                field={@form[:role]}
                options={[Member: "member", Admin: "admin", Volunteer: "volunteer"]}
                label="Role"
              />

              <.input
                :if={"#{@role}" == "admin"}
                type="select"
                field={@form[:board_position]}
                options={[
                  None: nil,
                  President: "president",
                  "Vice President": "vice_president",
                  Secretary: "secretary",
                  Treasurer: "treasurer",
                  "Clear Lake Cabin Master": "clear_lake_cabin_master",
                  "Tahoe Cabin Master": "tahoe_cabin_master",
                  "Event Director": "event_director",
                  "Member Outreach & Events": "member_outreach",
                  "Membership Director": "membership_director"
                ]}
                label="Board Position"
              />

              <.input
                :if={
                  "#{@role}" == "admin" &&
                    board_position_selected?(@form, @selected_user)
                }
                type="textarea"
                field={@form[:board_bio]}
                id="board_bio"
                label="Board bio"
                placeholder="Short biography shown on the public Board of Directors page."
              />
              <p
                :if={
                  "#{@role}" == "admin" &&
                    board_position_selected?(@form, @selected_user)
                }
                class="text-xs text-zinc-600 -mt-2"
              >
                This text is public on
                <.link navigate={~p"/board"} class="text-blue-600 hover:underline">
                  /board
                </.link>
                for members who hold a board position.
              </p>
            </div>
            <!-- Address Information -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-zinc-800 border-b border-zinc-200 pb-2">
                Address Information
              </h3>
              <.inputs_for :let={address_form} field={@form[:billing_address]}>
                <.input field={address_form[:address]} label="Address" />
                <div class="grid grid-cols-2 gap-4">
                  <.input field={address_form[:city]} label="City" />
                  <.input field={address_form[:region]} label="Region/State" />
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <.input field={address_form[:postal_code]} label="Postal Code" />
                  <.input field={address_form[:country]} label="Country" />
                </div>
              </.inputs_for>
            </div>

            <div class="flex flex-row justify-end w-full pt-8">
              <.button
                phx-disable-with="Saving..."
                type="submit"
                disabled={!form_has_changes?(@original_form_data, @form)}
                class={
                  if(!form_has_changes?(@original_form_data, @form),
                    do: "opacity-50 cursor-not-allowed",
                    else: ""
                  )
                }
              >
                <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" />Save changes
              </.button>
            </div>
          </.simple_form>
        </div>

        <div :if={@live_action == :orders} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Ticket Orders</h2>
          <div
            :if={@ticket_orders_meta == nil}
            class="text-zinc-400 text-sm py-8 text-center"
          >
            Loading...
          </div>
          <div :if={@ticket_orders_meta != nil} class="w-full">
            <Flop.Phoenix.table
              id="user_ticket_orders_list"
              items={@streams.ticket_orders}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
              row_click={
                fn {_id, order} ->
                  order.event_id &&
                    JS.navigate(~p"/admin/events/#{order.event_id}/tickets")
                end
              }
              opts={[tbody_tr_attrs: [class: "hover:bg-zinc-50 cursor-pointer"]]}
            >
              <:col :let={{_, order}} label="Order ID" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs">
                    {order.reference_id}
                  </span>
                </.badge>
              </:col>
              <:col :let={{_, order}} label="Event" field={:inserted_at}>
                <%= if order.event do %>
                  <div class="text-sm font-semibold text-zinc-800">
                    {order.event.title}
                  </div>
                  <%= if order.event.start_date do %>
                    <div class="text-xs text-zinc-500 mt-0.5">
                      {format_event_date(order.event.start_date)}
                    </div>
                  <% end %>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </:col>
              <:col :let={{_, order}} label="Tickets">
                <span class="text-sm text-zinc-600">
                  {length(order.tickets || [])} ticket(s)
                </span>
              </:col>
              <:col :let={{_, order}} label="Amount" field={:total_amount}>
                <span class="text-sm font-medium text-zinc-900">
                  {Ysc.MoneyHelper.format_money!(order.total_amount)}
                </span>
              </:col>
              <:col :let={{_, order}} label="Status" field={:status}>
                <%= case order.status do %>
                  <% :pending -> %>
                    <.badge type="yellow" class="whitespace-nowrap flex-shrink-0">
                      Pending
                    </.badge>
                  <% :completed -> %>
                    <.badge type="green" class="whitespace-nowrap flex-shrink-0">
                      Completed
                    </.badge>
                  <% :cancelled -> %>
                    <.badge type="red" class="whitespace-nowrap flex-shrink-0">
                      Cancelled
                    </.badge>
                  <% :expired -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">
                      Expired
                    </.badge>
                  <% _ -> %>
                    <.badge type="dark" class="whitespace-nowrap flex-shrink-0">
                      —
                    </.badge>
                <% end %>
              </:col>
              <:col :let={{_, order}} label="Order Date" field={:inserted_at}>
                <span class="text-sm text-zinc-600">
                  {format_utc_date(order.inserted_at)}
                </span>
              </:col>
            </Flop.Phoenix.table>

            <.admin_flop_pagination
              :if={@ticket_orders_meta}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
              density={:comfortable}
            />
          </div>
        </div>

        <div :if={@live_action == :bookings} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Bookings</h2>
          <div
            :if={@bookings_meta == nil}
            class="text-zinc-400 text-sm py-8 text-center"
          >
            Loading...
          </div>
          <div :if={@bookings_meta != nil} class="w-full">
            <Flop.Phoenix.table
              id="user_bookings_list"
              items={@streams.bookings}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
              row_click={
                fn {_id, booking} ->
                  JS.navigate(~p"/admin/bookings/#{booking.id}")
                end
              }
              opts={[tbody_tr_attrs: [class: "hover:bg-zinc-50 cursor-pointer"]]}
            >
              <:col :let={{_, booking}} label="Reference" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs flex-shrink-0 whitespace-nowrap">
                    {booking.reference_id}
                  </span>
                </.badge>
              </:col>
              <:col :let={{_, booking}} label="Property" field={:property}>
                <span class="text-sm text-zinc-800">
                  <%= case booking.property do %>
                    <% :tahoe -> %>
                      Lake Tahoe
                    <% :clear_lake -> %>
                      Clear Lake
                    <% _ -> %>
                      —
                  <% end %>
                </span>
              </:col>
              <:col :let={{_, booking}} label="Check-in" field={:checkin_date}>
                <span class="text-sm text-zinc-800">
                  {Calendar.strftime(booking.checkin_date, "%b %d, %Y")}
                </span>
              </:col>
              <:col :let={{_, booking}} label="Check-out" field={:checkout_date}>
                <span class="text-sm text-zinc-800">
                  {Calendar.strftime(booking.checkout_date, "%b %d, %Y")}
                </span>
              </:col>
              <:col :let={{_, booking}} label="Nights">
                <span class="text-sm text-zinc-600">
                  {Date.diff(booking.checkout_date, booking.checkin_date)}
                </span>
              </:col>
              <:col :let={{_, booking}} label="Guests" field={:guests_count}>
                <span class="text-sm text-zinc-600">
                  {booking.guests_count}
                </span>
              </:col>
              <:col :let={{_, booking}} label="Room" field={:booking_mode}>
                <%= if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do %>
                  <div class="space-y-1">
                    <%= for room <- booking.rooms do %>
                      <div>
                        <div class="text-sm font-medium text-zinc-800">
                          {room.name}
                        </div>
                        <%= if room.room_category do %>
                          <div class="text-xs text-zinc-500 mt-0.5">
                            {String.capitalize(to_string(room.room_category.name))}
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
              <:col :let={{_, booking}} label="Booked" field={:inserted_at}>
                <span class="text-sm text-zinc-600">
                  {format_utc_date(booking.inserted_at)}
                </span>
              </:col>
            </Flop.Phoenix.table>

            <.admin_flop_pagination
              :if={@bookings_meta}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
              density={:comfortable}
            />
          </div>

          <div class="mt-12 pt-10 border-t border-zinc-200 max-w-4xl space-y-8">
            <div>
              <h2 class="text-xl font-semibold text-zinc-800">
                Cabin booking benefits
              </h2>
              <p class="text-sm text-zinc-500 mt-1">
                Grants apply automatically when this member books an eligible stay (
                <.link
                  navigate={~p"/admin/bookings/entitlements"}
                  class="text-blue-600 hover:underline"
                >
                  view all outstanding
                </.link>
                ).
              </p>
            </div>

            <div class="rounded-lg border border-zinc-200 p-4 bg-white">
              <h3 class="text-sm font-semibold text-zinc-800 mb-3">
                Grant new benefit
              </h3>
              <.form
                for={@entitlement_form}
                id="grant-entitlement-form"
                phx-submit="grant_booking_entitlement"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input
                    field={@entitlement_form[:benefit_kind]}
                    type="select"
                    label="Benefit type"
                    options={[
                      {"Percent off stay", "percent_off"},
                      {"Free nights (proportional)", "free_nights"},
                      {"Fixed amount off", "fixed_amount_off"}
                    ]}
                  />
                  <.input
                    field={@entitlement_form[:property]}
                    type="select"
                    label="Property"
                    options={[
                      {"Any property", ""},
                      {"Lake Tahoe", "tahoe"},
                      {"Clear Lake", "clear_lake"}
                    ]}
                  />
                  <.input
                    field={@entitlement_form[:max_guests]}
                    type="number"
                    label="Max guests (optional)"
                  />
                  <.input
                    field={@entitlement_form[:free_nights]}
                    type="number"
                    label="Free nights count"
                  />
                  <.input
                    field={@entitlement_form[:percent_off]}
                    type="text"
                    label="Percent off (e.g. 50)"
                  />
                  <.input
                    field={@entitlement_form[:buyout_max_discount]}
                    type="text"
                    label="Buyout max discount (USD)"
                  />
                  <.input
                    field={@entitlement_form[:amount_off]}
                    type="text"
                    label="Fixed amount off (USD)"
                  />
                  <.input
                    field={@entitlement_form[:expires_on]}
                    type="date"
                    label="Expires (optional)"
                  />
                </div>
                <.input
                  field={@entitlement_form[:internal_note]}
                  type="textarea"
                  label="Internal note (optional)"
                  class="mt-3 w-full min-h-[4rem] border border-zinc-300 rounded-md px-3 py-2 text-sm"
                />
                <button
                  type="submit"
                  id="grant-entitlement-submit"
                  phx-disable-with="Granting..."
                  class="mt-4 px-4 py-2 bg-blue-600 text-white rounded font-semibold text-sm hover:bg-blue-700"
                >
                  Grant benefit & email member
                </button>
              </.form>
            </div>

            <div class="overflow-x-auto rounded-lg border border-zinc-200">
              <table class="min-w-full text-sm">
                <thead class="bg-zinc-50 text-left text-xs font-semibold text-zinc-600 uppercase">
                  <tr>
                    <th class="px-4 py-3">Status</th>
                    <th class="px-4 py-3">Benefit</th>
                    <th class="px-4 py-3">Property</th>
                    <th class="px-4 py-3">Created</th>
                    <th class="px-4 py-3">Expires</th>
                    <th class="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-100">
                  <tr :for={ent <- @booking_entitlements} class="hover:bg-zinc-50">
                    <td class="px-4 py-3">
                      <span class="font-medium text-zinc-800">
                        {format_entitlement_status(ent.status)}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-zinc-700">
                      {admin_entitlement_summary(ent)}
                    </td>
                    <td class="px-4 py-3 text-zinc-600">
                      <%= cond do %>
                        <% is_nil(ent.property) -> %>
                          Any
                        <% ent.property == :tahoe -> %>
                          Tahoe
                        <% true -> %>
                          Clear Lake
                      <% end %>
                    </td>
                    <td class="px-4 py-3 text-zinc-600 tabular-nums">
                      {Calendar.strftime(ent.inserted_at, "%Y-%m-%d")}
                    </td>
                    <td class="px-4 py-3 text-zinc-600 tabular-nums">
                      <%= if ent.expires_at do %>
                        {Date.to_iso8601(DateTime.to_date(ent.expires_at))}
                      <% else %>
                        —
                      <% end %>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <button
                        :if={ent.status == :active}
                        type="button"
                        phx-click="revoke_booking_entitlement"
                        phx-value-id={ent.id}
                        class="text-red-600 hover:underline text-xs font-semibold"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
              <p
                :if={@booking_entitlements == []}
                class="px-4 py-6 text-center text-zinc-500 text-sm"
              >
                No entitlements yet for this member.
              </p>
            </div>
          </div>
        </div>

        <div :if={@live_action == :application} class="max-w-2xl py-8 px-2">
          <div :if={@selected_user_application == nil}>
            <p class="text-sm text-zinc-800">No application found</p>
          </div>

          <div :if={@selected_user_application != nil} class="space-y-6">
            <div class="flex items-center justify-between border-b border-zinc-200 pb-4 mb-6 gap-4">
              <div class="min-w-0">
                <.admin_page_title level={2} variant={:emphasis}>
                  Application
                </.admin_page_title>
                <p class="text-sm text-zinc-500 mt-0.5">
                  <%= if @selected_user.state == :pending_approval do %>
                    Submitted {if @selected_user_application.completed,
                      do: Timex.from_now(@selected_user_application.completed),
                      else: "N/A"}
                  <% else %>
                    <%= if @selected_user_application.reviewed_at do %>
                      Reviewed {format_utc_date(
                        @selected_user_application.reviewed_at
                      )} by {if @selected_user_application.reviewed_by,
                        do: @selected_user_application.reviewed_by.email,
                        else: "—"}
                    <% else %>
                      Submitted {if @selected_user_application.completed,
                        do: Timex.from_now(@selected_user_application.completed),
                        else: "N/A"}
                    <% end %>
                  <% end %>
                </p>
              </div>
              <span :if={@selected_user.state == :pending_approval} class="shrink-0">
                <.badge type="default">Pending Review</.badge>
              </span>
              <span
                :if={
                  @selected_user.state != :pending_approval &&
                    @selected_user_application.review_outcome != nil
                }
                class="shrink-0"
              >
                <.badge type={
                  review_outcome_to_badge_type(
                    @selected_user_application.review_outcome
                  )
                }>
                  {@selected_user_application.review_outcome}
                </.badge>
              </span>
            </div>

            <%!-- Override banner: shown when rejection was overridden and user is now active --%>
            <div
              :if={
                @selected_user_application.review_outcome == :rejected &&
                  @selected_user.state == :active
              }
              id="admin-application-rejection-override-banner"
              class="flex items-start gap-3 rounded-lg bg-amber-50 border border-amber-200 p-4"
            >
              <.icon
                name="hero-exclamation-triangle"
                class="w-5 h-5 text-amber-600 shrink-0 mt-0.5"
              />
              <div>
                <p class="text-sm font-semibold text-amber-800">
                  Rejection overridden
                </p>
                <p class="text-sm text-amber-700 mt-0.5">
                  This application was rejected but an admin has overridden the decision and activated the account. See the override note at the bottom of this page.
                </p>
              </div>
            </div>

            <section>
              <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-400 mb-3">
                Applicant Details
              </h3>
              <dl class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
                <div class="py-2">
                  <dt class="text-sm font-semibold text-zinc-600">Full Name</dt>
                  <dd class="mt-0.5 text-sm text-zinc-900">
                    {"#{@selected_user.first_name} #{@selected_user.last_name}"}
                  </dd>
                </div>
                <div class="py-2">
                  <dt class="text-sm font-semibold text-zinc-600">Email</dt>
                  <dd class="mt-0.5 text-sm text-zinc-900 underline decoration-zinc-200">
                    {@selected_user.email}
                  </dd>
                </div>
                <div class="py-2">
                  <dt class="text-sm font-semibold text-zinc-600">Birth Date</dt>
                  <dd class="mt-0.5 text-sm text-zinc-900">
                    {format_birth_date(@selected_user_application.birth_date)}
                  </dd>
                </div>
                <div
                  :if={length(@selected_user.family_members) > 0}
                  class="py-2 sm:col-span-2"
                >
                  <dt class="text-sm font-semibold text-zinc-600">
                    Family members
                  </dt>
                  <dd class="mt-1 text-sm text-zinc-900">
                    <ul class="space-y-1 list-disc list-inside">
                      <li :for={family_member <- @selected_user.family_members}>
                        <span class="text-xs font-medium me-2 px-2.5 py-1 rounded bg-blue-100 text-blue-800">
                          {String.capitalize("#{family_member.type}")}
                        </span>
                        {"#{family_member.first_name} #{family_member.last_name} (#{format_birth_date(family_member.birth_date)})"}
                      </li>
                    </ul>
                  </dd>
                </div>
              </dl>
            </section>

            <section>
              <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-400 mb-3">
                Answers
              </h3>
              <div class="space-y-4">
                <div class="py-2">
                  <p class="text-sm font-semibold text-zinc-600 mb-1.5">
                    Membership type
                  </p>
                  <.badge type={
                    if to_string(@selected_user_application.membership_type) ==
                         "family", do: "green", else: "default"
                  }>
                    {String.capitalize(
                      "#{@selected_user_application.membership_type}"
                    )}
                  </.badge>
                </div>
                <div class="bg-zinc-50 rounded-lg p-4 ring-1 ring-zinc-200/50">
                  <p class="text-sm font-semibold text-zinc-700 mb-2">
                    Eligibility & Connections
                  </p>
                  <ul class="text-sm space-y-1 list-disc list-inside text-zinc-600">
                    <li :for={
                      reason <- @selected_user_application.membership_eligibility
                    }>
                      {Map.get(
                        Ysc.Accounts.SignupApplication.eligibility_lookup(),
                        reason
                      )}
                    </li>
                  </ul>
                </div>

                <dl class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
                  <div class="py-2">
                    <dt class="text-sm font-semibold text-zinc-600">Occupation</dt>
                    <dd class="mt-0.5 text-sm text-zinc-900">
                      {@selected_user_application.occupation}
                    </dd>
                  </div>
                  <div class="py-2">
                    <dt class="text-sm font-semibold text-zinc-600">
                      Place of birth
                    </dt>
                    <dd class="mt-0.5 text-sm text-zinc-900 flex items-center gap-2">
                      <span
                        :if={
                          country_to_flag_class(
                            @selected_user_application.place_of_birth
                          )
                        }
                        class="shrink-0"
                      >
                        <.flag
                          country={
                            country_to_flag_class(
                              @selected_user_application.place_of_birth
                            )
                          }
                          class="h-4 w-6 rounded inline-block align-middle"
                        />
                      </span>
                      {nordic_country_display_name(
                        @selected_user_application.place_of_birth
                      ) || @selected_user_application.place_of_birth}
                    </dd>
                  </div>
                  <div class="py-2">
                    <dt class="text-sm font-semibold text-zinc-600">Citizenship</dt>
                    <dd class="mt-0.5 text-sm text-zinc-900 flex items-center gap-2">
                      <span
                        :if={
                          country_to_flag_class(
                            @selected_user_application.citizenship
                          )
                        }
                        class="shrink-0"
                      >
                        <.flag
                          country={
                            country_to_flag_class(
                              @selected_user_application.citizenship
                            )
                          }
                          class="h-4 w-6 rounded inline-block align-middle"
                        />
                      </span>
                      {nordic_country_display_name(
                        @selected_user_application.citizenship
                      ) || @selected_user_application.citizenship}
                    </dd>
                  </div>
                  <div class="py-2">
                    <dt class="text-sm font-semibold text-zinc-600">
                      Most connected Nordic country
                    </dt>
                    <dd class="mt-0.5 text-sm text-zinc-900 flex items-center gap-2">
                      <span
                        :if={
                          country_to_flag_class(
                            @selected_user_application.most_connected_nordic_country
                          )
                        }
                        class="shrink-0"
                      >
                        <.flag
                          country={
                            country_to_flag_class(
                              @selected_user_application.most_connected_nordic_country
                            )
                          }
                          class="h-4 w-6 rounded inline-block align-middle"
                        />
                      </span>
                      {nordic_country_display_name(
                        @selected_user_application.most_connected_nordic_country
                      )}
                    </dd>
                  </div>
                </dl>

                <div class="pt-1">
                  <p class="text-sm font-semibold text-zinc-600 mb-1">
                    Link to Scandinavia
                  </p>
                  <div class="mt-1 p-3 bg-white border border-zinc-200 rounded-md text-sm text-zinc-800 italic min-h-[2.5rem]">
                    {@selected_user_application.link_to_scandinavia}
                  </div>
                </div>
                <div class="pt-1">
                  <p class="text-sm font-semibold text-zinc-600 mb-1">
                    Lived in Scandinavia
                  </p>
                  <div class="mt-1 p-3 bg-white border border-zinc-200 rounded-md text-sm text-zinc-800 italic min-h-[2.5rem]">
                    {@selected_user_application.lived_in_scandinavia}
                  </div>
                </div>
                <div class="pt-1">
                  <p class="text-sm font-semibold text-zinc-600 mb-1">
                    Spoken languages
                  </p>
                  <div class="mt-1 p-3 bg-white border border-zinc-200 rounded-md text-sm text-zinc-800 italic min-h-[2.5rem]">
                    {@selected_user_application.spoken_languages}
                  </div>
                </div>
                <div class="pt-1">
                  <p class="text-sm font-semibold text-zinc-600 mb-1">
                    How did you hear about the club?
                  </p>
                  <div class="mt-1 p-3 bg-white border border-zinc-200 rounded-md text-sm text-zinc-800 italic min-h-[2.5rem]">
                    {@selected_user_application.hear_about_the_club}
                  </div>
                </div>
              </div>
            </section>

            <section
              :if={length(@rejection_notes) > 0}
              id="admin-application-rejection-notes"
              class="pt-6 border-t border-zinc-200"
            >
              <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-400 mb-3">
                Rejection notes
              </h3>
              <div class="space-y-4">
                <div
                  :for={note <- @rejection_notes}
                  class="bg-red-50/50 rounded-lg p-4 border border-red-100"
                >
                  <div class="flex items-start justify-between gap-4 mb-2">
                    <p class="text-sm font-semibold text-zinc-900">
                      <%= if note.created_by do %>
                        {"#{note.created_by.first_name} #{note.created_by.last_name}"}
                      <% else %>
                        Unknown reviewer
                      <% end %>
                    </p>
                    <p class="text-xs text-zinc-500 shrink-0">
                      {format_datetime_for_display(note.inserted_at)}
                    </p>
                  </div>
                  <p
                    class="text-sm text-zinc-800 whitespace-pre-wrap"
                    data-testid="rejection-note-text"
                  >
                    {note.note}
                  </p>
                </div>
              </div>
            </section>
          </div>
        </div>

        <div :if={@live_action == :membership} class="max-w-lg py-8 px-2">
          <div class="space-y-6">
            <%!-- Board volunteer billing pause notice --%>
            <.board_pause_notice
              :if={@membership_paused_by_board != nil}
              board_member={@membership_paused_by_board}
              current_user={@current_user}
            />

            <%!-- Sub-account: membership via primary user --%>
            <div
              :if={@primary_user != nil}
              class="border border-zinc-200 rounded-lg p-6"
            >
              <h3 class="text-lg font-semibold text-zinc-800 mb-1">
                Membership via Primary Account
              </h3>
              <p class="text-sm text-zinc-500 mb-4">
                This user shares membership benefits through their primary account holder's plan.
              </p>
              <div class="flex items-center gap-4 p-4 bg-zinc-50 rounded-lg">
                <.user_avatar_image
                  user={@primary_user}
                  class="w-10 h-10 rounded-full"
                />
                <div class="flex-1">
                  <div class="font-semibold text-zinc-900">
                    {@primary_user.first_name} {@primary_user.last_name}
                  </div>
                  <div class="text-sm text-zinc-600">{@primary_user.email}</div>
                  <%= if @selected_user.family_relationship do %>
                    <.badge type="sky" class="mt-1 text-xs">
                      {format_family_relationship(
                        @selected_user.family_relationship
                      )}
                    </.badge>
                  <% end %>
                </div>
                <.link
                  navigate={~p"/admin/users/#{@primary_user.id}/details/membership"}
                  class="text-sm text-blue-600 hover:underline shrink-0"
                >
                  View membership
                </.link>
              </div>
            </div>

            <div
              :if={@has_lifetime_membership}
              class="bg-blue-50 border border-blue-200 rounded-lg p-4"
            >
              <h3 class="text-lg font-semibold text-blue-900 mb-3">
                Lifetime Membership
              </h3>
              <div class="space-y-2 text-sm text-blue-800">
                <p>
                  <span class="font-semibold">Status:</span>
                  <.badge class="bg-blue-600 text-white">
                    Active - Never Expires
                  </.badge>
                </p>
                <p>
                  <span class="font-semibold">Awarded on:</span>
                  {if @selected_user.lifetime_membership_awarded_at do
                    format_datetime_for_display(
                      @selected_user.lifetime_membership_awarded_at
                    )
                  else
                    "N/A"
                  end}
                </p>
                <p class="text-xs text-blue-700 pt-2">
                  Lifetime membership provides all Family membership perks and never expires.
                </p>
              </div>
            </div>

            <div
              :if={
                @active_subscription == nil && !@has_lifetime_membership &&
                  @primary_user == nil
              }
              class="space-y-4"
            >
              <div class="bg-zinc-50 border border-zinc-200 rounded-lg p-4">
                <p class="text-sm text-zinc-800">
                  No active membership subscription found
                </p>
                <p class="text-xs text-zinc-600 mt-2">
                  Create a subscription paid elsewhere (e.g. cash) or award lifetime membership below.
                </p>
              </div>
              <div class="border border-zinc-200 rounded-lg p-4 bg-white">
                <h3 class="text-lg font-semibold text-zinc-800 mb-2">
                  Create membership (paid elsewhere)
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Creates a membership subscription in Stripe and marks the first invoice as paid (e.g. cash, check).
                  The user will have an active membership for one billing period.
                </p>
                <.simple_form
                  for={@create_paid_membership_form}
                  id="create-paid-membership-form"
                  phx-change="validate_create_paid_membership"
                  phx-submit="create_paid_membership"
                >
                  <.input
                    field={@create_paid_membership_form[:plan_id]}
                    type="select"
                    label="Membership plan"
                    options={get_membership_type_options_for_create()}
                  />
                  <div class="flex flex-row justify-end w-full pt-4">
                    <.button phx-disable-with="Creating..." type="submit">
                      <.icon name="hero-banknotes" class="w-5 h-5 mb-0.5 me-1" />
                      Create membership (paid elsewhere)
                    </.button>
                  </div>
                </.simple_form>
              </div>
            </div>

            <div :if={@active_subscription != nil} class="space-y-6">
              <%= if @scheduled_downgrade_info do %>
                <div class="bg-amber-50 border border-amber-200 rounded-md p-4">
                  <div class="flex">
                    <div class="flex-shrink-0">
                      <.icon
                        name="hero-arrow-trending-down"
                        class="h-5 w-5 text-amber-500"
                      />
                    </div>
                    <div class="ml-3">
                      <h3 class="text-sm font-medium text-amber-800">
                        Downgrade Scheduled
                      </h3>
                      <p class="mt-1 text-sm text-amber-700">
                        This user's membership will change to
                        <strong>
                          {String.capitalize(
                            to_string(@scheduled_downgrade_info.target_plan)
                          )}
                        </strong>
                        on <strong><%= format_utc_date_long(@scheduled_downgrade_info.effective_date) %></strong>.
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>

              <div>
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                  Current Membership
                </h3>
                <div class="space-y-2 text-sm text-zinc-800">
                  <p>
                    <span class="font-semibold">Plan:</span>
                    {get_membership_plan_name(@active_subscription)}
                  </p>
                  <p>
                    <span class="font-semibold">Status:</span>
                    <.badge>
                      {String.capitalize(@active_subscription.stripe_status)}
                    </.badge>
                  </p>
                  <p>
                    <span class="font-semibold">Current Period Start:</span>
                    {if @active_subscription.current_period_start do
                      format_datetime_for_display(
                        @active_subscription.current_period_start
                      )
                    else
                      "N/A"
                    end}
                  </p>
                  <p>
                    <span class="font-semibold">Current Period End:</span>
                    {if @active_subscription.current_period_end do
                      format_datetime_for_display(
                        @active_subscription.current_period_end
                      )
                    else
                      "N/A"
                    end}
                  </p>
                  <p :if={@active_subscription.ends_at}>
                    <span class="font-semibold">Scheduled Cancellation:</span>
                    {format_datetime_for_display(@active_subscription.ends_at)}
                  </p>
                  <p :if={@scheduled_downgrade_info}>
                    <span class="font-semibold">Scheduled Downgrade:</span>
                    Will change to {String.capitalize(
                      to_string(@scheduled_downgrade_info.target_plan)
                    )} on {format_utc_date_long(
                      @scheduled_downgrade_info.effective_date
                    )}
                  </p>
                  <p>
                    <span class="font-semibold">Stripe Subscription ID:</span>
                    <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                      {@active_subscription.stripe_id}
                    </code>
                  </p>
                </div>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                  Change Membership Type
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Change the user's membership plan. Upgrades will be charged immediately, downgrades will take effect at the next renewal.
                </p>
                <.simple_form
                  for={@membership_type_form}
                  phx-change="validate_membership_type"
                  phx-submit="update_membership_type"
                >
                  <.input
                    field={@membership_type_form[:membership_type]}
                    type="select"
                    label="New Membership Type"
                    options={get_membership_type_options(@active_subscription)}
                  />
                  <div class="flex flex-row justify-end w-full pt-4">
                    <.button phx-disable-with="Changing..." type="submit">
                      <.icon
                        name="hero-arrows-right-left"
                        class="w-5 h-5 mb-0.5 me-1"
                      /> Change Membership Type
                    </.button>
                  </div>
                </.simple_form>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                  Override Membership Length
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Set a new period end date for this subscription. This will update the billing cycle anchor in Stripe.
                </p>
                <.simple_form
                  for={@membership_form}
                  phx-change="validate_membership"
                  phx-submit="update_membership_period"
                >
                  <.input
                    field={@membership_form[:period_end_date]}
                    type="datetime-local"
                    label="New Period End Date"
                    value={
                      if @membership_form[:period_end_date].value do
                        format_datetime_local(
                          @membership_form[:period_end_date].value
                        )
                      else
                        format_datetime_local(
                          @active_subscription.current_period_end
                        )
                      end
                    }
                  />
                  <div class="flex flex-row justify-end w-full pt-4">
                    <.button phx-disable-with="Updating..." type="submit">
                      <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" />
                      Update Period End
                    </.button>
                  </div>
                </.simple_form>
              </div>

              <div class="border-t border-zinc-200 pt-6">
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                  Payment History
                </h3>

                <div
                  :if={length(@subscription_payments) == 0}
                  class="text-sm text-zinc-600"
                >
                  <p>No payment history found for this subscription.</p>
                </div>

                <div
                  :if={length(@subscription_payments) > 0}
                  class="overflow-x-auto"
                >
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Date
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Amount
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Status
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Invoice ID
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Payment Method
                        </th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-zinc-200">
                      <tr
                        :for={payment <- @subscription_payments}
                        class="hover:bg-zinc-50"
                      >
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-800">
                          {if payment.payment_date do
                            format_datetime_for_display(payment.payment_date)
                          else
                            "N/A"
                          end}
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm font-medium text-zinc-900">
                          {Ysc.MoneyHelper.format_money!(payment.amount)}
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge>
                            {String.capitalize("#{payment.status}")}
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            {if payment.external_payment_id do
                              String.slice(payment.external_payment_id, 0..20) <>
                                if(String.length(payment.external_payment_id) > 20,
                                  do: "...",
                                  else: ""
                                )
                            else
                              "N/A"
                            end}
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          {if payment.payment_method do
                            case payment.payment_method.type do
                              "card" ->
                                if payment.payment_method.last4 do
                                  "Card ending in #{payment.payment_method.last4}"
                                else
                                  "Card"
                                end

                              "us_bank_account" ->
                                if payment.payment_method.last4 do
                                  "Bank ending in #{payment.payment_method.last4}"
                                else
                                  "Bank account"
                                end

                              _ ->
                                "Payment method"
                            end
                          else
                            "N/A"
                          end}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div class="border-t border-zinc-200 pt-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                Lifetime Membership Management
              </h3>
              <p class="text-sm text-zinc-600 mb-4">
                Award or revoke lifetime membership. Lifetime members never need to pay and have all Family membership perks.
                <strong>This works regardless of subscription status.</strong>
              </p>
              <.simple_form
                for={@lifetime_form}
                phx-change="validate_lifetime"
                phx-submit="update_lifetime_membership"
              >
                <.input
                  field={@lifetime_form[:has_lifetime]}
                  type="checkbox"
                  label="User has lifetime membership"
                />
                <.input
                  :if={@lifetime_form[:has_lifetime].value}
                  field={@lifetime_form[:awarded_at]}
                  type="datetime-local"
                  label="Awarded Date (can be in the past)"
                  value={
                    if @lifetime_form[:awarded_at].value do
                      format_datetime_local(@lifetime_form[:awarded_at].value)
                    else
                      format_datetime_local(DateTime.utc_now())
                    end
                  }
                />
                <div class="flex flex-row justify-end w-full pt-4">
                  <.button phx-disable-with="Saving..." type="submit">
                    <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" />
                    Save Lifetime Membership
                  </.button>
                </div>
              </.simple_form>
            </div>
          </div>
        </div>

        <div
          :if={@live_action == :bank_accounts && @is_treasurer}
          class="max-w-full py-8 px-2"
        >
          <div class="space-y-6">
            <.admin_page_title level={2}>Bank Accounts</.admin_page_title>
            <p class="text-sm text-zinc-600">
              View bank accounts for expense report reimbursements. Click "Unseal" to view encrypted account and routing numbers.
            </p>

            <div :if={length(@bank_accounts) > 0} class="space-y-4">
              <%= for bank_account <- @bank_accounts do %>
                <div class="border border-zinc-200 rounded-lg p-6">
                  <div class="flex justify-between items-start mb-4">
                    <div>
                      <h3 class="text-lg font-semibold text-zinc-900">
                        Account ending in ••••{bank_account.account_number_last_4}
                      </h3>
                      <p class="text-sm text-zinc-600 mt-1">
                        Added {format_utc_date_long(bank_account.inserted_at)}
                      </p>
                    </div>
                    <button
                      :if={@unsealed_account_id != bank_account.id}
                      type="button"
                      phx-click="unseal_bank_account"
                      phx-value-id={bank_account.id}
                      class="px-4 py-2 text-sm font-medium text-blue-600 bg-blue-50 rounded-md hover:bg-blue-100"
                    >
                      Unseal Details
                    </button>
                    <button
                      :if={@unsealed_account_id == bank_account.id}
                      type="button"
                      phx-click="seal_bank_account"
                      class="px-4 py-2 text-sm font-medium text-zinc-600 bg-zinc-50 rounded-md hover:bg-zinc-100"
                    >
                      Seal Details
                    </button>
                  </div>

                  <div
                    :if={@unsealed_account_id == bank_account.id}
                    class="mt-4 pt-4 border-t border-zinc-200"
                  >
                    <div class="grid grid-cols-2 gap-4">
                      <div>
                        <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                          Routing Number
                        </p>
                        <p class="text-sm font-mono text-zinc-900 bg-zinc-50 p-2 rounded">
                          {@unsealed_account.routing_number}
                        </p>
                      </div>
                      <div>
                        <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                          Account Number
                        </p>
                        <p class="text-sm font-mono text-zinc-900 bg-zinc-50 p-2 rounded">
                          {@unsealed_account.account_number}
                        </p>
                      </div>
                    </div>
                    <p class="text-xs text-zinc-500 mt-4 italic">
                      ⚠️ Sensitive information - keep secure
                    </p>
                  </div>
                </div>
              <% end %>
            </div>

            <div
              :if={length(@bank_accounts) == 0}
              class="text-center py-12 border border-zinc-200 rounded-lg"
            >
              <p class="text-zinc-500">No bank accounts found for this user.</p>
            </div>
          </div>
        </div>

        <div :if={@live_action == :notifications} class="max-w-full py-8 px-2">
          <div class="flex flex-row flex-nowrap items-stretch gap-0">
            <div
              id="resizable-left-panel"
              class={[
                "resizable-left flex-1 flex-auto overflow-auto",
                if(@selected_notification,
                  do: "flex-[0_0_auto]",
                  else: "flex-[1_1_auto]"
                )
              ]}
              style={
                if @selected_notification && @panel_width do
                  "width: calc(100% - #{@panel_width} - 8px); flex-shrink: 0;"
                else
                  nil
                end
              }
            >
              <h2 class="text-xl font-semibold text-zinc-800 mb-4">
                Notifications
              </h2>
              <div class="w-full">
                <div
                  :if={length(@notifications) == 0}
                  class="text-sm text-zinc-600 py-8"
                >
                  <p>No notifications found for this user.</p>
                </div>

                <div :if={length(@notifications) > 0} class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Sent
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Type
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Template
                        </th>
                        <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                          Recipient
                        </th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-zinc-200">
                      <tr
                        :for={notification <- @notifications}
                        phx-click="select_notification"
                        phx-value-id={notification.id}
                        class={[
                          "hover:bg-zinc-50 cursor-pointer",
                          @selected_notification &&
                            notification.id == @selected_notification.id &&
                            "bg-blue-50"
                        ]}
                      >
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-800">
                          {format_datetime_for_display(notification.inserted_at)}
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge type={
                            if notification.message_type == :email,
                              do: "default",
                              else: "green"
                          }>
                            {notification.message_type
                            |> to_string()
                            |> String.upcase()}
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            {notification.message_template}
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <%= if notification.email do %>
                            {notification.email}
                          <% else %>
                            <%= if notification.phone_number do %>
                              {Ysc.Extensions.PhoneNumber.format_for_display(
                                notification.phone_number
                              ) || notification.phone_number}
                            <% else %>
                              <span class="text-zinc-400">—</span>
                            <% end %>
                          <% end %>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div
              :if={@selected_notification}
              id="resizable-right-panel"
              phx-hook="PanelResizer"
              data-target=".resizable-right"
              class="resizable-right flex-[0_0_auto] bg-white border-l-4 border-zinc-300 hover:border-blue-500 select-none transition-colors flex flex-row"
              style={
                if @panel_width do
                  "max-height: calc(100vh - 200px); width: #{@panel_width}; flex-shrink: 0;"
                else
                  "max-height: calc(100vh - 200px); width: 40%; flex-shrink: 0;"
                end
              }
            >
              <div
                id="panel-resizer-left-edge"
                phx-update="ignore"
                class="flex-shrink-0 w-6 cursor-ew-resize z-10 flex items-center justify-center pointer-events-auto"
              >
                <.icon
                  name="hero-arrows-right-left"
                  class="w-4 h-4 text-zinc-400 pointer-events-none"
                />
              </div>
              <div
                id={"notification-content-#{@selected_notification.id}"}
                class="flex-1 p-6 overflow-auto"
              >
                <div class="flex justify-between items-start mb-4">
                  <h3 class="text-lg font-semibold text-zinc-800">
                    Message Details
                  </h3>
                  <button
                    phx-click="close_notification_panel"
                    class="text-zinc-400 hover:text-zinc-600"
                    type="button"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>

                <div class="space-y-4">
                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Sent
                    </p>
                    <p class="text-sm text-zinc-800">
                      {format_datetime_for_display(
                        @selected_notification.inserted_at
                      )}
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Type
                    </p>
                    <p class="text-sm text-zinc-800">
                      <.badge>
                        {@selected_notification.message_type
                        |> to_string()
                        |> String.capitalize()}
                      </.badge>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Template
                    </p>
                    <p class="text-sm text-zinc-800">
                      <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                        {@selected_notification.message_template}
                      </code>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Recipient
                    </p>
                    <p class="text-sm text-zinc-800">
                      <%= if @selected_notification.email do %>
                        {@selected_notification.email}
                      <% else %>
                        <%= if @selected_notification.phone_number do %>
                          {Ysc.Extensions.PhoneNumber.format_for_display(
                            @selected_notification.phone_number
                          ) || @selected_notification.phone_number}
                        <% else %>
                          <span class="text-zinc-400">—</span>
                        <% end %>
                      <% end %>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-2">
                      Message
                    </p>
                    <div class="bg-zinc-50 rounded-lg border border-zinc-200 overflow-hidden">
                      <%= if @selected_notification.rendered_message do %>
                        <iframe
                          id={"email-preview-#{@selected_notification.id}"}
                          srcdoc={@selected_notification.rendered_message}
                          class="w-full border-0"
                          style="min-height: 400px; height: 600px;"
                          phx-hook="EmailPreview"
                        >
                        </iframe>
                      <% else %>
                        <div class="p-4">
                          <p class="text-sm text-zinc-400 italic">
                            No message content available
                          </p>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <div :if={
                    @selected_notification.params &&
                      map_size(@selected_notification.params) > 0
                  }>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-2">
                      Parameters
                    </p>
                    <div class="bg-zinc-50 rounded-lg p-4 border border-zinc-200">
                      <pre class="text-xs text-zinc-600 overflow-x-auto"><code><%= inspect(@selected_notification.params, pretty: true) %></code></pre>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div :if={@live_action == :family} class="max-w-lg py-8 px-2">
          <div class="space-y-6">
            <%!-- Associated Users (unified for both primary and sub-account views) --%>
            <div class="border border-zinc-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-1">
                Associated Users
              </h3>
              <p class="text-sm text-zinc-500 mb-4">
                Users linked to this membership. Family and lifetime members can have additional users (spouse, children) who share membership benefits.
              </p>
              <div class="space-y-3">
                <%!-- Primary user row --%>
                <%= if @primary_user do %>
                  <.link
                    navigate={~p"/admin/users/#{@primary_user.id}/details"}
                    class="flex items-center gap-4 p-4 bg-zinc-50 rounded-lg hover:bg-zinc-100 transition-colors"
                  >
                    <.user_avatar_image
                      user={@primary_user}
                      class="w-10 h-10 rounded-full"
                    />
                    <div class="flex-1">
                      <span class="font-semibold text-zinc-900">
                        {@primary_user.first_name} {@primary_user.last_name}
                      </span>
                      <span class="text-zinc-500 text-sm ml-2">(Primary)</span>
                      <div class="text-sm text-zinc-600">{@primary_user.email}</div>
                      <%= if @primary_user.phone_number do %>
                        <div class="text-sm text-zinc-500">
                          {Ysc.Extensions.PhoneNumber.format_for_display(
                            @primary_user.phone_number
                          ) || @primary_user.phone_number}
                        </div>
                      <% end %>
                    </div>
                    <.badge type={user_state_to_badge_type(@primary_user.state)}>
                      {user_state_to_readable(@primary_user.state)}
                    </.badge>
                  </.link>
                <% else %>
                  <div class="flex items-center gap-4 p-4 bg-zinc-50 rounded-lg">
                    <.user_avatar_image
                      user={@selected_user}
                      class="w-10 h-10 rounded-full"
                    />
                    <div class="flex-1">
                      <span class="font-semibold text-zinc-900">
                        {@selected_user.first_name} {@selected_user.last_name}
                      </span>
                      <span class="text-zinc-500 text-sm ml-2">(Primary)</span>
                      <div class="text-sm text-zinc-600">
                        {@selected_user.email}
                      </div>
                    </div>
                  </div>
                <% end %>
                <%!-- Sub-accounts (children/spouse) --%>
                <%= for sub_account <- @sub_accounts do %>
                  <div class="flex items-center justify-between gap-4 p-4 bg-zinc-50 rounded-lg">
                    <div class="flex items-center gap-4 flex-1">
                      <.user_avatar_image
                        user={sub_account}
                        class="w-10 h-10 rounded-full"
                      />
                      <div>
                        <span class="font-semibold text-zinc-900">
                          {sub_account.first_name} {sub_account.last_name}
                        </span>
                        <.badge type="sky" class="ml-2 text-xs">
                          {format_family_relationship(
                            sub_account.family_relationship
                          )}
                        </.badge>
                        <div class="text-sm text-zinc-600">{sub_account.email}</div>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <.link
                        navigate={~p"/admin/users/#{sub_account.id}/details"}
                        class="text-sm text-blue-600 hover:underline"
                      >
                        View
                      </.link>
                      <button
                        phx-click="admin_remove_family_user"
                        phx-value-user_id={sub_account.id}
                        phx-disable-with="Removing..."
                        data-confirm="Remove this user from the family membership? They will lose access to membership benefits and receive an email notification."
                        class="text-sm text-red-600 hover:underline"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
              <%!-- Pending invites --%>
              <div
                :if={@can_manage_family && @pending_invites != []}
                class="mt-6 pt-6 border-t border-zinc-200"
              >
                <h4 class="text-sm font-semibold text-zinc-800 mb-3">
                  Pending invites
                </h4>
                <div class="space-y-2">
                  <%= for invite <- @pending_invites do %>
                    <div class="flex items-center justify-between gap-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                      <div>
                        <span class="text-sm font-medium text-zinc-900">
                          {invite.email}
                        </span>
                        <.badge type="sky" class="ml-2 text-xs">
                          {format_family_relationship(invite.relationship)}
                        </.badge>
                        <span class="text-xs text-zinc-500 ml-2">
                          Expires {format_utc_date(invite.expires_at)}
                        </span>
                      </div>
                      <button
                        phx-click="admin_cancel_family_invite"
                        phx-value-invite_id={invite.id}
                        phx-disable-with="Cancelling..."
                        data-confirm="Cancel this invite? The invitee will receive an email notification."
                        class="text-sm text-red-600 hover:underline"
                      >
                        Cancel invite
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
              <%!-- Add user form --%>
              <div
                :if={@can_manage_family}
                class="mt-6 pt-6 border-t border-zinc-200"
              >
                <h4 class="text-sm font-semibold text-zinc-800 mb-3">
                  Add user to membership
                </h4>
                <p class="text-xs text-zinc-500 mb-3">
                  Search by email. Link an existing user or invite a new one.
                </p>
                <form
                  phx-change="search_add_family_user"
                  phx-debounce="200"
                  class="space-y-3"
                >
                  <div class="relative">
                    <input
                      type="text"
                      name="query"
                      value={@add_family_user_search}
                      placeholder="Search by email..."
                      autocomplete="off"
                      class="block w-full rounded-md border border-zinc-300 px-3 py-2 text-sm shadow-sm focus:border-zinc-400 focus:outline-none focus:ring-0"
                    />
                    <div
                      :if={@add_family_user_search != ""}
                      class="absolute z-50 w-full mt-1 bg-white border border-zinc-200 rounded-md shadow-lg overflow-hidden"
                      phx-click-away="clear_add_family_user_search"
                    >
                      <%= for user <- @add_family_user_results do %>
                        <button
                          type="button"
                          phx-click="admin_link_family_user"
                          phx-value-user_id={user.id}
                          phx-value-relationship={@add_family_user_relationship}
                          phx-disable-with="Linking..."
                          class="w-full px-3 py-2.5 text-left hover:bg-zinc-50 flex items-center gap-2 border-b border-zinc-100 last:border-b-0"
                        >
                          <.icon
                            name="hero-user-plus"
                            class="w-4 h-4 text-blue-600 shrink-0"
                          />
                          <div>
                            <span class="text-sm font-medium text-zinc-900">
                              {user.first_name} {user.last_name}
                            </span>
                            <span class="text-xs text-zinc-500 ml-1">
                              ({user.email})
                            </span>
                            <span class="text-xs text-blue-600 ml-1">
                              — Link directly
                            </span>
                          </div>
                        </button>
                      <% end %>
                      <button
                        :if={@add_family_user_results == []}
                        type="button"
                        phx-click="admin_invite_family_user"
                        phx-value-email={@add_family_user_search}
                        phx-value-relationship={@add_family_user_relationship}
                        phx-disable-with="Sending invite..."
                        class="w-full px-3 py-2.5 text-left hover:bg-zinc-50 flex items-center gap-2"
                      >
                        <.icon
                          name="hero-envelope"
                          class="w-4 h-4 text-amber-600 shrink-0"
                        />
                        <div>
                          <span class="text-sm font-medium text-zinc-900">
                            Invite {@add_family_user_search}
                          </span>
                          <span class="text-xs text-amber-600 ml-1">
                            — New user will receive email
                          </span>
                        </div>
                      </button>
                    </div>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-zinc-700 mb-1">
                      Relationship
                    </label>
                    <select
                      name="relationship"
                      class="block w-full rounded-md border border-zinc-300 px-3 py-2 text-sm shadow-sm focus:border-zinc-400 focus:outline-none focus:ring-0"
                    >
                      <option
                        value="child"
                        selected={@add_family_user_relationship == "child"}
                      >
                        Child
                      </option>
                      <option
                        value="spouse"
                        selected={@add_family_user_relationship == "spouse"}
                      >
                        Spouse
                      </option>
                    </select>
                  </div>
                </form>
              </div>
            </div>
            <%!-- Family Members (non-user entities) --%>
            <div
              :if={length(@family_members) > 0}
              class="border border-zinc-200 rounded-lg p-6"
            >
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                Family Members ({length(@family_members)})
              </h3>
              <div class="space-y-3">
                <div
                  :for={family_member <- @family_members}
                  class="p-4 bg-zinc-50 rounded-lg"
                >
                  <div class="flex items-center gap-4">
                    <div class="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center">
                      <span class="text-blue-600 font-semibold">
                        {String.first(family_member.first_name)}
                      </span>
                    </div>
                    <div class="flex-1">
                      <div class="flex items-center gap-2">
                        <span class="font-semibold text-zinc-900">
                          {"#{family_member.first_name} #{family_member.last_name}"}
                        </span>
                        <.badge type="sky" class="text-xs">
                          {String.capitalize("#{family_member.type}")}
                        </.badge>
                      </div>
                      <%= if family_member.birth_date do %>
                        <div class="text-sm text-zinc-600">
                          Birth date: {Calendar.strftime(
                            family_member.birth_date,
                            "%B %d, %Y"
                          )}
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <%!-- Empty state: no sub-accounts and no family members --%>
            <div
              :if={
                @sub_accounts == [] && length(@family_members) == 0 &&
                  !@primary_user
              }
              class="mt-4 text-center py-8 border border-zinc-200 rounded-lg"
            >
              <p class="text-zinc-500">No family members linked yet.</p>
            </div>
          </div>
        </div>

        <div :if={@live_action == :logs} class="max-w-full py-8 px-2">
          <div class="space-y-6">
            <h2 class="text-xl font-semibold text-zinc-800 mb-4">User Notes</h2>

            <div class="bg-white border border-zinc-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">Add Note</h3>
              <.simple_form
                for={@note_form}
                phx-change="validate_note"
                phx-submit="create_note"
                id="note-form"
              >
                <.input
                  field={@note_form[:category]}
                  type="select"
                  label="Category"
                  options={[General: "general", Violation: "violation"]}
                />
                <.input
                  field={@note_form[:note]}
                  type="textarea"
                  label="Note"
                  placeholder="Enter a note about this user..."
                  rows="4"
                />
                <div class="flex flex-row justify-end w-full pt-4">
                  <.button phx-disable-with="Adding..." type="submit">
                    <.icon name="hero-plus" class="w-5 h-5 mb-0.5 me-1" /> Add Note
                  </.button>
                </div>
              </.simple_form>
            </div>

            <div class="bg-white border border-zinc-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">Timeline</h3>
              <div :if={length(@user_notes) == 0} class="text-center py-12">
                <p class="text-zinc-500">
                  No notes yet. Add a note above to get started.
                </p>
              </div>
              <div :if={length(@user_notes) > 0} class="relative">
                <div class="absolute left-4 top-0 bottom-0 w-0.5 bg-zinc-200"></div>
                <div class="space-y-6">
                  <%= for note <- @user_notes do %>
                    <div class="relative flex gap-4">
                      <div class="flex-shrink-0">
                        <div class="w-8 h-8 rounded-full bg-blue-100 border-2 border-white flex items-center justify-center relative z-10">
                          <.icon
                            name="hero-document-text"
                            class="w-4 h-4 text-blue-600"
                          />
                        </div>
                      </div>
                      <div class="flex-1 pb-6">
                        <div class="bg-zinc-50 rounded-lg p-4 border border-zinc-200">
                          <div class="flex items-start justify-between mb-2">
                            <div class="flex-1">
                              <div class="flex items-center gap-2 mb-1">
                                <p class="text-sm font-semibold text-zinc-900">
                                  <%= if note.created_by do %>
                                    {"#{note.created_by.first_name} #{note.created_by.last_name}"}
                                  <% else %>
                                    Unknown Admin
                                  <% end %>
                                </p>
                                <.badge type={
                                  if note.category in [:violation, :rejection],
                                    do: "red",
                                    else: "default"
                                }>
                                  {String.capitalize("#{note.category}")}
                                </.badge>
                              </div>
                              <p class="text-xs text-zinc-500 mt-0.5">
                                <%= if note.created_by do %>
                                  {note.created_by.email}
                                <% end %>
                              </p>
                            </div>
                            <div class="text-xs text-zinc-500">
                              {format_datetime_for_display(note.inserted_at)}
                            </div>
                          </div>
                          <div class="mt-3">
                            <p class="text-sm text-zinc-800 whitespace-pre-wrap">
                              {note.note}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.side_menu>

    <.modal
      :if={@pending_activation_params != nil}
      id="rejection-override-modal"
      show={true}
      on_cancel={JS.push("cancel_activation_override")}
      max_width="max-w-lg"
    >
      <div class="space-y-4">
        <div class="flex items-start gap-3">
          <div class="flex-shrink-0 w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-amber-600" />
          </div>
          <div>
            <h2
              id="rejection-override-modal-title"
              class="text-lg font-semibold text-zinc-900"
            >
              Override Rejection Decision
            </h2>
            <p class="text-sm text-zinc-600 mt-1">
              This user's membership application was <span class="font-semibold text-red-600">rejected</span>. You must provide a
              reason for overriding this decision before activating the account.
            </p>
          </div>
        </div>
        <.simple_form
          for={@override_rejection_form}
          phx-change="validate_override_note"
          phx-submit="confirm_activation_override"
          id="override-rejection-form"
        >
          <.input
            field={@override_rejection_form[:note]}
            type="textarea"
            label="Reason for override"
            placeholder="Explain why you are overriding the rejection decision..."
            rows="4"
          />
          <div class="flex flex-row justify-end gap-3 pt-2">
            <button
              type="button"
              phx-click="cancel_activation_override"
              class="px-4 py-2 rounded-md text-sm font-medium border border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50"
            >
              Cancel
            </button>
            <.button phx-disable-with="Activating..." type="submit">
              Activate & Save Note
            </.button>
          </div>
        </.simple_form>
      </div>
    </.modal>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    current_user = socket.assigns[:current_user]

    connect_params = get_connect_params(socket) || %{}
    timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

    today_max =
      timezone
      |> DateTime.now!()
      |> DateTime.to_date()
      |> Date.to_iso8601()

    selected_user =
      Accounts.get_user!(id, [
        :family_members,
        :billing_address,
        {:primary_user, :current_avatar},
        {:sub_accounts, :current_avatar},
        :current_avatar
      ])

    user_changeset =
      Accounts.User.update_user_with_address_changeset(selected_user, %{})

    user_form = to_form(user_changeset, as: "user")
    original_form_data = extract_form_data(user_form)

    is_treasurer =
      current_user.board_position == :treasurer && current_user.state == :active

    socket =
      socket
      |> assign(:user_id, id)
      |> assign(:first_name, selected_user.first_name)
      |> assign(:last_name, selected_user.last_name)
      |> assign(:role, selected_user.role)
      |> assign(:page_title, "Users")
      |> assign(:active_page, :members)
      |> assign(:selected_user, selected_user)
      |> assign(:selected_user_application, nil)
      |> assign(:active_subscription, nil)
      |> assign(:subscription_payments, [])
      |> assign(:scheduled_downgrade_info, nil)
      |> assign(:has_lifetime_membership, false)
      |> assign(:membership_paused_by_board, nil)
      |> assign(
        :membership_form,
        to_form(membership_changeset(%{period_end_date: nil}), as: "membership")
      )
      |> assign(
        :membership_type_form,
        to_form(membership_type_changeset(%{membership_type: nil}),
          as: "membership_type"
        )
      )
      |> assign(
        :lifetime_form,
        to_form(
          lifetime_membership_changeset(%{
            has_lifetime: false,
            awarded_at: DateTime.utc_now()
          }),
          as: "lifetime"
        )
      )
      |> assign(
        :create_paid_membership_form,
        to_form(create_paid_membership_changeset(%{plan_id: "single"}),
          as: "create_paid_membership"
        )
      )
      |> assign(:ticket_orders_meta, nil)
      |> assign(:bookings_meta, nil)
      |> assign(:notifications, [])
      |> assign(:selected_notification, nil)
      |> assign(:panel_width, nil)
      |> assign(:is_treasurer, is_treasurer)
      |> assign(:bank_accounts, [])
      |> assign(:unsealed_account_id, nil)
      |> assign(:unsealed_account, nil)
      |> assign(:original_form_data, original_form_data)
      |> assign(:timezone, timezone)
      |> assign(:today_max, today_max)
      |> assign(:primary_user, nil)
      |> assign(:sub_accounts, [])
      |> assign(:family_members, [])
      |> assign(:pending_invites, [])
      |> assign(:can_manage_family, false)
      |> assign(:add_family_user_search, "")
      |> assign(:add_family_user_results, [])
      |> assign(:add_family_user_relationship, "child")
      |> assign(:user_notes, [])
      |> assign(:rejection_notes, [])
      |> assign(
        :note_form,
        to_form(note_changeset(%{category: "general"}), as: "note")
      )
      |> assign(:pending_activation_params, nil)
      |> assign(
        :override_rejection_form,
        to_form(override_rejection_changeset(%{}), as: "override")
      )
      |> assign(:booking_entitlements, [])
      |> assign(:entitlement_form, entitlement_form_defaults())
      |> assign(form: user_form)

    socket =
      if connected?(socket) do
        [sub_result, has_lifetime, application, board_member] =
          Task.await_many(
            [
              Task.async(fn -> fetch_subscription_data(selected_user) end),
              Task.async(fn ->
                Accounts.has_lifetime_membership?(selected_user)
              end),
              Task.async(fn -> fetch_application(id, current_user) end),
              Task.async(fn ->
                Accounts.household_board_member(selected_user)
              end)
            ],
            :infinity
          )

        {active_subscription, subscription_payments} = sub_result

        membership_cs =
          %{
            period_end_date:
              active_subscription && active_subscription.current_period_end
          }
          |> membership_changeset()

        lifetime_cs =
          %{
            has_lifetime: has_lifetime,
            awarded_at:
              selected_user.lifetime_membership_awarded_at || DateTime.utc_now()
          }
          |> lifetime_membership_changeset()

        membership_type_cs =
          %{
            membership_type:
              get_current_membership_type_from_subscription(active_subscription)
          }
          |> membership_type_changeset()

        socket =
          socket
          |> assign(:selected_user_application, application)
          |> assign(:active_subscription, active_subscription)
          |> assign(:subscription_payments, subscription_payments)
          |> assign(:has_lifetime_membership, has_lifetime)
          |> assign(:membership_paused_by_board, board_member)
          |> assign(:membership_form, to_form(membership_cs, as: "membership"))
          |> assign(
            :membership_type_form,
            to_form(membership_type_cs, as: "membership_type")
          )
          |> assign(:lifetime_form, to_form(lifetime_cs, as: "lifetime"))

        if active_subscription do
          start_async(socket, :load_downgrade_info, fn ->
            Subscriptions.get_scheduled_downgrade_info(active_subscription)
          end)
        else
          socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    user_id = socket.assigns.user_id
    list_params = Map.drop(params, ["id"])
    socket = assign(socket, :list_params, list_params)

    if socket.assigns.live_action == :booking_benefits do
      {:noreply,
       push_navigate(socket,
         to: ~p"/admin/users/#{user_id}/details/bookings?#{list_params}"
       )}
    else
      socket =
        case socket.assigns.live_action do
          :orders ->
            socket
            |> stream(:ticket_orders, [], reset: true)
            |> start_async(:load_ticket_orders, fn ->
              Tickets.list_user_ticket_orders_paginated(user_id, params)
            end)

          :bookings ->
            socket
            |> stream(:bookings, [], reset: true)
            |> start_async(:load_bookings, fn ->
              Bookings.list_user_bookings_paginated(user_id, params)
            end)
            |> start_async(:load_booking_entitlements, fn ->
              Entitlements.list_all_for_user(user_id)
            end)

          :notifications ->
            user_email = socket.assigns.selected_user.email

            start_async(socket, :load_notifications, fn ->
              Messages.list_user_messages(user_id,
                limit: 100,
                email: user_email
              )
            end)

          :bank_accounts ->
            if socket.assigns.is_treasurer do
              start_async(socket, :load_bank_accounts, fn ->
                user = Accounts.get_user!(user_id)
                ExpenseReports.list_bank_accounts(user)
              end)
            else
              socket
            end

          :family ->
            selected_user = socket.assigns.selected_user

            start_async(socket, :load_family, fn ->
              fetch_family_assigns(selected_user)
            end)

          :membership ->
            selected_user = socket.assigns.selected_user

            start_async(socket, :load_family, fn ->
              fetch_family_assigns(selected_user)
            end)

          :logs ->
            start_async(socket, :load_user_notes, fn ->
              Accounts.list_user_notes(user_id)
            end)

          :application ->
            start_async(socket, :load_rejection_notes, fn ->
              Accounts.list_user_notes_by_category(user_id, :rejection)
            end)

          _ ->
            socket
        end

      {:noreply, socket}
    end
  end

  def handle_async(:load_downgrade_info, {:ok, info}, socket) do
    {:noreply, assign(socket, :scheduled_downgrade_info, info)}
  end

  def handle_async(:load_downgrade_info, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_ticket_orders, {:ok, {:ok, {orders, meta}}}, socket) do
    {:noreply,
     socket
     |> assign(:ticket_orders_meta, meta)
     |> stream(:ticket_orders, orders, reset: true)}
  end

  def handle_async(:load_ticket_orders, {:ok, {:error, meta}}, socket) do
    {:noreply,
     socket
     |> assign(:ticket_orders_meta, meta)
     |> stream(:ticket_orders, [], reset: true)}
  end

  def handle_async(:load_ticket_orders, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_bookings, {:ok, {:ok, {bookings, meta}}}, socket) do
    {:noreply,
     socket
     |> assign(:bookings_meta, meta)
     |> stream(:bookings, bookings, reset: true)}
  end

  def handle_async(:load_bookings, {:ok, {:error, meta}}, socket) do
    {:noreply,
     socket
     |> assign(:bookings_meta, meta)
     |> stream(:bookings, [], reset: true)}
  end

  def handle_async(:load_bookings, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_booking_entitlements, {:ok, list}, socket) do
    {:noreply, assign(socket, :booking_entitlements, list)}
  end

  def handle_async(:load_booking_entitlements, {:exit, reason}, socket) do
    Ysc.Logging.error("Failed to load booking entitlements",
      error: inspect(reason)
    )

    {:noreply, socket}
  end

  def handle_async(:load_notifications, {:ok, notifications}, socket) do
    {:noreply, assign(socket, :notifications, notifications)}
  end

  def handle_async(:load_notifications, {:exit, reason}, socket) do
    Ysc.Logging.error("Failed to load notifications", error: inspect(reason))
    {:noreply, socket}
  end

  def handle_async(:load_bank_accounts, {:ok, bank_accounts}, socket) do
    {:noreply, assign(socket, :bank_accounts, bank_accounts)}
  end

  def handle_async(:load_bank_accounts, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_family, {:ok, assigns}, socket) do
    {:noreply,
     socket
     |> assign(:primary_user, assigns.primary_user)
     |> assign(:sub_accounts, assigns.sub_accounts)
     |> assign(:family_members, assigns.family_members)
     |> assign(:pending_invites, assigns.pending_invites)
     |> assign(:can_manage_family, assigns.can_manage_family)
     |> assign(:add_family_user_search, "")
     |> assign(:add_family_user_results, [])
     |> assign(:add_family_user_relationship, "child")}
  end

  def handle_async(:load_family, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_user_notes, {:ok, notes}, socket) do
    {:noreply, assign(socket, :user_notes, notes)}
  end

  def handle_async(:load_user_notes, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_async(:load_rejection_notes, {:ok, notes}, socket) do
    {:noreply, assign(socket, :rejection_notes, notes)}
  end

  def handle_async(:load_rejection_notes, {:exit, _}, socket) do
    {:noreply, socket}
  end

  def handle_event("select_notification", %{"id" => id}, socket) do
    notification =
      socket.assigns.notifications
      |> Enum.find(fn n -> n.id == id end)

    {:noreply, assign(socket, :selected_notification, notification)}
  end

  def handle_event("close_notification_panel", _params, socket) do
    {:noreply, assign(socket, :selected_notification, nil)}
  end

  def handle_event("resize_panel", %{"width" => width}, socket) do
    {:noreply, assign(socket, :panel_width, width)}
  end

  def handle_event("grant_booking_entitlement", %{"entitlement" => p}, socket) do
    user_id = socket.assigns.user_id
    admin_id = socket.assigns.current_user.id
    attrs = Entitlements.grant_attrs_from_entitlement_form(p, admin_id, user_id)

    case Entitlements.create_entitlement(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Benefit granted. Member will receive an email.",
           title: "Bookings"
         )
         |> assign(:entitlement_form, entitlement_form_defaults())
         |> start_async(:load_booking_entitlements, fn ->
           Entitlements.list_all_for_user(user_id)
         end)}

      {:error, %Ecto.Changeset{} = cs} ->
        msg = format_changeset_errors(cs)

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, msg, title: "Bookings")
         |> assign(:entitlement_form, to_form(cs, as: :entitlement))}

      {:error, reason} ->
        Ysc.Logging.error(
          "Booking entitlement created but post-grant step failed",
          error: inspect(reason),
          extra: %{user_id: user_id, admin_id: admin_id}
        )

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :warning,
           "Benefit granted, but notifying the member failed. The benefit is active; do not retry unless you intended a second grant.",
           title: "Bookings"
         )
         |> assign(:entitlement_form, entitlement_form_defaults())
         |> start_async(:load_booking_entitlements, fn ->
           Entitlements.list_all_for_user(user_id)
         end)}
    end
  end

  def handle_event("revoke_booking_entitlement", %{"id" => id}, socket) do
    user_id = socket.assigns.user_id

    case Entitlements.get_entitlement(id) do
      nil ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Entitlement not found.",
           title: "Bookings"
         )}

      ent ->
        if ent.user_id != user_id do
          {:noreply,
           YscWeb.Flash.put_toast(socket, :error, "Invalid entitlement.",
             title: "Bookings"
           )}
        else
          case Entitlements.revoke_entitlement(ent) do
            {:ok, _} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(:info, "Benefit revoked.",
                 title: "Bookings"
               )
               |> start_async(:load_booking_entitlements, fn ->
                 Entitlements.list_all_for_user(user_id)
               end)}

            {:error, _} ->
              {:noreply,
               YscWeb.Flash.put_toast(socket, :error, "Could not revoke.",
                 title: "Bookings"
               )}
          end
        end
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    current_user = socket.assigns[:current_user]
    assigned = socket.assigns[:selected_user]
    application = socket.assigns[:selected_user_application]

    activating_rejected_user? =
      user_params["state"] == "active" &&
        assigned.state == :rejected &&
        application != nil &&
        application.review_outcome == :rejected

    if activating_rejected_user? do
      {:noreply,
       socket
       |> assign(:pending_activation_params, user_params)
       |> assign(
         :override_rejection_form,
         to_form(override_rejection_changeset(%{}), as: "override")
       )}
    else
      do_save_user(socket, assigned, user_params, current_user)
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    assigned = socket.assigns[:selected_user]

    form_data =
      Accounts.User.update_user_with_address_changeset(assigned, user_params)

    {:noreply,
     assign_form(socket, form_data)
     |> assign(:first_name, user_params["first_name"])
     |> assign(:last_name, user_params["last_name"])
     |> assign(:role, user_params["role"])}
  end

  def handle_event(
        "validate_lifetime",
        %{"lifetime" => lifetime_params},
        socket
      ) do
    changeset = lifetime_params |> lifetime_membership_changeset()

    {:noreply,
     assign(socket, lifetime_form: to_form(changeset, as: "lifetime"))}
  end

  def handle_event(
        "update_lifetime_membership",
        %{"lifetime" => lifetime_params},
        socket
      ) do
    selected_user = socket.assigns[:selected_user]
    active_subscription = socket.assigns[:active_subscription]

    has_lifetime =
      lifetime_params["has_lifetime"] == "true" ||
        lifetime_params["has_lifetime"] == true

    update_params =
      if has_lifetime do
        case parse_datetime(lifetime_params["awarded_at"]) do
          {:ok, awarded_at} ->
            %{lifetime_membership_awarded_at: awarded_at}

          {:error, _} ->
            # Use current time if date parsing fails
            %{lifetime_membership_awarded_at: DateTime.utc_now()}
        end
      else
        %{lifetime_membership_awarded_at: nil}
      end

    case Accounts.update_user(
           selected_user,
           update_params,
           socket.assigns[:current_user]
         ) do
      {:ok, updated_user} ->
        # Reload user to get updated lifetime membership status
        updated_user = Accounts.get_user!(updated_user.id)

        # Invalidate membership cache when lifetime membership is updated
        # Also invalidate for sub-accounts since they inherit from primary user
        MembershipCache.invalidate_user(updated_user.id)
        sub_accounts = Accounts.get_sub_accounts(updated_user)

        Enum.each(sub_accounts, fn sub_account ->
          MembershipCache.invalidate_user(sub_account.id)
        end)

        # If awarding lifetime membership and user has an active :single or :family subscription,
        # cancel it in Stripe so they are no longer charged
        cancelled_subscription =
          if has_lifetime && active_subscription &&
               Subscriptions.active?(active_subscription) do
            membership_type =
              get_current_membership_type_from_subscription(active_subscription)

            if membership_type in [:single, :family] do
              case Subscriptions.cancel(active_subscription) do
                {:ok, cancelled_sub} ->
                  cancelled_sub

                {:error, error} ->
                  # Log error but don't fail the lifetime membership update
                  Ysc.Logging.warning(
                    "Failed to cancel subscription when awarding lifetime membership",
                    user_id: updated_user.id,
                    subscription_id: active_subscription.id,
                    error: inspect(error)
                  )

                  nil
              end
            else
              nil
            end
          else
            nil
          end

        # Reload subscription if it was cancelled
        updated_active_subscription =
          if cancelled_subscription do
            Repo.preload(cancelled_subscription, :subscription_items)
          else
            active_subscription
          end

        lifetime_changeset =
          %{
            has_lifetime: Accounts.has_lifetime_membership?(updated_user),
            awarded_at:
              updated_user.lifetime_membership_awarded_at || DateTime.utc_now()
          }
          |> lifetime_membership_changeset()

        flash_message =
          if has_lifetime do
            if cancelled_subscription do
              "Lifetime membership awarded and active subscription cancelled in Stripe"
            else
              "Lifetime membership awarded"
            end
          else
            "Lifetime membership revoked"
          end

        {:noreply,
         socket
         |> assign(:selected_user, updated_user)
         |> assign(:active_subscription, updated_active_subscription)
         |> assign(
           :has_lifetime_membership,
           Accounts.has_lifetime_membership?(updated_user)
         )
         |> assign(:lifetime_form, to_form(lifetime_changeset, as: "lifetime"))
         |> YscWeb.Flash.put_toast(:info, flash_message,
           title: "Lifetime membership"
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Failed to update lifetime membership: #{inspect(changeset.errors)}",
           title: "Lifetime membership"
         )}
    end
  end

  def handle_event(
        "validate_membership",
        %{"membership" => membership_params},
        socket
      ) do
    changeset = membership_params |> membership_changeset()

    {:noreply,
     assign(socket, membership_form: to_form(changeset, as: "membership"))}
  end

  def handle_event(
        "validate_membership_type",
        %{"membership_type" => membership_type_params},
        socket
      ) do
    changeset = membership_type_params |> membership_type_changeset()

    {:noreply,
     assign(socket,
       membership_type_form: to_form(changeset, as: "membership_type")
     )}
  end

  def handle_event(
        "validate_create_paid_membership",
        %{"create_paid_membership" => params},
        socket
      ) do
    changeset = params |> create_paid_membership_changeset()

    {:noreply,
     assign(socket,
       create_paid_membership_form:
         to_form(changeset, as: "create_paid_membership")
     )}
  end

  def handle_event(
        "create_paid_membership",
        %{"create_paid_membership" => params},
        socket
      ) do
    selected_user = socket.assigns[:selected_user]
    plan_id_str = params["plan_id"]

    if is_nil(plan_id_str) or plan_id_str == "" do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Please select a membership plan.",
         title: "Membership"
       )}
    else
      plan_id = String.to_existing_atom(plan_id_str)

      case Subscriptions.create_subscription_paid_out_of_band(
             selected_user,
             plan_id
           ) do
        {:ok, subscription} ->
          subscription = Repo.preload(subscription, :subscription_items)

          subscription_payments =
            Ledgers.get_payments_for_subscription(subscription.id)

          membership_changeset =
            %{period_end_date: subscription.current_period_end}
            |> membership_changeset()

          current_membership_type =
            get_current_membership_type_from_subscription(subscription)

          membership_type_changeset =
            %{membership_type: current_membership_type}
            |> membership_type_changeset()

          create_paid_membership_changeset =
            %{plan_id: plan_id_str}
            |> create_paid_membership_changeset()

          {:noreply,
           socket
           |> assign(:active_subscription, subscription)
           |> assign(:subscription_payments, subscription_payments)
           |> assign(
             :membership_form,
             to_form(membership_changeset, as: "membership")
           )
           |> assign(
             :membership_type_form,
             to_form(membership_type_changeset, as: "membership_type")
           )
           |> assign(
             :create_paid_membership_form,
             to_form(create_paid_membership_changeset,
               as: "create_paid_membership"
             )
           )
           |> YscWeb.Flash.put_toast(
             :info,
             "Membership subscription created (paid elsewhere).",
             title: "Subscription"
           )}

        {:error, :sub_accounts_cannot_create_subscriptions} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Sub-accounts cannot have their own subscriptions.",
             title: "Subscription"
           )}

        {:error, :user_already_has_active_subscription} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "User already has an active subscription.",
             title: "Subscription"
           )}

        {:error, :invalid_plan} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Invalid membership plan selected.",
             title: "Subscription"
           )}

        {:error, :could_not_create_stripe_customer} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Could not create or link Stripe customer for user.",
             title: "Subscription"
           )}

        {:error, err} ->
          message =
            if is_binary(err),
              do: err,
              else: "Failed to create subscription: #{inspect(err)}"

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, message, title: "Subscription")}
      end
    end
  end

  def handle_event(
        "update_membership_type",
        %{"membership_type" => membership_type_params},
        socket
      ) do
    active_subscription = socket.assigns[:active_subscription]

    if is_nil(active_subscription) do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "User does not have an active subscription to change",
         title: "Membership type"
       )}
    else
      new_membership_type_str = membership_type_params["membership_type"]

      if is_nil(new_membership_type_str) or new_membership_type_str == "" do
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Please select a membership type.",
           title: "Membership type"
         )}
      else
        new_membership_type = String.to_existing_atom(new_membership_type_str)

        # Get membership plans
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        # Find current and new plans
        current_type =
          get_current_membership_type_from_subscription(active_subscription)

        current_plan = Enum.find(membership_plans, &(&1.id == current_type))
        new_plan = Enum.find(membership_plans, &(&1.id == new_membership_type))

        cond do
          is_nil(new_plan) ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "Invalid membership type selected",
               title: "Membership type"
             )}

          is_nil(current_plan) ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "Could not determine current membership plan",
               title: "Membership type"
             )}

          current_type == new_membership_type ->
            # Same plan selected - call change_membership_plan to cancel any
            # scheduled downgrade (releases Stripe schedule)
            had_scheduled_downgrade =
              socket.assigns[:scheduled_downgrade_info] != nil

            same_price_id = current_plan.stripe_price_id

            case Subscriptions.change_membership_plan(
                   active_subscription,
                   same_price_id,
                   :upgrade
                 ) do
              {:ok, updated_subscription} ->
                updated_subscription =
                  updated_subscription |> Repo.preload(:subscription_items)

                if had_scheduled_downgrade do
                  MembershipCache.invalidate_user(active_subscription.user_id)

                  sub_accounts =
                    Accounts.get_sub_accounts(
                      Accounts.get_user!(active_subscription.user_id)
                    )

                  Enum.each(sub_accounts, fn sub ->
                    MembershipCache.invalidate_user(sub.id)
                  end)
                end

                message =
                  if had_scheduled_downgrade do
                    "Scheduled downgrade cancelled. User will keep their current plan."
                  else
                    "User is already on that membership plan."
                  end

                {:noreply,
                 socket
                 |> assign(:active_subscription, updated_subscription)
                 |> assign(:scheduled_downgrade_info, nil)
                 |> YscWeb.Flash.put_toast(:info, message,
                   title: "Membership type"
                 )}

              {:error, error} ->
                error_message =
                  case error do
                    %{message: msg} -> msg
                    msg when is_binary(msg) -> msg
                    _ -> "Failed to update membership"
                  end

                {:noreply,
                 socket
                 |> YscWeb.Flash.put_toast(
                   :error,
                   "Failed to update membership: #{error_message}",
                   title: "Membership type"
                 )}
            end

          true ->
            new_price_id = new_plan.stripe_price_id

            direction =
              if new_plan.amount > current_plan.amount,
                do: :upgrade,
                else: :downgrade

            case Subscriptions.change_membership_plan(
                   active_subscription,
                   new_price_id,
                   direction
                 ) do
              {:ok, updated_subscription} ->
                # Reload subscription with items
                updated_subscription =
                  updated_subscription
                  |> Repo.preload(:subscription_items)

                # Update membership type form
                membership_type_changeset =
                  %{membership_type: new_membership_type}
                  |> membership_type_changeset()

                {:noreply,
                 socket
                 |> assign(:active_subscription, updated_subscription)
                 |> assign(:scheduled_downgrade_info, nil)
                 |> assign(
                   :membership_type_form,
                   to_form(membership_type_changeset, as: "membership_type")
                 )
                 |> YscWeb.Flash.put_toast(
                   :info,
                   "Membership type changed from #{String.capitalize("#{current_type}")} to #{String.capitalize("#{new_membership_type}")}",
                   title: "Membership type"
                 )}

              {:scheduled, subscription} ->
                # Downgrade scheduled for next renewal - refresh schedule info
                scheduled_downgrade_info =
                  Subscriptions.get_scheduled_downgrade_info(subscription)

                {:noreply,
                 socket
                 |> assign(:scheduled_downgrade_info, scheduled_downgrade_info)
                 |> YscWeb.Flash.put_toast(
                   :info,
                   "Downgrade scheduled. Membership will change to #{String.capitalize("#{new_membership_type}")} at next renewal.",
                   title: "Membership type"
                 )}

              {:error, error} ->
                error_message =
                  case error do
                    %{message: msg} -> msg
                    msg when is_binary(msg) -> msg
                    _ -> "Failed to change membership type"
                  end

                {:noreply,
                 socket
                 |> YscWeb.Flash.put_toast(
                   :error,
                   "Failed to change membership type: #{error_message}",
                   title: "Membership type"
                 )}
            end
        end
      end
    end
  end

  def handle_event("unseal_bank_account", %{"id" => bank_account_id}, socket) do
    if socket.assigns.is_treasurer do
      selected_user = Accounts.get_user!(socket.assigns.user_id)

      case ExpenseReports.get_decrypted_bank_account(
             bank_account_id,
             selected_user
           ) do
        nil ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, "Bank account not found.",
             title: "Bank account"
           )
           |> assign(:unsealed_account_id, nil)
           |> assign(:unsealed_account, nil)}

        decrypted_account ->
          {:noreply,
           socket
           |> assign(:unsealed_account_id, bank_account_id)
           |> assign(:unsealed_account, decrypted_account)}
      end
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You don't have permission to do this.",
         title: "Bank account"
       )}
    end
  end

  def handle_event("seal_bank_account", _params, socket) do
    {:noreply,
     socket
     |> assign(:unsealed_account_id, nil)
     |> assign(:unsealed_account, nil)}
  end

  @dialyzer {:nowarn_function, handle_event: 3}
  def handle_event(
        "update_membership_period",
        %{"membership" => membership_params},
        socket
      ) do
    active_subscription = socket.assigns[:active_subscription]

    if active_subscription == nil do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "No active subscription found.",
         title: "Membership period"
       )}
    else
      case parse_datetime(membership_params["period_end_date"]) do
        {:ok, new_end_date} ->
          case Subscriptions.update_period_end(
                 active_subscription,
                 new_end_date
               ) do
            {:ok, updated_subscription} ->
              # Reload the subscription with items
              updated_subscription =
                Repo.preload(updated_subscription, :subscription_items)

              # Reload payments for the subscription
              subscription_payments =
                Ledgers.get_payments_for_subscription(updated_subscription.id)

              membership_changeset =
                %{period_end_date: updated_subscription.current_period_end}
                |> membership_changeset()

              # If the new renewal date falls within the 7-day reminder window,
              # send the reminder immediately — the daily cron only looks at
              # exactly 7 days out and would miss a date moved closer than that.
              selected_user = socket.assigns[:selected_user]

              MembershipRenewalReminderWorker.schedule_reminder_if_within_window(
                selected_user,
                updated_subscription
              )

              {:noreply,
               socket
               |> assign(:active_subscription, updated_subscription)
               |> assign(:subscription_payments, subscription_payments)
               |> assign(
                 :membership_form,
                 to_form(membership_changeset, as: "membership")
               )
               |> YscWeb.Flash.put_toast(
                 :info,
                 "Membership period updated successfully",
                 title: "Membership period"
               )}

            {:error, error} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Failed to update membership period: #{inspect(error)}",
                 title: "Membership period"
               )}
          end

        {:error, _reason} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, "Invalid date format.",
             title: "Membership period"
           )}
      end
    end
  end

  def handle_event("validate_note", %{"note" => note_params}, socket) do
    changeset = note_params |> note_changeset()

    {:noreply, assign(socket, note_form: to_form(changeset, as: "note"))}
  end

  def handle_event("create_note", %{"note" => note_params}, socket) do
    current_user = socket.assigns[:current_user]
    selected_user = socket.assigns[:selected_user]

    case Accounts.create_user_note(selected_user, note_params, current_user) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> assign(
           :note_form,
           to_form(note_changeset(%{category: "general"}), as: "note")
         )
         |> assign(:user_notes, Accounts.list_user_notes(selected_user.id))
         |> YscWeb.Flash.put_toast(:info, "Note added successfully",
           title: "Note"
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:note_form, to_form(changeset, as: "note"))
         |> YscWeb.Flash.put_toast(
           :error,
           "Failed to add note: #{format_changeset_errors(changeset)}",
           title: "Note"
         )}
    end
  end

  def handle_event("cancel_activation_override", _params, socket) do
    {:noreply,
     socket
     |> assign(:pending_activation_params, nil)
     |> assign(
       :override_rejection_form,
       to_form(override_rejection_changeset(%{}), as: "override")
     )}
  end

  def handle_event("validate_override_note", %{"override" => params}, socket) do
    changeset =
      params |> override_rejection_changeset() |> Map.put(:action, :validate)

    {:noreply,
     assign(
       socket,
       :override_rejection_form,
       to_form(changeset, as: "override")
     )}
  end

  def handle_event(
        "confirm_activation_override",
        %{"override" => params},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    selected_user = socket.assigns[:selected_user]
    pending_params = socket.assigns[:pending_activation_params]

    if is_nil(pending_params) or not is_map(pending_params) or
         map_size(pending_params) == 0 do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "Pending profile changes are missing. Save again from the profile tab, then confirm the override.",
         title: "Error"
       )}
    else
      changeset =
        params |> override_rejection_changeset() |> Map.put(:action, :validate)

      if changeset.valid? do
        note_text = Ecto.Changeset.get_field(changeset, :note)

        case Accounts.update_user_with_address_and_rejection_override_note(
               selected_user,
               pending_params,
               note_text,
               current_user
             ) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> assign(:pending_activation_params, nil)
             |> assign(
               :override_rejection_form,
               to_form(override_rejection_changeset(%{}), as: "override")
             )
             |> YscWeb.Flash.put_toast(
               :info,
               "User activated and override note saved.",
               title: "Profile"
             )
             |> push_patch(to: ~p"/admin/users/#{updated_user.id}/details")}

          {:error, %Ecto.Changeset{} = failed_changeset} ->
            Ysc.Logging.error(
              "Failed to activate user with rejection override: #{inspect(failed_changeset.errors)}"
            )

            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "Failed to activate user. Please try again.",
               title: "Error"
             )}

          {:error, reason} ->
            Ysc.Logging.error(
              "Rejected rejection override activation: #{inspect(reason)}"
            )

            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "You are not allowed to perform this action.",
               title: "Error"
             )}
        end
      else
        {:noreply,
         assign(
           socket,
           :override_rejection_form,
           to_form(changeset, as: "override")
         )}
      end
    end
  end

  def handle_event(
        "search_add_family_user",
        %{"query" => query, "relationship" => relationship},
        socket
      ) do
    query = String.trim(query)
    relationship = relationship || "child"

    results =
      if String.length(query) >= 2 do
        primary_user =
          socket.assigns.primary_user || socket.assigns.selected_user

        sub_ids = [
          primary_user.id | Enum.map(socket.assigns.sub_accounts, & &1.id)
        ]

        Accounts.search_users(query, limit: 8)
        |> Enum.reject(fn u -> u.id in sub_ids end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:add_family_user_search, query)
     |> assign(:add_family_user_results, results)
     |> assign(:add_family_user_relationship, relationship)}
  end

  def handle_event("search_add_family_user", %{"query" => query}, socket) do
    handle_event(
      "search_add_family_user",
      %{"query" => query, "relationship" => "child"},
      socket
    )
  end

  def handle_event("clear_add_family_user_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:add_family_user_search, "")
     |> assign(:add_family_user_results, [])}
  end

  def handle_event(
        "admin_link_family_user",
        %{"user_id" => user_id} = params,
        socket
      ) do
    primary_user = socket.assigns.primary_user || socket.assigns.selected_user
    relationship = Map.get(params, "relationship", "child")
    rel = if relationship == "spouse", do: :spouse, else: :child

    user_to_link =
      try do
        Accounts.get_user!(user_id)
      rescue
        Ecto.NoResultsError -> nil
      end

    if is_nil(user_to_link) do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "User not found.", title: "Link User")}
    else
      case Accounts.admin_link_user_to_family(primary_user, user_to_link,
             relationship: rel
           ) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> then(&load_family_data_for_membership(&1, primary_user.id))
           |> assign(:add_family_user_search, "")
           |> assign(:add_family_user_results, [])
           |> YscWeb.Flash.put_toast(
             :info,
             "#{user_to_link.first_name} #{user_to_link.last_name} has been added to the family membership.",
             title: "Link User"
           )}

        {:error, :cannot_link_self} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Cannot link the primary user to themselves.",
             title: "Link User"
           )}

        {:error, :already_linked_to_family} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "That user is already linked to another family membership.",
             title: "Link User"
           )}

        {:error, :not_primary_user} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Primary user must not be a sub-account.",
             title: "Link User"
           )}

        {:error, :primary_must_have_family_or_lifetime} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Primary user must have family or lifetime membership.",
             title: "Link User"
           )}

        {:error, :max_spouses_reached} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Cannot add another spouse. Maximum 1 spouse per family.",
             title: "Link User"
           )}

        {:error, :max_sub_accounts_reached} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Maximum number of family members (10) reached.",
             title: "Link User"
           )}

        {:error, _} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, "Failed to link user.",
             title: "Link User"
           )}
      end
    end
  end

  def handle_event(
        "admin_invite_family_user",
        %{"email" => email} = params,
        socket
      ) do
    primary_user = socket.assigns.primary_user || socket.assigns.selected_user
    email = String.trim(email)
    relationship = Map.get(params, "relationship", "child")
    rel = if relationship == "spouse", do: :spouse, else: :child

    cond do
      email == "" ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Please enter an email address.",
           title: "Invite User"
         )}

      not String.match?(email, ~r/^[^\s]+@[^\s]+$/) ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Please enter a valid email address.",
           title: "Invite User"
         )}

      true ->
        case FamilyInvites.create_invite(primary_user, email, relationship: rel) do
          {:ok, _invite} ->
            {:noreply,
             socket
             |> assign(:add_family_user_search, "")
             |> assign(:add_family_user_results, [])
             |> YscWeb.Flash.put_toast(:info, "Invitation sent to #{email}.",
               title: "Invite User"
             )}

          {:error, :pending_invite_exists} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "A pending invite already exists for that email.",
               title: "Invite User"
             )}

          {:error, :max_spouses_reached} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "Cannot add another spouse. Maximum 1 spouse per family.",
               title: "Invite User"
             )}

          {:error, :max_sub_accounts_reached} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               "Maximum number of family members (10) reached.",
               title: "Invite User"
             )}

          {:error, %Ecto.Changeset{} = changeset} ->
            msg = format_changeset_errors(changeset)

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:error, "Failed to send invite: #{msg}",
               title: "Invite User"
             )}

          {:error, reason} when is_atom(reason) ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:error, "Failed to send invite.",
               title: "Invite User"
             )}
        end
    end
  end

  def handle_event(
        "admin_cancel_family_invite",
        %{"invite_id" => invite_id},
        socket
      ) do
    primary_user = socket.assigns.primary_user || socket.assigns.selected_user

    case FamilyInvites.revoke_invite(invite_id, primary_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> then(&load_family_data_for_membership(&1, primary_user.id))
         |> YscWeb.Flash.put_toast(
           :info,
           "Invite cancelled. Invitee will be notified by email.",
           title: "Cancel Invite"
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invite not found.",
           title: "Cancel Invite"
         )}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Not authorized to cancel this invite.",
           title: "Cancel Invite"
         )}

      {:error, :already_accepted} ->
        {:noreply,
         socket
         |> then(&load_family_data_for_membership(&1, primary_user.id))
         |> YscWeb.Flash.put_toast(:error, "Invite was already accepted.",
           title: "Cancel Invite"
         )}
    end
  end

  def handle_event("admin_remove_family_user", %{"user_id" => user_id}, socket) do
    primary_user = socket.assigns.primary_user || socket.assigns.selected_user
    sub_account = Accounts.get_user!(user_id)

    case Accounts.remove_sub_account(sub_account, primary_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> then(&load_family_data_for_membership(&1, primary_user.id))
         |> YscWeb.Flash.put_toast(:info, "User removed from membership.",
           title: "Remove User"
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Failed to remove user.",
           title: "Remove User"
         )}
    end
  end

  defp do_save_user(socket, assigned, user_params, current_user) do
    case Accounts.update_user_with_address(assigned, user_params, current_user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "User updated.", title: "Profile")
         |> push_patch(to: ~p"/admin/users/#{updated_user.id}/details")}

      {:error, changeset} ->
        # Log the actual error for debugging
        Ysc.Logging.error(
          "Failed to update user with address: #{inspect(changeset.errors)}"
        )

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Failed to save: #{inspect(changeset.errors)}",
           title: "Save failed"
         )}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp membership_changeset(params) do
    types = %{period_end_date: :utc_datetime}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:period_end_date])
    |> Ecto.Changeset.validate_required([:period_end_date])
  end

  defp get_membership_plan_name(subscription) do
    plan_id = YscWeb.UserAuth.get_membership_plan_type(subscription)

    if plan_id do
      membership_plans = Application.get_env(:ysc, :membership_plans, [])

      case Enum.find(membership_plans, &(&1.id == plan_id)) do
        %{name: name} -> "#{name} Membership"
        _ -> "Unknown Membership"
      end
    else
      "Unknown Membership"
    end
  end

  defp format_family_relationship(nil), do: "Child"
  defp format_family_relationship("spouse"), do: "Spouse"
  defp format_family_relationship("child"), do: "Child"
  defp format_family_relationship(_), do: "Child"

  defp format_event_date(%DateTime{} = dt) do
    dt |> DateTime.to_date() |> Calendar.strftime("%b %d, %Y")
  end

  defp format_event_date(_), do: "—"

  defp format_utc_date(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime("%b %d, %Y")
  end

  defp format_utc_date(_), do: "—"

  defp format_utc_date_long(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime("%B %d, %Y")
  end

  defp format_utc_date_long(_), do: "—"

  defp format_datetime_for_display(nil), do: "N/A"

  defp format_datetime_for_display(%DateTime{} = datetime) do
    # Convert UTC datetime to America/Los_Angeles timezone
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("{YYYY}-{0M}-{0D} {h12}:{m} {AM} {Zabbr}")
  end

  defp format_datetime_local(%DateTime{} = datetime) do
    # Convert UTC datetime to America/Los_Angeles for datetime-local input
    # datetime-local inputs expect a naive datetime string in local timezone
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp format_datetime_local(nil), do: ""
  defp format_datetime_local(datetime) when is_binary(datetime), do: datetime

  defp fetch_subscription_data(user) do
    case Subscriptions.get_active_subscription(user) do
      nil ->
        {nil, []}

      sub ->
        sub = Repo.preload(sub, :subscription_items)
        payments = Ledgers.get_payments_for_subscription(sub.id)
        {sub, payments}
    end
  end

  defp fetch_application(user_id, current_user) do
    try do
      Accounts.get_signup_application_from_user_id!(user_id, current_user, [
        :reviewed_by
      ])
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp fetch_family_assigns(selected_user) do
    if Accounts.primary_user?(selected_user) and
         (Accounts.has_lifetime_membership?(selected_user) or
            has_family_subscription?(selected_user)) do
      user =
        Accounts.get_user!(selected_user.id, [
          :family_members,
          {:primary_user, :current_avatar},
          {:sub_accounts, :current_avatar},
          :current_avatar
        ])

      primary_user = Accounts.get_primary_user(user)

      sub_accounts =
        if primary_user, do: [], else: Accounts.get_sub_accounts(user)

      family_members =
        if primary_user do
          case Accounts.get_user!(primary_user.id, [:family_members]).family_members do
            %Ecto.Association.NotLoaded{} -> []
            members when is_list(members) -> members
            _ -> []
          end
        else
          case user.family_members do
            %Ecto.Association.NotLoaded{} -> []
            members when is_list(members) -> members
            _ -> []
          end
        end

      primary_for_invites = primary_user || user

      pending_invites =
        FamilyInvites.list_invites(primary_for_invites)
        |> Enum.filter(&is_nil(&1.accepted_at))

      %{
        primary_user: primary_user,
        sub_accounts: sub_accounts,
        family_members: family_members,
        pending_invites: pending_invites,
        can_manage_family: true
      }
    else
      primary_user = Accounts.get_primary_user(selected_user)

      if primary_user do
        primary_with_data =
          Accounts.get_user!(primary_user.id, [:family_members, :sub_accounts])

        all_sub_accounts = Accounts.get_sub_accounts(primary_with_data)
        siblings = Enum.reject(all_sub_accounts, &(&1.id == selected_user.id))

        family_members =
          case primary_with_data.family_members do
            %Ecto.Association.NotLoaded{} -> []
            members when is_list(members) -> members
            _ -> []
          end

        pending_invites =
          FamilyInvites.list_invites(primary_user)
          |> Enum.filter(&is_nil(&1.accepted_at))

        can_manage =
          Accounts.has_lifetime_membership?(primary_with_data) or
            has_family_subscription?(primary_with_data)

        %{
          primary_user: primary_user,
          sub_accounts: siblings,
          family_members: family_members,
          pending_invites: pending_invites,
          can_manage_family: can_manage
        }
      else
        %{
          primary_user: nil,
          sub_accounts: [],
          family_members: [],
          pending_invites: [],
          can_manage_family: false
        }
      end
    end
  end

  defp load_family_data_for_membership(socket, user_id) do
    selected_user = socket.assigns.selected_user

    # Only load family group if this user is a primary with family/lifetime
    if Accounts.primary_user?(selected_user) and
         (Accounts.has_lifetime_membership?(selected_user) or
            has_family_subscription?(selected_user)) do
      socket
      |> load_family_data(user_id)
      |> assign(:can_manage_family, true)
      |> assign(:add_family_user_search, "")
      |> assign(:add_family_user_results, [])
      |> assign(:add_family_user_relationship, "child")
    else
      primary_user = Accounts.get_primary_user(selected_user)

      socket
      |> assign(:primary_user, primary_user)
      |> assign(:can_manage_family, false)
      |> assign(:add_family_user_search, "")
      |> assign(:add_family_user_results, [])
      |> assign(:add_family_user_relationship, "child")
    end
  end

  defp has_family_subscription?(user) do
    subs =
      case user.subscriptions do
        %Ecto.Association.NotLoaded{} ->
          Ysc.Subscriptions.list_subscriptions(user)

        s when is_list(s) ->
          s

        _ ->
          []
      end

    subs
    |> Enum.filter(&Ysc.Subscriptions.valid?/1)
    |> Enum.any?(fn s ->
      s = Repo.preload(s, :subscription_items)

      case s.subscription_items do
        [item | _] ->
          plans = Application.get_env(:ysc, :membership_plans, [])

          Enum.any?(plans, fn p ->
            p.stripe_price_id == item.stripe_price_id and p.id == :family
          end)

        _ ->
          false
      end
    end)
  end

  defp load_family_data(socket, user_id) do
    selected_user =
      Accounts.get_user!(user_id, [
        :family_members,
        {:primary_user, :current_avatar},
        {:sub_accounts, :current_avatar},
        :current_avatar
      ])

    # Get primary user if this is a sub-account
    primary_user = Accounts.get_primary_user(selected_user)

    # Get sub accounts if this is a primary user (not a sub-account)
    sub_accounts =
      if primary_user do
        # If user is a sub-account, don't show sub_accounts
        []
      else
        # If user is a primary account, get their sub_accounts
        Accounts.get_sub_accounts(selected_user)
      end

    # Get family members (non-user entities)
    # If user is a sub-account, show family_members from the primary user
    # Otherwise, show family_members from the selected user
    family_members =
      if primary_user do
        # Load primary user with family_members
        primary_user_with_members =
          Accounts.get_user!(primary_user.id, [:family_members])

        case primary_user_with_members.family_members do
          %Ecto.Association.NotLoaded{} -> []
          members when is_list(members) -> members
          _ -> []
        end
      else
        # Get family_members from the selected user
        case selected_user.family_members do
          %Ecto.Association.NotLoaded{} -> []
          members when is_list(members) -> members
          _ -> []
        end
      end

    primary_for_invites = primary_user || selected_user

    pending_invites =
      FamilyInvites.list_invites(primary_for_invites)
      |> Enum.filter(&is_nil(&1.accepted_at))

    socket
    |> assign(:primary_user, primary_user)
    |> assign(:sub_accounts, sub_accounts)
    |> assign(:family_members, family_members)
    |> assign(:pending_invites, pending_invites)
  end

  defp user_state_to_badge_type(:active), do: "green"
  defp user_state_to_badge_type(:pending_approval), do: "yellow"
  defp user_state_to_badge_type(:rejected), do: "red"
  defp user_state_to_badge_type(:suspended), do: "red"
  defp user_state_to_badge_type(:deleted), do: "dark"
  defp user_state_to_badge_type(_), do: "default"

  defp user_state_to_readable(:pending_approval), do: "Pending Approval"
  defp user_state_to_readable(state), do: String.capitalize("#{state}")

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    # Parse datetime-local string (assumed to be in America/Los_Angeles timezone)
    # and convert to UTC for storage
    case NaiveDateTime.from_iso8601("#{datetime_string}:00") do
      {:ok, naive_dt} ->
        # Create DateTime in America/Los_Angeles timezone
        local_dt = DateTime.from_naive!(naive_dt, "America/Los_Angeles")
        # Convert to UTC for storage
        {:ok, DateTime.shift_zone!(local_dt, "Etc/UTC")}

      error ->
        error
    end
  end

  defp parse_datetime(_), do: {:error, :invalid_format}

  defp lifetime_membership_changeset(params) do
    types = %{has_lifetime: :boolean, awarded_at: :utc_datetime}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:has_lifetime, :awarded_at])
  end

  defp membership_type_changeset(params) do
    types = %{membership_type: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:membership_type])
    |> Ecto.Changeset.validate_required([:membership_type])
  end

  defp create_paid_membership_changeset(params) do
    types = %{plan_id: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:plan_id])
    |> Ecto.Changeset.validate_required([:plan_id])
    |> Ecto.Changeset.validate_inclusion(:plan_id, ["single", "family"])
  end

  defp get_current_membership_type_from_subscription(subscription),
    do: YscWeb.UserAuth.get_membership_plan_type(subscription)

  defp get_membership_type_options(_subscription) do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    # Filter out lifetime membership (it's handled separately)
    available_plans = Enum.filter(membership_plans, &(&1.id != :lifetime))

    Enum.map(available_plans, fn plan ->
      label = "#{plan.name} - $#{plan.amount}/year"
      value = Atom.to_string(plan.id)
      {label, value}
    end)
  end

  defp get_membership_type_options_for_create do
    membership_plans = Application.get_env(:ysc, :membership_plans, [])

    available_plans =
      Enum.filter(membership_plans, &(&1.id in [:single, :family]))

    Enum.map(available_plans, fn plan ->
      label = "#{plan.name} - $#{plan.amount}/year"
      value = Atom.to_string(plan.id)
      {label, value}
    end)
  end

  defp board_position_selected?(form, user) do
    persisted? = user.board_position != nil

    form_selected? =
      case form[:board_position].value do
        nil -> false
        "" -> false
        _ -> true
      end

    persisted? or form_selected?
  end

  defp extract_form_data(form) do
    # Get form parameters for current input values
    params = form.params || %{}

    # For billing_address, use the form params if available, otherwise fall back to struct values
    billing_address_params = params["billing_address"] || %{}

    # Get the current struct values as fallback
    billing_address_value = form[:billing_address].value

    billing_address_struct =
      cond do
        is_struct(billing_address_value, Ecto.Changeset) ->
          billing_address_value.data

        is_struct(billing_address_value, Ysc.Accounts.Address) ->
          billing_address_value

        is_nil(billing_address_value) ->
          %Ysc.Accounts.Address{}

        true ->
          %Ysc.Accounts.Address{}
      end

    # Normalize all values to strings for consistent comparison
    # For date_of_birth, convert Date struct to string if present
    date_of_birth_value =
      cond do
        params["date_of_birth"] ->
          params["date_of_birth"]

        form[:date_of_birth].value &&
            is_struct(form[:date_of_birth].value, Date) ->
          Date.to_iso8601(form[:date_of_birth].value)

        form[:date_of_birth].value ->
          to_string(form[:date_of_birth].value)

        true ->
          ""
      end

    %{
      "first_name" =>
        to_string(params["first_name"] || form[:first_name].value || ""),
      "last_name" =>
        to_string(params["last_name"] || form[:last_name].value || ""),
      "email" => to_string(params["email"] || form[:email].value || ""),
      "phone_number" =>
        to_string(params["phone_number"] || form[:phone_number].value || ""),
      "date_of_birth" => date_of_birth_value,
      "most_connected_country" =>
        to_string(
          params["most_connected_country"] ||
            form[:most_connected_country].value || ""
        ),
      "state" => to_string(params["state"] || form[:state].value || ""),
      "role" => to_string(params["role"] || form[:role].value || ""),
      "board_position" =>
        to_string(params["board_position"] || form[:board_position].value || ""),
      "board_bio" =>
        to_string(params["board_bio"] || form[:board_bio].value || ""),
      "billing_address" => %{
        "address" =>
          to_string(
            billing_address_params["address"] || billing_address_struct.address ||
              ""
          ),
        "city" =>
          to_string(
            billing_address_params["city"] || billing_address_struct.city || ""
          ),
        "region" =>
          to_string(
            billing_address_params["region"] || billing_address_struct.region ||
              ""
          ),
        "postal_code" =>
          to_string(
            billing_address_params["postal_code"] ||
              billing_address_struct.postal_code || ""
          ),
        "country" =>
          to_string(
            billing_address_params["country"] || billing_address_struct.country ||
              ""
          )
      }
    }
  end

  defp form_has_changes?(original_data, current_form) do
    current_data = extract_form_data(current_form)
    current_data != original_data
  end

  defp note_changeset(params) do
    types = %{note: :string, category: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:note, :category])
    |> Ecto.Changeset.validate_required([:note, :category])
    |> Ecto.Changeset.validate_length(:note, min: 1, max: 5000)
    |> Ecto.Changeset.validate_inclusion(:category, ["general", "violation"])
  end

  defp override_rejection_changeset(params) do
    types = %{note: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, [:note])
    |> Ecto.Changeset.validate_required([:note],
      message: "Please provide a reason for overriding the rejection."
    )
    |> Ecto.Changeset.validate_length(:note,
      min: 10,
      max: 5000,
      message: "Please provide a more detailed reason (at least 10 characters)."
    )
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp country_to_flag_class(nil), do: nil

  defp country_to_flag_class(code) when is_binary(code) do
    normalized = code |> String.trim() |> String.upcase() |> String.slice(0, 2)

    if normalized in ["SE", "NO", "FI", "DK", "IS", "US"] do
      "fi-#{String.downcase(normalized)}"
    else
      nil
    end
  end

  defp nordic_country_display_name(nil), do: ""

  defp nordic_country_display_name(code) when is_binary(code) do
    key = code |> String.trim() |> String.upcase() |> String.slice(0, 2)

    Map.get(
      %{
        "SE" => "Sweden",
        "NO" => "Norway",
        "FI" => "Finland",
        "DK" => "Denmark",
        "IS" => "Iceland",
        "US" => "United States"
      },
      key,
      code
    )
  end

  defp format_birth_date(nil), do: ""

  defp format_birth_date(%Date{} = date),
    do: Timex.format!(date, "%b %d, %Y", :strftime)

  defp format_birth_date(other), do: to_string(other)

  defp review_outcome_to_badge_type(:approved), do: "green"
  defp review_outcome_to_badge_type(:rejected), do: "red"
  defp review_outcome_to_badge_type(_), do: "default"

  defp entitlement_form_defaults do
    to_form(Entitlements.entitlement_grant_default_params(), as: :entitlement)
  end

  defp format_entitlement_status(:active), do: "Active"
  defp format_entitlement_status(:consumed), do: "Consumed"
  defp format_entitlement_status(:revoked), do: "Revoked"
  defp format_entitlement_status(:expired), do: "Expired"
  defp format_entitlement_status(other), do: to_string(other)

  defp admin_entitlement_summary(ent) do
    case ent.benefit_kind do
      :free_nights ->
        "#{ent.free_nights || "?"} free night(s), buyout cap #{format_admin_money(ent.buyout_max_discount)}"

      :percent_off ->
        "#{Decimal.to_string(ent.percent_off || Decimal.new(0))}% off, buyout cap #{format_admin_money(ent.buyout_max_discount)}"

      :fixed_amount_off ->
        "#{format_admin_money(ent.amount_off)} off"
    end
  end

  defp format_admin_money(nil), do: "—"
  defp format_admin_money(m), do: Ysc.MoneyHelper.format_money!(m)
end
