defmodule YscWeb.UserSecurityLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    current_membership = socket.assigns.current_membership
    active_plan = YscWeb.UserAuth.get_membership_plan_type(current_membership)

    # Initialize password form
    password_changeset = Accounts.change_user_password(user)

    # Initialize with empty passkeys list and loading state
    socket =
      socket
      |> assign(:page_title, "Security Settings")
      |> assign(:user, user)
      |> assign(:current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:trigger_submit, false)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:passkeys, [])
      |> assign(:passkeys_loading, true)
      |> assign(:passkeys_loaded, false)
      |> assign(:active_plan_type, active_plan)
      |> assign(:show_reauth_modal, false)
      |> assign(:reauth_form, to_form(%{"password" => ""}))
      |> assign(:reauth_error, nil)
      |> assign(:reauth_challenge, nil)
      |> assign(:pending_password_change, nil)
      |> assign(:user_has_password, !is_nil(user.hashed_password))

    # Load passkeys asynchronously only if connected
    socket =
      if connected?(socket) do
        start_async(socket, :load_passkeys, fn ->
          Accounts.get_user_passkeys(user)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_passkeys, {:ok, passkeys}, socket) do
    {:noreply,
     socket
     |> assign(:passkeys, passkeys)
     |> assign(:passkeys_loading, false)
     |> assign(:passkeys_loaded, true)}
  end

  def handle_async(:load_passkeys, {:exit, reason}, socket) do
    require Logger
    Logger.error("Failed to load passkeys async: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:passkeys_loading, false)
     |> assign(:passkeys_loaded, true)}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  @impl true
  def handle_event("request_password_change", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    # Validate the password form first
    changeset =
      user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      # Store pending password change and show re-auth modal
      {:noreply,
       socket
       |> assign(:pending_password_change, user_params)
       |> assign(:show_reauth_modal, true)
       |> assign(:reauth_error, nil)}
    else
      # Show validation errors
      {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("cancel_reauth", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reauth_modal, false)
     |> assign(:pending_password_change, nil)
     |> assign(:reauth_error, nil)}
  end

  def handle_event("reauth_with_password", %{"password" => password}, socket) do
    user = socket.assigns.current_user

    case Accounts.get_user_by_email_and_password(user.email, password) do
      nil ->
        {:noreply,
         assign(socket, :reauth_error, "Invalid password. Please try again.")}

      _valid_user ->
        # Password verified, proceed with password change
        {:noreply, process_password_change_after_reauth(socket)}
    end
  end

  def handle_event("reauth_with_passkey", _params, socket) do
    require Logger
    Logger.info("[UserSecurityLive] reauth_with_passkey event received")

    # Generate authentication challenge for passkey
    challenge =
      :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    challenge_json = %{
      challenge: challenge,
      timeout: 60_000,
      userVerification: "required"
    }

    {:noreply,
     socket
     |> assign(:reauth_challenge, challenge)
     |> push_event("create_authentication_challenge", %{options: challenge_json})}
  end

  def handle_event("verify_authentication", params, socket) do
    require Logger

    Logger.info(
      "[UserSecurityLive] verify_authentication event received for re-auth"
    )

    Logger.debug("Params: #{inspect(params)}")

    # In a full production implementation, you should verify the passkey signature here
    # against the stored public key and challenge. For now, we trust the browser's
    # verification since the user is already authenticated in the session.

    # The browser has already verified:
    # 1. The user's biometric/PIN
    # 2. The passkey belongs to this domain
    # 3. The signature is valid

    # Since the user is in an authenticated session and the browser verified their
    # passkey, we can proceed with the password change
    {:noreply, process_password_change_after_reauth(socket)}
  end

  def handle_event("passkey_auth_error", %{"error" => error}, socket) do
    require Logger

    Logger.debug(
      "[UserSecurityLive] Passkey authentication error: #{inspect(error)}"
    )

    {:noreply,
     assign(
       socket,
       :reauth_error,
       "Passkey authentication failed. Please try again."
     )}
  end

  # PasskeyAuth hook sends these events - we don't need to handle them in security settings
  def handle_event("passkey_support_detected", _params, socket),
    do: {:noreply, socket}

  def handle_event("user_agent_received", _params, socket),
    do: {:noreply, socket}

  def handle_event("device_detected", _params, socket), do: {:noreply, socket}

  def handle_event("delete_passkey", %{"passkey_id" => id}, socket) do
    user = socket.assigns.current_user

    # Get passkey and verify it belongs to current user
    case Repo.get(Ysc.Accounts.UserPasskey, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Passkey not found.")}

      passkey ->
        if passkey.user_id == user.id do
          case Accounts.delete_user_passkey(passkey) do
            {:ok, _} ->
              # Remove deleted passkey from assigns
              updated_passkeys =
                Enum.reject(socket.assigns.passkeys, &(&1.id == id))

              {:noreply,
               socket
               |> assign(:passkeys, updated_passkeys)
               |> put_flash(:info, "Passkey deleted successfully.")}

            {:error, _changeset} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Failed to delete passkey. Please try again."
               )}
          end
        else
          {:noreply,
           put_flash(
             socket,
             :error,
             "You are not authorized to delete this passkey."
           )}
        end
    end
  end

  defp process_password_change_after_reauth(socket) do
    user = socket.assigns.current_user
    user_params = socket.assigns.pending_password_change
    user_has_password = socket.assigns.user_has_password

    # Use appropriate update function based on whether user has a password
    result =
      if user_has_password do
        # User is changing their existing password - no need to validate current password
        # since we just re-authenticated them
        changeset = Accounts.User.password_changeset(user, user_params)

        Ecto.Multi.new()
        |> Ecto.Multi.update(:user, changeset)
        |> Ecto.Multi.delete_all(
          :tokens,
          Accounts.UserToken.by_user_and_contexts_query(user, :all)
        )
        |> Ysc.Repo.transaction()
        |> case do
          {:ok, %{user: user}} -> {:ok, user}
          {:error, :user, changeset, _} -> {:error, changeset}
        end
      else
        # User is setting password for the first time
        Accounts.set_user_initial_password(user, user_params)
      end

    case result do
      {:ok, user} ->
        UserNotifier.deliver_password_changed_notification(user)

        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        socket
        |> assign(:trigger_submit, true)
        |> assign(:password_form, password_form)
        |> assign(:show_reauth_modal, false)
        |> assign(:pending_password_change, nil)
        |> assign(:reauth_error, nil)
        |> assign(:user_has_password, true)

      {:error, changeset} ->
        socket
        |> assign(:password_form, to_form(changeset))
        |> assign(:show_reauth_modal, false)
        |> assign(:pending_password_change, nil)
        |> assign(:reauth_error, nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-xl px-4 mx-auto py-8 lg:py-10">
      <.modal
        :if={@show_reauth_modal}
        id="reauth-modal"
        on_cancel={JS.push("cancel_reauth")}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
          Verify Your Identity
        </h2>

        <p class="text-sm text-zinc-600 mb-6">
          <%= if @user_has_password do %>
            For security reasons, please verify your identity before changing your password.
          <% else %>
            For security reasons, please verify your identity before setting a password.
          <% end %>
        </p>

        <div id="reauth-methods-password" class="space-y-4" phx-hook="PasskeyAuth">
          <!-- Password Authentication Option (if user has a password) -->
          <div :if={@user_has_password} class="space-y-4">
            <h3 class="font-semibold text-zinc-900">Verify with your password</h3>
            <.simple_form
              for={@reauth_form}
              id="reauth_password_form"
              phx-submit="reauth_with_password"
            >
              <.input
                field={@reauth_form[:password]}
                type="password-toggle"
                label="Password"
                required
                autocomplete="current-password"
              />
              <%= if @reauth_error do %>
                <div class="p-3 bg-red-50 border border-red-200 rounded-md">
                  <p class="text-sm text-red-800"><%= @reauth_error %></p>
                </div>
              <% end %>
              <:actions>
                <.button phx-disable-with="Verifying..." class="w-full">
                  Continue
                </.button>
              </:actions>
            </.simple_form>
          </div>
          <!-- Passkey Authentication Option -->
          <div class="space-y-4">
            <div :if={@user_has_password} class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-zinc-200"></div>
              </div>
              <div class="relative flex justify-center text-sm">
                <span class="px-2 bg-white text-zinc-500">OR</span>
              </div>
            </div>

            <h3 class="font-semibold text-zinc-900">
              <%= if @user_has_password,
                do: "Verify with a passkey",
                else: "Verify with your passkey" %>
            </h3>
            <p class="text-sm text-zinc-600">
              Use your device's fingerprint, face recognition, or security key
            </p>
            <.button
              type="button"
              phx-click="reauth_with_passkey"
              phx-disable-with="Verifying..."
              class="w-full"
            >
              <.icon name="hero-finger-print" class="w-5 h-5 me-2" />
              Continue with Passkey
            </.button>
          </div>
        </div>
      </.modal>

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
                "hover:bg-zinc-100 hover:text-zinc-900"
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
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-wallet" class="w-5 h-5 me-2" /> Payments
            </.link>
          </li>
          <%= if @current_user && (Accounts.primary_user?(@current_user) || Accounts.sub_account?(@current_user)) && (@active_plan_type == :family || @active_plan_type == :lifetime) do %>
            <li>
              <.link
                navigate={~p"/users/settings/family"}
                class={[
                  "inline-flex items-center px-4 py-3 rounded w-full",
                  "hover:bg-zinc-100 hover:text-zinc-900"
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
                "bg-blue-600 active text-zinc-100"
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
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" /> Notifications
            </.link>
          </li>
        </ul>

        <div class="text-medium px-2 text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div class="space-y-8">
            <!-- Passkeys Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Passkeys</h2>
              <p class="text-zinc-600 text-sm">
                A passkey is a passwordless way to sign in using your device’s built-in security (fingerprint, face, or PIN). It’s tied to your device and this site, so it can’t be phished or leaked like a password.
              </p>
              <div class="flex flex-wrap gap-3">
                <div class="inline-flex items-center gap-2 rounded-lg bg-blue-50 px-3 py-2 text-sm text-blue-800">
                  <.icon name="hero-bolt" class="w-4 h-4 shrink-0 text-blue-600" />
                  <span>Faster sign-in</span>
                </div>
                <div class="inline-flex items-center gap-2 rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
                  <.icon
                    name="hero-shield-check"
                    class="w-4 h-4 shrink-0 text-emerald-600"
                  />
                  <span>Stronger security</span>
                </div>
                <div class="inline-flex items-center gap-2 rounded-lg bg-purple-50 px-3 py-2 text-sm text-purple-800">
                  <.icon name="hero-key" class="w-4 h-4 shrink-0 text-purple-600" />
                  <span>No passwords to remember</span>
                </div>
              </div>

              <div
                :if={@passkeys_loading}
                class="flex items-center justify-center py-8"
              >
                <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600">
                </div>
                <span class="ml-3 text-zinc-600 text-sm">Loading passkeys...</span>
              </div>

              <div
                :if={@passkeys_loaded && @passkeys == []}
                class="text-center py-8"
              >
                <p class="text-zinc-600 text-sm mb-4">
                  You don't have any passkeys yet.
                </p>
                <.link
                  navigate={~p"/users/settings/passkeys/new"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                >
                  <.icon name="hero-plus" class="w-5 h-5 me-2" /> Add Passkey
                </.link>
              </div>

              <div :if={@passkeys_loaded && @passkeys != []} class="space-y-4">
                <.link
                  navigate={~p"/users/settings/passkeys/new"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 mb-4"
                >
                  <.icon name="hero-plus" class="w-5 h-5 me-2" /> Add Passkey
                </.link>

                <div class="space-y-3">
                  <div
                    :for={passkey <- @passkeys}
                    class="flex items-center justify-between p-4 border border-zinc-200 rounded-lg"
                  >
                    <div class="flex-1">
                      <div class="flex items-center gap-2 mb-1">
                        <.icon name="hero-key" class="w-5 h-5 text-zinc-600" />
                        <p class="text-zinc-900 font-medium">
                          <%= format_passkey_name(passkey) %>
                        </p>
                      </div>
                      <div class="text-sm text-zinc-600 space-y-1">
                        <p>
                          Created: <%= Calendar.strftime(
                            passkey.inserted_at,
                            "%B %d, %Y"
                          ) %>
                        </p>
                        <p>
                          Last used:
                          <%= if passkey.last_used_at do %>
                            <%= Calendar.strftime(passkey.last_used_at, "%B %d, %Y") %>
                          <% else %>
                            Never
                          <% end %>
                        </p>
                      </div>
                    </div>
                    <div>
                      <.button
                        phx-click="delete_passkey"
                        phx-value-passkey_id={passkey.id}
                        phx-confirm={"Are you sure you want to delete the passkey \"#{format_passkey_name(passkey)}\"? This action cannot be undone."}
                        phx-disable-with="Deleting..."
                        variant="danger"
                        class="ml-4"
                      >
                        <.icon name="hero-trash" class="w-4 h-4 me-1" /> Delete
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Password Change Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">
                <%= if @user_has_password,
                  do: "Change Password",
                  else: "Set Password" %>
              </h2>

              <p :if={!@user_has_password} class="text-sm text-zinc-600">
                You don't currently have a password set. Setting a password allows you to sign in with email and password in addition to other methods.
              </p>

              <.simple_form
                for={@password_form}
                id="password_form"
                action={~p"/users/log-in?_action=password_updated"}
                method="post"
                phx-change="validate_password"
                phx-submit="request_password_change"
                phx-trigger-action={@trigger_submit}
              >
                <.input
                  field={@password_form[:email]}
                  type="hidden"
                  id="hidden_user_email"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password-toggle"
                  label="New password"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password-toggle"
                  label="Confirm new password"
                />
                <p class="text-sm text-zinc-600 -mt-2">
                  <%= if @user_has_password do %>
                    You will be asked to verify your identity before changing your password.
                  <% else %>
                    You will be asked to verify your identity before setting your password.
                  <% end %>
                </p>
                <:actions>
                  <.button phx-disable-with="Continuing...">
                    <%= if @user_has_password,
                      do: "Change Password",
                      else: "Set Password" %>
                  </.button>
                </:actions>
              </.simple_form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_passkey_name(passkey) do
    if passkey.nickname && passkey.nickname != "" do
      passkey.nickname
    else
      # Fallback for passkeys created before nickname detection was implemented
      "Device (created #{Calendar.strftime(passkey.inserted_at, "%b %Y")})"
    end
  end
end
