defmodule YscWeb.AccountSetupLive do
  use YscWeb, :live_view

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Customers
  alias Ysc.Payments

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto py-4 px-4">
      <div class="flex w-full mx-auto items-center text-center justify-center">
        <.link
          navigate={~p"/"}
          class="p-8 hover:opacity-80 transition duration-200 ease-in-out"
        >
          <.ysc_logo class="h-28" width={112} height={112} fetchpriority="high" />
        </.link>
      </div>

      <div
        :if={
          @current_step > 0 and
            length(build_stepper_steps(@stepper_needs, @current_user)) > 1
        }
        class="w-full px-2"
      >
        <.stepper
          active_step={stepper_active_step(@stepper_needs, @current_step)}
          steps={build_stepper_steps(@stepper_needs, @current_user)}
        />
      </div>

      <div class="px-2 py-8">
        <div
          :if={@current_step === 0}
          id="email-verification-step"
          phx-hook="ResendTimer"
        >
          <.alert_box :if={@from_signup}>
            <.icon
              name="hero-rocket-launch"
              class="w-12 h-12 text-blue-800 me-3 mt-1"
            />
            Your application is submitted and is currently being reviewed by the board. We will email you when the board has made a decision.<br /><br />
            While you wait, let's finish setting up your account!
          </.alert_box>

          <.header class="text-left">
            Verify Your Email Address
            <:subtitle>
              We sent a verification code to <strong><%= @display_email %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@email_form}
            id="email_form"
            phx-submit="verify_code"
            phx-change="validate_email_code"
            class="pt-8"
          >
            <.input
              field={@email_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your spam folder.
              <%= if email_resend_available?(assigns) do %>
                <.link
                  phx-click="resend_code"
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  Resend the code
                </.link>
              <% else %>
                <% email_countdown =
                  email_resend_seconds_remaining(assigns) |> max(0) %>
                <span
                  class="text-zinc-500 cursor-not-allowed"
                  data-countdown={email_countdown}
                  data-timer-type="email"
                >
                  You can resend the code in {email_countdown}{if email_countdown ==
                                                                    1,
                                                                  do: " second",
                                                                  else: " seconds"}.
                </span>
              <% end %>
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

        <div :if={@current_step === 1 and @user_needs.payment_method_setup}>
          <.header class="text-left">
            Save Your Payment Method
            <:subtitle>
              Add a payment method to complete your application. You won't be charged unless you're approved.
            </:subtitle>
          </.header>

          <%= if @signup_plan do %>
            <div class="mt-4 mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
              <p class="text-sm font-semibold text-blue-900 mb-1">Selected plan</p>
              <p class="text-base font-bold text-blue-800">
                {@signup_plan.name} &mdash; {Money.to_string!(
                  Money.new(:USD, @signup_plan.amount)
                )}/year
              </p>
            </div>
          <% end %>

          <div class="mb-6 p-4 bg-amber-50 border border-amber-200 rounded-lg text-sm text-amber-900 space-y-2">
            <p>
              <.icon
                name="hero-shield-check"
                class="w-4 h-4 inline-block mr-1 -mt-0.5"
              />
              <strong>
                Your card will not be charged until your application is approved.
              </strong>
            </p>
            <p>
              By saving your payment details you authorize the Young Scandinavians Club to charge this payment method for your annual membership dues if your application is approved, and to automatically renew your membership each year until you cancel.
            </p>
          </div>

          <%= if @payment_intent_secret do %>
            <form
              id="setup-payment-form"
              class="flex flex-col space-y-4"
              phx-hook="StripeInput"
              data-clientSecret={@payment_intent_secret}
              data-publicKey={@public_key}
              data-submitURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/payment-method"}
              data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
            >
              <div id="error-message">
                <p id="card-errors" class="text-red-500 text-sm"></p>
              </div>
              <div id="payment-element"></div>
              <div class="flex justify-end items-center pt-2">
                <.button
                  id="submit"
                  type="submit"
                  phx-disable-with="Saving..."
                  color="blue"
                >
                  <.icon name="hero-credit-card" class="w-4 h-4" />
                  Save Payment Method &amp; Continue
                </.button>
              </div>
            </form>
          <% else %>
            <div class="text-center py-8 space-y-4">
              <p class="text-zinc-500">
                There was a problem loading the payment form. Please try again.
              </p>
              <button
                type="button"
                phx-click="retry_payment_setup"
                class="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg"
              >
                <.icon name="hero-arrow-path" class="w-4 h-4 me-2" /> Try Again
              </button>
            </div>
          <% end %>
        </div>

        <div :if={@current_step === 2 and @user_needs.password_setup}>
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

        <div :if={@current_step === 3}>
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
              <strong>Young Scandinavians Club (YSC)</strong>: By voluntarily providing your phone number and explicitly opting in to text messaging, you agree to receive account security codes and booking reminders from Young Scandinavians Club (YSC). Message frequency may vary. Message and data rates may apply. Reply HELP for support or STOP to unsubscribe. Your phone number will not be shared with third parties for marketing or promotional purposes. You can also opt out at any time in your notification settings. See our
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
                class="bg-transparent text-zinc-400 hover:text-zinc-600 hover:underline font-medium text-sm leading-6 py-2 px-3 rounded transition duration-150 ease-in-out"
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

        <div
          :if={@current_step === 4 and @user_needs.phone_verification}
          id="phone-verification-step"
          phx-hook="ResendTimer"
        >
          <.header class="text-left">
            Verify Your Phone Number
            <:subtitle>
              We sent a verification code to <strong><%= Ysc.Extensions.PhoneNumber.format_for_display(@user.phone_number) || @user.phone_number %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@phone_verification_form}
            id="phone_verification_form"
            phx-submit="verify_phone_code"
            phx-change="validate_phone_code"
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
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your messages.
              <%= if sms_resend_available?(assigns) do %>
                <.link
                  phx-click="resend_phone_code"
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  Resend the code
                </.link>
              <% else %>
                <% sms_countdown = sms_resend_seconds_remaining(assigns) |> max(0) %>
                <span
                  class="text-zinc-500 cursor-not-allowed font-bold"
                  data-countdown={sms_countdown}
                  data-timer-type="sms"
                >
                  You can resend the code in {sms_countdown}{if sms_countdown == 1,
                    do: " second",
                    else: " seconds"}.
                </span>
              <% end %>
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

        <div :if={@current_step === 5 && !@trigger_login}>
          <.header class="text-left">
            Account Setup Complete!
            <:subtitle>
              Your account is ready. Your application is under review.
            </:subtitle>
          </.header>

          <div class="text-center py-8">
            <.icon
              name="hero-check-circle"
              class="w-16 h-16 text-green-600 mx-auto mb-4"
            />
            <p class="text-zinc-600 mb-4">
              Your account has been successfully set up. The board will review your application and you'll receive an email with their decision.
            </p>
            <.link
              navigate={~p"/pending-review"}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              View Application Status
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

    # Add payment method step first (step 1) if needed — it comes before password
    steps =
      if Map.get(user_needs, :payment_method_setup, false),
        do: steps ++ ["Payment"],
        else: steps

    # Add password setup if needed
    steps =
      if user_needs.password_setup, do: steps ++ ["Password"], else: steps

    # Add phone step if phone setup or verification is needed
    steps =
      if user_needs.phone_setup or user_needs.phone_verification,
        do: steps ++ ["Phone"],
        else: steps

    steps
  end

  # Helper function to map current_step to stepper display step
  # Dynamically calculates position based on which steps are shown
  defp stepper_active_step(user_needs, current_step) when is_map(user_needs) do
    # Build the step mapping dynamically based on which steps are shown
    # Email verification (step 0) is not shown in stepper, so we skip it
    # New order: 1=payment, 2=password, 3=phone setup, 4=phone verify
    {_step_index, step_mapping} =
      {0, %{}}
      |> add_payment_step_if_needed(user_needs)
      |> add_step_if_needed(Map.get(user_needs, :password_setup, false), 2)
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

  # Helper function to add phone steps (setup and verification map to same stepper step)
  # Phone setup = step 3, phone verify = step 4 in the flow
  defp add_phone_steps_if_needed({step_index, step_mapping}, user_needs) do
    if Map.get(user_needs, :phone_setup, false) or
         Map.get(user_needs, :phone_verification, false) do
      step_mapping = Map.put(step_mapping, 3, step_index)
      # Phone verification maps to same stepper step as phone setup
      step_mapping = Map.put(step_mapping, 4, step_index)
      {step_index + 1, step_mapping}
    else
      {step_index, step_mapping}
    end
  end

  # Helper function to add payment method step (step 1 in the flow)
  defp add_payment_step_if_needed({step_index, step_mapping}, user_needs) do
    if Map.get(user_needs, :payment_method_setup, false) do
      {step_index + 1, Map.put(step_mapping, 1, step_index)}
    else
      {step_index, step_mapping}
    end
  end

  # Compute user_needs map from a user struct
  defp compute_user_needs(user) do
    %{
      email_verification: is_nil(user.email_verified_at),
      password_setup: is_nil(user.password_set_at),
      phone_setup: is_nil(user.phone_number),
      phone_verification:
        not is_nil(user.phone_number) and is_nil(user.phone_verified_at),
      payment_method_setup:
        user.state == :pending_approval and
          is_nil(Payments.get_default_payment_method(user))
    }
  end

  # Helper function to check if we're in dev/sandbox mode
  defp dev_or_sandbox? do
    Ysc.Env.non_prod?()
  end

  defp mask_email(email) when is_binary(email) do
    case String.split(email, "@") do
      [local, domain] ->
        masked_local =
          String.slice(local, 0, 1) <>
            String.duplicate("*", max(String.length(local) - 1, 3))

        "#{masked_local}@#{domain}"

      _ ->
        "***@***"
    end
  end

  defp mask_email(_), do: "***@***"

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

    needs_payment_method_setup =
      user.state == :pending_approval and
        is_nil(Payments.get_default_payment_method(user))

    # User needs setup if they have incomplete requirements
    needs_any_setup =
      needs_email_verification or needs_password_setup or needs_phone_setup or
        needs_phone_verification or needs_payment_method_setup

    # Access control logic:
    # 1. If user doesn't need any setup, deny access
    # 2. Email verification step: always allow (for signup flow)
    # 3. Password/Phone/Payment steps: require ownership (authentication)
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
        phone_verification: phone_number_exists and not phone_verified,
        payment_method_setup: needs_payment_method_setup
      }

      # Load the membership plan chosen during registration for pending users
      signup_plan =
        if needs_payment_method_setup do
          registration_form =
            Accounts.get_user!(user.id)
            |> Ysc.Repo.preload(:registration_form)
            |> Map.get(:registration_form)

          if registration_form do
            plans = Application.get_env(:ysc, :membership_plans, [])
            membership_type = registration_form.membership_type || :single
            Enum.find(plans, &(&1.id == membership_type))
          end
        end

      # Determine starting step based on what user needs and their auth status
      starting_step =
        cond do
          # If user needs email verification, start there (always accessible)
          user_needs.email_verification ->
            0

          # If user needs payment method setup and is authenticated (comes before password)
          user_needs.payment_method_setup and is_owner ->
            1

          # If user needs password setup and is authenticated
          user_needs.password_setup and is_owner ->
            2

          # If user needs phone setup and is authenticated
          user_needs.phone_setup and is_owner ->
            3

          # If user needs phone verification and is authenticated
          user_needs.phone_verification and is_owner ->
            4

          # User has completed all necessary steps
          true ->
            5
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

      # Only send email verification when this user still needs it. Otherwise an
      # unauthenticated visitor with a guessed or leaked user_id could trigger
      # verification emails (and, after expiry, repeat) for unrelated flows such
      # as payment setup.
      if user_needs.email_verification do
        case Ysc.VerificationCache.get_code(user.id, :email_verification) do
          {:ok, _existing_code} ->
            :ok

          {:error, _} ->
            code = Accounts.generate_and_store_email_verification_code(user)
            _job = Accounts.send_email_verification_code(user, code, "initial")
        end
      end

      email_changeset = %{"verification_code" => ""} |> to_form()

      # Start at step 0 - user progresses through the flow

      display_email = if is_owner, do: user.email, else: mask_email(user.email)

      public_key = Application.get_env(:stripity_stripe, :public_key)

      socket =
        socket
        |> assign(:page_title, "Complete Your Account Setup")
        |> assign(
          :meta_description,
          "Complete your Young Scandinavians Club membership account setup."
        )
        |> assign(:user, user)
        |> assign(:display_email, display_email)
        |> assign(:current_step, current_step)
        |> assign(:email_verified, false)
        |> assign(:from_signup, false)
        |> assign(:user_needs, user_needs)
        |> assign(:stepper_needs, user_needs)
        |> assign(:trigger_login, false)
        |> assign(:email_form, email_changeset)
        |> assign(:password_form, to_form(password_changeset))
        |> assign(:phone_form, to_form(phone_changeset))
        |> assign(:phone_verification_form, phone_verification_changeset)
        |> assign(:code_valid, false)
        |> assign(:phone_code_valid, false)
        |> assign(:email_verification_code_state, %{})
        |> assign(:phone_verification_code_state, %{})
        |> assign(:email_resend_disabled_until, nil)
        |> assign(:sms_resend_disabled_until, nil)
        |> assign(:payment_intent_secret, nil)
        |> assign(:signup_plan, signup_plan)
        |> assign(:public_key, public_key)

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Clear any stale flash from previous steps so old toasts don't replay on re-renders
    socket = Phoenix.LiveView.clear_flash(socket)

    # Handle step and from_signup parameters from URL query string
    step_param = params["step"]
    from_signup = params["from_signup"] == "true"

    if step_param do
      requested_step = String.to_integer(step_param)
      current_user = socket.assigns.current_user
      user = socket.assigns.user

      # Re-fetch user to get latest data for access control (important after email verification)
      fresh_user = Accounts.get_user!(user.id)

      # Steps after email verification require a real session whose user matches the
      # account in the URL. Never derive current_user from the path alone — that would
      # let an unauthenticated visitor impersonate the account for LiveView events.
      can_access_step =
        cond do
          requested_step == 0 ->
            # Email verification step: always accessible
            true

          is_nil(fresh_user.email_verified_at) ->
            false

          is_nil(current_user) or current_user.id != fresh_user.id ->
            false

          true ->
            true
        end

      if can_access_step do
        user_needs = socket.assigns.user_needs

        # Update socket assigns with fresh user data
        socket = assign(socket, user: fresh_user)

        # Calculate allowed step based on what user needs and their authentication
        # New order: 0=email, 1=payment, 2=password, 3=phone setup, 4=phone verify
        allowed_step =
          cond do
            # Step 0 (email verification): Always allow if user needs it
            requested_step == 0 and user_needs.email_verification ->
              0

            # Step 1 (payment method): Require authentication and need
            requested_step == 1 and not is_nil(current_user) and
                Map.get(user_needs, :payment_method_setup, false) ->
              1

            # Step 2 (password setup): Require authentication and need
            requested_step == 2 and not is_nil(current_user) and
                user_needs.password_setup ->
              2

            # Step 3 (phone setup): Require authentication and need
            requested_step == 3 and not is_nil(current_user) and
                user_needs.phone_setup ->
              3

            # Step 4 (phone verification): Require authentication and need
            requested_step == 4 and not is_nil(current_user) and
                user_needs.phone_verification ->
              4

            # Default: Stay on current step or go to completion
            true ->
              socket.assigns.current_step
          end

        # Create setup intent when user reaches the payment step (step 1)
        socket =
          if allowed_step == 1 and is_nil(socket.assigns.payment_intent_secret) do
            user = socket.assigns.user

            case Customers.create_setup_intent(user,
                   stripe: %{payment_method_types: ["card", "us_bank_account"]}
                 ) do
              {:ok, setup_intent} ->
                assign(
                  socket,
                  :payment_intent_secret,
                  setup_intent.client_secret
                )

              {:error, _} ->
                assign(socket, :payment_intent_secret, nil)
            end
          else
            socket
          end

        # Automatically send phone verification code if user reaches step 4 with unverified phone
        socket =
          if allowed_step == 4 and not is_nil(fresh_user.phone_number) and
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
                    "auto_step4"
                  )

                socket
            end
          else
            socket
          end

        {:noreply,
         assign(socket, current_step: allowed_step, from_signup: from_signup)}
      else
        # Access denied — stay on the current step without changing anything
        {:noreply, assign(socket, :from_signup, from_signup)}
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
    # Accumulate digits in a dedicated assign (phx-input may send only the changed
    # field, or paste can send as map; merge so we normalize the full code)
    current_code = socket.assigns[:email_verification_code_state] || %{}
    current_code = if is_map(current_code), do: current_code, else: %{}

    merged_code =
      if is_map(code) do
        Map.merge(current_code, code)
      else
        code
      end

    normalized_code = normalize_verification_code(merged_code)
    # Basic validation - ensure it's 6 digits
    is_valid =
      String.length(normalized_code) == 6 &&
        String.match?(normalized_code, ~r/^\d{6}$/)

    {:noreply,
     socket
     |> assign(:code_valid, is_valid)
     |> assign(:email_verification_code_state, merged_code)}
  end

  def handle_event(
        "verify_code",
        %{"verification_code" => entered_code},
        socket
      ) do
    # Handle both OTP array format and single string format
    code = normalize_verification_code(entered_code)

    user_id = socket.assigns.user.id

    case Ysc.EmailVerificationRateLimit.check(user_id) do
      :ok ->
        do_verify_email_code(socket, code)

      :rate_limited ->
        YscWeb.Flash.send_toast(
          :error,
          "Too many verification attempts. Please wait a minute and try again.",
          title: "Email verification"
        )

        {:noreply, socket}
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

        YscWeb.Flash.send_toast(
          :info,
          "A new verification code has been sent to your email.",
          title: "Email verification",
          icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
        )

        {:noreply,
         assign(
           socket,
           :email_resend_disabled_until,
           Ysc.ResendRateLimiter.disabled_until(60)
         )}

      {:error, :rate_limited, _remaining} ->
        YscWeb.Flash.send_toast(
          :error,
          "Please wait before requesting another verification code.",
          title: "Email verification"
        )

        {:noreply, socket}
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    # Only allow password validation if user is authenticated and needs password setup
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if setup_owner?(socket) && user_needs.password_setup do
      password_form =
        socket.assigns.user
        |> Accounts.change_user_password(user_params)
        |> Map.put(:action, :validate)
        |> to_form()

      {:noreply, assign(socket, password_form: password_form)}
    else
      YscWeb.Flash.send_toast(
        :error,
        "Please complete email verification first.",
        title: "Account setup"
      )

      {:noreply, socket}
    end
  end

  def handle_event("validate_phone", %{"user" => user_params}, socket) do
    # Only allow phone validation if user is authenticated and needs phone setup
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if setup_owner?(socket) && socket.assigns.current_step == 3 do
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
      YscWeb.Flash.send_toast(
        :error,
        "Phone details can only be entered on the Phone step, after earlier setup steps. Please return to Account setup and continue in order.",
        title: "Account setup"
      )

      {:noreply, socket}
    end
  end

  def handle_event("change_phone_number", _params, socket) do
    # Allow authenticated user to change phone number by going back to step 2
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if setup_owner?(socket) do
      {:noreply,
       socket
       |> assign(:current_step, 3)
       |> push_patch(to: ~p"/account/setup/#{socket.assigns.user.id}?step=3")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_password", %{"user" => user_params}, socket) do
    # Ensure user is authenticated and needs password setup
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    if not setup_owner?(socket) or not user_needs.password_setup do
      YscWeb.Flash.send_toast(:error, "Please verify your email address first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      case Accounts.set_user_initial_password(socket.assigns.user, user_params) do
        {:ok, updated_user} ->
          updated_user_needs = compute_user_needs(updated_user)

          # Determine next step based on phone status
          # Payment was already handled in step 1, so we continue with phone or completion
          next_step =
            cond do
              # Phone already verified — all done
              not is_nil(updated_user.phone_verified_at) ->
                5

              # Phone set but not verified, go to phone verification (step 4)
              not is_nil(updated_user.phone_number) ->
                4

              # Need to set up phone first (step 3)
              true ->
                3
            end

          YscWeb.Flash.send_toast(:info, "Password set successfully!",
            title: "Account setup"
          )

          {:noreply,
           socket
           |> assign(:current_step, next_step)
           |> push_patch(
             to: ~p"/account/setup/#{socket.assigns.user.id}?step=#{next_step}"
           )
           |> assign(:user, updated_user)
           |> assign(:user_needs, updated_user_needs)}

        {:error, changeset} ->
          {:noreply, assign(socket, password_form: to_form(changeset))}
      end
    end
  end

  def handle_event("save_phone", %{"user" => user_params}, socket) do
    # Ensure user is authenticated and needs phone setup
    current_user = socket.assigns.current_user
    _user_needs = socket.assigns.user_needs

    if not setup_owner?(socket) or socket.assigns.current_step != 3 do
      YscWeb.Flash.send_toast(
        :error,
        "Phone setup is not available at this step.",
        title: "Account setup"
      )

      {:noreply, socket}
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

          updated_user_needs = compute_user_needs(updated_user)

          YscWeb.Flash.send_toast(
            :info,
            "Phone number saved! Please verify it with the code we sent.",
            title: "Account setup"
          )

          # Advance to phone verification step (step 4)
          {:noreply,
           socket
           |> assign(:current_step, 4)
           |> assign(:user, updated_user)
           |> assign(:user_needs, updated_user_needs)
           |> push_patch(
             to: ~p"/account/setup/#{socket.assigns.user.id}?step=4"
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, phone_form: to_form(changeset))}
      end
    end
  end

  def handle_event("skip_phone", _params, socket) do
    # Ensure user is authenticated - re-fetch user to get latest data
    current_user = socket.assigns.current_user

    if not setup_owner?(socket) do
      YscWeb.Flash.send_toast(:error, "Please complete account setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      # Payment was already handled in step 1, so skip phone goes straight to pending-review
      one_time_token =
        Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", user.id)

      {:noreply,
       socket
       |> Phoenix.LiveView.redirect(
         to: ~p"/users/log-in/auto?#{%{token: one_time_token}}"
       )}
    end
  end

  def handle_event("set-step", %{"step" => step_str}, socket) do
    requested_step = String.to_integer(step_str)
    current_user = socket.assigns.current_user
    user_needs = socket.assigns.user_needs

    # Check if step is accessible based on authentication and user needs
    # New order: 0=email, 1=payment, 2=password, 3=phone setup, 4=phone verify
    owner? =
      not is_nil(current_user) and current_user.id == socket.assigns.user.id

    can_access_step =
      cond do
        # Step 0: Always allow if user needs email verification
        requested_step == 0 and user_needs.email_verification ->
          true

        # Steps 1+: Must be logged in as the user in the URL (same as handle_params)
        not owner? ->
          false

        # Step 1: Allow if user needs payment method setup
        requested_step == 1 and
            Map.get(user_needs, :payment_method_setup, false) ->
          true

        # Step 2: Allow if user needs password setup
        requested_step == 2 and user_needs.password_setup ->
          true

        # Step 3: Allow if user needs phone setup
        requested_step == 3 and user_needs.phone_setup ->
          true

        # Step 4: Allow if user needs phone verification
        requested_step == 4 and user_needs.phone_verification ->
          true

        # Default: Deny access
        true ->
          false
      end

    if can_access_step do
      {:noreply, assign(socket, :current_step, requested_step)}
    else
      YscWeb.Flash.send_toast(
        :error,
        "Please complete the required steps in order.",
        title: "Account setup"
      )

      {:noreply,
       redirect(socket, to: ~p"/account/setup/#{socket.assigns.user.id}")}
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

    if setup_owner?(socket) && user_needs.phone_verification do
      # Accumulate digits in a dedicated assign (phx-input may send only the changed
      # field, or paste can send as map; merge so we normalize the full code)
      current_code = socket.assigns[:phone_verification_code_state] || %{}
      current_code = if is_map(current_code), do: current_code, else: %{}

      merged_code =
        if is_map(code) do
          Map.merge(current_code, code)
        else
          code
        end

      normalized_code = normalize_verification_code(merged_code)
      # Basic validation - ensure it's 6 digits
      is_valid =
        String.length(normalized_code) == 6 &&
          String.match?(normalized_code, ~r/^\d{6}$/)

      {:noreply,
       socket
       |> assign(:phone_code_valid, is_valid)
       |> assign(:phone_verification_code_state, merged_code)}
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

    if not setup_owner?(socket) or not user_needs.phone_verification do
      YscWeb.Flash.send_toast(:error, "Please complete phone setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      # Handle both OTP array format and single string format
      code = normalize_verification_code(entered_code)

      case Accounts.verify_phone_verification_code(user, code) do
        {:ok, :verified} ->
          # Mark phone as verified in database
          {:ok, updated_user} = Accounts.mark_phone_verified(user)

          # Use a short-lived signed token (same pattern as email verification)
          token =
            Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", updated_user.id)

          {:noreply,
           socket
           |> Phoenix.LiveView.redirect(
             to:
               ~p"/users/log-in/auto?#{%{token: token, redirect_to: "/account/setup/#{updated_user.id}?step=5"}}"
           )}

        {:error, :not_found} ->
          YscWeb.Flash.send_toast(
            :error,
            "No verification code found. Please request a new one.",
            title: "Phone verification"
          )

          {:noreply, socket}

        {:error, :expired} ->
          YscWeb.Flash.send_toast(
            :error,
            "Verification code has expired. Please request a new one.",
            title: "Phone verification"
          )

          {:noreply, socket}

        {:error, :invalid_code} ->
          YscWeb.Flash.send_toast(
            :error,
            "Invalid verification code. Please try again.",
            title: "Phone verification"
          )

          {:noreply, socket}
      end
    end
  end

  def handle_event("resend_phone_code", _params, socket) do
    # Ensure user is authenticated and needs phone verification
    user_needs = socket.assigns.user_needs

    if not setup_owner?(socket) or not user_needs.phone_verification do
      YscWeb.Flash.send_toast(:error, "Please complete phone setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
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

          YscWeb.Flash.send_toast(
            :info,
            "Verification code sent to your phone.",
            title: "Phone verification",
            icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
          )

          {:noreply,
           assign(
             socket,
             :sms_resend_disabled_until,
             Ysc.ResendRateLimiter.disabled_until(60)
           )}

        {:error, :rate_limited, _remaining} ->
          YscWeb.Flash.send_toast(
            :error,
            "Please wait before requesting another verification code.",
            title: "Phone verification"
          )

          {:noreply, socket}
      end
    end
  end

  def handle_event(
        "payment-method-set",
        %{"payment_method_id" => payment_method_id},
        socket
      ) do
    current_user = socket.assigns.current_user
    user = socket.assigns.user

    if not setup_owner?(socket) or socket.assigns.current_step != 1 do
      YscWeb.Flash.send_toast(
        :error,
        "Cannot save payment method at this step.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             Stripe.PaymentMethod.retrieve(payment_method_id)
           end) do
        {:ok, stripe_payment_method} ->
          _ =
            Ysc.Stripe.RetryHelper.stripe_retry(fn ->
              Stripe.PaymentMethod.update(payment_method_id, %{
                metadata: %{"set_as_default" => "true"}
              })
            end)

          case Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_payment_method
               ) do
            {:ok, _} ->
              _ =
                Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                  Stripe.Customer.update(user.stripe_id, %{
                    invoice_settings: %{
                      default_payment_method: payment_method_id
                    }
                  })
                end)

              # Advance to the next required step (password, phone, or pending-review)
              updated_user_needs =
                compute_user_needs(Accounts.get_user!(user.id))

              next_step =
                cond do
                  updated_user_needs.password_setup -> 2
                  updated_user_needs.phone_setup -> 3
                  updated_user_needs.phone_verification -> 4
                  true -> 5
                end

              YscWeb.Flash.send_toast(
                :info,
                "Payment method saved! We'll charge it automatically if your application is approved.",
                title: "Account setup"
              )

              socket = assign(socket, :user_needs, updated_user_needs)

              if next_step == 5 do
                {:noreply, push_navigate(socket, to: ~p"/pending-review")}
              else
                {:noreply,
                 socket
                 |> assign(:current_step, next_step)
                 |> push_patch(
                   to: ~p"/account/setup/#{user.id}?step=#{next_step}"
                 )}
              end

            {:error, _error} ->
              Ysc.Logging.error(
                "Failed to upsert payment method in account setup",
                user_id: user.id
              )

              YscWeb.Flash.send_toast(
                :error,
                "Failed to save payment method. Please try again.",
                title: "Payment"
              )

              {:noreply, socket}
          end

        {:error, error} ->
          message =
            case error do
              %Stripe.Error{message: msg} -> msg
              _ -> "Failed to process payment method. Please try again."
            end

          YscWeb.Flash.send_toast(:error, message, title: "Payment")
          {:noreply, socket}
      end
    end
  end

  def handle_event("retry_payment_setup", _params, socket) do
    current_user = socket.assigns.current_user
    user = socket.assigns.user

    if not setup_owner?(socket) do
      YscWeb.Flash.send_toast(:error, "Please complete account setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      case Customers.create_setup_intent(user,
             stripe: %{payment_method_types: ["card", "us_bank_account"]}
           ) do
        {:ok, setup_intent} ->
          {:noreply,
           assign(socket, :payment_intent_secret, setup_intent.client_secret)}

        {:error, _} ->
          YscWeb.Flash.send_toast(
            :error,
            "Still unable to load the payment form. Please try again or contact support.",
            title: "Payment"
          )

          {:noreply, socket}
      end
    end
  end

  defp do_verify_email_code(socket, code) do
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
        updated_user_needs = compute_user_needs(updated_user)

        # Determine next step based on what still needs to be completed
        # New order: 1=payment, 2=password, 3=phone setup, 4=phone verify
        next_step =
          cond do
            updated_user_needs.payment_method_setup -> 1
            updated_user_needs.password_setup -> 2
            updated_user_needs.phone_setup -> 3
            updated_user_needs.phone_verification -> 4
            true -> 5
          end

        # Short-lived one-time token for auto-login (verified by controller, then session created)
        one_time_token =
          Phoenix.Token.sign(YscWeb.Endpoint, "auto_login", updated_user.id)

        # Redirect to auto-login to establish session, then back to account setup
        {:noreply,
         socket
         |> Phoenix.LiveView.redirect(
           to:
             ~p"/users/log-in/auto?#{%{token: one_time_token, redirect_to: "/account/setup/#{updated_user.id}?step=#{next_step}"}}"
         )}

      {:error, :not_found} ->
        YscWeb.Flash.send_toast(
          :error,
          "No verification code found. Please request a new one.",
          title: "Email verification"
        )

        {:noreply, socket}

      {:error, :expired} ->
        YscWeb.Flash.send_toast(
          :error,
          "Verification code has expired. Please request a new one.",
          title: "Email verification"
        )

        {:noreply, socket}

      {:error, :invalid_code} ->
        YscWeb.Flash.send_toast(
          :error,
          "Invalid verification code. Please try again.",
          title: "Email verification"
        )

        {:noreply, socket}
    end
  end

  # Helper function to normalize verification code from OTP array/map or string format
  defp normalize_verification_code(code) when is_map(code) do
    # Handle map format: %{"0" => "1", "1" => "2", ...}
    # Form may include non-integer keys (e.g. "_unused_1"); keep only integer keys
    code
    |> Enum.filter(fn {k, _v} ->
      case Integer.parse(k) do
        {_int, ""} -> true
        _ -> false
      end
    end)
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

  # LiveView events are not gated by handle_params; require the session user to
  # match the account in the URL before any post-verification setup action.
  defp setup_owner?(%{assigns: %{current_user: %{id: id}, user: %{id: id}}}),
    do: true

  defp setup_owner?(_), do: false
end
