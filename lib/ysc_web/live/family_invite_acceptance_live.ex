defmodule YscWeb.FamilyInviteAcceptanceLive do
  use YscWeb, :live_view

  alias Ysc.Accounts.{FamilyInvites, FamilyInvite, User}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invite = FamilyInvites.get_invite_by_token(token)

    cond do
      is_nil(invite) ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invalid invitation link.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      not FamilyInvite.valid?(invite) ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation has expired or has already been used.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      true ->
        # Check if invite email belongs to an existing user (for linking existing accounts)
        existing_user = Ysc.Accounts.get_user_by_email(invite.email)
        current_user = socket.assigns[:current_user]

        # Can link if: user is logged in, email matches invite, and they're not already linked
        can_link_existing =
          current_user &&
            String.downcase(String.trim(current_user.email)) ==
              String.downcase(String.trim(invite.email)) &&
            not Ysc.Accounts.sub_account?(current_user)

        # Block access if logged in but cannot link (wrong account or invite is for new user)
        if current_user && !can_link_existing do
          {:ok,
           socket
           |> push_navigate(
             to: ~p"/family-invite/#{invite.token}/logout-required"
           )}
        else
          # Pre-fill email and most_connected_country from invite/primary user, but allow editing
          initial_params = %{"email" => invite.email}

          # Pre-fill most_connected_country from primary user if available
          initial_params =
            if invite.primary_user && invite.primary_user.most_connected_country do
              Map.put(
                initial_params,
                "most_connected_country",
                invite.primary_user.most_connected_country
              )
            else
              initial_params
            end

          form =
            to_form(
              User.sub_account_registration_changeset(
                %User{},
                initial_params,
                invite.primary_user_id,
                hash_password: false,
                validate_email: false
              ),
              as: "user"
            )

          {:ok,
           socket
           |> assign(:invite, invite)
           |> assign(:form, form)
           |> assign(:existing_user, existing_user)
           |> assign(:can_link_existing, can_link_existing)
           |> assign(:page_title, "Accept Family Invitation")
           |> assign(
             :meta_description,
             "Accept your Young Scandinavians Club family account invitation."
           )}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    invite = socket.assigns.invite

    changeset =
      %User{}
      |> User.sub_account_registration_changeset(
        user_params,
        invite.primary_user_id,
        hash_password: false,
        validate_email: false
      )
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("link_existing", _params, socket) do
    invite = socket.assigns.invite
    current_user = socket.assigns.current_user

    case FamilyInvites.link_existing_user(invite.token, current_user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "You've joined the family membership! You now have access to all membership benefits.",
           title: "Family invitation"
         )
         |> redirect(to: ~p"/")}

      {:error, :invite_not_found} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invitation not found.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      {:error, :invite_expired_or_used} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation has expired or has already been used.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      {:error, :email_mismatch} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Please sign in with the email address that was invited.",
           title: "Invitation"
         )}

      {:error, :already_linked_to_family} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "You can only be on one family membership at a time. Click your name in the top-right corner, open Membership, and use \"Leave family membership\" to leave your current family first. Then you can accept this invitation.",
           title: "Invitation"
         )}

      {:error, :cannot_link_self} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation is for a family member, not for your own account.",
           title: "Invitation"
         )}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    invite = socket.assigns.invite

    case FamilyInvites.accept_invite(invite.token, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Account created successfully! You can now sign in with your email and password.",
           title: "Family invitation"
         )
         |> redirect(to: ~p"/users/log-in")}

      {:error, :invite_not_found} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invitation not found.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      {:error, :invite_expired_or_used} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation has expired or has already been used.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      {:error, :email_mismatch} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "The email address must match the one this invitation was sent to.",
           title: "Invitation"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto py-10 px-4">
      <div class="prose prose-zinc max-w-none">
        <h1>Accept Family Invitation</h1>

        <p>
          You've been invited by <strong>{@invite.primary_user.first_name}</strong>
          to join their family membership with the Young Scandinavians Club.
        </p>

        <p>
          As a family member, you'll share their membership benefits including cabin bookings and
          event ticket purchases.
        </p>

        <p>
          This is a quick sign-up to join an existing family membership. It is not a new membership
          application and does not need board approval.
        </p>

        <%!-- Logged in with matching email: show Join button --%>
        <div :if={@can_link_existing} class="mt-8">
          <.callout type="info" class="p-6">
            <p class="text-blue-800 mb-4">
              You're signed in as <strong>{@current_user.email}</strong>. Click below to join <strong>{@invite.primary_user.first_name}</strong>'s family membership.
            </p>
            <.button
              phx-click="link_existing"
              phx-disable-with="Joining..."
              class="w-full"
            >
              Join Family Membership
            </.button>
          </.callout>
        </div>

        <%!-- Not logged in but email exists: prompt to log in --%>
        <div :if={@existing_user && !@current_user} class="mt-8">
          <.callout type="neutral" class="p-6">
            <p class="mb-4">
              You already have an account with this email. Sign in to accept this invitation.
            </p>
            <.link
              navigate={
                ~p"/users/log-in?redirect_to=#{~p"/family-invite/#{@invite.token}/accept"}"
              }
              class="inline-flex items-center justify-center rounded-lg bg-blue-600 px-6 py-3 text-sm font-semibold text-white hover:bg-blue-500"
            >
              Sign in to accept
            </.link>
            <p class="mt-4 text-xs text-zinc-500">
              After you sign in, you'll return here to finish accepting the invitation.
            </p>
          </.callout>
        </div>

        <%!-- Create new account form (when email doesn't exist, or user not logged in) --%>
        <div :if={!@can_link_existing && !@existing_user} class="mt-8">
          <.simple_form
            for={@form}
            id="accept-invite-form"
            phx-submit="save"
            phx-change="validate"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              required
              readonly
            />
            <.input field={@form[:first_name]} label="First Name" required />
            <.input field={@form[:last_name]} label="Last Name" required />
            <.input
              field={@form[:date_of_birth]}
              type="date"
              label="Date of Birth"
              required
            />
            <.input
              type="phone-input"
              label="Phone Number"
              field={@form[:phone_number]}
            />
            <.input
              field={@form[:password]}
              type="password-toggle"
              label="Password"
              required
            />
            <p class="text-xs text-zinc-500 -mt-2">
              Must be at least 12 characters.
            </p>
            <.input
              field={@form[:password_confirmation]}
              type="password-toggle"
              label="Confirm Password"
              required
            />

            <:actions>
              <.button type="submit" phx-disable-with="Joining...">
                Join Family Membership
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <%!-- When existing user but logged in with different account --%>
        <div
          :if={@existing_user && @current_user && !@can_link_existing}
          class="mt-8"
        >
          <p class="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-4">
            You're signed in as a different account. To accept this invitation for <strong>{@invite.email}</strong>, please sign out and either sign in with that email or
            create a new account with that email.
          </p>
        </div>
      </div>
    </div>
    """
  end
end
