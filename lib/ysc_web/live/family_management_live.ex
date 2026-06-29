defmodule YscWeb.FamilyManagementLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Accounts.FamilyMembers
  alias Ysc.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_sub_account = Accounts.sub_account?(user)

    invite_form =
      to_form(
        %{"email" => "", "family_member_id" => "", "relationship" => "child"},
        as: "invite"
      )

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
      |> assign(:invite_form, invite_form)
      |> assign(:family_member_form, nil)
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
            :family_members,
            subscriptions: :subscription_items
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
  def handle_event("validate_invite", %{"invite" => invite_params}, socket) do
    changeset =
      %{}
      |> Map.put("email", invite_params["email"] || "")
      |> Map.put("family_member_id", invite_params["family_member_id"] || "")
      |> Map.put("relationship", invite_params["relationship"] || "child")
      |> to_form(as: "invite")

    {:noreply, assign(socket, invite_form: changeset)}
  end

  def handle_event("send_invite", %{"invite" => invite_params}, socket) do
    user = socket.assigns.current_user
    email = invite_params["email"]
    family_member_id = invite_params["family_member_id"]

    relationship =
      case invite_params["relationship"] do
        "spouse" -> :spouse
        _ -> :child
      end

    opts = [relationship: relationship]

    opts =
      if family_member_id && family_member_id != "",
        do: Keyword.put(opts, :family_member_id, family_member_id),
        else: opts

    case FamilyInvites.create_invite(user, email, opts) do
      {:ok, _invite} ->
        invites = FamilyInvites.list_invites(user)

        cleared_form =
          to_form(
            %{
              "email" => "",
              "family_member_id" => family_member_id || "",
              "relationship" => invite_params["relationship"] || "child"
            },
            as: "invite"
          )

        {:noreply,
         socket
         |> assign(:invites, invites)
         |> assign(:invite_form, cleared_form)
         |> YscWeb.Flash.put_toast(:info, "Invitation sent to #{email}",
           title: "Family"
         )}

      {:error, reason} ->
        {:noreply, invite_error(socket, reason)}
    end
  end

  def handle_event("invite_family_member", params, socket) do
    user = socket.assigns.current_user
    family_member_id = params["family_member_id"]
    email = params["email"]

    member =
      Enum.find(socket.assigns.family_members, fn fm ->
        to_string(fm.id) == to_string(family_member_id)
      end)

    relationship =
      case member && member.type do
        :spouse -> :spouse
        "spouse" -> :spouse
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
         |> YscWeb.Flash.put_toast(:info, "Invitation sent to #{email}",
           title: "Family"
         )}

      {:error, reason} ->
        {:noreply, invite_error(socket, reason)}
    end
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
        case Repo.delete(member) do
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
               "Could not remove this family member. Please try again.",
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
             "Could not remove this family member. Please try again.",
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
           "You have left the family membership. You can purchase your own membership or join another family from your Membership page.",
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
           "Could not leave the family membership. Please try again.",
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

        <div class="text-medium px-2 text-zinc-500 w-full md:border-l md:border-zinc-200 md:pl-10">
          <.async_section_loader
            :if={@loading_family_data}
            id="family-management-loading"
            label="Loading family settings..."
          />
          <div :if={!@loading_family_data} class="space-y-10">
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
  attr :invites, :list, required: true
  attr :sub_accounts, :list, required: true

  defp primary_account_view(assigns) do
    pending_invites = Enum.filter(assigns.invites, &is_nil(&1.accepted_at))
    assigns = assign(assigns, :pending_invites, pending_invites)

    ~H"""
    <header>
      <h1 class="text-zinc-900 font-bold text-2xl sm:text-3xl">
        Family Management
      </h1>
      <p class="text-sm text-zinc-600 mt-2 max-w-2xl">
        With a Family or Lifetime membership, you can add family members to your account and invite them to share your member benefits.
      </p>
      <%= if not @can_send_invite do %>
        <div class="mt-4 bg-amber-50 border border-amber-200 rounded-lg p-4">
          <p class="text-sm text-amber-800">
            You can't send family invites right now. Invites require an active Family or Lifetime
            membership, and you can link up to 10 people who have their own login. If you have a
            Single membership or unpaid dues, update your membership first.
          </p>
        </div>
      <% end %>
    </header>

    <section>
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-b border-zinc-200 pb-2 mb-4">
        <h2 class="text-zinc-900 font-semibold text-lg">
          Family Members on Your Account
          <span class="text-zinc-400 font-normal text-sm ml-2">
            ({length(@family_members)})
          </span>
        </h2>
        <.button
          :if={is_nil(@family_member_form)}
          type="button"
          variant="outline"
          phx-click="show_add_family_member"
          id="add-family-member-button"
        >
          <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add family member
        </.button>
      </div>

      <p class="text-xs text-zinc-500 mb-4">
        These are the family members listed on your account. You can add or edit them here without sending an invitation.
      </p>

      <%= if @family_member_form do %>
        <.family_member_editor form={@family_member_form} />
      <% end %>

      <%= if @family_members == [] and is_nil(@family_member_form) do %>
        <p class="text-zinc-500 text-sm italic">
          No family members on your account yet. Add a family member to keep their details on file.
        </p>
      <% else %>
        <div class="overflow-x-auto">
          <table
            class="min-w-full divide-y divide-zinc-200"
            id="account-family-members-table"
          >
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Name
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Relationship
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Date of Birth
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Invite
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr
                :for={member <- @family_members}
                id={"family-member-row-#{member.id}"}
              >
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900">
                  {member.first_name} {member.last_name}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {format_member_type(member.type)}
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                  {format_birth_date(member.birth_date)}
                </td>
                <td class="px-4 py-4 text-sm">
                  <form
                    id={"invite-family-member-form-#{member.id}"}
                    phx-submit="invite_family_member"
                    class="flex flex-col sm:flex-row gap-2 sm:items-center"
                  >
                    <input type="hidden" name="family_member_id" value={member.id} />
                    <input
                      type="email"
                      name="email"
                      required
                      disabled={not @can_send_invite}
                      placeholder="Email address"
                      class="block w-full sm:w-44 h-9 rounded border-zinc-300 focus:border-blue-500 focus:ring-blue-500 text-sm disabled:bg-zinc-100 disabled:text-zinc-400"
                    />
                    <button
                      type="submit"
                      phx-disable-with="Sending..."
                      disabled={not @can_send_invite}
                      class="inline-flex items-center justify-center rounded bg-blue-600 hover:bg-blue-700 disabled:bg-zinc-300 disabled:cursor-not-allowed text-white py-1.5 px-3 text-xs font-semibold shadow-sm transition whitespace-nowrap"
                    >
                      Send invite
                    </button>
                  </form>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-sm space-x-3">
                  <button
                    type="button"
                    phx-click="edit_family_member"
                    phx-value-id={member.id}
                    class="text-blue-600 hover:text-blue-800"
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    phx-click="delete_family_member"
                    phx-value-id={member.id}
                    phx-disable-with="Removing..."
                    data-confirm="Remove this family member from your list? This only removes their details from your account. It does not remove anyone who has already accepted an invitation and appears under Linked Family Members."
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
    </section>

    <div class="space-y-8">
      <section>
        <h2 class="text-zinc-900 font-semibold text-lg border-b border-zinc-200 pb-2 mb-4">
          Linked Family Members
          <span class="text-zinc-400 font-normal text-sm ml-2">
            ({length(@sub_accounts)})
          </span>
        </h2>

        <%= if @sub_accounts == [] do %>
          <p class="text-zinc-500 text-sm italic">
            No linked family members yet. When someone accepts your invitation, they will appear here.
          </p>
        <% else %>
          <div class="overflow-x-auto">
            <table
              class="min-w-full divide-y divide-zinc-200"
              id="linked-family-members-table"
            >
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Email
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Relationship
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={sub_account <- @sub_accounts}>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {sub_account.first_name} {sub_account.last_name}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                    {sub_account.email}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                    {format_relationship(sub_account.family_relationship)}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm">
                    <button
                      phx-click="remove_sub_account"
                      phx-value-user_id={sub_account.id}
                      phx-disable-with="Removing..."
                      data-confirm="Are you sure you want to remove this family member from your membership? They will lose access to membership benefits and receive an email notification."
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
      </section>

      <section>
        <h2 class="text-zinc-900 font-semibold text-lg border-b border-zinc-200 pb-2 mb-4">
          Pending Invitations
        </h2>

        <%= if @pending_invites == [] do %>
          <p class="text-zinc-500 text-sm italic">No pending invitations.</p>
          <p class="text-xs text-zinc-400 mt-2">
            When you send an invite, it will appear here until the person accepts or the invite
            expires.
          </p>
        <% else %>
          <p class="text-xs text-zinc-500 mb-3">
            Invitations awaiting acceptance. You can cancel any pending invite.
          </p>
          <div class="overflow-x-auto">
            <table
              class="min-w-full divide-y divide-zinc-200"
              id="pending-invites-table"
            >
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Email
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Relationship
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Expires
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={invite <- @pending_invites}>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {invite.email}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                    {format_relationship(invite.relationship)}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm text-zinc-500">
                    {Calendar.strftime(invite.expires_at, "%B %d, %Y")}
                  </td>
                  <td class="px-4 py-4 whitespace-nowrap text-sm">
                    <button
                      phx-click="revoke_invite"
                      phx-value-invite_id={invite.id}
                      phx-disable-with="Cancelling..."
                      data-confirm="Cancel this invite? The invitee will receive an email notification."
                      class="text-red-600 hover:text-red-800"
                    >
                      Cancel invite
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>
    </div>

    <section class="bg-zinc-50 rounded-xl border border-zinc-200 p-6 shadow-sm">
      <h2 class="text-zinc-900 font-bold text-lg mb-1">Send an Invitation</h2>
      <p class="text-xs text-zinc-500 mb-4">
        Invite someone by email. Optionally link the invite to a family member on your account so their name appears in the email.
      </p>

      <.form
        for={@invite_form}
        id="invite-form"
        phx-submit="send_invite"
        phx-change="validate_invite"
        class="space-y-6"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <.input
            field={@invite_form[:relationship]}
            type="select"
            label="Relationship"
            options={[{"Spouse", "spouse"}, {"Child", "child"}]}
            disabled={not @can_send_invite}
          />
          <p class="text-xs text-zinc-500 md:col-span-2 -mt-4">
            Max 1 spouse and 9 children on your family membership.
          </p>

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
                [{"Select a family member...", ""}] ++
                  Enum.map(valid_family_members, fn fm ->
                    {"#{fm.first_name} #{fm.last_name}", fm.id}
                  end)
              }
              disabled={not @can_send_invite}
            />
            <p class="text-xs text-zinc-500 md:col-span-2 -mt-4">
              If selected, their name will be included in the invitation email.
            </p>
          <% end %>

          <div class="md:col-span-2">
            <.input
              field={@invite_form[:email]}
              type="email"
              label="Email Address"
              placeholder="family.member@example.com"
              required
              disabled={not @can_send_invite}
            />
          </div>
        </div>

        <div class="flex justify-end">
          <.button
            type="submit"
            phx-disable-with="Sending..."
            disabled={not @can_send_invite}
          >
            Send Invitation
          </.button>
        </div>
      </.form>
    </section>
    """
  end

  attr :form, :any, required: true

  defp family_member_editor(assigns) do
    ~H"""
    <div
      id="family-member-editor"
      class="mb-6 bg-zinc-50 rounded-xl border border-zinc-200 p-6 shadow-sm"
    >
      <h3 class="text-zinc-900 font-semibold text-base mb-4">
        <%= if @form[:id].value in [nil, ""] do %>
          Add Family Member
        <% else %>
          Edit Family Member
        <% end %>
      </h3>

      <.form
        for={@form}
        id="family-member-form"
        phx-change="validate_family_member"
        phx-submit="save_family_member"
        class="space-y-4"
      >
        <input type="hidden" name="family_member[id]" value={@form[:id].value} />

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@form[:first_name]}
            type="text"
            label="First Name"
            required
          />
          <.input field={@form[:last_name]} type="text" label="Last Name" required />
          <.input field={@form[:birth_date]} type="date" label="Date of Birth" />
          <.input
            field={@form[:relationship]}
            type="select"
            label="Relationship"
            options={[{"Child", "child"}, {"Spouse", "spouse"}]}
          />
        </div>

        <p class="text-xs text-zinc-500 mt-2">
          Saving here updates your account records only. To share membership benefits, send an invitation separately.
        </p>

        <div class="flex gap-3 justify-end">
          <.button
            type="button"
            variant="outline"
            phx-click="cancel_family_member_form"
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving...">
            Save family member
          </.button>
        </div>
      </.form>
    </div>
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
        You are part of a family membership. Below you can see the primary account holder and other family members.
      </p>
    </header>

    <section>
      <h2 class="text-zinc-900 font-semibold text-lg border-b border-zinc-200 pb-2 mb-4">
        Primary Account Holder
      </h2>
      <%= if @primary_user do %>
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <p class="text-sm font-semibold text-blue-900">
            {@primary_user.first_name} {@primary_user.last_name}
          </p>
          <p class="text-sm text-blue-700 mt-1">{@primary_user.email}</p>
          <p class="text-xs text-blue-600 mt-2">
            <.icon name="hero-star" class="w-4 h-4 inline-block -mt-0.5 me-1" />
            Primary account holder — manages family membership
          </p>
        </div>
      <% else %>
        <p class="text-zinc-500 text-sm italic">
          Primary account holder information not available.
        </p>
      <% end %>
    </section>

    <section>
      <h2 class="text-zinc-900 font-semibold text-lg border-b border-zinc-200 pb-2 mb-4">
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
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200">
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

    <section class="border-t border-zinc-200 pt-8">
      <h2 class="text-zinc-900 font-semibold text-lg mb-2">
        Leave Family Membership
      </h2>
      <p class="text-sm text-zinc-600 mb-4">
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
          "Failed to send invitation. Please try again."
      end

    socket =
      case reason do
        %Ecto.Changeset{} = changeset ->
          assign(socket, :invite_form, to_form(changeset))

        _ ->
          socket
      end

    YscWeb.Flash.put_toast(socket, :error, message, title: "Family")
  end

  defp family_member_form_params(%FamilyMember{} = member) do
    relationship =
      case member.type do
        :spouse -> "spouse"
        "spouse" -> "spouse"
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

  defp format_relationship(nil), do: "Child"
  defp format_relationship("spouse"), do: "Spouse"
  defp format_relationship("child"), do: "Child"
  defp format_relationship(:spouse), do: "Spouse"
  defp format_relationship(:child), do: "Child"
  defp format_relationship(_), do: "Child"

  defp format_member_type(nil), do: "Child"
  defp format_member_type(:spouse), do: "Spouse"
  defp format_member_type("spouse"), do: "Spouse"
  defp format_member_type(:child), do: "Child"
  defp format_member_type("child"), do: "Child"
  defp format_member_type(_), do: "Child"

  defp format_birth_date(nil), do: "—"

  defp format_birth_date(%Date{} = date),
    do: Calendar.strftime(date, "%B %d, %Y")

  defp format_birth_date(_), do: "—"
end
