defmodule YscWeb.ContactLive do
  use YscWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4">
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16">
        <%!-- Left Column: Contact Form --%>
        <div class="prose prose-zinc prose-a:text-blue-600 max-w-xl mx-auto lg:mx-0">
          <h1>Get in touch</h1>
          <p>
            Have a question about the club or our cabins? Send us a message and we'll get back to you.
          </p>
          <p class="text-sm text-zinc-500">
            We are a community of volunteers. We usually respond within 24–48 hours.
          </p>

          <div
            :if={@submitted}
            class="not-prose mb-6 p-4 bg-green-50 border border-green-200 rounded-lg"
          >
            <div class="flex items-center">
              <.icon name="hero-check-circle" class="text-green-600 w-6 h-6 me-2" />
              <span class="text-green-800 font-semibold">
                Thank you! Your message has been sent. We'll get back to you soon.
              </span>
            </div>
          </div>

          <div class="not-prose">
            <div
              :if={@logged_in?}
              class="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg"
            >
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-full overflow-hidden flex-shrink-0 ring-2 ring-blue-200">
                  <.user_avatar_image
                    email={@current_user.email}
                    user_id={@current_user.id}
                    country={@current_user.most_connected_country}
                    class="w-full h-full object-cover"
                  />
                </div>
                <div>
                  <p class="text-sm font-semibold text-blue-900">Submitting as</p>
                  <p class="text-sm text-blue-700">
                    <%= @current_user.first_name %> <%= @current_user.last_name %> (<%= @current_user.email %>)
                  </p>
                </div>
              </div>
            </div>

            <.simple_form
              :if={!@submitted}
              for={@form}
              id="contact-form"
              phx-change="validate"
              phx-submit="save"
            >
              <.input :if={!@logged_in?} field={@form[:name]} label="Name" />
              <.input
                :if={!@logged_in?}
                field={@form[:email]}
                type="email"
                label="Email"
              />
              <.input
                field={@form[:subject]}
                type="select"
                label="Subject"
                options={[
                  {"General Inquiry", "General Inquiry"},
                  {"Tahoe Cabin", "Tahoe Cabin"},
                  {"Clear Lake Cabin", "Clear Lake Cabin"},
                  {"Membership", "Membership"},
                  {"Volunteering", "Volunteering"},
                  {"Board of Directors", "Board of Directors"},
                  {"Other", "Other"}
                ]}
              />
              <.input
                field={@form[:message]}
                type="textarea"
                label="Message"
                rows="6"
              />

              <div :if={!@logged_in?} class="w-full flex mb-4">
                <Turnstile.widget theme="light" />
              </div>

              <:actions>
                <.button type="submit" phx-disable-with="Sending..." class="w-full">
                  Send Message
                </.button>
              </:actions>
            </.simple_form>
          </div>
        </div>

        <%!-- Right Column: Department Cards and Contact Info --%>
        <div class="prose prose-zinc prose-a:text-blue-600 max-w-xl mx-auto lg:mx-0">
          <h2>Contact Directly</h2>
          <div class="not-prose grid grid-cols-1 sm:grid-cols-2 gap-4 mb-8">
            <a
              href="mailto:tahoe@ysc.org"
              class="p-5 border border-zinc-200 rounded-xl hover:bg-zinc-50 hover:border-blue-300 transition-all duration-200"
            >
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-home-modern"
                  class="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5"
                />
                <div>
                  <h3 class="font-bold text-zinc-900 mb-1">Tahoe Cabin</h3>
                  <p class="text-sm text-zinc-600">
                    Questions about bookings or stays.
                  </p>
                  <p class="text-sm text-blue-600 mt-2">tahoe@ysc.org</p>
                </div>
              </div>
            </a>

            <a
              href="mailto:cl@ysc.org"
              class="p-5 border border-zinc-200 rounded-xl hover:bg-zinc-50 hover:border-blue-300 transition-all duration-200"
            >
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-home"
                  class="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5"
                />
                <div>
                  <h3 class="font-bold text-zinc-900 mb-1">Clear Lake Cabin</h3>
                  <p class="text-sm text-zinc-600">
                    Questions about bookings or stays.
                  </p>
                  <p class="text-sm text-blue-600 mt-2">cl@ysc.org</p>
                </div>
              </div>
            </a>

            <a
              href="mailto:volunteer@ysc.org"
              class="p-5 border border-zinc-200 rounded-xl hover:bg-zinc-50 hover:border-blue-300 transition-all duration-200"
            >
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-user-group"
                  class="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5"
                />
                <div>
                  <h3 class="font-bold text-zinc-900 mb-1">Volunteer</h3>
                  <p class="text-sm text-zinc-600">
                    Join the team or suggest events.
                  </p>
                  <p class="text-sm text-blue-600 mt-2">volunteer@ysc.org</p>
                </div>
              </div>
            </a>

            <a
              href="mailto:board@ysc.org"
              class="p-5 border border-zinc-200 rounded-xl hover:bg-zinc-50 hover:border-blue-300 transition-all duration-200"
            >
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-users"
                  class="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5"
                />
                <div>
                  <h3 class="font-bold text-zinc-900 mb-1">Board of Directors</h3>
                  <p class="text-sm text-zinc-600">
                    Get in touch with the current Board.
                  </p>
                  <p class="text-sm text-blue-600 mt-2">board@ysc.org</p>
                </div>
              </div>
            </a>

            <a
              href="mailto:info@ysc.org"
              class="p-5 border border-zinc-200 rounded-xl hover:bg-zinc-50 hover:border-blue-300 transition-all duration-200"
            >
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-envelope"
                  class="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5"
                />
                <div>
                  <h3 class="font-bold text-zinc-900 mb-1">General Inquiry</h3>
                  <p class="text-sm text-zinc-600">
                    For general questions and inquiries.
                  </p>
                  <p class="text-sm text-blue-600 mt-2">info@ysc.org</p>
                </div>
              </div>
            </a>
          </div>

          <div class="pt-8 border-t border-zinc-200">
            <h2>Other Ways to Connect</h2>
            <div class="not-prose space-y-4 mt-6">
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-phone"
                  class="w-6 h-6 text-zinc-400 flex-shrink-0 mt-0.5"
                />
                <div>
                  <p class="font-semibold text-zinc-900 mb-1">Phone</p>
                  <a
                    href="tel:+14157230844"
                    class="text-blue-600 hover:text-blue-700 hover:underline transition"
                  >
                    +1 (415) 723-0844
                  </a>
                </div>
              </div>
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-map-pin"
                  class="w-6 h-6 text-zinc-400 flex-shrink-0 mt-0.5"
                />
                <div>
                  <p class="font-semibold text-zinc-900 mb-1">Mailing Address</p>
                  <p class="text-zinc-600 leading-relaxed">
                    <span class="font-semibold">Young Scandinavians Club</span>
                    <br /> PO Box 640610<br /> San Francisco, CA 94112
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    remote_ip = get_connect_info(socket, :peer_data).address
    current_user = socket.assigns[:current_user]

    base_params = starting_params(current_user)
    # Pre-fill subject from query parameter if provided
    params_with_subject =
      if subject = params["subject"] do
        Map.put(base_params, :subject, subject)
      else
        base_params
      end

    changeset =
      Ysc.Forms.ContactForm.changeset(
        %Ysc.Forms.ContactForm{},
        params_with_subject
      )

    {:ok,
     socket
     |> assign(:page_title, "Contact")
     |> assign(:current_user, current_user)
     |> assign(:logged_in?, current_user != nil)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)
     |> assign(:load_turnstile, true)}
  end

  @impl true
  def handle_event("validate", %{"contact_form" => contact_params}, socket) do
    params =
      contact_params
      |> add_user_info(socket.assigns[:current_user])
      |> add_user_id(socket.assigns[:current_user])

    changeset =
      Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, params)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"contact_form" => contact_params} = values, socket) do
    params =
      contact_params
      |> add_user_info(socket.assigns[:current_user])
      |> add_user_id(socket.assigns[:current_user])

    changeset =
      Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, params)

    if socket.assigns.logged_in? do
      case Ysc.Forms.create_contact_form(changeset) do
        {:ok, _contact_form} ->
          {:noreply,
           socket
           |> assign(:submitted, true)
           |> put_flash(:info, "Your message has been sent")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      case Turnstile.verify(values, socket.assigns.remote_ip) do
        {:ok, _} ->
          case Ysc.Forms.create_contact_form(changeset) do
            {:ok, _contact_form} ->
              {:noreply,
               socket
               |> assign(:submitted, true)
               |> put_flash(:info, "Your message has been sent")}

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
    form = to_form(changeset, as: "contact_form")

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
      name: "#{user.first_name} #{user.last_name}",
      email: user.email,
      user_id: user.id
    }
  end

  defp add_user_id(params, nil), do: params
  defp add_user_id(params, user), do: Map.put(params, "user_id", user.id)

  defp add_user_info(params, nil), do: params

  defp add_user_info(params, user) do
    params
    |> Map.put("name", "#{user.first_name} #{user.last_name}")
    |> Map.put("email", user.email)
  end
end
