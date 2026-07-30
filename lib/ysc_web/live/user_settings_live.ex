defmodule YscWeb.UserSettingsLive do
  use YscWeb, :live_view
  require Ysc.Logging

  import YscWeb.Live.AsyncHelpers

  @phone_verification_token_salt "phone_verification"
  @phone_verification_token_max_age 3600

  @email_verification_token_salt "email_verification_pending"
  # 30 minutes — long enough to complete the verification step
  @email_verification_token_max_age 1800

  alias Ysc.Accounts
  alias Ysc.Accounts.VerificationCodes
  alias Ysc.Accounts.{Address, FamilyInvites, MembershipCache}
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Avatars
  alias Ysc.Bookings.Entitlements
  alias Ysc.Customers
  alias Ysc.Events
  alias Ysc.GoogleWallet
  alias Ysc.Ledgers
  alias Ysc.Newsletter
  alias Ysc.Repo
  alias Ysc.Subscriptions
  alias Ysc.Payments.PaymentDisplay
  alias Ysc.Tickets.Display, as: TicketDisplay
  alias YscWeb.BookingDisplay

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="max-w-screen-xl px-4 mx-auto py-8 lg:py-10"
      id="user-settings-page"
      phx-hook="ConfirmCloseModal"
    >
      <div class="md:flex md:flex-row md:flex-auto md:grow container mx-auto">
        <.modal
          :if={@live_action == :phone_verification}
          id="phone-verification-modal"
          on_cancel={JS.push("confirm_cancel_phone_verification")}
          show
        >
          <.modal_title id="phone-verification-modal-title">
            Verify Your Phone Number
          </.modal_title>

          <.simple_form
            for={@phone_verification_form}
            id="phone_verification_form"
            phx-submit="verify_phone_code"
            phx-change="validate_phone_code"
            phx-hook="ResendTimer"
          >
            <.form_notice kind={:info} id="phone-verification-keep-open-notice">
              <strong>Keep this window open</strong>
              while you check your text messages for the verification code.
            </.form_notice>

            <p class="text-base text-zinc-600 mb-4">
              We sent a verification code via text message to <strong><%= Ysc.Extensions.PhoneNumber.format_for_display(@pending_phone_number) || @pending_phone_number %></strong>.
              Please enter it below to confirm your phone number.
            </p>

            <.form_notice
              :if={@phone_verification_error}
              kind={:error}
              id="phone-verification-error-notice"
            >
              {@phone_verification_error}
            </.form_notice>

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
                  phx-disable-with="Sending..."
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  Resend the code
                </.link>
              <% else %>
                <% sms_countdown = sms_resend_seconds_remaining(assigns) %>
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
        </.modal>

        <.modal
          :if={@live_action == :email_verification}
          id="email-verification-modal"
          on_cancel={JS.push("confirm_cancel_email_verification")}
          show
        >
          <.modal_title id="email-verification-modal-title">
            Verify Your New Email Address
          </.modal_title>

          <.simple_form
            for={@email_verification_form}
            id="email_verification_form"
            phx-submit="verify_email_code"
            phx-change="validate_email_code"
            phx-hook="ResendTimer"
          >
            <.form_notice kind={:info} id="email-verification-keep-open-notice">
              <strong>Keep this window open</strong>
              while you check your email for the verification code.
            </.form_notice>

            <p class="text-base text-zinc-600 mb-4">
              We sent a verification code to <strong><%= @pending_email %></strong>.
              Please enter it below to confirm your new email address.
            </p>

            <.form_notice
              :if={@email_verification_error}
              kind={:error}
              id="email-verification-error-notice"
            >
              {@email_verification_error}
            </.form_notice>
            <.input
              field={@email_verification_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your email.
              <%= if email_resend_available?(assigns) do %>
                <.link
                  phx-click="resend_email_code"
                  phx-disable-with="Sending..."
                  class="text-blue-600 hover:underline cursor-pointer"
                >
                  Resend the code
                </.link>
              <% else %>
                <% email_countdown = email_resend_seconds_remaining(assigns) %>
                <span
                  class="text-zinc-500 cursor-not-allowed font-bold"
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
                  disabled={!@email_code_valid}
                  class={
                    if !@email_code_valid,
                      do: "opacity-50 cursor-not-allowed",
                      else: ""
                  }
                >
                  <.icon name="hero-check-circle" class="w-5 h-5" />Verify Email Address
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </.modal>

        <.live_component
          :if={@show_reauth_modal}
          module={YscWeb.ReauthComponent}
          id="reauth"
          user={@current_user}
          user_has_password={@user_has_password}
          return_to={@request_path}
          description={reauth_modal_description(@reauth_purpose)}
          reauth_intent={reauth_intent_from_assigns(assigns)}
        />

        <.modal
          :if={@live_action == :payment_method}
          id="update-payment-method-modal"
          on_cancel={JS.patch(~p"/users/membership")}
          show
        >
          <.modal_title id="update-payment-method-modal-title">
            Payment Method
          </.modal_title>
          <%!-- Loading state --%>
          <.async_section_loader
            :if={assigns[:loading_payment_methods]}
            id="user-settings-payment-methods-loading"
            label="Loading payment methods..."
            class="py-12"
          />
          <%!-- Loaded content --%>
          <div :if={!assigns[:loading_payment_methods]}>
            <%!-- Section 1: Existing payment methods --%>
            <div :if={length(@all_payment_methods) > 0}>
              <p class="text-sm font-medium text-zinc-500 uppercase tracking-wide mb-3">
                Saved methods
              </p>
              <div class="space-y-2">
                <div
                  :for={payment_method <- @all_payment_methods}
                  class={[
                    "border rounded-lg p-4 transition-all duration-200",
                    @selecting_payment_method && "cursor-not-allowed opacity-50",
                    !@selecting_payment_method && "cursor-pointer",
                    @default_payment_method &&
                      payment_method.id == @default_payment_method.id &&
                      "border-blue-500 bg-blue-50",
                    (!@default_payment_method ||
                       payment_method.id != @default_payment_method.id) &&
                      !@selecting_payment_method &&
                      "border-zinc-200 hover:border-zinc-300"
                  ]}
                  phx-click={
                    if @selecting_payment_method,
                      do: nil,
                      else: "select-payment-method"
                  }
                  phx-value-payment_method_id={payment_method.id}
                >
                  <div class="flex items-center space-x-3 flex-1 min-w-0">
                    <div class="flex-1 min-w-0">
                      <.stored_payment_method_display
                        payment_method={payment_method}
                        text_class="text-zinc-800 text-sm font-semibold"
                        expiry_class="text-zinc-500 text-xs mt-0.5"
                      />
                    </div>
                    <div class="flex-shrink-0">
                      <div
                        :if={
                          @default_payment_method &&
                            payment_method.id == @default_payment_method.id
                        }
                        class="flex items-center gap-1 text-blue-600"
                      >
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fill-rule="evenodd"
                            d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                            clip-rule="evenodd"
                          >
                          </path>
                        </svg>
                        <span class="text-xs font-semibold">Default</span>
                      </div>
                      <span
                        :if={
                          !@default_payment_method ||
                            payment_method.id != @default_payment_method.id
                        }
                        class="text-xs text-zinc-400"
                      >
                        <%= cond do %>
                          <% @selecting_payment_method -> %>
                            Updating...
                          <% true -> %>
                            Set as default
                        <% end %>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <%!-- Separator --%>
            <div class="relative my-6">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-zinc-200"></div>
              </div>
              <div
                :if={!@show_new_payment_form}
                class="relative flex justify-center"
              >
                <span class="bg-white px-3 text-xs text-zinc-400 uppercase tracking-wide">
                  Add new
                </span>
              </div>
            </div>
            <%!-- Section 2: Add new payment method button OR Stripe form --%>
            <div :if={!@show_new_payment_form} class="flex justify-center py-2">
              <.button
                id="add-payment-method"
                type="button"
                variant="outline"
                color="zinc"
                phx-click="add-new-payment-method"
                phx-disable-with="Loading..."
                class="border-2 border-dashed border-zinc-300 px-5 text-zinc-600 hover:border-blue-400 hover:text-blue-600 hover:bg-blue-50"
              >
                <.icon name="hero-plus-circle" class="w-5 h-5" /> Add Payment Method
              </.button>
            </div>
            <div :if={@show_new_payment_form && @payment_intent_secret}>
              <form
                id="payment-form"
                class="flex flex-col space-y-4"
                phx-hook="StripeInput"
                data-clientSecret={@payment_intent_secret}
                data-publicKey={@public_key}
                data-submitURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/payment-method"}
                data-returnURL={"#{YscWeb.Endpoint.url()}/billing/user/#{@user.id}/finalize"}
                data-billing-details={@stripe_billing_details}
              >
                <div id="error-message">
                  <p id="card-errors" class="text-red-400 text-sm"></p>
                </div>
                <div id="payment-element"></div>
              </form>
            </div>
          </div>
          <%!-- Modal footer --%>
          <div class="flex justify-end gap-3 mt-8 pt-4 border-t border-zinc-200">
            <.button
              patch={~p"/users/membership"}
              variant="outline"
              color="zinc"
              class="px-4"
            >
              Close
            </.button>
            <.button
              :if={@show_new_payment_form && @payment_intent_secret}
              type="submit"
              form="payment-form"
              id="submit"
              phx-disable-with="Saving..."
              color="blue"
              class="px-4"
            >
              Save Payment Method
            </.button>
          </div>
        </.modal>

        <.account_settings_nav
          current={
            case @live_action do
              :membership -> :membership
              :payment_method -> :membership
              :payments -> :payments
              :notifications -> :notifications
              :family -> :family
              _ -> :profile
            end
          }
          show_family_link?={
            @current_user &&
              (Accounts.primary_user?(@current_user) ||
                 Accounts.sub_account?(@current_user)) &&
              (@active_plan_type == :family || @active_plan_type == :lifetime)
          }
        />

        <div class="text-medium px-2 text-zinc-500 rounded w-full md:border-l md:border-1 md:border-zinc-100 md:pl-16">
          <div :if={@live_action == :edit} class="space-y-8">
            <!-- Profile Picture Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Profile Picture</h2>
              <p class="text-sm text-zinc-500">
                Adding a profile picture helps other members recognize you at events and makes the community feel more personal.
              </p>

              <div class="flex items-start gap-6">
                <%!-- Current avatar (large) --%>
                <div class="shrink-0 relative">
                  <div
                    :if={@loading_avatars}
                    class="w-24 h-24 rounded-full bg-zinc-200 animate-pulse"
                  >
                  </div>
                  <.user_avatar_image
                    :if={!@loading_avatars}
                    user={@user}
                    avatar_url={@current_avatar_url}
                    class={
                      if @avatar_processing,
                        do: "w-24 h-24 rounded-full opacity-50",
                        else: "w-24 h-24 rounded-full"
                    }
                  />
                  <div
                    :if={@avatar_processing}
                    class="absolute inset-0 flex items-center justify-center"
                  >
                    <svg
                      class="w-8 h-8 text-blue-600 animate-spin"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      />
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                      />
                    </svg>
                  </div>
                </div>

                <%!-- Upload + library --%>
                <div class="flex-1 space-y-4">
                  <form
                    id="avatar-upload-form"
                    phx-change="validate_avatar"
                    phx-submit="save_avatar"
                  >
                    <div id="avatar-uploader" phx-hook="AvatarCropper">
                      <div phx-update="ignore" id="avatar-cropper-ui">
                        <input
                          type="file"
                          accept="image/jpeg,image/png,image/webp,image/gif"
                          class="sr-only"
                          data-avatar-file-input
                        />
                        <button
                          type="button"
                          data-avatar-file-trigger
                          class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded-lg cursor-pointer hover:bg-zinc-50 transition-colors"
                        >
                          <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                          Upload new photo
                        </button>

                        <%!-- Cropper modal --%>
                        <div
                          data-cropper-modal
                          class="hidden fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
                        >
                          <div class="bg-white rounded-xl shadow-2xl max-w-lg w-full p-6 space-y-4">
                            <h3 class="text-lg font-semibold text-zinc-900">
                              Crop your photo
                            </h3>
                            <div
                              data-cropper-container
                              class="w-full overflow-hidden rounded-lg"
                            >
                            </div>
                            <div class="flex justify-end gap-3">
                              <button
                                type="button"
                                data-cropper-cancel
                                class="px-4 py-2 text-sm font-medium text-zinc-700 bg-zinc-100 rounded-lg hover:bg-zinc-200 transition-colors"
                              >
                                Cancel
                              </button>
                              <button
                                type="button"
                                data-cropper-confirm
                                class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors"
                              >
                                Save
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>

                      <.live_file_input upload={@uploads.avatar} class="hidden" />
                    </div>
                  </form>

                  <%!-- Upload progress --%>
                  <%= for entry <- @uploads.avatar.entries do %>
                    <div class="flex items-center gap-3">
                      <div class="w-full bg-zinc-200 rounded-full h-2">
                        <div
                          class="bg-blue-600 h-2 rounded-full transition-all"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>
                      <span class="text-sm text-zinc-500 tabular-nums">
                        {entry.progress}%
                      </span>
                    </div>
                    <%= for err <- upload_errors(@uploads.avatar, entry) do %>
                      <p class="text-sm text-red-600">
                        <.icon
                          name="hero-exclamation-circle"
                          class="w-4 h-4 -mt-0.5 inline"
                        />
                        {YscWeb.UploadErrors.error_to_string(err, :avatar)}
                      </p>
                    <% end %>
                  <% end %>

                  <%!-- Processing indicator --%>
                  <div
                    :if={@avatar_processing}
                    class="flex items-center gap-2 text-sm text-blue-600"
                  >
                    <svg
                      class="w-4 h-4 animate-spin"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      />
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                      />
                    </svg>
                    Processing your photo…
                  </div>

                  <%!-- Avatar library: avoid tall skeleton that collapses when empty (CLS) --%>
                  <div
                    :if={@loading_avatars}
                    class="pt-2 min-h-[1.25rem]"
                    aria-hidden="true"
                  >
                  </div>
                  <div :if={!@loading_avatars && @user_avatars != []} class="pt-2">
                    <p class="text-sm font-bold text-zinc-900 mb-2">
                      Your photos
                    </p>
                    <div class="flex flex-wrap gap-2">
                      <%= for avatar <- @user_avatars do %>
                        <div class="relative">
                          <button
                            type="button"
                            phx-click="select_avatar"
                            phx-value-id={avatar.id}
                            id={"avatar-#{avatar.id}"}
                            disabled={@selecting_avatar_id == avatar.id}
                            class={[
                              "w-14 h-14 rounded-full border-2 transition-all hover:scale-105 cursor-pointer overflow-hidden",
                              if(@user.current_avatar_id == avatar.id,
                                do: "border-blue-600 ring-2 ring-blue-200",
                                else: "border-zinc-200 hover:border-zinc-400"
                              )
                            ]}
                          >
                            <img
                              src={Ysc.Avatars.avatar_url(avatar, :thumb)}
                              alt="Previous avatar"
                              class="w-full h-full object-cover"
                            />
                          </button>
                          <div
                            :if={@selecting_avatar_id == avatar.id}
                            class="absolute inset-0 flex items-center justify-center rounded-full bg-white/60"
                          >
                            <svg
                              class="animate-spin w-5 h-5 text-blue-600"
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                            >
                              <circle
                                class="opacity-25"
                                cx="12"
                                cy="12"
                                r="10"
                                stroke="currentColor"
                                stroke-width="4"
                              >
                              </circle>
                              <path
                                class="opacity-75"
                                fill="currentColor"
                                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                              >
                              </path>
                            </svg>
                          </div>
                          <%!-- Source badge for OAuth-synced avatars --%>
                          <%= cond do %>
                            <% avatar.source == :google -> %>
                              <span class="absolute -bottom-0.5 -right-0.5 w-5 h-5 rounded-full bg-white shadow flex items-center justify-center pointer-events-none">
                                <img
                                  src={~p"/images/google/google_g_logo.svg"}
                                  alt="Google"
                                  class="w-5 h-5"
                                />
                              </span>
                            <% avatar.source == :facebook -> %>
                              <span class="absolute -bottom-0.5 -right-0.5 w-5 h-5 rounded-full bg-white shadow flex items-center justify-center pointer-events-none">
                                <img
                                  src={~p"/images/fb/facebook_f_logo.svg"}
                                  alt="Facebook"
                                  class="w-5 h-5"
                                />
                              </span>
                            <% true -> %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <!-- Personal Information Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Personal Information</h2>

              <.simple_form
                for={@profile_form}
                id="profile_form"
                phx-submit="update_profile"
                phx-change="validate_profile"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={@profile_form[:first_name]}
                    type="text"
                    label="First Name"
                    required
                  />
                  <.input
                    field={@profile_form[:last_name]}
                    type="text"
                    label="Last Name"
                    required
                  />
                </div>

                <.input
                  type="phone-input"
                  label="Phone Number"
                  id="phone_number"
                  field={@profile_form[:phone_number]}
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

                <.input
                  field={@profile_form[:most_connected_country]}
                  type="select"
                  label="Which Scandinavian country do you feel most connected to? (Denmark, Finland, Iceland, Norway, or Sweden)"
                  options={[
                    {"Sweden", "SE"},
                    {"Norway", "NO"},
                    {"Denmark", "DK"},
                    {"Finland", "FI"},
                    {"Iceland", "IS"}
                  ]}
                />

                <.input
                  field={@profile_form[:date_of_birth]}
                  type="date"
                  label="Date of Birth"
                  max={@today_max}
                />

                <:actions>
                  <.button phx-disable-with="Updating...">Update Profile</.button>
                </:actions>
              </.simple_form>
            </div>
            <!-- Billing Address Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Billing Address</h2>

              <.simple_form
                for={@address_form}
                id="address_form"
                phx-submit="update_address"
                phx-change="validate_address"
              >
                <.input
                  field={@address_form[:address]}
                  type="text"
                  label="Street Address"
                  required
                />

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={@address_form[:city]}
                    type="text"
                    label="City"
                    required
                  />
                  <.input
                    field={@address_form[:postal_code]}
                    type="text"
                    label="Postal Code"
                    required
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={@address_form[:region]}
                    type="text"
                    label="State/Province/Region"
                  />
                  <.input
                    field={@address_form[:country]}
                    type="text"
                    label="Country"
                    required
                  />
                </div>

                <:actions>
                  <.button phx-disable-with="Updating...">Update Address</.button>
                </:actions>
              </.simple_form>
            </div>
            <!-- Email Change Section -->
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">Email</h2>

              <%= if @pending_email do %>
                <div class="p-4 bg-amber-50 border border-amber-200 rounded-md">
                  <div class="flex items-start">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="w-5 h-5 text-amber-600 mt-0.5 me-2"
                    />
                    <div class="flex-1">
                      <p class="text-sm text-amber-800 font-semibold">
                        Email verification pending
                      </p>
                      <p class="text-sm text-amber-700 mt-1">
                        You have a pending email change to <strong><%= @pending_email %></strong>.
                        Please verify your new email address to complete the change.
                      </p>
                      <.link
                        patch={
                          if @pending_email_token do
                            ~p"/users/settings/email-verification" <>
                              "?etok=#{@pending_email_token}"
                          else
                            ~p"/users/settings/email-verification"
                          end
                        }
                        class="inline-block mt-2 text-sm font-medium text-amber-800 hover:text-amber-900 underline"
                      >
                        Resume verification
                      </.link>
                    </div>
                  </div>
                </div>
              <% end %>

              <.simple_form
                for={@email_form}
                id="email_form"
                phx-submit="request_email_change"
                phx-change="validate_email"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label="Email"
                  required
                />
                <p class="text-sm text-zinc-600 -mt-2">
                  For security, you'll need to verify your identity before we change your email.
                </p>
                <:actions>
                  <.button phx-disable-with="Opening identity verification...">
                    Verify my identity to change email
                  </.button>
                </:actions>
              </.simple_form>
            </div>
          </div>

          <div
            :if={@live_action == :membership || @live_action == :payment_method}
            class="flex flex-col space-y-6"
          >
            <%!-- Sub-account: read-only view --%>
            <div
              :if={@is_sub_account}
              class="rounded border border-zinc-100 p-6 space-y-4"
            >
              <h2 class="text-zinc-900 font-bold text-xl">Membership</h2>
              <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                <div class="flex gap-3">
                  <.icon
                    name="hero-user-group"
                    class="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5"
                  />
                  <div>
                    <h3 class="text-sm font-semibold text-blue-800">
                      Family Account
                    </h3>
                    <p class="text-sm text-blue-700 mt-1">
                      You are a family member. You share membership benefits from <strong><%= if @primary_user,
                        do: "#{@primary_user.first_name} #{@primary_user.last_name}",
                        else: "your family membership manager" %></strong>.
                      Family members cannot purchase or manage their own membership.
                    </p>
                    <%= if @primary_user do %>
                      <p class="text-sm text-blue-700 mt-1">
                        Contact
                        <strong>
                          {@primary_user.first_name} {@primary_user.last_name}
                        </strong>
                        to make any changes.
                      </p>
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="mt-4 pt-4 border-t border-zinc-200">
                <p class="text-sm text-zinc-600 mb-2">
                  You can leave this family membership at any time. You will no longer share membership benefits and can purchase your own membership or join another family later.
                </p>
                <.button
                  phx-click="leave-family-membership"
                  phx-disable-with="Leaving..."
                  color="red"
                  variant="outline"
                  data-confirm="Are you sure you want to leave this family membership? You will lose access to membership benefits until you purchase your own membership or join another family."
                >
                  Leave family membership
                </.button>
              </div>
              <.board_pause_notice
                :if={@membership_paused_by_board != nil}
                board_member={@membership_paused_by_board}
                current_user={@current_user}
              />
              <.membership_status
                current_membership={@current_membership}
                primary_user={@primary_user}
                is_sub_account={@is_sub_account}
              />
              <div
                :if={@scheduled_downgrade_info}
                data-testid="scheduled-downgrade-notice"
                class="bg-amber-50 border border-amber-200 rounded-lg p-4"
              >
                <div class="flex gap-3">
                  <.icon
                    name="hero-arrow-trending-down"
                    class="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5"
                  />
                  <div class="flex-1">
                    <h3 class="text-sm font-semibold text-amber-800">
                      Plan change scheduled
                    </h3>
                    <p class="text-sm text-amber-700 mt-1">
                      <%= if @primary_user do %>
                        The membership from
                        <strong>
                          {@primary_user.first_name} {@primary_user.last_name}
                        </strong>
                        will change to
                      <% else %>
                        Your family membership will change to
                      <% end %>
                      <strong>
                        {String.capitalize(
                          to_string(@scheduled_downgrade_info.target_plan)
                        )}
                      </strong>
                      after <strong>
                        <%= format_utc_date(@scheduled_downgrade_info.effective_date, "%B %d, %Y") %>
                      </strong>. You will keep your current benefits until that date.
                    </p>
                    <div class="mt-3">
                      <.button
                        id="cancel-scheduled-downgrade-btn"
                        phx-click="cancel-scheduled-downgrade"
                        phx-disable-with="Updating..."
                        variant="outline"
                        color="amber"
                        data-confirm="Cancel your scheduled plan change and keep your current membership? You will stay on your current plan and will not switch on the date shown above."
                      >
                        Keep my current plan
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
              <.button
                :if={@current_membership != nil}
                phx-click="show_membership_qr"
              >
                <.icon name="hero-qr-code" class="w-5 h-5" /> My Membership QR
              </.button>
              <div
                :if={@pending_family_invites != []}
                class="mt-6 border-t border-zinc-100 pt-4"
              >
                <h3 class="text-sm font-semibold text-zinc-900">
                  Pending Family Invitations
                </h3>
                <p class="text-xs text-zinc-500 mt-1">
                  You have been invited to join a family membership. Accepting will link your account to the inviter's membership.
                </p>
                <div class="mt-3 space-y-2">
                  <%= for invite <- @pending_family_invites do %>
                    <div class="flex items-center justify-between rounded border border-zinc-200 bg-zinc-50 px-3 py-2">
                      <div class="text-sm">
                        <p class="font-medium text-zinc-900">
                          Invite from {invite.primary_user.first_name} {invite.primary_user.last_name}
                        </p>
                        <p class="text-xs text-zinc-500">
                          Sent to {@user.email}
                        </p>
                      </div>
                      <.button
                        phx-click="accept-family-invite"
                        phx-value-token={invite.token}
                        phx-disable-with="Accepting..."
                        class="text-xs"
                      >
                        Accept invitation
                      </.button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Lifetime membership: special case --%>
            <div
              :if={@active_plan_type == :lifetime && !@is_sub_account}
              class="rounded border border-zinc-100 p-6 space-y-4"
            >
              <h2 class="text-zinc-900 font-bold text-xl">Membership</h2>
              <.membership_status
                current_membership={@current_membership}
                primary_user={@primary_user}
                is_sub_account={@is_sub_account}
              />
              <div
                :if={@scheduled_downgrade_info}
                data-testid="scheduled-downgrade-notice"
                class="bg-amber-50 border border-amber-200 rounded-lg p-4"
              >
                <div class="flex gap-3">
                  <.icon
                    name="hero-arrow-trending-down"
                    class="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5"
                  />
                  <div class="flex-1">
                    <h3 class="text-sm font-semibold text-amber-800">
                      Plan change scheduled
                    </h3>
                    <p class="text-sm text-amber-700 mt-1">
                      Your membership will change to
                      <strong>
                        {String.capitalize(
                          to_string(@scheduled_downgrade_info.target_plan)
                        )}
                      </strong>
                      after <strong>
                        <%= format_utc_date(@scheduled_downgrade_info.effective_date, "%B %d, %Y") %>
                      </strong>. You will keep your current benefits until that date.
                    </p>
                    <div class="mt-3">
                      <.button
                        id="cancel-scheduled-downgrade-btn"
                        phx-click="cancel-scheduled-downgrade"
                        phx-disable-with="Updating..."
                        variant="outline"
                        color="amber"
                        data-confirm="Cancel your scheduled plan change and keep your current membership? You will stay on your current plan and will not switch on the date shown above."
                      >
                        Keep my current plan
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
              <.button phx-click="show_membership_qr">
                <.icon name="hero-qr-code" class="w-5 h-5" /> My Membership QR
              </.button>
              <.link
                navigate={~p"/users/settings/family"}
                class="mt-4 inline-flex items-center gap-2 text-sm font-medium text-blue-600 hover:text-blue-800 ms-2"
              >
                <.icon name="hero-user-group" class="w-4 h-4" />
                Add family members to your membership
              </.link>
              <div
                :if={@pending_family_invites != []}
                class="mt-6 border-t border-zinc-100 pt-4"
              >
                <h3 class="text-sm font-semibold text-zinc-900">
                  Pending Family Invitations
                </h3>
                <p class="text-xs text-zinc-500 mt-1">
                  You have been invited to join a family membership. Accepting will link your account to the inviter's membership.
                </p>
                <div class="mt-3 space-y-2">
                  <%= for invite <- @pending_family_invites do %>
                    <div class="flex items-center justify-between rounded border border-zinc-200 bg-zinc-50 px-3 py-2">
                      <div class="text-sm">
                        <p class="font-medium text-zinc-900">
                          Invite from {invite.primary_user.first_name} {invite.primary_user.last_name}
                        </p>
                        <p class="text-xs text-zinc-500">
                          Sent to {@user.email}
                        </p>
                      </div>
                      <.button
                        phx-click="accept-family-invite"
                        phx-value-token={invite.token}
                        phx-disable-with="Accepting..."
                        class="text-xs"
                      >
                        Accept invitation
                      </.button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- No active membership: 3-step purchase flow --%>
            <div :if={
              @active_plan_type == nil && @current_membership == nil &&
                !@is_sub_account
            }>
              <div class="mb-6">
                <h2 class="text-2xl font-bold text-zinc-900">
                  Get Your YSC Membership
                </h2>
                <p class="text-zinc-500 mt-1">
                  Access exclusive events, cabin access, and all membership benefits.
                </p>
              </div>

              <div :if={@pending_family_invites != []} class="mb-6">
                <h3 class="text-sm font-semibold text-zinc-900">
                  Pending Family Invitations
                </h3>
                <p class="text-xs text-zinc-500 mt-1">
                  You've been invited to join a family membership. If you accept, you'll share the same membership benefits as the person who invited you — including cabin bookings and member event tickets.
                </p>
                <div class="mt-3 space-y-2">
                  <%= for invite <- @pending_family_invites do %>
                    <div class="flex items-center justify-between rounded border border-zinc-200 bg-zinc-50 px-3 py-2">
                      <div class="text-sm">
                        <p class="font-medium text-zinc-900">
                          Invite from {invite.primary_user.first_name} {invite.primary_user.last_name}
                        </p>
                        <p class="text-xs text-zinc-500">
                          Sent to {@user.email}
                        </p>
                      </div>
                      <.button
                        phx-click="accept-family-invite"
                        phx-value-token={invite.token}
                        phx-disable-with="Accepting..."
                        class="text-xs"
                      >
                        Accept invitation
                      </.button>
                    </div>
                  <% end %>
                </div>
              </div>

              <div
                :if={!@user_is_active}
                class="mb-6 bg-yellow-50 border border-yellow-200 rounded-lg p-4"
              >
                <div class="flex gap-3">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="h-5 w-5 text-yellow-500 flex-shrink-0 mt-0.5"
                  />
                  <div>
                    <h3 class="text-sm font-semibold text-yellow-800">
                      Account Pending Approval
                    </h3>
                    <p class="text-sm text-yellow-700 mt-1">
                      Your application is being reviewed by the board. If you already saved a payment method during setup, your membership will start automatically when you're approved. Otherwise we'll email you a secure link to pay your dues. Reviews usually take up to 14 days — we'll email you when there's a decision. {" "}
                      <.link
                        navigate={~p"/pending-review"}
                        class="font-semibold text-yellow-900 underline underline-offset-2"
                      >
                        View application status
                      </.link>
                    </p>
                  </div>
                </div>
              </div>

              <.form
                for={@membership_form}
                id="membership_form"
                phx-submit="select_membership"
                phx-change="validate_membership"
              >
                <div class={[
                  "bg-white border border-zinc-100 rounded overflow-hidden",
                  !@user_is_active && "opacity-50 pointer-events-none"
                ]}>
                  <%!-- Step 1: Choose Plan --%>
                  <div class="p-6 border-b border-zinc-100">
                    <div class="flex items-start gap-3 mb-5">
                      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white flex-shrink-0 mt-0.5">
                        1
                      </span>
                      <div>
                        <h3 class="text-lg font-semibold text-zinc-900">
                          Choose Your Plan
                        </h3>
                        <p class="text-sm text-zinc-500 mt-0.5">
                          Single covers you. Family covers you, your spouse and children under 18. Both are billed annually.
                        </p>
                      </div>
                    </div>
                    <fieldset class="flex flex-wrap gap-3">
                      <.radio_fieldset
                        field={@membership_form[:membership_type]}
                        options={
                          @membership_plans
                          |> Enum.filter(&(&1.id != :lifetime))
                          |> Enum.map(fn plan ->
                            {plan.id,
                             %{
                               option: "#{plan.id}",
                               subtitle: plan.description,
                               icon: (plan.id == :single && "user") || "user-group",
                               footer:
                                 "#{Ysc.MoneyHelper.format_money!(Money.new(:USD, plan.amount))} per year"
                             }}
                          end)
                        }
                        checked_value={@membership_form.params["membership_type"]}
                      />
                    </fieldset>
                  </div>

                  <%!-- Step 2: Payment Method --%>
                  <div class="p-6 bg-zinc-50/50 border-b border-zinc-100">
                    <div class="flex items-start gap-3 mb-5">
                      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white flex-shrink-0 mt-0.5">
                        2
                      </span>
                      <div>
                        <h3 class="text-lg font-semibold text-zinc-900">
                          Payment Method
                        </h3>
                        <p class="text-sm text-zinc-500 mt-0.5">
                          Used for this purchase and all future automatic renewals.
                        </p>
                      </div>
                    </div>

                    <.payment_method_row_skeleton
                      :if={@loading_payment_methods}
                      id="membership-payment-method-loading"
                    />

                    <%!-- No payment method: dashed "add" prompt --%>
                    <.link
                      :if={
                        !@loading_payment_methods && @default_payment_method == nil
                      }
                      navigate={~p"/users/membership/payment-method"}
                      class="flex w-full items-center justify-between p-4 bg-white border-2 border-dashed border-zinc-300 rounded-lg hover:border-blue-400 hover:bg-blue-50 transition-all group"
                    >
                      <div class="flex items-center gap-3">
                        <.icon
                          name="hero-credit-card"
                          class="w-5 h-5 text-zinc-400 group-hover:text-blue-600"
                        />
                        <span class="text-zinc-600 font-medium group-hover:text-blue-700">
                          Add a payment method
                        </span>
                      </div>
                      <.icon
                        name="hero-plus-circle"
                        class="w-5 h-5 text-zinc-400 group-hover:text-blue-600"
                      />
                    </.link>

                    <%!-- Has payment method: display with Change link --%>
                    <div
                      :if={
                        !@loading_payment_methods && @default_payment_method != nil
                      }
                      class="flex items-center justify-between p-4 bg-white border border-zinc-200 rounded-lg"
                    >
                      <.stored_payment_method_display payment_method={
                        @default_payment_method
                      } />
                      <.link
                        navigate={~p"/users/membership/payment-method"}
                        class="text-sm font-medium text-blue-600 hover:text-blue-700 hover:underline"
                      >
                        Change
                      </.link>
                    </div>
                  </div>

                  <%!-- Step 3: Summary & Pay --%>
                  <div class="p-6">
                    <div class="flex items-center gap-3 mb-5">
                      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white flex-shrink-0">
                        3
                      </span>
                      <h3 class="text-lg font-semibold text-zinc-900">
                        Confirm & Pay
                      </h3>
                    </div>

                    <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
                      <% selected_type = @membership_form.params["membership_type"]

                      selected_plan =
                        if selected_type,
                          do:
                            Enum.find(
                              @membership_plans,
                              &(to_string(&1.id) == selected_type)
                            ),
                          else: nil %>
                      <div>
                        <%= if selected_plan do %>
                          <p class="text-sm text-zinc-500">
                            {String.capitalize(to_string(selected_plan.id))} Membership &middot; Billed annually
                          </p>
                          <p class="text-2xl font-bold text-zinc-900 mt-0.5">
                            {Ysc.MoneyHelper.format_money!(
                              Money.new(:USD, selected_plan.amount)
                            )}
                          </p>
                        <% else %>
                          <p class="text-sm text-zinc-400 italic">
                            Select a plan above to see pricing.
                          </p>
                        <% end %>
                      </div>
                      <div class="flex flex-col items-start sm:items-end gap-2">
                        <.button
                          disabled={
                            @default_payment_method == nil || !@user_is_active
                          }
                          phx-disable-with="Processing..."
                        >
                          <.icon name="hero-shield-check" class="w-5 h-5" />
                          Complete Membership Purchase
                        </.button>
                        <p class="text-xs text-zinc-400 flex items-center gap-1">
                          <.icon name="hero-lock-closed" class="w-3 h-3" />
                          Secure, encrypted payment
                        </p>
                      </div>
                    </div>

                    <p
                      :if={
                        !@loading_payment_methods && @default_payment_method == nil
                      }
                      class="mt-3 text-sm text-zinc-500"
                    >
                      Add a payment method in step 2 to complete your purchase.
                    </p>

                    <p
                      :if={
                        !@user_is_active && !@loading_payment_methods &&
                          @default_payment_method != nil
                      }
                      class="mt-3 text-sm text-zinc-500"
                    >
                      Membership purchase unlocks after the board approves your application.{" "}
                      <.link
                        navigate={~p"/pending-review"}
                        class="font-medium text-blue-600 hover:underline"
                      >
                        View application status
                      </.link>
                    </p>
                  </div>
                </div>
              </.form>
            </div>

            <%!-- Active membership (non-lifetime): status + plan management --%>
            <div
              :if={
                @current_membership != nil && @active_plan_type != :lifetime &&
                  !@is_sub_account
              }
              class="space-y-6"
            >
              <%!-- Current status card --%>
              <div class="rounded border border-zinc-100 p-6 space-y-4">
                <h2 class="text-zinc-900 font-bold text-xl">Current Membership</h2>

                <.board_pause_notice
                  :if={@membership_paused_by_board != nil}
                  board_member={@membership_paused_by_board}
                  current_user={@current_user}
                />
                <.membership_status
                  current_membership={@current_membership}
                  primary_user={@primary_user}
                  is_sub_account={@is_sub_account}
                />

                <div
                  :if={@pending_family_invites != []}
                  class="border-t border-zinc-100 pt-4"
                >
                  <h3 class="text-sm font-semibold text-zinc-900">
                    Pending Family Invitations
                  </h3>
                  <p class="text-xs text-zinc-500 mt-1">
                    You have been invited to join a family membership. Accepting will link your account to the inviter's membership.
                  </p>
                  <div class="mt-3 space-y-2">
                    <%= for invite <- @pending_family_invites do %>
                      <div class="flex items-center justify-between rounded border border-zinc-200 bg-zinc-50 px-3 py-2">
                        <div class="text-sm">
                          <p class="font-medium text-zinc-900">
                            Invite from {invite.primary_user.first_name} {invite.primary_user.last_name}
                          </p>
                          <p class="text-xs text-zinc-500">
                            Sent to {@user.email}
                          </p>
                        </div>
                        <.button
                          phx-click="accept-family-invite"
                          phx-value-token={invite.token}
                          phx-disable-with="Accepting..."
                          class="text-xs"
                        >
                          Accept invitation
                        </.button>
                      </div>
                    <% end %>
                  </div>
                </div>

                <div
                  :if={@scheduled_downgrade_info}
                  data-testid="scheduled-downgrade-notice"
                  class="bg-amber-50 border border-amber-200 rounded-lg p-4"
                >
                  <div class="flex gap-3">
                    <.icon
                      name="hero-arrow-trending-down"
                      class="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5"
                    />
                    <div class="flex-1">
                      <h3 class="text-sm font-semibold text-amber-800">
                        Plan change scheduled
                      </h3>
                      <p class="text-sm text-amber-700 mt-1">
                        Your membership will change to
                        <strong>
                          {String.capitalize(
                            to_string(@scheduled_downgrade_info.target_plan)
                          )}
                        </strong>
                        after <strong>
                          <%= format_utc_date(@scheduled_downgrade_info.effective_date, "%B %d, %Y") %>
                        </strong>. You will keep your current benefits until that date.
                      </p>
                      <div class="mt-3">
                        <.button
                          id="cancel-scheduled-downgrade-btn"
                          phx-click="cancel-scheduled-downgrade"
                          phx-disable-with="Updating..."
                          variant="outline"
                          color="amber"
                          data-confirm="Cancel your scheduled plan change and keep your current membership? You will stay on your current plan and will not switch on the date shown above."
                        >
                          Keep my current plan
                        </.button>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="flex flex-col sm:flex-row sm:flex-wrap sm:items-center gap-3 pt-4 border-t border-zinc-100">
                  <.button
                    phx-click="show_membership_qr"
                    class="w-full sm:w-auto justify-center"
                  >
                    <.icon name="hero-qr-code" class="w-5 h-5" /> My Membership QR
                  </.button>
                  <.button
                    patch={~p"/users/membership/payment-method"}
                    variant="outline"
                    class="w-full sm:w-auto justify-center"
                  >
                    <.icon name="hero-credit-card" class="w-5 h-5" />
                    Change Payment Method
                  </.button>
                  <.button
                    :if={
                      Subscriptions.scheduled_for_cancellation?(@current_membership)
                    }
                    phx-click="reactivate-membership"
                    phx-disable-with="Saving..."
                    color="green"
                    disabled={!@user_is_active}
                    class="w-full sm:w-auto justify-center"
                  >
                    Turn on auto-renewal
                  </.button>
                  <.button
                    :if={
                      !Subscriptions.scheduled_for_cancellation?(
                        @current_membership
                      )
                    }
                    phx-click="cancel-membership"
                    phx-disable-with="Saving..."
                    variant="outline"
                    color="amber"
                    disabled={
                      !@user_is_active ||
                        Subscriptions.scheduled_for_cancellation?(
                          @current_membership
                        )
                    }
                    data-confirm="Turn off automatic renewal? You keep full membership benefits until your current membership year ends, and you can turn auto-renewal back on anytime before then."
                    class="w-full sm:w-auto justify-center"
                  >
                    Turn off auto-renewal
                  </.button>
                </div>
              </div>

              <%!-- Change plan card (only when we know the plan type) --%>
              <div
                :if={@active_plan_type != nil}
                class="rounded border border-zinc-100 overflow-hidden"
              >
                <div class="p-6 border-b border-zinc-100">
                  <h2 class="text-zinc-900 font-bold text-xl">Change Plan</h2>
                  <p class="text-sm text-zinc-500 mt-1">
                    Switch between Single and Family plans. Upgrades take effect immediately; downgrades apply at your next renewal.
                  </p>
                </div>

                <div
                  :if={!@user_is_active}
                  class="m-6 bg-yellow-50 border border-yellow-200 rounded-lg p-4"
                >
                  <div class="flex gap-3">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="h-5 w-5 text-yellow-500 flex-shrink-0 mt-0.5"
                    />
                    <div>
                      <h3 class="text-sm font-semibold text-yellow-800">
                        Account Pending Approval
                      </h3>
                      <p class="text-sm text-yellow-700 mt-1">
                        You will be able to manage your membership once your account is approved.
                      </p>
                    </div>
                  </div>
                </div>

                <.form
                  for={@membership_form}
                  id="membership_form"
                  phx-change="validate_membership"
                  class={[!@user_is_active && "opacity-50 pointer-events-none"]}
                >
                  <%!-- Step 1: Plan selection --%>
                  <div class="p-6 border-b border-zinc-100">
                    <div class="flex items-center gap-3 mb-4">
                      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white flex-shrink-0">
                        1
                      </span>
                      <h3 class="text-lg font-semibold text-zinc-900">
                        Select Plan
                      </h3>
                    </div>
                    <fieldset class="flex flex-wrap gap-3">
                      <.radio_fieldset
                        field={@membership_form[:membership_type]}
                        options={
                          @membership_plans
                          |> Enum.filter(&(&1.id != :lifetime))
                          |> Enum.map(fn plan ->
                            {plan.id,
                             %{
                               option: "#{plan.id}",
                               subtitle: plan.description,
                               icon: (plan.id == :single && "user") || "user-group",
                               footer:
                                 "#{Ysc.MoneyHelper.format_money!(Money.new(:USD, plan.amount))} per year"
                             }}
                          end)
                        }
                        checked_value={@membership_form.params["membership_type"]}
                      />
                    </fieldset>
                  </div>

                  <%!-- Plan change info banner --%>
                  <div
                    :if={@membership_change_info != nil}
                    class={[
                      "mx-6 mt-4 rounded-lg p-4 border",
                      if(@membership_change_info.direction == :upgrade,
                        do: "bg-blue-50 border-blue-200",
                        else: "bg-amber-50 border-amber-200"
                      )
                    ]}
                  >
                    <div class="flex gap-3">
                      <.icon
                        name={
                          if(@membership_change_info.direction == :upgrade,
                            do: "hero-arrow-trending-up",
                            else: "hero-arrow-trending-down"
                          )
                        }
                        class={[
                          "h-5 w-5 flex-shrink-0 mt-0.5",
                          if(@membership_change_info.direction == :upgrade,
                            do: "text-blue-500",
                            else: "text-amber-500"
                          )
                        ]}
                      />
                      <div>
                        <h4 class={[
                          "text-sm font-semibold mb-1",
                          if(@membership_change_info.direction == :upgrade,
                            do: "text-blue-900",
                            else: "text-amber-900"
                          )
                        ]}>
                          <%= if @membership_change_info.direction == :upgrade do %>
                            Upgrade to {String.capitalize(
                              "#{@membership_change_info.new_plan.id}"
                            )} Membership
                          <% else %>
                            Downgrade to {String.capitalize(
                              "#{@membership_change_info.new_plan.id}"
                            )} Membership
                          <% end %>
                        </h4>
                        <div class={[
                          "text-sm",
                          if(@membership_change_info.direction == :upgrade,
                            do: "text-blue-800",
                            else: "text-amber-800"
                          )
                        ]}>
                          <%= if @membership_change_info.direction == :upgrade do %>
                            <p>
                              To upgrade today, you'll pay the prorated difference for the rest of your
                              membership year when you switch from {String.capitalize(
                                "#{@membership_change_info.current_plan.id}"
                              )} to {String.capitalize(
                                "#{@membership_change_info.new_plan.id}"
                              )} membership. Today's charge won't exceed <strong>
                                {Ysc.MoneyHelper.format_money!(
                                  Money.new(
                                    :USD,
                                    @membership_change_info.price_difference
                                  )
                                )}
                              </strong>.
                            </p>
                          <% else %>
                            <p>
                              Your membership will switch at your next renewal date. You will keep your {String.capitalize(
                                "#{@membership_change_info.current_plan.id}"
                              )} benefits until then. No immediate charges or credits will apply.
                            </p>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>

                  <%!-- Step 2: Payment Method --%>
                  <div class="p-6 bg-zinc-50/50 border-t border-zinc-100 mt-4">
                    <div class="flex items-start gap-3 mb-4">
                      <span class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white flex-shrink-0 mt-0.5">
                        2
                      </span>
                      <div>
                        <h3 class="text-lg font-semibold text-zinc-900">
                          Payment Method
                        </h3>
                        <p class="text-sm text-zinc-500 mt-0.5">
                          Used for this change and all future automatic renewals.
                        </p>
                      </div>
                    </div>

                    <.payment_method_row_skeleton
                      :if={@loading_payment_methods}
                      id="change-payment-method-loading"
                    />

                    <.link
                      :if={
                        !@loading_payment_methods && @default_payment_method == nil
                      }
                      navigate={~p"/users/membership/payment-method"}
                      class="flex w-full items-center justify-between p-4 bg-white border-2 border-dashed border-zinc-300 rounded-lg hover:border-blue-400 hover:bg-blue-50 transition-all group"
                    >
                      <div class="flex items-center gap-3">
                        <.icon
                          name="hero-credit-card"
                          class="w-5 h-5 text-zinc-400 group-hover:text-blue-600"
                        />
                        <span class="text-zinc-600 font-medium group-hover:text-blue-700">
                          Add a payment method
                        </span>
                      </div>
                      <.icon
                        name="hero-plus-circle"
                        class="w-5 h-5 text-zinc-400 group-hover:text-blue-600"
                      />
                    </.link>

                    <div
                      :if={
                        !@loading_payment_methods && @default_payment_method != nil
                      }
                      class="flex items-center justify-between p-4 bg-white border border-zinc-200 rounded-lg"
                    >
                      <.stored_payment_method_display payment_method={
                        @default_payment_method
                      } />
                      <.link
                        navigate={~p"/users/membership/payment-method"}
                        class="text-sm font-medium text-blue-600 hover:text-blue-700 hover:underline"
                      >
                        Change
                      </.link>
                    </div>
                  </div>

                  <%!-- Confirm change button --%>
                  <div
                    :if={@change_membership_button}
                    class="p-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-t border-zinc-100"
                  >
                    <p class="text-sm text-zinc-500">
                      <%= if @membership_change_info && @membership_change_info.direction == :upgrade do %>
                        You'll pay the difference for the rest of your membership year today.
                      <% else %>
                        The change will take effect at your next renewal date.
                      <% end %>
                    </p>
                    <.button
                      data-testid="change-membership-plan-button"
                      disabled={@default_payment_method == nil || !@user_is_active}
                      phx-click="change-membership"
                      phx-value-membership_type={
                        @membership_form.params["membership_type"]
                      }
                      phx-disable-with="Changing..."
                      type="button"
                    >
                      <.icon name="hero-arrows-right-left" /> Change Membership Plan
                    </.button>
                  </div>
                </.form>
              </div>
            </div>
          </div>

          <%!-- Detects platform to show the correct wallet button(s) --%>
          <div
            id="wallet-platform-detector"
            phx-hook="WalletPlatform"
            class="hidden"
          >
          </div>

          <.modal
            :if={
              @show_membership_qr &&
                (@live_action == :membership || @live_action == :payment_method)
            }
            id="settings-membership-qr-modal"
            show
            on_cancel={JS.push("hide_membership_qr")}
          >
            <div class="text-center">
              <h3 class="text-xl font-bold text-zinc-900 mb-1">
                My Membership QR
              </h3>
              <p class="text-sm text-zinc-500 mb-5">
                Show this to an admin for membership verification
              </p>
              <.qr_code data={@membership_qr_token} size={250} class="mx-auto" />
              <%= if @apple_wallet_membership_enabled? &&
                    @wallet_platform in [:apple_only, :both] do %>
                <div class="flex justify-center mt-4">
                  <.add_to_wallet_button href={~p"/wallet/membership"} />
                </div>
              <% end %>
              <%= if @google_wallet_membership_enabled? &&
                    @wallet_platform in [:google_only, :both] &&
                    @google_wallet_membership_url do %>
                <div class="flex justify-center mt-2">
                  <.add_to_google_wallet_button href={@google_wallet_membership_url} />
                </div>
              <% end %>
              <%= if @membership_qr_details do %>
                <div class="mt-5 rounded-xl bg-zinc-50 border border-zinc-200 divide-y divide-zinc-200 text-left">
                  <div class="flex items-center justify-between px-4 py-3">
                    <span class="text-xs font-semibold text-zinc-500 uppercase tracking-widest">
                      Type
                    </span>
                    <span class="text-sm font-semibold text-zinc-900">
                      {@membership_qr_details.type_label}
                    </span>
                  </div>
                  <%= if @membership_qr_details.member_since do %>
                    <div class="flex items-center justify-between px-4 py-3">
                      <span class="text-xs font-semibold text-zinc-500 uppercase tracking-widest">
                        Member Since
                      </span>
                      <span class="text-sm font-semibold text-zinc-900">
                        {format_utc_date(
                          @membership_qr_details.member_since,
                          "%b %-d, %Y"
                        )}
                      </span>
                    </div>
                  <% end %>
                  <div class="flex items-center justify-between px-4 py-3">
                    <span class="text-xs font-semibold text-zinc-500 uppercase tracking-widest">
                      Valid Until
                    </span>
                    <%= if @membership_qr_details.renewal_date do %>
                      <span class="text-sm font-semibold text-zinc-900">
                        {format_utc_date(
                          @membership_qr_details.renewal_date,
                          "%b %-d, %Y"
                        )}
                      </span>
                    <% else %>
                      <span class="text-sm font-semibold text-emerald-700">
                        Forever ✦
                      </span>
                    <% end %>
                  </div>
                  <%= if @membership_qr_details.is_sub_account && @membership_qr_details.primary_name do %>
                    <div class="flex items-center justify-between px-4 py-3">
                      <span class="text-xs font-semibold text-zinc-500 uppercase tracking-widest">
                        Through
                      </span>
                      <span class="text-sm font-semibold text-zinc-900">
                        {@membership_qr_details.primary_name}
                      </span>
                    </div>
                  <% end %>
                </div>
              <% end %>
              <.button
                phx-click="hide_membership_qr"
                color="zinc"
                class="w-full mt-3"
              >
                Close
              </.button>
            </div>
          </.modal>

          <div :if={@live_action == :notifications} class="space-y-6">
            <div class="rounded border border-zinc-100 py-4 px-4 space-y-4">
              <h2 class="text-zinc-900 font-bold text-xl">
                Notification Preferences
              </h2>
              <p class="text-sm text-zinc-600">
                Manage how you receive notifications from the YSC. You can control which types of notifications you receive via email or SMS.
              </p>
              <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mt-4">
                <p class="text-sm text-blue-900">
                  <strong>SMS Consent:</strong>
                  By voluntarily providing your phone number and explicitly opting in to text messaging, you consent to receive text messages from Young Scandinavians Club (YSC). Message and data rates may apply. You can opt out at any time by unchecking the SMS options below or sending a STOP message to the number you receive messages from. See our
                  <.link
                    navigate={~p"/privacy-policy"}
                    class="text-blue-700 hover:underline font-semibold"
                  >
                    Privacy Policy
                  </.link>
                  for more information about how we use your phone number.
                </p>
              </div>

              <div
                :if={@loading_notification_preferences}
                id="notification-preferences-loading"
                class="overflow-x-auto rounded-lg border border-zinc-200 min-h-[22rem]"
                role="status"
                aria-live="polite"
              >
                <span class="sr-only">Loading notification preferences…</span>
                <div class="bg-zinc-50 px-6 py-3 border-b border-zinc-200 flex gap-4">
                  <.skeleton_block class="h-3 w-20 rounded" />
                  <.skeleton_block class="h-3 w-12 rounded ml-auto" />
                  <.skeleton_block class="h-3 w-10 rounded" />
                </div>
                <div class="divide-y divide-zinc-100">
                  <div :for={_ <- 1..3} class="flex items-center gap-4 px-6 py-4">
                    <div class="flex-1 space-y-2">
                      <.skeleton_block class="h-4 w-40 rounded" />
                      <.skeleton_block class="h-3 w-64 max-w-full rounded" />
                    </div>
                    <.skeleton_block class="h-4 w-4 rounded shrink-0" />
                    <.skeleton_block class="h-4 w-4 rounded shrink-0" />
                  </div>
                </div>
                <div class="px-6 py-4">
                  <.skeleton_block class="h-10 w-40 rounded" />
                </div>
              </div>

              <div
                :if={!@loading_notification_preferences}
                class="min-h-[22rem]"
              >
                <.simple_form
                  for={@notification_form}
                  id="notification_form"
                  data-testid="notification-preferences-ready"
                  phx-submit="update_notifications"
                  phx-change="validate_notifications"
                >
                  <div class="overflow-x-auto">
                    <table class="min-w-full divide-y divide-zinc-200">
                      <thead class="bg-zinc-50">
                        <tr>
                          <th
                            scope="col"
                            class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                          >
                            Category
                          </th>
                          <th
                            scope="col"
                            class="px-6 py-3 text-center text-xs font-medium text-zinc-500 uppercase tracking-wider"
                          >
                            Email
                          </th>
                          <th
                            scope="col"
                            class="px-6 py-3 text-center text-xs font-medium text-zinc-500 uppercase tracking-wider"
                          >
                            SMS
                          </th>
                        </tr>
                      </thead>
                      <tbody class="bg-white divide-y divide-zinc-200">
                        <!-- Newsletter Row -->
                        <tr>
                          <td class="px-6 py-4">
                            <div>
                              <div class="text-sm font-medium text-zinc-900">
                                Newsletters
                              </div>
                              <div class="text-sm text-zinc-500 mt-1">
                                Receive our newsletter with updates about YSC events, news, and community highlights.
                              </div>
                            </div>
                          </td>
                          <td class="px-6 py-4">
                            <input
                              type="hidden"
                              name={
                                @notification_form[:newsletter_notifications].name
                              }
                              value="false"
                            />
                            <.input
                              field={@notification_form[:newsletter_notifications]}
                              type="checkbox"
                              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                            />
                          </td>
                          <td class="px-6 py-4">
                            <span class="text-sm text-zinc-400">—</span>
                          </td>
                        </tr>
                        <!-- Event Updates Row -->
                        <tr>
                          <td class="px-6 py-4">
                            <div>
                              <div class="text-sm font-medium text-zinc-900">
                                Event Updates
                              </div>
                              <div class="text-sm text-zinc-500 mt-1">
                                Receive notifications when new events are published and reminders before events you're attending.
                              </div>
                            </div>
                          </td>
                          <td class="px-6 py-4">
                            <input
                              type="hidden"
                              name={@notification_form[:event_notifications].name}
                              value="false"
                            />
                            <.input
                              field={@notification_form[:event_notifications]}
                              type="checkbox"
                              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                            />
                          </td>
                          <td class="px-6 py-4">
                            <input
                              type="hidden"
                              name={
                                @notification_form[:event_notifications_sms].name
                              }
                              value="false"
                            />
                            <.input
                              field={@notification_form[:event_notifications_sms]}
                              type="checkbox"
                              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                            />
                          </td>
                        </tr>
                        <!-- Account Updates Row -->
                        <tr>
                          <td class="px-6 py-4">
                            <div>
                              <div class="text-sm font-medium text-zinc-900">
                                Account Updates
                              </div>
                              <div class="text-sm text-zinc-500 mt-1">
                                Important account-related notifications such as password changes, email confirmations, and security alerts.
                              </div>
                            </div>
                          </td>
                          <td class="px-6 py-4">
                            <input
                              type="hidden"
                              name={@notification_form[:account_notifications].name}
                              value="true"
                            />
                            <input
                              type="checkbox"
                              id={@notification_form[:account_notifications].id}
                              name={@notification_form[:account_notifications].name}
                              value="true"
                              checked={true}
                              disabled
                              class="h-4 w-4 text-zinc-600 focus:ring-blue-500 border-zinc-300 rounded opacity-50 cursor-not-allowed"
                            />
                          </td>
                          <td class="px-6 py-4">
                            <input
                              type="hidden"
                              name={
                                @notification_form[:account_notifications_sms].name
                              }
                              value="false"
                            />
                            <.input
                              field={@notification_form[:account_notifications_sms]}
                              type="checkbox"
                              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-zinc-300 rounded"
                            />
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>

                  <:actions>
                    <.button phx-disable-with="Saving...">Save Preferences</.button>
                  </:actions>
                </.simple_form>
              </div>
            </div>
          </div>

          <div :if={@live_action == :payments} class="space-y-6">
            <div :if={!assigns[:loading_payments]} class="space-y-6">
              <div
                :if={@booking_entitlements_count > 0}
                id="member-booking-entitlements-section"
                class="rounded border border-zinc-200 bg-white py-6 px-4 sm:px-6"
              >
                <div class="mb-6 flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-bold text-zinc-900">Your stay perks</h2>
                    <p class="text-sm text-zinc-500 mt-1 max-w-xl">
                      Applied automatically when you book a cabin stay that matches each perk below. Discounts and free nights appear in your price before you pay.
                    </p>
                  </div>
                  <div class="hidden sm:flex items-center text-zinc-400">
                    <.icon name="hero-sparkles" class="w-6 h-6" />
                  </div>
                </div>
                <div
                  id="member-booking-entitlements"
                  phx-update="stream"
                  class="grid gap-4 sm:grid-cols-2"
                >
                  <div
                    :for={{id, ent} <- @streams.booking_entitlements}
                    id={id}
                    class="flex flex-col rounded-lg border border-zinc-200 bg-zinc-50/50 p-5 transition-colors hover:border-zinc-300"
                  >
                    <div class="flex items-start justify-between gap-3 mb-3">
                      <span class="inline-flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-zinc-700 border border-zinc-200 shadow-sm">
                        <.icon
                          name="hero-sparkles"
                          class="w-3.5 h-3.5 text-blue-600"
                        /> Member perk
                      </span>
                      <span class="text-xs font-medium text-zinc-500 mt-1 tabular-nums">
                        Since {Calendar.strftime(ent.inserted_at, "%b %Y")}
                      </span>
                    </div>
                    <div class="mb-4 flex-grow">
                      <p class="text-base font-bold text-zinc-900">
                        {member_entitlement_coupon_headline(ent)}
                      </p>
                      <p class="mt-1 text-sm text-zinc-600">
                        {member_entitlement_benefit_summary(ent)}
                      </p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2 text-xs">
                      <span class="inline-flex items-center rounded bg-zinc-100 px-2 py-1 font-medium text-zinc-700">
                        <.icon
                          name="hero-map-pin"
                          class="w-3.5 h-3.5 me-1 text-zinc-500"
                        />
                        {member_entitlement_property_label(ent.property)}
                      </span>
                      <span class="inline-flex items-center rounded bg-emerald-50 px-2 py-1 font-medium text-emerald-800 border border-emerald-100">
                        <.icon
                          name="hero-clock"
                          class="w-3.5 h-3.5 me-1 text-emerald-600"
                        />
                        {member_entitlement_coupon_expiry_phrase(ent)}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              <div
                :if={@ticket_reservations_count > 0}
                id="member-ticket-reservations-section"
                class="rounded border border-zinc-200 bg-white py-6 px-4 sm:px-6"
              >
                <div class="mb-6 flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-bold text-zinc-900">
                      Tickets waiting for payment
                    </h2>
                    <p class="text-sm text-zinc-500 mt-1 max-w-xl">
                      You started buying event tickets but didn't finish payment. Your selections and member price are still saved. Finish checkout before the time shown on each item — or as soon as you can if no time is listed.
                    </p>
                  </div>
                  <div class="hidden sm:flex items-center text-zinc-400">
                    <.icon name="hero-ticket" class="w-6 h-6" />
                  </div>
                </div>
                <div
                  id="member-ticket-reservations"
                  phx-update="stream"
                  class="grid gap-4 sm:grid-cols-2"
                >
                  <div
                    :for={{id, res} <- @streams.ticket_reservations}
                    id={id}
                    class="flex flex-col rounded-lg border border-zinc-200 bg-zinc-50/50 p-5 transition-colors hover:border-zinc-300"
                  >
                    <div class="flex items-start justify-between gap-3 mb-3">
                      <span class="inline-flex items-center gap-1.5 rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-zinc-700 border border-zinc-200 shadow-sm">
                        <.icon name="hero-bolt" class="w-3.5 h-3.5 text-blue-600" />
                        Payment not finished
                      </span>
                      <span class="text-xs font-medium text-zinc-500 mt-1 tabular-nums">
                        {if res.quantity == 1,
                          do: "1 ticket",
                          else: "#{res.quantity} tickets"}
                      </span>
                    </div>
                    <div class="mb-4 flex-grow">
                      <p class="text-base font-bold text-zinc-900">
                        <%= if res.ticket_tier && res.ticket_tier.event do %>
                          {res.ticket_tier.event.title}
                        <% else %>
                          Tickets in progress
                        <% end %>
                      </p>
                      <p :if={res.ticket_tier} class="mt-1 text-sm text-zinc-600">
                        {res.ticket_tier.name}
                      </p>
                      <p
                        :if={ticket_reservation_discount_phrase(res)}
                        class="mt-2 inline-flex items-center gap-1.5 rounded bg-blue-50 px-2 py-1 text-xs font-medium text-blue-800 border border-blue-100"
                      >
                        <.icon
                          name="hero-receipt-percent"
                          class="w-3.5 h-3.5 text-blue-600"
                        />
                        {ticket_reservation_discount_phrase(res)}
                      </p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2 text-xs mb-4">
                      <span class="inline-flex items-center rounded bg-zinc-100 px-2 py-1 font-medium text-zinc-700">
                        <.icon
                          name="hero-clock"
                          class="w-3.5 h-3.5 me-1 text-zinc-500"
                        />
                        <%= if res.expires_at do %>
                          Saved until {Calendar.strftime(
                            DateTime.shift_zone!(
                              res.expires_at,
                              "America/Los_Angeles"
                            ),
                            "%b %-d, %Y %H:%M PT"
                          )}
                        <% else %>
                          Finish checkout soon — your held tickets may be released if you wait too long
                        <% end %>
                      </span>
                    </div>
                    <%= if res.ticket_tier && res.ticket_tier.event do %>
                      <.link
                        navigate={~p"/events/#{res.ticket_tier.event.id}/tickets"}
                        class="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 transition-colors"
                      >
                        Finish buying tickets
                        <.icon name="hero-arrow-right" class="w-4 h-4" />
                      </.link>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded border border-zinc-100 py-4 px-4 space-y-6">
              <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
                <div>
                  <h2 class="text-zinc-900 font-bold text-xl">
                    My Bookings & Payments
                  </h2>
                  <p class="text-sm text-zinc-600 mt-1 max-w-2xl">
                    View your cabin booking payment history below. Unpaid cabin bookings won't appear here until checkout is complete — use the link in your email or return to the cabin page to finish. To see or use your event tickets, open Your event tickets.
                  </p>
                </div>
                <.link
                  navigate={~p"/users/tickets"}
                  class="inline-flex items-center gap-2 rounded-lg border border-zinc-200 bg-white px-4 py-2.5 text-sm font-semibold text-zinc-800 hover:bg-zinc-50 transition-colors shrink-0"
                >
                  <.icon name="hero-ticket" class="w-4 h-4" /> Your event tickets
                </.link>
              </div>
              <!-- Loading state for payments -->
              <div
                :if={assigns[:loading_payments]}
                id="payment-history-loading"
                role="status"
                aria-live="polite"
              >
                <span class="sr-only">Loading bookings and payments…</span>
                <div class="flex flex-wrap gap-2 pb-4 border-b border-zinc-200">
                  <.skeleton_block :for={_ <- 1..4} class="h-9 w-20 rounded-full" />
                </div>
                <.table_skeleton
                  rows={5}
                  columns={4}
                  class="mt-4"
                  announce?={false}
                />
              </div>
              <!-- Filter Chips (hidden while loading) -->
              <div :if={!assigns[:loading_payments]}>
                <div class="flex flex-wrap gap-2 pb-4 border-b border-zinc-200">
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="all"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all",
                      if(@payment_filter == :all,
                        do: "bg-blue-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    All
                  </button>
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="tahoe"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all flex items-center gap-2",
                      if(@payment_filter == :tahoe,
                        do: "bg-blue-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-home"
                      class={[
                        "w-4 h-4",
                        if(@payment_filter == :tahoe,
                          do: "text-white",
                          else: "text-blue-600"
                        )
                      ]}
                    />Tahoe
                  </button>
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="clear_lake"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all flex items-center gap-2",
                      if(@payment_filter == :clear_lake,
                        do: "bg-emerald-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-home"
                      class={[
                        "w-4 h-4",
                        if(@payment_filter == :clear_lake,
                          do: "text-white",
                          else: "text-emerald-600"
                        )
                      ]}
                    />Clear Lake
                  </button>
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="events"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all flex items-center gap-2",
                      if(@payment_filter == :events,
                        do: "bg-purple-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-ticket"
                      class={[
                        "w-4 h-4",
                        if(@payment_filter == :events,
                          do: "text-white",
                          else: "text-purple-600"
                        )
                      ]}
                    />Events
                  </button>
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="donations"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all flex items-center gap-2",
                      if(@payment_filter == :donations,
                        do: "bg-yellow-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-gift"
                      class={[
                        "w-4 h-4",
                        if(@payment_filter == :donations,
                          do: "text-white",
                          else: "text-yellow-600"
                        )
                      ]}
                    />Donations
                  </button>
                  <button
                    phx-click="filter-payments"
                    phx-value-filter="membership"
                    class={[
                      "px-4 py-2 rounded-full text-sm font-semibold transition-all flex items-center gap-2",
                      if(@payment_filter == :membership,
                        do: "bg-teal-600 text-white shadow-md",
                        else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-heart"
                      class={[
                        "w-4 h-4",
                        if(@payment_filter == :membership,
                          do: "text-white",
                          else: "text-teal-600"
                        )
                      ]}
                    />Membership
                  </button>
                </div>
                <!-- Desktop Table View -->
                <div class="hidden md:block overflow-x-auto">
                  <table class="min-w-full divide-y divide-zinc-200">
                    <thead class="bg-zinc-50">
                      <tr>
                        <th
                          scope="col"
                          class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Transaction
                        </th>
                        <th
                          scope="col"
                          class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Details
                        </th>
                        <th
                          scope="col"
                          class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Amount
                        </th>
                        <th
                          scope="col"
                          class="px-6 py-3 text-center text-xs font-medium text-zinc-500 uppercase tracking-wider"
                        >
                          Status
                        </th>
                      </tr>
                    </thead>
                    <tbody
                      id="payments-list"
                      phx-update="stream"
                      class="bg-white divide-y divide-zinc-200"
                    >
                      <%= for {id, payment_info} <- @streams.payments do %>
                        {render_payment_table_row(payment_info, id: id)}
                      <% end %>
                    </tbody>
                  </table>
                </div>
                <!-- Mobile Card View -->
                <div
                  :if={@filtered_payments_count > 0}
                  id="payments-cards"
                  class="md:hidden space-y-4 pt-4"
                >
                  <%= for payment_info <- @filtered_payments_list do %>
                    <% card_id = "mobile-card-#{payment_dom_id(payment_info)}" %>
                    <div id={card_id}>
                      {render_payment_card(payment_info)}
                    </div>
                  <% end %>
                </div>

                <div
                  :if={@filtered_payments_count == 0 && @payments_total > 0}
                  class="text-center py-12"
                >
                  <p class="text-zinc-500 text-sm">
                    No payments match the selected filter.
                  </p>
                </div>

                <div :if={@payments_total == 0} class="text-center py-12">
                  <p class="text-zinc-600 text-sm">
                    No payments yet. Cabin bookings you've paid for and event purchases will show up here.
                  </p>
                </div>

                <div
                  :if={@payments_total > 0}
                  class="flex items-center justify-between border-t border-zinc-200 pt-4 mt-6"
                >
                  <div class="flex items-center space-x-2">
                    <.button :if={@payments_page > 1} phx-click="prev-payments-page">
                      <.icon name="hero-chevron-left" class="w-4 h-4 me-1" />
                      Previous
                    </.button>
                  </div>

                  <div class="text-sm text-zinc-600">
                    Page {@payments_page} of {@payments_total_pages}
                  </div>

                  <div class="flex items-center space-x-2">
                    <.button
                      :if={@payments_page < @payments_total_pages}
                      phx-click="next-payments-page"
                    >
                      Next <.icon name="hero-chevron-right" class="w-4 h-4 ms-1" />
                    </.button>
                  </div>
                </div>
              </div>
              <%!-- End of loading wrapper --%>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Handle retry invoice payment from email link
    socket =
      if params["retry_invoice"] && connected?(socket) do
        invoice_id = params["retry_invoice"]
        # Trigger the retry via an event to ensure proper error handling
        send(self(), {:retry_invoice_payment, invoice_id})
        socket
      else
        socket
      end

    # Restore pending_email from a signed token so a page refresh during the
    # email-verification step does not lose the flow. The email is stored in a
    # signed Phoenix.Token in the URL rather than in plaintext, keeping it out
    # of browser history and server logs.
    socket =
      if socket.assigns[:live_action] == :email_verification do
        cond do
          not is_nil(socket.assigns[:pending_email]) ->
            # Already in memory from the initial push_patch — nothing to do.
            socket

          is_binary(params["etok"]) ->
            case Phoenix.Token.verify(
                   YscWeb.Endpoint,
                   @email_verification_token_salt,
                   params["etok"],
                   max_age: @email_verification_token_max_age
                 ) do
              {:ok, email} when is_binary(email) ->
                socket
                |> assign(:pending_email, email)
                |> assign(:pending_email_token, params["etok"])
                |> assign(:email_verification_code_state, %{})

              _ ->
                socket
                |> push_patch(to: ~p"/users/settings")
                |> YscWeb.Flash.put_toast(
                  :error,
                  "Verification link expired. Please request a new email verification code.",
                  title: "Email"
                )
            end

          true ->
            # No token and no pending_email in assigns — redirect to settings.
            push_patch(socket, to: ~p"/users/settings")
        end
      else
        socket
      end

    # Restore pending_phone_number from signed token so reload on phone-verification keeps modal working
    socket =
      if socket.assigns[:live_action] == :phone_verification && params["token"] do
        case Phoenix.Token.verify(
               YscWeb.Endpoint,
               @phone_verification_token_salt,
               params["token"],
               max_age: @phone_verification_token_max_age
             ) do
          {:ok, phone} when is_binary(phone) ->
            socket
            |> assign(:pending_phone_number, phone)
            |> assign(:phone_verification_code_state, %{})

          _ ->
            socket
            |> push_patch(to: ~p"/users/settings")
            |> YscWeb.Flash.put_toast(
              :error,
              "Verification link expired. Please change your phone number again to get a new code.",
              title: "Phone"
            )
        end
      else
        socket
      end

    # After OAuth reauth, restore the pending email/phone change and continue
    # (or re-open the reauth modal if verification failed).
    socket = maybe_resume_oauth_reauth(socket, params)

    {:noreply, socket}
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    # Only process the token on WebSocket connection, not on the dead render.
    # If processed on both, the token is consumed on the dead render and the
    # WebSocket mount would always see it as expired, showing two conflicting toasts.
    socket =
      if connected?(socket) do
        case Accounts.update_user_email(socket.assigns.current_user, token) do
          {:ok, updated_user, new_email} ->
            old_email = socket.assigns.current_user.email

            UserNotifier.deliver_email_changed_notification(
              updated_user,
              old_email,
              new_email
            )

            YscWeb.Flash.put_toast(socket, :info, "Email changed successfully.",
              title: "Email",
              icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
            )

          :error ->
            YscWeb.Flash.put_toast(
              socket,
              :error,
              "Email change link is invalid or it has expired.",
              title: "Email"
            )
        end
      else
        socket
      end

    {:ok, push_patch(socket, to: ~p"/users/settings")}
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    live_action = socket.assigns[:live_action] || :edit

    # This is all very dumb, but it's just a quick way to get the current membership status
    current_membership = socket.assigns.current_membership
    active_plan = get_membership_plan(current_membership)

    # Check if user is active to determine if they can manage membership
    user_is_active = user.state == :active

    # Check if user is a sub-account and get primary user info
    is_sub_account = Accounts.sub_account?(user)

    membership_plans = Application.get_env(:ysc, :membership_plans)
    public_key = Application.get_env(:stripity_stripe, :public_key)

    # Timezone from browser for date inputs (e.g. date of birth max = today in user TZ)
    connect_params = get_connect_params(socket) || %{}
    timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

    today_max =
      timezone
      |> DateTime.now!()
      |> DateTime.to_date()
      |> Date.to_iso8601()

    # Basic changesets that don't require DB queries (use existing user data)
    email_changeset = Accounts.change_user_email(user)
    profile_changeset = Accounts.change_user_profile(user)

    # Newsletter + pending family invites are loaded in `:load_settings_data` so the
    # dead render skips two DB round-trips (see `handle_info/2` for `:load_settings_data`).
    notification_changeset =
      Accounts.change_notification_preferences(user, %{
        "newsletter_notifications" => false
      })

    pending_family_invites = []

    # Base socket assigns that don't require expensive queries
    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(
        :meta_description,
        "Manage your Young Scandinavians Club account settings, profile, and preferences."
      )
      |> assign(:timezone, timezone)
      |> assign(:today_max, today_max)
      |> assign(:user, user)
      |> assign(:user_is_active, user_is_active)
      |> assign(:is_sub_account, is_sub_account)
      |> assign(:primary_user, nil)
      |> assign(:payment_intent_secret, nil)
      |> assign(:stripe_billing_details, "{}")
      |> assign(:public_key, public_key)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:change_membership_button, false)
      |> assign(:membership_change_info, nil)
      |> assign(:show_reauth_modal, false)
      |> assign(:reauth_verified_at, nil)
      |> assign(:reauth_purpose, nil)
      |> assign(:reauth_resume_handled, false)
      |> assign(:pending_email_change, nil)
      |> assign(:pending_phone_change, nil)
      |> assign(:pending_profile_params, nil)
      |> assign(:user_has_password, !is_nil(user.hashed_password))
      # Placeholder values for async-loaded data
      |> assign(:default_payment_method, nil)
      |> assign(:all_payment_methods, [])
      |> assign(:loading_payment_methods, true)
      |> assign(:show_new_payment_form, false)
      |> assign(:selecting_payment_method, false)
      |> assign(:membership_plans, membership_plans)
      |> assign(:scheduled_downgrade_info, nil)
      |> assign(:active_plan_type, active_plan)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:profile_form, to_form(profile_changeset))
      |> assign(:notification_form, to_form(notification_changeset))
      |> assign(:pending_family_invites, pending_family_invites)
      # Address form placeholder — billing_address is loaded in `:load_settings_data`
      |> assign(:address_form, to_form(empty_billing_address_changeset(user)))
      |> assign(
        :membership_form,
        to_form(%{"membership_type" => nil})
      )
      |> assign(:phone_verification_form, to_form(%{"verification_code" => ""}))
      |> assign(:phone_verification_code_state, %{})
      |> assign(:sms_resend_disabled_until, nil)
      |> assign(:pending_phone_number, nil)
      |> assign(:phone_code_valid, false)
      |> assign(:phone_verification_error, nil)
      |> assign(:email_verification_form, to_form(%{"verification_code" => ""}))
      |> assign(:email_verification_code_state, %{})
      |> assign(:email_resend_disabled_until, nil)
      |> assign(:pending_email, nil)
      |> assign(:pending_email_token, nil)
      |> assign(:email_code_valid, false)
      |> assign(:email_verification_error, nil)
      |> assign(:show_membership_qr, false)
      |> assign(:membership_qr_token, nil)
      |> assign(:membership_qr_details, nil)
      |> assign(:membership_paused_by_board, nil)
      |> assign(
        :apple_wallet_membership_enabled?,
        Ysc.AppleWallet.configured?(:membership)
      )
      |> assign(
        :google_wallet_membership_enabled?,
        GoogleWallet.configured?(:membership)
      )
      |> assign(:google_wallet_membership_url, nil)
      |> assign(:wallet_platform, wallet_platform_from_params(socket))
      |> assign(:user_avatars, [])
      |> assign(:current_avatar_url, nil)
      |> assign(:avatar_processing, false)
      |> assign(:selecting_avatar_id, nil)
      |> assign(:loading_avatars, true)
      |> assign(:loading_notification_preferences, true)
      |> allow_upload(:avatar,
        accept: ~w(.jpg .jpeg .png .webp .gif),
        max_entries: 1,
        max_file_size: 10_000_000,
        external: fn entry, socket ->
          YscWeb.AvatarUpload.presign(
            entry,
            socket,
            socket.assigns.current_user
          )
        end,
        auto_upload: true
      )

    # Payments tab assigns (placeholders for initial render)
    socket =
      if live_action == :payments do
        socket
        |> assign(:payments_page, 1)
        |> assign(:payments_per_page, 20)
        |> assign(:payments_total, 0)
        |> assign(:payments_total_pages, 0)
        |> assign(:all_payments, [])
        |> stream(:payments, [], dom_id: &payment_dom_id/1)
        |> assign(:payment_filter, :all)
        |> assign(:filtered_payments_count, 0)
        |> assign(:filtered_payments_list, [])
        |> assign(:loading_payments, true)
        |> assign(:booking_entitlements_count, 0)
        |> assign(:ticket_reservations_count, 0)
        |> stream(:booking_entitlements, [],
          dom_id: &booking_entitlement_dom_id/1
        )
        |> stream(:ticket_reservations, [],
          dom_id: &ticket_reservation_dom_id/1
        )
      else
        socket
      end

    # Schedule data loading only when connected (stateful mount)
    # This keeps the initial static render fast
    if connected?(socket) do
      send(self(), :load_settings_data)
      Ysc.Subscriptions.subscribe_membership_updates(user.id)
      Ysc.Avatars.subscribe_avatar_updates(user.id)

      if live_action == :payments do
        send(self(), :load_payments_data)
      end
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:avatar_processed, _user_id}, socket) do
    user =
      Ysc.Repo.get!(Ysc.Accounts.User, socket.assigns.current_user.id)
      |> Ysc.Repo.preload(:current_avatar)

    {:noreply,
     socket
     |> assign(:current_user, user)
     |> assign(:user, user)
     |> assign(:user_avatars, load_user_avatars(user))
     |> assign(:current_avatar_url, resolve_current_avatar_url(user))
     |> assign(:avatar_processing, false)}
  end

  @impl true
  def handle_info(:load_settings_data, socket) do
    socket =
      try do
        user = socket.assigns.current_user
        live_action = socket.assigns[:live_action] || :edit

        # Ensure Stripe customer exists - create if missing or invalid
        user = ensure_stripe_customer_exists(user)
        # Reload user with billing_address after ensure_stripe_customer_exists
        user = Repo.preload(user, :billing_address)

        # Load payment methods
        all_payment_methods =
          Ysc.Payments.list_payment_methods(user)
          |> Enum.sort_by(fn pm -> {!pm.is_default, pm.inserted_at} end)

        default_payment_method = Enum.find(all_payment_methods, & &1.is_default)

        # Get membership type from current or past subscriptions
        membership_type_to_select = get_membership_type_for_selection(user)

        # Get primary user if sub-account
        primary_user =
          if socket.assigns.is_sub_account,
            do: Accounts.get_primary_user(user),
            else: nil

        # Rebuild address changeset with loaded billing_address
        address_changeset = Accounts.change_billing_address(user)

        # Fetch scheduled downgrade info from Stripe (if user has membership with schedule)
        scheduled_downgrade_info =
          case socket.assigns.current_membership do
            nil -> nil
            membership -> Subscriptions.get_scheduled_downgrade_info(membership)
          end

        payment_intent_secret = payment_secret(live_action, user)

        # Auto-show the new payment form when the modal opens with no existing methods
        show_new_payment_form =
          live_action == :payment_method && all_payment_methods == [] &&
            not is_nil(payment_intent_secret)

        board_member = Accounts.household_board_member(user)

        effective_newsletter =
          case Newsletter.get_subscriber_by_email(user.email) do
            nil -> false
            subscriber -> subscriber.subscribed
          end

        notification_changeset =
          Accounts.change_notification_preferences(user, %{
            "newsletter_notifications" => effective_newsletter
          })

        pending_family_invites =
          FamilyInvites.list_pending_invites_for_email(user.email)

        socket
        |> assign(:user, user)
        |> assign(
          :stripe_billing_details,
          Ysc.Customers.payment_element_default_values_json(user)
        )
        |> assign(:scheduled_downgrade_info, scheduled_downgrade_info)
        |> assign(:primary_user, primary_user)
        |> assign(:membership_paused_by_board, board_member)
        |> assign(:payment_intent_secret, payment_intent_secret)
        |> assign(:default_payment_method, default_payment_method)
        |> assign(:all_payment_methods, all_payment_methods)
        |> assign(:show_new_payment_form, show_new_payment_form)
        |> assign(:address_form, to_form(address_changeset))
        |> assign(
          :membership_form,
          to_form(%{"membership_type" => membership_type_to_select})
        )
        |> assign(:notification_form, to_form(notification_changeset))
        |> assign(:pending_family_invites, pending_family_invites)
        |> assign(:user_avatars, load_user_avatars(user))
        |> assign(:current_avatar_url, resolve_current_avatar_url(user))
      rescue
        error ->
          Ysc.Logging.warning("Failed to load user settings async data",
            error: Exception.message(error)
          )

          socket
      end

    {:noreply,
     socket
     |> assign(:loading_payment_methods, false)
     |> assign(:loading_notification_preferences, false)
     |> assign(:loading_avatars, false)}
  end

  # Handle async data loading for payments tab
  def handle_info(:load_payments_data, socket) do
    socket =
      try do
        user = socket.assigns.user
        per_page = socket.assigns.payments_per_page

        parallel =
          [
            {:payments,
             fn ->
               Ledgers.list_user_payments_paginated(user.id, 1, per_page)
             end},
            {:entitlements,
             fn -> Entitlements.list_usable_for_user(user.id) end},
            {:reservations,
             fn -> Events.list_active_ticket_holds_for_user(user.id) end}
          ]
          |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
            max_concurrency: 3,
            timeout: :infinity
          )
          |> Enum.reduce(%{}, fn
            {:ok, {key, value}}, acc -> Map.put(acc, key, value)
            {:exit, _reason}, acc -> acc
          end)

        {all_payments, total_count} =
          Map.get(parallel, :payments, {[], 0})

        booking_entitlements = Map.get(parallel, :entitlements, [])
        ticket_reservations = Map.get(parallel, :reservations, [])

        total_pages = div(total_count + per_page - 1, per_page)

        socket
        |> assign(:payments_total, total_count)
        |> assign(:payments_total_pages, total_pages)
        |> assign(:all_payments, all_payments)
        |> stream(:payments, all_payments,
          reset: true,
          dom_id: &payment_dom_id/1
        )
        |> assign(:filtered_payments_count, length(all_payments))
        |> assign(:filtered_payments_list, all_payments)
        |> assign(:booking_entitlements_count, length(booking_entitlements))
        |> assign(:ticket_reservations_count, length(ticket_reservations))
        |> stream(:booking_entitlements, booking_entitlements,
          reset: true,
          dom_id: &booking_entitlement_dom_id/1
        )
        |> stream(:ticket_reservations, ticket_reservations,
          reset: true,
          dom_id: &ticket_reservation_dom_id/1
        )
      rescue
        error ->
          Ysc.Logging.warning("Failed to load payment history async data",
            error: Exception.message(error)
          )

          socket
      end

    {:noreply, assign(socket, :loading_payments, false)}
  end

  def handle_info(
        {Ysc.Subscriptions,
         %Ysc.MessagePassingEvents.MembershipUpdated{user_id: user_id}},
        socket
      ) do
    if socket.assigns.user.id == user_id do
      {:noreply,
       socket
       |> reload_membership_data()
       |> YscWeb.Flash.put_toast(:info, "Your membership has been updated.",
         title: "Membership"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:retry_invoice_payment, invoice_id}, socket) do
    handle_retry_invoice_payment(socket, invoice_id)
  end

  def handle_info({:refresh_payment_methods, user_id}, socket) do
    if socket.assigns.user.id == user_id do
      user = socket.assigns.user

      # Use the new sync function to ensure we're in sync with Stripe
      {:ok, updated_payment_methods} =
        Ysc.Payments.sync_payment_methods_with_stripe(user)

      updated_default = Ysc.Payments.get_default_payment_method(user)

      require Ysc.Logging

      Ysc.Logging.info("Refreshed payment methods after selection",
        user_id: user.id,
        payment_methods_count: length(updated_payment_methods),
        default_payment_method_id: updated_default && updated_default.id
      )

      {:noreply,
       socket
       |> assign(:all_payment_methods, updated_payment_methods)
       |> assign(:default_payment_method, updated_default)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:reauth_verified, socket) do
    socket =
      case socket.assigns[:reauth_purpose] do
        :phone_change -> process_phone_change_after_reauth(socket)
        _ -> process_email_change_after_reauth(socket)
      end

    {:noreply, socket}
  end

  def handle_info(:reauth_cancelled, socket) do
    {:noreply,
     socket
     |> assign(:show_reauth_modal, false)
     |> assign(:pending_email_change, nil)
     |> assign(:pending_phone_change, nil)
     |> assign(:pending_profile_params, nil)
     |> assign(:reauth_purpose, nil)}
  end

  # Catch-all for messages we don't need to handle (like email deliveries in tests)
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("request_email_change", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user
    new_email = user_params["email"]

    if new_email != user.email do
      changeset =
        user
        |> Accounts.change_user_email(user_params)
        |> Map.put(:action, :validate)

      if changeset.valid? do
        socket =
          socket
          |> assign(:pending_email_change, new_email)
          |> assign(:reauth_purpose, :email_change)

        if reauth_still_valid?(socket) do
          {:noreply, process_email_change_after_reauth(socket)}
        else
          {:noreply, assign(socket, :show_reauth_modal, true)}
        end
      else
        {:noreply, assign(socket, :email_form, to_form(changeset))}
      end
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :info,
         "That is already your email address.",
         title: "Email"
       )}
    end
  end

  # PasskeyAuth hook sends these events to the LiveView (via pushEvent, not pushEventTo)
  def handle_event("passkey_support_detected", _params, socket),
    do: {:noreply, socket}

  def handle_event("user_agent_received", _params, socket),
    do: {:noreply, socket}

  def handle_event("device_detected", _params, socket), do: {:noreply, socket}

  def handle_event(
        "wallet_platform_detected",
        %{"platform" => platform},
        socket
      ) do
    platform_atom =
      case platform do
        "apple_only" -> :apple_only
        "google_only" -> :google_only
        _ -> :both
      end

    {:noreply, assign(socket, :wallet_platform, platform_atom)}
  end

  def handle_event("validate_profile", params, socket) do
    %{"user" => user_params} = params

    profile_form =
      socket.assigns.current_user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  # Avatar upload: auto-consumed after presigned upload completes
  def handle_event("validate_avatar", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save_avatar", _params, socket) do
    user = socket.assigns.current_user
    uploaded_outcomes = YscWeb.AvatarUpload.consume(socket, user)

    socket =
      cond do
        YscWeb.AvatarUpload.upload_succeeded?(uploaded_outcomes) ->
          socket
          |> YscWeb.Flash.put_toast(
            :info,
            "Photo uploaded! It will be ready shortly.",
            title: "Profile Picture"
          )
          |> assign(:user_avatars, load_user_avatars(user))
          |> assign(:avatar_processing, true)

        YscWeb.AvatarUpload.upload_failed?(uploaded_outcomes) ->
          YscWeb.Flash.put_toast(
            socket,
            :error,
            "Could not upload profile picture. Please try again.",
            title: "Profile Picture"
          )

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("select_avatar", %{"id" => avatar_id}, socket) do
    user = socket.assigns.current_user
    socket = assign(socket, :selecting_avatar_id, avatar_id)

    case Avatars.set_current_avatar(user, avatar_id) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:selecting_avatar_id, nil)
         |> assign(:user, updated_user)
         |> assign(
           :current_avatar_url,
           resolve_current_avatar_url(updated_user)
         )
         |> YscWeb.Flash.put_toast(:info, "Profile picture updated.",
           title: "Profile Picture"
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:selecting_avatar_id, nil)
         |> YscWeb.Flash.put_toast(
           :error,
           "Could not update profile picture.",
           title: "Profile Picture"
         )}
    end
  end

  def handle_event("update_profile", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    # Check if phone number is being changed
    current_phone = user.phone_number
    new_phone = user_params["phone_number"]

    if new_phone != current_phone and new_phone != "" and not is_nil(new_phone) do
      other_params = Map.delete(user_params, "phone_number")

      socket =
        socket
        |> assign(:pending_phone_change, new_phone)
        |> assign(:pending_profile_params, other_params)
        |> assign(:reauth_purpose, :phone_change)

      if reauth_still_valid?(socket) do
        {:noreply, process_phone_change_after_reauth(socket)}
      else
        {:noreply, assign(socket, :show_reauth_modal, true)}
      end
    else
      # No phone change or phone is being cleared - normal update
      case Accounts.update_user_profile(user, user_params) do
        {:ok, updated_user} ->
          profile_form =
            Accounts.change_user_profile(updated_user, user_params) |> to_form()

          {:noreply,
           socket
           |> assign(:user, updated_user)
           |> assign(
             :stripe_billing_details,
             Ysc.Customers.payment_element_default_values_json(updated_user)
           )
           |> assign(:profile_form, profile_form)
           |> YscWeb.Flash.put_toast(:info, "Profile updated successfully.",
             title: "Profile"
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, profile_form: to_form(changeset))}
      end
    end
  end

  def handle_event(
        "validate_phone_code",
        %{"verification_code" => code},
        socket
      ) do
    # Only allow phone code validation if user has pending phone verification
    pending_phone = socket.assigns.pending_phone_number

    if pending_phone do
      # Accumulate digits in a dedicated assign (phx-input may send only the changed
      # field, or some inputs can be sent as _unused_ until focused)
      current_code = socket.assigns[:phone_verification_code_state] || %{}
      current_code = if is_map(current_code), do: current_code, else: %{}

      merged_code =
        if is_map(code) do
          Map.merge(current_code, code)
        else
          code
        end

      normalized_code = normalize_verification_code(merged_code)

      {:noreply,
       socket
       |> assign(
         phone_code_valid: VerificationCodes.valid_otp_format?(normalized_code),
         phone_verification_error: nil
       )
       |> assign(phone_verification_code_state: merged_code)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("verify_phone_code", params, socket) do
    pending_phone = socket.assigns.pending_phone_number
    user = socket.assigns.current_user

    if pending_phone do
      case params do
        %{"verification_code" => entered_code} ->
          code = normalize_verification_code(entered_code)

          case VerificationCodes.verify(user, :phone, code) do
            {:ok, :verified} ->
              apply_verified_phone_change(socket, user, pending_phone)

            {:error, :rate_limited} ->
              {:noreply,
               socket
               |> assign(
                 :phone_verification_error,
                 "Too many verification attempts. Please wait a minute and try again."
               )}

            {:error, reason} ->
              {:noreply,
               assign(
                 socket,
                 :phone_verification_error,
                 verification_error_message(reason)
               )}
          end

        _ ->
          {:noreply,
           socket
           |> assign(
             :phone_verification_error,
             "Please enter a verification code."
           )}
      end
    else
      {:noreply,
       assign(
         socket,
         :phone_verification_error,
         "No phone verification in progress."
       )}
    end
  end

  def handle_event("resend_phone_code", _params, socket) do
    pending_phone = socket.assigns.pending_phone_number
    user = socket.assigns.current_user

    if pending_phone do
      case VerificationCodes.resend(user, :phone, to: pending_phone) do
        {:ok, %{disabled_until: disabled_until}} ->
          {:noreply,
           socket
           |> assign(:sms_resend_disabled_until, disabled_until)
           |> YscWeb.Flash.put_toast(
             :info,
             "Verification code sent to your phone.",
             title: "Phone",
             icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
           )}

        {:error, :rate_limited, _remaining} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Please wait before requesting another verification code.",
             title: "Phone"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "validate_email_code",
        %{"verification_code" => code},
        socket
      ) do
    # Only allow email code validation if user has pending email verification
    pending_email = socket.assigns.pending_email

    if pending_email do
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

      {:noreply,
       socket
       |> assign(
         email_code_valid: VerificationCodes.valid_otp_format?(normalized_code),
         email_verification_error: nil
       )
       |> assign(:email_verification_code_state, merged_code)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("verify_email_code", params, socket) do
    pending_email = socket.assigns.pending_email
    user = socket.assigns.current_user

    if pending_email do
      case params do
        %{"verification_code" => entered_code} ->
          code = normalize_verification_code(entered_code)

          case VerificationCodes.verify(user, :email, code) do
            {:ok, :verified} ->
              apply_verified_email_change(socket, user, pending_email)

            {:error, :rate_limited} ->
              {:noreply,
               socket
               |> assign(
                 :email_verification_error,
                 "Too many verification attempts. Please wait a minute and try again."
               )}

            {:error, reason} ->
              {:noreply,
               assign(
                 socket,
                 :email_verification_error,
                 verification_error_message(reason)
               )}
          end

        _ ->
          {:noreply,
           assign(
             socket,
             :email_verification_error,
             "Please enter a verification code."
           )}
      end
    else
      {:noreply,
       assign(
         socket,
         :email_verification_error,
         "No email verification in progress."
       )}
    end
  end

  def handle_event("resend_email_code", _params, socket) do
    pending_email = socket.assigns.pending_email
    user = socket.assigns.current_user

    if pending_email do
      case VerificationCodes.resend(user, :email, to: pending_email) do
        {:ok, %{disabled_until: disabled_until}} ->
          {:noreply,
           socket
           |> assign(:email_resend_disabled_until, disabled_until)
           |> YscWeb.Flash.put_toast(
             :info,
             "Verification code sent to your email.",
             title: "Email",
             icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
           )}

        {:error, :rate_limited, _remaining} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Please wait before requesting another verification code.",
             title: "Email"
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_cancel_email_verification", _params, socket) do
    # Show confirmation before closing the email verification modal
    # The user might accidentally click outside while looking for their email
    if socket.assigns.pending_email do
      {:noreply,
       socket
       |> push_event("confirm_close_modal", %{
         title: "Close verification?",
         message:
           "Your verification code is still valid. You can resume verification later from your settings page.",
         confirm_text: "Close",
         cancel_text: "Stay here",
         on_confirm: "cancel_email_verification_confirmed"
       })}
    else
      # No pending email, just navigate away
      {:noreply, push_patch(socket, to: ~p"/users/settings")}
    end
  end

  def handle_event("cancel_email_verification_confirmed", _params, socket) do
    # User confirmed they want to close the modal
    {:noreply,
     socket
     |> assign(:email_verification_code_state, %{})
     |> push_patch(to: ~p"/users/settings")}
  end

  def handle_event("confirm_cancel_phone_verification", _params, socket) do
    # Show confirmation before closing the phone verification modal
    if socket.assigns.pending_phone_number do
      {:noreply,
       socket
       |> push_event("confirm_close_modal", %{
         title: "Close verification?",
         message:
           "Your verification code is still valid. You can resume verification later from your settings page.",
         confirm_text: "Close",
         cancel_text: "Stay here",
         on_confirm: "cancel_phone_verification_confirmed"
       })}
    else
      # No pending phone, just navigate away
      {:noreply, push_patch(socket, to: ~p"/users/settings")}
    end
  end

  def handle_event("cancel_phone_verification_confirmed", _params, socket) do
    # User confirmed they want to close the modal
    {:noreply,
     socket
     |> assign(:phone_verification_code_state, %{})
     |> push_patch(to: ~p"/users/settings")}
  end

  def handle_event("validate_notifications", _params, socket)
      when socket.assigns.loading_notification_preferences do
    {:noreply, socket}
  end

  def handle_event("validate_notifications", params, socket) do
    %{"user" => user_params} = params

    notification_form =
      socket.assigns.current_user
      |> Accounts.change_notification_preferences(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, notification_form: notification_form)}
  end

  def handle_event("update_notifications", _params, socket)
      when socket.assigns.loading_notification_preferences do
    {:noreply, socket}
  end

  def handle_event("update_notifications", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    # Ensure account_notifications is always true
    user_params = Map.put(user_params, "account_notifications", "true")

    case Accounts.update_notification_preferences(user, user_params) do
      {:ok, updated_user} ->
        newsletter_subscribed =
          parse_newsletter_param(user_params["newsletter_notifications"])

        Newsletter.sync_user_preference(updated_user,
          newsletter_subscribed: newsletter_subscribed
        )

        notification_form =
          Accounts.change_notification_preferences(updated_user, user_params)
          |> to_form()

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:notification_form, notification_form)
         |> YscWeb.Flash.put_toast(
           :info,
           "Notification preferences updated successfully.",
           title: "Notifications"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, notification_form: to_form(changeset))}
    end
  end

  def handle_event("validate_address", params, socket) do
    %{"address" => address_params} = params
    user = socket.assigns.current_user

    address_form =
      user
      |> Accounts.change_billing_address(address_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, address_form: address_form)}
  end

  def handle_event("update_address", params, socket) do
    %{"address" => address_params} = params
    user = socket.assigns.current_user

    case Accounts.update_billing_address(user, address_params) do
      {:ok, _address} ->
        # Reload user with updated address
        updated_user = Accounts.get_user!(user.id, [:billing_address])

        address_form =
          Accounts.change_billing_address(updated_user) |> to_form()

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(
           :stripe_billing_details,
           Ysc.Customers.payment_element_default_values_json(updated_user)
         )
         |> assign(:address_form, address_form)
         |> YscWeb.Flash.put_toast(
           :info,
           "Billing address updated successfully.",
           title: "Billing"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, address_form: to_form(changeset))}
    end
  end

  @dialyzer {:nowarn_function, handle_event: 3}
  def handle_event(
        "select_membership",
        %{"membership_type" => membership_type} = _params,
        socket
      ) do
    user = socket.assigns.user

    user =
      Accounts.get_user!(user.id)
      |> Accounts.User.populate_virtual_fields()

    if user.state != :active do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You must have an approved account to manage your membership plan.",
         title: "Membership"
       )}
    else
      if Accounts.sub_account?(user) do
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You're on a family membership and can't purchase a separate plan. Ask your family membership manager to make membership changes.",
           title: "Membership"
         )}
      else
        membership_atom = String.to_existing_atom(membership_type)
        return_url = url(~p"/billing/user/#{user.id}/finalize")
        price_id = get_price_id(membership_atom)
        default_payment_method = socket.assigns.default_payment_method

        case Customers.create_subscription(
               user,
               return_url: return_url,
               prices: [%{price: price_id, quantity: 1}],
               default_payment_method: default_payment_method.provider_id,
               expand: ["latest_invoice"]
             ) do
          {:ok, stripe_subscription} ->
            # Also save the subscription locally as a backup in case webhook fails
            case Ysc.Subscriptions.create_subscription_from_stripe(
                   user,
                   stripe_subscription
                 ) do
              {:ok, _local_subscription} ->
                # Invalidate membership cache when new subscription is created
                MembershipCache.invalidate_user(user.id)

                # Also invalidate for sub-accounts since they inherit from primary user
                sub_accounts = Accounts.get_sub_accounts(user)

                Enum.each(sub_accounts, fn sub_account ->
                  MembershipCache.invalidate_user(sub_account.id)
                end)

                {:noreply,
                 socket
                 |> YscWeb.Flash.put_toast(
                   :info,
                   "Membership activated successfully!",
                   title: "Membership"
                 )
                 |> push_patch(to: ~p"/users/membership")}

              {:error, reason} ->
                require Ysc.Logging

                Ysc.Logging.warning(
                  "Failed to save subscription locally, webhook should handle it",
                  user_id: user.id,
                  stripe_subscription_id: stripe_subscription.id,
                  error: reason
                )

                # Invalidate cache even if local save failed (webhook will update it)
                MembershipCache.invalidate_user(user.id)
                sub_accounts = Accounts.get_sub_accounts(user)

                Enum.each(sub_accounts, fn sub_account ->
                  MembershipCache.invalidate_user(sub_account.id)
                end)

                {:noreply,
                 socket
                 |> YscWeb.Flash.put_toast(
                   :info,
                   "Membership activated successfully!",
                   title: "Membership"
                 )
                 |> push_patch(to: ~p"/users/membership")}
            end

          {:error, :sub_accounts_cannot_create_subscriptions} ->
            {:noreply,
             YscWeb.Flash.put_toast(
               socket,
               :error,
               "You're on a family membership and can't purchase a separate plan. Ask your family membership manager to make membership changes.",
               title: "Membership"
             )}

          {:error, error} ->
            require Ysc.Logging

            Ysc.Logging.error("Failed to create subscription",
              user_id: user.id,
              error: error
            )

            error_message = format_payment_error(error)

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:error, error_message,
               title: "Membership"
             )}
        end
      end
    end
  end

  def handle_event(
        "validate_membership",
        %{"membership_type" => membership_type} = _params,
        socket
      ) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply, socket}
    else
      assigns = socket.assigns
      membership_atom = String.to_existing_atom(membership_type)

      change_membership_button =
        assigns.active_plan_type != nil &&
          assigns.active_plan_type !=
            membership_atom

      # Calculate change information if a different plan is selected
      change_info =
        if change_membership_button && assigns.active_plan_type != nil do
          plans = assigns.membership_plans
          current_plan = Enum.find(plans, &(&1.id == assigns.active_plan_type))
          new_plan = Enum.find(plans, &(&1.id == membership_atom))

          if current_plan && new_plan do
            direction =
              if new_plan.amount > current_plan.amount,
                do: :upgrade,
                else: :downgrade

            price_difference = abs(new_plan.amount - current_plan.amount)

            %{
              direction: direction,
              current_plan: current_plan,
              new_plan: new_plan,
              price_difference: price_difference
            }
          else
            nil
          end
        else
          nil
        end

      {:noreply,
       socket
       |> assign(change_membership_button: change_membership_button)
       |> assign(:membership_change_info, change_info)
       |> assign(
         :membership_form,
         to_form(%{"membership_type" => membership_type})
       )}
    end
  end

  def handle_event(
        "payment-method-set",
        %{"payment_method_id" => payment_method_id},
        socket
      ) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You must have an approved account to update your payment method.",
         title: "Payment"
       )}
    else
      # Retrieve the payment method from Stripe and store it locally
      case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
             stripe_payment_method_module().retrieve(payment_method_id)
           end) do
        {:ok, stripe_payment_method} ->
          _ =
            Ysc.Stripe.RetryHelper.stripe_retry(fn ->
              stripe_payment_method_module().update(payment_method_id, %{
                metadata: %{"set_as_default" => "true"}
              })
            end)

          case Ysc.Payments.upsert_and_set_default_payment_method_from_stripe(
                 user,
                 stripe_payment_method
               ) do
            {:ok, _} ->
              case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
                     stripe_customer_module().update(
                       user.stripe_id,
                       %{
                         invoice_settings: %{
                           default_payment_method: payment_method_id
                         }
                       },
                       []
                     )
                   end) do
                {:ok, _stripe_customer} ->
                  # Reload user and payment methods to get updated info
                  updated_user = Ysc.Accounts.get_user!(user.id)

                  updated_payment_methods =
                    Ysc.Payments.list_payment_methods(updated_user)

                  updated_default =
                    Ysc.Payments.get_default_payment_method(updated_user)

                  {socket, toast_message} =
                    maybe_activate_membership_after_settings_pm(
                      socket,
                      updated_user
                    )

                  updated_user = Ysc.Accounts.get_user!(user.id)

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
                   |> assign(:all_payment_methods, updated_payment_methods)
                   |> assign(:default_payment_method, updated_default)
                   |> assign(:show_new_payment_form, false)
                   |> YscWeb.Flash.put_toast(
                     :info,
                     toast_message,
                     title: "Payment",
                     icon: &YscWeb.CoreComponents.flash_toast_icon_payment/1
                   )
                   |> push_patch(to: ~p"/users/membership")}

                {:error, _stripe_error} ->
                  {:noreply,
                   YscWeb.Flash.put_toast(
                     socket,
                     :error,
                     "We saved your card, but couldn't make it your default. Please try again, or contact us at info@ysc.org if this keeps happening.",
                     title: "Payment"
                   )}
              end

            {:error, _reason} ->
              {:noreply,
               YscWeb.Flash.put_toast(
                 socket,
                 :error,
                 "We couldn't save your card. Please try again, or email info@ysc.org if this keeps happening.",
                 title: "Payment"
               )}
          end

        {:error, _reason} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "We couldn't load your saved payment methods. Please refresh the page or try again in a few minutes.",
             title: "Payment"
           )}
      end
    end
  end

  def handle_event(
        "select-payment-method",
        %{"payment_method_id" => payment_method_id},
        socket
      ) do
    user = socket.assigns.user

    result =
      with :ok <- validate_user_active(user),
           :ok <- validate_not_selecting(socket),
           selected_payment_method <-
             find_payment_method(socket, payment_method_id),
           :ok <- validate_payment_method_exists(selected_payment_method) do
        process_payment_method_selection(
          socket,
          user,
          selected_payment_method,
          payment_method_id
        )
      end

    case result do
      {:noreply, _socket} = reply ->
        reply

      {:error, :user_not_active} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You must have an approved account to update your payment method.",
           title: "Payment"
         )}

      {:error, :already_selecting} ->
        {:noreply, socket}

      {:error, :payment_method_not_found} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Payment method not found.",
           title: "Payment"
         )}
    end
  end

  def handle_event("add-new-payment-method", _params, socket) do
    require Ysc.Logging
    user = socket.assigns.user

    Ysc.Logging.info("Creating setup intent for user",
      user_id: user.id,
      stripe_id: user.stripe_id
    )

    # Ensure user has a Stripe customer ID (reload user if it was just created)
    user = ensure_stripe_customer_exists(user)

    if user.stripe_id == nil do
      Ysc.Logging.error(
        "User still has no stripe_id after ensure_stripe_customer_exists",
        user_id: user.id
      )

      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(
         :error,
         "We couldn't open the secure payment form. Please refresh the page and try again, or email info@ysc.org for help adding your card.",
         title: "Payment"
       )
       |> assign(:show_new_payment_form, false)}
    else
      Ysc.Logging.info("User has stripe_id, creating setup intent",
        user_id: user.id,
        stripe_id: user.stripe_id
      )

      case Customers.create_setup_intent(user,
             stripe: %{
               payment_method_types: ["us_bank_account", "card"]
             }
           ) do
        {:ok, setup_intent} ->
          Ysc.Logging.info("Setup intent created successfully",
            setup_intent_id: setup_intent.id
          )

          {:noreply,
           socket
           |> assign(:user, user)
           |> assign(:show_new_payment_form, true)
           |> assign(:payment_intent_secret, setup_intent.client_secret)}

        {:error, error} ->
          error_message =
            case error do
              %Stripe.Error{message: msg} -> msg
            end

          Ysc.Logging.error("Failed to create setup intent",
            user_id: user.id,
            stripe_id: user.stripe_id,
            error: error_message,
            full_error: inspect(error, pretty: true, limit: :infinity)
          )

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "We couldn't load the payment form. Please try again in a few minutes, or email memberships@ysc.org and we'll help you add a card.",
             title: "Payment"
           )
           |> assign(:show_new_payment_form, false)}
      end
    end
  end

  def handle_event("cancel-new-payment-method", _params, socket) do
    {:noreply, assign(socket, :show_new_payment_form, false)}
  end

  def handle_event("refresh-payment-methods", _params, socket) do
    user = socket.assigns.user

    # Use the new sync function to ensure we're in sync with Stripe
    {:ok, updated_payment_methods} =
      Ysc.Payments.sync_payment_methods_with_stripe(user)

    updated_default = Ysc.Payments.get_default_payment_method(user)

    {:noreply,
     socket
     |> assign(:all_payment_methods, updated_payment_methods)
     |> assign(:default_payment_method, updated_default)}
  end

  def handle_event(
        "retry-invoice-payment",
        %{"invoice_id" => invoice_id},
        socket
      ) do
    handle_retry_invoice_payment(socket, invoice_id)
  end

  def handle_event(
        "show_membership_qr",
        _params,
        %{
          assigns: %{
            current_user: %{} = user,
            current_membership: %{} = _membership
          }
        } =
          socket
      ) do
    token = Ysc.Scanning.QrToken.sign_membership(user.id)
    details = build_membership_qr_details(socket.assigns)

    google_wallet_url =
      if socket.assigns.google_wallet_membership_enabled? do
        case GoogleWallet.generate_membership_save_url(user) do
          {:ok, url} -> url
          _ -> nil
        end
      end

    {:noreply,
     socket
     |> assign(:show_membership_qr, true)
     |> assign(:membership_qr_token, token)
     |> assign(:membership_qr_details, details)
     |> assign(:google_wallet_membership_url, google_wallet_url)}
  end

  def handle_event("show_membership_qr", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("hide_membership_qr", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_membership_qr, false)
     |> assign(:membership_qr_token, nil)
     |> assign(:membership_qr_details, nil)}
  end

  def handle_event("leave-family-membership", _params, socket) do
    user = socket.assigns.user

    case Accounts.leave_family_membership(user) do
      {:ok, _updated_user} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "You have left the family membership. You can purchase your own membership or join another family from this page.",
           title: "Membership"
         )
         |> redirect(to: ~p"/users/membership")}

      {:error, :not_sub_account} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You are not linked to a family membership.",
           title: "Membership"
         )}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Could not leave the family membership. Please try again.",
           title: "Membership"
         )}
    end
  end

  def handle_event("accept-family-invite", %{"token" => token}, socket) do
    user = socket.assigns.user

    case FamilyInvites.link_existing_user(token, user) do
      {:ok, updated_user} ->
        MembershipCache.invalidate_user(user.id)

        socket =
          socket
          |> assign(:user, updated_user)
          |> assign(:is_sub_account, true)
          |> assign(:primary_user, Accounts.get_primary_user(updated_user))
          |> reload_membership_data()
          |> assign(
            :pending_family_invites,
            FamilyInvites.list_pending_invites_for_email(updated_user.email)
          )

        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :info,
           "Invitation accepted. Your account is now linked to the family membership.",
           title: "Membership"
         )}

      {:error, :invite_not_found} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Invitation not found.",
           title: "Membership"
         )}

      {:error, :invite_expired_or_used} ->
        {:noreply,
         socket
         |> assign(
           :pending_family_invites,
           FamilyInvites.list_pending_invites_for_email(user.email)
         )
         |> YscWeb.Flash.put_toast(
           :error,
           "This invitation has expired or has already been used.",
           title: "Membership"
         )}

      {:error, :email_mismatch} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "This invitation was sent to a different email address.",
           title: "Membership"
         )}

      {:error, :already_linked_to_family} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "You can only be linked to one family membership at a time. Leave your current family membership first if you want to join another (use \"Leave family membership\" below).",
           title: "Membership"
         )}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Could not accept this invitation. Please try again.",
           title: "Membership"
         )}
    end
  end

  def handle_event("cancel-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You must have an approved account to manage auto-renewal.",
         title: "Membership"
       )}
    else
      # Turn off auto-renewal at period end in Stripe (membership stays active until then)
      case Subscriptions.cancel(socket.assigns.current_membership) do
        {:ok, _subscription} ->
          # Cache invalidation is handled in Subscriptions.cancel
          # Also invalidate for sub-accounts since they inherit from primary user
          sub_accounts = Accounts.get_sub_accounts(user)

          Enum.each(sub_accounts, fn sub_account ->
            MembershipCache.invalidate_user(sub_account.id)
          end)

          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :info,
             "Auto-renewal is off. You'll keep access until your current membership year ends.",
             title: "Membership"
           )
           |> push_patch(to: ~p"/users/membership")}

        {:error, reason} when is_binary(reason) ->
          {:noreply,
           YscWeb.Flash.put_toast(socket, :error, reason, title: "Membership")}

        {:error, _changeset} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Couldn't turn off auto-renewal. Please try again.",
             title: "Membership"
           )}
      end
    end
  end

  def handle_event("cancel-scheduled-downgrade", _params, socket) do
    case Subscriptions.cancel_scheduled_downgrade(
           socket.assigns.current_membership
         ) do
      {:ok, _subscription} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :info,
           "Plan change cancelled. You'll stay on your current membership.",
           title: "Membership"
         )
         |> push_patch(to: ~p"/users/membership")}

      {:error, :no_scheduled_downgrade} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "There is no plan change scheduled on your account. Your current membership level is already in effect.",
           title: "Membership"
         )
         |> push_patch(to: ~p"/users/membership")}

      {:error, reason} when is_binary(reason) ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, reason, title: "Membership")}

      {:error, _} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :error,
           "Failed to cancel scheduled downgrade. Please try again.",
           title: "Membership"
         )}
    end
  end

  def handle_event("reactivate-membership", _params, socket) do
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You must have an approved account to manage auto-renewal.",
         title: "Membership"
       )}
    else
      case Subscriptions.resume(socket.assigns.current_membership) do
        {:error, reason} ->
          {:noreply,
           YscWeb.Flash.put_toast(socket, :error, reason, title: "Membership")}

        {:ok, _subscription} ->
          # Cache invalidation is handled in Subscriptions.resume (via update_subscription)
          # Also invalidate for sub-accounts since they inherit from primary user
          sub_accounts = Accounts.get_sub_accounts(user)

          Enum.each(sub_accounts, fn sub_account ->
            MembershipCache.invalidate_user(sub_account.id)
          end)

          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :info,
             "Auto-renewal is on. Your membership will renew as usual.",
             title: "Membership"
           )
           |> push_patch(to: ~p"/users/membership")}
      end
    end
  end

  def handle_event("next-payments-page", _, socket) do
    current_page = socket.assigns.payments_page
    total_pages = socket.assigns.payments_total_pages

    if current_page < total_pages do
      {:noreply, paginate_payments(socket, current_page + 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prev-payments-page", _, socket) do
    current_page = socket.assigns.payments_page

    if current_page > 1 do
      {:noreply, paginate_payments(socket, current_page - 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter-payments", %{"filter" => filter}, socket) do
    filter_atom = String.to_existing_atom(filter)

    {:noreply,
     socket
     |> assign(:payment_filter, filter_atom)
     |> assign(:payments_page, 1)
     |> paginate_payments(1)}
  end

  def handle_event("change-membership", params, socket) do
    user = socket.assigns.user

    result =
      with :ok <- validate_user_active_for_membership(user),
           :ok <- validate_membership_type(params, socket),
           current_membership <- socket.assigns.current_membership,
           :ok <- validate_current_membership_exists(current_membership),
           new_type <- get_new_membership_type(params, socket),
           current_type <- get_membership_plan(current_membership),
           new_atom <- String.to_existing_atom(new_type),
           :ok <- validate_membership_change_allowed(current_type, new_atom),
           :ok <- validate_not_same_plan(current_type, new_atom) do
        handle_membership_change(
          socket,
          user,
          current_membership,
          current_type,
          new_atom
        )
      end

    case result do
      {:noreply, _socket} = reply ->
        reply

      {:error, reason} when is_binary(reason) ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, reason, title: "Membership")}
    end
  end

  defp apply_verified_phone_change(socket, user, pending_phone) do
    phone_params = %{"phone_number" => pending_phone}

    case Accounts.update_user_phone_and_sms(user, phone_params) do
      {:ok, updated_user} ->
        {:ok, _} = Accounts.mark_phone_verified(updated_user)

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:current_user, updated_user)
         |> assign(:pending_phone_number, nil)
         |> assign(:phone_verification_code_state, %{})
         |> push_patch(to: ~p"/users/settings")
         |> YscWeb.Flash.put_toast(
           :info,
           "Phone number updated and verified successfully.",
           title: "Phone",
           icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(
           :phone_verification_error,
           "Failed to update phone number. Please try again."
         )}
    end
  end

  defp apply_verified_email_change(socket, user, pending_email) do
    email_params = %{"email" => pending_email}

    case user
         |> Accounts.User.email_changeset(email_params)
         |> Ecto.Changeset.put_change(
           :email_verified_at,
           DateTime.utc_now() |> DateTime.truncate(:second)
         )
         |> Ysc.Repo.update() do
      {:ok, updated_user} ->
        old_email = user.email

        if old_email != updated_user.email do
          UserNotifier.deliver_email_changed_notification(
            updated_user,
            old_email,
            updated_user.email
          )

          Accounts.update_newsletter_on_email_change(
            updated_user,
            old_email,
            updated_user.email
          )
        end

        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:current_user, updated_user)
         |> assign(:pending_email, nil)
         |> assign(:pending_email_token, nil)
         |> assign(:email_verification_code_state, %{})
         |> assign(:current_email, updated_user.email)
         |> push_patch(to: ~p"/users/settings")
         |> YscWeb.Flash.put_toast(
           :info,
           "Email address updated successfully.",
           title: "Email",
           icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
         )}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(
           :email_verification_error,
           "Failed to update email address. Please try again."
         )}
    end
  end

  defp verification_error_message(:not_found),
    do: "No verification code found. Please request a new one."

  defp verification_error_message(:expired),
    do: "Verification code has expired. Please request a new one."

  defp verification_error_message(_),
    do: "Invalid verification code. Please try again."

  defp reload_membership_data(socket) do
    user = Accounts.get_user!(socket.assigns.user.id, [:subscriptions])
    current_membership = MembershipCache.get_active_membership(user)
    active_plan = get_membership_plan(current_membership)

    membership_type_str =
      if active_plan, do: Atom.to_string(active_plan), else: nil

    scheduled_downgrade_info =
      case current_membership do
        nil -> nil
        membership -> Subscriptions.get_scheduled_downgrade_info(membership)
      end

    pending_family_invites =
      FamilyInvites.list_pending_invites_for_email(user.email)

    board_member = Accounts.household_board_member(user)

    socket
    |> assign(:user, user)
    |> assign(:current_membership, current_membership)
    |> assign(:active_plan_type, active_plan)
    |> assign(:scheduled_downgrade_info, scheduled_downgrade_info)
    |> assign(:pending_family_invites, pending_family_invites)
    |> assign(:membership_paused_by_board, board_member)
    |> assign(:change_membership_button, false)
    |> assign(:membership_change_info, nil)
    |> assign(
      :membership_form,
      to_form(%{"membership_type" => membership_type_str})
    )
  end

  defp process_email_change_after_reauth(socket) do
    user = socket.assigns.current_user
    new_email = socket.assigns.pending_email_change

    {:ok, _} =
      VerificationCodes.issue(user, :email,
        to: new_email,
        suffix: "email_change_#{DateTime.utc_now() |> DateTime.to_unix()}"
      )

    # Update form and store pending email
    email_form =
      Accounts.change_user_email(user, %{"email" => new_email}) |> to_form()

    token =
      Phoenix.Token.sign(
        YscWeb.Endpoint,
        @email_verification_token_salt,
        new_email,
        max_age: @email_verification_token_max_age
      )

    path =
      ~p"/users/settings/email-verification"
      |> URI.parse()
      |> Map.put(:query, URI.encode_query(%{"etok" => token}))
      |> URI.to_string()

    socket
    |> assign(:email_form, email_form)
    |> assign(:pending_email, new_email)
    |> assign(:pending_email_token, token)
    |> assign(:show_reauth_modal, false)
    |> assign(:pending_email_change, nil)
    |> assign(:reauth_error, nil)
    |> assign(:reauth_verified_at, DateTime.utc_now())
    |> assign(:reauth_purpose, nil)
    |> assign(:email_verification_error, nil)
    |> assign(:email_code_valid, false)
    |> push_patch(to: path)
  end

  defp process_phone_change_after_reauth(socket) do
    user = socket.assigns.current_user
    new_phone = socket.assigns.pending_phone_change
    other_params = socket.assigns.pending_profile_params || %{}

    case Accounts.update_user_profile(user, other_params) do
      {:ok, updated_user} ->
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        {:ok, _} =
          VerificationCodes.issue(updated_user, :phone,
            to: new_phone,
            suffix: "settings_change_#{timestamp}"
          )

        user_params = Map.put(other_params, "phone_number", new_phone)

        profile_form =
          Accounts.change_user_profile(updated_user, user_params) |> to_form()

        token =
          Phoenix.Token.sign(
            YscWeb.Endpoint,
            @phone_verification_token_salt,
            new_phone,
            max_age: @phone_verification_token_max_age
          )

        path =
          ~p"/users/settings/phone-verification"
          |> URI.parse()
          |> Map.put(:query, URI.encode_query(%{"token" => token}))
          |> URI.to_string()

        socket
        |> assign(:user, updated_user)
        |> assign(:profile_form, profile_form)
        |> assign(:pending_phone_number, new_phone)
        |> assign(:pending_phone_change, nil)
        |> assign(:pending_profile_params, nil)
        |> assign(:phone_verification_code_state, %{})
        |> assign(:show_reauth_modal, false)
        |> assign(:reauth_purpose, nil)
        |> assign(:reauth_verified_at, DateTime.utc_now())
        |> push_patch(to: path)
        |> YscWeb.Flash.put_toast(
          :info,
          "Phone number update initiated. Please verify the code sent to your new number.",
          title: "Phone",
          icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
        )

      {:error, changeset} ->
        socket
        |> assign(:profile_form, to_form(changeset))
        |> assign(:show_reauth_modal, false)
        |> assign(:pending_phone_change, nil)
        |> assign(:pending_profile_params, nil)
        |> assign(:reauth_purpose, nil)
    end
  end

  defp reauth_modal_description(:phone_change) do
    "For security reasons, please verify your identity before changing your phone number."
  end

  defp reauth_modal_description(_) do
    "For security reasons, please verify your identity before changing your email address."
  end

  defp reauth_intent_from_assigns(assigns) do
    case assigns[:reauth_purpose] do
      :phone_change ->
        %{
          "purpose" => "phone_change",
          "phone" => assigns[:pending_phone_change],
          "profile_params" => assigns[:pending_profile_params] || %{}
        }

      :email_change ->
        %{
          "purpose" => "email_change",
          "email" => assigns[:pending_email_change]
        }

      _ ->
        nil
    end
  end

  defp maybe_resume_oauth_reauth(socket, params) do
    # Only resume on the connected LiveView so we don't send verification codes
    # during the dead render, and only once per OAuth return.
    with true <- connected?(socket),
         false <- socket.assigns[:reauth_resume_handled] == true,
         token when is_binary(token) <- params["reauth_resume"],
         {:ok, intent} <- YscWeb.ReauthResume.verify(token) do
      socket =
        socket
        |> assign(:reauth_resume_handled, true)
        |> restore_pending_from_reauth_intent(intent)

      if reauth_still_valid?(socket) do
        case socket.assigns[:reauth_purpose] do
          :phone_change -> process_phone_change_after_reauth(socket)
          :email_change -> process_email_change_after_reauth(socket)
          _ -> assign(socket, :show_reauth_modal, false)
        end
      else
        # OAuth mismatch/cancel still lands here with the resume token — re-open modal.
        assign(socket, :show_reauth_modal, true)
      end
    else
      _ -> socket
    end
  end

  defp restore_pending_from_reauth_intent(
         socket,
         %{"purpose" => "email_change"} = intent
       ) do
    email = intent["email"]

    socket
    |> assign(:pending_email_change, email)
    |> assign(:reauth_purpose, :email_change)
  end

  defp restore_pending_from_reauth_intent(
         socket,
         %{"purpose" => "phone_change"} = intent
       ) do
    phone = intent["phone"]
    profile_params = intent["profile_params"] || %{}

    socket
    |> assign(:pending_phone_change, phone)
    |> assign(:pending_profile_params, profile_params)
    |> assign(:reauth_purpose, :phone_change)
  end

  defp restore_pending_from_reauth_intent(socket, _intent), do: socket

  defp reauth_still_valid?(socket) do
    case socket.assigns[:session_reauth_expires_at] do
      ts when is_integer(ts) -> ts > DateTime.utc_now() |> DateTime.to_unix()
      _ -> false
    end
  end

  defp validate_user_active(user) do
    if user.state == :active, do: :ok, else: {:error, :user_not_active}
  end

  defp maybe_activate_membership_after_settings_pm(socket, user) do
    unpaid_primary? =
      user.state == :active and not Accounts.sub_account?(user) and
        is_nil(MembershipCache.get_active_membership(user))

    if unpaid_primary? do
      return_url = YscWeb.Endpoint.url() <> "/billing/user/#{user.id}/finalize"

      case Subscriptions.activate_membership_with_saved_payment_method(user,
             return_url: return_url
           ) do
        {:ok, status} when status in [:activated, :already_active] ->
          YscWeb.Emails.ApplicationApprovedPaymentSuccess.maybe_schedule(
            user,
            status
          )

          _ = MembershipCache.invalidate_user(user.id)
          refreshed = Accounts.get_user!(user.id)

          membership = MembershipCache.get_active_membership(refreshed)
          plan_type = YscWeb.UserAuth.get_membership_plan_type(membership)

          {socket
           |> assign(:user, refreshed)
           |> assign(:current_membership, membership)
           |> assign(:active_plan_type, plan_type),
           "Payment method saved and your membership is now active!"}

        {:error, _reason} ->
          {socket,
           "Payment method updated. We couldn't activate membership automatically — choose a plan below to finish."}
      end
    else
      {socket, "Payment method updated and set as default."}
    end
  end

  defp validate_user_active_for_membership(user) do
    if user.state == :active do
      :ok
    else
      {:error,
       "You must have an approved account to change your membership plan."}
    end
  end

  defp validate_not_selecting(socket) do
    if socket.assigns.selecting_payment_method,
      do: {:error, :already_selecting},
      else: :ok
  end

  defp find_payment_method(socket, payment_method_id) do
    Enum.find(socket.assigns.all_payment_methods, &(&1.id == payment_method_id))
  end

  defp validate_payment_method_exists(nil),
    do: {:error, :payment_method_not_found}

  defp validate_payment_method_exists(_payment_method), do: :ok

  defp process_payment_method_selection(
         socket,
         user,
         selected_payment_method,
         payment_method_id
       ) do
    require Ysc.Logging

    socket =
      apply_optimistic_update(
        socket,
        selected_payment_method,
        payment_method_id
      )

    Ysc.Logging.info("Setting payment method as default",
      user_id: user.id,
      payment_method_id: selected_payment_method.id,
      provider_id: selected_payment_method.provider_id
    )

    result =
      with {:ok, _} <- set_default_in_database(user, selected_payment_method),
           {:ok, _} <- update_stripe_default(user, selected_payment_method) do
        {:ok, socket}
      end

    case result do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:selecting_payment_method, false)
         |> YscWeb.Flash.put_toast(:info, "Payment method set as default.",
           title: "Payment",
           icon: &YscWeb.CoreComponents.flash_toast_icon_payment/1
         )}

      {:error, :database_error} ->
        handle_database_error(socket)

      {:error, :stripe_error, stripe_error} ->
        handle_stripe_error(socket, stripe_error)
    end
  end

  defp apply_optimistic_update(
         socket,
         selected_payment_method,
         payment_method_id
       ) do
    updated_payment_methods =
      Enum.map(socket.assigns.all_payment_methods, fn pm ->
        if pm.id == payment_method_id do
          pm
          |> Ysc.Payments.PaymentMethod.changeset(%{is_default: true})
          |> Ecto.Changeset.apply_changes()
        else
          pm
          |> Ysc.Payments.PaymentMethod.changeset(%{is_default: false})
          |> Ecto.Changeset.apply_changes()
        end
      end)

    socket
    |> assign(:selecting_payment_method, true)
    |> assign(:all_payment_methods, updated_payment_methods)
    |> assign(:default_payment_method, selected_payment_method)
  end

  defp set_default_in_database(user, selected_payment_method) do
    require Ysc.Logging

    case Ysc.Payments.set_default_payment_method(user, selected_payment_method) do
      {:ok, _} ->
        Ysc.Logging.info(
          "Successfully set payment method as default in database",
          user_id: user.id,
          payment_method_id: selected_payment_method.id
        )

        {:ok, :success}

      {:error, reason} ->
        Ysc.Logging.error("Failed to set payment method as default in database",
          user_id: user.id,
          payment_method_id: selected_payment_method.id,
          reason: inspect(reason)
        )

        {:error, :database_error}
    end
  end

  defp update_stripe_default(user, selected_payment_method) do
    require Ysc.Logging

    Ysc.Logging.info("Updating Stripe customer default payment method",
      user_id: user.id,
      stripe_customer_id: user.stripe_id,
      default_payment_method_id: selected_payment_method.provider_id
    )

    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           stripe_customer_module().update(
             user.stripe_id,
             %{
               invoice_settings: %{
                 default_payment_method: selected_payment_method.provider_id
               }
             },
             []
           )
         end) do
      {:ok, _stripe_customer} ->
        Ysc.Logging.info(
          "Successfully updated Stripe customer default payment method",
          user_id: user.id,
          stripe_customer_id: user.stripe_id
        )

        {:ok, :success}

      {:error, stripe_error} ->
        {:error, :stripe_error, stripe_error}
    end
  end

  defp revert_optimistic_update(socket) do
    original_payment_methods =
      Enum.map(socket.assigns.all_payment_methods, fn pm ->
        if pm.id == socket.assigns.default_payment_method.id do
          pm
          |> Ysc.Payments.PaymentMethod.changeset(%{is_default: true})
          |> Ecto.Changeset.apply_changes()
        else
          pm
          |> Ysc.Payments.PaymentMethod.changeset(%{is_default: false})
          |> Ecto.Changeset.apply_changes()
        end
      end)

    socket
    |> assign(:all_payment_methods, original_payment_methods)
    |> assign(:selecting_payment_method, false)
  end

  defp handle_database_error(socket) do
    {:noreply,
     revert_optimistic_update(socket)
     |> YscWeb.Flash.put_toast(
       :error,
       "Failed to set payment method as default",
       title: "Payment"
     )}
  end

  defp handle_stripe_error(socket, _stripe_error) do
    {:noreply,
     revert_optimistic_update(socket)
     |> YscWeb.Flash.put_toast(
       :error,
       "We couldn't update your default payment method. Please try again, or contact us at info@ysc.org if this keeps happening.",
       title: "Payment"
     )}
  end

  defp validate_membership_type(params, socket) do
    new_type =
      params["membership_type"] ||
        socket.assigns.membership_form.params["membership_type"]

    if is_nil(new_type) or new_type == "" do
      {:error, "Please select a membership type first."}
    else
      :ok
    end
  end

  defp validate_current_membership_exists(nil) do
    {:error, "You do not have an active membership to change."}
  end

  defp validate_current_membership_exists(_), do: :ok

  defp get_new_membership_type(params, socket) do
    params["membership_type"] ||
      socket.assigns.membership_form.params["membership_type"]
  end

  defp validate_membership_change_allowed(:lifetime, _new_atom) do
    {:error, "Lifetime memberships cannot be changed."}
  end

  defp validate_membership_change_allowed(_current_type, :lifetime) do
    {:error, "Lifetime membership can only be awarded by an administrator."}
  end

  defp validate_membership_change_allowed(_current_type, _new_atom), do: :ok

  defp validate_not_same_plan(current_type, new_atom)
       when current_type == new_atom do
    {:error, "You are already on that plan."}
  end

  defp validate_not_same_plan(_current_type, _new_atom), do: :ok

  defp handle_membership_change(
         socket,
         user,
         current_membership,
         current_type,
         new_atom
       ) do
    plans = Application.get_env(:ysc, :membership_plans)
    current_plan = Enum.find(plans, &(&1.id == current_type))
    new_plan = Enum.find(plans, &(&1.id == new_atom))
    new_price_id = new_plan[:stripe_price_id]

    direction =
      if new_plan.amount > current_plan.amount, do: :upgrade, else: :downgrade

    with :ok <- validate_payment_method_for_upgrade(socket, direction),
         :ok <- validate_downgrade_with_sub_accounts(user, direction) do
      process_membership_change(
        socket,
        user,
        current_membership,
        new_price_id,
        direction,
        new_atom
      )
    end
  end

  # Manual (paid elsewhere) memberships have no payment method in Stripe. If we allow
  # upgrade without one, Stripe creates an invoice that cannot be paid and the
  # subscription goes incomplete, which can lead to lost membership in our app.
  defp validate_payment_method_for_upgrade(socket, :upgrade) do
    if socket.assigns[:default_payment_method] do
      :ok
    else
      {:error,
       "To upgrade, please add a payment method first. Use the Payment method step above to add a card or bank account."}
    end
  end

  defp validate_payment_method_for_upgrade(_socket, :downgrade), do: :ok

  defp validate_downgrade_with_sub_accounts(user, :downgrade) do
    sub_accounts = Accounts.get_sub_accounts(user)

    if sub_accounts != [] do
      {:error,
       "Cannot switch to a single-person membership while family members are still linked to your account. On the Family page, remove each linked family member, then try again."}
    else
      :ok
    end
  end

  defp validate_downgrade_with_sub_accounts(_user, _direction), do: :ok

  defp process_membership_change(
         socket,
         user,
         current_membership,
         new_price_id,
         direction,
         new_atom
       ) do
    case Subscriptions.change_membership_plan(
           current_membership,
           new_price_id,
           direction
         ) do
      {:ok, updated_subscription} ->
        handle_membership_change_success(
          socket,
          user,
          updated_subscription,
          direction,
          new_atom
        )

      {:scheduled, _schedule} ->
        handle_membership_change_scheduled(socket, user, direction)

      {:error, reason} ->
        handle_membership_change_error(socket, reason)
    end
  end

  defp handle_membership_change_success(
         socket,
         user,
         updated_subscription,
         direction,
         new_atom
       ) do
    updated_membership =
      updated_subscription |> Repo.preload(:subscription_items)

    invalidate_membership_cache(user)
    success_message = get_success_message(direction)

    {:noreply,
     socket
     |> assign(:current_membership, updated_membership)
     |> assign(:active_plan_type, new_atom)
     |> assign(:change_membership_button, false)
     |> assign(:membership_change_info, nil)
     |> assign(
       :membership_form,
       to_form(%{"membership_type" => Atom.to_string(new_atom)})
     )
     |> YscWeb.Flash.put_toast(:info, success_message, title: "Membership")
     |> push_patch(to: ~p"/users/membership")}
  end

  defp handle_membership_change_scheduled(socket, user, _direction) do
    invalidate_membership_cache(user)

    {:noreply,
     YscWeb.Flash.put_toast(
       socket,
       :info,
       "Your membership plan will switch at your next renewal.",
       title: "Membership",
       icon: &YscWeb.CoreComponents.flash_toast_icon_clock/1
     )
     |> push_patch(to: ~p"/users/membership")}
  end

  defp handle_membership_change_error(socket, reason) do
    require Ysc.Logging

    Ysc.Logging.error(
      "Membership plan change failed",
      reason: inspect(reason)
    )

    {:noreply,
     YscWeb.Flash.put_toast(
       socket,
       :error,
       "We couldn't update your membership plan. Please try again in a few minutes, or contact info@ysc.org if this continues.",
       title: "Membership"
     )}
  end

  defp format_payment_error(error),
    do: Ysc.PaymentUserMessages.format_stripe_error(error)

  defp invalidate_membership_cache(user) do
    MembershipCache.invalidate_user(user.id)
    sub_accounts = Accounts.get_sub_accounts(user)

    Enum.each(sub_accounts, fn sub_account ->
      MembershipCache.invalidate_user(sub_account.id)
    end)
  end

  defp get_success_message(:upgrade) do
    "Your membership plan has been upgraded. You've been charged the difference for the rest of your membership year."
  end

  defp get_success_message(:downgrade) do
    "Your membership plan change has been scheduled. The new price will take effect at your next renewal."
  end

  # Helper functions for resend rate limiting - delegate to ResendRateLimiter
  defp sms_resend_available?(assigns),
    do: Ysc.ResendRateLimiter.resend_available?(assigns, :sms)

  defp sms_resend_seconds_remaining(assigns),
    do: Ysc.ResendRateLimiter.resend_seconds_remaining(assigns, :sms)

  defp email_resend_available?(assigns),
    do: Ysc.ResendRateLimiter.resend_available?(assigns, :email)

  defp email_resend_seconds_remaining(assigns),
    do: Ysc.ResendRateLimiter.resend_seconds_remaining(assigns, :email)

  defp parse_newsletter_param(value) when value in [true, "true", "1"], do: true
  defp parse_newsletter_param(_), do: false

  # Helper function to check if we're in dev/sandbox mode
  defp dev_or_sandbox? do
    Ysc.Env.non_prod?()
  end

  defp normalize_verification_code(code),
    do: VerificationCodes.normalize_otp_input(code)

  defp paginate_payments(socket, new_page) when new_page >= 1 do
    %{payments_per_page: per_page, user: user} = socket.assigns
    filter = socket.assigns[:payment_filter] || :all

    {payments, total_count} =
      Ledgers.list_user_payments_paginated(user.id, new_page, per_page,
        filter: filter
      )

    total_pages =
      if total_count == 0 do
        0
      else
        div(total_count + per_page - 1, per_page)
      end

    socket
    |> assign(:payments_page, new_page)
    |> assign(:payments_total, total_count)
    |> assign(:payments_total_pages, total_pages)
    |> assign(:all_payments, payments)
    |> assign(:filtered_payments_count, length(payments))
    |> assign(:filtered_payments_list, payments)
    |> stream(:payments, payments,
      reset: true,
      dom_id: &payment_dom_id/1
    )
  end

  defp get_price_id(memberhip_type) do
    plans = Application.get_env(:ysc, :membership_plans)

    Enum.find(plans, &(&1.id == memberhip_type))[:stripe_price_id]
  end

  defp get_membership_plan(membership),
    do: YscWeb.UserAuth.get_membership_plan_type(membership)

  # defp payment_to_badge_style("paid"), do: "green"
  # defp payment_to_badge_style("open"), do: "blue"
  # defp payment_to_badge_style("draft"), do: "yellow"
  # defp payment_to_badge_style("uncollectible"), do: "red"
  # defp payment_to_badge_style("void"), do: "red"
  # defp payment_to_badge_style(_), do: "blue"

  # Get membership type for form pre-selection
  # Returns "family" or "single" based on current active membership, or most recent past membership
  defp get_membership_type_for_selection(user) do
    # Get all subscriptions (active and past)
    subscriptions =
      case user.subscriptions do
        %Ecto.Association.NotLoaded{} ->
          # Fallback if subscriptions aren't preloaded
          Subscriptions.list_subscriptions(user)

        subscriptions when is_list(subscriptions) ->
          subscriptions

        _ ->
          []
      end

    # Get price IDs for membership type lookup
    family_price_id = get_price_id(:family)
    single_price_id = get_price_id(:single)

    # First, check active subscriptions
    active_membership_type =
      subscriptions
      |> Enum.filter(&Subscriptions.active?/1)
      |> Enum.find_value(fn subscription ->
        if subscription_items_contain_price?(subscription, family_price_id) do
          :family
        else
          if subscription_items_contain_price?(subscription, single_price_id) do
            :single
          else
            nil
          end
        end
      end)

    # If we found an active membership type, return it
    if active_membership_type do
      Atom.to_string(active_membership_type)
    else
      # No active membership, check past subscriptions (most recent first)
      past_membership_type =
        subscriptions
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.find_value(fn subscription ->
          if subscription_items_contain_price?(subscription, family_price_id) do
            :family
          else
            if subscription_items_contain_price?(subscription, single_price_id) do
              :single
            else
              nil
            end
          end
        end)

      # Return past membership type if found, otherwise default to "single"
      if past_membership_type do
        Atom.to_string(past_membership_type)
      else
        "single"
      end
    end
  end

  defp empty_billing_address_changeset(user) do
    Address.changeset(%Address{user_id: user.id}, %{"user_id" => user.id})
  end

  defp payment_secret(:payment_method, user) do
    case Customers.create_setup_intent(user,
           stripe: %{
             payment_method_types: ["us_bank_account", "card"]
           }
         ) do
      {:ok, setup_intent} -> setup_intent.client_secret
      {:error, _} -> nil
    end
  end

  defp payment_secret(_, _), do: nil

  # Helper function to ensure Stripe customer exists
  @dialyzer {:nowarn_function, ensure_stripe_customer_exists: 1}
  defp ensure_stripe_customer_exists(user) do
    if user.stripe_id == nil do
      # No stripe_id - create new customer
      case Customers.create_stripe_customer(user) do
        {:ok, _stripe_customer} ->
          # Reload user to get updated stripe_id
          # Add a small delay to ensure the database update has committed
          db_sync_delay =
            Application.get_env(:ysc, :stripe_customer_db_sync_delay_ms, 50)

          Process.sleep(db_sync_delay)
          reloaded_user = Ysc.Accounts.get_user!(user.id)

          # If still no stripe_id after reload, try again (database might need a moment)
          if reloaded_user.stripe_id == nil do
            db_sync_retry_delay =
              Application.get_env(
                :ysc,
                :stripe_customer_db_sync_retry_delay_ms,
                100
              )

            Process.sleep(db_sync_retry_delay)
            Ysc.Accounts.get_user!(user.id)
          else
            reloaded_user
          end

        {:error, error} ->
          require Ysc.Logging

          Ysc.Logging.error("Failed to create Stripe customer",
            user_id: user.id,
            error: inspect(error)
          )

          user
      end
    else
      # Has stripe_id - verify customer exists in Stripe
      case verify_stripe_customer_exists(user.stripe_id) do
        :ok ->
          user

        {:error, _} ->
          # Customer doesn't exist in Stripe, create a new one
          case Customers.create_stripe_customer(user) do
            {:ok, _stripe_customer} ->
              # Reload user to get updated stripe_id
              # Add a small delay to ensure the database update has committed
              db_sync_delay =
                Application.get_env(:ysc, :stripe_customer_db_sync_delay_ms, 50)

              Process.sleep(db_sync_delay)
              reloaded_user = Ysc.Accounts.get_user!(user.id)

              # If still no stripe_id after reload, try again
              if reloaded_user.stripe_id == nil do
                db_sync_retry_delay =
                  Application.get_env(
                    :ysc,
                    :stripe_customer_db_sync_retry_delay_ms,
                    100
                  )

                Process.sleep(db_sync_retry_delay)
                Ysc.Accounts.get_user!(user.id)
              else
                reloaded_user
              end

            {:error, error} ->
              require Ysc.Logging

              Ysc.Logging.error("Failed to create Stripe customer",
                user_id: user.id,
                error: inspect(error)
              )

              user
          end
      end
    end
  end

  # Helper function to verify if Stripe customer exists
  defp verify_stripe_customer_exists(stripe_id) do
    case Ysc.Stripe.RetryHelper.stripe_retry(fn ->
           stripe_customer_module().retrieve(stripe_id, [])
         end) do
      {:ok, _customer} -> :ok
      {:error, %Stripe.Error{code: :resource_missing}} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp stripe_customer_module do
    Application.get_env(:ysc, :stripe_customer_module, Stripe.Customer)
  end

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  # Helper function to safely fetch user invoices

  # Render payment card for mobile view
  defp render_payment_card(payment_info) do
    row_navigate = payment_row_navigate_js(payment_info)

    assigns = %{
      payment_info: payment_info,
      row_navigate: row_navigate,
      row_navigate_label:
        payment_row_navigate_aria_label(payment_info, row_navigate)
    }

    ~H"""
    <%= if @row_navigate do %>
      <button
        type="button"
        phx-click={@row_navigate}
        aria-label={@row_navigate_label}
        class={[
          "group border border-zinc-200 rounded-2xl p-5 hover:border-blue-300 hover:shadow-sm transition-all bg-white cursor-pointer w-full text-left font-normal",
          "appearance-none m-0"
        ]}
      >
        {render_payment_card_body(assigns)}
      </button>
    <% else %>
      <div class="group border border-zinc-200 rounded-2xl p-5 hover:border-blue-300 hover:shadow-sm transition-all bg-white">
        {render_payment_card_body(assigns)}
      </div>
    <% end %>
    """
  end

  defp render_payment_card_body(assigns) do
    ~H"""
    <div class="flex items-center gap-4 mb-4">
      <div class={[
        "w-12 h-12 rounded-full flex items-center justify-center transition-colors",
        PaymentDisplay.get_payment_icon_bg(@payment_info)
      ]}>
        <.icon
          name={PaymentDisplay.get_payment_icon(@payment_info)}
          class={[
            "w-6 h-6",
            PaymentDisplay.get_payment_icon_color(@payment_info)
          ]}
        />
      </div>
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-zinc-900 text-lg leading-tight">
            {PaymentDisplay.get_payment_title(@payment_info)}
          </h3>
          <%= if @payment_info.type == :booking && @payment_info.booking && @payment_info.booking.status == :canceled do %>
            <.badge type="red">Cancelled</.badge>
          <% end %>
          <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
            <.badge type="red">Cancelled</.badge>
          <% end %>
        </div>
        <p class="text-xs font-mono text-zinc-400 mt-1">
          {PaymentDisplay.get_payment_reference(@payment_info)}
        </p>
      </div>
    </div>

    <div class="space-y-2 mb-4">
      {render_payment_details(assigns)}
    </div>

    <%= if @payment_info.type == :booking && @payment_info.booking && @payment_info.booking.status == :canceled do %>
      <div class="mb-3 p-2 bg-red-50 border border-red-200 rounded text-xs text-red-800">
        <strong>Booking Cancelled:</strong>
        This booking has been cancelled. {if @payment_info.payment do
          if @payment_info.refund_data && @payment_info.refund_data.total_refunded do
            " A refund of #{Ysc.MoneyHelper.format_money!(@payment_info.refund_data.total_refunded)} has been processed."
          else
            " Refund information is available in the booking details."
          end
        end}
      </div>
    <% end %>

    <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
      <div class="mb-3 p-2 bg-red-50 border border-red-200 rounded text-xs text-red-800">
        <strong>Tickets cancelled:</strong>
        These tickets have been cancelled. {if @payment_info.payment do
          if @payment_info.refund_data && @payment_info.refund_data.total_refunded do
            " A refund of #{Ysc.MoneyHelper.format_money!(@payment_info.refund_data.total_refunded)} has been processed."
          else
            " Refund information is available in the order details."
          end
        end}
      </div>
    <% end %>

    <div class="flex items-center justify-between pt-4 border-t border-zinc-200">
      <div class="text-right">
        <p class="text-lg font-black text-zinc-900">
          {if @payment_info.payment do
            Ysc.MoneyHelper.format_money!(@payment_info.payment.amount)
          else
            "Free"
          end}
        </p>
        <p class="text-xs text-zinc-400 uppercase tracking-widest font-bold">
          Paid on {if @payment_info.payment do
            if @payment_info.payment.payment_date do
              format_payment_date(@payment_info.payment.payment_date)
            else
              format_payment_date(@payment_info.payment.inserted_at)
            end
          else
            format_payment_date(@payment_info.ticket_order.inserted_at)
          end}
        </p>
      </div>
      <div class="flex items-center gap-3">
        {render_payment_status_badge(@payment_info)}
      </div>
    </div>
    """
  end

  defp payment_row_navigate_js(%{type: :booking, booking: %{id: id}}) do
    JS.navigate(~p"/bookings/#{id}/receipt")
  end

  defp payment_row_navigate_js(%{type: :ticket, ticket_order: %{id: id}}) do
    JS.navigate(~p"/orders/#{id}/confirmation")
  end

  defp payment_row_navigate_js(_), do: nil

  defp payment_row_navigate_aria_label(%{type: :booking}, %JS{}),
    do: "View booking receipt"

  defp payment_row_navigate_aria_label(%{type: :ticket}, %JS{}),
    do: "View ticket confirmation"

  defp payment_row_navigate_aria_label(_, _), do: nil

  # Render payment table row for desktop view
  defp render_payment_table_row(payment_info, opts) do
    id = Keyword.get(opts, :id)
    row_navigate = payment_row_navigate_js(payment_info)

    assigns = %{
      payment_info: payment_info,
      id: id,
      row_navigate: row_navigate,
      row_navigate_label:
        payment_row_navigate_aria_label(payment_info, row_navigate)
    }

    ~H"""
    <tr
      id={@id}
      class={[
        "group hover:bg-zinc-50 transition-colors",
        @row_navigate && "cursor-pointer"
      ]}
      phx-click={@row_navigate}
      tabindex={@row_navigate && "0"}
      role={@row_navigate && "link"}
      aria-label={@row_navigate_label}
      phx-keydown={@row_navigate}
      phx-key={@row_navigate && "enter"}
    >
      <td class="px-6 py-4 whitespace-nowrap">
        <div class="flex items-center gap-4">
          <div class={[
            "w-10 h-10 rounded-full flex items-center justify-center",
            PaymentDisplay.get_payment_icon_bg(@payment_info)
          ]}>
            <.icon
              name={PaymentDisplay.get_payment_icon(@payment_info)}
              class={[
                "w-5 h-5",
                PaymentDisplay.get_payment_icon_color(@payment_info)
              ]}
            />
          </div>
          <div>
            <div class="flex items-center gap-2">
              <h3 class="font-bold text-zinc-900 text-sm">
                {PaymentDisplay.get_payment_title(@payment_info)}
              </h3>
              <%= if @payment_info.type == :booking && @payment_info.booking && @payment_info.booking.status == :canceled do %>
                <.badge type="red" class="text-xs">Cancelled</.badge>
              <% end %>
              <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
                <.badge type="red" class="text-xs">Cancelled</.badge>
              <% end %>
            </div>
            <p class="text-xs font-mono text-zinc-400 mt-0.5">
              {PaymentDisplay.get_payment_reference(@payment_info)}
            </p>
          </div>
        </div>
      </td>
      <td class="px-6 py-4">
        <div class="text-sm text-zinc-600">
          {render_payment_details_compact(assigns)}
        </div>
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-right">
        <p class="text-base font-black text-zinc-900">
          {if @payment_info.payment do
            Ysc.MoneyHelper.format_money!(@payment_info.payment.amount)
          else
            "Free"
          end}
        </p>
        <p class="text-xs text-zinc-400 uppercase tracking-wider font-bold">
          {if @payment_info.payment do
            if @payment_info.payment.payment_date do
              format_payment_date(@payment_info.payment.payment_date)
            else
              format_payment_date(@payment_info.payment.inserted_at)
            end
          else
            format_payment_date(@payment_info.ticket_order.inserted_at)
          end}
        </p>
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-center">
        {render_payment_status_badge(@payment_info)}
      </td>
    </tr>
    """
  end

  defp render_payment_details(assigns) do
    payment_info = assigns.payment_info

    cond do
      payment_info.type == :booking && not is_nil(payment_info.booking) ->
        assigns = Map.put(assigns, :booking, payment_info.booking)

        ~H"""
        <div class="flex flex-col text-sm text-zinc-500">
          <p class="font-medium text-zinc-700 italic">
            {Timex.format!(@booking.checkin_date, "{Mshort} {D}")} – {Timex.format!(
              @booking.checkout_date,
              "{Mshort} {D}, {YYYY}"
            )}
          </p>
          <p class="text-xs">
            {if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do
              Enum.map_join(@booking.rooms, ", ", fn room -> room.name end)
            else
              ""
            end}
            {if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 &&
                  @booking.guests_count > 0 do
              " • "
            else
              ""
            end}
            {if @booking.guests_count > 0 do
              "#{@booking.guests_count} #{if @booking.guests_count == 1, do: "guest", else: "guests"}"
            end}
          </p>
        </div>
        """

      payment_info.type == :ticket && not is_nil(payment_info.ticket_order) ->
        assigns =
          assigns
          |> Map.put(:ticket_order, payment_info.ticket_order)
          |> Map.put(:event, payment_info.event)

        ~H"""
        <div class="flex flex-col text-sm text-zinc-500">
          <p class="font-medium text-zinc-700">
            {if @event do
              @event.title
            else
              "Event"
            end}
          </p>
          <p class="text-xs">
            {TicketDisplay.format_order_ticket_summary(@ticket_order.tickets)}
          </p>
        </div>
        """

      payment_info.type == :membership && not is_nil(payment_info.subscription) ->
        # Ensure subscription_items are loaded before rendering
        subscription =
          case payment_info.subscription.subscription_items do
            %Ecto.Association.NotLoaded{} ->
              Repo.preload(payment_info.subscription, :subscription_items)

            _ ->
              payment_info.subscription
          end

        assigns = Map.put(assigns, :subscription, subscription)

        ~H"""
        <div class="flex flex-col text-sm text-zinc-500">
          <p class="font-medium text-zinc-700">
            {case @subscription.subscription_items do
              [item | _] ->
                plans = Application.get_env(:ysc, :membership_plans)
                plan = Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id))

                if plan do
                  String.capitalize(to_string(plan.id))
                else
                  "Single"
                end

              _ ->
                "Single"
            end} Membership
          </p>
        </div>
        """

      true ->
        assigns = %{}

        ~H"""
        <div></div>
        """
    end
  end

  defp render_payment_details_compact(assigns) do
    payment_info = assigns.payment_info

    cond do
      payment_info.type == :booking && not is_nil(payment_info.booking) ->
        assigns = Map.put(assigns, :booking, payment_info.booking)

        ~H"""
        <p class="font-medium text-zinc-700 italic">
          {Timex.format!(@booking.checkin_date, "{Mshort} {D}")} – {Timex.format!(
            @booking.checkout_date,
            "{Mshort} {D}, {YYYY}"
          )}
        </p>
        <p class="text-xs mt-0.5">
          {if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do
            Enum.map_join(@booking.rooms, ", ", fn room -> room.name end)
          else
            ""
          end}
          {if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 &&
                @booking.guests_count > 0 do
            " • "
          else
            ""
          end}
          {if @booking.guests_count > 0 do
            "#{@booking.guests_count} #{if @booking.guests_count == 1, do: "guest", else: "guests"}"
          end}
        </p>
        """

      payment_info.type == :ticket && not is_nil(payment_info.ticket_order) ->
        assigns =
          assigns
          |> Map.put(:ticket_order, payment_info.ticket_order)
          |> Map.put(:event, payment_info.event)

        ~H"""
        <p class="font-medium text-zinc-700">
          {if @event do
            @event.title
          else
            "Event"
          end}
        </p>
        <p class="text-xs mt-0.5">
          {TicketDisplay.format_order_ticket_summary(@ticket_order.tickets)}
        </p>
        """

      payment_info.type == :membership && not is_nil(payment_info.subscription) ->
        # Ensure subscription_items are loaded before rendering
        subscription =
          case payment_info.subscription.subscription_items do
            %Ecto.Association.NotLoaded{} ->
              Repo.preload(payment_info.subscription, :subscription_items)

            _ ->
              payment_info.subscription
          end

        assigns = Map.put(assigns, :subscription, subscription)

        ~H"""
        <p class="font-medium text-zinc-700">
          {case @subscription.subscription_items do
            [item | _] ->
              plans = Application.get_env(:ysc, :membership_plans)
              plan = Enum.find(plans, &(&1.stripe_price_id == item.stripe_price_id))

              if plan do
                String.capitalize(to_string(plan.id))
              else
                "Single"
              end

            _ ->
              "Single"
          end} Membership
        </p>
        """

      true ->
        assigns = %{}

        ~H"""
        <p class="text-zinc-500">—</p>
        """
    end
  end

  defp render_payment_status_badge(payment_info) do
    status = payment_status_for_badge(payment_info)
    assigns = %{status: status}

    ~H"""
    <.badge type={BookingDisplay.payment_status_badge_type(@status)} class="text-xs">
      {BookingDisplay.payment_status_label(@status)}
    </.badge>
    """
  end

  defp payment_status_for_badge(%{payment: nil}), do: :completed
  defp payment_status_for_badge(%{payment: payment}), do: payment.status

  # Helper function to handle retry invoice payment
  defp handle_retry_invoice_payment(socket, invoice_id)
       when is_binary(invoice_id) do
    require Ysc.Logging
    user = socket.assigns.user

    if user.state != :active do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You must have an approved account to retry invoice payments.",
         title: "Invoice"
       )}
    else
      Ysc.Logging.info("Retrying invoice payment",
        user_id: user.id,
        invoice_id: invoice_id
      )

      case Subscriptions.retry_failed_invoice(user, invoice_id) do
        {:ok, _paid_invoice} ->
          Ysc.Logging.info("Successfully retried invoice payment",
            user_id: user.id,
            invoice_id: invoice_id
          )

          # Invalidate membership cache after successful payment
          # The subscription will be updated via webhook, but invalidate cache now for immediate effect
          MembershipCache.invalidate_user(user.id)

          # Also invalidate for sub-accounts since they inherit from primary user
          sub_accounts = Accounts.get_sub_accounts(user)

          Enum.each(sub_accounts, fn sub_account ->
            MembershipCache.invalidate_user(sub_account.id)
          end)

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :info,
             "Payment retry successful! Your invoice has been paid and your membership will be updated shortly.",
             title: "Invoice",
             icon: &YscWeb.CoreComponents.flash_toast_icon_payment/1
           )
           |> push_patch(to: ~p"/users/membership")}

        {:error, :invoice_not_found} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             retry_invoice_link_help_message(),
             title: "Invoice"
           )}

        {:error, :unauthorized} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "This invoice does not belong to your account.",
             title: "Invoice"
           )}

        {:error, :already_paid} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :info,
             "This invoice has already been paid. Your membership is up to date.",
             title: "Invoice"
           )}

        {:error, :invalid_invoice_status} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             retry_invoice_link_help_message(),
             title: "Invoice"
           )}

        {:error, error_message} when is_binary(error_message) ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             Ysc.PaymentUserMessages.invoice_retry_error(error_message),
             title: "Invoice"
           )}

        {:error, _reason} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Your payment could not be processed. Please try a different payment method or contact your bank. If the issue persists, email info@ysc.org.",
             title: "Invoice"
           )}
      end
    end
  end

  defp handle_retry_invoice_payment(socket, _invalid_invoice_id) do
    {:noreply,
     YscWeb.Flash.put_toast(
       socket,
       :error,
       retry_invoice_link_help_message(),
       title: "Invoice"
     )}
  end

  defp retry_invoice_link_help_message do
    "This payment link didn't work — it may have expired. Open Membership in your account menu to update your card and try again, or email #{Ysc.EmailConfig.membership_email()} for help."
  end

  defp subscription_items_contain_price?(subscription, price_id) do
    subscription_items =
      case subscription.subscription_items do
        %Ecto.Association.NotLoaded{} ->
          # Preload subscription items if not loaded
          subscription = Repo.preload(subscription, :subscription_items)
          subscription.subscription_items

        items when is_list(items) ->
          items

        _ ->
          []
      end

    Enum.any?(subscription_items, fn item ->
      item.stripe_price_id == price_id
    end)
  end

  defp booking_entitlement_dom_id(ent), do: "member-entitlement-#{ent.id}"

  defp ticket_reservation_dom_id(res), do: "member-ticket-reservation-#{res.id}"

  # Generate unique DOM ID for payment stream items
  defp payment_dom_id(%{type: :booking, booking: booking})
       when not is_nil(booking) do
    "payment-booking-#{booking.id}"
  end

  defp payment_dom_id(%{type: :ticket, ticket_order: ticket_order})
       when not is_nil(ticket_order) do
    "payment-ticket-#{ticket_order.id}"
  end

  defp payment_dom_id(%{type: :membership, payment: payment})
       when not is_nil(payment) do
    "payment-membership-#{payment.id}"
  end

  defp payment_dom_id(%{type: :donation, payment: payment})
       when not is_nil(payment) do
    "payment-donation-#{payment.id}"
  end

  defp payment_dom_id(%{payment: payment}) when not is_nil(payment) do
    "payment-#{payment.id}"
  end

  defp payment_dom_id(_) do
    "payment-#{System.unique_integer([:positive])}"
  end

  defp build_membership_qr_details(assigns) do
    YscWeb.MembershipHelpers.build_membership_qr_details(assigns)
  end

  defp wallet_platform_from_params(socket) do
    if connected?(socket) do
      case get_connect_params(socket)["wallet_platform"] do
        "apple_only" -> :apple_only
        "google_only" -> :google_only
        _ -> :both
      end
    else
      :both
    end
  end

  # --- Avatar helpers ---

  defp load_user_avatars(user) do
    Avatars.list_user_avatars(user)
  end

  defp resolve_current_avatar_url(user) do
    user = Repo.preload(user, :current_avatar, force: true)

    case user.current_avatar do
      nil -> nil
      avatar -> Avatars.avatar_url(avatar, :profile)
    end
  end

  defp format_utc_date(%DateTime{} = dt, format) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime(format)
  end

  defp format_utc_date(%Date{} = date, format),
    do: Calendar.strftime(date, format)

  defp format_utc_date(_, _), do: ""

  defp format_payment_date(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime("%b %-d")
  end

  defp format_payment_date(%Date{} = date),
    do: Calendar.strftime(date, "%b %-d")

  defp format_payment_date(_), do: ""

  defp member_entitlement_coupon_headline(ent) do
    case ent.benefit_kind do
      :percent_off ->
        pct = ent.percent_off || Decimal.new(0)
        "#{Decimal.round(pct, 0)}% off"

      :free_nights ->
        n = ent.free_nights || 0

        if n == 1 do
          "1 free night"
        else
          "#{n} free nights"
        end

      :fixed_amount_off ->
        "#{format_member_money(ent.amount_off)} off"

      _ ->
        "Member savings"
    end
  end

  defp member_entitlement_coupon_expiry_phrase(ent) do
    if ent.expires_at do
      d =
        ent.expires_at
        |> DateTime.shift_zone!("America/Los_Angeles")
        |> DateTime.to_date()

      "Use by #{Calendar.strftime(d, "%b %-d, %Y")}"
    else
      "No expiry — book anytime"
    end
  end

  defp ticket_reservation_discount_phrase(%{discount_percentage: p})
       when not is_nil(p) do
    case Decimal.compare(p, Decimal.new(0)) do
      :gt -> "#{Decimal.round(p, 0)}% off member tickets"
      _ -> nil
    end
  end

  defp ticket_reservation_discount_phrase(_), do: nil

  defp member_entitlement_property_label(nil), do: "Any cabin"
  defp member_entitlement_property_label(:tahoe), do: "Tahoe"
  defp member_entitlement_property_label(:clear_lake), do: "Clear Lake"
  defp member_entitlement_property_label(other), do: to_string(other)

  defp member_entitlement_benefit_summary(ent) do
    case ent.benefit_kind do
      :free_nights ->
        n = ent.free_nights || 0
        cap = format_member_money(ent.buyout_max_discount)

        "#{n} free night#{if n == 1, do: "", else: "s"} (up to #{cap} off when you reserve the whole cabin)"

      :percent_off ->
        pct = ent.percent_off || Decimal.new(0)
        cap = format_member_money(ent.buyout_max_discount)

        "#{Decimal.round(pct, 2)}% off your stay (up to #{cap} when booking the whole cabin)"

      :fixed_amount_off ->
        "#{format_member_money(ent.amount_off)} off your stay"
    end
  end

  defp format_member_money(nil), do: "—"

  defp format_member_money(%Money{} = m) do
    Ysc.MoneyHelper.format_money!(m)
  end
end
