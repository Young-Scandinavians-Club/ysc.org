defmodule YscWeb.ReauthComponent do
  @moduledoc """
  Shared re-authentication LiveComponent.

  Presents the user with password, passkey, and OAuth verification options.
  Sends `{:reauth_verified}` or `{:reauth_cancelled}` to the parent LiveView
  process via `send/2`.

  Required assigns:
    - `user` — the current user struct
    - `user_has_password` — boolean
    - `description` — contextual sentence shown below the heading
    - `return_to` — path to redirect back to after OAuth reauth (e.g. `@request_path`)
  """
  use YscWeb, :live_component

  alias Ysc.Accounts

  require Ysc.Logging

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:reauth_form, fn -> to_form(%{"password" => ""}) end)
     |> assign_new(:reauth_error, fn -> nil end)
     |> assign_new(:reauth_challenge, fn -> nil end)}
  end

  @impl true
  def handle_event("cancel_reauth", _params, socket) do
    notify_parent(:reauth_cancelled)
    {:noreply, socket}
  end

  def handle_event("reauth_with_password", %{"password" => password}, socket) do
    user = socket.assigns.user

    case Accounts.get_user_by_email_and_password(user.email, password) do
      nil ->
        {:noreply,
         assign(socket, :reauth_error, "Invalid password. Please try again.")}

      _valid_user ->
        notify_parent(:reauth_verified)
        {:noreply, socket}
    end
  end

  def handle_event("reauth_with_passkey", _params, socket) do
    Ysc.Logging.info("[ReauthComponent] reauth_with_passkey event received")

    challenge =
      :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    {:noreply,
     socket
     |> assign(:reauth_challenge, challenge)
     |> push_event("create_authentication_challenge", %{
       options: %{
         challenge: challenge,
         timeout: 60_000,
         userVerification: "required"
       }
     })}
  end

  def handle_event("verify_authentication", _params, socket) do
    Ysc.Logging.info("[ReauthComponent] verify_authentication event received")
    notify_parent(:reauth_verified)
    {:noreply, socket}
  end

  def handle_event("passkey_auth_error", %{"error" => error}, socket) do
    Ysc.Logging.debug("[ReauthComponent] Passkey auth error: #{inspect(error)}")

    {:noreply,
     assign(
       socket,
       :reauth_error,
       "Passkey authentication failed. Please try again."
     )}
  end

  def handle_event("reauth_with_google", _params, socket) do
    url =
      ~p"/auth/google?#{[reauth: "true", return_to: socket.assigns.return_to]}"

    {:noreply, Phoenix.LiveView.redirect(socket, to: url)}
  end

  def handle_event("reauth_with_facebook", _params, socket) do
    url =
      ~p"/auth/facebook?#{[reauth: "true", return_to: socket.assigns.return_to]}"

    {:noreply, Phoenix.LiveView.redirect(socket, to: url)}
  end

  # PasskeyAuth hook fires these via pushEvent (goes to LiveView), but also
  # via pushEventTo when data-push-to targets this component.
  def handle_event("passkey_support_detected", _params, socket),
    do: {:noreply, socket}

  def handle_event("user_agent_received", _params, socket),
    do: {:noreply, socket}

  def handle_event("device_detected", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id="reauth-modal"
        on_cancel={JS.push("cancel_reauth", target: @myself)}
        show
      >
        <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
          Verify Your Identity
        </h2>

        <p class="text-sm text-zinc-600 mb-6">{@description}</p>

        <%!-- Password + passkey are grouped inside the PasskeyAuth hook element.
             phx-target routes events (including render_hook in tests) to this component.
             data-push-to makes the JS hook use pushEventTo for verify/error events. --%>
        <div
          id="reauth-passkey-hook"
          class="space-y-4"
          phx-hook="PasskeyAuth"
          phx-target={@myself}
          data-push-to="reauth-passkey-hook"
        >
          <%!-- Password section --%>
          <div :if={@user_has_password} class="space-y-4">
            <h3 class="font-semibold text-zinc-900">Verify with your password</h3>
            <.simple_form
              for={@reauth_form}
              id="reauth_password_form"
              phx-submit="reauth_with_password"
              phx-target={@myself}
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
                  <p class="text-sm text-red-800">{@reauth_error}</p>
                </div>
              <% end %>
              <:actions>
                <.button phx-disable-with="Verifying..." class="w-full">
                  Continue
                </.button>
              </:actions>
            </.simple_form>
          </div>

          <%!-- Passkey section --%>
          <div class="space-y-3">
            <div :if={@user_has_password} class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-zinc-200"></div>
              </div>
              <div class="relative flex justify-center text-sm">
                <span class="px-2 bg-white text-zinc-500">OR</span>
              </div>
            </div>

            <h3 class="font-semibold text-zinc-900">
              {if @user_has_password,
                do: "Verify with a passkey",
                else: "Verify with your passkey"}
            </h3>
            <p class="text-sm text-zinc-600">
              Use your device's fingerprint, face recognition, or security key
            </p>
            <.button
              type="button"
              phx-click="reauth_with_passkey"
              phx-target={@myself}
              phx-disable-with="Verifying..."
              class="w-full"
            >
              <.icon name="hero-finger-print" class="w-5 h-5 me-2" />
              Continue with Passkey
            </.button>

            <%!-- Show error for passkey-only users (no password section to host it) --%>
            <%= if @reauth_error && !@user_has_password do %>
              <div class="p-3 bg-red-50 border border-red-200 rounded-md">
                <p class="text-sm text-red-800">{@reauth_error}</p>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- OAuth section — rendered outside the hook div since these cause a full
             page redirect and don't interact with WebAuthn. --%>
        <div class="mt-6 space-y-3">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-zinc-200"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="px-2 bg-white text-zinc-500">OR</span>
            </div>
          </div>

          <p class="text-sm font-semibold text-zinc-900">
            Verify with a social account
          </p>

          <.button
            type="button"
            variant="outline"
            class="w-full flex items-center justify-center gap-2 h-10 border-zinc-300 text-zinc-700"
            phx-click="reauth_with_google"
            phx-target={@myself}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              height="20"
              viewBox="0 0 24 24"
              width="20"
              class="w-5 h-5"
            >
              <path
                d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                fill="#4285F4"
              />
              <path
                d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                fill="#34A853"
              />
              <path
                d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                fill="#FBBC05"
              />
              <path
                d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                fill="#EA4335"
              />
              <path d="M1 1h22v22H1z" fill="none" />
            </svg>
            Continue with Google
          </.button>

          <.button
            type="button"
            variant="outline"
            class="w-full flex items-center justify-center gap-2 h-10 border-zinc-300 text-zinc-700"
            phx-click="reauth_with_facebook"
            phx-target={@myself}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              height="20"
              viewBox="0 0 24 24"
              width="20"
              class="w-5 h-5"
            >
              <path
                d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"
                fill="#1877F2"
              />
            </svg>
            Continue with Facebook
          </.button>
        </div>

        <div class="mt-4 text-center">
          <button
            type="button"
            phx-click="cancel_reauth"
            phx-target={@myself}
            class="text-sm text-zinc-500 hover:text-zinc-700"
          >
            Cancel
          </button>
        </div>
      </.modal>
    </div>
    """
  end

  defp notify_parent(msg), do: send(self(), msg)
end
