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
    timezone = get_timezone_from_connect_params(socket)

    # Initialize password form
    password_changeset = Accounts.change_user_password(user)

    # Initialize with empty passkeys list and loading state
    socket =
      socket
      |> assign(:page_title, "Security Settings")
      |> assign(
        :meta_description,
        "Manage your Young Scandinavians Club account security, password, and passkeys."
      )
      |> assign(:timezone, timezone)
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
      |> assign(:pending_password_change, nil)
      |> assign(:user_has_password, !is_nil(user.hashed_password))
      |> assign(:login_history, [])
      |> assign(:login_history_loading, true)
      |> assign(:revoked_session_ids, [])

    # Load passkeys and login history asynchronously only if connected
    socket =
      if connected?(socket) do
        socket
        |> start_async(:load_passkeys, fn ->
          Accounts.get_user_passkeys(user)
        end)
        |> start_async(:load_login_history, fn ->
          Accounts.get_user_auth_history(user, 10)
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
    require Ysc.Logging
    Ysc.Logging.warning("Failed to load passkeys async: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:passkeys_loading, false)
     |> assign(:passkeys_loaded, true)}
  end

  @impl true
  def handle_async(:load_login_history, {:ok, login_history}, socket) do
    {:noreply,
     socket
     |> assign(:login_history, login_history)
     |> assign(:login_history_loading, false)}
  end

  def handle_async(:load_login_history, {:exit, reason}, socket) do
    require Ysc.Logging

    Ysc.Logging.warning(
      "Failed to load login history async: #{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(:login_history_loading, false)}
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

    changeset =
      user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      socket = assign(socket, :pending_password_change, user_params)

      if reauth_still_valid?(socket) do
        # Already verified via recent reauth — process immediately
        {:noreply, process_password_change_after_reauth(socket)}
      else
        {:noreply, assign(socket, :show_reauth_modal, true)}
      end
    else
      {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  # PasskeyAuth hook sends these events to the LiveView (via pushEvent, not pushEventTo)
  def handle_event("passkey_support_detected", _params, socket),
    do: {:noreply, socket}

  def handle_event("user_agent_received", _params, socket),
    do: {:noreply, socket}

  def handle_event("device_detected", _params, socket), do: {:noreply, socket}

  def handle_event(
        "revoke_session",
        %{"session_id" => encoded_session_id},
        socket
      ) do
    user = socket.assigns.current_user

    case Accounts.revoke_user_session_by_id(user, encoded_session_id) do
      :ok ->
        # Disconnect any LiveView sockets using this session (e.g. other tab or device)
        if live_socket_id =
             YscWeb.UserAuth.live_socket_id_from_encoded_session(
               encoded_session_id
             ) do
          YscWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
        end

        current_session_id = socket.assigns[:current_session_id]

        if current_session_id && encoded_session_id == current_session_id do
          # User revoked their current session — sign them out
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:info, "You have signed out.",
             title: "Session ended",
             icon: &YscWeb.CoreComponents.flash_toast_icon_shield/1
           )
           |> push_navigate(to: ~p"/users/log-in")}
        else
          {:noreply,
           socket
           |> assign(:revoked_session_ids, [
             encoded_session_id | socket.assigns.revoked_session_ids
           ])
           |> YscWeb.Flash.put_toast(:info, "Session signed out.",
             title: "Session ended",
             icon: &YscWeb.CoreComponents.flash_toast_icon_shield/1
           )}
        end

      :error ->
        # Token may already be revoked (e.g. from another tab or previous visit); hide the button
        {:noreply,
         socket
         |> assign(:revoked_session_ids, [
           encoded_session_id | socket.assigns.revoked_session_ids
         ])
         |> YscWeb.Flash.put_toast(
           :info,
           "That session may already be signed out.",
           title: "Session"
         )}
    end
  end

  def handle_event("delete_passkey", %{"passkey_id" => id}, socket) do
    user = socket.assigns.current_user

    # Get passkey and verify it belongs to current user
    case Repo.get(Ysc.Accounts.UserPasskey, id) do
      nil ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "Passkey not found.",
           title: "Passkey"
         )}

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
               |> YscWeb.Flash.put_toast(:info, "Passkey deleted successfully.",
                 title: "Passkey",
                 icon: &YscWeb.CoreComponents.flash_toast_icon_shield/1
               )}

            {:error, _changeset} ->
              {:noreply,
               YscWeb.Flash.put_toast(
                 socket,
                 :error,
                 "Failed to delete passkey. Please try again.",
                 title: "Passkey"
               )}
          end
        else
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "You are not authorized to delete this passkey.",
             title: "Passkey"
           )}
        end
    end
  end

  @impl true
  def handle_info(:reauth_verified, socket) do
    {:noreply, process_password_change_after_reauth(socket)}
  end

  def handle_info(:reauth_cancelled, socket) do
    {:noreply,
     socket
     |> assign(:show_reauth_modal, false)
     |> assign(:pending_password_change, nil)}
  end

  # Catch-all: drop unhandled messages (e.g. Swoosh email delivery in tests)
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reauth_still_valid?(socket) do
    case socket.assigns[:session_reauth_expires_at] do
      ts when is_integer(ts) -> ts > DateTime.utc_now() |> DateTime.to_unix()
      _ -> false
    end
  end

  @dialyzer {:nowarn_function, process_password_change_after_reauth: 1}
  defp process_password_change_after_reauth(socket) do
    user = socket.assigns.current_user
    user_params = socket.assigns.pending_password_change
    user_has_password = socket.assigns.user_has_password

    # When UI says "no password", confirm in DB to avoid overwriting an existing
    # password (e.g. stale session/cache showing hashed_password as nil).
    actually_has_password =
      user_has_password || Accounts.user_has_password_in_db?(user)

    # Use appropriate update function based on whether user has a password
    result =
      if actually_has_password do
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
      <.live_component
        :if={@show_reauth_modal}
        module={YscWeb.ReauthComponent}
        id="reauth"
        user={@current_user}
        user_has_password={@user_has_password}
        return_to={@request_path}
        description={
          if @user_has_password,
            do:
              "For security reasons, please verify your identity before changing your password.",
            else:
              "For security reasons, please verify your identity before setting a password."
        }
      />

      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <.account_settings_nav
          current={:security}
          show_family_link?={
            @current_user &&
              (Accounts.primary_user?(@current_user) ||
                 Accounts.sub_account?(@current_user)) &&
              (@active_plan_type == :family || @active_plan_type == :lifetime)
          }
        />

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
                id="user-security-passkeys-loading"
                class="space-y-3"
                role="status"
                aria-live="polite"
              >
                <span class="sr-only">Loading passkeys…</span>
                <.skeleton_list_row
                  :for={_ <- 1..2}
                  class="flex items-center justify-between p-4 border border-zinc-200 rounded-lg"
                  lines={[
                    "h-4 w-40 rounded",
                    "h-3 w-32 rounded",
                    "h-3 w-28 rounded"
                  ]}
                  trailing_class="h-8 w-20 rounded"
                />
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
                          {format_passkey_name(passkey)}
                        </p>
                      </div>
                      <div class="text-sm text-zinc-600 space-y-1">
                        <p>
                          Created: {Calendar.strftime(
                            passkey.inserted_at,
                            "%B %d, %Y"
                          )}
                        </p>
                        <p>
                          Last used:
                          <%= if passkey.last_used_at do %>
                            {Calendar.strftime(passkey.last_used_at, "%B %d, %Y")}
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
                {if @user_has_password,
                  do: "Change Password",
                  else: "Set Password"}
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
                    {if @user_has_password,
                      do: "Change Password",
                      else: "Set Password"}
                  </.button>
                </:actions>
              </.simple_form>
            </div>
            <!-- Recent Activity Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Recent Activity</h2>
              <p class="text-zinc-600 text-sm">
                Review where and how you signed in. If you see an unfamiliar sign-in, change your password and sign out other sessions.
              </p>

              <div
                :if={@login_history_loading}
                id="user-security-login-history-loading"
                class="space-y-3"
                role="status"
                aria-live="polite"
              >
                <span class="sr-only">Loading activity…</span>
                <div
                  :for={_ <- 1..3}
                  class="p-4 border border-zinc-200 rounded-lg space-y-2"
                >
                  <.skeleton_block class="h-3 w-24 rounded-md" />
                  <.skeleton_block class="h-4 w-48 rounded" />
                  <.skeleton_block class="h-3 w-36 rounded" />
                </div>
              </div>

              <div
                :if={!@login_history_loading && @login_history == []}
                class="text-center py-8"
              >
                <p class="text-zinc-600 text-sm">No sign-in history yet.</p>
              </div>

              <%= if !@login_history_loading && @login_history != [] do %>
                <% {current_event, past_events} =
                  split_current_and_past_events(@login_history, @current_session_id) %>
                <div class="space-y-6">
                  <%= if current_event do %>
                    <div>
                      <h3 class="text-sm font-semibold text-zinc-700 mb-3">
                        Current session
                      </h3>
                      <div class="flex items-start justify-between gap-4 p-4 border border-blue-200 rounded-lg bg-blue-50/50">
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2 flex-wrap mb-1">
                            <span class="inline-flex items-center rounded-md bg-blue-100 px-2 py-1 text-xs font-medium text-blue-800">
                              Current session
                            </span>
                            <span class="text-zinc-600 text-xs">
                              {sign_in_method_label(current_event)}
                            </span>
                          </div>
                          <p class="text-sm text-zinc-900 font-medium">
                            {login_device_description(current_event)}
                          </p>
                          <p class="text-xs text-zinc-500 mt-1">
                            {format_login_time(current_event.inserted_at, @timezone)} · {format_location(
                              current_event
                            )}
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                  <div>
                    <h3 class="text-sm font-semibold text-zinc-700 mb-3">
                      Past sign-ins
                    </h3>
                    <div class="space-y-3">
                      <div
                        :for={event <- past_events}
                        class="flex items-start justify-between gap-4 p-4 border border-zinc-200 rounded-lg"
                      >
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center gap-2 flex-wrap mb-1">
                            <.icon
                              name={device_type_icon(event.device_type)}
                              class="w-5 h-5 text-zinc-600 shrink-0"
                            />
                            <span class={login_status_badge(event)}>
                              {if event.success,
                                do: "Successful",
                                else: "Failed sign-in"}
                            </span>
                            <span class="text-zinc-500 text-xs">
                              {sign_in_method_label(event)}
                            </span>
                            <%= if event.is_suspicious do %>
                              <span class="inline-flex items-center rounded-md bg-amber-50 px-2 py-1 text-xs font-medium text-amber-800">
                                <.icon
                                  name="hero-exclamation-triangle"
                                  class="w-3 h-3 me-1"
                                /> Flagged
                              </span>
                            <% end %>
                          </div>
                          <p class="text-sm text-zinc-900 font-medium">
                            {login_device_description(event)}
                          </p>
                          <p class="text-xs text-zinc-500 mt-1">
                            {format_login_time(event.inserted_at, @timezone)} · {format_location(
                              event
                            )}
                          </p>
                        </div>
                        <div class="shrink-0">
                          <%= if event.success && event.session_id && event.session_id != @current_session_id && event.session_id not in @revoked_session_ids do %>
                            <.button
                              phx-click="revoke_session"
                              phx-value-session_id={event.session_id}
                              phx-confirm="Sign out this session? You will need to sign in again on that device."
                              phx-disable-with="Signing out..."
                              variant="secondary"
                              class="text-sm"
                            >
                              Sign out this session
                            </.button>
                          <% else %>
                            <%= if !event.success do %>
                              <span class="text-xs text-zinc-500">
                                Failed sign-in attempt — no action needed unless you don't recognize this device.
                              </span>
                            <% end %>
                          <% end %>
                        </div>
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

  defp device_type_icon(device_type) do
    case device_type do
      "mobile" -> "hero-device-phone-mobile"
      "tablet" -> "hero-device-tablet"
      "desktop" -> "hero-computer-desktop"
      _ -> "hero-computer-desktop"
    end
  end

  defp get_timezone_from_connect_params(socket) do
    connect_params = get_connect_params(socket) || %{}
    Map.get(connect_params, "timezone", "America/Los_Angeles")
  end

  defp format_login_time(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y at %H:%M")
  end

  defp mask_ip(nil), do: "—"
  defp mask_ip(""), do: "—"

  defp mask_ip(ip) when is_binary(ip) do
    # IPv4: mask last two octets (e.g. 192.168.xxx.xxx)
    parts = String.split(ip, ".")

    if length(parts) == 4 do
      [a, b | _] = parts
      "#{a}.#{b}.xxx.xxx"
    else
      # IPv6: show first two groups and mask rest
      parts = String.split(ip, ":")

      if length(parts) > 2 do
        [a, b | _] = parts
        "#{a}:#{b}:xxxx:..."
      else
        "—"
      end
    end
  end

  defp login_status_badge(event) do
    if event.success do
      "inline-flex items-center rounded-md bg-emerald-50 px-2 py-1 text-xs font-medium text-emerald-800"
    else
      "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-800"
    end
  end

  defp login_device_description(event) do
    browser = event.browser || "Unknown browser"
    os = event.operating_system || "Unknown OS"
    "#{browser} on #{os}"
  end

  defp split_current_and_past_events(events, current_session_id) do
    current =
      Enum.find(events, fn e ->
        e.success && e.session_id && e.session_id == current_session_id
      end)

    past =
      if current do
        Enum.reject(events, &(&1.id == current.id))
      else
        events
      end

    {current, past}
  end

  defp sign_in_method_label(event) do
    meta = event.metadata || %{}
    method = Map.get(meta, "auth_method") || Map.get(meta, :auth_method)

    case method do
      "email_password" -> "Password"
      "passkey" -> "Passkey"
      "google" -> "Google"
      "facebook" -> "Facebook"
      "oauth" -> "Google or Facebook"
      other when is_binary(other) and other != "" -> String.capitalize(other)
      _ -> "Sign-in"
    end
  end

  defp format_location(event) do
    parts =
      [event.city, event.region, event.country]
      |> Enum.reject(&(is_nil(&1) || &1 == ""))

    if parts != [] do
      Enum.join(parts, ", ")
    else
      masked = mask_ip(event.ip_address)
      if masked != "—", do: masked, else: "—"
    end
  end
end
