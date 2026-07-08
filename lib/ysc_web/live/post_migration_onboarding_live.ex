defmodule YscWeb.PostMigrationOnboardingLive do
  @moduledoc """
  Full-screen onboarding wizard for WP-migrated users completing their first login.

  Steps:
    1 - Profile review/edit (name, phone, date of birth, country)
    2 - Phone verification via SMS OTP (only if phone was added/changed or unverified)
    3 - Payment method collection + Stripe subscription creation
    5 - Family member listing; saved on continue, invites sent when email provided (family plans only)
  """
  use YscWeb, :live_view

  require Ysc.Logging

  # Dialyzer cannot fully type-check LiveView handle_event callbacks due to their
  # polymorphic nature and the dynamic Stripe client return types.
  @dialyzer {:nowarn_function, handle_event: 3}

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Accounts.FamilyMembers
  alias Ysc.Customers
  alias Ysc.Subscriptions

  @payment_method_module Application.compile_env(
                           :ysc,
                           :stripe_payment_method_module,
                           Stripe.PaymentMethod
                         )
  @customer_module Application.compile_env(
                     :ysc,
                     :stripe_customer_module,
                     Stripe.Customer
                   )

  # Step constants
  @step_profile 1
  @step_address 2
  @step_phone_verification 3
  @step_membership_selection 7
  @step_payment 4
  @step_family 5
  @step_complete 6

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Accounts.needs_post_migration_onboarding?(user) do
      socket =
        socket
        |> assign(:loading_onboarding_data, true)
        |> assign_onboarding_shell(user)

      if connected?(socket) do
        send(self(), :load_onboarding_data)
      end

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_info(:load_onboarding_data, socket) do
    user =
      Accounts.get_user!(socket.assigns.current_user.id, [
        :family_members,
        :registration_form,
        :billing_address,
        subscriptions: :subscription_items
      ])

    default_payment_method = Ysc.Payments.get_default_payment_method(user)

    {:noreply,
     socket
     |> assign_onboarding_data(user, default_payment_method)
     |> assign(:loading_onboarding_data, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white">
      <div class="max-w-2xl mx-auto py-8 px-4">
        <%!-- Logo --%>
        <div class="flex justify-center mb-8">
          <.link navigate={~p"/"} class="hover:opacity-80 transition duration-200">
            <.ysc_logo class="h-28" width={112} height={112} fetchpriority="high" />
          </.link>
        </div>

        <div
          :if={@loading_onboarding_data}
          id="onboarding-loading"
          role="status"
          aria-live="polite"
        >
          <span class="sr-only">Loading your account…</span>
          <div class="mb-8 flex items-center justify-center gap-2">
            <.skeleton_block :for={_ <- 1..6} class="h-2 flex-1 rounded-full" />
          </div>
          <div class="bg-white rounded-xl shadow-sm border border-zinc-200 p-6 md:p-8 space-y-4">
            <.skeleton_block class="h-6 w-1/2 rounded" />
            <.skeleton_block :for={_ <- 1..3} class="h-11 w-full rounded-lg" />
            <.skeleton_block class="h-11 w-1/3 rounded-lg" />
          </div>
        </div>

        <div :if={!@loading_onboarding_data}>
          <%!-- Stepper --%>
          <div class="mb-8">
            <.stepper
              active_step={step_index(@current_step, @steps)}
              steps={Enum.map(@steps, fn {label, _} -> label end)}
            />
          </div>

          <%!-- Step content --%>
          <div class="bg-white rounded-xl shadow-sm border border-zinc-200 p-6 md:p-8">
            <%= if @current_step == 1 do %>
              <.step_profile form={@profile_form} />
            <% end %>
            <%= if @current_step == 2 do %>
              <.step_address form={@address_form} />
            <% end %>
            <%= if @current_step == 7 do %>
              <.step_membership_selection
                form={@membership_selection_form}
                membership_plan={@membership_plan}
                membership_plans={@membership_plans}
              />
            <% end %>
            <%= if @current_step == 3 do %>
              <.step_phone_verification
                form={@phone_code_form}
                user={@user}
                phone_code_valid={@phone_code_valid}
                sms_resend_disabled_until={@sms_resend_disabled_until}
              />
            <% end %>
            <%= if @current_step == 4 do %>
              <.step_payment
                user={@user}
                membership_plan={@membership_plan}
                has_real_subscription={@has_real_subscription}
                active_subscription={@active_subscription}
                public_key={@public_key}
                payment_intent_secret={@payment_intent_secret}
                payment_method_saved={@payment_method_saved}
                default_payment_method={@default_payment_method}
              />
            <% end %>
            <%= if @current_step == 5 and @needs_family_members_step do %>
              <.step_family
                user={@user}
                family_members_forms={@family_members_forms}
                invite_results={@invite_results}
              />
            <% end %>
            <%= if @current_step == 6 do %>
              <.step_complete user={@user} />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Step components
  # ---------------------------------------------------------------------------

  attr :form, :any, required: true

  defp step_profile(assigns) do
    ~H"""
    <div>
      <.header class="text-left">
        Welcome back — let's make sure your details are up to date
        <:subtitle>
          We recently moved member accounts to our new website. Please review the information below and update anything that has changed.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="onboarding-profile-form"
        phx-submit="save_profile"
        phx-change="validate_profile"
        class="mt-6 space-y-4"
      >
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:first_name]}
            type="text"
            label="First Name"
            required
          />
          <.input field={@form[:last_name]} type="text" label="Last Name" required />
        </div>
        <.input
          field={@form[:phone_number]}
          type="phone-input"
          label="Phone Number"
        />
        <.input
          field={@form[:date_of_birth]}
          type="date"
          label="Date of Birth"
        />
        <.input
          field={@form[:most_connected_country]}
          type="select"
          label="Which Scandinavian country do you feel most connected to? (Denmark, Finland, Iceland, Norway, or Sweden)"
          options={nordic_country_options()}
          prompt="Select a country"
        />
        <:actions>
          <div class="flex justify-end w-full">
            <.button type="submit" phx-disable-with="Saving...">
              Confirm & Continue
              <.icon name="hero-arrow-right" class="w-4 h-4 ms-1 -mt-0.5" />
            </.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  attr :form, :any, required: true

  defp step_address(assigns) do
    ~H"""
    <div>
      <.header class="text-left">
        Confirm Your Address
        <:subtitle>
          Please review and confirm your mailing address. We use this for membership correspondence and renewal notices.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="onboarding-address-form"
        phx-submit="save_address"
        phx-change="validate_address"
        class="mt-6 space-y-4"
      >
        <.input
          field={@form[:address]}
          type="text"
          label="Street Address"
          placeholder="123 Main St"
          required
        />
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input field={@form[:city]} type="text" label="City" required />
          <.input field={@form[:region]} type="text" label="State / Region" />
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:postal_code]}
            type="text"
            label="Postal / ZIP Code"
            required
          />
          <.input field={@form[:country]} type="text" label="Country" required />
        </div>
        <:actions>
          <div class="flex justify-end w-full">
            <.button type="submit" phx-disable-with="Saving...">
              Confirm & Continue
              <.icon name="hero-arrow-right" class="w-4 h-4 ms-1 -mt-0.5" />
            </.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :membership_plan, :atom, required: true
  attr :membership_plans, :list, required: true

  defp step_membership_selection(assigns) do
    ~H"""
    <div>
      <.header class="text-left">
        Choose Your Membership Type
        <:subtitle>
          Please confirm whether you have a single or family membership so we can set up billing correctly.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="membership-selection"
        phx-change="validate_membership_selection"
        phx-submit="confirm_membership_selection"
        class="mt-6"
      >
        <div class="grid w-full gap-4 sm:grid-cols-2">
          <.input
            type="large-radio"
            field={@form[:membership_plan]}
            id="select-membership-single"
            value="single"
            checked={@form[:membership_plan].value == "single"}
            label="Single Membership"
            subtitle="Membership for one person. Access to all YSC events and community resources."
            footer={membership_plan_price_footer(@membership_plans, :single)}
            icon="user"
          />
          <.input
            type="large-radio"
            field={@form[:membership_plan]}
            id="select-membership-family"
            value="family"
            checked={@form[:membership_plan].value == "family"}
            label="Family Membership"
            subtitle="Covers you, your spouse or partner, and children under 18. Includes family member invitations."
            footer={membership_plan_price_footer(@membership_plans, :family)}
            icon="user-group"
          />
        </div>
        <:actions>
          <div class="flex justify-end w-full">
            <.button
              type="submit"
              id="confirm-membership-selection"
              disabled={@membership_plan == :unknown}
            >
              Confirm & Continue
              <.icon name="hero-arrow-right" class="w-4 h-4 ms-1 -mt-0.5" />
            </.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :user, :any, required: true
  attr :phone_code_valid, :boolean, required: true
  attr :sms_resend_disabled_until, :any, required: true

  defp step_phone_verification(assigns) do
    ~H"""
    <div>
      <.header class="text-left">
        Verify Your Phone Number
        <:subtitle>
          We sent a 6-digit code to <strong><%= Ysc.Extensions.PhoneNumber.format_for_display(@user.phone_number) || @user.phone_number %></strong>. Enter it below to verify your number.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="onboarding-phone-form"
        phx-submit="verify_phone"
        phx-change="validate_phone_code"
        class="mt-6"
      >
        <.input
          field={@form[:code]}
          type="otp"
          label="Verification Code"
          required
        />
        <:actions>
          <div class="flex items-center justify-between w-full">
            <.button
              type="button"
              variant="outline"
              color="zinc"
              phx-click="resend_phone_code"
              phx-disable-with="Sending..."
              disabled={not is_nil(@sms_resend_disabled_until)}
            >
              Resend code
            </.button>
            <.button
              type="submit"
              phx-disable-with="Verifying..."
              disabled={not @phone_code_valid}
            >
              <.icon name="hero-check-circle" class="w-4 h-4 me-1" /> Verify Phone
            </.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  attr :user, :any, required: true
  attr :membership_plan, :atom, required: true
  attr :has_real_subscription, :boolean, required: true
  attr :active_subscription, :any, required: true
  attr :public_key, :string, required: true
  attr :payment_intent_secret, :any, required: true
  attr :payment_method_saved, :boolean, required: true
  attr :default_payment_method, :any, required: true

  defp step_payment(assigns) do
    ~H"""
    <div>
      <%= if @has_real_subscription do %>
        <%!-- User has an active subscription: show details and optionally collect PM --%>
        <.header class="text-left">
          Your Membership
          <:subtitle>
            Your membership is active. Review the details below and make sure a payment method is on file for auto-renewal.
          </:subtitle>
        </.header>

        <div class="mt-6 border border-zinc-200 rounded-lg divide-y divide-zinc-100">
          <div class="flex items-center justify-between px-4 py-3">
            <span class="text-sm text-zinc-500">Plan</span>
            <span class="text-sm font-medium text-zinc-900">
              {plan_name(@membership_plan)}
            </span>
          </div>
          <div class="flex items-center justify-between px-4 py-3">
            <span class="text-sm text-zinc-500">Status</span>
            <span class="inline-flex items-center gap-1.5 text-sm font-medium text-green-700">
              <.icon name="hero-check-circle" class="w-4 h-4" /> Active
            </span>
          </div>
          <div class="flex items-center justify-between px-4 py-3">
            <span class="text-sm text-zinc-500">Next Renewal</span>
            <span class="text-sm font-medium text-zinc-900">
              {format_renewal_date(
                @active_subscription && @active_subscription.current_period_end
              )}
            </span>
          </div>
        </div>

        <p class="mt-3 text-xs text-zinc-400">
          If anything looks incorrect, please contact <.link
            href="mailto:info@ysc.org"
            class="text-blue-600 hover:underline"
          >
            info@ysc.org
          </.link>.
        </p>

        <%= if @payment_method_saved || not is_nil(@default_payment_method) do %>
          <div class="mt-6 p-4 bg-green-50 border border-green-200 rounded-lg flex items-center gap-3 text-green-800">
            <.icon name="hero-check-circle" class="w-5 h-5 shrink-0" />
            <div class="text-sm">
              <span class="font-medium">Payment method on file:</span>
              {payment_method_display(@default_payment_method)}
            </div>
          </div>
          <div class="mt-6 flex justify-end">
            <.button
              phx-click="confirm_payment_step"
              phx-disable-with="Continuing..."
            >
              Continue <.icon name="hero-arrow-right" class="w-4 h-4 ms-1" />
            </.button>
          </div>
        <% else %>
          <div class="mt-6 p-4 bg-amber-50 border border-amber-200 rounded-lg flex items-start gap-3 text-amber-800 text-sm">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 mt-0.5 shrink-0" />
            <span>
              No payment method on file. Please add one to ensure your membership auto-renews on the next billing date.
            </span>
          </div>
          <%= if is_nil(@payment_intent_secret) do %>
            <div class="mt-6 flex justify-end">
              <.button phx-click="load_payment_form" phx-disable-with="Loading...">
                <.icon name="hero-credit-card" class="w-4 h-4 me-1" />
                Add Payment Method
              </.button>
            </div>
          <% else %>
            <form
              id="onboarding-payment-form"
              class="mt-6 flex flex-col space-y-4"
              phx-hook="StripeInput"
              data-clientSecret={@payment_intent_secret}
              data-publicKey={@public_key}
              data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
            >
              <div id="onboarding-payment-errors">
                <p id="card-errors" class="text-red-400 text-sm"></p>
              </div>
              <div id="payment-element"></div>
              <div class="flex justify-end mt-4">
                <.button type="submit" id="submit" phx-disable-with="Saving...">
                  <.icon name="hero-lock-closed" class="w-4 h-4 me-1" />
                  Save Payment Method
                </.button>
              </div>
            </form>
          <% end %>
        <% end %>
      <% else %>
        <%!-- No active subscription: offer to set one up, with a skip option --%>
        <.header class="text-left">
          Set Up Renewal Payment
          <:subtitle>
            Add a card or bank account so your membership can renew automatically each year. You won't be charged today unless your renewal date has passed. You can skip for now and add a payment method later in account settings.
          </:subtitle>
        </.header>

        <div class="mt-4 p-4 bg-blue-50 rounded-lg border border-blue-200 text-sm text-blue-800">
          <div class="flex items-start gap-3">
            <.icon name="hero-information-circle" class="w-5 h-5 mt-0.5 shrink-0" />
            <div>
              <strong>Plan: {plan_name(@membership_plan)}</strong>
              <br />
              You'll be billed annually. You can cancel at any time from your account settings.
            </div>
          </div>
        </div>

        <%= if @payment_method_saved || not is_nil(@default_payment_method) do %>
          <div class="mt-6 p-4 bg-green-50 border border-green-200 rounded-lg flex items-center gap-3 text-green-800">
            <.icon name="hero-check-circle" class="w-5 h-5 shrink-0" />
            <span class="text-sm font-medium">
              Payment method saved. You're all set for automatic renewal.
            </span>
          </div>
          <p class="mt-2 text-sm text-zinc-600">
            You won't be charged today unless your renewal date has already passed.
          </p>
          <div class="mt-6 flex items-center justify-between">
            <.button
              type="button"
              variant="outline"
              color="zinc"
              phx-click="skip_payment_step"
              phx-disable-with="Skipping..."
            >
              Skip for now
            </.button>
            <.button
              phx-click="confirm_payment_step"
              phx-disable-with="Saving..."
            >
              Save and continue
              <.icon name="hero-arrow-right" class="w-4 h-4 ms-1" />
            </.button>
          </div>
        <% else %>
          <%= if is_nil(@payment_intent_secret) do %>
            <div class="mt-6 flex items-center justify-between">
              <.button
                type="button"
                variant="outline"
                color="zinc"
                phx-click="skip_payment_step"
                phx-disable-with="Skipping..."
              >
                Skip for now
              </.button>
              <.button phx-click="load_payment_form" phx-disable-with="Loading...">
                <.icon name="hero-credit-card" class="w-4 h-4 me-1" />
                Add Payment Method
              </.button>
            </div>
          <% else %>
            <form
              id="onboarding-payment-form"
              class="mt-6 flex flex-col space-y-4"
              phx-hook="StripeInput"
              data-clientSecret={@payment_intent_secret}
              data-publicKey={@public_key}
              data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
            >
              <div id="onboarding-payment-errors">
                <p id="card-errors" class="text-red-400 text-sm"></p>
              </div>
              <div id="payment-element"></div>
              <div class="mt-4 flex items-center justify-between">
                <.button
                  type="button"
                  variant="outline"
                  color="zinc"
                  phx-click="skip_payment_step"
                  phx-disable-with="Skipping..."
                >
                  Skip for now
                </.button>
                <.button type="submit" id="submit" phx-disable-with="Saving...">
                  <.icon name="hero-lock-closed" class="w-4 h-4 me-1" />
                  Save payment method
                </.button>
              </div>
            </form>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :user, :any, required: true
  attr :family_members_forms, :list, required: true
  attr :invite_results, :list, required: true

  defp step_family(assigns) do
    ~H"""
    <div>
      <.header class="text-left">
        Add Family Members
        <:subtitle>
          Family memberships must include at least one other person (spouse, partner, or child under 18). Add everyone who should be on your membership now. We'll save their details when you continue, and email an invite to anyone you add an email for.
        </:subtitle>
      </.header>

      <%!-- Existing invite results --%>
      <%= for result <- @invite_results do %>
        <div class={[
          "mt-2 p-3 rounded-lg text-sm flex items-center gap-2",
          if(result.ok,
            do: "bg-green-50 text-green-800 border border-green-200",
            else: "bg-red-50 text-red-800 border border-red-200"
          )
        ]}>
          <.icon
            name={if result.ok, do: "hero-check-circle", else: "hero-x-circle"}
            class="w-4 h-4 shrink-0"
          />
          {result.message}
        </div>
      <% end %>

      <%!-- Family member forms --%>
      <div id="family-member-entries" class="mt-6 space-y-4">
        <%= for {form, idx} <- Enum.with_index(@family_members_forms) do %>
          <div class="p-4 border border-zinc-200 rounded-lg space-y-3">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-semibold text-zinc-700">
                Family Member {idx + 1}
                <span
                  :if={family_member_form_id(form) != ""}
                  class="ms-2 font-normal text-zinc-500"
                >
                  (saved)
                </span>
              </h4>
              <.button
                :if={length(@family_members_forms) > 1}
                type="button"
                variant="outline"
                color="red"
                phx-click="remove_family_member"
                phx-value-index={idx}
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </.button>
            </div>
            <.simple_form
              for={form}
              id={family_member_form_dom_id(idx)}
              phx-change="validate_family_member"
              phx-value-index={idx}
              class="space-y-3"
            >
              <input
                type="hidden"
                name={"family_members[#{idx}][id]"}
                value={family_member_form_id(form)}
              />
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <.input
                  field={form[:first_name]}
                  type="text"
                  label="First Name"
                  required
                />
                <.input
                  field={form[:last_name]}
                  type="text"
                  label="Last Name"
                  required
                />
              </div>
              <.input
                field={form[:email]}
                type="email"
                label="Email Address (optional)"
                placeholder="member@example.com"
              />
              <p class="text-xs text-zinc-500 -mt-2">
                If provided, we'll email them an invite when you continue.
              </p>
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <.input field={form[:birth_date]} type="date" label="Date of Birth" />
                <.input
                  field={form[:relationship]}
                  type="select"
                  label="Relationship"
                  options={[{"Child", "child"}, {"Spouse", "spouse"}]}
                />
              </div>
            </.simple_form>
          </div>
        <% end %>
      </div>

      <div class="mt-4 flex items-center justify-between">
        <.button
          type="button"
          variant="outline"
          color="blue"
          phx-click="add_family_member"
        >
          <.icon name="hero-plus-circle" class="w-4 h-4 me-1" /> Add a family member
        </.button>

        <.button phx-click="complete_family_step" phx-disable-with="Saving...">
          <.icon name="hero-check-circle" class="w-4 h-4 me-1" /> Save & Continue
        </.button>
      </div>
    </div>
    """
  end

  attr :user, :any, required: true

  defp step_complete(assigns) do
    ~H"""
    <div class="text-center py-8">
      <.icon name="hero-check-circle" class="w-16 h-16 text-green-500 mx-auto mb-4" />
      <h2 class="text-2xl font-semibold text-zinc-800 mb-2">You're all set!</h2>
      <p class="text-zinc-500 mb-8">
        Your account is fully up to date. Welcome to the Young Scandinavians Club!
      </p>
      <.link
        navigate={~p"/"}
        class="inline-flex items-center gap-2 phx-submit-loading:opacity-75 rounded py-2 px-3 text-sm font-semibold leading-6 bg-blue-700 hover:bg-blue-800 text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2 transition duration-150 ease-in-out"
      >
        <.icon name="hero-home" class="w-4 h-4" /> Go to Home
      </.link>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Event handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("validate_profile", %{"user" => params}, socket) do
    form =
      socket.assigns.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :profile_form, form)}
  end

  def handle_event("save_profile", %{"user" => params}, socket) do
    user = socket.assigns.user

    case Accounts.update_user_profile(user, params) do
      {:ok, updated_user} ->
        phone_changed =
          updated_user.phone_number != socket.assigns.original_phone

        phone_needs_verification =
          phone_changed or is_nil(updated_user.phone_verified_at)

        socket =
          socket
          |> assign(:user, updated_user)

        if phone_needs_verification and not is_nil(updated_user.phone_number) do
          # Send verification code and go to phone verification step
          phone_code =
            Accounts.generate_and_store_phone_verification_code(updated_user)

          _job =
            Accounts.send_phone_verification_code(
              updated_user,
              phone_code,
              "onboarding_initial"
            )

          YscWeb.Flash.send_toast(
            :info,
            "A verification code was sent to #{updated_user.phone_number}",
            title: "Phone Verification"
          )

          {:noreply, assign(socket, :current_step, @step_phone_verification)}
        else
          # Skip phone verification, proceed to next step
          {:noreply, advance_to_next_step(socket, @step_profile)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("validate_address", %{"address" => params}, socket) do
    user = socket.assigns.user

    form =
      user
      |> Accounts.change_billing_address(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :address_form, form)}
  end

  def handle_event("save_address", %{"address" => params}, socket) do
    user = socket.assigns.user

    case Accounts.update_billing_address(user, params) do
      {:ok, updated_user} ->
        {:noreply,
         advance_to_next_step(
           assign(socket, :user, updated_user),
           @step_address
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :address_form, to_form(changeset))}
    end
  end

  def handle_event(
        "validate_membership_selection",
        %{"membership_selection" => params},
        socket
      ) do
    plan =
      case params["membership_plan"] do
        "family" -> :family
        "single" -> :single
        _ -> :unknown
      end

    form = to_form(params, as: "membership_selection")

    {:noreply,
     socket
     |> assign(:membership_plan, plan)
     |> assign(:membership_selection_form, form)
     |> rebuild_onboarding_steps()}
  end

  def handle_event(
        "confirm_membership_selection",
        %{"membership_selection" => params},
        socket
      ) do
    plan =
      case params["membership_plan"] do
        "family" -> :family
        "single" -> :single
        _ -> :unknown
      end

    if plan == :unknown do
      YscWeb.Flash.send_toast(
        :error,
        "Please select a membership type before continuing.",
        title: "Selection Required"
      )

      {:noreply, socket}
    else
      user = socket.assigns.user

      case persist_membership_plan(user, plan) do
        {:ok, _} ->
          updated_user =
            Accounts.get_user!(user.id, [
              :family_members,
              :registration_form,
              :billing_address,
              subscriptions: :subscription_items
            ])

          needs_plan_selection = false

          # Rebuild steps without the selection step, then advance from address
          # (the step that precedes payment in the rebuilt list).
          socket =
            socket
            |> assign(:user, updated_user)
            |> assign(:membership_plan, plan)
            |> assign(:needs_plan_selection, needs_plan_selection)
            |> rebuild_onboarding_steps()

          {:noreply, advance_to_next_step(socket, @step_address)}

        {:error, reason} ->
          Ysc.Logging.error(
            "Failed to persist membership plan during onboarding",
            user_id: user.id,
            plan: plan,
            reason: inspect(reason)
          )

          YscWeb.Flash.send_toast(
            :error,
            "We couldn't save your membership selection. Please try again, or email info@ysc.org if this keeps happening.",
            title: "Error"
          )

          {:noreply, socket}
      end
    end
  end

  def handle_event("validate_phone_code", params, socket) do
    raw = get_in(params, ["phone_code", "code"]) || ""

    # OTP input fires phx-input on each keystroke, sending only the changed digit as
    # an indexed map. Merge with accumulated state so all digits are available.
    current_state = socket.assigns.phone_verification_code_state || %{}

    merged =
      if is_map(raw) do
        Map.merge(if(is_map(current_state), do: current_state, else: %{}), raw)
      else
        raw
      end

    normalized = normalize_verification_code(merged)

    valid =
      String.length(normalized) == 6 && String.match?(normalized, ~r/^\d{6}$/)

    {:noreply,
     socket
     |> assign(:phone_code_valid, valid)
     |> assign(:phone_verification_code_state, merged)}
  end

  def handle_event("verify_phone", params, socket) do
    raw = get_in(params, ["phone_code", "code"]) || ""
    code = normalize_verification_code(raw)
    user = socket.assigns.user

    case Accounts.verify_phone_verification_code(user, code) do
      {:ok, :verified} ->
        case Accounts.mark_phone_verified(user) do
          {:ok, updated_user} ->
            {:noreply,
             socket
             |> assign(:user, updated_user)
             |> advance_to_next_step(@step_phone_verification)}

          {:error, _} ->
            YscWeb.Flash.send_toast(
              :error,
              "We couldn't save your phone verification. Please try again, or email info@ysc.org if this keeps happening.",
              title: "Error"
            )

            {:noreply, socket}
        end

      {:error, :invalid_code} ->
        YscWeb.Flash.send_toast(
          :error,
          "That code is incorrect. Please try again.",
          title: "Invalid Code"
        )

        {:noreply, socket}

      {:error, :expired} ->
        YscWeb.Flash.send_toast(
          :error,
          "Your code has expired. Please request a new one.",
          title: "Expired Code"
        )

        {:noreply, socket}

      {:error, _} ->
        YscWeb.Flash.send_toast(
          :error,
          "We couldn't verify your code. Please try again, or email info@ysc.org if this keeps happening.",
          title: "Error"
        )

        {:noreply, socket}
    end
  end

  def handle_event("resend_phone_code", _params, socket) do
    user = socket.assigns.user

    case Ysc.ResendRateLimiter.check_and_record_resend(user.id, :sms) do
      {:ok, :allowed} ->
        {code, is_existing} =
          case Ysc.VerificationCache.get_code(user.id, :phone_verification) do
            {:ok, existing_code} ->
              {existing_code, true}

            {:error, _} ->
              {Accounts.generate_and_store_phone_verification_code(user), false}
          end

        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        suffix =
          if is_existing,
            do: "resend_existing_#{timestamp}",
            else: "resend_new_#{timestamp}"

        _job = Accounts.send_phone_verification_code(user, code, suffix)

        YscWeb.Flash.send_toast(
          :info,
          "A new code was sent to #{user.phone_number}",
          title: "Code Sent"
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

  def handle_event("load_payment_form", _params, socket) do
    user = socket.assigns.user

    case Customers.create_setup_intent(user,
           stripe: %{payment_method_types: ["card", "us_bank_account"]}
         ) do
      {:ok, setup_intent} ->
        {:noreply,
         assign(socket, :payment_intent_secret, setup_intent.client_secret)}

      {:error, error} ->
        Ysc.Logging.error("Failed to create setup intent during onboarding",
          user_id: user.id,
          error: inspect(error)
        )

        YscWeb.Flash.send_toast(
          :error,
          "We couldn't load the payment form. Please try again in a few minutes, or email memberships@ysc.org and we'll help you add a card.",
          title: "Payment Error"
        )

        {:noreply, socket}
    end
  end

  def handle_event(
        "payment-method-set",
        %{"payment_method_id" => payment_method_id},
        socket
      ) do
    user = socket.assigns.user

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           @payment_method_module.retrieve(payment_method_id)
         end) do
      {:ok, stripe_payment_method} ->
        _ =
          Ysc.Stripe.RetryHelper.stripe_retry(fn ->
            @payment_method_module.update(payment_method_id, %{
              metadata: %{"set_as_default" => "true"}
            })
          end)

        case Ysc.Payments.upsert_and_set_default_payment_method_from_stripe(
               user,
               stripe_payment_method
             ) do
          {:ok, _} ->
            updated_user =
              Accounts.get_user!(user.id, [
                :family_members,
                :registration_form,
                :billing_address,
                subscriptions: :subscription_items
              ])

            default_pm = Ysc.Payments.get_default_payment_method(updated_user)

            if updated_user.stripe_id do
              case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                     @customer_module.update(
                       updated_user.stripe_id,
                       %{
                         invoice_settings: %{
                           default_payment_method: payment_method_id
                         }
                       },
                       []
                     )
                   end) do
                {:ok, _} ->
                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
                   |> assign(:payment_method_saved, true)
                   |> assign(:default_payment_method, default_pm)}

                {:error, err} ->
                  Ysc.Logging.error(
                    "Failed to set default payment method in Stripe during onboarding",
                    user_id: updated_user.id,
                    error: inspect(err)
                  )

                  YscWeb.Flash.send_toast(
                    :error,
                    "Your payment method was saved, but we could not set it as your default for renewals. Please try again or contact info@ysc.org.",
                    title: "Payment"
                  )

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
                   |> assign(:payment_method_saved, true)
                   |> assign(:default_payment_method, default_pm)}
              end
            else
              {:noreply,
               socket
               |> assign(:user, updated_user)
               |> assign(:payment_method_saved, true)
               |> assign(:default_payment_method, default_pm)}
            end

          {:error, _} ->
            YscWeb.Flash.send_toast(
              :error,
              "We couldn't save your payment method. Please try again, or email memberships@ysc.org if this keeps happening.",
              title: "Payment"
            )

            {:noreply, socket}
        end

      {:error, _} ->
        YscWeb.Flash.send_toast(
          :error,
          "We couldn't confirm your payment method. Please try again, or email memberships@ysc.org if this keeps happening.",
          title: "Payment"
        )

        {:noreply, socket}
    end
  end

  def handle_event("confirm_payment_step", _params, socket) do
    user = socket.assigns.user
    default_pm = socket.assigns.default_payment_method

    cond do
      socket.assigns.has_real_subscription ->
        # Already subscribed — just advance without touching Stripe subscriptions.
        {:noreply,
         socket
         |> sync_onboarding_plan_from_user()
         |> advance_to_next_step(@step_payment)}

      is_nil(default_pm) ->
        YscWeb.Flash.send_toast(
          :error,
          "Please add a payment method before continuing.",
          title: "Payment Required"
        )

        {:noreply, socket}

      true ->
        case create_stripe_subscription(
               user,
               socket.assigns.membership_plan,
               default_pm
             ) do
          {:ok, _subscription} ->
            {:noreply,
             socket
             |> sync_onboarding_plan_from_user()
             |> advance_to_next_step(@step_payment)}

          {:error, :user_already_has_active_subscription} ->
            Ysc.Logging.error(
              "User already has active subscription during onboarding",
              user_id: user.id
            )

            YscWeb.Flash.send_toast(
              :error,
              "Your membership renewal is already set up. Click Continue at the bottom of this page to finish updating your profile.",
              title: "Membership renewal"
            )

            {:noreply, socket}

          {:error, reason} ->
            Ysc.Logging.error("Failed to create subscription during onboarding",
              user_id: user.id,
              reason: inspect(reason)
            )

            YscWeb.Flash.send_toast(
              :error,
              "We couldn't turn on automatic renewal. Your payment method was saved — please try again, or email info@ysc.org for help.",
              title: "Payment setup"
            )

            {:noreply, socket}
        end
    end
  end

  def handle_event("skip_payment_step", _params, socket) do
    {:noreply, advance_to_next_step(socket, @step_payment)}
  end

  def handle_event("set-step", %{"step" => step_str}, socket) do
    steps = socket.assigns.steps

    case Integer.parse(step_str) do
      {index, ""} when index >= 0 and index < length(steps) ->
        {_label, step_num} = Enum.fetch!(steps, index)

        socket =
          socket
          |> assign(:current_step, step_num)
          |> ensure_family_members_forms()

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_family_member", _params, socket) do
    params_list =
      socket.assigns.family_members_forms
      |> Enum.map(&family_member_params_from_form/1)
      |> Kernel.++([family_member_form_params()])

    {:noreply,
     assign(
       socket,
       :family_members_forms,
       reindex_family_member_forms(params_list)
     )}
  end

  def handle_event("remove_family_member", %{"index" => idx_str}, socket) do
    if length(socket.assigns.family_members_forms) <= 1 do
      {:noreply, socket}
    else
      idx = String.to_integer(idx_str)
      form = Enum.at(socket.assigns.family_members_forms, idx)
      member_params = family_member_params_from_form(form)

      socket =
        socket
        |> delete_family_member_if_saved(member_params["id"])
        |> reload_user_family_members()

      params_list =
        socket.assigns.family_members_forms
        |> Enum.map(&family_member_params_from_form/1)
        |> List.delete_at(idx)

      {:noreply,
       assign(
         socket,
         :family_members_forms,
         reindex_family_member_forms(params_list)
       )}
    end
  end

  def handle_event("validate_family_member", params, socket) do
    idx = String.to_integer(params["index"] || "0")
    member_params = family_member_params_from_event(params, idx)

    member_params =
      merge_family_member_form_params(
        member_params,
        socket.assigns.family_members_forms,
        idx
      )

    form = indexed_family_member_form(member_params, idx)

    updated_forms =
      List.replace_at(socket.assigns.family_members_forms, idx, form)

    {:noreply, assign(socket, :family_members_forms, updated_forms)}
  end

  def handle_event("complete_family_step", _params, socket) do
    if socket.assigns.needs_family_members_step do
      complete_family_step_with_members(socket)
    else
      {:noreply, finalize_onboarding(socket)}
    end
  end

  defp complete_family_step_with_members(socket) do
    user = socket.assigns.user
    forms = socket.assigns.family_members_forms

    case process_family_step(user, forms) do
      {:ok, validated_forms, results} ->
        socket =
          socket
          |> assign(:family_members_forms, validated_forms)
          |> assign(:invite_results, socket.assigns.invite_results ++ results)
          |> reload_user_family_members()
          |> flash_family_invite_results(results)

        {:noreply, finalize_onboarding(socket)}

      {:error, :no_members} ->
        YscWeb.Flash.send_toast(
          :error,
          "Please add at least one family member (spouse, partner, or child) before continuing, or contact info@ysc.org if you need help.",
          title: "Family Members Required"
        )

        {:noreply, socket}

      {:error, :validation_failed, updated_forms} ->
        YscWeb.Flash.send_toast(
          :error,
          "Please fix the errors below before continuing.",
          title: "Check Family Member Details"
        )

        {:noreply, assign(socket, :family_members_forms, updated_forms)}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns the 0-based index of the current step in the steps list (for the stepper component)
  defp step_index(current_step, steps) do
    case Enum.find_index(steps, fn {_label, step_num} ->
           step_num == current_step
         end) do
      nil -> 0
      idx -> idx
    end
  end

  defp needs_family_members_step?(plan), do: plan == :family

  defp build_steps(
         needs_family_members_step,
         skip_payment,
         needs_plan_selection
       ) do
    base = [
      {"Profile", @step_profile},
      {"Address", @step_address}
    ]

    base =
      if needs_plan_selection,
        do: base ++ [{"Membership Type", @step_membership_selection}],
        else: base

    base =
      if skip_payment,
        do: base,
        else: base ++ [{"Renewal Payment", @step_payment}]

    if needs_family_members_step,
      do: base ++ [{"Family", @step_family}],
      else: base
  end

  defp rebuild_onboarding_steps(socket) do
    needs_family_members_step =
      needs_family_members_step?(socket.assigns.membership_plan)

    steps =
      build_steps(
        needs_family_members_step,
        socket.assigns.skip_payment,
        socket.assigns.needs_plan_selection
      )

    family_members_forms =
      if needs_family_members_step and socket.assigns.family_members_forms == [] do
        initial_family_members_forms(socket.assigns.user)
      else
        socket.assigns.family_members_forms
      end

    socket
    |> assign(:needs_family_members_step, needs_family_members_step)
    |> assign(:steps, steps)
    |> assign(:family_members_forms, family_members_forms)
  end

  defp sync_onboarding_plan_from_user(socket) do
    user =
      Accounts.get_user!(socket.assigns.user.id, [
        :family_members,
        :registration_form,
        :billing_address,
        subscriptions: :subscription_items
      ])

    membership_plan = resolve_membership_plan(user)
    needs_family_members_step = needs_family_members_step?(membership_plan)
    skip_payment = membership_plan == :lifetime

    steps =
      build_steps(
        needs_family_members_step,
        skip_payment,
        socket.assigns.needs_plan_selection
      )

    socket
    |> assign(:user, user)
    |> assign(:membership_plan, membership_plan)
    |> assign(:needs_family_members_step, needs_family_members_step)
    |> assign(:skip_payment, skip_payment)
    |> assign(:steps, steps)
    |> assign(
      :has_real_subscription,
      not is_nil(find_active_real_subscription(user))
    )
    |> assign(:active_subscription, find_active_real_subscription(user))
  end

  # Advance from the given step to the next applicable step.
  # For phone verification (not in @steps list), treat it as if coming from profile.
  defp advance_to_next_step(socket, current_step) do
    steps = socket.assigns.steps
    step_numbers = Enum.map(steps, fn {_, n} -> n end)
    socket = Phoenix.LiveView.clear_flash(socket)

    # Phone verification is not in the steps list; treat it as if we're after profile
    effective_step =
      if current_step == @step_phone_verification,
        do: @step_profile,
        else: current_step

    current_idx = Enum.find_index(step_numbers, &(&1 == effective_step))

    next_step =
      if current_idx && current_idx + 1 < length(step_numbers) do
        Enum.at(step_numbers, current_idx + 1)
      else
        @step_complete
      end

    next_step = maybe_skip_family_step(socket, next_step)

    cond do
      next_step == @step_payment ->
        socket
        |> assign(:current_step, @step_payment)
        |> load_payment_form_if_needed()

      next_step == @step_complete ->
        finalize_onboarding(socket)

      true ->
        socket
        |> assign(:current_step, next_step)
        |> ensure_family_members_forms()
    end
  end

  defp assign_onboarding_shell(socket, user) do
    socket
    |> assign(:page_title, "Welcome Back — Complete Your Profile")
    |> assign(:user, user)
    |> assign(:current_step, @step_profile)
    |> assign(:steps, [{"Profile", @step_profile}])
    |> assign(:membership_plan, :unknown)
    |> assign(
      :membership_plans,
      Application.get_env(:ysc, :membership_plans, [])
    )
    |> assign(:needs_plan_selection, true)
    |> assign(:needs_family_members_step, false)
    |> assign(:skip_payment, false)
    |> assign(:has_real_subscription, false)
    |> assign(:active_subscription, nil)
    |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
    |> assign(:original_phone, user.phone_number)
    |> assign(:address_form, to_form(Accounts.change_billing_address(user)))
    |> assign(:phone_code_form, to_form(%{"code" => ""}, as: "phone_code"))
    |> assign(:phone_code_valid, false)
    |> assign(:phone_verification_code_state, %{})
    |> assign(:sms_resend_disabled_until, nil)
    |> assign(:public_key, Application.get_env(:stripity_stripe, :public_key))
    |> assign(:payment_intent_secret, nil)
    |> assign(:payment_method_saved, false)
    |> assign(:default_payment_method, nil)
    |> assign(
      :membership_selection_form,
      to_form(%{"membership_plan" => ""}, as: "membership_selection")
    )
    |> assign(:family_members_forms, [])
    |> assign(:invite_results, [])
  end

  defp assign_onboarding_data(socket, user, default_payment_method) do
    membership_plan = resolve_membership_plan(user)
    active_subscription = find_active_real_subscription(user)
    has_real_subscription = not is_nil(active_subscription)
    needs_plan_selection = membership_plan == :unknown
    needs_family_members_step = needs_family_members_step?(membership_plan)
    skip_payment = membership_plan == :lifetime

    steps =
      build_steps(
        needs_family_members_step,
        skip_payment,
        needs_plan_selection
      )

    socket
    |> assign(:user, user)
    |> assign(:steps, steps)
    |> assign(:membership_plan, membership_plan)
    |> assign(:needs_plan_selection, needs_plan_selection)
    |> assign(:needs_family_members_step, needs_family_members_step)
    |> assign(:skip_payment, skip_payment)
    |> assign(:has_real_subscription, has_real_subscription)
    |> assign(:active_subscription, active_subscription)
    |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
    |> assign(:original_phone, user.phone_number)
    |> assign(:address_form, to_form(Accounts.change_billing_address(user)))
    |> assign(:default_payment_method, default_payment_method)
    |> assign(
      :membership_selection_form,
      to_form(
        %{
          "membership_plan" =>
            if(membership_plan == :unknown,
              do: "",
              else: to_string(membership_plan)
            )
        },
        as: "membership_selection"
      )
    )
    |> assign(
      :family_members_forms,
      if(needs_family_members_step,
        do: initial_family_members_forms(user),
        else: []
      )
    )
  end

  defp load_payment_form_if_needed(socket) do
    if is_nil(socket.assigns.payment_intent_secret) and
         is_nil(socket.assigns.default_payment_method) do
      user = socket.assigns.user

      case Customers.create_setup_intent(user,
             stripe: %{payment_method_types: ["card", "us_bank_account"]}
           ) do
        {:ok, setup_intent} ->
          assign(socket, :payment_intent_secret, setup_intent.client_secret)

        {:error, _} ->
          socket
      end
    else
      socket
    end
  end

  defp finalize_onboarding(socket) do
    user = socket.assigns.user

    case Accounts.complete_post_migration_onboarding(user) do
      {:ok, _updated_user} ->
        assign(socket, :current_step, @step_complete)

      {:error, _} ->
        YscWeb.Flash.send_toast(
          :error,
          "We couldn't finish setting up your account. Please try again, or email info@ysc.org and we'll help you complete this.",
          title: "Error"
        )

        socket
    end
  end

  # Dialyzer cannot fully type-check the Stripe client return values, so we suppress
  # warnings for this function. The Customers.create_subscription/2 module has a
  # similar annotation for the same reason.
  @dialyzer {:nowarn_function, create_stripe_subscription: 3}
  # Lifetime members have no Stripe subscription — this is a no-op.
  defp create_stripe_subscription(_user, :lifetime, _default_pm),
    do: {:ok, :lifetime_no_op}

  defp create_stripe_subscription(user, plan, default_pm) do
    price_id = get_price_id(plan)

    if is_nil(price_id) do
      {:error, :no_price_id_for_plan}
    else
      # Stable idempotency key scoped to this user + plan so Stripe deduplicates
      # any duplicate requests within its 24-hour idempotency window.
      idempotency_key = "wp_onboarding_#{user.id}_#{plan}"

      case Customers.create_subscription(
             user,
             return_url:
               "#{YscWeb.Endpoint.url()}/billing/user/#{user.id}/finalize",
             prices: [%{price: price_id, quantity: 1}],
             default_payment_method: default_pm.provider_id,
             expand: ["latest_invoice"],
             idempotency_key: idempotency_key
           ) do
        {:ok, stripe_subscription} ->
          # Delete migrated placeholder subscriptions only after Stripe succeeds
          # to avoid data loss if the Stripe call fails or the process crashes.
          user
          |> Subscriptions.list_subscriptions()
          |> Enum.filter(&migrated_subscription?/1)
          |> Enum.each(&Subscriptions.delete_subscription/1)

          Subscriptions.create_subscription_from_stripe(
            user,
            stripe_subscription
          )

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp migrated_subscription?(%{stripe_id: stripe_id})
       when is_binary(stripe_id) do
    String.starts_with?(stripe_id, "migrated_")
  end

  defp migrated_subscription?(_), do: false

  defp find_active_real_subscription(user) do
    user.subscriptions
    |> Enum.find(fn sub ->
      Subscriptions.active?(sub) and not migrated_subscription?(sub)
    end)
  end

  # Resolve the intended membership plan for a WP-migrated user.
  # Checks (in order): lifetime award, real active sub, migrated sub name, signup application, default single.
  defp resolve_membership_plan(user) do
    # Lifetime membership takes precedence over all subscription-based logic.
    if is_nil(user.lifetime_membership_awarded_at) do
      resolve_membership_plan_from_subscriptions(user)
    else
      :lifetime
    end
  end

  defp resolve_membership_plan_from_subscriptions(user) do
    plans = Application.get_env(:ysc, :membership_plans, [])
    subscriptions = user.subscriptions

    # First: real active subscription
    real_active =
      Enum.find(subscriptions, fn sub ->
        Subscriptions.active?(sub) and not migrated_subscription?(sub)
      end)

    if real_active do
      plan_type_from_subscription(real_active, plans)
    else
      # Second: migrated subscription
      migrated =
        Enum.find(subscriptions, &migrated_subscription?/1)

      if migrated do
        plan_type_from_subscription(migrated, plans)
      else
        # Third: signup application
        plan_from_application(user) || :unknown
      end
    end
  end

  defp plan_type_from_subscription(subscription, plans) do
    items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          Ysc.Repo.preload(subscription, :subscription_items).subscription_items

        items ->
          items
      end

    case items do
      [item | _] ->
        case Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{id: id} -> id
          _ -> :single
        end

      _ ->
        :single
    end
  end

  defp plan_from_application(user) do
    case user.registration_form do
      %{membership_type: mt} when not is_nil(mt) ->
        case to_string(mt) do
          "family" -> :family
          "single" -> :single
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Persists the user-selected membership plan to the SignupApplication record so
  # resolve_membership_plan/1 finds it on any subsequent mount or process restart.
  defp persist_membership_plan(user, plan) do
    membership_type = to_string(plan)

    registration_form =
      case user.registration_form do
        %Ecto.Association.NotLoaded{} ->
          Ysc.Repo.preload(user, :registration_form).registration_form

        form ->
          form
      end

    if is_nil(registration_form) do
      %Ysc.Accounts.SignupApplication{user_id: user.id}
      |> Ysc.Accounts.SignupApplication.migration_changeset(%{
        membership_type: membership_type
      })
      |> Ysc.Repo.insert()
    else
      registration_form
      |> Ysc.Accounts.SignupApplication.migration_changeset(%{
        membership_type: membership_type
      })
      |> Ysc.Repo.update()
    end
  end

  defp initial_family_members_forms(user) do
    members =
      case user.family_members do
        %Ecto.Association.NotLoaded{} -> []
        members when is_list(members) -> members
        _ -> []
      end

    params_list =
      case members do
        [] ->
          [family_member_form_params()]

        members ->
          Enum.map(members, &family_member_params_from_record/1)
      end

    reindex_family_member_forms(params_list)
  end

  defp maybe_skip_family_step(socket, @step_family) do
    if socket.assigns.needs_family_members_step do
      @step_family
    else
      @step_complete
    end
  end

  defp maybe_skip_family_step(_socket, step), do: step

  defp ensure_family_members_forms(socket) do
    if socket.assigns.current_step == @step_family and
         socket.assigns.needs_family_members_step do
      merge_family_members_forms(socket)
    else
      socket
    end
  end

  defp merge_family_members_forms(socket) do
    user = Accounts.get_user!(socket.assigns.user.id, [:family_members])

    unsaved_params =
      socket.assigns.family_members_forms
      |> Enum.map(&family_member_params_from_form/1)
      |> Enum.filter(fn params ->
        id = params["id"]
        id in [nil, ""] and not family_member_params_blank?(params)
      end)

    db_params =
      Enum.map(user.family_members || [], &family_member_params_from_record/1)

    forms =
      case db_params ++ unsaved_params do
        [] -> reindex_family_member_forms([family_member_form_params()])
        params_list -> reindex_family_member_forms(params_list)
      end

    socket
    |> assign(:user, user)
    |> assign(:family_members_forms, forms)
  end

  defp family_member_form_dom_id(idx), do: "family-member-form-#{idx}"

  defp family_member_form_name(idx), do: "family_members[#{idx}]"

  defp indexed_family_member_form(params, idx, opts \\ []) do
    opts =
      Keyword.merge(
        [as: family_member_form_name(idx), id: family_member_form_dom_id(idx)],
        opts
      )

    to_form(family_member_form_params(params), opts)
  end

  defp reindex_family_member_forms(params_list) do
    params_list
    |> Enum.with_index()
    |> Enum.map(fn {params, idx} -> indexed_family_member_form(params, idx) end)
  end

  defp family_member_params_from_form(form) do
    case form.source do
      %Ecto.Changeset{} = changeset ->
        type = Ecto.Changeset.get_field(changeset, :type)

        relationship =
          case type do
            :spouse -> "spouse"
            "spouse" -> "spouse"
            _ -> "child"
          end

        birth_date =
          case Ecto.Changeset.get_field(changeset, :birth_date) do
            %Date{} = date -> Date.to_iso8601(date)
            _ -> changeset.params["birth_date"] || ""
          end

        family_member_form_params(%{
          "id" => family_member_form_id_from_changeset(changeset),
          "first_name" =>
            Ecto.Changeset.get_field(changeset, :first_name) || "",
          "last_name" => Ecto.Changeset.get_field(changeset, :last_name) || "",
          "email" => Ecto.Changeset.get_field(changeset, :email) || "",
          "birth_date" => birth_date,
          "relationship" => relationship
        })

      %{} = params ->
        family_member_form_params(params)

      _ ->
        family_member_form_params()
    end
  end

  defp family_member_params_from_event(params, idx) do
    get_in(params, ["family_members", Integer.to_string(idx)]) || %{}
  end

  defp family_member_form_params(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => "",
        "first_name" => "",
        "last_name" => "",
        "email" => "",
        "birth_date" => "",
        "relationship" => "child"
      },
      attrs
    )
  end

  defp family_member_params_from_record(%FamilyMember{} = member) do
    relationship =
      case member.type do
        :spouse -> "spouse"
        "spouse" -> "spouse"
        _ -> "child"
      end

    birth_date =
      case member.birth_date do
        %Date{} = date -> Date.to_iso8601(date)
        _ -> ""
      end

    family_member_form_params(%{
      "id" => to_string(member.id),
      "first_name" => member.first_name || "",
      "last_name" => member.last_name || "",
      "birth_date" => birth_date,
      "relationship" => relationship
    })
  end

  defp family_member_form_id(form) do
    case form[:id] do
      %{value: value} when is_binary(value) and value != "" ->
        value

      _ ->
        case form.source do
          %Ecto.Changeset{} = changeset ->
            family_member_form_id_from_changeset(changeset)

          %{} = params ->
            params["id"] || ""

          _ ->
            ""
        end
    end
  end

  defp family_member_form_id_from_changeset(changeset) do
    case Ecto.Changeset.get_field(changeset, :id) do
      nil -> changeset.params["id"] || ""
      id -> to_string(id)
    end
  end

  defp merge_family_member_form_params(member_params, forms, idx) do
    existing =
      forms
      |> Enum.at(idx)
      |> case do
        %{source: source} when is_map(source) -> source
        _ -> %{}
      end

    id = member_params["id"] || existing["id"] || ""

    Map.merge(existing, member_params, fn _key, _existing, new -> new end)
    |> Map.put("id", id)
  end

  defp process_family_step(user, forms) do
    params_list = Enum.map(forms, &(&1.source || %{}))

    filled =
      Enum.reject(params_list, &family_member_params_blank?/1)

    if filled == [] do
      {:error, :no_members}
    else
      case validate_all_family_members(user, params_list) do
        {:error, updated_forms} ->
          {:error, :validation_failed, updated_forms}

        {:ok, validated_params} ->
          kept_ids =
            validated_params
            |> Enum.map(& &1["id"])
            |> Enum.reject(&(&1 in [nil, ""]))
            |> MapSet.new()

          FamilyMembers.delete_removed_members(user, kept_ids)

          {save_results, invite_results, save_ok?} =
            Enum.reduce(validated_params, {[], [], true}, fn params,
                                                             {results, invites,
                                                              ok} ->
              case FamilyMembers.upsert_family_member(user, params) do
                {:ok, family_member} ->
                  invite = maybe_send_family_invite(user, params, family_member)

                  saved_params =
                    family_member_form_params_from_record(family_member, params)

                  {
                    [{:ok, saved_params} | results],
                    if(invite, do: [invite | invites], else: invites),
                    ok
                  }

                {:error, _changeset} ->
                  {[{:error, params} | results], invites, false}
              end
            end)

          updated_forms =
            if save_ok? do
              save_results
              |> Enum.reverse()
              |> Enum.map(fn {:ok, params} -> params end)
              |> reindex_family_member_forms()
            else
              save_results
              |> Enum.reverse()
              |> Enum.with_index()
              |> Enum.map(fn
                {{:ok, params}, idx} ->
                  indexed_family_member_form(params, idx)

                {{:error, params}, idx} ->
                  family_member_form_with_errors(user, params, idx)
              end)
            end

          invite_results = Enum.reverse(invite_results)

          if save_ok? do
            {:ok, updated_forms, invite_results}
          else
            {:error, :validation_failed, updated_forms}
          end
      end
    end
  end

  defp validate_all_family_members(user, params_list) do
    {forms, filled, valid?} =
      Enum.reduce(Enum.with_index(params_list), {[], [], true}, fn {params, idx},
                                                                   {forms,
                                                                    filled,
                                                                    valid} ->
        cond do
          family_member_params_blank?(params) ->
            {[indexed_family_member_form(params, idx) | forms], filled, valid}

          true ->
            case validate_family_member_params(user, params) do
              {:ok, _} ->
                {[indexed_family_member_form(params, idx) | forms],
                 [params | filled], valid}

              {:error, _} ->
                {[family_member_form_with_errors(user, params, idx) | forms],
                 filled, false}
            end
        end
      end)

    forms = Enum.reverse(forms)

    if valid? do
      {:ok, Enum.reverse(filled)}
    else
      {:error, forms}
    end
  end

  defp family_member_params_blank?(params) do
    Enum.all?(
      ["first_name", "last_name", "email", "birth_date"],
      fn field -> String.trim(params[field] || "") == "" end
    )
  end

  defp validate_family_member_params(user, params) do
    FamilyMembers.validate_params(user, params)
  end

  defp family_member_form_with_errors(user, params, idx) do
    changeset =
      user
      |> FamilyMembers.changeset_for_params(params)
      |> Map.put(:action, :validate)

    to_form(changeset,
      as: family_member_form_name(idx),
      id: family_member_form_dom_id(idx)
    )
  end

  defp family_member_form_params_from_record(%FamilyMember{} = member, params) do
    relationship =
      case member.type do
        :spouse -> "spouse"
        "spouse" -> "spouse"
        _ -> "child"
      end

    birth_date =
      case member.birth_date do
        %Date{} = date -> Date.to_iso8601(date)
        _ -> params["birth_date"] || ""
      end

    family_member_form_params(%{
      "id" => to_string(member.id),
      "first_name" => member.first_name || "",
      "last_name" => member.last_name || "",
      "email" => params["email"] || "",
      "birth_date" => birth_date,
      "relationship" => relationship
    })
  end

  defp delete_family_member_if_saved(socket, id) when id in [nil, ""],
    do: socket

  defp delete_family_member_if_saved(socket, id) do
    user = socket.assigns.user

    case FamilyMembers.find_by_id(user, id) do
      %FamilyMember{} = member ->
        case Ysc.Repo.delete(member) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Ysc.Logging.warning(
              "Failed to delete family member during onboarding",
              user_id: user.id,
              family_member_id: id,
              reason: inspect(reason)
            )

            socket
        end

      _ ->
        socket
    end
  end

  defp family_member_display_name(params) do
    first = String.trim(params["first_name"] || "")
    last = String.trim(params["last_name"] || "")
    String.trim("#{first} #{last}")
  end

  defp maybe_send_family_invite(user, params, family_member) do
    email = String.trim(params["email"] || "")

    if email == "" do
      nil
    else
      relationship =
        case params["relationship"] do
          "spouse" -> :spouse
          _ -> :child
        end

      name = family_member_display_name(params)

      case FamilyInvites.create_invite(user, email,
             relationship: relationship,
             family_member_id: family_member.id
           ) do
        {:ok, _invite} ->
          %{ok: true, message: "Invite sent to #{email} (#{name})"}

        {:error, :pending_invite_exists} ->
          %{
            ok: true,
            message: "An invite was already sent to #{email} (#{name})"
          }

        {:error, :email_already_registered} ->
          %{
            ok: false,
            message:
              "#{email} (#{name}) already has an account. They can be linked in Family Settings."
          }

        {:error, :max_sub_accounts_reached} ->
          %{ok: false, message: "Maximum number of family members reached."}

        {:error, :max_spouses_reached} ->
          %{
            ok: false,
            message:
              "You can only have one spouse or partner on the family membership."
          }

        {:error, :invalid_membership_type} ->
          %{
            ok: false,
            message: "Your membership plan doesn't support family invites."
          }

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          Ysc.Logging.warning(
            "Family invite failed during onboarding (validation)",
            user_id: user.id,
            email: email
          )

          %{ok: false, message: "Could not send invite to #{email} (#{name})."}

        {:error, reason} ->
          Ysc.Logging.warning(
            "Family invite failed during onboarding",
            user_id: user.id,
            email: email,
            reason: inspect(reason)
          )

          %{
            ok: false,
            message:
              "Could not send invite to #{email} (#{name}). Please try again from Family Settings."
          }
      end
    end
  end

  defp reload_user_family_members(socket) do
    user = Accounts.get_user!(socket.assigns.user.id, [:family_members])
    assign(socket, :user, user)
  end

  defp flash_family_invite_results(socket, []), do: socket

  defp flash_family_invite_results(socket, results) do
    sent = Enum.count(results, & &1.ok)
    failed = length(results) - sent

    message =
      cond do
        sent > 0 and failed > 0 ->
          "Saved your family members. Sent #{sent} invite(s); #{failed} could not be sent — you can retry from Family Settings."

        sent > 0 ->
          "Saved your family members and sent #{sent} invite(s)."

        failed > 0 ->
          "Saved your family members, but #{failed} invite(s) could not be sent — you can retry from Family Settings."

        true ->
          nil
      end

    if message do
      kind = if failed > 0, do: :warning, else: :info

      YscWeb.Flash.send_toast(
        kind,
        message,
        title:
          if(failed > 0, do: "Invites Partially Sent", else: "Invites Sent")
      )
    end

    socket
  end

  defp get_price_id(plan_id) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.id == plan_id)) do
      %{stripe_price_id: price_id} -> price_id
      _ -> nil
    end
  end

  # Normalise an OTP verification code from whichever format the OTP input
  # delivers it: indexed-key map (%{"0" => "1", "1" => "2", ...}), list, or
  # plain string.  Non-integer map keys (e.g. "_unused_1") are ignored.
  defp normalize_verification_code(code) when is_map(code) do
    code
    |> Enum.filter(fn {k, _v} ->
      case Integer.parse(k) do
        {_int, ""} -> true
        _ -> false
      end
    end)
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, v} -> v end)
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_list(code) do
    code |> Enum.reject(&(&1 == "" || is_nil(&1))) |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_binary(code), do: code
  defp normalize_verification_code(_), do: ""

  defp plan_name(:family), do: "Family Membership"
  defp plan_name(:single), do: "Single Membership"
  defp plan_name(:lifetime), do: "Lifetime Membership"
  defp plan_name(_), do: "Membership"

  defp format_renewal_date(nil), do: "—"

  defp format_renewal_date(%DateTime{} = dt) do
    months =
      ~w[January February March April May June July August September October November December]

    "#{Enum.at(months, dt.month - 1)} #{dt.day}, #{dt.year}"
  end

  defp payment_method_display(nil), do: "—"

  defp payment_method_display(%{display_brand: brand, last_four: last4})
       when is_binary(brand) and is_binary(last4) do
    "#{String.capitalize(brand)} ···· #{last4}"
  end

  defp payment_method_display(%{last_four: last4}) when is_binary(last4) do
    "Card ···· #{last4}"
  end

  defp payment_method_display(_), do: "Card on file"

  defp nordic_country_options do
    [
      {"Denmark", "DK"},
      {"Finland", "FI"},
      {"Iceland", "IS"},
      {"Norway", "NO"},
      {"Sweden", "SE"},
      {"Other", "other"}
    ]
  end

  defp membership_plan_price_footer(plans, plan_id) do
    case Enum.find(plans, &(&1.id == plan_id)) do
      %{amount: amount} ->
        "#{Ysc.MoneyHelper.format_money!(Money.new(:USD, amount))} per year"

      _ ->
        nil
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end
end
