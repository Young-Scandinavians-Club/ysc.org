defmodule YscWeb.ConductViolationReportLive do
  use YscWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50 flex items-center justify-center py-12 px-4">
      <div class="w-full max-w-2xl">
        <%!-- Success State --%>
        <div
          :if={@submitted}
          class="bg-white rounded-xl shadow-sm border border-zinc-200 p-8 lg:p-12 text-center"
        >
          <div class="flex justify-center mb-6">
            <.icon name="hero-check-circle" class="text-green-600 w-16 h-16" />
          </div>
          <h1 class="text-2xl lg:text-3xl font-bold text-zinc-900 mb-4">
            Thank You for Your Report
          </h1>
          <p class="text-zinc-600 mb-4 text-lg">
            Your report has been successfully submitted. A confirmation email with a copy of your report has been sent to your email address.
          </p>
          <p class="text-zinc-500 mb-6">
            The YSC board will review your report and you can expect a response within 48-72 hours. We take all reports seriously and will handle this matter with care and discretion.
          </p>
          <div
            :if={@submitted_summary}
            class="mb-8 p-4 bg-zinc-50 border border-zinc-200 rounded-lg text-left"
          >
            <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-2">
              Your Submitted Report
            </p>
            <p class="text-sm text-zinc-700 whitespace-pre-wrap">
              <%= @submitted_summary %>
            </p>
          </div>
          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <.link
              navigate={~p"/"}
              class="inline-flex items-center justify-center px-6 py-3 bg-blue-700 hover:bg-blue-800 text-white font-semibold rounded-lg transition-colors"
            >
              Return to Home
            </.link>
            <.link
              navigate={~p"/code-of-conduct"}
              class="inline-flex items-center justify-center px-6 py-3 bg-zinc-100 hover:bg-zinc-200 text-zinc-900 font-semibold rounded-lg transition-colors"
            >
              View Code of Conduct
            </.link>
          </div>
        </div>

        <%!-- Form State --%>
        <div :if={!@submitted}>
          <%!-- Header Section --%>
          <div class="mb-8 text-center">
            <div class="flex justify-center mb-6">
              <.link navigate={~p"/"} class="inline-block">
                <.ysc_logo no_circle={true} class="h-16 w-16 lg:h-20 lg:w-20" />
              </.link>
            </div>
            <h1 class="text-3xl lg:text-4xl font-bold text-zinc-900 mb-4">
              Report a Conduct Violation
            </h1>
            <p class="text-lg text-zinc-600 max-w-xl mx-auto mb-4">
              We're here to help. If you've experienced or witnessed a violation of our Code of Conduct, please share the details below. Your report will be handled with care and confidentiality.
            </p>
            <p class="text-sm text-zinc-500 mb-6">
              You can expect a response from the board within <strong class="text-zinc-700">48-72 hours</strong>. All reports are reviewed promptly and with discretion.
            </p>
            <p class="text-sm">
              <.link
                href={~p"/code-of-conduct"}
                class="text-blue-600 hover:text-blue-700 transition ease-in-out font-medium inline-flex items-center gap-1"
                target="_blank"
                rel="noopener noreferrer"
              >
                Review the YSC Code of Conduct
                <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
              </.link>
            </p>
          </div>

          <%!-- Form Card --%>
          <div class="bg-white rounded-xl shadow-sm border border-zinc-200 p-6 lg:p-10">
            <.simple_form
              for={@form}
              phx-change="validate"
              phx-submit="save"
              id="violation-form"
            >
              <%!-- Contact Information Section --%>
              <div class="mb-8">
                <h2 class="text-xl font-bold text-zinc-900 mb-6">
                  Your Contact Information
                </h2>

                <%!-- Logged in user display --%>
                <div
                  :if={@logged_in?}
                  class="bg-zinc-50 border border-zinc-200 rounded-lg p-6"
                >
                  <p class="text-sm text-zinc-500 mb-4">
                    You are submitting this report as:
                  </p>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                    <div>
                      <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-1">
                        Name
                      </p>
                      <p class="text-zinc-900 font-medium">
                        <%= @current_user.first_name %> <%= @current_user.last_name %>
                      </p>
                    </div>
                    <div>
                      <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-1">
                        Email
                      </p>
                      <p class="text-zinc-900 font-medium">
                        <%= @current_user.email %>
                      </p>
                    </div>
                    <div>
                      <p class="text-xs font-semibold text-zinc-500 uppercase tracking-wide mb-1">
                        Phone
                      </p>
                      <p class="text-zinc-900 font-medium">
                        <%= @current_user.phone_number || "Not provided" %>
                      </p>
                    </div>
                  </div>
                  <p class="text-xs text-zinc-500 italic border-t border-zinc-200 pt-3">
                    This information allows us to contact you for further details. Your identity is protected under our confidentiality protocols.
                  </p>
                  <%!-- Hidden fields to ensure user data is submitted --%>
                  <input
                    type="hidden"
                    name={@form[:first_name].name}
                    value={
                      Phoenix.HTML.Form.normalize_value(
                        "text",
                        @form[:first_name].value
                      )
                    }
                  />
                  <input
                    type="hidden"
                    name={@form[:last_name].name}
                    value={
                      Phoenix.HTML.Form.normalize_value(
                        "text",
                        @form[:last_name].value
                      )
                    }
                  />
                  <input
                    type="hidden"
                    name={@form[:email].name}
                    value={
                      Phoenix.HTML.Form.normalize_value(
                        "email",
                        @form[:email].value
                      )
                    }
                  />
                  <input
                    type="hidden"
                    name={@form[:phone].name}
                    value={
                      Phoenix.HTML.Form.normalize_value("text", @form[:phone].value)
                    }
                  />
                </div>

                <%!-- Non-logged in user form fields --%>
                <div :if={!@logged_in?}>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div phx-feedback-for={@form[:first_name].id}>
                      <.input field={@form[:first_name]} label="First Name*" />
                    </div>
                    <div phx-feedback-for={@form[:last_name].id}>
                      <.input field={@form[:last_name]} label="Last Name*" />
                    </div>
                  </div>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-6">
                    <div phx-feedback-for={@form[:email].id}>
                      <.input
                        field={@form[:email]}
                        type="email"
                        label="Email Address*"
                      />
                    </div>
                    <div phx-feedback-for={@form[:phone].id}>
                      <.input field={@form[:phone]} label="Phone Number*" />
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Incident Details Section --%>
              <div class="mb-8">
                <h2 class="text-xl font-bold text-zinc-900 mb-2">
                  Incident Details
                </h2>
                <p class="text-sm text-zinc-500 mb-3">
                  Don't worry about perfect formatting—just describe the event as you remember it. If you know which part of the Code of Conduct was violated, feel free to mention it.
                </p>
                <div class="mb-4 p-3 bg-blue-50 border border-blue-100 rounded-lg">
                  <p class="text-xs font-semibold text-blue-900 mb-2">
                    Helpful details to include:
                  </p>
                  <ul class="text-xs text-blue-800 space-y-1 list-disc list-inside">
                    <li>Approximate time and date</li>
                    <li>Location (Tahoe Cabin, event name, etc.)</li>
                    <li>Names of witnesses (if any)</li>
                    <li>What happened, in your own words</li>
                  </ul>
                </div>
                <div phx-feedback-for={@form[:summary].id}>
                  <.input
                    type="textarea"
                    field={@form[:summary]}
                    label="Violation Summary*"
                    placeholder="Describe the incident in detail, including when and where it occurred, who was involved, and any relevant context..."
                    rows={8}
                  />
                </div>
              </div>

              <%!-- Anonymous Option --%>
              <label
                for={@form[:anonymous].id}
                class="mb-8 p-4 bg-blue-50 border border-blue-100 rounded-lg transition-colors hover:bg-blue-100/50 cursor-pointer block group"
              >
                <div class="flex items-start gap-3">
                  <div class="flex items-center h-6 pt-0.5 flex-shrink-0">
                    <input
                      type="hidden"
                      name={@form[:anonymous].name}
                      value="false"
                    />
                    <input
                      type="checkbox"
                      id={@form[:anonymous].id}
                      name={@form[:anonymous].name}
                      value="true"
                      checked={
                        Phoenix.HTML.Form.normalize_value(
                          "checkbox",
                          @form[:anonymous].value
                        )
                      }
                      class="mt-0.5 rounded border-zinc-300 text-zinc-900 focus:ring-0 w-5 h-5"
                    />
                  </div>
                  <div class="flex-1">
                    <p class="text-sm font-semibold text-zinc-900 mb-2">
                      I wish to remain anonymous to the parties involved
                    </p>
                    <p class="text-xs text-zinc-600">
                      Your name will still be visible to the YSC board for follow-up purposes, but will not be shared with the parties involved in the incident.
                    </p>
                  </div>
                </div>
              </label>

              <%!-- Turnstile for non-logged-in users --%>
              <div :if={!@logged_in?} class="mb-8 flex justify-center">
                <Turnstile.widget theme="light" />
              </div>

              <%!-- Submit Button --%>
              <div class="flex flex-col items-end gap-2">
                <div class="flex items-center gap-2">
                  <.icon
                    name="hero-lock-closed"
                    class="w-5 h-5 text-zinc-500 phx-submit-loading:opacity-50"
                  />
                  <.button type="submit" class="px-8 py-3 text-base relative">
                    <span class="phx-submit-loading:opacity-0">Submit Report</span>
                    <span class="absolute inset-0 flex items-center justify-center phx-submit-loading:opacity-100 opacity-0">
                      <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
                    </span>
                  </.button>
                </div>
                <p class="text-xs text-zinc-500">
                  Securely transmitted to the Board of Directors
                </p>
              </div>
            </.simple_form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    remote_ip = get_connect_info(socket, :peer_data).address
    current_user = socket.assigns[:current_user]

    params = starting_params(current_user)

    changeset =
      Ysc.Forms.ConductViolationReport.changeset(
        %Ysc.Forms.ConductViolationReport{},
        params
      )

    {:ok,
     socket
     |> assign(:page_title, "Report Conduct Violation")
     |> assign(:logged_in?, current_user != nil)
     |> assign(:current_user, current_user)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign(:submitted_summary, nil)
     |> assign(:request_path, "/report-conduct-violation")
     |> assign_form(changeset)
     |> assign(:load_turnstile, true)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    parsed_uri = URI.parse(uri)
    uri_path = parsed_uri.path || "/report-conduct-violation"
    {:noreply, assign(socket, :request_path, uri_path)}
  end

  @impl true
  def handle_event("validate", %{"conduct_form" => volunteer_params}, socket) do
    params = add_user_id(volunteer_params, socket.assigns[:current_user])

    changeset =
      Ysc.Forms.ConductViolationReport.changeset(
        %Ysc.Forms.ConductViolationReport{},
        params
      )

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"conduct_form" => form_values} = values, socket) do
    params = add_user_id(form_values, socket.assigns[:current_user])

    changeset =
      Ysc.Forms.ConductViolationReport.changeset(
        %Ysc.Forms.ConductViolationReport{},
        params
      )

    summary_text = Map.get(form_values, "summary", "")

    if socket.assigns.logged_in? do
      case Ysc.Forms.create_conduct_violation_report(changeset) do
        {:ok, _conduct_report} ->
          {:noreply,
           socket
           |> assign(:submitted, true)
           |> assign(:submitted_summary, summary_text)
           |> put_flash(:info, "Your report has been submitted")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      case Turnstile.verify(values, socket.assigns.remote_ip) do
        {:ok, _} ->
          case Ysc.Forms.create_conduct_violation_report(changeset) do
            {:ok, _conduct_report} ->
              {:noreply,
               socket
               |> assign(:submitted, true)
               |> assign(:submitted_summary, summary_text)
               |> put_flash(:info, "Your report has been submitted")}

            {:error, changeset} ->
              {:noreply, assign_form(socket, changeset)}
          end

        {:error, _} ->
          socket =
            socket
            |> put_flash(:error, "Please try submitting again")
            |> Turnstile.refresh()

          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "conduct_form")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp starting_params(nil) do
    %{}
  end

  defp starting_params(user) do
    %{
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      phone: user.phone_number,
      user_id: user.id
    }
  end

  defp add_user_id(params, nil), do: params
  defp add_user_id(params, user), do: Map.put(params, "user_id", user.id)
end
