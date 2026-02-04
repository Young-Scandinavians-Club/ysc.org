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
         |> put_flash(:error, "Invalid invitation link.")
         |> redirect(to: ~p"/")}

      not FamilyInvite.valid?(invite) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "This invitation has expired or has already been used."
         )
         |> redirect(to: ~p"/")}

      true ->
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
         |> assign(:page_title, "Accept Family Invitation")}
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

  def handle_event("save", %{"user" => user_params}, socket) do
    invite = socket.assigns.invite

    case FamilyInvites.accept_invite(invite.token, user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Account created successfully! You can now log in with your email and password."
         )
         |> redirect(to: ~p"/users/log-in")}

      {:error, :invite_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invitation not found.")
         |> redirect(to: ~p"/")}

      {:error, :invite_expired_or_used} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "This invitation has expired or has already been used."
         )
         |> redirect(to: ~p"/")}

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
          You've been invited by
          <strong><%= @invite.primary_user.first_name %></strong>
          to join
          their YSC family membership!
        </p>

        <p>
          As a family member, you'll share their membership benefits including cabin bookings and
          event ticket purchases.
        </p>

        <div class="mt-8">
          <.simple_form
            for={@form}
            id="accept-invite-form"
            phx-submit="save"
            phx-change="validate"
          >
            <.input field={@form[:email]} type="email" label="Email" required />
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
            <.input
              field={@form[:password_confirmation]}
              type="password-toggle"
              label="Confirm Password"
              required
            />

            <:actions>
              <.button type="submit" phx-disable-with="Creating...">
                Create Account
              </.button>
            </:actions>
          </.simple_form>
        </div>
      </div>
    </div>
    """
  end
end
