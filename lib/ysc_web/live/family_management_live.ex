defmodule YscWeb.FamilyManagementLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_sub_account = Accounts.sub_account?(user)

    if is_sub_account do
      # For sub-accounts, get the primary user and family group
      primary_user = Accounts.get_primary_user(user)
      family_group = Accounts.get_family_group(user)

      # Get all family members (excluding primary user, but including current user)
      other_family_members =
        family_group
        |> then(fn members ->
          if primary_user do
            Enum.reject(members, &(&1.id == primary_user.id))
          else
            members
          end
        end)

      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:is_sub_account, true)
       |> assign(:is_primary_user, false)
       |> assign(:primary_user, primary_user)
       |> assign(:other_family_members, other_family_members)
       |> assign(:live_action, :family)}
    else
      # For primary users, show management interface
      user = Accounts.get_user!(user.id, [:sub_accounts, :family_members])

      # Get family members from user (family_members belong to User, not SignupApplication)
      family_members =
        if Ecto.assoc_loaded?(user.family_members) do
          user.family_members
        else
          # Reload user with family_members if not loaded
          Accounts.get_user!(user.id, [:family_members]).family_members || []
        end

      invites = FamilyInvites.list_invites(user)

      invite_form =
        to_form(%{"email" => "", "family_member_id" => ""}, as: "invite")

      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:is_sub_account, false)
       |> assign(:is_primary_user, true)
       |> assign(:sub_accounts, Accounts.get_sub_accounts(user))
       |> assign(:invites, invites)
       |> assign(:family_members, family_members)
       |> assign(:invite_form, invite_form)
       |> assign(:can_send_invite, Accounts.can_send_family_invite?(user))
       |> assign(:live_action, :family)}
    end
  end

  @impl true
  def handle_event("validate_invite", %{"invite" => invite_params}, socket) do
    changeset =
      %{}
      |> Map.put("email", invite_params["email"] || "")
      |> Map.put("family_member_id", invite_params["family_member_id"] || "")
      |> to_form(as: "invite")

    {:noreply, assign(socket, invite_form: changeset)}
  end

  def handle_event("send_invite", %{"invite" => invite_params}, socket) do
    user = socket.assigns.current_user
    email = invite_params["email"]
    family_member_id = invite_params["family_member_id"]

    # If a family member is selected, include it in the invite
    opts =
      if family_member_id && family_member_id != "",
        do: [family_member_id: family_member_id],
        else: []

    case FamilyInvites.create_invite(user, email, opts) do
      {:ok, _invite} ->
        invites = FamilyInvites.list_invites(user)

        {:noreply,
         socket
         |> assign(:invites, invites)
         |> put_flash(:info, "Invitation sent to #{email}")}

      {:error, :user_not_active} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your account must be active to send invites."
         )}

      {:error, :invalid_membership_type} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You must have a family or lifetime membership to send invites."
         )}

      {:error, :max_sub_accounts_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You have reached the maximum number of sub-accounts (10)."
         )}

      {:error, :email_already_registered} ->
        {:noreply,
         put_flash(socket, :error, "This email is already registered.")}

      {:error, :pending_invite_exists} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A pending invitation already exists for this email."
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:invite_form, to_form(changeset))
         |> put_flash(
           :error,
           "Failed to send invitation. Please check the email address."
         )}
    end
  end

  def handle_event("revoke_invite", %{"invite_id" => invite_id}, socket) do
    user = socket.assigns.current_user

    case FamilyInvites.revoke_invite(invite_id, user) do
      {:ok, _} ->
        invites = FamilyInvites.list_invites(user)

        {:noreply,
         socket
         |> assign(:invites, invites)
         |> put_flash(:info, "Invitation revoked.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Invitation not found.")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You are not authorized to revoke this invitation."
         )}

      {:error, :already_accepted} ->
        {:noreply,
         put_flash(socket, :error, "This invitation has already been accepted.")}
    end
  end

  def handle_event("remove_sub_account", %{"user_id" => user_id}, socket) do
    user = socket.assigns.current_user
    sub_account = Accounts.get_user(user_id)

    if sub_account && sub_account.primary_user_id == user.id do
      case Accounts.remove_sub_account(sub_account, user) do
        {:ok, _} ->
          sub_accounts = Accounts.get_sub_accounts(user)

          {:noreply,
           socket
           |> assign(:sub_accounts, sub_accounts)
           |> put_flash(:info, "Sub-account removed successfully.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove sub-account.")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Sub-account not found or unauthorized.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-xl px-4 mx-auto py-8 lg:py-10">
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <ul class="flex-column space-y space-y-4 md:pr-10 text-sm font-medium text-zinc-600 md:me-4 mb-4 md:mb-0">
          <li>
            <h2 class="text-zinc-800 text-2xl font-semibold leading-8 mb-10">
              Account
            </h2>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :edit && "bg-blue-600 active text-zinc-100",
                @live_action != :edit && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-user" class="w-5 h-5 me-2" /> Profile
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/membership"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                (@live_action == :membership || @live_action == :payment_method) &&
                  "bg-blue-600 active text-zinc-100",
                @live_action != :membership && @live_action != :payment_method &&
                  "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-heart" class="w-5 h-5 me-2" /> Membership
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/payments"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :payments && "bg-blue-600 active text-zinc-100",
                @live_action != :payments && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-wallet" class="w-5 h-5 me-2" /> Payments
            </.link>
          </li>
          <%= if @current_user && (Accounts.primary_user?(@current_user) || Accounts.sub_account?(@current_user)) do %>
            <li>
              <.link
                navigate={~p"/users/settings/family"}
                class={[
                  "inline-flex items-center px-4 py-3 rounded w-full",
                  @live_action == :family && "bg-blue-600 active text-zinc-100",
                  @live_action != :family && "hover:bg-zinc-100 hover:text-zinc-900"
                ]}
              >
                <.icon name="hero-user-group" class="w-5 h-5 me-2" /> Family
              </.link>
            </li>
          <% end %>
          <li>
            <.link
              navigate={~p"/users/settings/security"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-shield-check" class="w-5 h-5 me-2" /> Security
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/notifications"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :notifications && "bg-blue-600 active text-zinc-100",
                @live_action != :notifications &&
                  "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" /> Notifications
            </.link>
          </li>
        </ul>

        <div class="text-medium px-2 text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div class="space-y-8">
            <%= if @is_sub_account do %>
              <!-- Sub-Account View: Show Primary User and Other Family Members -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">Your Family Group</h2>
                <p class="text-sm text-zinc-600">
                  You are part of a family membership. Below you can see the primary account holder and other family members.
                </p>
              </div>
              <!-- Primary User Section -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">
                  Primary Account Holder
                </h2>
                <%= if @primary_user do %>
                  <div class="bg-blue-50 border border-blue-200 rounded-md p-4">
                    <div class="flex items-center justify-between">
                      <div>
                        <p class="text-sm font-semibold text-blue-900">
                          <%= @primary_user.first_name %> <%= @primary_user.last_name %>
                        </p>
                        <p class="text-sm text-blue-700 mt-1">
                          <%= @primary_user.email %>
                        </p>
                        <p class="text-xs text-blue-600 mt-2">
                          <.icon
                            name="hero-star"
                            class="w-4 h-4 inline-block -mt-0.5 me-1"
                          /> Primary account holder - manages family membership
                        </p>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <p class="text-zinc-600 text-sm">
                    Primary account holder information not available.
                  </p>
                <% end %>
              </div>
              <!-- Other Family Members Section -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">
                  Other Family Members (<%= length(@other_family_members) %>)
                </h2>
                <%= if @other_family_members == [] do %>
                  <p class="text-zinc-600 text-sm">
                    No other family members in your group.
                  </p>
                <% else %>
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-zinc-200">
                      <thead class="bg-zinc-50">
                        <tr>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Name
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Email
                          </th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-zinc-200">
                        <tr :for={member <- @other_family_members}>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                            <%= member.first_name %> <%= member.last_name %>
                            <%= if member.id == @user.id do %>
                              <span class="text-xs text-zinc-500 ml-2">(You)</span>
                            <% end %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-500">
                            <%= member.email %>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            <% else %>
              <!-- Primary User View: Full Management Interface -->
              <!-- Family Management Overview -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">Family Management</h2>

                <p class="text-sm text-zinc-600">
                  As a primary account holder with a family or lifetime membership, you can invite family
                  members to share your membership benefits.
                </p>

                <%= if not @can_send_invite do %>
                  <div class="bg-amber-50 border border-amber-200 rounded-md p-4">
                    <p class="text-sm text-amber-800">
                      You cannot send invites at this time. Please ensure you have an active family or
                      lifetime membership and have not reached the maximum number of sub-accounts (10).
                    </p>
                  </div>
                <% end %>
              </div>
              <!-- Send Invitation Section -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">Send Invitation</h2>

                <.simple_form
                  for={@invite_form}
                  id="invite-form"
                  phx-submit="send_invite"
                  phx-change="validate_invite"
                >
                  <% valid_family_members =
                    Enum.filter(@family_members, fn fm ->
                      not is_nil(fm.first_name) && String.trim(fm.first_name) != "" &&
                        not is_nil(fm.last_name) && String.trim(fm.last_name) != ""
                    end) %>
                  <%= if valid_family_members != [] do %>
                    <.input
                      field={@invite_form[:family_member_id]}
                      type="select"
                      label="Select Family Member (Optional)"
                      options={
                        Enum.map(valid_family_members, fn fm ->
                          {"#{fm.first_name} #{fm.last_name}", fm.id}
                        end)
                      }
                      prompt="Select a family member..."
                      disabled={not @can_send_invite}
                    />
                    <p class="text-sm text-zinc-600 mt-1">
                      If you select a family member, their name will be included in the invitation email.
                    </p>
                  <% end %>

                  <.input
                    field={@invite_form[:email]}
                    type="email"
                    label="Email Address"
                    placeholder="family.member@example.com"
                    required
                    disabled={not @can_send_invite}
                  />

                  <:actions>
                    <.button
                      type="submit"
                      phx-disable-with="Sending..."
                      disabled={not @can_send_invite}
                    >
                      Send Invitation
                    </.button>
                  </:actions>
                </.simple_form>
              </div>
              <!-- Sub-Accounts Section -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">
                  Family Accounts (<%= length(@sub_accounts) %>)
                </h2>

                <%= if @sub_accounts == [] do %>
                  <p class="text-zinc-600 text-sm">No sub-accounts yet.</p>
                <% else %>
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-zinc-200">
                      <thead class="bg-zinc-50">
                        <tr>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Name
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Email
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Actions
                          </th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-zinc-200">
                        <tr :for={sub_account <- @sub_accounts}>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                            <%= sub_account.first_name %> <%= sub_account.last_name %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-500">
                            <%= sub_account.email %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm">
                            <button
                              phx-click="remove_sub_account"
                              phx-value-user_id={sub_account.id}
                              phx-disable-with="Removing..."
                              data-confirm="Are you sure you want to remove this sub-account? They will lose access to membership benefits."
                              class="text-red-600 hover:text-red-800"
                            >
                              Remove
                            </button>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
              <!-- Pending Invitations Section -->
              <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">Invitations</h2>

                <%= if @invites == [] do %>
                  <p class="text-zinc-600 text-sm">No family invitations.</p>
                <% else %>
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-zinc-200">
                      <thead class="bg-zinc-50">
                        <tr>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Email
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Status
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Expires
                          </th>
                          <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                            Actions
                          </th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-zinc-200">
                        <tr :for={invite <- @invites}>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                            <%= invite.email %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-500">
                            <%= if invite.accepted_at do %>
                              <span class="text-green-600">Accepted</span>
                            <% else %>
                              <span class="text-amber-600">Pending</span>
                            <% end %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-500">
                            <%= if invite.accepted_at do %>
                              Accepted <%= Calendar.strftime(
                                invite.accepted_at,
                                "%B %d, %Y"
                              ) %>
                            <% else %>
                              <%= Calendar.strftime(invite.expires_at, "%B %d, %Y") %>
                            <% end %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm">
                            <%= if is_nil(invite.accepted_at) do %>
                              <button
                                phx-click="revoke_invite"
                                phx-value-invite_id={invite.id}
                                phx-disable-with="Revoking..."
                                class="text-red-600 hover:text-red-800"
                              >
                                Revoke
                              </button>
                            <% end %>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
