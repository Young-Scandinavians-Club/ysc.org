defmodule YscWeb.AccountSetupLive do
  use YscWeb, :live_view

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Accounts.VerificationCodes
  alias Ysc.Customers
  alias YscWeb.AccountSetupAccess
  alias Ysc.Payments
  alias Ysc.Subscriptions

  defp payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  defp customer_module do
    Application.get_env(:ysc, :stripe_customer_module, Stripe.Customer)
  end

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
          :if={@loading_account_setup?}
          id="account-setup-loading"
          class="space-y-6"
          role="status"
          aria-live="polite"
        >
          <span class="sr-only">Loading account setup…</span>
          <.skeleton_block class="h-8 w-2/3 rounded" />
          <.skeleton_block class="h-4 w-full rounded" />
          <.skeleton_block class="h-4 w-5/6 rounded" />
          <.skeleton_block class="h-12 w-full rounded-lg" />
          <.skeleton_block class="h-11 w-1/3 rounded-lg" />
        </div>

        <div
          :if={!@loading_account_setup? and @current_step === 0}
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
              We sent a 6-digit code to <strong><%= @display_email %></strong>. Enter it below to continue.
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
              label="6-digit verification code"
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
                  <.icon name="hero-check-circle" class="w-5 h-5" />Verify Code
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={
          !@loading_account_setup? and @current_step === 1 and
            (@user_needs.payment_method_setup or @user_needs.membership_activation)
        }>
          <%= if @user.state == :active do %>
            <.header class="text-left">
              Activate Your Membership
              <:subtitle>
                Your application is approved. Add or confirm a payment method to activate your membership and unlock member benefits.
              </:subtitle>
            </.header>
          <% else %>
            <.header class="text-left">
              Save Your Payment Method
              <:subtitle>
                Save a payment method so we can activate your membership if you're approved. You won't be charged until the board approves your application.
              </:subtitle>
            </.header>
          <% end %>

          <%= if @signup_plan do %>
            <div class="mt-4 mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
              <p class="text-sm font-semibold text-blue-900 mb-1">
                Membership type on your application
              </p>
              <p class="text-base font-bold text-blue-800">
                {@signup_plan.name} &mdash; {Money.to_string!(
                  Money.new(:USD, @signup_plan.amount)
                )}/year
              </p>
            </div>
          <% end %>

          <%= if @user.state == :active do %>
            <div class="mb-6 p-4 bg-green-50 border border-green-200 rounded-lg text-sm text-green-900 space-y-2">
              <p>
                <strong>You're approved.</strong>
                We'll charge your card now for your first year of membership. Your membership renews automatically each year unless you turn off auto-renewal in account settings.
              </p>
            </div>

            <div
              :if={@user_needs.membership_activation}
              class="mb-6 flex flex-col sm:flex-row gap-3"
            >
              <.button
                id="retry-membership-activation"
                type="button"
                phx-click="retry_membership_activation"
                phx-disable-with="Activating..."
                color="blue"
              >
                Activate Membership Now
              </.button>
              <.link
                navigate={~p"/users/membership"}
                class="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-blue-700 hover:underline"
              >
                Or pay from membership settings
              </.link>
            </div>
          <% else %>
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
                If your application is approved, we'll charge this card for your first year of membership. Your membership renews automatically each year unless you turn off auto-renewal in account settings.
              </p>
            </div>
          <% end %>

          <%= if @payment_intent_secret do %>
            <form
              id="setup-payment-form"
              class="flex flex-col space-y-4"
              phx-hook="StripeInput"
              data-clientSecret={@payment_intent_secret}
              data-publicKey={@public_key}
              data-submitURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/payment-method"}
              data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
              data-billing-details={@stripe_billing_details}
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
                  <%= if @user.state == :active do %>
                    Save Payment Method &amp; Activate
                  <% else %>
                    Save Payment Method &amp; Continue
                  <% end %>
                </.button>
              </div>
            </form>
          <% else %>
            <div
              :if={@user_needs.payment_method_setup}
              class="text-center py-8 space-y-4"
            >
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

        <div :if={
          !@loading_account_setup? and @current_step === 2 and
            @user_needs.password_setup
        }>
          <.header class="text-left">
            Set Your Password
            <:subtitle>
              Create a password at least 12 characters long to access your account and manage your membership.
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
                  <.icon name="hero-check-circle" class="w-5 h-5" />Set Password
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={!@loading_account_setup? and @current_step === 3}>
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
                <.icon name="hero-check-circle" class="w-5 h-5" />Save Phone Number
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <div
          :if={
            !@loading_account_setup? and @current_step === 4 and
              @user_needs.phone_verification
          }
          id="phone-verification-step"
          phx-hook="ResendTimer"
        >
          <.header class="text-left">
            Verify Your Phone Number
            <:subtitle>
              We sent a 6-digit code to <strong><%= Ysc.Extensions.PhoneNumber.format_for_display(@user.phone_number) || @user.phone_number %></strong>. Enter it below to continue.
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
              label="6-digit verification code"
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
                  <.icon name="hero-check-circle" class="w-5 h-5" />Verify Phone Number
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={
          (!@loading_account_setup? and @current_step === 5) && !@trigger_login
        }>
          <%= cond do %>
            <% @user.state == :active and not @user_needs.payment_method_setup and
                 not @user_needs.membership_activation -> %>
              <.header class="text-left">
                You're All Set!
                <:subtitle>
                  Your membership is active. Welcome to the Young Scandinavians Club!
                </:subtitle>
              </.header>

              <div class="text-center py-8">
                <.icon
                  name="hero-check-circle"
                  class="w-16 h-16 text-green-600 mx-auto mb-4"
                />
                <p class="text-zinc-600 mb-4">
                  Account setup is complete and your membership is active.
                </p>
                <.link
                  navigate={~p"/"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                >
                  Go to Home
                </.link>
              </div>
            <% @user.state == :active -> %>
              <.header class="text-left">
                One More Step
                <:subtitle>
                  Your application is approved — activate your membership to unlock member benefits.
                </:subtitle>
              </.header>

              <div class="text-center py-8">
                <.icon
                  name="hero-credit-card"
                  class="w-16 h-16 text-blue-600 mx-auto mb-4"
                />
                <p class="text-zinc-600 mb-4">
                  Add a payment method to activate your membership.
                </p>
                <.link
                  patch={~p"/account/setup/#{@user.id}?step=1"}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                >
                  Activate Membership
                </.link>
              </div>
            <% true -> %>
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
          <% end %>
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
      if Map.get(user_needs, :payment_method_setup, false) or
           Map.get(user_needs, :membership_activation, false),
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
    if Map.get(user_needs, :payment_method_setup, false) or
         Map.get(user_needs, :membership_activation, false) do
      {step_index + 1, Map.put(step_mapping, 1, step_index)}
    else
      {step_index, step_mapping}
    end
  end

  defp unpaid_active_primary?(user) do
    user.state == :active and not Accounts.sub_account?(user) and
      is_nil(MembershipCache.get_active_membership(user))
  end

  # Compute user_needs map from a user struct.
  defp compute_user_needs(user, opts \\ []) do
    check_payment? = Keyword.get(opts, :check_payment?, true)

    has_default_pm? =
      if check_payment? do
        not is_nil(Payments.get_default_payment_method(user))
      else
        false
      end

    unpaid_active? = unpaid_active_primary?(user)

    payment_method_setup =
      cond do
        not check_payment? and
            (user.state == :pending_approval or unpaid_active?) ->
          true

        user.state == :pending_approval ->
          not has_default_pm?

        unpaid_active? and not has_default_pm? ->
          true

        true ->
          false
      end

    membership_activation =
      unpaid_active? and has_default_pm? and check_payment?

    %{
      email_verification: is_nil(user.email_verified_at),
      password_setup: is_nil(user.password_set_at),
      phone_setup: is_nil(user.phone_number),
      phone_verification:
        not is_nil(user.phone_number) and is_nil(user.phone_verified_at),
      payment_method_setup: payment_method_setup,
      membership_activation: membership_activation
    }
  end

  defp signup_plan_for(user, user_needs) do
    if user_needs.payment_method_setup or user_needs.membership_activation do
      registration_form = user.registration_form

      if registration_form do
        plans = Application.get_env(:ysc, :membership_plans, [])
        membership_type = registration_form.membership_type || :single
        Enum.find(plans, &(&1.id == membership_type))
      end
    end
  end

  defp starting_step_for(user_needs, is_owner) do
    cond do
      user_needs.email_verification ->
        0

      needs_payment_step?(user_needs) and is_owner ->
        1

      user_needs.password_setup and is_owner ->
        2

      user_needs.phone_setup and is_owner ->
        3

      user_needs.phone_verification and is_owner ->
        4

      true ->
        5
    end
  end

  defp needs_payment_step?(user_needs) do
    Map.get(user_needs, :payment_method_setup, false) or
      Map.get(user_needs, :membership_activation, false)
  end

  defp next_setup_step(user_needs) do
    cond do
      needs_payment_step?(user_needs) -> 1
      user_needs.password_setup -> 2
      user_needs.phone_setup -> 3
      user_needs.phone_verification -> 4
      true -> 5
    end
  end

  defp membership_return_url(user) do
    YscWeb.Endpoint.url() <> "/billing/user/#{user.id}/finalize"
  end

  defp ensure_verification_email_sent(user) do
    _ = VerificationCodes.ensure(user, :email, suffix: "initial")
    :ok
  end

  defp maybe_adjust_step_after_payment_refine(socket, user_needs) do
    if socket.assigns.current_step == 1 and not needs_payment_step?(user_needs) do
      assign(
        socket,
        :current_step,
        starting_step_for(user_needs, socket.assigns.is_owner)
      )
    else
      socket
    end
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
    connected_remount? =
      connected?(socket) &&
        socket.assigns[:user_id] == user_id &&
        socket.assigns[:loading_account_setup?] == false &&
        not is_nil(socket.assigns[:user])

    cond do
      connected_remount? ->
        {:ok, socket}

      connected?(socket) ->
        load_account_setup(socket, user_id)

      true ->
        {:ok, assign_account_setup_loading_shell(socket, user_id)}
    end
  end

  defp assign_account_setup_loading_shell(socket, user_id) do
    empty_user_needs = %{
      email_verification: false,
      password_setup: false,
      phone_setup: false,
      phone_verification: false,
      payment_method_setup: false,
      membership_activation: false
    }

    socket
    |> assign(:loading_account_setup?, true)
    |> assign(:user_id, user_id)
    |> assign(:page_title, "Complete Your Account Setup")
    |> assign(
      :meta_description,
      "Complete your Young Scandinavians Club membership account setup."
    )
    |> assign(:user, nil)
    |> assign(:is_owner, false)
    |> assign(:display_email, "")
    |> assign(:current_step, 0)
    |> assign(:email_verified, false)
    |> assign(:from_signup, false)
    |> assign(:user_needs, empty_user_needs)
    |> assign(:stepper_needs, empty_user_needs)
    |> assign(:trigger_login, false)
    |> assign(:email_form, to_form(%{"verification_code" => ""}))
    |> assign(
      :password_form,
      to_form(%{"password" => "", "password_confirmation" => ""})
    )
    |> assign(
      :phone_form,
      to_form(%{"phone_number" => "", "sms_opt_in" => "true"}, as: "user")
    )
    |> assign(:phone_verification_form, to_form(%{"verification_code" => ""}))
    |> assign(:code_valid, false)
    |> assign(:phone_code_valid, false)
    |> assign(:email_verification_code_state, %{})
    |> assign(:phone_verification_code_state, %{})
    |> assign(:email_resend_disabled_until, nil)
    |> assign(:sms_resend_disabled_until, nil)
    |> assign(:payment_intent_secret, nil)
    |> assign(:stripe_billing_details, "{}")
    |> assign(:signup_plan, nil)
    |> assign(:activation_attempted?, false)
    |> assign(:public_key, Application.get_env(:stripity_stripe, :public_key))
  end

  defp load_account_setup(socket, user_id) do
    user = Accounts.get_user!(user_id, [:registration_form])
    current_user = socket.assigns.current_user
    is_owner = !!(current_user && current_user.id == user.id)

    {user, user_needs, activation_result} =
      maybe_activate_membership_on_load(user, is_owner)

    activation_attempted? = activation_result != :skipped

    needs_any_setup = user_needs_needs_setup?(user_needs)
    can_access = needs_any_setup

    cond do
      activation_result in [:activated, :already_active] and not needs_any_setup ->
        {:ok,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Your membership is active. Welcome!",
           title: "Membership"
         )
         |> redirect(to: ~p"/")}

      can_access ->
        signup_plan = signup_plan_for(user, user_needs)
        current_step = starting_step_for(user_needs, is_owner)

        phone_changeset =
          if user_needs.phone_setup or is_nil(user.phone_number) do
            Ysc.Accounts.User.registration_changeset(
              user,
              %{"sms_opt_in" => "true"},
              hash_password: false,
              validate_email: false
            )
          else
            Ysc.Accounts.User.registration_changeset(
              user,
              %{
                "phone_number" => user.phone_number,
                "sms_opt_in" =>
                  if(user.event_notifications_sms, do: "true", else: "false")
              },
              hash_password: false,
              validate_email: false
            )
          end

        phone_verification_changeset = %{"verification_code" => ""} |> to_form()
        password_changeset = Accounts.change_user_password(user)
        email_changeset = %{"verification_code" => ""} |> to_form()

        display_email =
          if is_owner, do: user.email, else: mask_email(user.email)

        public_key = Application.get_env(:stripity_stripe, :public_key)

        socket =
          socket
          |> assign(:loading_account_setup?, false)
          |> assign(:user_id, user_id)
          |> assign(:page_title, "Complete Your Account Setup")
          |> assign(
            :meta_description,
            "Complete your Young Scandinavians Club membership account setup."
          )
          |> assign(:user, user)
          |> assign(:is_owner, is_owner)
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
          |> assign(
            :stripe_billing_details,
            Ysc.Customers.payment_element_default_values_json(user)
          )
          |> assign(:signup_plan, signup_plan)
          |> assign(:public_key, public_key)
          |> assign(:activation_attempted?, activation_attempted?)
          |> refine_setup_needs_assigns(user)
          |> then(fn s ->
            if s.assigns.user_needs.email_verification and
                 email_verification_authorized?(s) do
              ensure_verification_email_sent(user)
            end

            s
          end)

        if user_needs_needs_setup?(socket.assigns.user_needs) do
          {:ok, socket}
        else
          {:ok, redirect(socket, to: ~p"/")}
        end

      true ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  defp maybe_activate_membership_on_load(user, is_owner) do
    user_needs = compute_user_needs(user, check_payment?: true)

    if is_owner and user_needs.membership_activation do
      case Subscriptions.activate_membership_with_saved_payment_method(user,
             return_url: membership_return_url(user)
           ) do
        {:ok, status} when status in [:activated, :already_active] ->
          YscWeb.Emails.ApplicationApprovedPaymentSuccess.maybe_schedule(
            user,
            status
          )

          refreshed = Accounts.get_user!(user.id, [:registration_form])
          {refreshed, compute_user_needs(refreshed), status}

        {:error, _reason} ->
          {user, user_needs, :activation_failed}
      end
    else
      {user, user_needs, :skipped}
    end
  end

  # Mid-setup approval with PM on file: try activation before routing steps.
  # Skip when mount already attempted activation in this load cycle to avoid
  # a duplicate Stripe subscription create.
  defp maybe_activate_membership_on_params(socket, fresh_user, user_needs) do
    cond do
      connected?(socket) and setup_owner?(socket) and
        user_needs.membership_activation and
          socket.assigns[:activation_attempted?] ->
        assign(socket, :activation_attempted?, false)

      connected?(socket) and setup_owner?(socket) and
          user_needs.membership_activation ->
        case Subscriptions.activate_membership_with_saved_payment_method(
               fresh_user,
               return_url: membership_return_url(fresh_user)
             ) do
          {:ok, status} when status in [:activated, :already_active] ->
            YscWeb.Emails.ApplicationApprovedPaymentSuccess.maybe_schedule(
              fresh_user,
              status
            )

            refresh_setup_user_and_needs(socket)

          {:error, _} ->
            socket
        end

      true ->
        socket
    end
  end

  defp user_needs_needs_setup?(user_needs) do
    user_needs.email_verification or user_needs.password_setup or
      user_needs.phone_setup or user_needs.phone_verification or
      needs_payment_step?(user_needs)
  end

  defp refine_setup_needs_assigns(socket, user) do
    user_needs = compute_user_needs(user, check_payment?: true)
    signup_plan = signup_plan_for(user, user_needs)

    socket
    |> assign(:user_needs, user_needs)
    |> assign(:stepper_needs, user_needs)
    |> assign(:signup_plan, signup_plan)
    |> maybe_adjust_step_after_payment_refine(user_needs)
  end

  defp refresh_setup_user_and_needs(socket) do
    user = Accounts.get_user!(socket.assigns.user.id, [:registration_form])

    socket
    |> assign(:user, user)
    |> refine_setup_needs_assigns(user)
  end

  defp maybe_redirect_after_activation(socket) do
    user_needs = socket.assigns.user_needs

    cond do
      user_needs_needs_setup?(user_needs) ->
        {:cont, socket}

      socket.assigns.user.state == :active ->
        {:halt,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Your membership is active. Welcome!",
           title: "Membership"
         )
         |> redirect(to: ~p"/")}

      true ->
        {:halt, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.loading_account_setup? do
      {:noreply, assign(socket, :from_signup, params["from_signup"] == "true")}
    else
      handle_loaded_params(params, socket)
    end
  end

  defp handle_loaded_params(params, socket) do
    # Clear any stale flash from previous steps so old toasts don't replay on re-renders
    socket = Phoenix.LiveView.clear_flash(socket)

    # Handle step and from_signup parameters from URL query string
    step_param = params["step"]
    from_signup = params["from_signup"] == "true"

    if step_param do
      requested_step = String.to_integer(step_param)
      current_user = socket.assigns.current_user

      socket =
        if connected?(socket) do
          refresh_setup_user_and_needs(socket)
        else
          socket
        end

      fresh_user = socket.assigns.user
      user_needs = socket.assigns.user_needs

      socket =
        maybe_activate_membership_on_params(socket, fresh_user, user_needs)

      case maybe_redirect_after_activation(socket) do
        {:halt, redirected} ->
          {:noreply, redirected}

        {:cont, socket} ->
          fresh_user = socket.assigns.user
          user_needs = socket.assigns.user_needs

          # Steps after email verification require a real session whose user matches the
          # account in the URL. Never derive current_user from the path alone — that would
          # let an unauthenticated visitor impersonate the account for LiveView events.
          can_access_step =
            cond do
              requested_step == 0 ->
                true

              is_nil(fresh_user.email_verified_at) ->
                false

              is_nil(current_user) or current_user.id != fresh_user.id ->
                false

              true ->
                true
            end

          if can_access_step do
            allowed_step =
              cond do
                requested_step == 0 and user_needs.email_verification ->
                  0

                # Keep unpaid / pending-without-PM users on payment until done
                needs_payment_step?(user_needs) and not is_nil(current_user) and
                    requested_step != 0 ->
                  1

                requested_step == 1 and not is_nil(current_user) and
                    needs_payment_step?(user_needs) ->
                  1

                requested_step == 2 and not is_nil(current_user) and
                    user_needs.password_setup ->
                  2

                # Allow returning to phone setup to change number while verifying
                requested_step == 3 and not is_nil(current_user) and
                    (user_needs.phone_setup or user_needs.phone_verification) ->
                  3

                requested_step == 4 and not is_nil(current_user) and
                    user_needs.phone_verification ->
                  4

                # Approval flipped needs — send them to the correct next step
                true ->
                  starting_step_for(
                    user_needs,
                    not is_nil(current_user) and
                      current_user.id == fresh_user.id
                  )
              end

            socket =
              if connected?(socket) && allowed_step == 1 &&
                   is_nil(socket.assigns.payment_intent_secret) do
                case Customers.create_setup_intent(fresh_user,
                       stripe: %{
                         payment_method_types: ["card", "us_bank_account"]
                       }
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

            socket =
              if (connected?(socket) && allowed_step == 4 &&
                    not is_nil(fresh_user.phone_number)) and
                   is_nil(fresh_user.phone_verified_at) do
                _ =
                  VerificationCodes.ensure(fresh_user, :phone,
                    suffix: "auto_step4"
                  )

                socket
              else
                socket
              end

            {:noreply,
             assign(socket,
               current_step: allowed_step,
               from_signup: from_signup
             )}
          else
            {:noreply, assign(socket, :from_signup, from_signup)}
          end
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
    merged_code =
      merge_verification_code_input(
        socket,
        :email_verification_code_state,
        code
      )

    normalized_code = normalize_verification_code(merged_code)

    {:noreply,
     socket
     |> assign(
       :code_valid,
       VerificationCodes.valid_otp_format?(normalized_code)
     )
     |> assign(:email_verification_code_state, merged_code)}
  end

  def handle_event(
        "verify_code",
        %{"verification_code" => entered_code},
        socket
      ) do
    if email_verification_authorized?(socket) do
      do_handle_verify_code(socket, entered_code)
    else
      return_unauthorized_email_verification(socket)
    end
  end

  def handle_event("resend_code", _params, socket) do
    if email_verification_authorized?(socket) do
      do_handle_resend_code(socket)
    else
      return_unauthorized_email_verification(socket)
    end
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    # Only allow password validation if user is authenticated and needs password setup
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
    user_needs = socket.assigns.user_needs

    if not setup_owner?(socket) or not user_needs.password_setup do
      YscWeb.Flash.send_toast(:error, "Please verify your email address first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      case Accounts.set_user_initial_password(socket.assigns.user, user_params) do
        {:ok, updated_user} ->
          updated_user =
            Accounts.get_user!(updated_user.id, [:registration_form])

          updated_user_needs = compute_user_needs(updated_user)
          next_step = next_setup_step(updated_user_needs)

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
           |> assign(:user_needs, updated_user_needs)
           |> assign(:stepper_needs, updated_user_needs)}

        {:error, changeset} ->
          {:noreply, assign(socket, password_form: to_form(changeset))}
      end
    end
  end

  def handle_event("save_phone", %{"user" => user_params}, socket) do
    # Ensure user is authenticated and needs phone setup
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
          {:ok, _} =
            VerificationCodes.issue(updated_user, :phone, suffix: "initial")

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
    if setup_owner?(socket) do
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      # Payment was already handled in step 1, so skip phone goes straight to pending-review
      one_time_token = Accounts.generate_auto_login_token(user)

      {:noreply,
       socket
       |> Phoenix.LiveView.redirect(
         to: ~p"/users/log-in/auto?#{%{token: one_time_token}}"
       )}
    else
      YscWeb.Flash.send_toast(:error, "Please complete account setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
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

        # Step 1: Allow if user needs payment method setup or membership activation
        requested_step == 1 and needs_payment_step?(user_needs) ->
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
    user_needs = socket.assigns.user_needs

    if setup_owner?(socket) && user_needs.phone_verification do
      merged_code =
        merge_verification_code_input(
          socket,
          :phone_verification_code_state,
          code
        )

      normalized_code = normalize_verification_code(merged_code)

      {:noreply,
       socket
       |> assign(
         :phone_code_valid,
         VerificationCodes.valid_otp_format?(normalized_code)
       )
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
    user_needs = socket.assigns.user_needs

    if not setup_owner?(socket) or not user_needs.phone_verification do
      YscWeb.Flash.send_toast(:error, "Please complete phone setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      # Re-fetch user to get latest data
      user = Accounts.get_user!(socket.assigns.user.id)

      code =
        socket
        |> merge_verification_code_input(
          :phone_verification_code_state,
          entered_code
        )
        |> normalize_verification_code()

      case VerificationCodes.verify(user, :phone, code) do
        {:ok, :verified} ->
          do_verify_phone_code_success(socket, user)

        {:error, :rate_limited} ->
          YscWeb.Flash.send_toast(
            :error,
            "Too many verification attempts. Please wait a minute and try again.",
            title: "Phone verification"
          )

          {:noreply, socket}

        {:error, reason} ->
          YscWeb.Flash.send_toast(
            :error,
            verification_error_message(reason),
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
      user = Accounts.get_user!(socket.assigns.user.id)

      case VerificationCodes.resend(user, :phone) do
        {:ok, %{disabled_until: disabled_until}} ->
          YscWeb.Flash.send_toast(
            :info,
            "Verification code sent to your phone.",
            title: "Phone verification",
            icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
          )

          {:noreply, assign(socket, :sms_resend_disabled_until, disabled_until)}

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
    user = Accounts.get_user!(socket.assigns.user.id, [:registration_form])

    if not setup_owner?(socket) or socket.assigns.current_step != 1 do
      YscWeb.Flash.send_toast(
        :error,
        "Cannot save payment method at this step.",
        title: "Account setup"
      )

      {:noreply, socket}
    else
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             payment_method_module().retrieve(payment_method_id)
           end) do
        {:ok, stripe_payment_method} ->
          _ =
            Ysc.Stripe.RetryHelper.stripe_retry(fn ->
              payment_method_module().update(payment_method_id, %{
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
                  customer_module().update(
                    user.stripe_id,
                    %{
                      invoice_settings: %{
                        default_payment_method: payment_method_id
                      }
                    },
                    []
                  )
                end)

              advance_after_payment_method_saved(socket, user)

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
          message = Ysc.PaymentUserMessages.format_stripe_error(error)

          YscWeb.Flash.send_toast(:error, message, title: "Payment")
          {:noreply, socket}
      end
    end
  end

  def handle_event("retry_membership_activation", _params, socket) do
    if setup_owner?(socket) do
      user = Accounts.get_user!(socket.assigns.user.id, [:registration_form])

      case Subscriptions.activate_membership_with_saved_payment_method(user,
             return_url: membership_return_url(user)
           ) do
        {:ok, status} when status in [:activated, :already_active] ->
          YscWeb.Emails.ApplicationApprovedPaymentSuccess.maybe_schedule(
            user,
            status
          )

          socket = refresh_setup_user_and_needs(socket)

          case maybe_redirect_after_activation(socket) do
            {:halt, redirected} ->
              {:noreply, redirected}

            {:cont, socket} ->
              next_step = next_setup_step(socket.assigns.user_needs)

              YscWeb.Flash.send_toast(
                :info,
                "Your membership is active!",
                title: "Membership"
              )

              {:noreply,
               socket
               |> assign(:current_step, next_step)
               |> push_patch(
                 to: ~p"/account/setup/#{user.id}?step=#{next_step}"
               )}
          end

        {:error, :no_payment_method} ->
          YscWeb.Flash.send_toast(
            :error,
            "Please save a payment method first.",
            title: "Membership"
          )

          {:noreply, refresh_setup_user_and_needs(socket)}

        {:error, _reason} ->
          YscWeb.Flash.send_toast(
            :error,
            "We couldn't activate your membership. Please try again or pay from membership settings.",
            title: "Membership"
          )

          {:noreply, refresh_setup_user_and_needs(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry_payment_setup", _params, socket) do
    user = socket.assigns.user

    if setup_owner?(socket) do
      case Customers.create_setup_intent(user,
             stripe: %{payment_method_types: ["card", "us_bank_account"]}
           ) do
        {:ok, setup_intent} ->
          {:noreply,
           assign(socket, :payment_intent_secret, setup_intent.client_secret)}

        {:error, _} ->
          YscWeb.Flash.send_toast(
            :error,
            "Still unable to load the payment form. Please email #{Ysc.EmailConfig.contact_email()} and we'll help you complete your application.",
            title: "Payment"
          )

          {:noreply, socket}
      end
    else
      YscWeb.Flash.send_toast(:error, "Please complete account setup first.",
        title: "Account setup"
      )

      {:noreply, socket}
    end
  end

  defp advance_after_payment_method_saved(socket, user) do
    user = Accounts.get_user!(user.id, [:registration_form])

    {socket, toast_message, activated?} =
      if user.state == :active and unpaid_active_primary?(user) do
        case Subscriptions.activate_membership_with_saved_payment_method(user,
               return_url: membership_return_url(user)
             ) do
          {:ok, status} when status in [:activated, :already_active] ->
            YscWeb.Emails.ApplicationApprovedPaymentSuccess.maybe_schedule(
              user,
              status
            )

            socket = refresh_setup_user_and_needs(socket)

            {socket, "Payment saved and your membership is now active!", true}

          {:error, _reason} ->
            socket = refresh_setup_user_and_needs(socket)

            {socket,
             "Payment method saved, but we couldn't activate membership yet. Use Activate Membership Now or pay from settings.",
             false}
        end
      else
        socket =
          socket
          |> assign(:user, user)
          |> refine_setup_needs_assigns(user)

        {socket,
         "Payment method saved! We'll charge it automatically if your application is approved.",
         false}
      end

    YscWeb.Flash.send_toast(:info, toast_message, title: "Account setup")

    case maybe_redirect_after_activation(socket) do
      {:halt, redirected} ->
        {:noreply, redirected}

      {:cont, socket} ->
        next_step = next_setup_step(socket.assigns.user_needs)

        cond do
          activated? and next_step == 5 ->
            {:noreply, push_navigate(socket, to: ~p"/")}

          next_step == 5 and socket.assigns.user.state == :pending_approval ->
            {:noreply, push_navigate(socket, to: ~p"/pending-review")}

          next_step == 5 and socket.assigns.user.state == :active ->
            {:noreply,
             socket
             |> assign(:current_step, 1)
             |> push_patch(to: ~p"/account/setup/#{user.id}?step=1")}

          true ->
            {:noreply,
             socket
             |> assign(:current_step, next_step)
             |> push_patch(to: ~p"/account/setup/#{user.id}?step=#{next_step}")}
        end
    end
  end

  defp do_verify_phone_code_success(socket, user) do
    {:ok, updated_user} = Accounts.mark_phone_verified(user)
    token = Accounts.generate_auto_login_token(updated_user)

    {:noreply,
     socket
     |> Phoenix.LiveView.redirect(
       to:
         ~p"/users/log-in/auto?#{%{token: token, redirect_to: "/account/setup/#{updated_user.id}?step=5"}}"
     )}
  end

  defp do_handle_verify_code(socket, entered_code) do
    code =
      socket
      |> merge_verification_code_input(
        :email_verification_code_state,
        entered_code
      )
      |> normalize_verification_code()

    case VerificationCodes.verify(socket.assigns.user, :email, code) do
      {:ok, :verified} ->
        do_verify_email_code_success(socket)

      {:error, :rate_limited} ->
        YscWeb.Flash.send_toast(
          :error,
          "Too many verification attempts. Please wait a minute and try again.",
          title: "Email verification"
        )

        {:noreply, socket}

      {:error, reason} ->
        YscWeb.Flash.send_toast(
          :error,
          verification_error_message(reason),
          title: "Email verification"
        )

        {:noreply, socket}
    end
  end

  defp do_handle_resend_code(socket) do
    case VerificationCodes.resend(socket.assigns.user, :email) do
      {:ok, %{disabled_until: disabled_until, reused?: reused?}} ->
        message =
          if reused? do
            "Your verification code was sent again to your email."
          else
            "A new verification code has been sent to your email."
          end

        YscWeb.Flash.send_toast(
          :info,
          message,
          title: "Email verification",
          icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
        )

        {:noreply, assign(socket, :email_resend_disabled_until, disabled_until)}

      {:error, :rate_limited, _remaining} ->
        YscWeb.Flash.send_toast(
          :error,
          "Please wait before requesting another verification code.",
          title: "Email verification"
        )

        {:noreply, socket}
    end
  end

  defp do_verify_email_code_success(socket) do
    {:ok, updated_user} = Accounts.mark_email_verified(socket.assigns.user)

    updated_user = Accounts.get_user!(updated_user.id, [:registration_form])
    updated_user_needs = compute_user_needs(updated_user)
    next_step = next_setup_step(updated_user_needs)

    one_time_token = Accounts.generate_auto_login_token(updated_user)

    {:noreply,
     socket
     |> Phoenix.LiveView.redirect(
       to:
         ~p"/users/log-in/auto?#{%{token: one_time_token, redirect_to: "/account/setup/#{updated_user.id}?step=#{next_step}"}}"
     )}
  end

  defp verification_error_message(:not_found),
    do: "No verification code found. Please request a new one."

  defp verification_error_message(:expired),
    do: "Verification code has expired. Please request a new one."

  defp verification_error_message(_),
    do: "Invalid verification code. Please try again."

  # phx-change may send one digit or a paste map; phx-submit can omit unchanged fields.
  # Merge with the accumulated assign so verify uses the full code the user entered.
  defp merge_verification_code_input(socket, state_key, code) do
    current_code = socket.assigns[state_key] || %{}
    current_code = if is_map(current_code), do: current_code, else: %{}

    if is_map(code) do
      Map.merge(current_code, code)
    else
      code
    end
  end

  defp normalize_verification_code(code),
    do: VerificationCodes.normalize_otp_input(code)

  # LiveView events are not gated by handle_params; require the session user to
  # match the account in the URL before any post-verification setup action.
  defp setup_owner?(%{assigns: %{current_user: %{id: id}, user: %{id: id}}}),
    do: true

  defp setup_owner?(_), do: false

  defp email_verification_authorized?(socket) do
    AccountSetupAccess.email_verification_authorized?(
      socket.assigns.user.id,
      socket.assigns.current_user,
      Map.get(socket.assigns, :setup_access_granted, false)
    )
  end

  defp return_unauthorized_email_verification(socket) do
    YscWeb.Flash.send_toast(
      :error,
      "Open the account setup link from your registration or sign-in email to verify your address.",
      title: "Email verification"
    )

    {:noreply, socket}
  end
end
