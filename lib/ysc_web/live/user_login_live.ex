defmodule YscWeb.UserLoginLive do
  use YscWeb, :live_view
  require Ysc.Logging

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-4 px-4">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-8 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" width={112} height={112} fetchpriority="high" />
      </.link>
      <.header class="text-center">
        Sign in to your YSC account
        <:subtitle>
          <span class="block">
            New to YSC?
            <.link
              navigate={~p"/users/register"}
              class="font-semibold text-blue-600 hover:underline"
            >
              Apply for membership
            </.link>
          </span>
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
                      <g id="corner-1">
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="corner-2"
                        transform="translate(68.070175, 11.929825) scale(-1, 1) translate(-68.070175, -11.929825) translate(56.140351, 0.000000)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="corner-3"
                        transform="translate(11.929825, 68.070175) scale(1, -1) translate(-11.929825, -68.070175) translate(0.000000, 56.140351)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                      <g
                        id="corner-4"
                        transform="translate(68.070175, 68.070175) scale(-1, -1) translate(-68.070175, -68.070175) translate(56.140351, 56.140351)"
                      >
                        <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                        </path>
                      </g>
                    </g>
                    <g
                      id="eye-1"
                      transform="translate(21.754386, 28.070175)"
                      fill-rule="nonzero"
                    >
                      <path
                        d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                        id="path-1"
                      >
                      </path>
                    </g>
                    <g
                      id="eye-2"
                      transform="translate(54.736842, 28.070175)"
                      fill-rule="nonzero"
                    >
                      <path
                        d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                        id="path-2"
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
              Sign in with Face ID
            <% else %>
              Sign in with Passkey
            <% end %>
          <% end %>
        </.button>
        <.oauth_button
          provider={:google}
          label="Sign in with Google"
          phx-click="sign_in_with_google"
        />
        <.oauth_button
          provider={:facebook}
          label="Sign in with Facebook"
          phx-click="sign_in_with_facebook"
        />
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
                You've had several failed sign-in attempts. Try another sign-in option below, reset your password if you use one, or contact us for help.
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
        onsubmit="this.querySelector('[type=submit]')?.setAttribute('disabled','disabled')"
      >
        <input type="hidden" name="redirect_to" value={@redirect_to || ""} />
        <div class="space-y-4">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
            autofocus
          />
          <.input
            field={@form[:password]}
            type="password-toggle"
            label="Password"
            required
          />
        </div>

        <:actions>
          <div class="flex flex-col gap-3 w-full pb-2">
            <.button phx-disable-with="Signing in..." class="w-full">
              Sign in <.icon name="hero-arrow-right" class="w-5 h-5 ms-1" />
            </.button>
            <div class="text-center">
              <.link
                href={~p"/users/reset-password"}
                class="text-sm font-semibold hover:underline text-blue-600"
              >
                Forgot your password?
              </.link>
            </div>
          </div>
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

    # Capture redirect_to from URL params, then fall back to session
    # `:user_return_to` (set by require_authenticated_user, e.g. OAuth authorize).
    redirect_to =
      case params do
        %{"redirect_to" => redirect_path}
        when is_binary(redirect_path) and redirect_path != "" ->
          if YscWeb.UserAuth.valid_internal_redirect?(redirect_path) do
            redirect_path
          else
            nil
          end

        _ ->
          session_return_to =
            Map.get(session, :user_return_to) ||
              Map.get(session, "user_return_to")

          if is_binary(session_return_to) and
               YscWeb.UserAuth.valid_internal_redirect?(session_return_to) do
            session_return_to
          else
            nil
          end
      end

    # Show toast when redirected from auto_login with expired/invalid token (query param
    # avoids session flash overwriting a concurrent successful login).
    socket =
      if params["reason"] == "expired_link" do
        YscWeb.Flash.put_toast(
          socket,
          :error,
          "Invalid or expired login link. Please sign in again.",
          title: "Login"
        )
      else
        socket
      end

    {:ok,
     assign(socket, form: form)
     |> assign(:page_title, "Sign in")
     |> assign(
       :meta_description,
       "Sign in to your Young Scandinavians Club account."
     )
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

    # For discoverable credentials, do not pre-load any passkeys.
    # The browser authenticator selects the credential locally and responds with
    # the credential_id (rawId). We look up that single passkey after the response
    # and inject its public key into the challenge before calling Wax.authenticate.
    # This avoids exposing all credential IDs and prevents a DoS via the DB query.
    rp_id = Application.get_env(:wax_, :rp_id) || "localhost"
    origin = Application.get_env(:wax_, :origin) || "http://localhost:4000"

    challenge =
      Wax.new_authentication_challenge(
        rp_id: rp_id,
        origin: origin,
        allow_credentials: []
      )

    Ysc.Logging.debug("[UserLoginLive] Authentication challenge created",
      challenge_bytes_length: byte_size(challenge.bytes),
      timeout: challenge.timeout
    )

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
    require Ysc.Logging

    Ysc.Logging.warning(
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
    require Ysc.Logging

    Ysc.Logging.warning(
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
    require Ysc.Logging

    Ysc.Logging.info("[UserLoginLive] verify_authentication event received",
      has_response: !is_nil(response),
      response_keys: Map.keys(response),
      has_raw_id: !is_nil(response["rawId"]),
      has_id: !is_nil(response["id"]),
      has_response_object: !is_nil(response["response"])
    )

    challenge = socket.assigns.passkey_challenge
    auth_mode = socket.assigns[:passkey_auth_mode] || :non_discoverable

    Ysc.Logging.debug("[UserLoginLive] Verification state",
      has_challenge: !is_nil(challenge),
      auth_mode: auth_mode,
      challenge_bytes_length:
        if(challenge, do: byte_size(challenge.bytes), else: nil)
    )

    if is_nil(challenge) do
      Ysc.Logging.warning(
        "[UserLoginLive] Challenge is nil in verify_authentication"
      )

      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "That sign-in timed out. Please try again, or sign in with your email and password below."
       )
       |> assign(:passkey_loading, false)
       |> assign(:passkey_challenge, nil)
       |> assign(:passkey_auth_mode, nil)}
    else
      # Decode the response from JS
      # All binary data from JavaScript is Base64URL encoded and must be decoded here
      raw_id_string = response["rawId"] || response["id"]

      Ysc.Logging.debug("[UserLoginLive] Decoding authentication response",
        raw_id_string: raw_id_string,
        has_authenticator_data:
          !is_nil(response["response"]["authenticatorData"]),
        has_client_data_json: !is_nil(response["response"]["clientDataJSON"]),
        has_signature: !is_nil(response["response"]["signature"]),
        has_user_handle: !is_nil(response["response"]["userHandle"]),
        response_keys: Map.keys(response["response"] || %{})
      )

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

      Ysc.Logging.debug("[UserLoginLive] Decoded authentication data",
        raw_id_length: byte_size(raw_id),
        raw_id_hex: Base.encode16(raw_id, case: :lower),
        authenticator_data_length: byte_size(authenticator_data),
        client_data_json_length: byte_size(client_data_json),
        signature_length: byte_size(signature)
      )

      # Find passkey by external_id first (needed for verification)
      case Ysc.Accounts.get_user_passkey_by_external_id(raw_id) do
        nil ->
          Ysc.Logging.warning(
            "[UserLoginLive] Passkey not found by external_id",
            %{
              raw_id_hex: Base.encode16(raw_id, case: :lower),
              raw_id_base64: Base.url_encode64(raw_id, padding: false),
              raw_id_length: byte_size(raw_id)
            }
          )

          {:noreply,
           YscWeb.Flash.put_toast(
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
              Ysc.Logging.warning(
                "[UserLoginLive] Missing userHandle in discoverable credential response",
                %{
                  has_user_handle: !is_nil(user_handle),
                  user_handle: user_handle,
                  response_keys: Map.keys(response["response"] || %{})
                }
              )

              {:noreply,
               YscWeb.Flash.put_toast(
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
                    Ysc.Logging.warning(
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
                 YscWeb.Flash.put_toast(
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
                  Ysc.Logging.warning(
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
                   YscWeb.Flash.put_toast(
                     socket,
                     :error,
                     "Passkey verification failed. Please try again or use another sign-in method."
                   )
                   |> assign(:passkey_loading, false)
                   |> assign(:passkey_challenge, nil)
                   |> assign(:passkey_auth_mode, nil)}
                else
                  Ysc.Logging.info(
                    "[UserLoginLive] User IDs match, proceeding to verify_passkey_authentication"
                  )

                  # Verify that raw_id matches passkey.external_id before calling Wax.authenticate
                  if passkey.external_id != raw_id do
                    Ysc.Logging.error(
                      "[UserLoginLive] CRITICAL: raw_id from response does not match passkey.external_id",
                      raw_id_hex: Base.encode16(raw_id, case: :lower),
                      raw_id_base64url:
                        Base.url_encode64(raw_id, padding: false),
                      passkey_external_id_hex:
                        Base.encode16(passkey.external_id, case: :lower),
                      passkey_external_id_base64url:
                        Base.url_encode64(passkey.external_id, padding: false),
                      lengths_match:
                        byte_size(raw_id) == byte_size(passkey.external_id)
                    )

                    {:noreply,
                     YscWeb.Flash.put_toast(
                       socket,
                       :error,
                       "We couldn't finish passkey sign-in. Please try again, or sign in with your email and password, Google, or Facebook."
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
            Ysc.Logging.info(
              "[UserLoginLive] Processing non-discoverable credential, using passkey.user_id directly"
            )

            # Verify that raw_id matches passkey.external_id before calling Wax.authenticate
            if passkey.external_id != raw_id do
              Ysc.Logging.error(
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
               YscWeb.Flash.put_toast(
                 socket,
                 :error,
                 "We couldn't finish passkey sign-in. Please try again, or sign in with your email and password, Google, or Facebook."
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
    require Ysc.Logging

    user_cancelled? = error in ["NotAllowedError", "AbortError"]
    expected_client_limitation? = error == "NotSupportedError"

    cond do
      user_cancelled? ->
        Ysc.Logging.info(
          "[UserLoginLive] Passkey authentication cancelled by user or timed out",
          error: error
        )

      expected_client_limitation? ->
        Ysc.Logging.info(
          "[UserLoginLive] Passkey authentication not supported by this browser/platform",
          error: error,
          message: message
        )

      true ->
        Ysc.Logging.warning(
          "[UserLoginLive] Passkey authentication error from client",
          error: error,
          message: message,
          user_agent: socket.assigns[:user_agent],
          has_challenge: !is_nil(socket.assigns[:passkey_challenge]),
          auth_mode: socket.assigns[:passkey_auth_mode]
        )
    end

    {toast_level, error_message} =
      case error do
        e when e in ["NotAllowedError", "AbortError"] ->
          {:info, "Passkey sign-in was cancelled."}

        "InvalidStateError" ->
          {:error,
           "This passkey may have been removed. Please use another sign-in method."}

        "NotSupportedError" ->
          {:error,
           "Your device doesn't support this authentication method. Please use another sign-in method."}

        _ ->
          {:error,
           "We couldn't sign you in with Face ID or fingerprint. Try again, or sign in with your email and password, Google, or Facebook."}
      end

    {:noreply,
     YscWeb.Flash.put_toast(socket, toast_level, error_message, title: "Login")
     |> assign(:passkey_loading, false)
     |> assign(:passkey_challenge, nil)
     |> assign(:passkey_auth_mode, nil)}
  end

  def handle_event("passkey_auth_error", params, socket) do
    require Ysc.Logging

    # Log fallback error handler
    Ysc.Logging.warning(
      "[UserLoginLive] Passkey authentication error (fallback)",
      params: params,
      user_agent: socket.assigns[:user_agent],
      has_challenge: !is_nil(socket.assigns[:passkey_challenge]),
      auth_mode: socket.assigns[:passkey_auth_mode]
    )

    {:noreply,
     YscWeb.Flash.put_toast(
       socket,
       :error,
       "An error occurred during authentication. Please try again.",
       title: "Login"
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
    require Ysc.Logging

    Ysc.Logging.info("[UserLoginLive] verify_passkey_authentication called",
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
    )

    # For Wax.authenticate, we must use the raw_id from the response
    # This is the credential_id that the browser/authenticator used, and it must match
    # what's embedded in the authenticator_data (if present) or what the authenticator expects
    # Even though we verified raw_id matches passkey.external_id, we use raw_id here
    # because Wax.authenticate validates it against the authenticator_data structure
    credential_id_to_verify = raw_id

    Ysc.Logging.debug("[UserLoginLive] Calling Wax.authenticate",
      credential_id_length: byte_size(credential_id_to_verify),
      authenticator_data_length: byte_size(authenticator_data),
      signature_length: byte_size(signature),
      client_data_json_length: byte_size(client_data_json),
      challenge_bytes_length: byte_size(challenge.bytes)
    )

    # Inject the single passkey's public key into the challenge so Wax can verify
    # the signature. The challenge was created with allow_credentials: [] to avoid
    # loading all passkeys at challenge-creation time; we populate it here with only
    # the one credential that the client actually presented.
    public_key = Ysc.Accounts.UserPasskey.decode_public_key(passkey.public_key)

    challenge_with_credentials = %{
      challenge
      | allow_credentials: [{credential_id_to_verify, public_key}]
    }

    case Wax.authenticate(
           credential_id_to_verify,
           authenticator_data,
           signature,
           client_data_json,
           challenge_with_credentials
         ) do
      {:ok, auth_result} ->
        require Ysc.Logging

        Ysc.Logging.info("[UserLoginLive] Wax.authenticate succeeded")

        # Wax.authenticate returns {:ok, authenticator_data} where authenticator_data is a Wax.AuthenticatorData struct
        # The struct has fields like sign_count, not nested under :authenticator_data
        authenticator_data = auth_result

        # Verify sign_count increased (replay attack prevention).
        # Strictly require new > stored to detect cloned authenticators.
        # The only exception is 0 == 0 for authenticators that don't support
        # sign counts (they always report 0 per the WebAuthn spec).
        new_sign_count = authenticator_data.sign_count

        Ysc.Logging.debug("[UserLoginLive] Checking sign_count",
          new_sign_count: new_sign_count,
          passkey_sign_count: passkey.sign_count,
          sign_count_valid:
            new_sign_count > passkey.sign_count or
              (new_sign_count == 0 and passkey.sign_count == 0)
        )

        if new_sign_count > passkey.sign_count or
             (new_sign_count == 0 and passkey.sign_count == 0) do
          Ysc.Logging.info(
            "[UserLoginLive] Sign count check passed, proceeding with login",
            user_id: user_id,
            user_id_hex: Base.encode16(user_id, case: :lower)
          )

          # Update passkey sign_count and last_used_at
          {:ok, _updated_passkey} =
            Ysc.Accounts.update_passkey_sign_count(passkey, new_sign_count)

          # Do not log login here: we redirect to /users/log-in/passkey and
          # UserSessionController.passkey_login will log with the real conn
          # (IP + User-Agent). Logging from the socket would create a duplicate
          # event with 127.0.0.1 and "Unknown browser on Unknown OS".

          # Clear the challenge and loading state
          socket =
            socket
            |> assign(:passkey_loading, false)
            |> assign(:passkey_challenge, nil)
            |> assign(:passkey_auth_mode, nil)
            |> YscWeb.Flash.success_with_title(
              "Welcome back! 👋",
              "Welcome back! 👋 Good to see you again."
            )

          # One-time DB token so the controller can trust this redirect came from
          # a successful passkey verification. Unlike Phoenix.Token, this token is
          # deleted on first use, preventing replay attacks within the TTL window.
          user = Ysc.Accounts.get_user!(passkey.user_id)
          token = Ysc.Accounts.generate_passkey_login_token(user)

          query_params = %{"token" => token}

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

          require Ysc.Logging

          Ysc.Logging.info("[UserLoginLive] Redirecting to passkey login",
            base_path: base_path,
            has_redirect_to: Map.has_key?(query_params, "redirect_to"),
            has_token: Map.has_key?(query_params, "token")
          )

          {:noreply,
           socket
           |> redirect(to: redirect_url)}
        else
          require Ysc.Logging

          Ysc.Logging.warning(
            "[UserLoginLive] Sign count check failed - possible replay attack",
            %{
              new_sign_count: new_sign_count,
              passkey_sign_count: passkey.sign_count,
              sign_count_decreased: new_sign_count < passkey.sign_count
            }
          )

          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Security check failed. Please try again."
           )
           |> assign(:passkey_loading, false)
           |> assign(:passkey_challenge, nil)
           |> assign(:passkey_auth_mode, nil)}
        end

      {:error, reason} ->
        require Ysc.Logging

        # Log the error with full context
        error_string = inspect(reason, pretty: true, limit: :infinity)

        Ysc.Logging.warning("[UserLoginLive] Wax.authenticate failed",
          error: error_string,
          error_type: :exception,
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
        )

        {:noreply,
         YscWeb.Flash.put_toast(
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
