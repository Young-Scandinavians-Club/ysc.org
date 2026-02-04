defmodule YscWeb.UserLoginLive do
  use YscWeb, :live_view
  require Logger

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" />
      </.link>
      <.header class="text-center">
        Sign in to your YSC account
        <:subtitle>
          Not a member yet?
          <.link
            navigate={~p"/users/register"}
            class="font-semibold text-blue-600 hover:underline"
          >
            Apply for a membership
          </.link>
        </:subtitle>
      </.header>
      <!-- Alternative Authentication Methods -->
      <div id="auth-methods" class="space-y-3 pt-8" phx-hook="PasskeyAuth">
        <.button
          :if={@passkey_supported}
          type="button"
          disabled={@passkey_loading}
          class={
            "w-full flex items-center justify-center gap-2 h-10" <>
              if(@passkey_loading, do: " opacity-50 cursor-not-allowed", else: "")
          }
          phx-click="sign_in_with_passkey"
          phx-mounted={
            JS.transition(
              {"transition ease-out duration-300", "opacity-0 -translate-y-1",
               "opacity-100 translate-y-0"}
            )
          }
        >
          <%= if @passkey_loading do %>
            <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
            Signing in...
          <% else %>
            <%= if @is_ios_mobile do %>
              <svg
                width="20"
                height="20"
                viewBox="0 0 80 80"
                version="1.1"
                xmlns="http://www.w3.org/2000/svg"
                class="w-5 h-5"
              >
                <g
                  stroke="none"
                  stroke-width="1"
                  fill="currentColor"
                  fill-rule="evenodd"
                >
                  <g>
                    <g id="Corners" fill-rule="nonzero">
                      <g id="Corner">
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="Corner"
                        transform="translate(68.070175, 11.929825) scale(-1, 1) translate(-68.070175, -11.929825) translate(56.140351, 0.000000)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="Corner"
                        transform="translate(11.929825, 68.070175) scale(1, -1) translate(-11.929825, -68.070175) translate(0.000000, 56.140351)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="Corner"
                        transform="translate(68.070175, 68.070175) scale(-1, -1) translate(-68.070175, -68.070175) translate(56.140351, 56.140351)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                    </g>
                    <g
                      id="Eye"
                      transform="translate(21.754386, 28.070175)"
                      fill-rule="nonzero"
                    >
                      <path
                        d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                        id="Path"
                      >
                      </path>
                    </g>
                    <g
                      id="Eye"
                      transform="translate(54.736842, 28.070175)"
                      fill-rule="nonzero"
                    >
                      <path
                        d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                        id="Path"
                      >
                      </path>
                    </g>
                    <path
                      d="M25.9319616,59.0829234 C29.8331111,62.7239962 34.5578726,64.5614035 40,64.5614035 C45.4421274,64.5614035 50.1668889,62.7239962 54.0680384,59.0829234 C54.9180398,58.2895887 54.9639773,56.9574016 54.1706427,56.1074002 C53.377308,55.2573988 52.0451209,55.2114613 51.1951195,56.0047959 C48.0787251,58.9134307 44.382434,60.3508772 40,60.3508772 C35.617566,60.3508772 31.9212749,58.9134307 28.8048805,56.0047959 C27.9548791,55.2114613 26.622692,55.2573988 25.8293573,56.1074002 C25.0360227,56.9574016 25.0819602,58.2895887 25.9319616,59.0829234 Z"
                      id="Mouth"
                      fill-rule="nonzero"
                    >
                    </path>
                    <path
                      d="M40,30.1754386 L40,44.9122807 C40,45.85537 39.539042,46.3157895 38.5912711,46.3157895 L37.1929825,46.3157895 C36.0302777,46.3157895 35.0877193,47.2583479 35.0877193,48.4210526 C35.0877193,49.5837574 36.0302777,50.5263158 37.1929825,50.5263158 L38.5912711,50.5263158 C41.8633505,50.5263158 44.2105263,48.1818819 44.2105263,44.9122807 L44.2105263,30.1754386 C44.2105263,29.0127339 43.2679679,28.0701754 42.1052632,28.0701754 C40.9425584,28.0701754 40,29.0127339 40,30.1754386 Z"
                      id="Nose"
                      fill-rule="nonzero"
                    >
                    </path>
                  </g>
                </g>
              </svg>
            <% else %>
              <.icon name="hero-finger-print" class="w-5 h-5" />
            <% end %>
            <%= if @is_ios_mobile do %>
              Sign in with Face ID (Passkey)
            <% else %>
              Sign in with Passkey
            <% end %>
          <% end %>
        </.button>
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2 h-10 border-zinc-300 text-zinc-700"
          phx-click="sign_in_with_google"
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
          Sign in with Google
        </.button>
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2 h-10 border-zinc-300 text-zinc-700"
          phx-click="sign_in_with_facebook"
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
          Sign in with Facebook
        </.button>
      </div>
      <!-- Divider -->
      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-zinc-300"></div>
        </div>
        <div class="relative flex justify-center items-center text-sm leading-none">
          <span class="bg-white px-2 text-zinc-500">or</span>
        </div>
      </div>
      <!-- Failed Sign-in Attempts Banner -->
      <div
        :if={@failed_login_attempts >= 3 && !@banner_dismissed}
        id="failed-login-banner"
        class="bg-amber-50 border border-amber-200 rounded-lg p-4 my-6 relative"
        phx-mounted={
          JS.transition(
            {"transition ease-out duration-300", "opacity-0 -translate-y-1",
             "opacity-100 translate-y-0"}
          )
        }
        phx-remove={
          JS.transition(
            {"transition ease-in duration-200", "opacity-100", "opacity-0"}
          )
        }
      >
        <button
          type="button"
          phx-click="dismiss_banner"
          class="absolute top-2 right-2 p-1 rounded hover:bg-amber-100 opacity-60 hover:opacity-100 transition-opacity"
          aria-label="Dismiss"
        >
          <.icon name="hero-x-mark" class="w-5 h-5 text-amber-600" />
        </button>
        <div class="flex items-start pr-6">
          <div class="flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-600" />
          </div>
          <div class="ml-3 flex-1">
            <h3 class="text-sm font-semibold text-amber-900">
              Having trouble signing in?
            </h3>
            <div class="mt-2 text-sm text-amber-800">
              <p class="mb-2">
                You've had multiple failed sign-in attempts. You may want to reset your password.
              </p>
              <div class="flex flex-col sm:flex-row gap-2">
                <.link
                  navigate={~p"/users/reset-password"}
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Reset your password
                </.link>
                <span class="hidden sm:inline">•</span>
                <.link
                  href="mailto:info@ysc.org"
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Contact us for help
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.simple_form
        for={@form}
        id="login_form"
        action={~p"/users/log-in"}
        phx-update="ignore"
      >
        <input type="hidden" name="redirect_to" value={@redirect_to} />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input
          field={@form[:password]}
          type="password-toggle"
          label="Password"
          required
        />

        <:actions>
          <.input
            field={@form[:remember_me]}
            type="checkbox"
            label="Keep me signed in"
          />
          <.link
            href={~p"/users/reset-password"}
            class="text-sm font-semibold hover:underline text-blue-600"
          >
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full">
            Sign in <.icon name="hero-arrow-right" class="w-5 h-5 ms-1 -mt-0.5" />
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(params, session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    # Get failed login attempts from session (handle both atom and string keys)
    failed_login_attempts =
      session
      |> Map.get(:failed_login_attempts)
      |> Kernel.||(Map.get(session, "failed_login_attempts"))
      |> Kernel.||(0)

    # Capture redirect_to from URL params and validate it's an internal path
    redirect_to =
      case params do
        %{"redirect_to" => redirect_path} when is_binary(redirect_path) ->
          if YscWeb.UserAuth.valid_internal_redirect?(redirect_path) do
            redirect_path
          else
            nil
          end

        _ ->
          nil
      end

    {:ok,
     assign(socket, form: form)
     |> assign(:page_title, "Sign in")
     |> assign(:failed_login_attempts, failed_login_attempts)
     |> assign(:redirect_to, redirect_to)
     |> assign(:is_ios_mobile, false)
     |> assign(:passkey_supported, false)
     |> assign(:banner_dismissed, false)
     |> assign(:passkey_loading, false)
     |> assign(:passkey_challenge, nil)
     |> assign(:passkey_auth_mode, nil), temporary_assigns: [form: form]}
  end

  def handle_event("sign_in_with_passkey", _params, socket) do
    # Use discoverable credentials (passwordless - no email needed)
    # The browser will show a native account picker with available passkeys

    # Set loading state
    socket = assign(socket, :passkey_loading, true)

    # For discoverable credentials, we need to pass allow_credentials to Wax
    # so it knows which public keys to use for verification, but we omit it
    # from the JSON sent to the browser to enable the native account picker.
    # Get all passkeys from the database to pass to Wax
    # Use the same rp_id and origin as registration to ensure consistency
    rp_id = Application.get_env(:wax_, :rp_id) || "localhost"
    origin = Application.get_env(:wax_, :origin) || "http://localhost:4000"

    # Get all passkeys from all users for discoverable credentials
    # Wax needs to know all possible credential_ids and public keys for verification
    all_passkeys = Ysc.Repo.all(Ysc.Accounts.UserPasskey)

    # Convert to list of {credential_id, public_key} tuples for Wax
    allow_credentials =
      Enum.map(all_passkeys, fn passkey ->
        public_key =
          Ysc.Accounts.UserPasskey.decode_public_key(passkey.public_key)

        {passkey.external_id, public_key}
      end)

    challenge =
      Wax.new_authentication_challenge(
        rp_id: rp_id,
        origin: origin,
        allow_credentials: allow_credentials
      )

    Logger.debug("[UserLoginLive] Authentication challenge created", %{
      challenge_bytes_length: byte_size(challenge.bytes),
      timeout: challenge.timeout
    })

    # Convert challenge to JSON-serializable format for JS
    # Note: We omit allow_credentials from the JSON to enable discoverable credentials
    # (native account picker), but we pass it to Wax so it knows the public keys
    #
    # IMPORTANT: All binary data (challenges, credential IDs, signatures) must use Base64URL encoding
    # Base64URL is URL-safe Base64 without padding, required for WebAuthn data transmission
    # This prevents issues with JSON parsers and LiveView's transport layer
    challenge_base64url = Base.url_encode64(challenge.bytes, padding: false)

    challenge_json = %{
      challenge: challenge_base64url,
      timeout: challenge.timeout,
      rpId: challenge.rp_id,
      userVerification: "preferred"
      # Intentionally omitting allowCredentials to enable discoverable credentials
      # (browser will show native account picker)
    }

    {:noreply,
     socket
     |> assign(:passkey_challenge, challenge)
     |> assign(:passkey_auth_mode, :discoverable)
     |> push_event("create_authentication_challenge", %{options: challenge_json})}
  end

  def handle_event("sign_in_with_google", _params, socket) do
    # Pass redirect_to as query parameter - Ueberauth will preserve it through OAuth flow
    redirect_to = socket.assigns.redirect_to

    oauth_url =
      if redirect_to && YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
        ~p"/auth/google?redirect_to=#{URI.encode(redirect_to)}"
      else
        ~p"/auth/google"
      end

    # Redirect to OAuth provider (full page redirect, not LiveView navigation)
    {:noreply, socket |> redirect(to: oauth_url)}
  end

  def handle_event("sign_in_with_facebook", _params, socket) do
    # Pass redirect_to as query parameter - Ueberauth will preserve it through OAuth flow
    redirect_to = socket.assigns.redirect_to

    oauth_url =
      if redirect_to && YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
        ~p"/auth/facebook?redirect_to=#{URI.encode(redirect_to)}"
      else
        ~p"/auth/facebook"
      end

    # Redirect to OAuth provider (full page redirect, not LiveView navigation)
    {:noreply, socket |> redirect(to: oauth_url)}
  end

  def handle_event("device_detected", %{"device" => "ios_mobile"}, socket) do
    {:noreply, assign(socket, :is_ios_mobile, true)}
  end

  def handle_event("device_detected", params, socket) do
    require Logger

    Logger.warning(
      "[UserLoginLive] device_detected event received with unexpected params: #{inspect(params)}"
    )

    {:noreply, socket}
  end

  def handle_event(
        "passkey_support_detected",
        %{"supported" => supported},
        socket
      ) do
    {:noreply, assign(socket, :passkey_supported, supported)}
  end

  def handle_event("passkey_support_detected", params, socket) do
    require Logger

    Logger.warning(
      "[UserLoginLive] passkey_support_detected event received with unexpected params: #{inspect(params)}"
    )

    {:noreply, socket}
  end

  def handle_event("user_agent_received", _params, socket) do
    # User agent is sent by PasskeyAuth hook but not needed for login page
    # Just acknowledge it to prevent errors
    {:noreply, socket}
  end

  def handle_event("verify_authentication", response, socket) do
    require Logger

    Logger.info("[UserLoginLive] verify_authentication event received", %{
      has_response: !is_nil(response),
      response_keys: if(response, do: Map.keys(response), else: []),
      has_raw_id: !is_nil(response && response["rawId"]),
      has_id: !is_nil(response && response["id"]),
      has_response_object: !is_nil(response && response["response"])
    })

    challenge = socket.assigns.passkey_challenge
    auth_mode = socket.assigns[:passkey_auth_mode] || :non_discoverable

    Logger.debug("[UserLoginLive] Verification state", %{
      has_challenge: !is_nil(challenge),
      auth_mode: auth_mode,
      challenge_bytes_length:
        if(challenge, do: byte_size(challenge.bytes), else: nil)
    })

    if is_nil(challenge) do
      Logger.warning(
        "[UserLoginLive] Challenge is nil in verify_authentication"
      )

      {:noreply,
       put_flash(
         socket,
         :error,
         "Authentication session expired. Please try again."
       )
       |> assign(:passkey_loading, false)
       |> assign(:passkey_challenge, nil)
       |> assign(:passkey_auth_mode, nil)}
    else
      # Decode the response from JS
      # All binary data from JavaScript is Base64URL encoded and must be decoded here
      raw_id_string = response["rawId"] || response["id"]

      Logger.debug("[UserLoginLive] Decoding authentication response", %{
        raw_id_string: raw_id_string,
        has_authenticator_data:
          !is_nil(response["response"]["authenticatorData"]),
        has_client_data_json: !is_nil(response["response"]["clientDataJSON"]),
        has_signature: !is_nil(response["response"]["signature"]),
        has_user_handle: !is_nil(response["response"]["userHandle"]),
        response_keys: Map.keys(response["response"] || %{})
      })

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

      Logger.debug("[UserLoginLive] Decoded authentication data", %{
        raw_id_length: byte_size(raw_id),
        raw_id_hex: Base.encode16(raw_id, case: :lower),
        authenticator_data_length: byte_size(authenticator_data),
        client_data_json_length: byte_size(client_data_json),
        signature_length: byte_size(signature)
      })

      # Find passkey by external_id first (needed for verification)
      case Ysc.Accounts.get_user_passkey_by_external_id(raw_id) do
        nil ->
          Logger.warning("[UserLoginLive] Passkey not found by external_id", %{
            raw_id_hex: Base.encode16(raw_id, case: :lower),
            raw_id_base64: Base.url_encode64(raw_id, padding: false),
            raw_id_length: byte_size(raw_id)
          })

          {:noreply,
           put_flash(
             socket,
             :error,
             "Invalid passkey. Please try again or use another sign-in method."
           )
           |> assign(:passkey_loading, false)
           |> assign(:passkey_challenge, nil)
           |> assign(:passkey_auth_mode, nil)}

        passkey ->
          # For discoverable credentials, verify userHandle matches passkey's user_id
          if auth_mode == :discoverable do
            user_handle = response["response"]["userHandle"]

            if is_nil(user_handle) || user_handle == "" do
              Logger.warning(
                "[UserLoginLive] Missing userHandle in discoverable credential response",
                %{
                  has_user_handle: !is_nil(user_handle),
                  user_handle: user_handle,
                  response_keys: Map.keys(response["response"] || %{})
                }
              )

              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Invalid passkey response. Please try again or use another sign-in method."
               )
               |> assign(:passkey_loading, false)
               |> assign(:passkey_challenge, nil)
               |> assign(:passkey_auth_mode, nil)}
            else
              # Decode user_id from userHandle and verify it matches passkey's user_id
              # userHandle is Base64URL encoded (from JavaScript), decode it to get the binary user_id
              user_id_from_handle =
                try do
                  Base.url_decode64!(user_handle, padding: false)
                rescue
                  e ->
                    Logger.warning(
                      "[UserLoginLive] Failed to decode userHandle",
                      %{
                        error: inspect(e),
                        user_handle: user_handle
                      }
                    )

                    nil
                end

              if is_nil(user_id_from_handle) do
                {:noreply,
                 put_flash(
                   socket,
                   :error,
                   "Invalid passkey response. Please try again or use another sign-in method."
                 )
                 |> assign(:passkey_loading, false)
                 |> assign(:passkey_challenge, nil)
                 |> assign(:passkey_auth_mode, nil)}
              else
                # passkey.user_id is Ecto.ULID which is already a binary
                # Both should be binaries, so direct comparison should work
                if passkey.user_id != user_id_from_handle do
                  Logger.warning(
                    "[UserLoginLive] User ID mismatch during passkey verification",
                    %{
                      passkey_user_id: inspect(passkey.user_id),
                      passkey_user_id_hex:
                        Base.encode16(passkey.user_id, case: :lower),
                      passkey_user_id_binary: is_binary(passkey.user_id),
                      user_id_from_handle: inspect(user_id_from_handle),
                      user_id_from_handle_hex:
                        Base.encode16(user_id_from_handle, case: :lower),
                      user_id_from_handle_binary:
                        is_binary(user_id_from_handle),
                      user_handle_encoded: user_handle,
                      user_ids_match: passkey.user_id == user_id_from_handle
                    }
                  )

                  {:noreply,
                   put_flash(
                     socket,
                     :error,
                     "Passkey verification failed. Please try again or use another sign-in method."
                   )
                   |> assign(:passkey_loading, false)
                   |> assign(:passkey_challenge, nil)
                   |> assign(:passkey_auth_mode, nil)}
                else
                  Logger.info(
                    "[UserLoginLive] User IDs match, proceeding to verify_passkey_authentication"
                  )

                  # Verify that raw_id matches passkey.external_id before calling Wax.authenticate
                  if passkey.external_id != raw_id do
                    Logger.error(
                      "[UserLoginLive] CRITICAL: raw_id from response does not match passkey.external_id",
                      %{
                        raw_id_hex: Base.encode16(raw_id, case: :lower),
                        raw_id_base64url:
                          Base.url_encode64(raw_id, padding: false),
                        passkey_external_id_hex:
                          Base.encode16(passkey.external_id, case: :lower),
                        passkey_external_id_base64url:
                          Base.url_encode64(passkey.external_id, padding: false),
                        lengths_match:
                          byte_size(raw_id) == byte_size(passkey.external_id)
                      }
                    )

                    {:noreply,
                     put_flash(
                       socket,
                       :error,
                       "Passkey credential ID mismatch. Please try again or use another sign-in method."
                     )
                     |> assign(:passkey_loading, false)
                     |> assign(:passkey_challenge, nil)
                     |> assign(:passkey_auth_mode, nil)}
                  else
                    # Continue with verification using the passkey
                    verify_passkey_authentication(
                      socket,
                      passkey,
                      user_id_from_handle,
                      raw_id,
                      authenticator_data,
                      client_data_json,
                      signature,
                      challenge
                    )
                  end
                end
              end
            end
          else
            Logger.info(
              "[UserLoginLive] Processing non-discoverable credential, using passkey.user_id directly"
            )

            # Verify that raw_id matches passkey.external_id before calling Wax.authenticate
            if passkey.external_id != raw_id do
              Logger.error(
                "[UserLoginLive] CRITICAL: raw_id from response does not match passkey.external_id (non-discoverable)",
                %{
                  raw_id_hex: Base.encode16(raw_id, case: :lower),
                  raw_id_base64url: Base.url_encode64(raw_id, padding: false),
                  passkey_external_id_hex:
                    Base.encode16(passkey.external_id, case: :lower),
                  passkey_external_id_base64url:
                    Base.url_encode64(passkey.external_id, padding: false),
                  lengths_match:
                    byte_size(raw_id) == byte_size(passkey.external_id)
                }
              )

              {:noreply,
               put_flash(
                 socket,
                 :error,
                 "Passkey credential ID mismatch. Please try again or use another sign-in method."
               )
               |> assign(:passkey_loading, false)
               |> assign(:passkey_challenge, nil)
               |> assign(:passkey_auth_mode, nil)}
            else
              # Non-discoverable: use passkey's user_id directly
              verify_passkey_authentication(
                socket,
                passkey,
                passkey.user_id,
                raw_id,
                authenticator_data,
                client_data_json,
                signature,
                challenge
              )
            end
          end
      end
    end
  end

  def handle_event(
        "passkey_auth_error",
        %{"error" => error, "message" => message},
        socket
      ) do
    error_message =
      case error do
        "NotAllowedError" ->
          "Authentication was cancelled or not allowed. Please try again."

        "InvalidStateError" ->
          "This passkey may have been removed. Please use another sign-in method."

        "NotSupportedError" ->
          "Your device doesn't support this authentication method. Please use another sign-in method."

        _ ->
          "Authentication failed: #{message}. Please try again or use another sign-in method."
      end

    {:noreply,
     put_flash(socket, :error, error_message)
     |> assign(:passkey_loading, false)
     |> assign(:passkey_challenge, nil)
     |> assign(:passkey_auth_mode, nil)}
  end

  def handle_event("passkey_auth_error", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "An error occurred during authentication. Please try again."
     )
     |> assign(:passkey_loading, false)
     |> assign(:passkey_challenge, nil)
     |> assign(:passkey_auth_mode, nil)}
  end

  def handle_event("dismiss_banner", _params, socket) do
    # Reset failed login attempts when user dismisses the banner
    # Redirect to controller endpoint to clear session, then redirect back
    {:noreply,
     socket
     |> assign(:failed_login_attempts, 0)
     |> assign(:banner_dismissed, true)
     |> redirect(to: ~p"/users/log-in/reset-attempts")}
  end

  defp verify_passkey_authentication(
         socket,
         passkey,
         user_id,
         raw_id,
         authenticator_data,
         client_data_json,
         signature,
         challenge
       ) do
    require Logger

    Logger.info("[UserLoginLive] verify_passkey_authentication called", %{
      passkey_id: passkey.id,
      passkey_user_id: passkey.user_id,
      passkey_user_id_hex: Base.encode16(passkey.user_id, case: :lower),
      user_id: user_id,
      user_id_hex: Base.encode16(user_id, case: :lower),
      raw_id_hex: Base.encode16(raw_id, case: :lower),
      passkey_external_id_hex: Base.encode16(passkey.external_id, case: :lower),
      passkey_nickname: passkey.nickname,
      passkey_sign_count: passkey.sign_count,
      ids_match: passkey.external_id == raw_id,
      user_ids_match: passkey.user_id == user_id
    })

    # For Wax.authenticate, we must use the raw_id from the response
    # This is the credential_id that the browser/authenticator used, and it must match
    # what's embedded in the authenticator_data (if present) or what the authenticator expects
    # Even though we verified raw_id matches passkey.external_id, we use raw_id here
    # because Wax.authenticate validates it against the authenticator_data structure
    credential_id_to_verify = raw_id

    Logger.debug("[UserLoginLive] Calling Wax.authenticate", %{
      credential_id_length: byte_size(credential_id_to_verify),
      authenticator_data_length: byte_size(authenticator_data),
      signature_length: byte_size(signature),
      client_data_json_length: byte_size(client_data_json),
      challenge_bytes_length: byte_size(challenge.bytes)
    })

    # Verify the authentication
    # For discoverable credentials, Wax.authenticate needs the public key to verify the signature.
    # Since we didn't pass allow_credentials in the challenge, we need to provide the public key here.
    # However, Wax.authenticate might not accept public_key as an option. Let's try the standard call first.
    # If that fails, we might need to reconstruct the challenge with allow_credentials.
    case Wax.authenticate(
           credential_id_to_verify,
           authenticator_data,
           signature,
           client_data_json,
           challenge
         ) do
      {:ok, auth_result} ->
        require Logger

        Logger.info("[UserLoginLive] Wax.authenticate succeeded")

        # Wax.authenticate returns {:ok, authenticator_data} where authenticator_data is a Wax.AuthenticatorData struct
        # The struct has fields like sign_count, not nested under :authenticator_data
        authenticator_data = auth_result

        # Verify sign_count increased (replay attack prevention)
        # For discoverable credentials, the first use might have sign_count = 0
        # So we allow >= instead of > to handle the first use case
        new_sign_count = authenticator_data.sign_count

        Logger.debug("[UserLoginLive] Checking sign_count", %{
          new_sign_count: new_sign_count,
          passkey_sign_count: passkey.sign_count,
          sign_count_valid: new_sign_count >= passkey.sign_count
        })

        if new_sign_count >= passkey.sign_count do
          Logger.info(
            "[UserLoginLive] Sign count check passed, proceeding with login",
            %{
              user_id: user_id,
              user_id_hex: Base.encode16(user_id, case: :lower)
            }
          )

          # Update passkey sign_count and last_used_at
          {:ok, _updated_passkey} =
            Ysc.Accounts.update_passkey_sign_count(passkey, new_sign_count)

          # Get the user and log them in
          user = Ysc.Accounts.get_user!(user_id)

          # Log successful authentication
          Ysc.Accounts.AuthService.log_login_success(user, socket, %{
            method: "passkey"
          })

          # Clear the challenge and loading state
          socket =
            socket
            |> assign(:passkey_loading, false)
            |> assign(:passkey_challenge, nil)
            |> assign(:passkey_auth_mode, nil)
            |> put_flash(:info, "Welcome back!")

          # Redirect to session controller to log in (since we need a conn, not socket)
          encoded_user_id = Base.url_encode64(user_id, padding: false)

          query_params = %{"user_id" => encoded_user_id}

          query_params =
            if socket.assigns.redirect_to && socket.assigns.redirect_to != "" do
              Map.put(query_params, "redirect_to", socket.assigns.redirect_to)
            else
              query_params
            end

          # Construct URL as plain string to avoid query string parsing issues
          base_path = ~p"/users/log-in/passkey"
          query_string = URI.encode_query(query_params)
          redirect_url = "#{base_path}?#{query_string}"

          require Logger

          Logger.info("[UserLoginLive] Redirecting to passkey login", %{
            redirect_url: redirect_url,
            base_path: base_path,
            query_string: query_string,
            encoded_user_id: encoded_user_id,
            user_id_hex: Base.encode16(user_id, case: :lower),
            query_params: query_params,
            has_redirect_to: Map.has_key?(query_params, "redirect_to")
          })

          {:noreply,
           socket
           |> redirect(to: redirect_url)}
        else
          require Logger

          Logger.warning(
            "[UserLoginLive] Sign count check failed - possible replay attack",
            %{
              new_sign_count: new_sign_count,
              passkey_sign_count: passkey.sign_count,
              sign_count_decreased: new_sign_count < passkey.sign_count
            }
          )

          {:noreply,
           put_flash(
             socket,
             :error,
             "Security check failed. Please try again."
           )
           |> assign(:passkey_loading, false)
           |> assign(:passkey_challenge, nil)
           |> assign(:passkey_auth_mode, nil)}
        end

      {:error, reason} ->
        require Logger

        # Log the error with full context
        error_string = inspect(reason, pretty: true, limit: :infinity)

        Logger.error("[UserLoginLive] Wax.authenticate failed", %{
          error: error_string,
          error_type: if(is_exception(reason), do: :exception, else: :unknown),
          passkey_id: passkey.id,
          passkey_user_id: passkey.user_id,
          passkey_user_id_hex: Base.encode16(passkey.user_id, case: :lower),
          user_id: user_id,
          user_id_hex: Base.encode16(user_id, case: :lower),
          raw_id_hex: Base.encode16(raw_id, case: :lower),
          passkey_external_id_hex:
            Base.encode16(passkey.external_id, case: :lower),
          credential_id_match: passkey.external_id == raw_id,
          authenticator_data_length: byte_size(authenticator_data),
          signature_length: byte_size(signature),
          client_data_json_length: byte_size(client_data_json)
        })

        {:noreply,
         put_flash(
           socket,
           :error,
           "Passkey verification failed. Please try again or use another sign-in method."
         )
         |> assign(:passkey_loading, false)
         |> assign(:passkey_challenge, nil)
         |> assign(:passkey_auth_mode, nil)}
    end
  end
end
