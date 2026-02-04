defmodule YscWeb.PasskeyRegistrationLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Accounts.UserPasskey

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
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
          <p class="text-sm text-red-800"><%= @error %></p>
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
          <.icon :if={@loading} name="hero-arrow-path" class="w-5 h-5 animate-spin" />
          <.icon :if={!@loading} name="hero-key" class="w-5 h-5" />
          <%= if @loading, do: "Creating Passkey...", else: "Create Passkey" %>
        </.button>

        <div :if={!@passkey_supported} class="text-center text-sm text-zinc-500">
          Your device doesn't support passkeys. Please use a modern browser with WebAuthn support.
        </div>

        <div class="mt-6 text-center">
          <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">
            ← Back to Home
          </.link>
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
       |> put_flash(:error, "You must be signed in to add a passkey.")
       |> redirect(to: ~p"/users/log-in")}
    else
      {:ok,
       assign(socket,
         page_title: "Add Passkey",
         passkey_supported: false,
         error: nil,
         success: false,
         loading: false,
         passkey_challenge: nil,
         user_agent: nil
       )}
    end
  end

  def handle_event("create_passkey", _params, socket) do
    require Logger
    user = socket.assigns.current_user

    # Set loading state
    socket = assign(socket, :loading, true)

    # Generate registration challenge
    # For registration, we need to provide user information
    user_id_binary = user.id

    try do
      # Get rp_id and origin from Wax config to ensure consistency
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

      require Logger

      # Convert challenge to JSON-serializable format for JS
      # Note: WebAuthn API requires camelCase keys
      challenge_json = %{
        challenge: Base.url_encode64(challenge.bytes, padding: false),
        timeout: challenge.timeout,
        rp: %{
          id: challenge.rp_id,
          name: "YSC"
        },
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
        Logger.error("[PasskeyRegistrationLive] Error creating challenge", %{
          error: inspect(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:noreply,
         assign(socket,
           error: "Failed to create passkey challenge. Please try again.",
           loading: false,
           passkey_challenge: nil
         )}
    end
  end

  def handle_event("verify_registration", response, socket) do
    challenge = socket.assigns.passkey_challenge
    user = socket.assigns.current_user

    if is_nil(challenge) do
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

        # Verify the registration
        # Wax.register returns {:ok, {auth_data, attestation_result_data}}
        case Wax.register(attestation_object, client_data_json, challenge) do
          {:ok, {auth_data, _attestation_result_data}} ->
            credential_data = auth_data.attested_credential_data
            credential_id = credential_data.credential_id
            public_key = credential_data.credential_public_key

            attrs = %{
              external_id: credential_id,
              public_key: UserPasskey.encode_public_key(public_key),
              nickname: get_device_nickname(socket.assigns[:user_agent])
            }

            case Accounts.create_user_passkey(user, attrs) do
              {:ok, passkey} ->
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
                 |> put_flash(
                   :info,
                   "Passkey added successfully! You can now use it to sign in."
                 )}

              {:error, _changeset} ->
                {:noreply,
                 assign(socket,
                   error: "Failed to save passkey. Please try again.",
                   loading: false,
                   passkey_challenge: nil
                 )}
            end

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error:
                 "Passkey registration failed: #{inspect(reason)}. Please try again.",
               loading: false,
               passkey_challenge: nil
             )}
        end
      rescue
        _ ->
          {:noreply,
           assign(socket,
             error: "Invalid passkey response. Please try again.",
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

  def handle_event("passkey_registration_error", _params, socket) do
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
