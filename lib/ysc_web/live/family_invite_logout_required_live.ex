defmodule YscWeb.FamilyInviteLogoutRequiredLive do
  @moduledoc """
  Dedicated page shown when a logged-in user clicks a family invite link for a different email.

  Prompts them to either:
  - log out and log in with the invited email (when an account already exists), or
  - log out and create a new linked account via the membership application flow.
  """
  use YscWeb, :live_view

  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invite = FamilyInvites.get_invite_by_token(token)
    current_user = socket.assigns[:current_user]

    cond do
      is_nil(current_user) ->
        {:ok,
         socket
         |> redirect(to: ~p"/family-invite/#{token}/accept")}

      is_nil(invite) ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invalid invitation link.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      not Ysc.Accounts.FamilyInvite.valid?(invite) ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation has expired or has already been used.",
           title: "Invitation"
         )
         |> redirect(to: ~p"/")}

      true ->
        # If the invite email already has an account, we want the user to
        # log out and then log in with that email. Otherwise, we send them
        # to the registration flow with the invite token preserved.
        existing_user = Accounts.get_user_by_email(invite.email)

        redirect_to =
          if existing_user do
            "/users/log-in?redirect_to=/users/membership"
          else
            # Send to invite acceptance page so they get the same flow as when
            # opening the link logged out (create-account form, no "choose membership" step)
            "/family-invite/#{token}/accept"
          end

        {:ok,
         socket
         |> assign(:invite, invite)
         |> assign(:current_user, current_user)
         |> assign(:existing_user, existing_user)
         |> assign(:logout_redirect_url, ~p"/users/log-out")
         |> assign(:redirect_to, redirect_to)
         |> assign(:page_title, "Log Out to Accept Invitation")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center px-4 py-12 bg-zinc-50">
      <div class="max-w-lg w-full">
        <div class="bg-white rounded-xl shadow-sm border border-zinc-200 p-8">
          <h1 class="text-2xl font-semibold text-zinc-900 mb-4">
            Log Out to Accept Invitation
          </h1>
          <p class="text-zinc-600 mb-6">
            You're currently logged in as <strong>{@current_user.email}</strong>.
          </p>
          <p :if={@existing_user} class="text-zinc-600 mb-6">
            To accept this invitation for <strong>{@invite.email}</strong>, you need to log out from the
            current account and then log in using <strong>{@invite.email}</strong>. After logging in, go to
            your <strong>Membership</strong>
            page to review and accept the pending family invitation.
          </p>
          <p :if={!@existing_user} class="text-zinc-600 mb-6">
            To accept this invitation for <strong>{@invite.email}</strong>, you need to log out and
            create a new account with that email. Your membership application will be linked to this
            invitation and sent for review. Once approved, you'll be immediately added to the family
            membership.
          </p>
          <form action={@logout_redirect_url} method="post">
            <input
              type="hidden"
              name="_csrf_token"
              value={Phoenix.Controller.get_csrf_token()}
            />
            <input type="hidden" name="redirect_to" value={@redirect_to} />
            <button
              type="submit"
              class="w-full flex justify-center rounded-lg bg-blue-600 px-6 py-3 text-base font-semibold text-white hover:bg-blue-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
            >
              <%= if @existing_user do %>
                Log out and log in using {@invite.email} to accept
              <% else %>
                Log out and create new linked user
              <% end %>
            </button>
          </form>
          <p class="mt-6 text-sm text-zinc-500">
            <.link navigate={~p"/"} class="text-blue-600 hover:underline">
              Return to home
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
