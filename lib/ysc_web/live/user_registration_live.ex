defmodule YscWeb.UserRegistrationLive do
  alias Ecto.Changeset
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.{FamilyInvites, FamilyMember, SignupApplication, User}
  alias YscWeb.Workers.CreateStripeCustomerWorker

  def render(assigns) do
    ~H"""
    <div id="registration-wrapper" class="max-w-xl mx-auto py-4 px-4">
      <div class="flex w-full mx-auto items-center text-center justify-center">
        <.link
          navigate={~p"/"}
          class="p-8 hover:opacity-80 transition duration-200 ease-in-out"
        >
          <.ysc_logo class="h-28" width={112} height={112} fetchpriority="high" />
        </.link>
      </div>
      <div class="w-full px-2">
        <.stepper
          active_step={@current_step}
          steps={["Eligibility", "About you", "Questions"]}
        />
      </div>

      <div id="registration-form" class="px-2 pt-8 pb-4">
        <div :if={@current_step === 0} id="step-0-header">
          <.header class="text-left">
            Apply for membership
            <:subtitle>
              Already a member?
              <.link
                navigate={~p"/users/log-in"}
                class="font-semibold text-blue-700 hover:underline"
              >
                Sign in
              </.link>
              to your account.
            </:subtitle>
          </.header>

          <p class="mt-2 mb-6 text-sm leading-6 text-zinc-600">
            We are excited to have you join us! The application is quick—we'll email you as soon as your membership is approved.
          </p>
        </div>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          phx-auto-recover="recover_wizard"
          phx-trigger-action={@trigger_submit}
          method="post"
        >
          <div class="space-y-4 min-h-[28rem]">
            <p class="text-right text-xs text-zinc-400">* Required fields</p>
            <.error :if={@check_errors}>
              Oops, something went wrong! Please check the errors below.
            </.error>

            <div id="step-0-content" class={if @current_step !== 0, do: "hidden"}>
              <div class="py-4 space pb-8">
                <p class="mb-4 text-sm font-semibold leading-6 text-zinc-800">
                  Who is applying for membership today?*
                </p>

                <.icon name="hero-user" class="hidden" />
                <.icon name="hero-user-group" class="hidden" />
                <.inputs_for :let={rf} field={@form[:registration_form]}>
                  <fieldset class="flex flex-wrap mb-8">
                    <.radio_fieldset
                      field={rf[:membership_type]}
                      options={[
                        single: %{
                          option: "single",
                          subtitle: "Myself",
                          icon: "user"
                        },
                        family: %{
                          option: "family",
                          subtitle:
                            "You, your partner and dependents (18 years or younger)",
                          icon: "user-group"
                        }
                      ]}
                      checked_value={rf.params["membership_type"]}
                    />
                  </fieldset>

                  <.checkgroup
                    field={rf[:membership_eligibility]}
                    label="Tell us about your connection to Scandinavia (select at least one)*"
                    options={SignupApplication.eligibility_options()}
                  />
                </.inputs_for>
              </div>
            </div>

            <div
              id="step-1-content"
              class={
                if @current_step !== 1,
                  do: "hidden",
                  else: "flex flex-col space-y-3 pb-8"
              }
            >
              <.header class="text-left">Account Information</.header>
              <div
                :if={@email_already_taken}
                class="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800"
                role="alert"
              >
                <p class="font-medium">This email is already registered.</p>
                <p class="mt-1 text-amber-700">
                  If this is you, sign in to your account or reset your password if you've forgotten how to sign in.
                </p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <.link
                    navigate={~p"/users/log-in"}
                    class="inline-flex items-center rounded-md bg-amber-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-amber-500"
                  >
                    Sign in
                  </.link>
                  <.link
                    navigate={~p"/users/reset-password"}
                    class="inline-flex items-center rounded-md border border-amber-300 bg-white px-3 py-2 text-sm font-semibold text-amber-700 hover:bg-amber-50"
                  >
                    Reset password
                  </.link>
                </div>
              </div>
              <.input
                field={@form[:email]}
                type="email"
                label="Email*"
                placeholder="example@ysc.org"
                autocomplete="email"
                required
              />
              <.header class="text-left pt-6">Personal Information</.header>
              <.input
                field={@form[:first_name]}
                label="First Name*"
                autocomplete="given-name"
                required
              />
              <.input
                field={@form[:last_name]}
                label="Last Name*"
                autocomplete="family-name"
                required
              />

              <.inputs_for :let={rf} field={@form[:registration_form]}>
                <.input
                  field={rf[:birth_date]}
                  label="Birth Date*"
                  type="date"
                  max={@today_max}
                  required
                />
                <.input field={rf[:occupation]} label="Occupation" />
              </.inputs_for>

              <div :if={@show_family_input} id="family-members" class="pt-4">
                <div class="pb-2">
                  <h2 class="font-semibold leading-6 text-zinc-800">Family</h2>
                  <p class="text-sm leading-6 text-zinc-600">
                    Please list all members of your family.
                  </p>
                </div>

                <div :if={!@trigger_submit}>
                  <.inputs_for :let={nested_f} field={@form[:family_members]}>
                    <div class="relative mb-2 last:mb-0 rounded-lg border border-zinc-200 p-3 pr-10">
                      <input
                        type="hidden"
                        name="user[family_members_order][]"
                        value={nested_f.index}
                      />
                      <%!-- Row 1: Type + First Name + Last Name --%>
                      <div class="grid grid-cols-2 gap-3 sm:grid-cols-[7.5rem_1fr_1fr]">
                        <div class="col-span-2 sm:col-span-1">
                          <.input
                            type="select"
                            options={[Spouse: "spouse", Child: "child"]}
                            field={nested_f[:type]}
                            label="Type"
                          />
                        </div>
                        <.input
                          type="text"
                          field={nested_f[:first_name]}
                          placeholder="First Name"
                          label="First Name"
                        />
                        <.input
                          type="text"
                          field={nested_f[:last_name]}
                          placeholder="Last Name"
                          label="Last Name"
                        />
                      </div>
                      <%!-- Row 2: Birth Date --%>
                      <div class="mt-3">
                        <.input
                          type="date-text"
                          field={nested_f[:birth_date]}
                          placeholder="Birth Date"
                          label="Birth Date"
                          max={@today_max}
                        />
                      </div>
                      <%!-- Delete button: always absolute top-right --%>
                      <label class="absolute top-2.5 right-2.5 cursor-pointer">
                        <input
                          type="checkbox"
                          name="user[family_members_delete][]"
                          value={nested_f.index}
                          class="hidden"
                        />
                        <.icon
                          name="hero-x-circle"
                          class="w-6 h-6 text-red-400 transition-all duration-150 hover:text-red-600 hover:scale-125 active:scale-95"
                        />
                      </label>
                    </div>
                  </.inputs_for>
                </div>

                <div class="w-full py-4">
                  <label class="w-full flex items-center justify-center gap-x-1.5 border border-dashed border-zinc-300 cursor-pointer rounded hover:bg-zinc-50 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-700 active:text-zinc-700/80">
                    <input
                      type="checkbox"
                      name="user[family_members_order][]"
                      class="hidden"
                    />
                    <.icon name="hero-plus-circle" class="w-5 h-5" />
                    Add Family Member
                  </label>
                </div>
              </div>

              <.inputs_for :let={rf} field={@form[:registration_form]}>
                <.header class="text-left pt-6">Mailing Address</.header>
                <.input
                  field={rf[:address]}
                  label="Address*"
                  autocomplete="address-line1"
                  required
                />
                <.input
                  field={rf[:city]}
                  label="City*"
                  autocomplete="address-level2"
                  required
                />
                <.input
                  field={rf[:region]}
                  label="State/Province"
                  autocomplete="address-level1"
                />
                <.input
                  prompt="Select country/region"
                  type="country-select"
                  field={rf[:country]}
                  label="Country/Region*"
                  autocomplete="country"
                  required
                />
                <.input
                  field={rf[:postal_code]}
                  label="ZIP/Postal Code*"
                  autocomplete="postal-code"
                  required
                />
              </.inputs_for>
            </div>

            <div
              id="step-2-content"
              class={
                if @current_step !== 2,
                  do: "hidden",
                  else: "flex flex-col space-y-3 pb-8"
              }
            >
              <.header class="text-left">Additional Questions</.header>
              <.inputs_for :let={rf} field={@form[:registration_form]}>
                <.input
                  prompt="Select country"
                  type="country-select"
                  field={rf[:place_of_birth]}
                  label="Place of Birth*"
                  required
                />
                <.input
                  prompt="Select country"
                  type="country-select"
                  field={rf[:citizenship]}
                  label="Citizenship*"
                  required
                />
                <.input
                  prompt="Select country"
                  field={rf[:most_connected_nordic_country]}
                  label="To which one Nordic/Scandinavian country do you feel the most connected?*"
                  type="select"
                  options={[
                    Sweden: "SE",
                    Norway: "NO",
                    Finland: "FI",
                    Iceland: "IS",
                    Denmark: "DK"
                  ]}
                  required
                />
                <.input
                  field={rf[:link_to_scandinavia]}
                  label="If not born in or a citizen of a Nordic/Scandinavian country, describe the descent or link to Scandinavia on which you base your eligibility for membership:"
                  type="textarea"
                />
                <.input
                  field={rf[:lived_in_scandinavia]}
                  label="If you have lived in a Nordic/Scandinavian country, where and for how long?"
                  type="textarea"
                />
                <.input
                  field={rf[:spoken_languages]}
                  label="Which, if any, Nordic/Scandinavian languages do you speak?"
                  type="textarea"
                />
                <.input
                  field={rf[:hear_about_the_club]}
                  label="How did you hear about the Young Scandinavians Club (YSC)?"
                  type="textarea"
                />

                <% field = rf[:agreed_to_bylaws] %>
                <% checked =
                  Phoenix.HTML.Form.normalize_value("checkbox", field.value) %>
                <div class="pt-4">
                  <div class="flex flex-nowrap items-center gap-2">
                    <input type="hidden" name={field.name} value="false" />
                    <input
                      type="checkbox"
                      id={field.id}
                      name={field.name}
                      value="true"
                      checked={checked}
                      class="mt-0.5 rounded border-zinc-300 text-zinc-900 focus:ring-0 w-5 h-5 flex-shrink-0"
                    />
                    <label
                      for={field.id}
                      class="flex flex-nowrap items-center gap-1.5 text-sm leading-6 text-zinc-600 cursor-pointer py-1"
                    >
                      <span>I have read and agreed to the</span>
                      <.link
                        navigate={~p"/bylaws"}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center gap-1 text-blue-600 hover:underline"
                      >
                        Young Scandinavians Club Bylaws
                        <.icon
                          name="hero-arrow-top-right-on-square"
                          class="w-4 h-4 flex-shrink-0"
                        />
                      </.link>
                    </label>
                  </div>
                  <.error :for={
                    msg <-
                      if(Phoenix.Component.used_input?(field),
                        do: Enum.map(field.errors, &translate_error(&1)),
                        else: []
                      )
                  }>
                    {msg}
                  </.error>
                </div>
              </.inputs_for>
            </div>

            <div
              id="registration-actions"
              class="sticky bottom-0 z-10 flex flex-row justify-between items-center -mx-6 px-6 sm:mx-0 sm:px-0 py-3 bg-white border-t border-zinc-100 mt-2"
            >
              <div>
                <div :if={@current_step > 0}>
                  <button
                    type="button"
                    class="flex items-center gap-x-1.5 rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-800/80"
                    phx-click="prev-step"
                  >
                    <.icon name="hero-arrow-left-solid" class="w-4 h-4" />
                    Previous step
                  </button>
                </div>
              </div>

              <div class={[@current_step > 1 && "flex-1 sm:flex-none ml-3"]}>
                <div :if={@current_step < 2}>
                  <button
                    type="button"
                    class="flex items-center gap-x-1.5 rounded bg-blue-700 hover:bg-blue-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80"
                    phx-click="next-step"
                    disabled={
                      disable_next_button(
                        @current_step,
                        @step_0_invalid,
                        @step_1_invalid,
                        @step_2_invalid
                      )
                    }
                    aria-disabled={
                      disable_next_button(
                        @current_step,
                        @step_0_invalid,
                        @step_1_invalid,
                        @step_2_invalid
                      )
                    }
                  >
                    Next Step
                    <.icon name="hero-arrow-right-solid" class="w-4 h-4" />
                  </button>
                </div>

                <div :if={@current_step > 1} class="w-full">
                  <.button
                    phx-disable-with="Submitting application..."
                    class="w-full"
                    disabled={@step_2_invalid}
                    aria-disabled={@step_2_invalid}
                  >
                    Submit Application
                  </.button>
                </div>
              </div>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    connect_params =
      case get_connect_params(socket) do
        nil -> %{}
        v -> v
      end

    browser_timezone =
      connect_params |> Map.get("timezone", "America/Los_Angeles")

    # Today in user's timezone for date input max (so "today" is correct for their locale)
    today_max =
      browser_timezone
      |> DateTime.now!()
      |> DateTime.to_date()
      |> Date.to_iso8601()

    # Check for family invite link (from logout-required flow)
    family_invite = get_family_invite_from_params(params)

    initial_attrs =
      if family_invite do
        %{
          "email" => family_invite.email,
          "registration_form" => %{"family_invite_id" => family_invite.id}
        }
      else
        %{}
      end

    changeset = Accounts.change_user_registration(%User{}, initial_attrs)

    socket =
      socket
      |> assign(:page_title, "Become a Member")
      |> assign(:family_invite, family_invite)
      |> assign(
        :meta_description,
        "Join the Young Scandinavians Club. Apply for membership and become part of our vibrant Scandinavian community in the Bay Area."
      )
      |> assign(:current_step, 0)
      |> assign(:step_0_invalid, false)
      |> assign(:step_1_invalid, false)
      |> assign(:step_2_invalid, false)
      |> assign(:show_family_input, false)
      |> assign(:browser_timezone, browser_timezone)
      |> assign(:today_max, today_max)
      |> assign(
        trigger_submit: false,
        check_errors: false,
        email_already_taken: false
      )
      |> assign_new(:started, fn -> DateTime.to_string(DateTime.utc_now()) end)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @spec handle_event(<<_::32, _::_*32>>, map(), any()) :: {:noreply, any()}
  def handle_event("save", %{"user" => user_params}, socket) do
    reg_form_updated =
      user_params["registration_form"]
      |> Map.put("started", socket.assigns[:started])
      |> Map.put("browser_timezone", socket.assigns[:browser_timezone])

    # Filter out empty family members (those without first_name, last_name, or birth_date)
    # Handle both map and list formats - Phoenix forms can return maps with numeric string keys
    family_members_list =
      case user_params["family_members"] do
        nil -> []
        %{} = map -> Map.values(map)
        list when is_list(list) -> list
      end

    filtered_family_members =
      family_members_list
      |> Enum.filter(fn fm ->
        first_name = Map.get(fm, "first_name", "") || ""
        last_name = Map.get(fm, "last_name", "") || ""
        birth_date = Map.get(fm, "birth_date", "") || ""

        String.trim(first_name) != "" &&
          String.trim(last_name) != "" &&
          String.trim(birth_date) != ""
      end)

    reg_form_with_invite =
      if family_invite = socket.assigns[:family_invite] do
        Map.put(reg_form_updated, "family_invite_id", family_invite.id)
      else
        reg_form_updated
      end

    updated_user_params =
      user_params
      |> Map.replace("registration_form", reg_form_with_invite)
      |> Map.put("family_members", filtered_family_members)
      |> Map.put(
        "most_connected_country",
        reg_form_updated["most_connected_nordic_country"]
      )

    case Accounts.register_user(updated_user_params) do
      {:ok, user} ->
        Accounts.deliver_application_submitted_notification(user)

        # Create Stripe customer in background so it's ready when user visits settings
        %{"user_id" => user.id}
        |> CreateStripeCustomerWorker.new()
        |> Oban.insert()

        YscWeb.Emails.Notifier.schedule_email_to_board(
          "#{user.id}",
          "New Membership Application Received - Action Needed",
          "admin_application_submitted",
          %{
            applicant_name:
              "#{Ysc.title_case(user.first_name)} #{Ysc.title_case(user.last_name)}",
            submission_date:
              Timex.format!(
                Timex.now("America/Los_Angeles"),
                "{Mshort} {D}, {YYYY} at {h12}:{m} {AM}"
              ),
            review_url:
              YscWeb.Endpoint.url() <> "/admin/users/#{user.id}/review"
          }
        )

        # Email verification is now handled in the account setup flow with codes
        # No need to send separate confirmation email with link
        # {:ok, _} =
        #   Accounts.deliver_user_confirmation_instructions(
        #     user,
        #     &url(~p"/users/confirm/#{&1}")
        #   )

        # After successful registration, redirect to account setup flow
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :info,
           "Application submitted successfully! Please complete your account setup.",
           title: "Registration"
         )
         |> redirect(to: ~p"/account/setup/#{user.id}?from_signup=true")}

      {:error, %Ecto.Changeset{} = changeset} ->
        email_taken? = email_already_taken_error?(changeset)
        step_with_error = step_with_first_error(changeset)
        show_family = show_family_input_from_changeset?(changeset)

        {:noreply,
         socket
         |> assign(check_errors: true, email_already_taken: email_taken?)
         |> assign(:current_step, step_with_error)
         |> assign(:show_family_input, show_family)
         |> assign_form(changeset)
         |> evaluate_steps()
         |> push_event("scroll-to-top", %{})}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    form_data =
      User.registration_changeset(
        %User{},
        user_params,
        hash_password: false,
        validate_email: false
      )

    re_val =
      assign_form(socket, Map.put(form_data, :action, :validate))
      |> assign(:email_already_taken, false)

    {:noreply, re_val |> evaluate_steps() |> show_family_input?(user_params)}
  end

  def handle_event("recover_wizard", %{"user" => user_params}, socket) do
    # Custom recovery handler for multi-step wizard form
    # Restores both form data and determines the appropriate step based on filled fields
    form_data =
      User.registration_changeset(
        %User{},
        user_params,
        hash_password: false,
        validate_email: false
      )

    # Determine which step the user should be on based on filled fields
    current_step = determine_step_from_params(user_params)

    re_val =
      socket
      |> assign_form(Map.put(form_data, :action, :validate))
      |> assign(:current_step, current_step)
      |> evaluate_steps()
      |> show_family_input?(user_params)

    {:noreply, re_val}
  end

  def handle_event("set-step", %{"step" => step}, socket) do
    assigns = socket.assigns
    int_step = String.to_integer(step)
    current_step = assigns.current_step

    new_step =
      case int_step do
        1 ->
          if assigns.step_0_invalid, do: current_step, else: int_step

        2 ->
          if assigns.step_0_invalid || assigns.step_1_invalid,
            do: current_step,
            else: int_step

        _ ->
          int_step
      end

    {:noreply,
     socket
     |> assign(:current_step, new_step)
     |> push_event("scroll-to-top", %{})
     |> push_event("focus-first-input", %{id: "step-#{new_step}-content"})}
  end

  def handle_event("prev-step", _value, socket) do
    new_step = max(socket.assigns.current_step - 1, 0)

    {:noreply,
     socket
     |> assign(:current_step, new_step)
     |> push_event("scroll-to-top", %{})
     |> push_event("focus-first-input", %{id: "step-#{new_step}-content"})}
  end

  def handle_event("next-step", _values, socket) do
    current_step = socket.assigns.current_step

    step_invalid = false

    new_step = if step_invalid, do: current_step, else: current_step + 1

    {:noreply,
     socket
     |> assign(:current_step, new_step)
     |> push_event("scroll-to-top", %{})
     |> push_event("focus-first-input", %{id: "step-#{new_step}-content"})}
  end

  # Which step (0, 1, or 2) has the first validation error; used to jump to that step on save failure
  defp step_with_first_error(changeset) do
    reg_form_errors =
      case changeset.changes do
        %{registration_form: reg_cs} when is_struct(reg_cs, Ecto.Changeset) ->
          reg_cs.errors

        _ ->
          []
      end

    reg_keys = Keyword.keys(reg_form_errors)
    base_keys = Keyword.keys(changeset.errors)

    step_0_error? =
      Enum.any?(reg_keys, fn k ->
        k in [:membership_type, :membership_eligibility]
      end)

    step_1_error? =
      Enum.any?(base_keys, fn k ->
        k in [:email, :password, :first_name, :last_name]
      end) or
        Enum.any?(reg_keys, fn k ->
          k in [:birth_date, :address, :city, :country, :postal_code]
        end)

    step_2_error? =
      Enum.any?(reg_keys, fn k ->
        k in [
          :place_of_birth,
          :citizenship,
          :most_connected_nordic_country,
          :agreed_to_bylaws
        ]
      end)

    cond do
      step_0_error? -> 0
      step_1_error? -> 1
      step_2_error? -> 2
      true -> 2
    end
  end

  defp show_family_input_from_changeset?(changeset) do
    case Ecto.Changeset.get_change(changeset, :registration_form) do
      %Ecto.Changeset{} = reg_cs ->
        Ecto.Changeset.get_change(reg_cs, :membership_type) == "family" or
          Ecto.Changeset.get_field(reg_cs, :membership_type, nil) == "family"

      _ ->
        false
    end
  end

  defp email_already_taken_error?(changeset) do
    case Keyword.get(changeset.errors, :email) do
      {msg, _opts} when is_binary(msg) ->
        msg_lower = String.downcase(msg)

        String.contains?(msg_lower, "already") or
          String.contains?(msg_lower, "taken")

      _ ->
        false
    end
  end

  # Determine the appropriate step based on which fields are filled
  defp determine_step_from_params(user_params) do
    reg_form = user_params["registration_form"] || %{}

    # Step 0: membership_type and membership_eligibility
    has_step_0 =
      (reg_form["membership_type"] && reg_form["membership_type"] != "") ||
        (reg_form["membership_eligibility"] &&
           reg_form["membership_eligibility"] != [])

    # Step 1: user fields and address fields
    has_step_1 =
      (user_params["email"] && user_params["email"] != "") ||
        (user_params["first_name"] && user_params["first_name"] != "") ||
        (reg_form["birth_date"] && reg_form["birth_date"] != "") ||
        (reg_form["address"] && reg_form["address"] != "")

    # Step 2: place_of_birth, citizenship, etc.
    has_step_2 =
      (reg_form["place_of_birth"] && reg_form["place_of_birth"] != "") ||
        (reg_form["citizenship"] && reg_form["citizenship"] != "") ||
        (reg_form["most_connected_nordic_country"] &&
           reg_form["most_connected_nordic_country"] != "")

    cond do
      has_step_2 -> 2
      has_step_1 -> 1
      has_step_0 -> 0
      true -> 0
    end
  end

  defp evaluate_steps(socket) do
    base_errors = socket.assigns.form.errors

    reg_form_errors =
      case socket.assigns.form.source.changes do
        %{registration_form: reg_form_changeset} -> reg_form_changeset.errors
        _ -> []
      end

    step_0_invalid =
      Enum.any?(Keyword.keys(reg_form_errors), fn k ->
        k in [:membership_type, :membership_eligibility]
      end)

    step_1_invalid =
      Enum.any?(Keyword.keys(base_errors), fn k ->
        k in [:email, :password, :first_name, :last_name]
      end) ||
        Enum.any?(Keyword.keys(reg_form_errors), fn k ->
          k in [:birth_date, :address, :city, :country, :postal_code]
        end)

    step_2_invalid =
      Enum.any?(Keyword.keys(reg_form_errors), fn k ->
        k in [
          :place_of_birth,
          :citizenship,
          :most_connected_nordic_country,
          :agreed_to_bylaws
        ]
      end)

    socket
    |> assign(:step_0_invalid, step_0_invalid)
    |> assign(:step_1_invalid, step_1_invalid)
    |> assign(:step_2_invalid, step_2_invalid)
  end

  defp disable_next_button(
         current_step,
         step_0_invalid,
         step_1_invalid,
         step_2_invalid
       ) do
    case current_step do
      0 -> step_0_invalid
      1 -> step_1_invalid
      2 -> step_2_invalid
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    # Check if family_members association is loaded or if it's in changeset changes
    # Only add empty family member during form editing/validation, not after successful save
    patched_changset =
      cond do
        # If association is in changeset changes, use that (preserve validation state)
        Map.has_key?(changeset.changes, :family_members) ->
          case Map.get(changeset.changes, :family_members) do
            [] ->
              # Add empty family member to existing changes using put_assoc
              # This preserves the validation state and errors
              Ecto.Changeset.put_assoc(changeset, :family_members, [
                %FamilyMember{}
              ])

            _ ->
              changeset
          end

        # If association is loaded, check its value
        Ecto.assoc_loaded?(changeset.data.family_members) ->
          case Changeset.get_field(changeset, :family_members) do
            [] ->
              Ecto.Changeset.put_assoc(changeset, :family_members, [
                %FamilyMember{}
              ])

            _ ->
              changeset
          end

        # Association not loaded and not in changes
        # Only add empty family member if this is a new changeset (not a persisted user)
        # After successful registration, the user is persisted and we don't need to add empty family member
        true ->
          # If the user is persisted (has an ID), don't try to add empty family member
          # This happens after successful registration when we're about to redirect
          if changeset.data.id do
            # Persisted user - just return changeset as-is
            changeset
          else
            # New changeset during form editing - add empty family member using cast_assoc
            # We need to preserve all existing changes from the changeset
            # Extract all changes and merge with family_members
            existing_attrs = changeset_to_attrs(changeset)
            attrs = Map.put(existing_attrs, "family_members", [%{}])

            User.registration_changeset(
              changeset.data,
              attrs,
              hash_password: false,
              validate_email: false
            )
            # Preserve the action from the original changeset
            |> Map.put(:action, changeset.action)
          end
      end

    form = to_form(patched_changset, as: "user")

    if patched_changset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp show_family_input?(socket, %{"registration_form" => reg_form}) do
    socket
    |> assign(
      :show_family_input,
      reg_form["membership_type"] === "family"
    )
  end

  # Convert changeset changes to attrs format (string keys) for use in cast_assoc
  defp changeset_to_attrs(changeset) do
    changeset.changes
    |> Enum.map(fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), convert_value_to_attrs(value)}

      {key, value} ->
        {key, convert_value_to_attrs(value)}
    end)
    |> Enum.into(%{})
  end

  # Recursively convert changeset values to attrs format
  defp convert_value_to_attrs(%Ecto.Changeset{} = nested_changeset) do
    # For nested changesets (like registration_form), extract their changes
    changeset_to_attrs(nested_changeset)
  end

  defp convert_value_to_attrs(list) when is_list(list) do
    # For lists, convert each item
    Enum.map(list, fn
      %Ecto.Changeset{} = cs -> changeset_to_attrs(cs)
      %{} = map -> map_to_string_keys(map)
      value -> value
    end)
  end

  defp convert_value_to_attrs(value), do: value

  # Convert a map with atom keys to string keys
  @dialyzer {:nowarn_function, map_to_string_keys: 1}
  defp map_to_string_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), convert_value_to_attrs(value)}

      {key, value} ->
        {key, convert_value_to_attrs(value)}
    end)
    |> Enum.into(%{})
  end

  defp map_to_string_keys(value), do: value

  defp get_family_invite_from_params(params) do
    case params["invite"] do
      nil ->
        nil

      token when is_binary(token) and token != "" ->
        invite = FamilyInvites.get_invite_by_token(token)

        if invite && Ysc.Accounts.FamilyInvite.valid?(invite) do
          invite
        else
          nil
        end

      _ ->
        nil
    end
  end
end
