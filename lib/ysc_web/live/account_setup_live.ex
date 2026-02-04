defmodule YscWeb.AccountSetupLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto py-10">
      <div class="flex w-full mx-auto items-center text-center justify-center">
        <.link
          navigate={~p"/"}
          class="p-10 hover:opacity-80 transition duration-200 ease-in-out"
        >
          <.ysc_logo class="h-28" />
        </.link>
      </div>

      <div
        :if={length(build_stepper_steps(@user_needs, @current_user)) > 1}
        class="w-full px-2"
      >
        <.stepper
          active_step={stepper_active_step(@user_needs, @current_step)}
          steps={build_stepper_steps(@user_needs, @current_user)}
        />
      </div>

      <div class="px-2 py-8">
        <div :if={@current_step === 0}>
          <.alert_box :if={@from_signup}>
            <.icon
              name="hero-rocket-launch"
              class="w-12 h-12 text-blue-800 me-3 mt-1"
            />
            Your application is submitted and is currently being reviewed by the board. We will email you as soon as your membership is approved.<br /><br />
            While you wait, let's finish setting up your account!
          </.alert_box>

          <.header class="text-left">
            Verify Your Email Address
            <:subtitle>
              We sent a verification code to <strong><%= @user.email %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@email_form}
            id="email_form"
            phx-submit="verify_code"
            phx-change="validate_email_code"
            phx-hook="ResendTimer"
            class="pt-8"
          >
            <.input
              field={@email_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
              phx-input="validate_email_code"
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your spam folder or
              <%= if email_resend_available?(assigns) do %>
                <.link
                  phx-click="resend_code"
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  click here to resend
                </.link>
              <% else %>
                <% email_countdown =
                  email_resend_seconds_remaining(assigns) |> max(0) %>
                <span
                  class="text-zinc-500 cursor-not-allowed"
                  data-countdown={email_countdown}
                  data-timer-type="email"
                >
                  resend in <%= email_countdown %>s
                </span>
              <% end %>.
            </p>

            <:actions>
              <div class="flex justify-end w-full">
                <.button
                  phx-disable-with="Verifying..."
                  type="submit"
                  disabled={!@code_valid}
                  class={
                    if !@code_valid, do: "opacity-50 cursor-not-allowed", else: ""
                  }
                >
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Verify Code
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 1 and @user_needs.password_setup}>
          <.header class="text-left">
            Set Your Password
            <:subtitle>
              Create a password to access your account and manage your membership.
            </:subtitle>
          </.header>

          <.simple_form
            for={@password_form}
            id="password_form"
            phx-submit="save_password"
            phx-change="validate_password"
          >
            <.input
              field={@password_form[:password]}
              type="password-toggle"
              label="Password"
              required
              placeholder="Enter a secure password"
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password-toggle"
              label="Confirm Password"
              required
              placeholder="Confirm your password"
            />

            <:actions>
              <div class="flex justify-end w-full">
                <.button phx-disable-with="Setting password...">
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Set Password
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 2}>
          <.header class="text-left">
            Add Your Phone Number (Optional)
            <:subtitle>
              Providing your phone number allows us to send you SMS notifications for important account updates and event reminders.
            </:subtitle>
          </.header>

          <.simple_form
            for={@phone_form}
            id="phone_form"
            phx-submit="save_phone"
            phx-change="validate_phone"
          >
            <.input
              type="phone-input"
              label="Phone Number"
              field={@phone_form[:phone_number]}
            />
            <.input
              type="checkbox"
              label="I would like to receive SMS notifications for account security, event reminders, and booking updates"
              field={@phone_form[:sms_opt_in]}
            />
            <p class="text-xs text-zinc-600 mt-1">
              <strong>Young Scandinavians Club (YSC)</strong>: By voluntarily providing your phone number and explicitly opting in to text messaging, you agree to receive account security codes and booking reminders from Young Scandinavians Club(YSC). Message frequency may vary. Message & data rates may apply. Reply HELP for support or STOP to unsubscribe. Your phone number will not be shared with third parties for marketing or promotional purposes. You can also opt out at any time in your notification settings. See our
              <.link
                navigate={~p"/privacy-policy"}
                class="text-blue-600 hover:underline"
              >
                Privacy Policy
              </.link>
              for more information.
            </p>

            <:actions>
              <.button
                class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
                phx-click="skip_phone"
              >
                Skip for now
              </.button>
              <.button phx-disable-with="Saving...">
                <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Save Phone Number
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 3 and @user_needs.phone_verification}>
          <.header class="text-left">
            Verify Your Phone Number
            <:subtitle>
              We sent a verification code to <strong><%= @user.phone_number %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@phone_verification_form}
            id="phone_verification_form"
            phx-submit="verify_phone_code"
            phx-change="validate_phone_code"
            phx-hook="ResendTimer"
            class="pt-8"
          >
            <p
              :if={dev_or_sandbox?()}
              class="text-xs text-amber-600 mt-2 bg-amber-50 p-2 rounded border border-amber-200"
            >
              <strong>Dev Mode:</strong>
              You can use <code class="bg-amber-100 px-1 rounded">000000</code>
              as the verification code.
            </p>
            <.input
              field={@phone_verification_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
              phx-input="validate_phone_code"
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your messages or
              <%= if sms_resend_available?(assigns) do %>
                <.link
                  phx-click="resend_phone_code"
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  click here to resend
                </.link>
              <% else %>
                <% sms_countdown = sms_resend_seconds_remaining(assigns) |> max(0) %>
                <span
                  class="text-zinc-500 cursor-not-allowed font-bold"
                  data-countdown={sms_countdown}
                  data-timer-type="sms"
                >
                  resend in <%= sms_countdown %>s
                </span>
              <% end %>.
            </p>

            <div class="py-2">
              <p class="text-sm mb-2 text-zinc-600 font-bold">
                Want to use a different phone number?
              </p>
              <button
                type="button"
                phx-click="change_phone_number"
                class="text-sm text-blue-600 hover:text-blue-700 font-medium hover:underline"
              >
                Change phone number →
              </button>
            </div>

            <:actions>
              <div class="flex justify-end w-full">
                <.button
                  phx-disable-with="Verifying..."
                  disabled={!@phone_code_valid}
                  class={
                    if !@phone_code_valid,
                      do: "opacity-50 cursor-not-allowed",
                      else: ""
                  }
                >
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Verify Phone Number
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 4 && !@trigger_login}>
          <.header class="text-left">
            Account Setup Complete!
            <:subtitle>
              Welcome to the Young Scandinavians Club! You can now access all features.
            </:subtitle>
          </.header>

          <div class="text-center py-8">
            <.icon
              name="hero-check-circle"
              class="w-16 h-16 text-green-600 mx-auto mb-4"
            />
            <p class="text-zinc-600 mb-4">
              Your account has been successfully set up and you're now logged in.
            </p>
            <.link
              navigate={~p"/"}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              Continue to Dashboard
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Build stepper steps dynamically - only show steps that are actually needed for this user
  defp build_stepper_steps(user_needs, _current_user) do
    steps = []

    # Email verification is not shown in stepper (handled separately)

    # Add password setup if needed
    steps =
      if user_needs.password_setup, do: steps ++ ["Set Password"], else: steps

    # Add phone step if phone setup or verification is needed
    steps =
      if user_needs.phone_setup or user_needs.phone_verification,
        do: steps ++ ["Verify Phone Number"],
        else: steps

    steps
  end

  # Helper function to map current_step to stepper display step
  # Dynamically calculates position based on which steps are shown
  defp stepper_active_step(user_needs, current_step) when is_map(user_needs) do
    # Build the step mapping dynamically based on which steps are shown
    # Email verification (step 0) is not shown in stepper, so we skip it
    {_step_index, step_mapping} =
      {0, %{}}
      |> add_step_if_needed(Map.get(user_needs, :password_setup, false), 1)
      |> add_phone_steps_if_needed(user_needs)

    # Return the mapped step or 0 if not found
    Map.get(step_mapping, current_step, 0)
  end

  defp stepper_active_step(_invalid_user_needs, _current_step) do
    # Fallback for invalid user_needs
    0
  end

  # Helper function to conditionally add a step to the mapping
  defp add_step_if_needed({step_index, step_mapping}, condition, step_key) do
    if condition do
      {step_index + 1, Map.put(step_mapping, step_key, step_index)}
    else
      {step_index, step_mapping}
    end
  end

  # Helper function to add phone steps (setup and verification map to same step)
  defp add_phone_steps_if_needed({step_index, step_mapping}, user_needs) do
    if Map.get(user_needs, :phone_setup, false) or
         Map.get(user_needs, :phone_verification, false) do
      step_mapping = Map.put(step_mapping, 2, step_index)
      # Phone verification maps to same step
      step_mapping = Map.put(step_mapping, 3, step_index)
      {step_index + 1, step_mapping}
    else
      {step_index, step_mapping}
    end
  end

  # Helper function to check if we're in dev/sandbox mode
  defp dev_or_sandbox? do
    Ysc.Env.non_prod?()
  end

  # Helper functions for resend rate limiting - delegate to ResendRateLimiter
  defp email_resend_available?(assigns),
    do: Ysc.ResendRateLimiter.resend_available?(assigns, :email)

  defp sms_resend_available?(assigns),
    do: Ysc.ResendRateLimiter.resend_available?(assigns, :sms)

  defp email_resend_seconds_remaining(assigns),
    do: Ysc.ResendRateLimiter.resend_seconds_remaining(assigns, :email)

  defp sms_resend_seconds_remaining(assigns),
    do: Ysc.ResendRateLimiter.resend_seconds_remaining(assigns, :sms)

  @impl true
  def mount(%{"user_id" => user_id}, _session, socket) do
    user = Accounts.get_user!(user_id)
    current_user = socket.assigns.current_user

    # Determine user's current setup status
    email_verified = not is_nil(user.email_verified_at)
    password_set = not is_nil(user.password_set_at)
    phone_verified = not is_nil(user.phone_verified_at)
    phone_number_exists = not is_nil(user.phone_number)

    # Check if user owns this setup (is authenticated as this user)
    is_owner = !!(current_user && current_user.id == user.id)

    # Determine what the user actually needs to complete
    needs_email_verification = not email_verified
    needs_password_setup = not password_set
    needs_phone_setup = not phone_number_exists
    needs_phone_verification = phone_number_exists and not phone_verified

    # User needs setup if they have incomplete requirements
    needs_any_setup =
      needs_email_verification or needs_password_setup or needs_phone_setup or
        needs_phone_verification

    # Access control logic:
    # 1. If user doesn't need any setup, deny access
    # 2. Email verification step: always allow (for signup flow)
    # 3. Password/Phone steps: require ownership (authentication)
    can_access =
      if needs_any_setup do
        # User needs some setup - check specific access rules
        true
      else
        # User has everything set up already
        false
      end

    if can_access do
      # Determine which steps the user needs (don't skip, just don't show unnecessary ones)
      user_needs = %{
        email_verification: not email_verified,
        password_setup: not password_set,
        phone_setup: not phone_number_exists,
        phone_verification: phone_number_exists and not phone_verified
      }

      # Determine starting step based on what user needs and their auth status
      starting_step =
        cond do
          # If user needs email verification, start there (always accessible)
          user_needs.email_verification ->
            0

          # If user needs password setup and is authenticated
          user_needs.password_setup and is_owner ->
            1

          # If user needs phone setup and is authenticated
          user_needs.phone_setup and is_owner ->
            2

          # If user needs phone verification and is authenticated
          user_needs.phone_verification and is_owner ->
            3

          # User has completed all necessary steps
          true ->
            4
        end

      # Create phone changeset with existing phone number if available
      phone_changeset =
        if phone_number_exists do
          # Pre-fill with existing phone number
          Ysc.Accounts.User.registration_changeset(
            user,
            %{"phone_number" => user.phone_number},
            hash_password: false,
            validate_email: false
          )
        else
          Ysc.Accounts.User.registration_changeset(user, %{},
            hash_password: false,
            validate_email: false
          )
        end

      phone_verification_changeset = %{"verification_code" => ""} |> to_form()

      # Start at the appropriate step
      current_step = starting_step
      password_changeset = Accounts.change_user_password(user)

      # Generate and send initial verification code only if one doesn't already exist
      case Ysc.VerificationCache.get_code(user.id, :email_verification) do
        {:ok, _existing_code} ->
          # Code already exists, don't generate a new one
          :ok

        {:error, _} ->
          # No existing code, generate and send new one
          code = Accounts.generate_and_store_email_verification_code(user)
          _job = Accounts.send_email_verification_code(user, code, "initial")
      end

      email_changeset = %{"verification_code" => ""} |> to_form()

      # Start at step 0 - user progresses through the flow

      socket =
        socket
        |> assign(:page_title, "Complete Your Account Setup")
        |> assign(:user, user)
        |> assign(:current_step, current_step)
        |> assign(:email_verified, false)
        |> assign(:from_signup, false)
        |> assign(:user_needs, user_needs)
        |> assign(:trigger_login, false)
        |> assign(:email_form, email_changeset)
        |> assign(:password_form, to_form(password_changeset))
        |> assign(:phone_form, to_form(phone_changeset))
        |> assign(:phone_verification_form, phone_verification_changeset)
        |> assign(:user_needs, user_needs)
        |> assign(:code_valid, false)
        |> assign(:phone_code_valid, false)
        |> assign(:email_resend_disabled_until, nil)
        |> assign(:sms_resend_disabled_until, nil)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Handle step and from_signup parameters from URL query string
    step_param = params["step"]
    from_signup = params["from_signup"] == "true"

    if step_param do
      requested_step = String.to_integer(step_param)
      current_user = socket.assigns.current_user
      user = socket.assigns.user

      # Re-fetch user to get latest data for access control (important after email verification)
      fresh_user = Accounts.get_user!(user.id)

      # Check authentication for steps that require it
      can_access_step =
        cond do
          requested_step == 0 ->
            # Email verification step: always accessible
            true

          requested_step > 0 and is_nil(fresh_user.email_verified_at) ->
            # Trying to access steps after email verification but email not verified
            false

          requested_step > 0 and not is_nil(current_user) and
              current_user.id != fresh_user.id ->
            # Trying to access authenticated steps but not the owner
            false

          requested_step > 0 and is_nil(current_user) and
              not is_nil(fresh_user.email_verified_at) ->
            # User has verified email but session not set yet - allow access
            # This handles the case where user just verified email and is being redirected
            true

          requested_step > 0 and is_nil(current_user) ->
            # Trying to access authenticated steps but not logged in
            false

          true ->
            # Authenticated owner accessing their own setup
            true
        end

      if can_access_step do
        user_needs = socket.assigns.user_needs

        # Update socket assigns with fresh user data
        socket = assign(socket, user: fresh_user)

        # If current_user is not set but user has verified email, set current_user
        # This handles the case where session is not fully loaded yet
        socket =
          if is_nil(current_user) and not is_nil(fresh_user.email_verified_at) do
            assign(socket, current_user: fresh_user)
          else
            socket
          end

        # Calculate allowed step based on what user needs and their authentication
        allowed_step =
          cond do
            # Step 0 (email verification): Always allow if user needs it
            requested_step == 0 and user_needs.email_verification ->
              0

            # Step 1 (password setup): Require authentication and need
            requested_step == 1 and not is_nil(current_user) and
                user_needs.password_setup ->
              1

            # Step 2 (phone setup): Require authentication and need
            requested_step == 2 and not is_nil(current_user) and
                user_needs.phone_setup ->
              2

            # Step 3 (phone verification): Require authentication and need
            requested_step == 3 and not is_nil(current_user) and
                user_needs.phone_verification ->
              3

            # Default: Stay on current step or go to completion
            true ->
              socket.assigns.current_step
          end

        # Automatically send phone verification code if user reaches step 3 with unverified phone
        socket =
          if allowed_step == 3 and not is_nil(fresh_user.phone_number) and
               is_nil(fresh_user.phone_verified_at) do
            # Check if code already exists in cache
            case Ysc.VerificationCache.get_code(
                   fresh_user.id,
                   :phone_verification
                 ) do
              {:ok, _existing_code} ->
                # Code already exists, don't send new one
                socket

              {:error, _} ->
                # Generate and send new verification code
                phone_code =
                  Accounts.generate_and_store_phone_verification_code(
                    fresh_user
                  )

                _job =
                  Accounts.send_phone_verification_code(
                    fresh_user,
                    phone_code,
                    "auto_step3"
                  )

                socket
            end
          else
            socket
          end

        {:noreply,
         assign(socket, current_step: allowed_step, from_signup: from_signup)}
      end
    else
      {:noreply, assign(socket, :from_signup, from_signup)}
    end
  end

  @impl true
  # Client-side hook for countdown timers
  def handle_event("update_resend_timers", _params, socket) do
    # This is called by JavaScript to trigger a re-render with updated timers
    {:noreply, socket}
  end

  @impl true
  def handle_event("resend_timer_expired", %{"type" => type}, socket) do
    # Clear the specific resend disabled state when timer expires
    assign_key =
      case type do
        "email" -> :email_resend_disabled_until
        "sms" -> :sms_resend_disabled_until
      end

    {:noreply, assign(socket, assign_key, nil)}
  end

  @impl true
  def handle_event(
        "validate_email_code",
        %{"verification_code" => code},
        socket
      ) do
    # Handle both OTP array format and single string format
    normalized_code = normalize_verification_code(code)
    # Basic validation - ensure it's 6 digits
    is_valid =
      String.length(normalized_code) == 6 &&
        String.match?(normalized_code, ~r/^\d{6}$/)

    {:noreply, assign(socket, :code_valid, is_valid)}
  end

  def handle_event(
        "verify_code",
        %{"verification_code" => entered_code},
        socket
      ) do
    # Handle both OTP array format and single string format
    code = normalize_verification_code(entered_code)

    # In dev/sandbox, always accept 000000 as valid code
    verification_result =
      if dev_or_sandbox?() and code == "000000" do
        {:ok, :verified}
      else
        Accounts.verify_email_verification_code(socket.assigns.user, code)
      end

    case verification_result do
      {:ok, :verified} ->
        # Mark email as verified in database
        {:ok, updated_user} = Accounts.mark_email_verified(socket.assigns.user)

        # Determine next step, skipping password if already set
        next_step = if is_nil(updated_user.password_set_at), do: 1, else: 4

        # Create session token and log the user in
        token = Accounts.generate_user_session_token(updated_user)

        # Redirect to auto-login to establish session, then back to account setup
        {:noreply,
         socket
         |> Phoenix.LiveView.redirect(
           to:
             ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token), redirect_to: "/account/setup/#{updated_user.id}?step=#{next_step}"}}"
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "No verification code found. Please request a new one."
         )}

      {:error, :expired} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Verification code has expired. Please request a new one."
         )}

      {:error, :invalid_code} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid verification code. Please try again.")}
    end
  end

  def handle_event("resend_code", _params, socket) do
    user_id = socket.assigns.user.id

    case Ysc.ResendRateLimiter.check_and_record_resend(user_id, :email) do
      {:ok, :allowed} ->
        # Resend allowed, proceed with sending email
        {code, is_existing} =
          case Ysc.VerificationCache.get_code(user_id, :email_verification) do
            {:ok, existing_code} ->
              {existing_code, true}

            {:error, _} ->
              # Generate new code if none exists
              new_code =
                Accounts.generate_and_store_email_verification_code(
                  socket.assigns.user
                )

              {new_code, false}
          end

        # Use timestamp to make idempotency key unique for resend attempts
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        suffix =
          if is_existing,
            do: "resend_existing_#{timestamp}",
            else: "resend_new_#{timestamp}"

        _job =
          Accounts.send_email_verification_code(
            socket.assigns.user,
            code,
            suffix
          )

        {:noreply,
         socket
         |> assign(
           :email_resend_disabled_until,
           Ysc.ResendRateLimiter.disabled_until(60)
         )
         |> put_flash(
           :info,
           "A new verification code has been sent to your email."
         )}

      {:error, :rate_limited, _remaining} ->
        # Rate limited
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Please wait before requesting another verification code."
         )}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    # Only allow password validation if user is authenticated and needs password setup
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if current_user && user_needs.password_setup do
      password_form =
        socket.assigns.user
        |> Accounts.change_user_password(user_params)
        |> Map.put(:action, :validate)
        |> to_form()

      {:noreply, assign(socket, password_form: password_form)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please complete email verification first.")}
    end
  end

  def handle_event("validate_phone", %{"user" => user_params}, socket) do
    # Only allow phone validation if user is authenticated and needs phone setup
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if current_user && socket.assigns.current_step == 2 do
      phone_form =
        socket.assigns.user
        |> Accounts.User.registration_changeset(user_params,
          hash_password: false,
          validate_email: false
        )
        |> Map.put(:action, :validate)
        |> to_form()

      {:noreply, assign(socket, phone_form: phone_form)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please complete password setup first.")}
    end
  end

  def handle_event("change_phone_number", _params, socket) do
    # Allow authenticated user to change phone number by going back to step 2
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if current_user do
      {:noreply,
       socket
       |> assign(:current_step, 2)
       |> push_patch(to: ~p"/account/setup/#{socket.assigns.user.id}?step=2")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_password", %{"user" => user_params}, socket) do
    # Ensure user is authenticated and needs password setup
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if is_nil(current_user) or not user_needs.password_setup do
      {:noreply,
       socket
       |> put_flash(:error, "Please verify your email address first.")}
    else
      case Accounts.set_user_initial_password(socket.assigns.user, user_params) do
        {:ok, updated_user} ->
          # Store the password for later login and move to next step
          password = user_params["password"]

          # Cache the password temporarily for the account setup flow
          cache_key = "account_setup_password:#{updated_user.id}"
          Cachex.put(:ysc_cache, cache_key, password, ttl: :timer.minutes(30))

          # Determine next step based on phone verification status
          next_step =
            cond do
              # Phone already verified, go to complete
              not is_nil(updated_user.phone_verified_at) -> 4
              # Phone set but not verified, go to verification
              not is_nil(updated_user.phone_number) -> 3
              # Need to set up phone first
              true -> 2
            end

          # Recalculate user needs based on updated user
          updated_user_needs = %{
            email_verification: is_nil(updated_user.email_verified_at),
            password_setup: is_nil(updated_user.password_set_at),
            phone_setup: is_nil(updated_user.phone_number),
            phone_verification:
              not is_nil(updated_user.phone_number) and
                is_nil(updated_user.phone_verified_at)
          }

          {:noreply,
           socket
           |> assign(:current_step, next_step)
           |> push_patch(
             to: ~p"/account/setup/#{socket.assigns.user.id}?step=#{next_step}"
           )
           |> assign(:user, updated_user)
           |> assign(:user_needs, updated_user_needs)
           |> assign(:password, password)
           |> put_flash(:info, "Password set successfully!")}

        {:error, changeset} ->
          {:noreply, assign(socket, password_form: to_form(changeset))}
      end
    end
  end

  def handle_event("save_phone", %{"user" => user_params}, socket) do
    # Ensure user is authenticated and needs phone setup
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if is_nil(current_user) or socket.assigns.current_step != 2 do
      {:noreply,
       socket
       |> put_flash(:error, "Phone setup is not available at this step.")}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      case Accounts.update_user_phone_and_sms(user, user_params) do
        {:ok, updated_user} ->
          # Generate and send phone verification code
          phone_code =
            Accounts.generate_and_store_phone_verification_code(updated_user)

          _job =
            Accounts.send_phone_verification_code(
              updated_user,
              phone_code,
              "initial"
            )

          # Recalculate user needs based on updated user
          updated_user_needs = %{
            email_verification: is_nil(updated_user.email_verified_at),
            password_setup: is_nil(updated_user.password_set_at),
            phone_setup: is_nil(updated_user.phone_number),
            phone_verification:
              not is_nil(updated_user.phone_number) and
                is_nil(updated_user.phone_verified_at)
          }

          # Advance to phone verification step
          {:noreply,
           socket
           |> assign(:current_step, 3)
           |> assign(:user, updated_user)
           |> assign(:user_needs, updated_user_needs)
           |> push_patch(
             to: ~p"/account/setup/#{socket.assigns.user.id}?step=3"
           )
           |> put_flash(
             :info,
             "Phone number saved! Please verify it with the code we sent."
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, phone_form: to_form(changeset))}
      end
    end
  end

  def handle_event("skip_phone", _params, socket) do
    # Ensure user is authenticated - re-fetch user to get latest data
    current_user = socket.assigns.current_user

    if is_nil(current_user) do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete account setup first.")}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      # After skipping phone setup, complete account setup
      # Generate session token and redirect for auto-login
      token = Accounts.generate_user_session_token(user)

      {:noreply,
       socket
       |> Phoenix.LiveView.redirect(
         to: ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token)}}"
       )}
    end
  end

  def handle_event("set-step", %{"step" => step_str}, socket) do
    requested_step = String.to_integer(step_str)
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    # Check if step is accessible based on authentication and user needs
    can_access_step =
      cond do
        # Step 0: Always allow if user needs email verification
        requested_step == 0 and user_needs.email_verification ->
          true

        # Steps 1+: Require authentication
        requested_step >= 1 and is_nil(current_user) ->
          false

        # Step 1: Allow if user needs password setup
        requested_step == 1 and user_needs.password_setup ->
          true

        # Step 2: Allow if user needs phone setup
        requested_step == 2 and user_needs.phone_setup ->
          true

        # Step 3: Allow if user needs phone verification
        requested_step == 3 and user_needs.phone_verification ->
          true

        # Default: Deny access
        true ->
          false
      end

    if can_access_step do
      {:noreply, assign(socket, :current_step, requested_step)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please complete the required steps in order.")
       |> redirect(to: ~p"/account/setup/#{socket.assigns.user.id}")}
    end
  end

  def handle_event(
        "validate_phone_code",
        %{"verification_code" => code},
        socket
      ) do
    # Only allow phone code validation if user is authenticated and needs phone verification
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if current_user && user_needs.phone_verification do
      # Handle both OTP array format and single string format
      normalized_code = normalize_verification_code(code)
      # Basic validation - ensure it's 6 digits
      is_valid =
        String.length(normalized_code) == 6 &&
          String.match?(normalized_code, ~r/^\d{6}$/)

      {:noreply, assign(socket, phone_code_valid: is_valid)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "verify_phone_code",
        %{"verification_code" => entered_code},
        socket
      ) do
    # Ensure user is authenticated and needs phone verification
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if is_nil(current_user) or not user_needs.phone_verification do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete phone setup first.")}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      # Handle both OTP array format and single string format
      code = normalize_verification_code(entered_code)

      case Accounts.verify_phone_verification_code(user, code) do
        {:ok, :verified} ->
          # Mark phone as verified in database
          {:ok, updated_user} = Accounts.mark_phone_verified(user)

          # Generate session token and redirect based on account state
          token = Accounts.generate_user_session_token(updated_user)

          {:noreply,
           socket
           |> Phoenix.LiveView.redirect(
             to: ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token)}}"
           )}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "No verification code found. Please request a new one."
           )}

        {:error, :expired} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Verification code has expired. Please request a new one."
           )}

        {:error, :invalid_code} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid verification code. Please try again.")}
      end
    end
  end

  def handle_event("resend_phone_code", _params, socket) do
    # Ensure user is authenticated and needs phone verification
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if is_nil(current_user) or not user_needs.phone_verification do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete phone setup first.")}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)
      user_id = user.id

      case Ysc.ResendRateLimiter.check_and_record_resend(user_id, :sms) do
        {:ok, :allowed} ->
          # Resend allowed, proceed with sending SMS
          {code, is_existing} =
            case Ysc.VerificationCache.get_code(user_id, :phone_verification) do
              {:ok, existing_code} ->
                {existing_code, true}

              {:error, _} ->
                # Generate new code if none exists
                new_code =
                  Accounts.generate_and_store_phone_verification_code(user)

                {new_code, false}
            end

          # Send the code via SMS
          timestamp = DateTime.utc_now() |> DateTime.to_unix()

          suffix =
            if is_existing,
              do: "resend_existing_#{timestamp}",
              else: "resend_new_#{timestamp}"

          _job = Accounts.send_phone_verification_code(user, code, suffix)

          {:noreply,
           socket
           |> assign(
             :sms_resend_disabled_until,
             Ysc.ResendRateLimiter.disabled_until(60)
           )
           |> put_flash(:info, "Verification code sent to your phone.")}

        {:error, :rate_limited, _remaining} ->
          # Rate limited
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Please wait before requesting another verification code."
           )}
      end
    end
  end

  # Helper function to normalize verification code from OTP array/map or string format
  defp normalize_verification_code(code) when is_map(code) do
    # Handle map format: %{"0" => "1", "1" => "2", ...}
    # Sort by key and join values, filtering out empty values
    code
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, v} -> v end)
    |> Enum.reject(&(&1 == "" || &1 == nil))
    |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_list(code) do
    # Join array elements and filter out empty values
    code
    |> Enum.reject(&(&1 == "" || &1 == nil))
    |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_binary(code) do
    code
  end

  defp normalize_verification_code(_), do: ""
end
