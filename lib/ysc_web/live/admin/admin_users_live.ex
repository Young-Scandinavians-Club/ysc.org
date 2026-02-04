defmodule YscWeb.AdminUsersLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Accounts

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
      <.modal
        :if={@live_action == :edit}
        id="edit-user-modal"
        on_cancel={JS.navigate(~p"/admin/users?#{@params}")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Edit User
        </h2>

        <div>
          <.user_avatar_image
            email={@selected_user.email}
            user_id={@selected_user.id}
            country={@selected_user.most_connected_country}
            class="w-32 h-32 rounded-full"
          />
        </div>

        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <.input field={@form[:email]} label="Email" />
          <.input field={@form[:first_name]} label="First Name" />
          <.input field={@form[:last_name]} label="Last Name" />
          <.input
            field={@form[:most_connected_country]}
            label="Most connected Nordic country:"
            type="select"
            options={["Sweden", "Norway", "Finland", "Denmark", "Iceland"]}
          />
          <.input
            type="select"
            field={@form[:state]}
            options={[
              "active",
              "pending_approval",
              "rejected",
              "suspended",
              "deleted"
            ]}
            label="State"
          />
          <.input
            type="select"
            field={@form[:role]}
            options={["member", "admin"]}
            label="State"
          />

          <div class="flex flex-row justify-end w-full pt-8">
            <button
              phx-click={JS.navigate(~p"/admin/users?#{@params}")}
              class="rounded hover:bg-zinc-100 py-2 px-3 mr-4 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-600"
            >
              Cancel
            </button>

            <.button phx-disable-with="Saving..." type="submit">
              <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Save changes
            </.button>
          </div>
        </.simple_form>
      </.modal>

      <.modal
        :if={@live_action == :review}
        id="review-user-modal"
        on_cancel={JS.navigate(~p"/admin/users?#{@params}")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Review Application
        </h2>

        <.alert_box :if={@selected_user.state != :pending_approval}>
          <p class="leading-6 text-sm text-zinc-800">
            This application has already been reviewed. It was
            <span>
              <.badge type={
                if @selected_user_application.review_outcome == :approved,
                  do: "green",
                  else: "red"
              }>
                <%= @selected_user_application.review_outcome %>
              </.badge>
            </span>
            on
            <span class="font-semibold">
              <%= Timex.format!(
                @selected_user_application.reviewed_at,
                "%Y-%m-%d",
                :strftime
              ) %>
            </span>
            by <span class="font-semibold"><%= @selected_user_application.reviewed_by.email %></span>.
          </p>
        </.alert_box>

        <p class="leading-6 text-sm text-zinc-800 mb-4 font-semibold">
          Submitted:
          <.badge>
            <%= "#{Timex.format!(Timex.Timezone.convert(@selected_user_application.completed, "America/Los_Angeles"), "{YYYY}-{0M}-{0D}")} (#{Timex.from_now(@selected_user_application.completed)})" %>
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
              <li :for={reason <- @selected_user_application.membership_eligibility}>
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

        <div class="flex flex-row justify-between w-full pt-8">
          <button
            :if={@selected_user.state == :pending_approval}
            phx-click="deny-application"
            phx-value-user-id={@selected_user.id}
            phx-value-application-id={@selected_user_application.id}
            class="phx-submit-loading:opacity-75 rounded bg-red-700 hover:bg-red-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
            data-confirm="You are about to reject this application. Are you sure?"
          >
            <.icon name="hero-no-symbol" class="w-5 h-5 mb-0.5 me-1" /> Reject
          </button>
          <button
            :if={@selected_user.state == :pending_approval}
            phx-click="approve-application"
            phx-value-user-id={@selected_user.id}
            phx-value-application-id={@selected_user_application.id}
            class="phx-submit-loading:opacity-75 rounded bg-green-700 hover:bg-green-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
          >
            <.icon name="hero-check" class="w-5 h-5 mb-0.5 me-1" /> Approve
          </button>
        </div>
      </.modal>

      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Users
        </h1>

        <.dropdown
          id="export-users-button"
          right={true}
          class="bg-blue-700 hover:bg-blue-800 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
        >
          <:button_block>
            <.tooltip tooltip_text="Export to CSV">
              <.icon name="hero-document-arrow-down" class="w-5 h-5 -mt-1" />
              <span class="me-1">Export</span>
            </.tooltip>
          </:button_block>
          <div class="w-full px-4 py-3">
            <h3 class="leading-8 font-semibold text-zinc-800 mb-2">
              Include Fields
            </h3>
            <form
              phx-submit="export-csv"
              class="flex flex-col gap-y-2 justify-between"
            >
              <%= for attr <- ~w(id email first_name last_name phone_number state)a do %>
                <.input
                  field={@form[attr]}
                  label={export_field_to_label(attr)}
                  type="checkbox"
                  checked={true}
                />
              <% end %>

              <div class="border-t border-zinc-100 py-2">
                <.input
                  field={@form[:only_subscribers]}
                  label="Only users with active memberships"
                  type="checkbox"
                  checked={false}
                />
              </div>
              <.button
                type="submit"
                phx-disable-with="Exporting..."
                disabled={
                  !(@export_status == :not_exporting || @export_status == :failed)
                }
              >
                <span :if={
                  @export_status == :not_exporting || @export_status == :failed
                }>
                  Export CSV
                </span>
                <.spinner
                  :if={@export_status == :in_progress}
                  class="w-6 h-6 mx-auto"
                />
                <.icon
                  :if={@export_status == :complete}
                  name="hero-check-circle"
                  class="w-6 h-6 flex-none fill-blue-600 text-zinc-200 mx-auto"
                />
              </.button>

              <.progress_bar
                :if={@export_status == :in_progress}
                progress={@export_progress}
              />

              <p
                :if={@export_status == :failed}
                class="flex gap-1 mt-1 text-sm leading-6 text-rose-600"
              >
                <.icon
                  name="hero-exclamation-circle-mini"
                  class="mt-0.5 w-5 h-5 flex-none"
                />
                <%= @export_error %>
              </p>

              <a
                :if={@export_status == :complete}
                class="flex gap-1 mt-1 text-sm leading-6"
                href={@file_export_path}
                target="_blank"
              >
                <.icon
                  name="hero-document-check"
                  class="mt-0.5 w-5 h-5 flex-none text-green-600"
                />
                <span
                  href={@file_export_path}
                  target="_blank"
                  class="text-blue-800 hover:underline"
                >
                  Download file
                </span>
              </a>
            </form>
          </div>
        </.dropdown>
      </div>

      <div class="w-full pt-4">
        <div>
          <form
            id="user-search-form"
            action=""
            novalidate=""
            role="search"
            phx-change="change"
            class="relative"
          >
            <div class="absolute inset-y-0 rtl:inset-r-0 start-0 flex items-center ps-3 pointer-events-none">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 text-zinc-500" />
            </div>
            <input
              id="user-search"
              type="search"
              name="search[query]"
              autocomplete="off"
              autocorrect="off"
              autocapitalize="off"
              enterkeyhint="search"
              spellcheck="false"
              placeholder="Search by name, email or phone number"
              value={
                case @params["search"] do
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
        <div class="py-6 w-full">
          <div id="admin-user-filters" class="pb-4 flex">
            <.dropdown
              id="filter-state-dropdown"
              class="group hover:bg-zinc-100"
              wide={false}
            >
              <:button_block>
                <.icon
                  name="hero-funnel"
                  class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
                /> Filters
              </:button_block>

              <div class="w-full px-4 py-3">
                <.filter_form
                  fields={[
                    state: [
                      label: "State",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Active", :active},
                        {"Pending Approval", :pending_approval},
                        {"Suspended", :suspended},
                        {"Rejected", :rejected},
                        {"Deleted", :deleted}
                      ]
                    ],
                    role: [
                      label: "Role",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Member", :member},
                        {"Admin", :admin}
                      ]
                    ],
                    board_position: [
                      label: "Board Position",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"President", :president},
                        {"Vice President", :vice_president},
                        {"Secretary", :secretary},
                        {"Treasurer", :treasurer},
                        {"Clear Lake Cabin Master", :clear_lake_cabin_master},
                        {"Tahoe Cabin Master", :tahoe_cabin_master},
                        {"Event Director", :event_director},
                        {"Member Outreach & Events", :member_outreach},
                        {"Membership Director", :membership_director}
                      ]
                    ],
                    membership_type: [
                      label: "Membership",
                      type: "checkgroup",
                      multiple: true,
                      op: :in,
                      options: [
                        {"Single", :single},
                        {"Family", :family},
                        {"Lifetime", :lifetime},
                        {"No Active Membership", :none}
                      ]
                    ]
                  ]}
                  meta={@meta}
                  id="user-filter-form"
                />
              </div>

              <div class="px-4 py-4">
                <button
                  class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80 w-full"
                  phx-click={JS.navigate(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </.dropdown>
          </div>
          <!-- Mobile Card View -->
          <div class="block md:hidden space-y-4">
            <%= for {_, user} <- @streams.users do %>
              <div class="bg-white rounded-lg border border-zinc-200 p-4 hover:shadow-md transition-shadow">
                <.link
                  navigate={
                    if user.state == :pending_approval,
                      do: ~p"/admin/users/#{user.id}/review?#{@params}",
                      else: ~p"/admin/users/#{user.id}/details"
                  }
                  class="block"
                >
                  <div class="flex items-start gap-3 mb-3">
                    <.user_card
                      email={user.email}
                      user_id={user.id}
                      most_connected_country={user.most_connected_country}
                      first_name={user.first_name}
                      last_name={user.last_name}
                    />
                  </div>
                </.link>

                <div class="space-y-2 mb-3">
                  <div :if={user.phone_number} class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">Phone:</span>
                    <span class="text-sm text-zinc-900">
                      <%= format_phone_number(user.phone_number) %>
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">State:</span>
                    <.badge type={user_state_to_badge_type(user.state)}>
                      <%= user_state_to_readable(user.state) %>
                    </.badge>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">Membership:</span>
                    <%= case get_active_membership_type(user) do %>
                      <% nil -> %>
                        <span class="text-sm text-zinc-400">—</span>
                      <% membership_type -> %>
                        <div class="flex items-center gap-1">
                          <.badge type="sky">
                            <%= String.capitalize("#{membership_type}") %>
                          </.badge>
                          <%= if membership_inherited?(user) do %>
                            <.tooltip tooltip_text="Membership inherited from parent account">
                              <.icon
                                name="hero-users"
                                class="w-4 h-4 text-zinc-500"
                              />
                            </.tooltip>
                          <% end %>
                        </div>
                    <% end %>
                  </div>
                </div>

                <div class="flex justify-end pt-3 border-t border-zinc-200">
                  <button
                    :if={user.state == :pending_approval}
                    phx-click={
                      JS.navigate(~p"/admin/users/#{user.id}/review?#{@params}")
                    }
                    class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                  >
                    Review
                  </button>
                  <button
                    :if={user.state != :pending_approval}
                    phx-click={JS.navigate(~p"/admin/users/#{user.id}/details")}
                    class="text-blue-600 font-semibold hover:underline cursor-pointer text-sm"
                  >
                    Edit
                  </button>
                </div>
              </div>
            <% end %>
            <!-- Mobile Empty State -->
            <div :if={@empty} class="py-16">
              <.empty_viking_state
                title="No results found"
                suggestion="Try adjusting your search term and filters."
              />

              <div class="px-4 py-4 flex items-center align-center justify-center">
                <button
                  class="rounded mx-auto hover:bg-zinc-100 w-36 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80"
                  phx-click={JS.navigate(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </div>
            <!-- Mobile Pagination -->
            <div :if={@meta && !@empty} class="pt-4">
              <Flop.Phoenix.pagination
                meta={@meta}
                path={~p"/admin/users"}
                opts={[
                  wrapper_attrs: [class: "flex items-center justify-center py-4"],
                  pagination_list_attrs: [
                    class: ["flex gap-0 order-2 justify-center items-center"]
                  ],
                  previous_link_attrs: [
                    class:
                      "order-1 flex justify-center items-center px-3 py-2 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                  ],
                  next_link_attrs: [
                    class:
                      "order-3 flex justify-center items-center px-3 py-2 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100"
                  ],
                  page_links: {:ellipsis, 3}
                ]}
              />
            </div>
          </div>
          <!-- Desktop Table View -->
          <div class="hidden md:block">
            <Flop.Phoenix.table
              id="admin_users_list"
              items={@streams.users}
              meta={@meta}
              path={~p"/admin/users"}
            >
              <:col :let={{_, user}} label="Name" field={:first_name}>
                <.link
                  navigate={
                    if user.state == :pending_approval,
                      do: ~p"/admin/users/#{user.id}/review?#{@params}",
                      else: ~p"/admin/users/#{user.id}/details"
                  }
                  class="cursor-pointer hover:opacity-80 transition-opacity"
                >
                  <.user_card
                    email={user.email}
                    user_id={user.id}
                    most_connected_country={user.most_connected_country}
                    first_name={user.first_name}
                    last_name={user.last_name}
                  />
                </.link>
              </:col>
              <:col :let={{_, user}} label="Phone" field={:phone_number}>
                <%= format_phone_number(user.phone_number) %>
              </:col>
              <:col
                :let={{_, user}}
                label="State"
                field={:state}
                thead_th_attrs={[class: "dance"]}
              >
                <.badge type={user_state_to_badge_type(user.state)}>
                  <%= user_state_to_readable(user.state) %>
                </.badge>
              </:col>
              <:col :let={{_, user}} label="Membership" field={:membership_type}>
                <%= case get_active_membership_type(user) do %>
                  <% nil -> %>
                    <span class="text-zinc-400">—</span>
                  <% membership_type -> %>
                    <div class="flex items-center gap-1">
                      <.badge type="sky">
                        <%= String.capitalize("#{membership_type}") %>
                      </.badge>
                      <%= if membership_inherited?(user) do %>
                        <.tooltip tooltip_text="Membership inherited from parent account">
                          <.icon name="hero-users" class="w-4 h-4 text-zinc-500" />
                        </.tooltip>
                      <% end %>
                    </div>
                <% end %>
              </:col>
              <:action :let={{_, user}} label="Action">
                <button
                  :if={user.state == :pending_approval}
                  phx-click={
                    JS.navigate(~p"/admin/users/#{user.id}/review?#{@params}")
                  }
                  class="text-blue-600 font-semibold hover:underline cursor-pointer"
                >
                  Review
                </button>
                <button
                  :if={user.state != :pending_approval}
                  phx-click={JS.navigate(~p"/admin/users/#{user.id}/details")}
                  class="text-blue-600 font-semibold hover:underline cursor-pointer"
                >
                  Edit
                </button>
              </:action>
            </Flop.Phoenix.table>

            <div :if={@empty} class="py-16">
              <.empty_viking_state
                title="No results found"
                suggestion="Try adjusting your search term and filters."
              />

              <div class="px-4 py-4 flex items-center align-center justify-center">
                <button
                  class="rounded mx-auto hover:bg-zinc-100 w-36 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80"
                  phx-click={JS.navigate(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </div>

            <Flop.Phoenix.pagination
              meta={@meta}
              path={~p"/admin/users"}
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
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns[:current_user]

    selected_user = Accounts.get_user!(id, [:family_members])

    application =
      Accounts.get_signup_application_from_user_id!(id, current_user, [
        :reviewed_by
      ])

    user_changeset = Accounts.User.update_user_changeset(selected_user, %{})

    {:ok,
     socket
     |> assign(:active_page, :members)
     |> assign(:selected_user, selected_user)
     |> assign(:selected_user_application, application)
     |> assign(:empty, false)
     |> assign(:page_title, "Users")
     |> assign(:params, params)
     |> assign(:export_status, :not_exporting)
     |> assign(:export_progress, 0)
     |> assign(:file_export_path, "")
     |> assign(:export_error, "Something went wrong")
     |> assign(form: to_form(%{}, as: "csv_export"))
     |> assign(form: to_form(user_changeset, as: "user"))}
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :members)
     |> assign(:empty, false)
     |> assign(:page_title, "Users")
     |> assign(:params, params)
     |> assign(:export_status, :not_exporting)
     |> assign(:export_progress, 0)
     |> assign(:file_export_path, "")
     |> assign(:export_error, "Something went wrong")
     |> assign(form: to_form(%{}, as: "csv_export"))}
  end

  @spec handle_params(
          %{
            optional(:__struct__) => Flop,
            optional(atom() | binary()) => any()
          },
          any(),
          atom()
          | %{
              :assigns => nil | maybe_improper_list() | map(),
              optional(any()) => any()
            }
        ) :: {:noreply, any()}
  def handle_params(params, _, socket) do
    search = params["search"]

    search_term =
      case search do
        %{"query" => query} when is_binary(query) -> query
        _ -> nil
      end

    case Accounts.list_paginated_users(params, search_term) do
      {:ok, {users, meta}} ->
        {:noreply,
         assign(socket, meta: meta)
         |> assign(:empty, no_results?(users))
         |> assign(:params, params)
         |> stream(:users, users, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/users")}
    end
  end

  @spec handle_event(
          <<_::48>>,
          map(),
          atom()
          | %{
              :assigns => nil | maybe_improper_list() | map(),
              optional(any()) => any()
            }
        ) :: {:noreply, any()}
  def handle_event("change", %{"search" => %{"query" => search_query}}, socket) do
    new_params =
      Map.put(socket.assigns[:params], "search", %{"query" => search_query})

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("change", %{"search" => search_query}, socket)
      when is_binary(search_query) do
    new_params =
      Map.put(socket.assigns[:params], "search", %{"query" => search_query})

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("export-csv", %{"csv_export" => fields}, socket) do
    reduced_fields =
      Enum.reduce(fields, [], fn {field, active}, acc ->
        field = String.to_existing_atom(field)
        if active == "true", do: [field | acc], else: acc
      end)

    reduced_fields = List.delete(reduced_fields, :only_subscribers)

    only_subscribed? =
      Enum.any?(fields, fn {field, active} ->
        field == "only_subscribers" && active == "true"
      end)

    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.subscribe(topic)

    # Async exporter
    %{
      channel: topic,
      fields: reduced_fields,
      only_subscribed: only_subscribed?
    }
    |> YscWeb.Workers.UserExporter.new()
    |> Oban.insert()

    {:noreply, socket |> assign(:export_status, :in_progress)}
  end

  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")

    updated_filters =
      Enum.reduce(params["filters"], %{}, fn {k, v}, red ->
        Map.put(red, k, maybe_update_filter(v))
      end)

    new_params = Map.replace(params, "filters", updated_filters)

    new_params =
      Map.put(new_params, "search", socket.assigns[:params]["search"])

    {:noreply,
     assign(socket, :params, new_params)
     |> push_patch(to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("approve-application", _params, socket) do
    user = socket.assigns[:selected_user]
    application = socket.assigns[:selected_user_application]
    current_user = socket.assigns[:current_user]

    case Accounts.record_application_outcome(
           :approved,
           user,
           application,
           current_user
         ) do
      :ok ->
        YscWeb.Emails.Notifier.schedule_email(
          user.email,
          "#{user.id}",
          "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)",
          "application_approved",
          %{first_name: user.first_name},
          """
          ==============================

          Hi #{user.email},

          Your application has been approved! 🎉

          To complete your membership, please pay your membership dues by visiting the link below:

          #{YscWeb.Endpoint.url()}/users/membership

          If you have any questions, please don't hesitate to contact the Membership Coordinator or reach out to us at memberships@ysc.org.


          Velkommen!

          Young Scandinavians Club

          ==============================
          """,
          user.id
        )

        # Schedule reminder emails if user hasn't paid
        YscWeb.Workers.MembershipPaymentReminderWorker.schedule_7day_reminder(
          user.id
        )

        YscWeb.Workers.MembershipPaymentReminderWorker.schedule_30day_reminder(
          user.id
        )

        {:noreply,
         socket
         |> redirect(to: ~p"/admin/users?#{socket.assigns[:params]}")
         |> put_flash(:info, "User was approved and is now a member!")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Something went wrong")}
    end
  end

  def handle_event("deny-application", _params, socket) do
    user = socket.assigns[:selected_user]
    application = socket.assigns[:selected_user_application]
    current_user = socket.assigns[:current_user]

    case Accounts.record_application_outcome(
           :rejected,
           user,
           application,
           current_user
         ) do
      :ok ->
        YscWeb.Emails.Notifier.schedule_email(
          user.email,
          "#{user.id}",
          "Update on your Young Scandinavians Club application",
          "application_rejected",
          %{first_name: user.first_name},
          """
          ==============================

          Hi #{user.email},

          We regret to inform you that your application has been rejected.

          If you have any questions, please don't hesitate to contact the Membership Coordinator or reach out to us at memberships@ysc.org.

          ==============================
          """,
          user.id
        )

        {:noreply,
         socket
         |> redirect(to: ~p"/admin/users?#{socket.assigns[:params]}")
         |> put_flash(:info, "User application was rejected!")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Something went wrong")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    assigned = socket.assigns[:selected_user]
    form_data = Accounts.change_user_registration(assigned, user_params)
    {:noreply, assign_form(socket, form_data)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "user_export:progress",
          payload: progress
        },
        socket
      ) do
    {:noreply, socket |> assign(:export_progress, progress)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "user_export:complete", payload: path},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.unsubscribe(topic)

    {:noreply,
     socket
     |> assign(:export_progress, 100)
     |> assign(:export_status, :complete)
     |> assign(:file_export_path, path)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "user_export:failed", payload: msg},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    topic = "exporter:#{current_user.id}"
    YscWeb.Endpoint.unsubscribe(topic)

    {:noreply,
     socket |> assign(:export_status, :failed) |> assign(:export_error, msg)}
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

  defp maybe_update_filter(%{"value" => [""]} = filter),
    do: Map.replace(filter, "value", "")

  defp maybe_update_filter(filter), do: filter

  defp no_results?([]), do: true
  defp no_results?(_), do: false

  defp export_field_to_label(:id), do: "User ID"
  defp export_field_to_label(:email), do: "Email"
  defp export_field_to_label(:first_name), do: "First Name"
  defp export_field_to_label(:last_name), do: "Last Name"
  defp export_field_to_label(:phone_number), do: "Phone Number"
  defp export_field_to_label(:state), do: "Account State"
  defp export_field_to_label(field), do: "#{field}"

  # "pending_approval", "rejected", "active", "suspended", "deleted"
  defp user_state_to_badge_type(:active), do: "green"
  defp user_state_to_badge_type(:pending_approval), do: "yellow"
  defp user_state_to_badge_type(:rejected), do: "red"
  defp user_state_to_badge_type(:suspended), do: "red"
  defp user_state_to_badge_type(:deleted), do: "dark"
  defp user_state_to_badge_type(_), do: "default"

  defp user_state_to_readable(:pending_approval), do: "Pending Approval"
  defp user_state_to_readable(state), do: String.capitalize("#{state}")

  defp get_active_membership_type(user) do
    YscWeb.UserAuth.get_user_membership_plan_type(user)
  end

  defp membership_inherited?(user) do
    Accounts.sub_account?(user) && get_active_membership_type(user) != nil
  end
end
