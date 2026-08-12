defmodule YscWeb.FamilyManagementLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyDisplay
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Accounts.FamilyMembers
  alias YscWeb.DateDisplay

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_sub_account = Accounts.sub_account?(user)

    socket =
      socket
      |> assign(:user, user)
      |> assign(:is_sub_account, is_sub_account)
      |> assign(:is_primary_user, not is_sub_account)
      |> assign(:primary_user, nil)
      |> assign(:other_family_members, [])
      |> assign(:sub_accounts, [])
      |> assign(:invites, [])
      |> assign(:family_members, [])
      |> assign(:family_member_form, nil)
      |> assign(:invite_target, nil)
      |> assign(:invite_form, empty_invite_form())
      |> assign(:can_send_invite, false)
      |> assign(:loading_family_data, true)
      |> assign(:page_title, "Family")
      |> assign(
        :meta_description,
        "Manage your family members and their linked accounts in Young Scandinavians Club."
      )
      |> assign(:live_action, :family)

    if connected?(socket) do
      send(self(), :load_family_management_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_family_management_data, socket) do
    user = socket.assigns.current_user

    socket =
      if socket.assigns.is_sub_account do
        user = Accounts.get_user!(user.id, primary_user: :sub_accounts)
        primary_user = user.primary_user

        other_family_members =
          if primary_user do
            (primary_user.sub_accounts || [])
            |> then(fn members -> [primary_user | members] end)
            |> Enum.reject(&(&1.id == primary_user.id))
          else
            []
          end

        socket
        |> assign(:user, user)
        |> assign(:primary_user, primary_user)
        |> assign(:other_family_members, other_family_members)
      else
        user =
          Accounts.get_user!(user.id, [
            :sub_accounts,
            :family_members
          ])

        socket
        |> assign(:user, user)
        |> assign(:sub_accounts, Accounts.get_sub_accounts(user))
        |> assign(:invites, FamilyInvites.list_invites(user))
        |> assign(:family_members, user.family_members || [])
        |> assign(:can_send_invite, Accounts.can_send_family_invite?(user))
      end

    {:noreply, assign(socket, :loading_family_data, false)}
  end

  @impl true
  def handle_event("open_invite_modal", %{"id" => id}, socket) do
    member =
      Enum.find(socket.assigns.family_members, fn fm ->
        to_string(fm.id) == to_string(id)
      end)

    if member do
      {:noreply,
       socket
       |> assign(:invite_target, member)
       |> assign(:invite_form, invite_form_for_member(member))}
    else
      {:noreply,
       YscWeb.Flash.put_toast(socket, :error, "Family member not found.",
         title: "Family"
       )}
    end
  end

  def handle_event("cancel_invite_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:invite_target, nil)
     |> assign(:invite_form, empty_invite_form())}
  end

  def handle_event("validate_invite", %{"invite" => invite_params}, socket) do
    family_member_id =
      invite_params["family_member_id"] ||
        (socket.assigns.invite_target &&
           to_string(socket.assigns.invite_target.id)) ||
        ""

    form =
      to_form(
        %{
          "email" => invite_params["email"] || "",
          "family_member_id" => family_member_id
        },
        as: "invite"
      )

    {:noreply, assign(socket, :invite_form, form)}
  end

  def handle_event("invite_family_member", %{"invite" => params}, socket) do
    do_invite_family_member(socket, params)
  end

  def handle_event("invite_family_member", params, socket) do
    do_invite_family_member(socket, params)
  end

  def handle_event("show_add_family_member", _params, socket) do
    form =
      to_form(
        %{
          "id" => "",
          "first_name" => "",
          "last_name" => "",
          "birth_date" => "",
          "relationship" => "child"
        },
        as: "family_member"
      )

    {:noreply, assign(socket, :family_member_form, form)}
  end

  def handle_event("edit_family_member", %{"id" => id}, socket) do
    member =
      Enum.find(socket.assigns.family_members, fn fm ->
        to_string(fm.id) == to_string(id)
      end)

    if member do
      form = to_form(family_member_form_params(member), as: "family_member")
      {:noreply, assign(socket, :family_member_form, form)}
    else
      {:noreply,
       YscWeb.Flash.put_toast(socket, :error, "Family member not found.",
         title: "Family"
       )}
    end
  end

  def handle_event("cancel_family_member_form", _params, socket) do
    {:noreply, assign(socket, :family_member_form, nil)}
  end

  def handle_event(
        "validate_family_member",
        %{"family_member" => params},
        socket
      ) do
    user = socket.assigns.user

    form =
      user
      |> FamilyMembers.changeset_for_params(params)
      |> to_form(as: "family_member")

    {:noreply, assign(socket, :family_member_form, form)}
  end

  def handle_event("save_family_member", %{"family_member" => params}, socket) do
    user = socket.assigns.user

    case FamilyMembers.validate_params(user, params) do
      {:ok, validated_params} ->
        case FamilyMembers.upsert_family_member(user, validated_params) do
          {:ok, _member} ->
            user = Accounts.get_user!(user.id, [:family_members])

            {:noreply,
             socket
             |> assign(:user, user)
             |> assign(:family_members, user.family_members || [])
             |> assign(:family_member_form, nil)
             |> YscWeb.Flash.put_toast(:info, "Family member saved.",
               title: "Family"
             )}

          {:error, changeset} ->
            form = to_form(changeset, as: "family_member")

            {:noreply,
             socket
             |> assign(:family_member_form, form)
             |> YscWeb.Flash.put_toast(
               :error,
               "Could not save family member. Please check the details.",
               title: "Family"
             )}
        end

      {:error, changeset} ->
        form = to_form(changeset, as: "family_member")
        {:noreply, assign(socket, :family_member_form, form)}
    end
  end

  def handle_event("delete_family_member", %{"id" => id}, socket) do
    user = socket.assigns.user

    case FamilyMembers.find_by_id(user, id) do
      %FamilyMember{} = member ->
        case FamilyMembers.delete_family_member(user, member) do
          {:ok, _} ->
            user = Accounts.get_user!(user.id, [:family_members])

            {:noreply,
             socket
             |> assign(:user, user)
             |> assign(:family_members, user.family_members || [])
             |> assign(:family_member_form, nil)
             |> YscWeb.Flash.put_toast(:info, "Family member removed.",
               title: "Family"
             )}

          {:error, _} ->
            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "We couldn't remove this family member. Please try again, or email info@ysc.org if this keeps happening.",
               title: "Family"
             )}
        end

      _ ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Family member not found.",
           title: "Family"
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
         |> YscWeb.Flash.put_toast(:info, "Invitation revoked.",
           title: "Family"
         )}

      {:error, :not_found} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Invitation not found.",
           title: "Family"
         )}

      {:error, :unauthorized} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You are not authorized to revoke this invitation.",
           title: "Family"
         )}

      {:error, :already_accepted} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "This invitation has already been accepted.",
           title: "Family"
         )}
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
           |> YscWeb.Flash.put_toast(
             :info,
             "Family member removed successfully.",
             title: "Family"
           )}

        {:error, _} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "We couldn't remove this family member. Please try again, or email info@ysc.org if this keeps happening.",
             title: "Family"
           )}
      end
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "That family member could not be found, or you are not allowed to remove them.",
         title: "Family"
       )}
    end
  end

  def handle_event("leave-family-membership", _params, socket) do
    user = socket.assigns.user

    case Accounts.leave_family_membership(user) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "You have left the family membership. You can purchase your own membership or join another family — click your name in the top-right corner and open Membership.",
           title: "Family"
         )
         |> redirect(to: ~p"/users/membership")}

      {:error, :not_sub_account} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You are not linked to a family membership.",
           title: "Family"
         )}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "We couldn't leave this family membership. Please try again, or email info@ysc.org if this keeps happening.",
           title: "Family"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-xl px-4 mx-auto py-8 lg:py-10">
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <.account_settings_nav
          current={:family}
          show_family_link?={
            @current_user &&
              (Accounts.primary_user?(@current_user) ||
                 Accounts.sub_account?(@current_user))
          }
        />

        <div class="text-medium px-2 text-zinc-500 w-full md:border-l md:border-zinc-100 md:pl-16">
          <div
            :if={@loading_family_data}
            id="family-management-loading"
            class="space-y-6"
            role="status"
            aria-live="polite"
          >
            <span class="sr-only">Loading family settings…</span>
            <.skeleton_block class="h-6 w-48 rounded" />
            <.skeleton_list_row
              :for={_ <- 1..2}
              class="flex items-center gap-3 p-4 border border-zinc-200 rounded-lg"
              leading_class="h-10 w-10 rounded-full shrink-0"
              lines={["h-4 w-40 rounded", "h-3 w-28 rounded"]}
            />
            <div class="space-y-2">
              <.skeleton_block class="h-4 w-32 rounded" />
              <.skeleton_block class="h-11 w-full rounded-lg" />
            </div>
          </div>
          <div :if={!@loading_family_data} class="space-y-8">
            <%= if @is_sub_account do %>
              <.sub_account_view
                primary_user={@primary_user}
                other_family_members={@other_family_members}
                user={@user}
              />
            <% else %>
              <.primary_account_view
                can_send_invite={@can_send_invite}
                family_members={@family_members}
                family_member_form={@family_member_form}
                invite_form={@invite_form}
                invite_target={@invite_target}
                invites={@invites}
                sub_accounts={@sub_accounts}
              />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :can_send_invite, :boolean, required: true
  attr :family_members, :list, required: true
  attr :family_member_form, :any, required: true
  attr :invite_form, :any, required: true
  attr :invite_target, :any, required: true
  attr :invites, :list, required: true
  attr :sub_accounts, :list, required: true

  defp primary_account_view(assigns) do
    pending_invites = Enum.filter(assigns.invites, &is_nil(&1.accepted_at))

    active_rows =
      active_member_rows(assigns.sub_accounts, assigns.family_members)

    assigns =
      assigns
      |> assign(:pending_invites, pending_invites)
      |> assign(:active_rows, active_rows)

    ~H"""
    <header class="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
      <div>
        <h1
          id="family-management-heading"
          class="text-zinc-900 font-bold text-2xl sm:text-3xl"
        >
          Family Management
        </h1>
        <p class="text-sm text-zinc-600 mt-2 max-w-2xl">
          Manage your family members and invite them to share your membership benefits.
          Add their details first, then send an invite so they can sign in.
        </p>
        <p id="family-member-limit" class="text-xs text-zinc-500 mt-2">
          Limit: 1 spouse or partner, up to 9 children
        </p>
      </div>
      <.button
        type="button"
        phx-click="show_add_family_member"
        id="add-family-member-button"
        class="shrink-0"
      >
        <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add Family Member
      </.button>
    </header>

    <%= if not @can_send_invite do %>
      <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
        <p class="text-sm text-amber-800">
          You can't send family invites right now. Invites require an active Family or Lifetime
          membership, and you can link up to 10 people who have their own login. If you have a
          Single membership or unpaid dues, update your membership first.
        </p>
      </div>
    <% end %>

    <section class="rounded border border-zinc-100 py-4 px-4 space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-zinc-900 font-bold text-xl">
          Family Members
          <span class="text-zinc-400 font-normal text-sm ml-2">
            ({length(@active_rows)})
          </span>
        </h2>
      </div>

      <p class="text-sm text-zinc-500">
        People you have added and people with their own login. Send an invite to anyone who does not have login access yet.
      </p>

      <%= if @active_rows == [] do %>
        <div class="text-center py-8">
          <p class="text-zinc-600 text-sm mb-4">
            No family members yet. Add someone to get started.
          </p>
          <.button type="button" phx-click="show_add_family_member">
            <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add Family Member
          </.button>
        </div>
      <% else %>
        <div class="overflow-x-auto sm:overflow-x-visible">
          <table
            class="min-w-full divide-y divide-zinc-200"
            id="active-family-members-table"
          >
            <thead class="bg-zinc-50">
              <tr>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Member
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Relationship
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Status
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr
                :for={row <- @active_rows}
                id={row.dom_id}
                class="hover:bg-zinc-50/50"
              >
                <td class="px-4 py-4 text-sm">
                  <div class="font-medium text-zinc-900">{row.name}</div>
                  <div class="text-xs text-zinc-500 mt-0.5">{row.subtitle}</div>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {row.relationship}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm">
                  <.badge type={row.badge_type}>{row.status_label}</.badge>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-right">
                  <.family_member_row_actions row={row} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>

    <section class="rounded border border-zinc-100 py-4 px-4 space-y-4">
      <h2 class="text-zinc-900 font-bold text-xl">
        Pending Invitations
        <span class="text-zinc-400 font-normal text-sm ml-2">
          ({length(@pending_invites)})
        </span>
      </h2>

      <%= if @pending_invites == [] do %>
        <div
          id="pending-invites-empty"
          class="rounded-lg border border-dashed border-zinc-300 p-8 text-center bg-zinc-50/50"
        >
          <.icon name="hero-envelope" class="w-8 h-8 text-zinc-400 mx-auto mb-2" />
          <p class="text-sm font-medium text-zinc-700">No pending invitations</p>
          <p class="text-xs text-zinc-500 mt-1">
            Invites you send will appear here until they are accepted.
          </p>
        </div>
      <% else %>
        <p class="text-sm text-zinc-500">
          Invitations awaiting acceptance. You can cancel any pending invite.
        </p>
        <div class="overflow-x-auto sm:overflow-x-visible">
          <table
            class="min-w-full divide-y divide-zinc-200"
            id="pending-invites-table"
          >
            <thead class="bg-zinc-50">
              <tr>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Email
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Relationship
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Expires
                </th>
                <th
                  scope="col"
                  class="px-4 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider"
                >
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr
                :for={invite <- @pending_invites}
                id={"pending-invite-row-#{invite.id}"}
              >
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900">
                  {invite.email}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {FamilyDisplay.relationship_label(invite.relationship)}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {DateDisplay.format_date_long(invite.expires_at)}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-right">
                  <.pending_invite_actions_dropdown invite={invite} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>

    <.modal
      :if={@family_member_form}
      id="family-member-modal"
      show
      on_cancel={JS.push("cancel_family_member_form")}
    >
      <.modal_title id="family-member-modal-title">
        <%= if @family_member_form[:id].value in [nil, ""] do %>
          Add Family Member
        <% else %>
          Edit Family Member
        <% end %>
      </.modal_title>

      <.form_notice kind={:info} id="family-member-form-notice">
        Saving here updates your account records only. To share membership benefits, send an invitation from the member row.
      </.form_notice>

      <.form
        for={@family_member_form}
        id="family-member-form"
        phx-change="validate_family_member"
        phx-submit="save_family_member"
        class="space-y-4"
      >
        <input
          type="hidden"
          name="family_member[id]"
          value={@family_member_form[:id].value}
        />

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@family_member_form[:first_name]}
            type="text"
            label="First Name"
            required
          />
          <.input
            field={@family_member_form[:last_name]}
            type="text"
            label="Last Name"
            required
          />
          <.input
            field={@family_member_form[:birth_date]}
            type="date"
            label="Date of Birth"
          />
          <.input
            field={@family_member_form[:relationship]}
            type="select"
            label="Relationship"
            options={[{"Child", "child"}, {"Spouse", "spouse"}]}
          />
        </div>

        <div class="flex justify-end gap-3 mt-8 pt-4 border-t border-zinc-200">
          <.button
            type="button"
            variant="outline"
            color="zinc"
            phx-click="cancel_family_member_form"
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving...">
            Save family member
          </.button>
        </div>
      </.form>
    </.modal>

    <.modal
      :if={@invite_target}
      id="invite-family-member-modal"
      show
      on_cancel={JS.push("cancel_invite_modal")}
    >
      <.modal_title id="invite-family-member-modal-title">
        Invite {@invite_target.first_name} {@invite_target.last_name}
      </.modal_title>

      <%= if @can_send_invite do %>
        <.form_notice kind={:info} id="invite-family-member-notice">
          We'll email an invitation so they can create a login and share your membership benefits.
          Relationship: {FamilyDisplay.relationship_label(@invite_target.type)}.
        </.form_notice>
      <% else %>
        <.form_notice kind={:error} id="invite-family-member-disabled-notice">
          You can't send family invites right now. Update your membership first.
        </.form_notice>
      <% end %>

      <.form
        for={@invite_form}
        id="invite-family-member-form"
        phx-change="validate_invite"
        phx-submit="invite_family_member"
        class="space-y-4"
      >
        <input
          type="hidden"
          name="invite[family_member_id]"
          value={@invite_target.id}
        />
        <.input
          field={@invite_form[:email]}
          type="email"
          label="Email Address"
          placeholder="family.member@example.com"
          required
          disabled={not @can_send_invite}
        />

        <div class="flex justify-end gap-3 mt-8 pt-4 border-t border-zinc-200">
          <.button
            type="button"
            variant="outline"
            color="zinc"
            phx-click="cancel_invite_modal"
          >
            Cancel
          </.button>
          <.button
            type="submit"
            phx-disable-with="Sending..."
            disabled={not @can_send_invite}
          >
            Send Invitation
          </.button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :primary_user, :any, required: true
  attr :other_family_members, :list, required: true
  attr :user, :any, required: true

  defp sub_account_view(assigns) do
    ~H"""
    <header>
      <h1 class="text-zinc-900 font-bold text-2xl sm:text-3xl">
        Your Family Group
      </h1>
      <p class="text-sm text-zinc-600 mt-2 max-w-2xl">
        You are part of a family membership. Below you can see who manages your family membership and the other members on your account.
      </p>
    </header>

    <section class="rounded border border-zinc-100 py-4 px-4 space-y-4">
      <h2 class="text-zinc-900 font-bold text-xl">Family membership manager</h2>
      <%= if @primary_user do %>
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <p class="text-sm font-semibold text-blue-900">
            {@primary_user.first_name} {@primary_user.last_name}
          </p>
          <p class="text-sm text-blue-700 mt-1">{@primary_user.email}</p>
          <p class="text-xs text-blue-600 mt-2">
            <.icon name="hero-star" class="w-4 h-4 inline-block -mt-0.5 me-1" />
            Manages your family membership and billing
          </p>
        </div>
      <% else %>
        <p class="text-zinc-500 text-sm italic">
          Family membership manager information is not available.
        </p>
      <% end %>
    </section>

    <section class="rounded border border-zinc-100 py-4 px-4 space-y-4">
      <h2 class="text-zinc-900 font-bold text-xl">
        Other Family Members
        <span class="text-zinc-400 font-normal text-sm ml-2">
          ({length(@other_family_members)})
        </span>
      </h2>
      <%= if @other_family_members == [] do %>
        <p class="text-zinc-500 text-sm italic">
          No other family members in your group.
        </p>
      <% else %>
        <div class="overflow-x-auto sm:overflow-x-visible">
          <table
            class="min-w-full divide-y divide-zinc-200"
            id="other-family-members-table"
          >
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Name
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Email
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={member <- @other_family_members}>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900">
                  {member.first_name} {member.last_name}
                  <%= if member.id == @user.id do %>
                    <span class="text-xs text-zinc-500 ml-2">(You)</span>
                  <% end %>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {member.email}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>

    <section class="rounded border border-zinc-100 py-4 px-4 space-y-4">
      <h2 class="text-zinc-900 font-bold text-xl">Leave Family Membership</h2>
      <p class="text-sm text-zinc-600">
        You can leave this family membership at any time. You will no longer share membership benefits and can purchase your own membership or join another family later.
      </p>
      <.button
        phx-click="leave-family-membership"
        phx-disable-with="Leaving..."
        color="red"
        variant="outline"
        data-confirm="Are you sure you want to leave this family membership? You will lose access to membership benefits until you purchase your own membership or join another family."
      >
        Leave family membership
      </.button>
    </section>
    """
  end

  attr :row, :map, required: true

  defp family_member_row_actions(assigns) do
    menu_id = "family-member-actions-#{assigns.row.kind}-#{assigns.row.id}"
    assigns = assign(assigns, :menu_id, menu_id)

    ~H"""
    <div class="inline-flex items-center justify-end gap-2">
      <.button
        :if={@row.kind == :roster}
        type="button"
        variant="outline"
        color="blue"
        id={"invite-family-member-button-#{@row.id}"}
        phx-click="open_invite_modal"
        phx-value-id={@row.id}
        class="!min-h-0 py-1.5 px-2.5 text-xs"
      >
        <.icon name="hero-envelope" class="w-4 h-4" /> Send Invite
      </.button>

      <.row_actions_dropdown id={@menu_id} label="Family member actions">
        <%= if @row.kind == :linked do %>
          <.dropdown_menu_item
            id={"#{@menu_id}-unlink"}
            icon="hero-user-minus"
            tone={:danger}
            phx-click="remove_sub_account"
            phx-value-user_id={@row.id}
            data-confirm="Are you sure you want to remove this family member from your membership? They will lose access to membership benefits and receive an email notification."
          >
            Unlink
          </.dropdown_menu_item>
        <% else %>
          <.dropdown_menu_item
            id={"#{@menu_id}-edit"}
            icon="hero-pencil-square"
            phx-click="edit_family_member"
            phx-value-id={@row.id}
          >
            Edit
          </.dropdown_menu_item>
          <.dropdown_menu_item
            id={"#{@menu_id}-remove"}
            icon="hero-trash"
            tone={:danger}
            phx-click="delete_family_member"
            phx-value-id={@row.id}
            data-confirm="Remove this family member from your list? This only removes their details from your account. It does not unlink anyone who has already accepted an invitation."
          >
            Remove
          </.dropdown_menu_item>
        <% end %>
      </.row_actions_dropdown>
    </div>
    """
  end

  attr :invite, :any, required: true

  defp pending_invite_actions_dropdown(assigns) do
    menu_id = "pending-invite-actions-#{assigns.invite.id}"
    assigns = assign(assigns, :menu_id, menu_id)

    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Invitation actions">
      <.dropdown_menu_item
        id={"#{@menu_id}-cancel"}
        icon="hero-x-mark"
        tone={:danger}
        phx-click="revoke_invite"
        phx-value-invite_id={@invite.id}
        data-confirm="Cancel this invite? The invitee will receive an email notification."
      >
        Cancel invite
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  defp do_invite_family_member(socket, params) do
    user = socket.assigns.current_user
    family_member_id = params["family_member_id"]
    email = String.trim(params["email"] || "")

    if email == "" do
      {:noreply,
       YscWeb.Flash.put_toast(socket, :error, "Please enter an email address.",
         title: "Family"
       )}
    else
      send_family_invite(socket, user, email, family_member_id)
    end
  end

  defp send_family_invite(socket, user, email, family_member_id) do
    member =
      Enum.find(socket.assigns.family_members, fn fm ->
        to_string(fm.id) == to_string(family_member_id)
      end)

    relationship =
      case member && member.type do
        :spouse -> :spouse
        _ -> :child
      end

    case FamilyInvites.create_invite(user, email,
           relationship: relationship,
           family_member_id: family_member_id
         ) do
      {:ok, _invite} ->
        invites = FamilyInvites.list_invites(user)

        {:noreply,
         socket
         |> assign(:invites, invites)
         |> assign(:invite_target, nil)
         |> assign(:invite_form, empty_invite_form())
         |> YscWeb.Flash.put_toast(:info, "Invitation sent to #{email}",
           title: "Family"
         )}

      {:error, reason} ->
        {:noreply, invite_error(socket, reason)}
    end
  end

  defp active_member_rows(sub_accounts, family_members) do
    linked_rows =
      Enum.map(sub_accounts, fn sub_account ->
        %{
          kind: :linked,
          id: sub_account.id,
          dom_id: "linked-family-member-row-#{sub_account.id}",
          name: "#{sub_account.first_name} #{sub_account.last_name}",
          subtitle: sub_account.email,
          relationship:
            FamilyDisplay.relationship_label(sub_account.family_relationship),
          status_label: "Linked Account",
          badge_type: "green"
        }
      end)

    roster_rows =
      Enum.map(family_members, fn member ->
        subtitle =
          case member.birth_date do
            %Date{} = date -> "DOB: #{DateDisplay.format_date_long(date)}"
            _ -> "Details saved"
          end

        %{
          kind: :roster,
          id: member.id,
          dom_id: "family-member-row-#{member.id}",
          name: "#{member.first_name} #{member.last_name}",
          subtitle: subtitle,
          relationship: FamilyDisplay.relationship_label(member.type),
          status_label: "No account yet",
          badge_type: "yellow"
        }
      end)

    linked_rows ++ roster_rows
  end

  defp empty_invite_form do
    to_form(%{"email" => "", "family_member_id" => ""}, as: "invite")
  end

  defp invite_form_for_member(%FamilyMember{} = member) do
    to_form(
      %{"email" => "", "family_member_id" => to_string(member.id)},
      as: "invite"
    )
  end

  defp invite_error(socket, reason) do
    message =
      case reason do
        :user_not_active ->
          "Your account must be approved by the board before you can send family invitations. We'll email you when your application is approved."

        :invalid_membership_type ->
          "You must have a family or lifetime membership to send invites."

        :max_sub_accounts_reached ->
          "You have reached the maximum number of family members (10)."

        :max_spouses_reached ->
          "You can only have one spouse on your family membership."

        :pending_invite_exists ->
          "A pending invitation already exists for this email."

        %Ecto.Changeset{} ->
          "Failed to send invitation. Please check the email address."

        _ ->
          "We couldn't send this invitation. Please try again, or email info@ysc.org if this keeps happening."
      end

    socket =
      case reason do
        %Ecto.Changeset{} = changeset ->
          assign(socket, :invite_form, to_form(changeset, as: "invite"))

        _ ->
          socket
      end

    YscWeb.Flash.put_toast(socket, :error, message, title: "Family")
  end

  defp family_member_form_params(%FamilyMember{} = member) do
    relationship =
      case member.type do
        :spouse -> "spouse"
        _ -> "child"
      end

    birth_date =
      case member.birth_date do
        %Date{} = date -> Date.to_iso8601(date)
        _ -> ""
      end

    %{
      "id" => to_string(member.id),
      "first_name" => member.first_name || "",
      "last_name" => member.last_name || "",
      "birth_date" => birth_date,
      "relationship" => relationship
    }
  end
end
