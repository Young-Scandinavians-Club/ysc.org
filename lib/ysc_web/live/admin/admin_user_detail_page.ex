defmodule YscWeb.AdminUserDetailsLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Bookings
  alias Ysc.ExpenseReports
  alias Ysc.Ledgers
  alias Ysc.Messages
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Tickets

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
      <div class="flex flex-col justify-between py-6">
        <.back navigate={~p"/admin/users"}>Back</.back>

        <div class="flex flex-row items-center justify-between pt-4">
          <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
            <%= "#{String.capitalize(@first_name)} #{String.capitalize(@last_name)}" %>
          </h1>
          <.link
            href={~p"/admin/impersonate/#{@user_id}"}
            class="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors font-semibold"
          >
            <.icon name="hero-user-circle" class="w-5 h-5" /> Log in as User
          </.link>
        </div>

        <div class="w-full py-4">
          <div class="h-24">
            <.user_avatar_image
              email={@selected_user.email}
              user_id={@selected_user.id}
              country={@selected_user.most_connected_country}
              class="w-24 h-24 rounded-full"
            />
          </div>
        </div>

        <div class="pt-4">
          <div class="text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
            <ul class="flex flex-wrap -mb-px">
              <li class="me-2">
                <.link
                  navigate={~p"/admin/users/#{@user_id}/details"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/orders"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/bookings"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/application"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/membership"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/notifications"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/bank-accounts"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/family"}
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
                  navigate={~p"/admin/users/#{@user_id}/details/logs"}
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
                label="State"
              />
              <.input
                type="select"
                field={@form[:role]}
                options={[Member: "member", Admin: "admin"]}
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
          <div class="w-full">
            <Flop.Phoenix.table
              id="user_ticket_orders_list"
              items={@streams.ticket_orders}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
            >
              <:col :let={{_, order}} label="Order ID" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs">
                    <%= order.reference_id %>
                  </span>
                </.badge>
              </:col>
              <:col :let={{_, order}} label="Event" field={:inserted_at}>
                <%= if order.event do %>
                  <div class="text-sm font-semibold text-zinc-800">
                    <%= order.event.title %>
                  </div>
                  <%= if order.event.start_date do %>
                    <div class="text-xs text-zinc-500 mt-0.5">
                      <%= Calendar.strftime(order.event.start_date, "%b %d, %Y") %>
                    </div>
                  <% end %>
                <% else %>
                  <span class="text-zinc-400">—</span>
                <% end %>
              </:col>
              <:col :let={{_, order}} label="Tickets">
                <span class="text-sm text-zinc-600">
                  <%= length(order.tickets || []) %> ticket(s)
                </span>
              </:col>
              <:col :let={{_, order}} label="Amount" field={:total_amount}>
                <span class="text-sm font-medium text-zinc-900">
                  <%= Ysc.MoneyHelper.format_money!(order.total_amount) %>
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
                  <%= Calendar.strftime(order.inserted_at, "%b %d, %Y") %>
                </span>
              </:col>
            </Flop.Phoenix.table>

            <Flop.Phoenix.pagination
              :if={@ticket_orders_meta}
              meta={@ticket_orders_meta}
              path={~p"/admin/users/#{@user_id}/details/orders"}
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

        <div :if={@live_action == :bookings} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Bookings</h2>
          <div class="w-full">
            <Flop.Phoenix.table
              id="user_bookings_list"
              items={@streams.bookings}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
            >
              <:col :let={{_, booking}} label="Reference" field={:reference_id}>
                <.badge type="default" class="whitespace-nowrap">
                  <span class="font-mono text-xs flex-shrink-0 whitespace-nowrap">
                    <%= booking.reference_id %>
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
                <span class="text-sm text-zinc-600">
                  <%= booking.guests_count %>
                </span>
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
                            <%= String.capitalize(
                              to_string(room.room_category.name)
                            ) %>
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
                  <%= Calendar.strftime(booking.inserted_at, "%b %d, %Y") %>
                </span>
              </:col>
              <:action :let={{_, booking}} label="Action">
                <.link
                  navigate={~p"/admin/bookings/#{booking.id}"}
                  class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                >
                  View
                </.link>
              </:action>
            </Flop.Phoenix.table>

            <Flop.Phoenix.pagination
              :if={@bookings_meta}
              meta={@bookings_meta}
              path={~p"/admin/users/#{@user_id}/details/bookings"}
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

        <div :if={@live_action == :application} class="max-w-lg py-8 px-2">
          <div :if={@selected_user_application == nil}>
            <p class="text-sm text-zinc-800">No application found</p>
          </div>

          <div :if={@selected_user_application != nil}>
            <p class="leading-6 text-sm text-zinc-800 mb-4 font-semibold">
              Submitted:
              <.badge>
                <%= if @selected_user_application.completed do
                  date_str =
                    @selected_user_application.completed
                    |> DateTime.shift_zone!("America/Los_Angeles")
                    |> Timex.format!("{YYYY}-{0M}-{0D}")

                  "#{date_str} (#{Timex.from_now(@selected_user_application.completed)})"
                else
                  "N/A"
                end %>
              </.badge>
            </p>

            <p
              :if={@selected_user_application.review_outcome != nil}
              class="leading-6 text-sm text-zinc-800 mb-4 font-semibold"
            >
              Review outcome:
              <.badge>
                <%= @selected_user_application.review_outcome %>
              </.badge>
            </p>

            <p
              :if={@selected_user_application.reviewed_by != nil}
              class="leading-6 text-sm text-zinc-800 mb-4"
            >
              <span class="font-semibold">Reviewed by:</span> <%= @selected_user_application.reviewed_by.first_name %> <%= @selected_user_application.reviewed_by.last_name %> (<%= @selected_user_application.reviewed_by.email %>)
            </p>

            <p
              :if={@selected_user_application.reviewed_at != nil}
              class="leading-6 text-sm text-zinc-800 mb-4"
            >
              <span class="font-semibold">Reviewed at:</span>
              <.badge>
                <%= if @selected_user_application.reviewed_at do
                  format_datetime_for_display(
                    @selected_user_application.reviewed_at
                  )
                else
                  "N/A"
                end %>
              </.badge>
            </p>

            <h3 class="leading-6 text-zinc-800 font-semibold mb-2">
              Applicant Details
            </h3>
            <ul class="leading-6 text-zinc-800 text-sm pb-6">
              <li>
                <span class="font-semibold">Email:</span> <%= @selected_user.email %>
              </li>
              <li>
                <span class="font-semibold">Name:</span> <%= "#{@selected_user.first_name} #{@selected_user.last_name}" %>
              </li>
              <li>
                <span class="font-semibold">Birth date:</span> <%= @selected_user_application.birth_date %>
              </li>

              <li :if={length(@selected_user.family_members) > 0}>
                <p class="font-semibold">Family members:</p>
                <ul class="space-y-1 text-zinc-800 list-disc list-inside">
                  <li :for={family_member <- @selected_user.family_members}>
                    <span class="text-xs font-medium me-2 px-2.5 py-1 rounded text-left bg-blue-100 text-blue-800">
                      <%= String.capitalize("#{family_member.type}") %>
                    </span>
                    <%= "#{family_member.first_name} #{family_member.last_name} (#{family_member.birth_date})" %>
                  </li>
                </ul>
              </li>
            </ul>

            <h3 class="leading-6 text-zinc-800 font-semibold mb-2">
              Application Answers
            </h3>
            <ul class="leading-6 text-sm text-zinc-800 pb-6">
              <li>
                <span class="font-semibold">Membership type:</span> <%= @selected_user_application.membership_type %>
              </li>

              <li class="pt-2">
                <p class="font-semibold">Eligibility:</p>
                <ul class="space-y-1 text-zinc-800 list-disc list-inside">
                  <li :for={
                    reason <- @selected_user_application.membership_eligibility
                  }>
                    <%= Map.get(
                      Ysc.Accounts.SignupApplication.eligibility_lookup(),
                      reason
                    ) %>
                  </li>
                </ul>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Occupation:</span> <%= @selected_user_application.occupation %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Place of birth:</span> <%= @selected_user_application.place_of_birth %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Citizenship:</span> <%= @selected_user_application.citizenship %>
              </li>
              <li class="pt-2">
                <span class="font-semibold">Most connected Nordic country:</span> <%= @selected_user_application.most_connected_nordic_country %>
              </li>

              <li class="pt-2">
                <span class="font-semibold">Link to Scandinavia:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.link_to_scandinavia}
                  disabled={true}
                />
              </li>
              <li class="pt-2">
                <span class="font-semibold">Lived in Scandinavia:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.lived_in_scandinavia}
                  disabled={true}
                />
              </li>
              <li class="pt-2">
                <span class="font-semibold">Spoken languages:</span>
                <input
                  type="textarea"
                  class="mt-2 block w-full rounded text-zinc-900 sm:text-sm sm:leading-6 bg-zinc-100 px-2 py-3"
                  value={@selected_user_application.spoken_languages}
                  disabled={true}
                />
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :membership} class="max-w-lg py-8 px-2">
          <div class="space-y-6">
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
                  <%= if @selected_user.lifetime_membership_awarded_at do
                    format_datetime_for_display(
                      @selected_user.lifetime_membership_awarded_at
                    )
                  else
                    "N/A"
                  end %>
                </p>
                <p class="text-xs text-blue-700 pt-2">
                  Lifetime membership provides all Family membership perks and never expires.
                </p>
              </div>
            </div>

            <div
              :if={@active_subscription == nil && !@has_lifetime_membership}
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
              <div>
                <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                  Current Membership
                </h3>
                <div class="space-y-2 text-sm text-zinc-800">
                  <p>
                    <span class="font-semibold">Plan:</span>
                    <%= get_membership_plan_name(@active_subscription) %>
                  </p>
                  <p>
                    <span class="font-semibold">Status:</span>
                    <.badge>
                      <%= String.capitalize(@active_subscription.stripe_status) %>
                    </.badge>
                  </p>
                  <p>
                    <span class="font-semibold">Current Period Start:</span>
                    <%= if @active_subscription.current_period_start do
                      format_datetime_for_display(
                        @active_subscription.current_period_start
                      )
                    else
                      "N/A"
                    end %>
                  </p>
                  <p>
                    <span class="font-semibold">Current Period End:</span>
                    <%= if @active_subscription.current_period_end do
                      format_datetime_for_display(
                        @active_subscription.current_period_end
                      )
                    else
                      "N/A"
                    end %>
                  </p>
                  <p :if={@active_subscription.ends_at}>
                    <span class="font-semibold">Scheduled Cancellation:</span>
                    <%= format_datetime_for_display(@active_subscription.ends_at) %>
                  </p>
                  <p>
                    <span class="font-semibold">Stripe Subscription ID:</span>
                    <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                      <%= @active_subscription.stripe_id %>
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
                          <%= if payment.payment_date do
                            format_datetime_for_display(payment.payment_date)
                          else
                            "N/A"
                          end %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm font-medium text-zinc-900">
                          <%= Ysc.MoneyHelper.format_money!(payment.amount) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge>
                            <%= String.capitalize("#{payment.status}") %>
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            <%= if payment.external_payment_id do
                              String.slice(payment.external_payment_id, 0..20) <>
                                if(String.length(payment.external_payment_id) > 20,
                                  do: "...",
                                  else: ""
                                )
                            else
                              "N/A"
                            end %>
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <%= if payment.payment_method do
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
                          end %>
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
            <h2 class="text-2xl font-semibold leading-8 text-zinc-800">
              Bank Accounts
            </h2>
            <p class="text-sm text-zinc-600">
              View bank accounts for expense report reimbursements. Click "Unseal" to view encrypted account and routing numbers.
            </p>

            <div :if={length(@bank_accounts) > 0} class="space-y-4">
              <%= for bank_account <- @bank_accounts do %>
                <div class="border border-zinc-200 rounded-lg p-6">
                  <div class="flex justify-between items-start mb-4">
                    <div>
                      <h3 class="text-lg font-semibold text-zinc-900">
                        Account ending in ••••<%= bank_account.account_number_last_4 %>
                      </h3>
                      <p class="text-sm text-zinc-600 mt-1">
                        Added <%= Calendar.strftime(
                          bank_account.inserted_at,
                          "%B %d, %Y"
                        ) %>
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
                          <%= @unsealed_account.routing_number %>
                        </p>
                      </div>
                      <div>
                        <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                          Account Number
                        </p>
                        <p class="text-sm font-mono text-zinc-900 bg-zinc-50 p-2 rounded">
                          <%= @unsealed_account.account_number %>
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
              phx-update="ignore"
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
                          <%= format_datetime_for_display(notification.inserted_at) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.badge type={
                            if notification.message_type == :email,
                              do: "default",
                              else: "green"
                          }>
                            <%= notification.message_type
                            |> to_string()
                            |> String.upcase() %>
                          </.badge>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                            <%= notification.message_template %>
                          </code>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                          <%= if notification.email do %>
                            <%= notification.email %>
                          <% else %>
                            <%= if notification.phone_number do %>
                              <%= notification.phone_number %>
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
                      <%= format_datetime_for_display(
                        @selected_notification.inserted_at
                      ) %>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Type
                    </p>
                    <p class="text-sm text-zinc-800">
                      <.badge>
                        <%= @selected_notification.message_type
                        |> to_string()
                        |> String.capitalize() %>
                      </.badge>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Template
                    </p>
                    <p class="text-sm text-zinc-800">
                      <code class="text-xs bg-zinc-100 px-2 py-1 rounded">
                        <%= @selected_notification.message_template %>
                      </code>
                    </p>
                  </div>

                  <div>
                    <p class="text-xs font-medium text-zinc-500 uppercase tracking-wider mb-1">
                      Recipient
                    </p>
                    <p class="text-sm text-zinc-800">
                      <%= if @selected_notification.email do %>
                        <%= @selected_notification.email %>
                      <% else %>
                        <%= if @selected_notification.phone_number do %>
                          <%= @selected_notification.phone_number %>
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

        <div :if={@live_action == :family} class="max-w-full py-8 px-2">
          <h2 class="text-xl font-semibold text-zinc-800 mb-4">Family Members</h2>

          <div class="space-y-6">
            <!-- Primary User (Parent Account) -->
            <div :if={@primary_user} class="border border-zinc-200 rounded-lg p-6">
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                Primary Account
              </h3>
              <div class="space-y-3">
                <.link
                  navigate={~p"/admin/users/#{@primary_user.id}/details"}
                  class="block p-4 bg-zinc-50 rounded-lg hover:bg-zinc-100 transition-colors"
                >
                  <div class="flex items-center gap-4">
                    <.user_avatar_image
                      email={@primary_user.email}
                      user_id={@primary_user.id}
                      country={@primary_user.most_connected_country}
                      class="w-12 h-12 rounded-full"
                    />
                    <div class="flex-1">
                      <div class="font-semibold text-zinc-900">
                        <%= "#{@primary_user.first_name} #{@primary_user.last_name}" %>
                      </div>
                      <div class="text-sm text-zinc-600">
                        <%= @primary_user.email %>
                      </div>
                      <%= if @primary_user.phone_number do %>
                        <div class="text-sm text-zinc-500">
                          <%= format_phone_number(@primary_user.phone_number) %>
                        </div>
                      <% end %>
                    </div>
                    <.badge type={user_state_to_badge_type(@primary_user.state)}>
                      <%= user_state_to_readable(@primary_user.state) %>
                    </.badge>
                  </div>
                </.link>
              </div>
            </div>
            <!-- Sub Accounts -->
            <div
              :if={length(@sub_accounts) > 0}
              class="border border-zinc-200 rounded-lg p-6"
            >
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                Sub Accounts (<%= length(@sub_accounts) %>)
              </h3>
              <div class="space-y-3">
                <.link
                  :for={sub_account <- @sub_accounts}
                  navigate={~p"/admin/users/#{sub_account.id}/details"}
                  class="block p-4 bg-zinc-50 rounded-lg hover:bg-zinc-100 transition-colors"
                >
                  <div class="flex items-center gap-4">
                    <.user_avatar_image
                      email={sub_account.email}
                      user_id={sub_account.id}
                      country={sub_account.most_connected_country}
                      class="w-12 h-12 rounded-full"
                    />
                    <div class="flex-1">
                      <div class="font-semibold text-zinc-900">
                        <%= "#{sub_account.first_name} #{sub_account.last_name}" %>
                      </div>
                      <div class="text-sm text-zinc-600">
                        <%= sub_account.email %>
                      </div>
                      <%= if sub_account.phone_number do %>
                        <div class="text-sm text-zinc-500">
                          <%= format_phone_number(sub_account.phone_number) %>
                        </div>
                      <% end %>
                    </div>
                    <.badge type={user_state_to_badge_type(sub_account.state)}>
                      <%= user_state_to_readable(sub_account.state) %>
                    </.badge>
                  </div>
                </.link>
              </div>
            </div>
            <!-- Family Members (Non-User Entities) -->
            <div
              :if={length(@family_members) > 0}
              class="border border-zinc-200 rounded-lg p-6"
            >
              <h3 class="text-lg font-semibold text-zinc-800 mb-4">
                Family Members (<%= length(@family_members) %>)
              </h3>
              <div class="space-y-3">
                <div
                  :for={family_member <- @family_members}
                  class="p-4 bg-zinc-50 rounded-lg"
                >
                  <div class="flex items-center gap-4">
                    <div class="w-12 h-12 rounded-full bg-blue-100 flex items-center justify-center">
                      <span class="text-blue-600 font-semibold text-lg">
                        <%= String.first(family_member.first_name) %>
                      </span>
                    </div>
                    <div class="flex-1">
                      <div class="flex items-center gap-2">
                        <div class="font-semibold text-zinc-900">
                          <%= "#{family_member.first_name} #{family_member.last_name}" %>
                        </div>
                        <.badge type="sky" class="text-xs">
                          <%= String.capitalize("#{family_member.type}") %>
                        </.badge>
                      </div>
                      <%= if family_member.birth_date do %>
                        <div class="text-sm text-zinc-600">
                          Birth date: <%= Calendar.strftime(
                            family_member.birth_date,
                            "%B %d, %Y"
                          ) %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Empty State -->
            <div
              :if={
                !@primary_user && length(@sub_accounts) == 0 &&
                  length(@family_members) == 0
              }
              class="text-center py-12 border border-zinc-200 rounded-lg"
            >
              <p class="text-zinc-500">No family members found for this user.</p>
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
                                    <%= "#{note.created_by.first_name} #{note.created_by.last_name}" %>
                                  <% else %>
                                    Unknown Admin
                                  <% end %>
                                </p>
                                <.badge type={
                                  if note.category == :violation,
                                    do: "red",
                                    else: "default"
                                }>
                                  <%= String.capitalize("#{note.category}") %>
                                </.badge>
                              </div>
                              <p class="text-xs text-zinc-500 mt-0.5">
                                <%= if note.created_by do %>
                                  <%= note.created_by.email %>
                                <% end %>
                              </p>
                            </div>
                            <div class="text-xs text-zinc-500">
                              <%= format_datetime_for_display(note.inserted_at) %>
                            </div>
                          </div>
                          <div class="mt-3">
                            <p class="text-sm text-zinc-800 whitespace-pre-wrap">
                              <%= note.note %>
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
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    current_user = socket.assigns[:current_user]

    selected_user =
      Accounts.get_user!(id, [
        :family_members,
        :billing_address,
        :primary_user,
        :sub_accounts
      ])

    # Note: We don't pre-create billing_address here. cast_assoc will handle creating new records when billing_address is nil

    application =
      try do
        Accounts.get_signup_application_from_user_id!(id, current_user, [
          :reviewed_by
        ])
      rescue
        Ecto.NoResultsError -> nil
      end

    user_changeset =
      Accounts.User.update_user_with_address_changeset(selected_user, %{})

    user_form = to_form(user_changeset, as: "user")

    # Extract original data after form is created to ensure consistent formatting
    original_form_data = extract_form_data(user_form)

    # Load active subscription
    active_subscription = Subscriptions.get_active_subscription(selected_user)

    # Preload subscription items if subscription exists
    active_subscription =
      if active_subscription do
        Repo.preload(active_subscription, :subscription_items)
      else
        nil
      end

    # Load subscription payments if subscription exists
    subscription_payments =
      if active_subscription do
        Ledgers.get_payments_for_subscription(active_subscription.id)
      else
        []
      end

    # Check for lifetime membership
    has_lifetime = Accounts.has_lifetime_membership?(selected_user)

    # Check if current user is treasurer
    is_treasurer =
      current_user.board_position == :treasurer && current_user.state == :active

    # Load bank accounts if treasurer
    bank_accounts =
      if is_treasurer,
        do: ExpenseReports.list_bank_accounts(selected_user),
        else: []

    # Create membership form changeset
    membership_changeset =
      %{
        period_end_date:
          active_subscription && active_subscription.current_period_end
      }
      |> membership_changeset()

    # Create lifetime membership form changeset
    lifetime_changeset =
      %{
        has_lifetime: has_lifetime,
        awarded_at:
          selected_user.lifetime_membership_awarded_at || DateTime.utc_now()
      }
      |> lifetime_membership_changeset()

    # Create membership type form changeset
    current_membership_type =
      get_current_membership_type_from_subscription(active_subscription)

    membership_type_changeset =
      %{
        membership_type: current_membership_type
      }
      |> membership_type_changeset()

    create_paid_membership_changeset =
      %{plan_id: "single"}
      |> create_paid_membership_changeset()

    {:ok,
     socket
     |> assign(:user_id, id)
     |> assign(:first_name, selected_user.first_name)
     |> assign(:last_name, selected_user.last_name)
     |> assign(:role, selected_user.role)
     |> assign(:page_title, "Users")
     |> assign(:active_page, :members)
     |> assign(:selected_user, selected_user)
     |> assign(:selected_user_application, application)
     |> assign(:active_subscription, active_subscription)
     |> assign(:subscription_payments, subscription_payments)
     |> assign(:has_lifetime_membership, has_lifetime)
     |> assign(
       :membership_form,
       to_form(membership_changeset, as: "membership")
     )
     |> assign(
       :membership_type_form,
       to_form(membership_type_changeset, as: "membership_type")
     )
     |> assign(:lifetime_form, to_form(lifetime_changeset, as: "lifetime"))
     |> assign(
       :create_paid_membership_form,
       to_form(create_paid_membership_changeset, as: "create_paid_membership")
     )
     |> assign(:ticket_orders_meta, nil)
     |> assign(:bookings_meta, nil)
     |> assign(:notifications, [])
     |> assign(:selected_notification, nil)
     |> assign(:panel_width, nil)
     |> assign(:is_treasurer, is_treasurer)
     |> assign(:bank_accounts, bank_accounts)
     |> assign(:unsealed_account_id, nil)
     |> assign(:unsealed_account, nil)
     |> assign(:original_form_data, original_form_data)
     |> assign(:primary_user, nil)
     |> assign(:sub_accounts, [])
     |> assign(:family_members, [])
     |> assign(:user_notes, [])
     |> assign(
       :note_form,
       to_form(note_changeset(%{category: "general"}), as: "note")
     )
     |> assign(form: user_form)}
  end

  def handle_params(params, _uri, socket) do
    user_id = socket.assigns.user_id

    socket =
      case socket.assigns.live_action do
        :orders ->
          load_ticket_orders(socket, user_id, params)

        :bookings ->
          load_bookings(socket, user_id, params)

        :notifications ->
          load_notifications(socket, user_id)

        :bank_accounts ->
          load_bank_accounts(socket, user_id)

        :family ->
          load_family_data(socket, user_id)

        :logs ->
          load_user_notes(socket, user_id)

        _ ->
          socket
      end

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

  def handle_event("save", %{"user" => user_params}, socket) do
    current_user = socket.assigns[:current_user]
    assigned = socket.assigns[:selected_user]

    case Accounts.update_user_with_address(assigned, user_params, current_user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User updated")
         |> redirect(to: ~p"/admin/users/#{updated_user.id}/details")}

      {:error, changeset} ->
        # Log the actual error for debugging
        require Logger

        Logger.error(
          "Failed to update user with address: #{inspect(changeset.errors)}"
        )

        {:noreply,
         socket
         |> put_flash(:error, "Failed to save: #{inspect(changeset.errors)}")}
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
                  require Logger

                  Logger.warning(
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
         |> put_flash(:info, flash_message)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to update lifetime membership: #{inspect(changeset.errors)}"
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
      {:noreply, socket |> put_flash(:error, "Please select a membership plan")}
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
           |> put_flash(
             :info,
             "Membership subscription created (paid elsewhere)."
           )}

        {:error, :sub_accounts_cannot_create_subscriptions} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Sub-accounts cannot have their own subscriptions."
           )}

        {:error, :user_already_has_active_subscription} ->
          {:noreply,
           socket
           |> put_flash(:error, "User already has an active subscription.")}

        {:error, :invalid_plan} ->
          {:noreply,
           socket |> put_flash(:error, "Invalid membership plan selected.")}

        {:error, :could_not_create_stripe_customer} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Could not create or link Stripe customer for user."
           )}

        {:error, err} ->
          message =
            if is_binary(err),
              do: err,
              else: "Failed to create subscription: #{inspect(err)}"

          {:noreply, socket |> put_flash(:error, message)}
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
       |> put_flash(
         :error,
         "User does not have an active subscription to change"
       )}
    else
      new_membership_type_str = membership_type_params["membership_type"]

      if is_nil(new_membership_type_str) or new_membership_type_str == "" do
        {:noreply,
         socket |> put_flash(:error, "Please select a membership type")}
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
             socket |> put_flash(:error, "Invalid membership type selected")}

          current_type == new_membership_type ->
            {:noreply,
             socket
             |> put_flash(:info, "User is already on that membership plan")}

          is_nil(current_plan) ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not determine current membership plan")}

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
                 |> assign(
                   :membership_type_form,
                   to_form(membership_type_changeset, as: "membership_type")
                 )
                 |> put_flash(
                   :info,
                   "Membership type changed from #{String.capitalize("#{current_type}")} to #{String.capitalize("#{new_membership_type}")}"
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
                 |> put_flash(
                   :error,
                   "Failed to change membership type: #{error_message}"
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
           |> put_flash(:error, "Bank account not found")
           |> assign(:unsealed_account_id, nil)
           |> assign(:unsealed_account, nil)}

        decrypted_account ->
          {:noreply,
           socket
           |> assign(:unsealed_account_id, bank_account_id)
           |> assign(:unsealed_account, decrypted_account)}
      end
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  def handle_event("seal_bank_account", _params, socket) do
    {:noreply,
     socket
     |> assign(:unsealed_account_id, nil)
     |> assign(:unsealed_account, nil)}
  end

  def handle_event(
        "update_membership_period",
        %{"membership" => membership_params},
        socket
      ) do
    active_subscription = socket.assigns[:active_subscription]

    if active_subscription == nil do
      {:noreply, socket |> put_flash(:error, "No active subscription found")}
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

              {:noreply,
               socket
               |> assign(:active_subscription, updated_subscription)
               |> assign(:subscription_payments, subscription_payments)
               |> assign(
                 :membership_form,
                 to_form(membership_changeset, as: "membership")
               )
               |> put_flash(:info, "Membership period updated successfully")}

            {:error, error} ->
              {:noreply,
               socket
               |> put_flash(
                 :error,
                 "Failed to update membership period: #{inspect(error)}"
               )}
          end

        {:error, _reason} ->
          {:noreply, socket |> put_flash(:error, "Invalid date format")}
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
         |> put_flash(:info, "Note added successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:note_form, to_form(changeset, as: "note"))
         |> put_flash(
           :error,
           "Failed to add note: #{format_changeset_errors(changeset)}"
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

  defp load_bank_accounts(socket, user_id) do
    if socket.assigns.is_treasurer do
      selected_user = Accounts.get_user!(user_id)
      bank_accounts = ExpenseReports.list_bank_accounts(selected_user)
      assign(socket, :bank_accounts, bank_accounts)
    else
      socket
    end
  end

  defp load_family_data(socket, user_id) do
    selected_user =
      Accounts.get_user!(user_id, [
        :family_members,
        :primary_user,
        :sub_accounts
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

    socket
    |> assign(:primary_user, primary_user)
    |> assign(:sub_accounts, sub_accounts)
    |> assign(:family_members, family_members)
  end

  defp load_user_notes(socket, user_id) do
    user_notes = Accounts.list_user_notes(user_id)
    assign(socket, :user_notes, user_notes)
  end

  defp format_phone_number(phone_number) do
    case ExPhoneNumber.parse(phone_number, "") do
      {:ok, parsed} ->
        ExPhoneNumber.format(parsed, :international)

      {:error, _} ->
        # Return as-is if parsing fails
        phone_number
    end
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

  defp load_ticket_orders(socket, user_id, params) do
    case Tickets.list_user_ticket_orders_paginated(user_id, params) do
      {:ok, {orders, meta}} ->
        socket
        |> assign(:ticket_orders_meta, meta)
        |> stream(:ticket_orders, orders, reset: true)

      {:error, meta} ->
        socket
        |> assign(:ticket_orders_meta, meta)
        |> stream(:ticket_orders, [], reset: true)
    end
  end

  defp load_bookings(socket, user_id, params) do
    case Bookings.list_user_bookings_paginated(user_id, params) do
      {:ok, {bookings, meta}} ->
        socket
        |> assign(:bookings_meta, meta)
        |> stream(:bookings, bookings, reset: true)

      {:error, meta} ->
        socket
        |> assign(:bookings_meta, meta)
        |> stream(:bookings, [], reset: true)
    end
  end

  defp load_notifications(socket, user_id) do
    notifications = Messages.list_user_messages(user_id, limit: 100)
    assign(socket, :notifications, notifications)
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
end
