defmodule YscWeb.VolunteerLive do
  use YscWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4">
      <%!-- Split Header Section --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 mb-12">
        <div class="prose prose-zinc prose-a:text-blue-600">
          <h1>Volunteer with the YSC!</h1>
          <p>
            Want to contribute to a vibrant community and help create memorable experiences for others?
          </p>
          <p>
            The YSC thrives on the dedication of our volunteers. Whether you're passionate about event planning, outdoor adventures, or supporting our members, there's a place for you at the YSC. Join our team and make a lasting impact!
          </p>
        </div>
        <div class="not-prose">
          <picture>
            <source srcset={~p"/images/ysc_group_photo.webp"} type="image/webp" />
            <img
              src={~p"/images/ysc_group_photo.jpg"}
              alt="Group of YSC Members and Volunteers"
              class="w-full h-full object-cover rounded-2xl aspect-video flex items-center justify-center"
              fetchpriority="high"
              loading="eager"
            />
          </picture>
        </div>
      </div>

      <%!-- Form Section --%>
      <div class="max-w-3xl">
        <div class="prose prose-zinc prose-a:text-blue-600 mb-8">
          <h2>Join Our Team</h2>
          <p>
            YSC is 100% volunteer-led. Your help keeps our cabins open and our traditions alive!
          </p>
        </div>

        <div class="not-prose">
          <.simple_form
            for={@form}
            phx-change="validate"
            phx-submit="save"
            id="volunteer-form"
          >
            <%!-- Show user info if logged in, otherwise show input fields --%>
            <.submitting_as
              :if={@logged_in?}
              user={@current_user}
              id="volunteer-submitting-as"
            >
              <%!-- Hidden fields to ensure name and email are submitted --%>
              <input
                type="hidden"
                name={@form[:name].name}
                value={@form[:name].value}
              />
              <input
                type="hidden"
                name={@form[:email].name}
                value={@form[:email].value}
              />
            </.submitting_as>

            <div
              :if={!@logged_in?}
              class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8"
            >
              <.input
                field={@form[:name]}
                label="Name*"
                class="focus:ring-2 focus:ring-blue-500/20"
              />
              <.input
                field={@form[:email]}
                type="email"
                label="Email*"
                class="focus:ring-2 focus:ring-blue-500/20"
              />
            </div>

            <%!-- Interest Cards --%>
            <div class="mb-8">
              <p class="font-semibold text-zinc-900 mb-4">
                How would you like to volunteer with the YSC? Select all that apply.
              </p>

              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <.checkbox_card
                  :for={card <- volunteer_interest_cards()}
                  field={@form[card.field]}
                  icon={card.icon}
                  label={card.label}
                  description={card.description}
                  hover_class={card.hover_class}
                  phx-debounce="blur"
                />
              </div>
            </div>

            <div :if={!@logged_in?} class="w-full flex mb-6">
              <Turnstile.widget theme="light" />
            </div>

            <div
              :if={@submitted}
              class="mb-6 p-6 bg-green-50 border-2 border-green-200 rounded-xl"
            >
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-check-circle"
                  class="text-green-600 w-8 h-8 flex-shrink-0 mt-0.5"
                />
                <div>
                  <p class="text-green-800 font-bold text-lg mb-2">Välkommen! (Welcome!)</p>
                  <p class="text-green-700">
                    One of our board members will reach out to you within a few days. Thank you for your interest in volunteering with the YSC!
                  </p>
                </div>
              </div>
            </div>

            <:actions>
              <.button
                :if={!@submitted}
                id="volunteer-submit-button"
                type="submit"
                phx-disable-with="Sending..."
                class="w-full md:w-auto"
              >
                Submit volunteer form
              </.button>
            </:actions>
          </.simple_form>
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
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)

    {:ok,
     socket
     |> assign(:page_title, "Volunteer")
     |> assign(
       :meta_description,
       "Volunteer with the Young Scandinavians Club. Help organize events, assist at cabin trips, and give back to our community."
     )
     |> assign(:logged_in?, current_user != nil)
     |> assign(:current_user, current_user)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)
     |> assign(:load_turnstile, true)}
  end

  @impl true
  def handle_event("validate", %{"volunteer" => volunteer_params}, socket) do
    changeset =
      %Ysc.Forms.Volunteer{}
      |> Ysc.Forms.Volunteer.changeset(volunteer_params)
      |> Ysc.Forms.Volunteer.put_submitter(socket.assigns[:current_user])

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"volunteer" => volunteer_params} = values, socket) do
    changeset =
      %Ysc.Forms.Volunteer{}
      |> Ysc.Forms.Volunteer.changeset(volunteer_params)
      |> Ysc.Forms.Volunteer.put_submitter(socket.assigns[:current_user])

    if socket.assigns.logged_in? do
      case Ysc.Forms.create_volunteer(changeset) do
        {:ok, _volunteer} ->
          {:noreply,
           socket
           |> assign(:submitted, true)
           |> YscWeb.Flash.put_toast(:info, "Volunteer form submitted",
             title: "Volunteer"
           )}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    else
      case Turnstile.verify(values, socket.assigns.remote_ip) do
        {:ok, _} ->
          case Ysc.Forms.create_volunteer(changeset) do
            {:ok, _volunteer} ->
              {:noreply,
               assign(socket, submitted: true)
               |> YscWeb.Flash.put_toast(
                 :info,
                 "Thank you for your interest in volunteering with the YSC!",
                 title: "Volunteer"
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
              title: "Volunteer"
            )
            |> Turnstile.refresh()

          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "volunteer")

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

  defp volunteer_interest_cards do
    [
      %{
        field: :interest_events,
        icon: "hero-calendar",
        label: "Events & Parties",
        description: "Help organize banquets and social gatherings.",
        hover_class: nil
      },
      %{
        field: :interest_activities,
        icon: "hero-map",
        label: "Activities",
        description: "Plan outdoor adventures and member activities.",
        hover_class: nil
      },
      %{
        field: :interest_clear_lake,
        icon: "hero-home",
        label: "Clear Lake",
        description: "Help maintain and manage our Clear Lake cabin.",
        hover_class: "hover:border-orange-200"
      },
      %{
        field: :interest_tahoe,
        icon: "hero-home-modern",
        label: "Tahoe",
        description: "Support our mountain retreat at Lake Tahoe.",
        hover_class: "hover:border-orange-200"
      },
      %{
        field: :interest_marketing,
        icon: "hero-megaphone",
        label: "Marketing",
        description: "Help us grow our Instagram and newsletter.",
        hover_class: "hover:border-purple-200"
      },
      %{
        field: :interest_website,
        icon: "hero-computer-desktop",
        label: "Website",
        description: "Help improve and maintain our website.",
        hover_class: "hover:border-purple-200"
      }
    ]
  end
end
