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
  alias Ysc.Accounts.UserPasskey

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

    user = socket.assigns.user

    # Build allow_credentials from the user's registered passkeys so Wax can
    # verify the signature against the correct public key.
    allow_credentials =
      user
      |> Accounts.get_user_passkeys()
      |> Enum.map(fn pk ->
        {pk.external_id, UserPasskey.decode_public_key(pk.public_key)}
      end)

    rp_id = Application.get_env(:wax_, :rp_id) || "localhost"
    origin = Application.get_env(:wax_, :origin) || "http://localhost:4000"

    challenge =
      Wax.new_authentication_challenge(
        rp_id: rp_id,
        origin: origin,
        allow_credentials: allow_credentials
      )

    {:noreply,
     socket
     |> assign(:reauth_challenge, challenge)
     |> push_event("create_authentication_challenge", %{
       options: %{
         challenge: Base.url_encode64(challenge.bytes, padding: false),
         timeout: 60_000,
         userVerification: "required"
       }
     })}
  end

  def handle_event("verify_authentication", response, socket) do
    Ysc.Logging.info("[ReauthComponent] verify_authentication event received")

    challenge = socket.assigns.reauth_challenge
    user = socket.assigns.user

    if is_nil(challenge) do
      Ysc.Logging.warning(
        "[ReauthComponent] Challenge is nil in verify_authentication"
      )

      {:noreply,
       assign(
         socket,
         :reauth_error,
         "That sign-in timed out. Please try again, or verify with your password below."
       )}
    else
      try do
        raw_id_string = response["rawId"] || response["id"]
        raw_id = Base.url_decode64!(raw_id_string, padding: false)

        authenticator_data =
          Base.url_decode64!(response["response"]["authenticatorData"],
            padding: false
          )

        client_data_json =
          Base.url_decode64!(response["response"]["clientDataJSON"],
            padding: false
          )

        signature =
          Base.url_decode64!(response["response"]["signature"], padding: false)

        case Accounts.get_user_passkey_by_external_id(raw_id) do
          nil ->
            Ysc.Logging.warning(
              "[ReauthComponent] Passkey not found by external_id"
            )

            {:noreply,
             assign(
               socket,
               :reauth_error,
               "Passkey not recognized. Please try again."
             )}

          passkey ->
            if passkey.user_id != user.id do
              Ysc.Logging.error(
                "[ReauthComponent] Passkey user_id mismatch — possible credential stuffing",
                passkey_user_id: inspect(passkey.user_id),
                current_user_id: inspect(user.id)
              )

              {:noreply,
               assign(
                 socket,
                 :reauth_error,
                 "Passkey verification failed. Please try again."
               )}
            else
              case Wax.authenticate(
                     raw_id,
                     authenticator_data,
                     signature,
                     client_data_json,
                     challenge
                   ) do
                {:ok, _auth_data} ->
                  notify_parent(:reauth_verified)
                  {:noreply, socket}

                {:error, reason} ->
                  Ysc.Logging.error("[ReauthComponent] Wax.authenticate failed",
                    error: inspect(reason),
                    user_id: user.id
                  )

                  {:noreply,
                   assign(
                     socket,
                     :reauth_error,
                     "Passkey authentication failed. Please try again."
                   )}
              end
            end
        end
      rescue
        e ->
          Ysc.Logging.error("[ReauthComponent] Error decoding passkey response",
            error: inspect(e)
          )

          {:noreply,
           assign(
             socket,
             :reauth_error,
             "Invalid passkey response. Please try again."
           )}
      end
    end
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
        <.modal_title id="reauth-modal-title">
          Verify Your Identity
        </.modal_title>

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
              <.form_notice
                :if={@reauth_error}
                kind={:error}
                id="reauth-password-error-notice"
                margin_bottom={false}
              >
                {@reauth_error}
              </.form_notice>
              <:actions>
                <.button phx-disable-with="Verifying..." class="w-full">
                  Verify with password
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
              <.icon name="hero-finger-print" class="w-5 h-5" />
              Continue with Passkey
            </.button>

            <%!-- Show error for passkey-only users (no password section to host it) --%>
            <.form_notice
              :if={@reauth_error && !@user_has_password}
              kind={:error}
              id="reauth-passkey-only-error-notice"
              margin_bottom={false}
            >
              {@reauth_error}
            </.form_notice>
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

          <.oauth_button
            provider={:google}
            label="Continue with Google"
            phx-click="reauth_with_google"
            phx-target={@myself}
          />

          <.oauth_button
            provider={:facebook}
            label="Continue with Facebook"
            phx-click="reauth_with_facebook"
            phx-target={@myself}
          />
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
