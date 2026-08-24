defmodule YscWeb.ContactLive do
  use YscWeb, :live_view

  alias Ysc.EmailConfig

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

          <.form_notice
            :if={@submitted}
            kind={:success}
            id="contact-success"
            size={:comfortable}
            class="not-prose"
          >
            <span class="font-semibold">
              Thank you! Your message has been sent. We'll get back to you soon.
            </span>
          </.form_notice>

          <div class="not-prose">
            <.submitting_as :if={@logged_in?} user={@current_user} />

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
                  {"Events", "Events"},
                  {"Choir", "Choir"},
                  {"Website", "Website"},
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
            <.mailto_card
              :for={card <- department_contact_cards()}
              id={card.id}
              email={card.email}
              icon={card.icon}
              title={card.title}
            >
              {card.description}
            </.mailto_card>
          </div>

          <div class="pt-8 border-t border-zinc-200">
            <h2>Other Ways to Connect</h2>
            <div class="not-prose space-y-4 mt-6">
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-map-pin"
                  class="w-6 h-6 text-zinc-400 flex-shrink-0 mt-0.5"
                />
                <div>
                  <p class="font-semibold text-zinc-900 mb-1">Mailing Address</p>
                  <p class="text-zinc-600 leading-relaxed">
                    <span class="font-semibold">{Ysc.Organization.name()}</span>
                    <%= for line <- Ysc.Organization.mailing_address_street_lines() do %>
                      <br /> {line}
                    <% end %>
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

    prefilled_params =
      base_params
      |> then(fn p ->
        if subject = params["subject"],
          do: Map.put(p, :subject, URI.decode(subject)),
          else: p
      end)
      |> then(fn p ->
        if message = params["message"],
          do: Map.put(p, :message, URI.decode(message)),
          else: p
      end)

    changeset =
      Ysc.Forms.ContactForm.changeset(
        %Ysc.Forms.ContactForm{},
        prefilled_params
      )

    {:ok,
     socket
     |> assign(:page_title, "Contact")
     |> assign(
       :meta_description,
       "Get in touch with the Young Scandinavians Club. We'd love to hear from you."
     )
     |> assign(:current_user, current_user)
     |> assign(:logged_in?, current_user != nil)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)
     |> assign(:load_turnstile, true)}
  end

  @impl true
  def handle_event("validate", %{"contact_form" => contact_params}, socket) do
    params = add_user_info(contact_params, socket.assigns[:current_user])

    changeset =
      %Ysc.Forms.ContactForm{}
      |> Ysc.Forms.ContactForm.changeset(params)
      |> Ysc.Forms.ContactForm.put_submitter(socket.assigns[:current_user])

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"contact_form" => contact_params} = values, socket) do
    params = add_user_info(contact_params, socket.assigns[:current_user])

    changeset =
      %Ysc.Forms.ContactForm{}
      |> Ysc.Forms.ContactForm.changeset(params)
      |> Ysc.Forms.ContactForm.put_submitter(socket.assigns[:current_user])

    if socket.assigns.logged_in? do
      case Ysc.Forms.create_contact_form(changeset) do
        {:ok, _contact_form} ->
          {:noreply,
           socket
           |> assign(:submitted, true)
           |> YscWeb.Flash.put_toast(:info, "Your message has been sent",
             title: "Contact"
           )}

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
               |> YscWeb.Flash.put_toast(:info, "Your message has been sent",
                 title: "Contact"
               )}

            {:error, changeset} ->
              {:noreply, assign_form(socket, changeset)}
          end

        {:error, _} ->
          socket =
            socket
            |> YscWeb.Flash.put_toast(
              :error,
              "We couldn't verify you're a real person. Please try submitting again. If this keeps happening, refresh the page or try a different browser.",
              title: "Contact"
            )
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
      email: user.email
    }
  end

  defp add_user_info(params, nil), do: params

  defp add_user_info(params, user) do
    params
    |> Map.put("name", "#{user.first_name} #{user.last_name}")
    |> Map.put("email", user.email)
  end

  defp department_contact_cards do
    [
      %{
        id: "contact-card-tahoe",
        email: EmailConfig.tahoe_email(),
        icon: "hero-home-modern",
        title: "Tahoe Cabin",
        description: "Questions about bookings or stays."
      },
      %{
        id: "contact-card-clear-lake",
        email: EmailConfig.clear_lake_email(),
        icon: "hero-home",
        title: "Clear Lake Cabin",
        description: "Questions about bookings or stays."
      },
      %{
        id: "contact-card-volunteer",
        email: EmailConfig.volunteer_email(),
        icon: "hero-user-group",
        title: "Volunteer",
        description: "Join the team or suggest events."
      },
      %{
        id: "contact-card-board",
        email: EmailConfig.board_email(),
        icon: "hero-users",
        title: "Board of Directors",
        description: "Get in touch with the current Board."
      },
      %{
        id: "contact-card-web",
        email: "web@ysc.org",
        icon: "hero-computer-desktop",
        title: "Web",
        description: "Sign in or website related issues."
      },
      %{
        id: "contact-card-choir",
        email: "choir@ysc.org",
        icon: "hero-musical-note",
        title: "Choir",
        description: "Questions about choir rehearsals or events."
      },
      %{
        id: "contact-card-general",
        email: EmailConfig.contact_email(),
        icon: "hero-envelope",
        title: "General Inquiry",
        description: "For general questions and inquiries."
      }
    ]
  end
end
