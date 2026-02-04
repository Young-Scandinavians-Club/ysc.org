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
          <%!-- Placeholder for volunteer photo --%>
          <img
            src="/images/ysc_group_photo.jpg"
            alt="Group of YSC Members and Volunteers"
            class="w-full h-full object-cover rounded-2xl aspect-video flex items-center justify-center"
          />
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
            </div>

            <div
              :if={!@logged_in?}
              class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8"
            >
              <.input
                field={@form[:name]}
                label="Name (*)"
                class="focus:ring-2 focus:ring-blue-500/20"
              />
              <.input
                field={@form[:email]}
                type="email"
                label="Email (*)"
                class="focus:ring-2 focus:ring-blue-500/20"
              />
            </div>

            <%!-- Interest Cards --%>
            <div class="mb-8">
              <p class="font-semibold text-zinc-900 mb-4">
                How would you like to volunteer with the YSC? Select all that apply.
              </p>

              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%!-- Events/Parties --%>
                <label
                  for={@form[:interest_events].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_events].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_events].id}
                    name={@form[:interest_events].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_events].value
                      )
                    }
                    aria-label="Events & Parties: Help organize banquets and social gatherings"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-calendar"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Events & Parties
                  </span>
                  <span class="text-xs text-zinc-500">
                    Help organize banquets and social gatherings.
                  </span>
                </label>

                <%!-- Activities --%>
                <label
                  for={@form[:interest_activities].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_activities].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_activities].id}
                    name={@form[:interest_activities].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_activities].value
                      )
                    }
                    aria-label="Activities: Plan outdoor adventures and member activities"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-map"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Activities
                  </span>
                  <span class="text-xs text-zinc-500">
                    Plan outdoor adventures and member activities.
                  </span>
                </label>

                <%!-- Clear Lake --%>
                <label
                  for={@form[:interest_clear_lake].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 hover:border-orange-200 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_clear_lake].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_clear_lake].id}
                    name={@form[:interest_clear_lake].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_clear_lake].value
                      )
                    }
                    aria-label="Clear Lake: Help maintain and manage our Clear Lake cabin"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-home"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Clear Lake
                  </span>
                  <span class="text-xs text-zinc-500">
                    Help maintain and manage our Clear Lake cabin.
                  </span>
                </label>

                <%!-- Tahoe --%>
                <label
                  for={@form[:interest_tahoe].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 hover:border-orange-200 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_tahoe].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_tahoe].id}
                    name={@form[:interest_tahoe].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_tahoe].value
                      )
                    }
                    aria-label="Tahoe: Support our mountain retreat at Lake Tahoe"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-home-modern"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Tahoe
                  </span>
                  <span class="text-xs text-zinc-500">
                    Support our mountain retreat at Lake Tahoe.
                  </span>
                </label>

                <%!-- Marketing --%>
                <label
                  for={@form[:interest_marketing].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 hover:border-purple-200 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_marketing].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_marketing].id}
                    name={@form[:interest_marketing].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_marketing].value
                      )
                    }
                    aria-label="Marketing: Help us grow our Instagram and newsletter"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-megaphone"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Marketing
                  </span>
                  <span class="text-xs text-zinc-500">
                    Help us grow our Instagram and newsletter.
                  </span>
                </label>

                <%!-- Website --%>
                <label
                  for={@form[:interest_website].id}
                  class="relative flex flex-col p-5 border-2 rounded-xl cursor-pointer hover:bg-zinc-50 hover:border-purple-200 transition-all border-zinc-200 has-[:checked]:border-blue-600 has-[:checked]:bg-blue-50/50 has-[:checked]:scale-[1.02] group"
                >
                  <input
                    type="hidden"
                    name={@form[:interest_website].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id={@form[:interest_website].id}
                    name={@form[:interest_website].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:interest_website].value
                      )
                    }
                    aria-label="Website: Help improve and maintain our website"
                    class="absolute top-4 right-4 w-5 h-5 rounded border-zinc-300 text-blue-600 focus:ring-2 focus:ring-blue-500/20 focus:ring-offset-0"
                    phx-debounce="blur"
                  />
                  <.icon
                    name="hero-computer-desktop"
                    class="w-8 h-8 text-zinc-400 group-has-[:checked]:text-blue-600 mb-3 transition-all duration-200 group-has-[:checked]:animate-bounce"
                  />
                  <span class="font-bold text-zinc-900 leading-tight mb-1">
                    Website
                  </span>
                  <span class="text-xs text-zinc-500">
                    Help improve and maintain our website.
                  </span>
                </label>
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
                  <p class="text-green-800 font-bold text-lg mb-2">Välkommen!</p>
                  <p class="text-green-700">
                    One of our board members will reach out to you within a few days. Thank you for your interest in volunteering with the YSC!
                  </p>
                </div>
              </div>
            </div>

            <:actions>
              <.button
                :if={!@submitted}
                type="submit"
                class="w-full md:w-auto phx-submit-loading:opacity-75"
              >
                <span class="phx-submit-loading:hidden">Submit Application →</span>
                <span class="hidden phx-submit-loading:inline text-zinc-300">
                  Sending...
                </span>
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
     |> assign(:logged_in?, current_user != nil)
     |> assign(:current_user, current_user)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)
     |> assign(:load_turnstile, true)}
  end

  @impl true
  def handle_event("validate", %{"volunteer" => volunteer_params}, socket) do
    params = add_user_id(volunteer_params, socket.assigns[:current_user])
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)
    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"volunteer" => volunteer_params} = values, socket) do
    params = add_user_id(volunteer_params, socket.assigns[:current_user])
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)

    if socket.assigns.logged_in? do
      case Ysc.Forms.create_volunteer(changeset) do
        {:ok, _volunteer} ->
          {:noreply,
           socket
           |> assign(:submitted, true)
           |> put_flash(:info, "Volunteer application submitted")}

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
               |> put_flash(
                 :info,
                 "Thank you for your interest in volunteering with the YSC!"
               )}

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
      email: user.email,
      user_id: user.id
    }
  end

  defp add_user_id(params, nil), do: params
  defp add_user_id(params, user), do: Map.put(params, "user_id", user.id)
end
