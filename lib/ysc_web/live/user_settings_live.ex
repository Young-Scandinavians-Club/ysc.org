defmodule YscWeb.UserSettingsLive do
  use YscWeb, :live_view

  import YscWeb.Live.AsyncHelpers

  @phone_verification_token_salt "phone_verification"
  @phone_verification_token_max_age 3600

  @email_verification_token_salt "email_verification_pending"
  # 30 minutes — long enough to complete the verification step
  @email_verification_token_max_age 1800

  alias Ysc.Accounts
  alias Ysc.Accounts.{FamilyInvites, MembershipCache}
  alias Ysc.Accounts.UserNotifier
  alias Ysc.Avatars
  alias Ysc.Bookings.Entitlements
  alias Ysc.Customers
  alias Ysc.Events
  alias Ysc.GoogleWallet
  alias Ysc.Ledgers
  alias Ysc.Newsletter
  alias Ysc.Repo
  alias Ysc.S3Config
  alias Ysc.Subscriptions
  alias YscWeb.S3.SimpleS3Upload

  import Ecto.Query

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
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
            Verify Your Phone Number
          </h2>

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
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Verify Phone Number
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
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
            Verify Your New Email Address
          </h2>

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
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Verify Email Address
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
          description="For security reasons, please verify your identity before changing your email address."
        />

        <.modal
          :if={@live_action == :payment_method}
          id="update-payment-method-modal"
          on_cancel={JS.patch(~p"/users/membership")}
          show
        >
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
            Payment Method
          </h2>
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
                  <div class="flex items-center space-x-3">
                    <div class="flex-shrink-0">
                      <svg
                        :if={payment_method.type == :card}
                        stroke="currentColor"
                        fill="currentColor"
                        stroke-width="0"
                        viewBox="0 0 576 512"
                        xmlns="http://www.w3.org/2000/svg"
                        class="w-6 h-6 fill-zinc-800 text-zinc-800"
                      >
                        <path d={payment_method_icon(payment_method)}></path>
                      </svg>
                      <svg
                        :if={payment_method.type == :bank_account}
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="w-6 h-6 text-zinc-800"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d={payment_method_icon(payment_method)}
                        >
                        </path>
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-zinc-800 text-sm font-semibold">
                        {payment_method_display_text(payment_method)}
                      </p>
                      <p
                        :if={
                          payment_method.type == :card && payment_method.exp_month &&
                            payment_method.exp_year
                        }
                        class="text-zinc-500 text-xs mt-0.5"
                      >
                        Expires {String.pad_leading(
                          to_string(payment_method.exp_month),
                          2,
                          "0"
                        )} / {payment_method.exp_year}
                      </p>
                      <p
                        :if={
                          payment_method.type == :bank_account &&
                            payment_method.account_type
                        }
                        class="text-zinc-500 text-xs mt-0.5"
                      >
                        {payment_method.account_type}
                      </p>
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
              <button
                id="add-payment-method"
                type="button"
                phx-click="add-new-payment-method"
                phx-disable-with="Loading..."
                class="inline-flex items-center gap-2 px-5 py-2.5 rounded-lg border-2 border-dashed border-zinc-300 text-sm font-medium text-zinc-600 hover:border-blue-400 hover:text-blue-600 hover:bg-blue-50 transition-all duration-150"
              >
                <.icon name="hero-plus-circle" class="w-5 h-5" /> Add Payment Method
              </button>
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

        <ul class="flex-column space-y space-y-4 md:pr-10 text-sm font-medium text-zinc-600 md:me-4 mb-4 md:mb-0">
          <li>
            <h2 class="text-zinc-800 text-2xl font-semibold leading-8 mb-10">
              Account
            </h2>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :edit && "bg-blue-600 active text-zinc-100",
                @live_action != :edit && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
              aria-active={@live_action == :edit}
            >
              <.icon name="hero-user" class="w-5 h-5 me-2" /> Profile
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/membership"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                (@live_action == :membership || @live_action == :payment_method) &&
                  "bg-blue-600 active text-zinc-100",
                @live_action != :membership && @live_action != :payment_method &&
                  "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-heart" class="w-5 h-5 me-2" /> Membership
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/payments"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :payments && "bg-blue-600 active text-zinc-100",
                @live_action != :payments && "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-wallet" class="w-5 h-5 me-2" /> Payments
            </.link>
          </li>
          <%= if @current_user && (Accounts.primary_user?(@current_user) || Accounts.sub_account?(@current_user)) && (@active_plan_type == :family || @active_plan_type == :lifetime) do %>
            <li>
              <.link
                navigate={~p"/users/settings/family"}
                class={[
                  "inline-flex items-center px-4 py-3 rounded w-full",
                  @live_action == :family && "bg-blue-600 active text-zinc-100",
                  @live_action != :family && "hover:bg-zinc-100 hover:text-zinc-900"
                ]}
              >
                <.icon name="hero-user-group" class="w-5 h-5 me-2" /> Family
              </.link>
            </li>
          <% end %>
          <li>
            <.link
              navigate={~p"/users/settings/security"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-shield-check" class="w-5 h-5 me-2" /> Security
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/notifications"}
              class={[
                "inline-flex items-center px-4 py-3 rounded w-full",
                @live_action == :notifications && "bg-blue-600 active text-zinc-100",
                @live_action != :notifications &&
                  "hover:bg-zinc-100 hover:text-zinc-900"
              ]}
            >
              <.icon name="hero-bell-alert" class="w-5 h-5 me-2" /> Notifications
            </.link>
          </li>
        </ul>

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
                        <label class="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded-lg cursor-pointer hover:bg-zinc-50 transition-colors">
                          <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                          Upload new photo
                          <input
                            type="file"
                            accept="image/jpeg,image/png,image/webp,image/gif"
                            class="hidden"
                            data-avatar-file-input
                          />
                        </label>

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
                        {avatar_upload_error_to_string(err)}
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

                  <%!-- Avatar library --%>
                  <div :if={@loading_avatars} class="pt-2">
                    <div class="h-4 w-20 bg-zinc-200 rounded animate-pulse mb-2">
                    </div>
                    <div class="flex flex-wrap gap-2">
                      <%= for _i <- 1..4 do %>
                        <div class="w-14 h-14 rounded-full bg-zinc-200 animate-pulse">
                        </div>
                      <% end %>
                    </div>
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
                  label="Which Nordic or Scandinavian country do you feel most connected to?"
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
                  You will be asked to verify your identity before changing your email address.
                </p>
                <:actions>
                  <.button phx-disable-with="Continuing...">Change Email</.button>
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
                        else: "your primary account" %></strong>.
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
                      Downgrade Scheduled
                    </h3>
                    <p class="text-sm text-amber-700 mt-1">
                      <%= if @primary_user do %>
                        The membership from
                        <strong>
                          {@primary_user.first_name} {@primary_user.last_name}
                        </strong>
                        will change to
                      <% else %>
                        The primary account membership will change to
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
                        phx-disable-with="Cancelling..."
                        variant="outline"
                        color="amber"
                        data-confirm="Are you sure you want to cancel the scheduled downgrade? Your membership will stay at its current level."
                      >
                        Cancel downgrade
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
              <.button
                :if={@current_membership != nil}
                phx-click="show_membership_qr"
              >
                <.icon name="hero-qr-code" class="w-5 h-5 me-1.5 -mt-0.5" />
                My Membership QR
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
                      Downgrade Scheduled
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
                        phx-disable-with="Cancelling..."
                        variant="outline"
                        color="amber"
                        data-confirm="Are you sure you want to cancel the scheduled downgrade? Your membership will stay at its current level."
                      >
                        Cancel downgrade
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
              <.button phx-click="show_membership_qr">
                <.icon name="hero-qr-code" class="w-5 h-5 me-1.5 -mt-0.5" />
                My Membership QR
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
                  You have been invited to join a family membership. Accepting an invitation will
                  link your account to the inviter's membership.
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
                      Your account must be approved by the board before you can purchase a membership. Please check back shortly.
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

                    <div
                      :if={@loading_payment_methods}
                      class="flex items-center gap-3 py-3"
                    >
                      <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600">
                      </div>
                      <span class="text-sm text-zinc-500">
                        Loading payment methods...
                      </span>
                    </div>

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
                      <div class="flex items-center gap-3">
                        <div class="flex-shrink-0">
                          <svg
                            :if={@default_payment_method.type == :card}
                            stroke="currentColor"
                            fill="currentColor"
                            stroke-width="0"
                            viewBox="0 0 576 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 fill-zinc-700"
                          >
                            <path d={payment_method_icon(@default_payment_method)}>
                            </path>
                          </svg>
                          <svg
                            :if={@default_payment_method.type == :bank_account}
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="w-6 h-6 text-zinc-700"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d={payment_method_icon(@default_payment_method)}
                            >
                            </path>
                          </svg>
                        </div>
                        <div>
                          <p class="text-sm font-semibold text-zinc-700">
                            {payment_method_display_text(@default_payment_method)}
                          </p>
                          <p
                            :if={
                              @default_payment_method.type == :card &&
                                @default_payment_method.exp_month &&
                                @default_payment_method.exp_year
                            }
                            class="text-xs text-zinc-500"
                          >
                            Expires {String.pad_leading(
                              to_string(@default_payment_method.exp_month),
                              2,
                              "0"
                            )} / {@default_payment_method.exp_year}
                          </p>
                          <p
                            :if={
                              @default_payment_method.type == :bank_account &&
                                @default_payment_method.account_type
                            }
                            class="text-xs text-zinc-500"
                          >
                            {@default_payment_method.account_type}
                          </p>
                        </div>
                      </div>
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
                          <.icon name="hero-shield-check" class="w-5 h-5 me-1.5" />
                          Complete Membership Purchase
                        </.button>
                        <p class="text-xs text-zinc-400 flex items-center gap-1">
                          <.icon name="hero-lock-closed" class="w-3 h-3" />
                          Secure payment via Stripe
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
                        Downgrade Scheduled
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
                          phx-disable-with="Cancelling..."
                          variant="outline"
                          color="amber"
                          data-confirm="Are you sure you want to cancel the scheduled downgrade? Your membership will stay at its current level."
                        >
                          Cancel downgrade
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
                    <.icon name="hero-qr-code" class="w-5 h-5 me-1.5 -mt-0.5" />
                    My Membership QR
                  </.button>
                  <.button
                    patch={~p"/users/membership/payment-method"}
                    variant="outline"
                    class="w-full sm:w-auto justify-center"
                  >
                    <.icon name="hero-credit-card" class="w-5 h-5 me-1.5 -mt-0.5" />
                    Change Payment Method
                  </.button>
                  <.button
                    :if={
                      @current_membership != nil &&
                        Subscriptions.scheduled_for_cancellation?(
                          @current_membership
                        )
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
                      @current_membership != nil &&
                        !Subscriptions.scheduled_for_cancellation?(
                          @current_membership
                        ) &&
                        @active_plan_type != :lifetime
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
                    data-confirm="Turn off automatic renewal? You keep full membership benefits until the end of your current billing period, and you can turn auto-renewal back on anytime before then."
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
                              You will be charged a prorated amount now to upgrade from {String.capitalize(
                                "#{@membership_change_info.current_plan.id}"
                              )} to {String.capitalize(
                                "#{@membership_change_info.new_plan.id}"
                              )} membership. The maximum charge will be
                              <strong>
                                {Ysc.MoneyHelper.format_money!(
                                  Money.new(
                                    :USD,
                                    @membership_change_info.price_difference
                                  )
                                )}
                              </strong>
                              based on time remaining in your billing period.
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

                    <div
                      :if={@loading_payment_methods}
                      class="flex items-center gap-3 py-3"
                    >
                      <div class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600">
                      </div>
                      <span class="text-sm text-zinc-500">Loading...</span>
                    </div>

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
                      <div class="flex items-center gap-3">
                        <div class="flex-shrink-0">
                          <svg
                            :if={@default_payment_method.type == :card}
                            stroke="currentColor"
                            fill="currentColor"
                            stroke-width="0"
                            viewBox="0 0 576 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 fill-zinc-700"
                          >
                            <path d={payment_method_icon(@default_payment_method)}>
                            </path>
                          </svg>
                          <svg
                            :if={@default_payment_method.type == :bank_account}
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="w-6 h-6 text-zinc-700"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d={payment_method_icon(@default_payment_method)}
                            >
                            </path>
                          </svg>
                        </div>
                        <div>
                          <p class="text-sm font-semibold text-zinc-700">
                            {payment_method_display_text(@default_payment_method)}
                          </p>
                          <p
                            :if={
                              @default_payment_method.type == :card &&
                                @default_payment_method.exp_month &&
                                @default_payment_method.exp_year
                            }
                            class="text-xs text-zinc-500"
                          >
                            Expires {String.pad_leading(
                              to_string(@default_payment_method.exp_month),
                              2,
                              "0"
                            )} / {@default_payment_method.exp_year}
                          </p>
                          <p
                            :if={
                              @default_payment_method.type == :bank_account &&
                                @default_payment_method.account_type
                            }
                            class="text-xs text-zinc-500"
                          >
                            {@default_payment_method.account_type}
                          </p>
                        </div>
                      </div>
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
                        You will be charged a prorated amount today.
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
                      <.icon name="hero-arrows-right-left" class="me-2 -mt-0.5" />
                      Change Membership Plan
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

              <.async_section_loader
                :if={@loading_notification_preferences}
                id="notification-preferences-loading"
                label="Loading notification preferences…"
              />

              <.simple_form
                :if={!@loading_notification_preferences}
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
                            name={@notification_form[:event_notifications_sms].name}
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

          <div :if={@live_action == :payments} class="space-y-6">
            <div :if={!assigns[:loading_payments]} class="space-y-6">
              <div
                :if={@booking_entitlements_count > 0}
                id="member-booking-entitlements-section"
                class="rounded-2xl border border-amber-200/80 bg-gradient-to-br from-amber-50 via-white to-orange-50/90 p-5 sm:p-6 shadow-sm ring-1 ring-amber-100/60"
              >
                <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3 mb-5">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-widest text-amber-800/90">
                      Cabin savings
                    </p>
                    <h2 class="text-zinc-900 font-extrabold text-2xl mt-1 tracking-tight">
                      Your stay perks
                    </h2>
                    <p class="text-sm text-zinc-600 mt-1 max-w-xl">
                      Apply these automatically when you book a qualifying cabin stay — like a coupon on file for members.
                    </p>
                  </div>
                  <div class="hidden sm:flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-amber-100 text-amber-700 ring-2 ring-amber-200/80">
                    <.icon name="hero-home-modern" class="w-7 h-7" />
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
                    class={[
                      "relative overflow-hidden rounded-2xl border-2 border-dashed bg-white/90 backdrop-blur-sm shadow-md transition hover:shadow-lg hover:-translate-y-0.5",
                      member_entitlement_coupon_frame_class(ent.property)
                    ]}
                  >
                    <div class={[
                      "absolute -right-8 -top-8 h-24 w-24 rounded-full opacity-25 blur-2xl",
                      member_entitlement_coupon_blob_class(ent.property)
                    ]}>
                    </div>
                    <div class={[
                      "absolute inset-x-0 top-0 h-1.5 bg-gradient-to-r opacity-95",
                      member_entitlement_coupon_ribbon_class(ent.property)
                    ]}>
                    </div>
                    <div class="relative p-5 sm:p-6 flex flex-col gap-4">
                      <div class="flex items-start justify-between gap-3">
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-zinc-900/90 px-3 py-1 text-xs font-bold uppercase tracking-wide text-amber-50 shadow-sm">
                          <.icon name="hero-sparkles" class="w-3.5 h-3.5" />
                          Member perk
                        </span>
                        <span class="text-xs font-semibold text-zinc-500 tabular-nums">
                          Since {Calendar.strftime(ent.inserted_at, "%b %Y")}
                        </span>
                      </div>
                      <div>
                        <p class="text-2xl sm:text-3xl font-black text-zinc-900 leading-tight tracking-tight">
                          {member_entitlement_coupon_headline(ent)}
                        </p>
                        <p class="mt-2 text-sm text-zinc-600 leading-relaxed">
                          {member_entitlement_benefit_summary(ent)}
                        </p>
                      </div>
                      <div class="flex flex-wrap items-center gap-2 text-sm">
                        <span class="inline-flex items-center rounded-lg bg-zinc-100 px-2.5 py-1 font-semibold text-zinc-800">
                          <.icon
                            name="hero-map-pin"
                            class="w-4 h-4 me-1 text-zinc-500"
                          />
                          {member_entitlement_property_label(ent.property)}
                        </span>
                        <span class="inline-flex items-center rounded-lg bg-emerald-50 px-2.5 py-1 font-medium text-emerald-900 ring-1 ring-emerald-200/80">
                          <.icon
                            name="hero-clock"
                            class="w-4 h-4 me-1 text-emerald-600"
                          />
                          {member_entitlement_coupon_expiry_phrase(ent)}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div
                :if={@ticket_reservations_count > 0}
                id="member-ticket-reservations-section"
                class="rounded-2xl border border-fuchsia-200/80 bg-gradient-to-br from-fuchsia-50 via-white to-violet-50/90 p-5 sm:p-6 shadow-sm ring-1 ring-fuchsia-100/60"
              >
                <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3 mb-5">
                  <div>
                    <p class="text-xs font-bold uppercase tracking-widest text-fuchsia-800/90">
                      Event tickets
                    </p>
                    <h2 class="text-zinc-900 font-extrabold text-2xl mt-1 tracking-tight">
                      Your price holds
                    </h2>
                    <p class="text-sm text-zinc-600 mt-1 max-w-xl">
                      Active reservations lock in member-friendly pricing while you finish checkout — treat them like reserved coupons for the event.
                    </p>
                  </div>
                  <div class="hidden sm:flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-fuchsia-100 text-fuchsia-700 ring-2 ring-fuchsia-200/80">
                    <.icon name="hero-ticket" class="w-7 h-7" />
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
                    class="relative overflow-hidden rounded-2xl border-2 border-dashed border-fuchsia-300/90 bg-white/90 backdrop-blur-sm shadow-md transition hover:shadow-lg hover:-translate-y-0.5"
                  >
                    <div class="absolute -left-10 bottom-0 h-28 w-28 rounded-full bg-gradient-to-tr from-fuchsia-400/20 to-violet-400/20 blur-2xl">
                    </div>
                    <div class="absolute inset-x-0 top-0 h-1.5 bg-gradient-to-r from-fuchsia-500 via-violet-500 to-purple-500 opacity-90">
                    </div>
                    <div class="relative p-5 sm:p-6 flex flex-col gap-4">
                      <div class="flex items-start justify-between gap-3">
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-fuchsia-900/90 px-3 py-1 text-xs font-bold uppercase tracking-wide text-fuchsia-50 shadow-sm">
                          <.icon name="hero-bolt" class="w-3.5 h-3.5" /> Active hold
                        </span>
                        <span class="text-xs font-semibold text-zinc-500 tabular-nums">
                          Qty {res.quantity}
                        </span>
                      </div>
                      <div>
                        <p class="text-xl sm:text-2xl font-black text-zinc-900 leading-snug">
                          <%= if res.ticket_tier && res.ticket_tier.event do %>
                            {res.ticket_tier.event.title}
                          <% else %>
                            Ticket hold
                          <% end %>
                        </p>
                        <p
                          :if={res.ticket_tier}
                          class="mt-1 text-sm font-semibold text-fuchsia-900/90"
                        >
                          {res.ticket_tier.name}
                        </p>
                        <p
                          :if={ticket_reservation_discount_phrase(res)}
                          class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-100 px-2.5 py-1 text-sm font-bold text-amber-950 ring-1 ring-amber-300/70"
                        >
                          <.icon name="hero-receipt-percent" class="w-4 h-4" />
                          {ticket_reservation_discount_phrase(res)}
                        </p>
                      </div>
                      <div class="flex flex-wrap items-center gap-2 text-sm">
                        <span class="inline-flex items-center rounded-lg bg-violet-50 px-2.5 py-1 font-medium text-violet-900 ring-1 ring-violet-200/80">
                          <.icon
                            name="hero-clock"
                            class="w-4 h-4 me-1 text-violet-600"
                          />
                          <%= if res.expires_at do %>
                            Hold until {Calendar.strftime(
                              DateTime.shift_zone!(
                                res.expires_at,
                                "America/Los_Angeles"
                              ),
                              "%b %-d, %Y %H:%M PT"
                            )}
                          <% else %>
                            No timer — finish checkout when you are ready
                          <% end %>
                        </span>
                      </div>
                      <%= if res.ticket_tier && res.ticket_tier.event do %>
                        <.link
                          navigate={~p"/events/#{res.ticket_tier.event.id}/tickets"}
                          class="inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-fuchsia-600 to-violet-600 px-4 py-3 text-sm font-bold text-white shadow-md hover:from-fuchsia-500 hover:to-violet-500 transition"
                        >
                          Use this hold
                          <.icon name="hero-arrow-right" class="w-4 h-4" />
                        </.link>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded border border-zinc-100 py-4 px-4 space-y-6">
              <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                <h2 class="text-zinc-900 font-bold text-xl">Payment History</h2>
                <%= if @yearly_stats && (@yearly_stats.nights > 0 || @yearly_stats.events > 0) do %>
                  <div class="bg-gradient-to-r from-blue-50 to-indigo-50 border border-blue-200 rounded-xl p-4">
                    <p class="text-sm text-blue-900 font-semibold">
                      In {@yearly_stats_year}, you've enjoyed
                      <%= if @yearly_stats.nights > 0 do %>
                        <strong>{@yearly_stats.nights}</strong>
                        {if @yearly_stats.nights == 1,
                          do: "night",
                          else: "nights"} at the cabins {if @yearly_stats.events >
                                                              0,
                                                            do: "and",
                                                            else: ""}
                      <% end %>
                      <%= if @yearly_stats.events > 0 do %>
                        attended <strong>{@yearly_stats.events}</strong>
                        {if @yearly_stats.events == 1,
                          do: "club event",
                          else: "club events"}!
                      <% else %>
                        !
                      <% end %>
                    </p>
                  </div>
                <% end %>
              </div>
              <!-- Loading state for payments -->
              <div
                :if={assigns[:loading_payments]}
                class="flex items-center justify-center py-12"
              >
                <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600">
                </div>
                <span class="ml-3 text-zinc-600">Loading payment history...</span>
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
                  class="md:hidden space-y-4"
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
                  <p class="text-zinc-600 text-sm">No payments found.</p>
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
      if params["retry_invoice"] do
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
      |> assign(:public_key, public_key)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:change_membership_button, false)
      |> assign(:membership_change_info, nil)
      |> assign(:show_reauth_modal, false)
      |> assign(:reauth_verified_at, nil)
      |> assign(:pending_email_change, nil)
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
      # Address form with placeholder - will be populated when connected
      |> assign(:address_form, to_form(Accounts.change_billing_address(user)))
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
        external: &presign_avatar_upload/2,
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
        |> assign(:yearly_stats, nil)
        |> assign(:yearly_stats_year, nil)
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

    {:noreply,
     socket
     |> assign(:user, user)
     |> assign(:scheduled_downgrade_info, scheduled_downgrade_info)
     |> assign(:primary_user, primary_user)
     |> assign(:membership_paused_by_board, board_member)
     |> assign(:payment_intent_secret, payment_intent_secret)
     |> assign(:default_payment_method, default_payment_method)
     |> assign(:all_payment_methods, all_payment_methods)
     |> assign(:loading_payment_methods, false)
     |> assign(:show_new_payment_form, show_new_payment_form)
     |> assign(:address_form, to_form(address_changeset))
     |> assign(
       :membership_form,
       to_form(%{"membership_type" => membership_type_to_select})
     )
     |> assign(:notification_form, to_form(notification_changeset))
     |> assign(:pending_family_invites, pending_family_invites)
     |> assign(:loading_notification_preferences, false)
     |> assign(:user_avatars, load_user_avatars(user))
     |> assign(:loading_avatars, false)
     |> assign(:current_avatar_url, resolve_current_avatar_url(user))}
  end

  # Handle async data loading for payments tab
  def handle_info(:load_payments_data, socket) do
    user = socket.assigns.user
    per_page = socket.assigns.payments_per_page

    parallel =
      [
        {:payments,
         fn -> Ledgers.list_user_payments_paginated(user.id, 1, per_page) end},
        {:entitlements, fn -> Entitlements.list_usable_for_user(user.id) end},
        {:reservations,
         fn -> Events.list_active_ticket_holds_for_user(user.id) end}
      ]
      |> async_stream_with_repo(fn {key, fun} -> {key, fun.()} end,
        max_concurrency: 3,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
        Map.put(acc, key, value)
      end)

    {all_payments, total_count} = Map.fetch!(parallel, :payments)
    booking_entitlements = Map.fetch!(parallel, :entitlements)
    ticket_reservations = Map.fetch!(parallel, :reservations)

    total_pages = div(total_count + per_page - 1, per_page)

    # Calculate yearly impact stats
    yearly_stats_year = pst_today().year
    yearly_stats = calculate_yearly_stats(all_payments)

    {:noreply,
     socket
     |> assign(:payments_total, total_count)
     |> assign(:payments_total_pages, total_pages)
     |> assign(:all_payments, all_payments)
     |> stream(:payments, all_payments, reset: true, dom_id: &payment_dom_id/1)
     |> assign(:filtered_payments_count, length(all_payments))
     |> assign(:filtered_payments_list, all_payments)
     |> assign(:yearly_stats, yearly_stats)
     |> assign(:yearly_stats_year, yearly_stats_year)
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
     |> assign(:loading_payments, false)}
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
    {:noreply, process_email_change_after_reauth(socket)}
  end

  def handle_info(:reauth_cancelled, socket) do
    {:noreply,
     socket
     |> assign(:show_reauth_modal, false)
     |> assign(:pending_email_change, nil)}
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
        socket = assign(socket, :pending_email_change, new_email)

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

    uploaded_avatars =
      consume_uploaded_entries(socket, :avatar, fn %{key: key}, _entry ->
        location = S3Config.object_url(key, S3Config.avatars_bucket_name())

        with {:ok, avatar} <-
               Avatars.create_avatar(user, %{
                 source: :upload,
                 original_path: location
               }),
             {:ok, _job} <-
               %{id: avatar.id}
               |> YscWeb.Workers.AvatarProcessor.new()
               |> Oban.insert() do
          {:ok, avatar}
        else
          {:error, reason} -> {:error, reason}
        end
      end)

    socket =
      case uploaded_avatars do
        [_avatar | _] ->
          socket
          |> YscWeb.Flash.put_toast(
            :info,
            "Photo uploaded! It will be ready shortly.",
            title: "Profile Picture"
          )
          |> assign(:user_avatars, load_user_avatars(user))
          |> assign(:avatar_processing, true)

        _ ->
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
      # Phone number is being changed - handle with verification

      # First, update other profile fields (excluding phone)
      other_params = Map.delete(user_params, "phone_number")

      case Accounts.update_user_profile(user, other_params) do
        {:ok, updated_user} ->
          # Send verification code to new phone number.
          # Use timestamp in suffix so idempotency key is unique per attempt (e.g. user
          # switching back to the same number later can receive a new code).
          timestamp = DateTime.utc_now() |> DateTime.to_unix()

          phone_code =
            Accounts.generate_and_store_phone_verification_code(updated_user)

          _job =
            Accounts.send_phone_verification_code(
              updated_user,
              phone_code,
              "settings_change_#{timestamp}",
              new_phone
            )

          # Update form and store pending phone number
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

          {:noreply,
           socket
           |> assign(:user, updated_user)
           |> assign(:profile_form, profile_form)
           |> assign(:pending_phone_number, new_phone)
           |> assign(:phone_verification_code_state, %{})
           |> push_patch(to: path)
           |> YscWeb.Flash.put_toast(
             :info,
             "Phone number update initiated. Please verify the code sent to your new number.",
             title: "Phone",
             icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, profile_form: to_form(changeset))}
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

      # Basic validation - ensure it's 6 digits
      is_valid =
        String.length(normalized_code) == 6 &&
          String.match?(normalized_code, ~r/^\d{6}$/)

      {:noreply,
       socket
       |> assign(phone_code_valid: is_valid, phone_verification_error: nil)
       |> assign(phone_verification_code_state: merged_code)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("verify_phone_code", params, socket) do
    # Ensure user has pending phone verification
    pending_phone = socket.assigns.pending_phone_number
    user = socket.assigns.current_user

    if pending_phone do
      case params do
        %{"verification_code" => entered_code} ->
          # Handle both OTP array format and single string format
          code = normalize_verification_code(entered_code)

          # In dev/sandbox, always accept 000000 as valid code
          verification_result =
            if dev_or_sandbox?() and code == "000000" do
              {:ok, :verified}
            else
              Accounts.verify_phone_verification_code(user, code)
            end

          case verification_result do
            {:ok, :verified} ->
              # Update user's phone number and mark as verified
              phone_params = %{"phone_number" => pending_phone}

              case Accounts.update_user_phone_and_sms(user, phone_params) do
                {:ok, updated_user} ->
                  {:ok, _} = Accounts.mark_phone_verified(updated_user)

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
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

            {:error, :not_found} ->
              {:noreply,
               socket
               |> assign(
                 :phone_verification_error,
                 "No verification code found. Please request a new one."
               )}

            {:error, :expired} ->
              {:noreply,
               socket
               |> assign(
                 :phone_verification_error,
                 "Verification code has expired. Please request a new one."
               )}

            {:error, :invalid_code} ->
              {:noreply,
               socket
               |> assign(
                 :phone_verification_error,
                 "Invalid verification code. Please try again."
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
    # Ensure user has pending phone verification
    pending_phone = socket.assigns.pending_phone_number
    user = socket.assigns.current_user

    if pending_phone do
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

          _job =
            Accounts.send_phone_verification_code(
              user,
              code,
              suffix,
              pending_phone
            )

          {:noreply,
           socket
           |> assign(
             :sms_resend_disabled_until,
             Ysc.ResendRateLimiter.disabled_until(60)
           )
           |> YscWeb.Flash.put_toast(
             :info,
             "Verification code sent to your phone.",
             title: "Phone",
             icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
           )}

        {:error, :rate_limited, _remaining} ->
          # Rate limited
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

      is_valid =
        String.length(normalized_code) == 6 &&
          String.match?(normalized_code, ~r/^\d{6}$/)

      {:noreply,
       socket
       |> assign(email_code_valid: is_valid, email_verification_error: nil)
       |> assign(:email_verification_code_state, merged_code)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("verify_email_code", params, socket) do
    # Ensure user has pending email verification
    pending_email = socket.assigns.pending_email
    user = socket.assigns.current_user

    if pending_email do
      case params do
        %{"verification_code" => entered_code} ->
          code = normalize_verification_code(entered_code)

          verification_result =
            Accounts.verify_email_verification_code(user, code)

          case verification_result do
            {:ok, :verified} ->
              # Update user's email address and mark as verified
              email_params = %{"email" => pending_email}

              case user
                   |> Accounts.User.email_changeset(email_params)
                   |> Ecto.Changeset.put_change(
                     :email_verified_at,
                     DateTime.utc_now() |> DateTime.truncate(:second)
                   )
                   |> Ysc.Repo.update() do
                {:ok, updated_user} ->
                  # Send email changed notification to the old email address for security
                  old_email = user.email

                  if old_email != updated_user.email do
                    UserNotifier.deliver_email_changed_notification(
                      updated_user,
                      old_email,
                      updated_user.email
                    )

                    # Update newsletter subscription to new email if enabled
                    Accounts.update_newsletter_on_email_change(
                      updated_user,
                      old_email,
                      updated_user.email
                    )
                  end

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
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

            {:error, :not_found} ->
              {:noreply,
               socket
               |> assign(
                 :email_verification_error,
                 "No verification code found. Please request a new one."
               )}

            {:error, :expired} ->
              {:noreply,
               socket
               |> assign(
                 :email_verification_error,
                 "Verification code has expired. Please request a new one."
               )}

            {:error, :invalid_code} ->
              {:noreply,
               socket
               |> assign(
                 :email_verification_error,
                 "Invalid verification code. Please try again."
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
    # Ensure user has pending email verification
    pending_email = socket.assigns.pending_email
    user = socket.assigns.current_user

    if pending_email do
      user_id = user.id

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
                  Accounts.generate_and_store_email_verification_code(user)

                {new_code, false}
            end

          # Send the code via email
          timestamp = DateTime.utc_now() |> DateTime.to_unix()

          suffix =
            if is_existing,
              do: "resend_existing_#{timestamp}",
              else: "resend_new_#{timestamp}"

          _job =
            Accounts.send_email_verification_code(
              user,
              code,
              suffix,
              pending_email
            )

          {:noreply,
           socket
           |> assign(
             :email_resend_disabled_until,
             Ysc.ResendRateLimiter.disabled_until(60)
           )
           |> YscWeb.Flash.put_toast(
             :info,
             "Verification code sent to your email.",
             title: "Email",
             icon: &YscWeb.CoreComponents.flash_toast_icon_mail/1
           )}

        {:error, :rate_limited, _remaining} ->
          # Rate limited
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
           "Linked family members cannot purchase a separate membership. Your benefits are included in the primary account holder's family membership.",
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
               "Linked family members cannot purchase a separate membership. Your benefits are included in the primary account holder's family membership.",
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

                  {:noreply,
                   socket
                   |> assign(:user, updated_user)
                   |> assign(:all_payment_methods, updated_payment_methods)
                   |> assign(:default_payment_method, updated_default)
                   |> assign(:show_new_payment_form, false)
                   |> YscWeb.Flash.put_toast(
                     :info,
                     "Payment method updated and set as default.",
                     title: "Payment",
                     icon: &YscWeb.CoreComponents.flash_toast_icon_payment/1
                   )
                   |> push_patch(to: ~p"/users/membership")}

                {:error, stripe_error} ->
                  {:noreply,
                   YscWeb.Flash.put_toast(
                     socket,
                     :error,
                     "Payment method saved but failed to set as default in Stripe: #{stripe_error.message}",
                     title: "Payment"
                   )}
              end

            {:error, _reason} ->
              {:noreply,
               YscWeb.Flash.put_toast(
                 socket,
                 :error,
                 "Failed to store payment method",
                 title: "Payment"
               )}
          end

        {:error, _reason} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Failed to retrieve payment method from Stripe",
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
         "Failed to create payment account. Please try again or contact support.",
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
             "Failed to initialize payment form: #{error_message}",
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
             "Auto-renewal is off. You'll keep access until the end of your current billing period.",
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
           "Scheduled downgrade cancelled. Your membership will stay at its current level.",
           title: "Membership"
         )
         |> push_patch(to: ~p"/users/membership")}

      {:error, :no_scheduled_downgrade} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, "No scheduled downgrade found.",
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

    filtered_payments =
      apply_payment_filter(socket.assigns.all_payments, filter_atom)

    {:noreply,
     socket
     |> assign(:payment_filter, filter_atom)
     |> assign(:filtered_payments_count, length(filtered_payments))
     |> assign(:filtered_payments_list, filtered_payments)
     |> stream(:payments, filtered_payments,
       reset: true,
       dom_id: &payment_dom_id/1
     )}
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

    # Send verification code to new email address
    email_code = Accounts.generate_and_store_email_verification_code(user)

    # Include timestamp in suffix to make idempotency key unique for each email change attempt
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    suffix = "email_change_#{timestamp}"

    _job =
      Accounts.send_email_verification_code(user, email_code, suffix, new_email)

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
    |> assign(:email_verification_error, nil)
    |> assign(:email_code_valid, false)
    |> push_patch(to: path)
  end

  defp reauth_still_valid?(socket) do
    case socket.assigns[:session_reauth_expires_at] do
      ts when is_integer(ts) -> ts > DateTime.utc_now() |> DateTime.to_unix()
      _ -> false
    end
  end

  defp validate_user_active(user) do
    if user.state == :active, do: :ok, else: {:error, :user_not_active}
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

  defp handle_stripe_error(socket, stripe_error) do
    {:noreply,
     revert_optimistic_update(socket)
     |> YscWeb.Flash.put_toast(
       :error,
       "Failed to update default payment method in Stripe: #{stripe_error.message}",
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

  @dialyzer {:nowarn_function, format_payment_error: 1}
  defp format_payment_error(%Stripe.Error{code: code})
       when code in [:card_declined, "card_declined"] do
    "Your card was declined. Please try a different payment method or contact your bank."
  end

  defp format_payment_error(%Stripe.Error{message: message})
       when is_binary(message) do
    message
  end

  defp format_payment_error(error) when is_binary(error) do
    if String.contains?(String.downcase(error), "declined") do
      "Your card was declined. Please try a different payment method or contact your bank."
    else
      error
    end
  end

  defp invalidate_membership_cache(user) do
    MembershipCache.invalidate_user(user.id)
    sub_accounts = Accounts.get_sub_accounts(user)

    Enum.each(sub_accounts, fn sub_account ->
      MembershipCache.invalidate_user(sub_account.id)
    end)
  end

  defp get_success_message(:upgrade) do
    "Your membership plan has been upgraded. You have been charged the prorated difference."
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

  # Helper function to normalize verification code from OTP array/map or string format
  defp normalize_verification_code(code) when is_map(code) do
    # Handle map format: %{"0" => "1", "1" => "2", ...}; form may include "_unused_N" keys
    code
    |> Enum.filter(fn {k, _v} -> match?({_, _}, Integer.parse(k)) end)
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

  defp paginate_payments(socket, new_page) when new_page >= 1 do
    %{payments_per_page: per_page, payments_total: total_count, user: user} =
      socket.assigns

    {all_payments, _total_count} =
      Ledgers.list_user_payments_paginated(user.id, new_page, per_page)

    total_pages = div(total_count + per_page - 1, per_page)

    # Apply current filter to new page
    filter = socket.assigns[:payment_filter] || :all
    filtered_payments = apply_payment_filter(all_payments, filter)

    socket
    |> assign(:payments_page, new_page)
    |> assign(:payments_total_pages, total_pages)
    |> assign(:all_payments, all_payments)
    |> assign(:filtered_payments_count, length(filtered_payments))
    |> assign(:filtered_payments_list, filtered_payments)
    |> stream(:payments, filtered_payments,
      reset: true,
      dom_id: &payment_dom_id/1
    )
  end

  defp apply_payment_filter(payments, :all), do: payments

  defp apply_payment_filter(payments, :tahoe) do
    Enum.filter(payments, fn payment_info ->
      payment_info.type == :booking &&
        payment_info.booking &&
        payment_info.booking.property == :tahoe
    end)
  end

  defp apply_payment_filter(payments, :clear_lake) do
    Enum.filter(payments, fn payment_info ->
      payment_info.type == :booking &&
        payment_info.booking &&
        payment_info.booking.property == :clear_lake
    end)
  end

  defp apply_payment_filter(payments, :events) do
    Enum.filter(payments, fn payment_info -> payment_info.type == :ticket end)
  end

  defp apply_payment_filter(payments, :donations) do
    Enum.filter(payments, fn payment_info -> payment_info.type == :donation end)
  end

  defp apply_payment_filter(payments, :membership) do
    Enum.filter(payments, fn payment_info ->
      payment_info.type == :membership
    end)
  end

  defp apply_payment_filter(payments, _), do: payments

  defp calculate_yearly_stats(payments) do
    current_year = pst_today().year

    stats =
      Enum.reduce(
        payments,
        %{nights: 0, events: 0, total_amount: Money.new(0, :USD)},
        fn payment_info, acc ->
          # Check if payment is from current year
          payment_date =
            cond do
              payment_info.payment && payment_info.payment.payment_date ->
                to_pst_date(payment_info.payment.payment_date)

              payment_info.payment && payment_info.payment.inserted_at ->
                to_pst_date(payment_info.payment.inserted_at)

              payment_info.ticket_order && payment_info.ticket_order.inserted_at ->
                to_pst_date(payment_info.ticket_order.inserted_at)

              true ->
                nil
            end

          if payment_date && payment_date.year == current_year do
            acc
            |> add_booking_nights(payment_info)
            |> add_event_count(payment_info)
            |> add_payment_amount(payment_info)
          else
            acc
          end
        end
      )

    stats
  end

  defp add_booking_nights(acc, %{type: :booking, booking: booking})
       when not is_nil(booking) do
    nights = Date.diff(booking.checkout_date, booking.checkin_date)
    Map.update(acc, :nights, nights, &(&1 + nights))
  end

  defp add_booking_nights(acc, _), do: acc

  defp add_event_count(acc, %{type: :ticket}) do
    Map.update(acc, :events, 1, &(&1 + 1))
  end

  defp add_event_count(acc, _), do: acc

  defp add_payment_amount(acc, %{payment: payment}) when not is_nil(payment) do
    case Money.add(acc.total_amount, payment.amount) do
      {:ok, new_total} -> %{acc | total_amount: new_total}
      _ -> acc
    end
  end

  defp add_payment_amount(acc, _), do: acc

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

  defp card_icon("visa"),
    do:
      "M470.1 231.3s7.6 37.2 9.3 45H446c3.3-8.9 16-43.5 16-43.5-.2.3 3.3-9.1 5.3-14.9l2.8 13.4zM576 80v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V80c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM152.5 331.2L215.7 176h-42.5l-39.3 106-4.3-21.5-14-71.4c-2.3-9.9-9.4-12.7-18.2-13.1H32.7l-.7 3.1c15.8 4 29.9 9.8 42.2 17.1l35.8 135h42.5zm94.4.2L272.1 176h-40.2l-25.1 155.4h40.1zm139.9-50.8c.2-17.7-10.6-31.2-33.7-42.3-14.1-7.1-22.7-11.9-22.7-19.2.2-6.6 7.3-13.4 23.1-13.4 13.1-.3 22.7 2.8 29.9 5.9l3.6 1.7 5.5-33.6c-7.9-3.1-20.5-6.6-36-6.6-39.7 0-67.6 21.2-67.8 51.4-.3 22.3 20 34.7 35.2 42.2 15.5 7.6 20.8 12.6 20.8 19.3-.2 10.4-12.6 15.2-24.1 15.2-16 0-24.6-2.5-37.7-8.3l-5.3-2.5-5.6 34.9c9.4 4.3 26.8 8.1 44.8 8.3 42.2.1 69.7-20.8 70-53zM528 331.4L495.6 176h-31.1c-9.6 0-16.9 2.8-21 12.9l-59.7 142.5H426s6.9-19.2 8.4-23.3H486c1.2 5.5 4.8 23.3 4.8 23.3H528z"

  defp card_icon("mastercard"),
    do:
      "M482.9 410.3c0 6.8-4.6 11.7-11.2 11.7-6.8 0-11.2-5.2-11.2-11.7 0-6.5 4.4-11.7 11.2-11.7 6.6 0 11.2 5.2 11.2 11.7zm-310.8-11.7c-7.1 0-11.2 5.2-11.2 11.7 0 6.5 4.1 11.7 11.2 11.7 6.5 0 10.9-4.9 10.9-11.7-.1-6.5-4.4-11.7-10.9-11.7zm117.5-.3c-5.4 0-8.7 3.5-9.5 8.7h19.1c-.9-5.7-4.4-8.7-9.6-8.7zm107.8.3c-6.8 0-10.9 5.2-10.9 11.7 0 6.5 4.1 11.7 10.9 11.7 6.8 0 11.2-4.9 11.2-11.7 0-6.5-4.4-11.7-11.2-11.7zm105.9 26.1c0 .3.3.5.3 1.1 0 .3-.3.5-.3 1.1-.3.3-.3.5-.5.8-.3.3-.5.5-1.1.5-.3.3-.5.3-1.1.3-.3 0-.5 0-1.1-.3-.3 0-.5-.3-.8-.5-.3-.3-.5-.5-.5-.8-.3-.5-.3-.8-.3-1.1 0-.5 0-.8.3-1.1 0-.5.3-.8.5-1.1.3-.3.5-.3.8-.5.5-.3.8-.3 1.1-.3.5 0 .8 0 1.1.3.5.3.8.3 1.1.5s.2.6.5 1.1zm-2.2 1.4c.5 0 .5-.3.8-.3.3-.3.3-.5.3-.8 0-.3 0-.5-.3-.8-.3 0-.5-.3-1.1-.3h-1.6v3.5h.8V426h.3l1.1 1.4h.8l-1.1-1.3zM576 81v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V81c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM64 220.6c0 76.5 62.1 138.5 138.5 138.5 27.2 0 53.9-8.2 76.5-23.1-72.9-59.3-72.4-171.2 0-230.5-22.6-15-49.3-23.1-76.5-23.1-76.4-.1-138.5 62-138.5 138.2zm224 108.8c70.5-55 70.2-162.2 0-217.5-70.2 55.3-70.5 162.6 0 217.5zm-142.3 76.3c0-8.7-5.7-14.4-14.7-14.7-4.6 0-9.5 1.4-12.8 6.5-2.4-4.1-6.5-6.5-12.2-6.5-3.8 0-7.6 1.4-10.6 5.4V392h-8.2v36.7h8.2c0-18.9-2.5-30.2 9-30.2 10.2 0 8.2 10.2 8.2 30.2h7.9c0-18.3-2.5-30.2 9-30.2 10.2 0 8.2 10 8.2 30.2h8.2v-23zm44.9-13.7h-7.9v4.4c-2.7-3.3-6.5-5.4-11.7-5.4-10.3 0-18.2 8.2-18.2 19.3 0 11.2 7.9 19.3 18.2 19.3 5.2 0 9-1.9 11.7-5.4v4.6h7.9V392zm40.5 25.6c0-15-22.9-8.2-22.9-15.2 0-5.7 11.9-4.8 18.5-1.1l3.3-6.5c-9.4-6.1-30.2-6-30.2 8.2 0 14.3 22.9 8.3 22.9 15 0 6.3-13.5 5.8-20.7.8l-3.5 6.3c11.2 7.6 32.6 6 32.6-7.5zm35.4 9.3l-2.2-6.8c-3.8 2.1-12.2 4.4-12.2-4.1v-16.6h13.1V392h-13.1v-11.2h-8.2V392h-7.6v7.3h7.6V416c0 17.6 17.3 14.4 22.6 10.9zm13.3-13.4h27.5c0-16.2-7.4-22.6-17.4-22.6-10.6 0-18.2 7.9-18.2 19.3 0 20.5 22.6 23.9 33.8 14.2l-3.8-6c-7.8 6.4-19.6 5.8-21.9-4.9zm59.1-21.5c-4.6-2-11.6-1.8-15.2 4.4V392h-8.2v36.7h8.2V408c0-11.6 9.5-10.1 12.8-8.4l2.4-7.6zm10.6 18.3c0-11.4 11.6-15.1 20.7-8.4l3.8-6.5c-11.6-9.1-32.7-4.1-32.7 15 0 19.8 22.4 23.8 32.7 15l-3.8-6.5c-9.2 6.5-20.7 2.6-20.7-8.6zm66.7-18.3H408v4.4c-8.3-11-29.9-4.8-29.9 13.9 0 19.2 22.4 24.7 29.9 13.9v4.6h8.2V392zm33.7 0c-2.4-1.2-11-2.9-15.2 4.4V392h-7.9v36.7h7.9V408c0-11 9-10.3 12.8-8.4l2.4-7.6zm40.3-14.9h-7.9v19.3c-8.2-10.9-29.9-5.1-29.9 13.9 0 19.4 22.5 24.6 29.9 13.9v4.6h7.9v-51.7zm7.6-75.1v4.6h.8V302h1.9v-.8h-4.6v.8h1.9zm6.6 123.8c0-.5 0-1.1-.3-1.6-.3-.3-.5-.8-.8-1.1-.3-.3-.8-.5-1.1-.8-.5 0-1.1-.3-1.6-.3-.3 0-.8.3-1.4.3-.5.3-.8.5-1.1.8-.5.3-.8.8-.8 1.1-.3.5-.3 1.1-.3 1.6 0 .3 0 .8.3 1.4 0 .3.3.8.8 1.1.3.3.5.5 1.1.8.5.3 1.1.3 1.4.3.5 0 1.1 0 1.6-.3.3-.3.8-.5 1.1-.8.3-.3.5-.8.8-1.1.3-.6.3-1.1.3-1.4zm3.2-124.7h-1.4l-1.6 3.5-1.6-3.5h-1.4v5.4h.8v-4.1l1.6 3.5h1.1l1.4-3.5v4.1h1.1v-5.4zm4.4-80.5c0-76.2-62.1-138.3-138.5-138.3-27.2 0-53.9 8.2-76.5 23.1 72.1 59.3 73.2 171.5 0 230.5 22.6 15 49.5 23.1 76.5 23.1 76.4.1 138.5-61.9 138.5-138.4z"

  defp card_icon("amex"),
    do:
      "M0 432c0 26.5 21.5 48 48 48H528c26.5 0 48-21.5 48-48v-1.1H514.3l-31.9-35.1-31.9 35.1H246.8V267.1H181L262.7 82.4h78.6l28.1 63.2V82.4h97.2L483.5 130l17-47.6H576V80c0-26.5-21.5-48-48-48H48C21.5 32 0 53.5 0 80V432zm440.4-21.7L482.6 364l42 46.3H576l-68-72.1 68-72.1H525.4l-42 46.7-41.5-46.7H390.5L458 338.6l-67.4 71.6V377.1h-83V354.9h80.9V322.6H307.6V300.2h83V267.1h-122V410.3H440.4zm96.3-72L576 380.2V296.9l-39.3 41.4zm-36.3-92l36.9-100.6V246.3H576V103H515.8l-32.2 89.3L451.7 103H390.5V246.1L327.3 103H276.1L213.7 246.3h43l11.9-28.7h65.9l12 28.7h82.7V146L466 246.3h34.4zM282 185.4l19.5-46.9 19.4 46.9H282z"

  defp card_icon("discover"),
    do:
      "M520.4 196.1c0-7.9-5.5-12.1-15.6-12.1h-4.9v24.9h4.7c10.3 0 15.8-4.4 15.8-12.8zM528 32H48C21.5 32 0 53.5 0 80v352c0 26.5 21.5 48 48 48h480c26.5 0 48-21.5 48-48V80c0-26.5-21.5-48-48-48zm-44.1 138.9c22.6 0 52.9-4.1 52.9 24.4 0 12.6-6.6 20.7-18.7 23.2l25.8 34.4h-19.6l-22.2-32.8h-2.2v32.8h-16zm-55.9.1h45.3v14H444v18.2h28.3V217H444v22.2h29.3V253H428zm-68.7 0l21.9 55.2 22.2-55.2h17.5l-35.5 84.2h-8.6l-35-84.2zm-55.9-3c24.7 0 44.6 20 44.6 44.6 0 24.7-20 44.6-44.6 44.6-24.7 0-44.6-20-44.6-44.6 0-24.7 20-44.6 44.6-44.6zm-49.3 6.1v19c-20.1-20.1-46.8-4.7-46.8 19 0 25 27.5 38.5 46.8 19.2v19c-29.7 14.3-63.3-5.7-63.3-38.2 0-31.2 33.1-53 63.3-38zm-97.2 66.3c11.4 0 22.4-15.3-3.3-24.4-15-5.5-20.2-11.4-20.2-22.7 0-23.2 30.6-31.4 49.7-14.3l-8.4 10.8c-10.4-11.6-24.9-6.2-24.9 2.5 0 4.4 2.7 6.9 12.3 10.3 18.2 6.6 23.6 12.5 23.6 25.6 0 29.5-38.8 37.4-56.6 11.3l10.3-9.9c3.7 7.1 9.9 10.8 17.5 10.8zM55.4 253H32v-82h23.4c26.1 0 44.1 17 44.1 41.1 0 18.5-13.2 40.9-44.1 40.9zm67.5 0h-16v-82h16zM544 433c0 8.2-6.8 15-15 15H128c189.6-35.6 382.7-139.2 416-160zM74.1 191.6c-5.2-4.9-11.6-6.6-21.9-6.6H48v54.2h4.2c10.3 0 17-2 21.9-6.4 5.7-5.2 8.9-12.8 8.9-20.7s-3.2-15.5-8.9-20.5z"

  defp card_icon("jcb"),
    do:
      "M431.5 244.3V212c41.2 0 38.5.2 38.5.2 7.3 1.3 13.3 7.3 13.3 16 0 8.8-6 14.5-13.3 15.8-1.2.4-3.3.3-38.5.3zm42.8 20.2c-2.8-.7-3.3-.5-42.8-.5v35c39.6 0 40 .2 42.8-.5 7.5-1.5 13.5-8 13.5-17 0-8.7-6-15.5-13.5-17zM576 80v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V80c0-26.5 21.5-48 48-48h480c26.5 0 48 21.5 48 48zM182 192.3h-57c0 67.1 10.7 109.7-35.8 109.7-19.5 0-38.8-5.7-57.2-14.8v28c30 8.3 68 8.3 68 8.3 97.9 0 82-47.7 82-131.2zm178.5 4.5c-63.4-16-165-14.9-165 59.3 0 77.1 108.2 73.6 165 59.2V287C312.9 311.7 253 309 253 256s59.8-55.6 107.5-31.2v-28zM544 286.5c0-18.5-16.5-30.5-38-32v-.8c19.5-2.7 30.3-15.5 30.3-30.2 0-19-15.7-30-37-31 0 0 6.3-.3-120.3-.3v127.5h122.7c24.3.1 42.3-12.9 42.3-33.2z"

  defp card_icon("diners"),
    do:
      "M239.7 79.9c-96.9 0-175.8 78.6-175.8 175.8 0 96.9 78.9 175.8 175.8 175.8 97.2 0 175.8-78.9 175.8-175.8 0-97.2-78.6-175.8-175.8-175.8zm-39.9 279.6c-41.7-15.9-71.4-56.4-71.4-103.8s29.7-87.9 71.4-104.1v207.9zm79.8.3V151.6c41.7 16.2 71.4 56.7 71.4 104.1s-29.7 87.9-71.4 104.1zM528 32H48C21.5 32 0 53.5 0 80v352c0 26.5 21.5 48 48 48h480c26.5 0 48-21.5 48-48V80c0-26.5-21.5-48-48-48zM329.7 448h-90.3c-106.2 0-193.8-85.5-193.8-190.2C45.6 143.2 133.2 64 239.4 64h90.3c105 0 200.7 79.2 200.7 193.8 0 104.7-95.7 190.2-200.7 190.2z"

  defp card_icon(_), do: "hero-credit-card"

  defp payment_method_icon(%{type: :card, display_brand: brand}),
    do: card_icon(brand)

  defp payment_method_icon(%{type: :bank_account}), do: bank_account_icon()
  defp payment_method_icon(_), do: "hero-credit-card"

  defp bank_account_icon(),
    do:
      "M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z"

  defp payment_method_display_text(%{type: :card, last_four: last_four})
       when not is_nil(last_four) do
    "**** **** **** #{last_four}"
  end

  defp payment_method_display_text(%{
         type: :bank_account,
         bank_name: bank_name,
         account_type: _account_type,
         last_four: last_four
       })
       when not is_nil(bank_name) and not is_nil(last_four) do
    "#{bank_name} ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :bank_account, last_four: last_four})
       when not is_nil(last_four) do
    "Bank Account ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :card}) do
    "Credit Card"
  end

  defp payment_method_display_text(%{type: :bank_account}) do
    "Bank Account"
  end

  defp payment_method_display_text(_) do
    "Payment Method"
  end

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

  # Helper function to get refund data for a payment
  defp get_refund_data_for_payment(payment) do
    alias Ysc.Ledgers.Refund

    # Get processed refunds for this payment
    processed_refunds =
      from(r in Refund,
        where: r.payment_id == ^payment.id,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()

    # Calculate total refunded amount
    processed_total =
      Enum.reduce(processed_refunds, Money.new(0, :USD), fn refund, acc ->
        case Money.add(acc, refund.amount) do
          {:ok, sum} -> sum
          _ -> acc
        end
      end)

    if Money.positive?(processed_total) do
      %{
        processed_refunds: processed_refunds,
        total_refunded: processed_total
      }
    else
      nil
    end
  end

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
        get_payment_icon_bg(@payment_info)
      ]}>
        <.icon
          name={get_payment_icon(@payment_info)}
          class={[
            "w-6 h-6",
            get_payment_icon_color(@payment_info)
          ]}
        />
      </div>
      <div class="flex-1">
        <div class="flex items-center gap-2">
          <h3 class="font-bold text-zinc-900 text-lg leading-tight">
            {get_payment_title(@payment_info)}
          </h3>
          <%= if @payment_info.type == :booking && @payment_info.booking && @payment_info.booking.status == :canceled do %>
            <.badge type="red">Cancelled</.badge>
          <% end %>
          <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
            <.badge type="red">Cancelled</.badge>
          <% end %>
        </div>
        <p class="text-xs font-mono text-zinc-400 mt-1">
          {get_payment_reference(@payment_info)}
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
          refund_data = get_refund_data_for_payment(@payment_info.payment)

          if refund_data && refund_data.total_refunded do
            " A refund of #{Ysc.MoneyHelper.format_money!(refund_data.total_refunded)} has been processed."
          else
            " Refund information is available in the booking details."
          end
        end}
      </div>
    <% end %>

    <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
      <div class="mb-3 p-2 bg-red-50 border border-red-200 rounded text-xs text-red-800">
        <strong>Order Cancelled:</strong>
        This ticket order has been cancelled. {if @payment_info.payment do
          refund_data = get_refund_data_for_payment(@payment_info.payment)

          if refund_data && refund_data.total_refunded do
            " A refund of #{Ysc.MoneyHelper.format_money!(refund_data.total_refunded)} has been processed."
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
    do: "View ticket order confirmation"

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
            get_payment_icon_bg(@payment_info)
          ]}>
            <.icon
              name={get_payment_icon(@payment_info)}
              class={[
                "w-5 h-5",
                get_payment_icon_color(@payment_info)
              ]}
            />
          </div>
          <div>
            <div class="flex items-center gap-2">
              <h3 class="font-bold text-zinc-900 text-sm">
                {get_payment_title(@payment_info)}
              </h3>
              <%= if @payment_info.type == :booking && @payment_info.booking && @payment_info.booking.status == :canceled do %>
                <.badge type="red" class="text-xs">Cancelled</.badge>
              <% end %>
              <%= if @payment_info.type == :ticket && @payment_info.ticket_order && @payment_info.ticket_order.status == :cancelled do %>
                <.badge type="red" class="text-xs">Cancelled</.badge>
              <% end %>
            </div>
            <p class="text-xs font-mono text-zinc-400 mt-0.5">
              {get_payment_reference(@payment_info)}
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

  # Helper functions for payment rendering
  defp get_payment_icon(%{type: :booking, booking: booking})
       when not is_nil(booking) do
    "hero-home"
  end

  defp get_payment_icon(%{type: :ticket}), do: "hero-ticket"
  defp get_payment_icon(%{type: :membership}), do: "hero-heart"
  defp get_payment_icon(%{type: :donation}), do: "hero-gift"
  defp get_payment_icon(_), do: "hero-credit-card"

  defp get_payment_icon_bg(%{type: :booking, booking: booking})
       when not is_nil(booking) do
    case booking.property do
      :tahoe -> "bg-blue-50 group-hover:bg-blue-600"
      :clear_lake -> "bg-emerald-50 group-hover:bg-emerald-600"
      _ -> "bg-purple-50 group-hover:bg-purple-600"
    end
  end

  defp get_payment_icon_bg(%{type: :ticket}),
    do: "bg-purple-50 group-hover:bg-purple-600"

  defp get_payment_icon_bg(%{type: :membership}),
    do: "bg-teal-50 group-hover:bg-teal-600"

  defp get_payment_icon_bg(%{type: :donation}),
    do: "bg-yellow-50 group-hover:bg-yellow-600"

  defp get_payment_icon_bg(_), do: "bg-zinc-50 group-hover:bg-zinc-600"

  defp get_payment_icon_color(%{type: :booking, booking: booking})
       when not is_nil(booking) do
    case booking.property do
      :tahoe -> "text-blue-600 group-hover:text-white"
      :clear_lake -> "text-emerald-600 group-hover:text-white"
      _ -> "text-purple-600 group-hover:text-white"
    end
  end

  defp get_payment_icon_color(%{type: :ticket}),
    do: "text-purple-600 group-hover:text-white"

  defp get_payment_icon_color(%{type: :membership}),
    do: "text-teal-600 group-hover:text-white"

  defp get_payment_icon_color(%{type: :donation}),
    do: "text-yellow-600 group-hover:text-white"

  defp get_payment_icon_color(_), do: "text-zinc-600 group-hover:text-white"

  defp get_payment_title(%{type: :booking, booking: booking})
       when not is_nil(booking) do
    property_name =
      case booking.property do
        :tahoe -> "Tahoe"
        :clear_lake -> "Clear Lake"
        _ -> "Cabin"
      end

    "#{property_name} Booking"
  end

  defp get_payment_title(%{type: :ticket, event: event})
       when not is_nil(event) do
    event.title
  end

  defp get_payment_title(%{type: :ticket}), do: "Event Tickets"
  defp get_payment_title(%{type: :membership}), do: "Membership Payment"
  defp get_payment_title(%{type: :donation}), do: "Donation"
  defp get_payment_title(%{description: description}), do: description
  defp get_payment_title(_), do: "Payment"

  defp get_payment_reference(%{booking: booking}) when not is_nil(booking) do
    booking.reference_id || "—"
  end

  defp get_payment_reference(%{ticket_order: ticket_order})
       when not is_nil(ticket_order) do
    ticket_order.reference_id || "—"
  end

  defp get_payment_reference(%{payment: payment}) when not is_nil(payment) do
    payment.reference_id || "—"
  end

  defp get_payment_reference(_), do: "—"

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
            {if @ticket_order.tickets do
              tickets = @ticket_order.tickets
              refunded_count = Enum.count(tickets, fn t -> t.status == :cancelled end)
              active_tickets = Enum.filter(tickets, fn t -> t.status != :cancelled end)

              ticket_summary =
                if length(active_tickets) > 0 do
                  active_tickets
                  |> Enum.group_by(fn t -> t.ticket_tier && t.ticket_tier.name end)
                  |> Enum.map(fn {tier_name, tier_tickets} ->
                    count = length(tier_tickets)
                    tier_display = tier_name || "General Admission"
                    "#{count}x #{tier_display}"
                  end)
                  |> Enum.join(", ")
                else
                  "All tickets refunded"
                end

              if refunded_count > 0 do
                "#{ticket_summary} (#{refunded_count} refunded)"
              else
                ticket_summary
              end
            else
              "No ticket details"
            end}
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
          {if @ticket_order.tickets do
            tickets = @ticket_order.tickets
            refunded_count = Enum.count(tickets, fn t -> t.status == :cancelled end)
            active_tickets = Enum.filter(tickets, fn t -> t.status != :cancelled end)

            ticket_summary =
              if length(active_tickets) > 0 do
                active_tickets
                |> Enum.group_by(fn t -> t.ticket_tier && t.ticket_tier.name end)
                |> Enum.map(fn {tier_name, tier_tickets} ->
                  count = length(tier_tickets)
                  tier_display = tier_name || "General Admission"
                  "#{count}x #{tier_display}"
                end)
                |> Enum.join(", ")
              else
                "All tickets refunded"
              end

            if refunded_count > 0 do
              "#{ticket_summary} (#{refunded_count} refunded)"
            else
              ticket_summary
            end
          else
            "No ticket details"
          end}
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
    if is_nil(payment_info.payment) do
      assigns = %{}

      ~H"""
      <.badge type="green" class="text-xs">Completed</.badge>
      """
    else
      assigns = %{payment: payment_info.payment}

      ~H"""
      <%= if @payment.status == :completed do %>
        <.badge type="green" class="text-xs">Completed</.badge>
      <% else %>
        <%= if @payment.status == :pending do %>
          <.badge type="yellow" class="text-xs">Pending</.badge>
        <% else %>
          <%= if @payment.status == :refunded do %>
            <.badge type="red" class="text-xs">Refunded</.badge>
          <% end %>
        <% end %>
      <% end %>
      """
    end
  end

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
             "Invoice not found. Please contact support if this issue persists.",
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
             "This invoice cannot be paid in its current state. Please update your payment method and try again.",
             title: "Invoice"
           )}

        {:error, error_message} when is_binary(error_message) ->
          display_message =
            if String.contains?(String.downcase(error_message), "declined") do
              "Your card was declined. Please try a different payment method or contact your bank."
            else
              "Failed to retry payment: #{error_message}. Please update your payment method and try again."
            end

          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             display_message,
             title: "Invoice"
           )}

        {:error, _reason} ->
          {:noreply,
           YscWeb.Flash.put_toast(
             socket,
             :error,
             "Your payment could not be processed. Please try a different payment method or contact your bank. If the issue persists, contact support.",
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
       "Invalid invoice ID. Please use the link from your email or contact support.",
       title: "Invoice"
     )}
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

  @allowed_avatar_extensions ~w(.jpg .jpeg .png .webp .gif .svg)

  defp presign_avatar_upload(entry, socket) do
    user = socket.assigns.current_user
    avatar_id = Ecto.ULID.generate()

    ext =
      entry.client_name
      |> Path.extname()
      |> String.downcase()
      |> then(fn e ->
        if e in @allowed_avatar_extensions, do: e, else: ".webp"
      end)

    key = "#{user.id}/#{avatar_id}/original#{ext}"

    config = %{
      region: S3Config.region(),
      access_key_id: S3Config.aws_access_key_id(),
      secret_access_key: S3Config.aws_secret_access_key()
    }

    {:ok, fields} =
      SimpleS3Upload.sign_form_upload(config, S3Config.avatars_bucket_name(),
        key: key,
        content_type: entry.client_type,
        max_file_size: socket.assigns.uploads.avatar.max_file_size,
        expires_in: :timer.hours(1),
        server_side_encryption: S3Config.server_side_encryption?()
      )

    upload_url = S3Config.avatars_upload_url()
    :ok = S3Config.assert_direct_upload_url!(upload_url, :avatars)

    meta = %{
      uploader: "S3",
      key: key,
      url: upload_url,
      fields: fields
    }

    {:ok, meta, socket}
  end

  defp load_user_avatars(user) do
    Avatars.list_user_avatars(user)
  end

  defp resolve_current_avatar_url(user) do
    user = Repo.preload(user, :current_avatar)

    case user.current_avatar do
      nil -> nil
      avatar -> Avatars.avatar_url(avatar, :profile)
    end
  end

  defp avatar_upload_error_to_string(:too_large),
    do: "Image must be under 10 MB"

  defp avatar_upload_error_to_string(:not_accepted),
    do: "Only JPG, PNG, WebP, and GIF files are accepted"

  defp avatar_upload_error_to_string(:too_many_files),
    do: "Only one photo at a time"

  defp avatar_upload_error_to_string(_), do: "Upload failed"

  defp pst_today, do: DateTime.now!("America/Los_Angeles") |> DateTime.to_date()

  defp to_pst_date(%DateTime{} = dt),
    do: dt |> DateTime.shift_zone!("America/Los_Angeles") |> DateTime.to_date()

  defp to_pst_date(%Date{} = d), do: d
  defp to_pst_date(_), do: nil

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

  defp member_entitlement_coupon_frame_class(:tahoe),
    do: "border-sky-400/80 shadow-sky-100/80"

  defp member_entitlement_coupon_frame_class(:clear_lake),
    do: "border-emerald-400/80 shadow-emerald-100/80"

  defp member_entitlement_coupon_frame_class(_),
    do: "border-violet-400/80 shadow-violet-100/80"

  defp member_entitlement_coupon_blob_class(:tahoe), do: "bg-sky-400"
  defp member_entitlement_coupon_blob_class(:clear_lake), do: "bg-emerald-400"
  defp member_entitlement_coupon_blob_class(_), do: "bg-violet-400"

  defp member_entitlement_coupon_ribbon_class(:tahoe),
    do: "from-sky-500 via-sky-300 to-blue-600"

  defp member_entitlement_coupon_ribbon_class(:clear_lake),
    do: "from-emerald-500 via-teal-400 to-cyan-600"

  defp member_entitlement_coupon_ribbon_class(_),
    do: "from-violet-500 via-fuchsia-400 to-purple-600"

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
