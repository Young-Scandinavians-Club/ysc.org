defmodule YscWeb.PasskeyRegistrationLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Accounts.UserPasskey

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.live_component
        :if={@show_reauth}
        module={YscWeb.ReauthComponent}
        id="reauth"
        user={@current_user}
        user_has_password={@user_has_password}
        return_to={~p"/users/settings/passkeys/new"}
        description="For security reasons, please verify your identity before adding a passkey."
      />

      <div :if={!@show_reauth}>
        <.header class="text-center">
          Add a Passkey to Your Account
          <:subtitle>
            Use your device's fingerprint or face scan to sign in faster
          </:subtitle>
        </.header>

        <div id="passkey-registration" class="space-y-3 pt-8" phx-hook="PasskeyAuth">
          <div
            :if={@error}
            class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6"
          >
            <p class="text-sm text-red-800">{@error}</p>
          </div>

          <div
            :if={@success}
            class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6"
          >
            <p class="text-sm text-green-800">
              Passkey added successfully! You can now use it to sign in.
            </p>
          </div>

          <.button
            :if={@passkey_supported && !@success}
            type="button"
            disabled={@loading}
            class={
              "w-full flex items-center justify-center gap-2 h-10" <>
                if(@loading, do: " opacity-50 cursor-not-allowed", else: "")
            }
            phx-click="create_passkey"
            phx-mounted={
              JS.transition(
                {"transition ease-out duration-300", "opacity-0 -translate-y-1",
                 "opacity-100 translate-y-0"}
              )
            }
          >
            <.icon
              :if={@loading}
              name="hero-arrow-path"
              class="w-5 h-5 animate-spin"
            />
            <.icon :if={!@loading} name="hero-key" class="w-5 h-5" />
            {if @loading, do: "Creating Passkey...", else: "Create Passkey"}
          </.button>

          <div :if={!@passkey_supported} class="text-center text-sm text-zinc-500">
            This device or browser can't set up sign-in with Face ID or fingerprint. You can still sign in with your email and password, or try again on a phone or computer that supports it.
          </div>

          <div class="mt-6 text-center">
            <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
              ← Back to Home
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "You must be signed in to add a passkey."
       )
       |> redirect(to: ~p"/users/log-in")}
    else
      reauth_verified = socket.assigns[:session_reauth_verified] || false

      {:ok,
       assign(socket,
         page_title: "Add Passkey",
         meta_description:
           "Register a passkey for secure, passwordless sign-in to Young Scandinavians Club.",
         passkey_supported: false,
         error: nil,
         success: false,
         loading: false,
         passkey_challenge: nil,
         user_agent: nil,
         show_reauth: !reauth_verified,
         user_has_password: !is_nil(user.hashed_password)
       )}
    end
  end

  def handle_info(:reauth_verified, socket) do
    {:noreply, assign(socket, :show_reauth, false)}
  end

  def handle_info(:reauth_cancelled, socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/settings/security")}
  end

  def handle_event("create_passkey", _params, socket) do
    if socket.assigns.show_reauth do
      {:noreply,
       assign(socket,
         error: "Re-authentication is required before adding a passkey.",
         loading: false
       )}
    else
      do_create_passkey(socket)
    end
  end

  def handle_event("verify_registration", _response, socket)
      when socket.assigns.show_reauth do
    {:noreply,
     assign(socket,
       error: "Re-authentication is required before adding a passkey.",
       loading: false,
       passkey_challenge: nil
     )}
  end

  def handle_event("verify_registration", response, socket) do
    require Ysc.Logging

    challenge = socket.assigns.passkey_challenge
    user = socket.assigns.current_user

    Ysc.Logging.info(
      "[PasskeyRegistrationLive] verify_registration event received",
      %{
        has_challenge: !is_nil(challenge),
        has_response: !is_nil(response),
        user_id: user.id,
        response_keys: if(response, do: Map.keys(response), else: [])
      }
    )

    if is_nil(challenge) do
      Ysc.Logging.warning(
        "[PasskeyRegistrationLive] Challenge is nil in verify_registration"
      )

      {:noreply,
       assign(socket,
         error: "Registration session expired. Please try again.",
         loading: false,
         passkey_challenge: nil
       )}
    else
      try do
        attestation_object =
          Base.url_decode64!(response["response"]["attestationObject"],
            padding: false
          )

        client_data_json =
          Base.url_decode64!(response["response"]["clientDataJSON"],
            padding: false
          )

        Ysc.Logging.debug(
          "[PasskeyRegistrationLive] Decoded registration data",
          %{
            attestation_object_length: byte_size(attestation_object),
            client_data_json_length: byte_size(client_data_json)
          }
        )

        # Verify the registration
        # Wax.register returns {:ok, {auth_data, attestation_result_data}}
        case Wax.register(attestation_object, client_data_json, challenge) do
          {:ok, {auth_data, _attestation_result_data}} ->
            credential_data = auth_data.attested_credential_data
            credential_id = credential_data.credential_id
            public_key = credential_data.credential_public_key

            Ysc.Logging.info(
              "[PasskeyRegistrationLive] Wax.register succeeded",
              %{
                credential_id_length: byte_size(credential_id),
                credential_id_hex: Base.encode16(credential_id, case: :lower)
              }
            )

            attrs = %{
              external_id: credential_id,
              public_key: UserPasskey.encode_public_key(public_key),
              nickname: get_device_nickname(socket.assigns[:user_agent])
            }

            case Accounts.create_user_passkey(user, attrs) do
              {:ok, passkey} ->
                Ysc.Logging.info(
                  "[PasskeyRegistrationLive] Passkey created successfully",
                  %{
                    passkey_id: passkey.id,
                    passkey_nickname: passkey.nickname
                  }
                )

                # Send security notification email
                UserNotifier.deliver_passkey_added_notification(
                  user,
                  passkey.nickname
                )

                {:noreply,
                 socket
                 |> assign(:success, true)
                 |> assign(:error, nil)
                 |> assign(:loading, false)
                 |> assign(:passkey_challenge, nil)
                 |> YscWeb.Flash.put_toast(
                   :info,
                   "Passkey added successfully! You can now use it to sign in.",
                   title: "Passkey added",
                   icon: &YscWeb.CoreComponents.flash_toast_icon_shield/1
                 )}

              {:error, changeset} ->
                Ysc.Logging.error(
                  "[PasskeyRegistrationLive] Failed to save passkey",
                  error: "Database save failed",
                  changeset_errors: inspect(changeset.errors),
                  user_id: user.id
                )

                {:noreply,
                 assign(socket,
                   error: "Failed to save passkey. Please try again.",
                   loading: false,
                   passkey_challenge: nil
                 )}
            end

          {:error, reason} ->
            Ysc.Logging.warning("[PasskeyRegistrationLive] Wax.register failed",
              error: reason,
              user_id: user.id
            )

            {:noreply,
             assign(socket,
               error:
                 "Passkey registration did not complete. Please try again, or use another way to sign in.",
               loading: false,
               passkey_challenge: nil
             )}
        end
      rescue
        e in ArgumentError ->
          Ysc.Logging.warning(
            "[PasskeyRegistrationLive] Failed to decode base64 data",
            error: Exception.message(e),
            stacktrace: __STACKTRACE__,
            user_id: user.id,
            has_attestation_object:
              !is_nil(response["response"]["attestationObject"]),
            has_client_data_json:
              !is_nil(response["response"]["clientDataJSON"])
          )

          {:noreply,
           assign(socket,
             error: "Invalid passkey response. Please try again.",
             loading: false,
             passkey_challenge: nil
           )}

        e ->
          Ysc.Logging.error(
            "[PasskeyRegistrationLive] Unexpected error during registration",
            error: Exception.message(e),
            error_type: e.__struct__,
            stacktrace: __STACKTRACE__,
            user_id: user.id
          )

          {:noreply,
           assign(socket,
             error: "An unexpected error occurred. Please try again.",
             loading: false,
             passkey_challenge: nil
           )}
      end
    end
  end

  def handle_event(
        "passkey_registration_error",
        %{"error" => error, "message" => message},
        socket
      ) do
    error_message =
      case error do
        "NotAllowedError" ->
          "Registration was cancelled or not allowed. Please try again."

        "InvalidStateError" ->
          "A passkey may already exist for this device. Please use another device or remove the existing passkey."

        "NotSupportedError" ->
          "Your device doesn't support this authentication method. Please use another device."

        _ ->
          "Registration failed: #{message}. Please try again."
      end

    {:noreply,
     assign(socket,
       error: error_message,
       loading: false,
       passkey_challenge: nil
     )}
  end

  def handle_event("passkey_registration_error", params, socket) do
    require Ysc.Logging

    error_name = params["error"] || "UnknownError"
    error_message_raw = params["message"] || "Registration failed"

    # Log the error with context
    Ysc.Logging.warning(
      "[PasskeyRegistrationLive] Passkey registration error from client (fallback handler)",
      error: error_name,
      message: error_message_raw,
      params: params,
      user_id: socket.assigns.current_user.id,
      user_agent: socket.assigns[:user_agent],
      has_challenge: !is_nil(socket.assigns[:passkey_challenge])
    )

    {:noreply,
     assign(socket,
       error: "An error occurred during registration. Please try again.",
       loading: false,
       passkey_challenge: nil
     )}
  end

  def handle_event(
        "passkey_support_detected",
        %{"supported" => supported},
        socket
      ) do
    {:noreply, assign(socket, :passkey_supported, supported)}
  end

  def handle_event("passkey_support_detected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("user_agent_received", %{"user_agent" => user_agent}, socket) do
    {:noreply, assign(socket, :user_agent, user_agent)}
  end

  def handle_event("user_agent_received", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("device_detected", _params, socket), do: {:noreply, socket}

  defp do_create_passkey(socket) do
    require Ysc.Logging

    user = socket.assigns.current_user
    user_id_binary = user.id

    socket = assign(socket, :loading, true)

    try do
      rp_id = Application.get_env(:wax_, :rp_id) || "localhost"
      origin = get_origin()

      challenge =
        Wax.new_registration_challenge(
          origin: origin,
          rp_id: rp_id,
          user: %{
            id: user_id_binary,
            name: user.email,
            display_name: "#{user.first_name} #{user.last_name}"
          },
          user_verification: "preferred",
          authenticator_selection: %{
            authenticator_attachment: "platform",
            user_verification: "preferred",
            require_resident_key: true
          }
        )

      challenge_json = %{
        challenge: Base.url_encode64(challenge.bytes, padding: false),
        timeout: challenge.timeout,
        rp: %{id: challenge.rp_id, name: "YSC"},
        user: %{
          id: Base.url_encode64(user_id_binary, padding: false),
          name: user.email,
          displayName: "#{user.first_name} #{user.last_name}"
        },
        pubKeyCredParams: [
          %{type: "public-key", alg: -7},
          %{type: "public-key", alg: -257}
        ],
        authenticatorSelection: %{
          authenticatorAttachment: "platform",
          userVerification: "preferred",
          requireResidentKey: true
        }
      }

      {:noreply,
       socket
       |> assign(:passkey_challenge, challenge)
       |> push_event("create_registration_challenge", %{options: challenge_json})}
    rescue
      e ->
        Ysc.Logging.error(
          "[PasskeyRegistrationLive] Error creating challenge",
          %{
            error: inspect(e),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          }
        )

        {:noreply,
         assign(socket,
           error: "Failed to create passkey challenge. Please try again.",
           loading: false,
           passkey_challenge: nil
         )}
    end
  end

  defp get_origin do
    # Get origin from Wax config
    Application.get_env(:wax_, :origin) || "http://localhost:4000"
  end

  defp get_device_nickname(user_agent) do
    if user_agent && user_agent != "" do
      parse_user_agent_to_nickname(user_agent)
    else
      "Device"
    end
  end

  defp parse_user_agent_to_nickname(user_agent) do
    # Use the existing AuthEvent parsing logic
    parsed = Ysc.Accounts.AuthEvent.parse_user_agent(user_agent)
    browser = Map.get(parsed, :browser, "Unknown")
    os = Map.get(parsed, :operating_system, "Unknown")
    device_type = Map.get(parsed, :device_type, "unknown")

    # Create a descriptive nickname
    cond do
      browser != "Unknown" && os != "Unknown" ->
        "#{browser} on #{os}"

      browser != "Unknown" ->
        browser

      os != "Unknown" ->
        "#{device_type} (#{os})"

      true ->
        String.capitalize(device_type)
    end
  end
end
