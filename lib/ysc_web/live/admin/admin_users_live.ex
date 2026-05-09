defmodule YscWeb.AdminUsersLive do
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Customers
  alias Ysc.Payments
  alias Ysc.Subscriptions

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <.modal
        :if={@live_action == :edit}
        id="edit-user-modal"
        on_cancel={JS.patch(~p"/admin/users?#{list_params_for_back(@params)}")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-4">
          Edit User
        </h2>

        <div>
          <.user_avatar_image
            user={@selected_user}
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
            label="Account Status"
          />
          <.input
            type="select"
            field={@form[:role]}
            options={["member", "admin", "volunteer"]}
            label="Role"
          />

          <div class="flex flex-row justify-end w-full pt-8">
            <button
              phx-click={
                JS.patch(~p"/admin/users?#{list_params_for_back(@params)}")
              }
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
        on_cancel={JS.patch(~p"/admin/users?#{list_params_for_back(@params)}")}
        show
      >
        <div class="max-w-2xl mx-auto">
          <div class="flex items-center justify-between border-b border-zinc-200 pb-4 mb-6 gap-4">
            <div class="min-w-0">
              <h2 class="text-2xl font-bold text-zinc-900">Review Application</h2>
              <p class="text-sm text-zinc-500 mt-0.5">
                {if @selected_user.state == :pending_approval do
                  "Submitted " <>
                    Timex.from_now(@selected_user_application.completed)
                else
                  "Reviewed " <>
                    format_utc_date(@selected_user_application.reviewed_at) <>
                    " by " <> @selected_user_application.reviewed_by.email
                end}
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

          <div class="space-y-6">
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
              </div>
            </section>

            <div
              :if={@selected_user.state == :pending_approval}
              class="pt-6 border-t border-zinc-200 flex flex-col-reverse sm:flex-row justify-between items-stretch sm:items-center gap-4"
            >
              <div class="flex flex-col gap-3">
                <button
                  type="button"
                  phx-click="toggle-reject-form"
                  class="text-sm font-semibold text-red-600 hover:text-red-700 py-2 px-4 text-left"
                >
                  Reject Application...
                </button>
                <div
                  :if={@show_reject_form}
                  class="rounded-md bg-zinc-50 border border-zinc-200 p-3"
                >
                  <.form
                    for={@rejection_form}
                    id="reject-application-form"
                    phx-submit="deny-application"
                    class="space-y-3"
                  >
                    <p class="text-sm text-zinc-600">
                      Optional rejection note (internal use only; not sent to the applicant).
                    </p>
                    <.input
                      field={@rejection_form[:note]}
                      type="textarea"
                      label="Rejection note (optional)"
                      class="mt-1 block w-full rounded border-zinc-300 text-zinc-900 sm:text-sm"
                      rows="3"
                    />
                    <button
                      type="submit"
                      data-confirm="You are about to reject this application. Are you sure?"
                      class="phx-submit-loading:opacity-75 rounded bg-red-600 hover:bg-red-700 py-2 px-3 text-sm font-semibold text-white transition-colors"
                    >
                      <.icon name="hero-no-symbol" class="w-4 h-4 inline me-1" />
                      Confirm Reject
                    </button>
                  </.form>
                </div>
              </div>
              <.button
                color="green"
                phx-click="approve-application"
                phx-value-user-id={@selected_user.id}
                phx-value-application-id={@selected_user_application.id}
                class="shrink-0"
              >
                <.icon name="hero-check" class="w-4 h-4 me-2" /> Approve Member
              </.button>
            </div>
          </div>
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
              <%= for attr <- ~w(id email first_name last_name phone_number state address)a do %>
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
                {@export_error}
              </p>

              <a
                :if={@export_status == :complete}
                class="flex gap-1 mt-1 text-sm leading-6"
                href={@file_export_path}
                target="_blank"
                rel="noopener noreferrer"
              >
                <.icon
                  name="hero-document-check"
                  class="mt-0.5 w-5 h-5 flex-none text-green-600"
                />
                <span
                  href={@file_export_path}
                  target="_blank"
                  rel="noopener noreferrer"
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
          <.admin_search_bar
            id="user-search-form"
            input_id="user-search"
            name="search[query]"
            value={
              case @params["search"] do
                %{"query" => query} -> query
                query when is_binary(query) -> query
                _ -> ""
              end
            }
            placeholder="Search by name, email or phone number"
            on_change="change"
          />
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
                      label: "Account Status",
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
                        {"Admin", :admin},
                        {"Volunteer", :volunteer}
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
                  phx-click={JS.patch(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </.dropdown>
          </div>
          <!-- Mobile Card View -->
          <div class="block md:hidden space-y-4">
            <%= for {_, user} <- @streams.users do %>
              <div
                class="bg-white rounded-lg border border-zinc-200 p-4 hover:shadow-md transition-shadow cursor-pointer"
                phx-click={
                  if user.state == :pending_approval,
                    do: JS.navigate(~p"/admin/users/#{user.id}/review?#{@params}"),
                    else:
                      JS.navigate(~p"/admin/users/#{user.id}/details?#{@params}")
                }
              >
                <div class="flex items-start gap-3 mb-3">
                  <.user_card user={user} />
                </div>

                <div class="space-y-2 mb-3">
                  <div :if={user.phone_number} class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">Phone:</span>
                    <span class="text-sm text-zinc-900">
                      {Ysc.Extensions.PhoneNumber.format_for_display(
                        user.phone_number
                      ) || user.phone_number}
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="text-sm text-zinc-600">Account Status:</span>
                    <.badge type={user_state_to_badge_type(user.state)}>
                      {user_state_to_readable(user.state)}
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
                            {String.capitalize("#{membership_type}")}
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
                  <.user_actions_dropdown
                    user={user}
                    params={@params}
                    menu_id={"user-actions-mob-#{user.id}"}
                  />
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
                  phx-click={JS.patch(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </div>
            <!-- Mobile Pagination -->
            <div :if={@meta && !@empty} class="pt-4">
              <Flop.Phoenix.pagination
                meta={@meta}
                path={~p"/admin/users?#{non_flop_params(@params)}"}
                class="flex items-center justify-center py-4 text-base"
                page_list_attrs={[
                  class: "flex gap-1 order-2 justify-center items-center"
                ]}
                page_list_item_attrs={[class: "list-none"]}
                page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
                ]}
                current_page_link_attrs={[
                  class:
                    "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
                ]}
                page_links={3}
              >
                <:previous attrs={[
                  class:
                    "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-left" class="w-4 h-4" />
                </:previous>
                <:next attrs={[
                  class:
                    "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
                ]}>
                  <.icon name="hero-chevron-right" class="w-4 h-4" />
                </:next>
              </Flop.Phoenix.pagination>
            </div>
          </div>
          <!-- Desktop Table View -->
          <div class="hidden md:block">
            <Flop.Phoenix.table
              id="admin_users_list"
              items={@streams.users}
              meta={@meta}
              path={~p"/admin/users?#{non_flop_params(@params)}"}
              row_click={
                fn {_, user} ->
                  if user.state == :pending_approval,
                    do: JS.navigate(~p"/admin/users/#{user.id}/review?#{@params}"),
                    else:
                      JS.navigate(~p"/admin/users/#{user.id}/details?#{@params}")
                end
              }
              opts={[tbody_tr_attrs: [class: "cursor-pointer"]]}
            >
              <:col :let={{_, user}} label="Name" field={:first_name}>
                <.user_card user={user} />
              </:col>
              <:col :let={{_, user}} label="Phone" field={:phone_number}>
                {Ysc.Extensions.PhoneNumber.format_for_display(user.phone_number) ||
                  user.phone_number}
              </:col>
              <:col
                :let={{_, user}}
                label="Account Status"
                field={:state}
                thead_th_attrs={[class: "dance"]}
              >
                <.badge type={user_state_to_badge_type(user.state)}>
                  {user_state_to_readable(user.state)}
                </.badge>
              </:col>
              <:col :let={{_, user}} label="Membership" field={:membership_type}>
                <%= case get_active_membership_type(user) do %>
                  <% nil -> %>
                    <span class="text-zinc-400">—</span>
                  <% membership_type -> %>
                    <div class="flex items-center gap-1">
                      <.badge type="sky">
                        {String.capitalize("#{membership_type}")}
                      </.badge>
                      <%= if membership_inherited?(user) do %>
                        <.tooltip tooltip_text="Membership inherited from parent account">
                          <.icon name="hero-users" class="w-4 h-4 text-zinc-500" />
                        </.tooltip>
                      <% end %>
                    </div>
                <% end %>
              </:col>
              <:action :let={{_, user}}>
                <.user_actions_dropdown
                  user={user}
                  params={@params}
                  menu_id={"user-actions-dt-#{user.id}"}
                />
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
                  phx-click={JS.patch(~p"/admin/users")}
                >
                  <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
                </button>
              </div>
            </div>

            <Flop.Phoenix.pagination
              meta={@meta}
              path={~p"/admin/users?#{non_flop_params(@params)}"}
              class="flex items-center justify-center py-10 text-base"
              page_list_attrs={[
                class: "flex gap-1 order-2 justify-center items-center"
              ]}
              page_list_item_attrs={[class: "list-none"]}
              page_link_attrs={[
                class:
                  "flex items-center justify-center w-9 h-9 text-sm font-medium text-zinc-600 rounded hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
              ]}
              current_page_link_attrs={[
                class:
                  "flex items-center justify-center w-9 h-9 text-sm font-semibold text-white bg-zinc-800 rounded pointer-events-none"
              ]}
              page_links={5}
            >
              <:previous attrs={[
                class:
                  "order-1 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
              ]}>
                <.icon name="hero-chevron-left" class="w-4 h-4" />
              </:previous>
              <:next attrs={[
                class:
                  "order-3 flex justify-center items-center w-9 h-9 text-sm font-semibold text-zinc-500 hover:text-zinc-800 rounded hover:bg-zinc-100 transition-colors"
              ]}>
                <.icon name="hero-chevron-right" class="w-4 h-4" />
              </:next>
            </Flop.Phoenix.pagination>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  attr :user, :map, required: true
  attr :params, :map, required: true
  attr :menu_id, :string, required: true

  def user_actions_dropdown(assigns) do
    ~H"""
    <div class="flex justify-end" onclick="event.stopPropagation()">
      <.dropdown
        id={@menu_id}
        right={true}
        class="min-w-0 !w-auto shrink-0 rounded-md px-1 py-1 text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <:button_block>
          <span class="sr-only">User actions</span>
          <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
        </:button_block>

        <div class="w-full divide-y divide-zinc-100 py-1 text-sm text-zinc-700">
          <ul class="py-1">
            <li :if={@user.state == :pending_approval}>
              <button
                id={"#{@menu_id}-review"}
                type="button"
                phx-click={JS.patch(~p"/admin/users/#{@user.id}/review?#{@params}")}
                class="flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100"
              >
                <.icon
                  name="hero-clipboard-document-check"
                  class="h-5 w-5 shrink-0 text-zinc-500"
                />
                <span>Review</span>
              </button>
            </li>
            <li :if={@user.state != :pending_approval}>
              <button
                id={"#{@menu_id}-edit"}
                type="button"
                phx-click={
                  JS.navigate(~p"/admin/users/#{@user.id}/details?#{@params}")
                }
                class="flex w-full items-center gap-2 px-4 py-2 text-left transition hover:bg-zinc-100"
              >
                <.icon
                  name="hero-pencil-square"
                  class="h-5 w-5 shrink-0 text-zinc-500"
                />
                <span>Edit</span>
              </button>
            </li>
          </ul>
        </div>
      </.dropdown>
    </div>
    """
  end

  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns[:current_user]

    selected_user = Accounts.get_user!(id, [:family_members, :current_avatar])

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
     |> assign(:focus_search_input, nil)
     |> assign(:export_status, :not_exporting)
     |> assign(:export_progress, 0)
     |> assign(:file_export_path, "")
     |> assign(:export_error, "Something went wrong")
     |> assign(form: to_form(%{}, as: "csv_export"))
     |> assign(form: to_form(user_changeset, as: "user"))
     |> assign(:rejection_form, to_form(%{"note" => ""}, as: "reject"))
     |> assign(:show_reject_form, false)}
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :members)
     |> assign(:empty, false)
     |> assign(:page_title, "Users")
     |> assign(:params, params)
     |> assign(:focus_search_input, nil)
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
         |> assign(:focus_search_input, nil)
         |> stream(:users, users, reset: true)}

      {:error, _meta} ->
        {:noreply, push_patch(socket, to: ~p"/admin/users")}
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

    {:noreply,
     socket
     |> assign(:focus_search_input, nil)
     |> push_patch(to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("change", %{"search" => search_query}, socket)
      when is_binary(search_query) do
    new_params =
      Map.put(socket.assigns[:params], "search", %{"query" => search_query})

    {:noreply,
     socket
     |> assign(:focus_search_input, nil)
     |> push_patch(to: ~p"/admin/users?#{new_params}")}
  end

  def handle_event("clear-search", %{"input-id" => input_id}, socket) do
    new_params = Map.delete(socket.assigns[:params], "search")

    {:noreply,
     socket
     |> assign(:focus_search_input, input_id)
     |> push_patch(to: ~p"/admin/users?#{new_params}")}
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

    existing = socket.assigns[:params]

    new_params =
      new_params
      |> then(fn p ->
        if existing["search"],
          do: Map.put(p, "search", existing["search"]),
          else: p
      end)
      |> then(fn p ->
        if existing["order_by"],
          do: Map.put(p, "order_by", existing["order_by"]),
          else: p
      end)
      |> then(fn p ->
        if existing["order_directions"],
          do: Map.put(p, "order_directions", existing["order_directions"]),
          else: p
      end)

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
      {:ok, approved_application} ->
        approval_status =
          if approved_application.family_invite_id do
            YscWeb.Emails.Notifier.schedule_email(
              user.email,
              "#{user.id}",
              "Velkommen! You're officially a Young Scandinavian 🎉",
              "application_approved_family_linked",
              %{first_name: user.first_name},
              """
              ==============================

              Hi #{user.email},

              Your application has been approved! 🎉

              Because you were invited to join a family membership, your membership is immediately active—no payment required.

              If you have any questions, please don't hesitate to contact the Membership Coordinator or reach out to us at memberships@ysc.org.

              Velkommen!

              Young Scandinavians Club

              ==============================
              """,
              user.id
            )

            :family_linked_email_sent
          else
            attempt_membership_activation_on_approval(
              user,
              approved_application
            )
          end

        toast_message =
          case approval_status do
            :activated ->
              "User was approved and membership activated!"

            :family_linked_email_sent ->
              "User was approved! Family membership invite email sent."

            :activation_failed ->
              "User was approved! They will receive an email with payment instructions."
          end

        {:noreply,
         socket
         |> push_patch(to: ~p"/admin/users?#{socket.assigns[:params]}")
         |> YscWeb.Flash.put_toast(
           :info,
           toast_message,
           title: "Application"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts
              |> Keyword.get(String.to_existing_atom(key), key)
              |> to_string()
            end)
          end)

        error_detail =
          Enum.map_join(errors, "; ", fn {field, msgs} ->
            "#{field}: #{Enum.join(msgs, ", ")}"
          end)

        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Could not approve application — #{error_detail}",
           title: "Application"
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Could not approve application. Please try again.",
           title: "Application"
         )}
    end
  end

  def handle_event("toggle-reject-form", _params, socket) do
    {:noreply,
     assign(socket, :show_reject_form, !socket.assigns[:show_reject_form])}
  end

  def handle_event("deny-application", params, socket) do
    user = socket.assigns[:selected_user]
    application = socket.assigns[:selected_user_application]
    current_user = socket.assigns[:current_user]

    reject_params = params["reject"] || %{}

    note =
      reject_params["note"]
      |> Kernel.||("")
      |> String.trim()

    if note != "" and String.length(note) > 5000 do
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "Rejection note must be 5000 characters or fewer.",
         title: "Application"
       )}
    else
      case Accounts.record_application_outcome(
             :rejected,
             user,
             application,
             current_user
           ) do
        :ok ->
          if note != "" do
            Accounts.create_user_note(
              user,
              %{"note" => note, "category" => "rejection"},
              current_user
            )
          end

          has_payment_method =
            not is_nil(Payments.get_default_payment_method(user))

          YscWeb.Emails.Notifier.schedule_email(
            user.email,
            "#{user.id}",
            "Update on your Young Scandinavians Club application",
            "application_rejected",
            %{
              first_name: user.first_name,
              has_payment_method: has_payment_method
            },
            """
            ==============================

            Hi #{user.email},

            We regret to inform you that your application has been rejected.

            #{if has_payment_method, do: "Your payment method on file has not been charged and will not be charged.", else: ""}

            If you have any questions, please don't hesitate to contact the Membership Coordinator or reach out to us at memberships@ysc.org.

            ==============================
            """,
            user.id
          )

          {:noreply,
           socket
           |> push_patch(to: ~p"/admin/users?#{socket.assigns[:params]}")
           |> YscWeb.Flash.put_toast(:info, "User application was rejected!",
             title: "Application"
           )}

        {:error, _} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Could not reject application. Please try again.",
             title: "Application"
           )}
      end
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

  def handle_info(_msg, socket), do: {:noreply, socket}

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

  defp export_field_to_label(:address),
    do: "Address (street, city, region, postal code, country)"

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

  defp country_to_flag_class(nil), do: nil

  defp country_to_flag_class(code) when is_binary(code) do
    normalized = code |> String.trim() |> String.upcase() |> String.slice(0, 2)

    if normalized in ["SE", "NO", "FI", "DK", "IS"] do
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
        "IS" => "Iceland"
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

  defp list_params_for_back(params) when is_map(params) do
    Map.drop(params, ["id"])
  end

  defp list_params_for_back(_), do: %{}

  @flop_keys ~w(order_by order_directions page page_size limit offset filters)
  defp non_flop_params(params) when is_map(params),
    do: Map.drop(params, @flop_keys)

  defp non_flop_params(_), do: %{}

  defp format_utc_date(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime("%b %d, %Y")
  end

  defp format_utc_date(_), do: "—"

  # Attempts to auto-activate a membership by charging the user's saved payment method.
  # Returns true if the subscription was successfully created, false otherwise.
  # Also sends the appropriate approval email in all cases.
  defp attempt_membership_activation_on_approval(user, approved_application) do
    default_pm = Payments.get_default_payment_method(user)

    if default_pm do
      membership_type = approved_application.membership_type || :single
      price_id = get_membership_price_id(membership_type)
      return_url = YscWeb.Endpoint.url() <> "/billing/user/#{user.id}/finalize"

      subscription_result =
        if price_id do
          Customers.create_subscription(
            user,
            return_url: return_url,
            prices: [%{price: price_id, quantity: 1}],
            default_payment_method: default_pm.provider_id,
            expand: ["latest_invoice"]
          )
        else
          Ysc.Logging.error(
            "No Stripe price ID found for membership type on approval",
            user_id: user.id,
            membership_type: inspect(membership_type)
          )

          {:error, :no_price_id}
        end

      case subscription_result do
        {:ok, stripe_subscription} ->
          case Subscriptions.create_subscription_from_stripe(
                 user,
                 stripe_subscription
               ) do
            {:ok, _} ->
              _ = Ysc.Accounts.MembershipCache.invalidate_user(user.id)

            {:error, reason} ->
              Ysc.Logging.error(
                "Failed to persist Stripe subscription locally on approval",
                user_id: user.id,
                stripe_subscription_id: stripe_subscription.id,
                reason: inspect(reason)
              )
          end

          YscWeb.Emails.Notifier.schedule_email(
            user.email,
            "approved_payment_success_#{user.id}",
            "Velkommen! Your YSC Membership is Active! 🎉",
            "application_approved_payment_success",
            %{first_name: user.first_name},
            """
            ==============================

            Hi #{user.email},

            Your application has been approved and your membership payment has been processed! 🎉

            Your membership is now active. Welcome to the Young Scandinavians Club!

            Visit: #{YscWeb.Endpoint.url()}

            If you have any questions, please don't hesitate to contact us at memberships@ysc.org.

            Velkommen!

            Young Scandinavians Club

            ==============================
            """,
            user.id
          )

          :activated

        {:error, reason} ->
          Ysc.Logging.error("Failed to auto-charge membership on approval",
            user_id: user.id,
            reason: inspect(reason)
          )

          send_approved_pay_now_email(user)
          schedule_payment_reminders(user.id)
          :activation_failed
      end
    else
      # No payment method on file
      send_approved_pay_now_email(user)
      schedule_payment_reminders(user.id)
      :activation_failed
    end
  end

  defp send_approved_pay_now_email(user) do
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
  end

  defp schedule_payment_reminders(user_id) do
    YscWeb.Workers.MembershipPaymentReminderWorker.schedule_7day_reminder(
      user_id
    )

    YscWeb.Workers.MembershipPaymentReminderWorker.schedule_30day_reminder(
      user_id
    )
  end

  defp get_membership_price_id(membership_type) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    Enum.find_value(plans, fn plan ->
      if plan.id == membership_type, do: plan[:stripe_price_id]
    end)
  end
end
