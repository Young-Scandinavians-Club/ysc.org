defmodule YscWeb.AdminHelpLive do
  @moduledoc """
  Index of interactive admin help guides for volunteers and admins.
  """
  use YscWeb, :admin_live_view

  import YscWeb.AdminHelpComponents

  alias Ysc.AdminHelp.Assistant
  alias YscWeb.AdminHelp.Guide
  alias YscWeb.AdminHelp.Registry

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.admin_role

    {:ok,
     socket
     |> assign(:active_page, :help)
     |> assign(:page_title, "Help")
     |> assign(:finder_query, "")
     |> assign(:finder_result, nil)
     |> assign(:finder_loading?, false)
     |> assign(:finder_error, nil)
     |> assign(:assistant_enabled?, Assistant.enabled?())
     |> assign(:guides_by_category, Registry.guides_by_category(role))}
  end

  @impl true
  def handle_event("find-guide", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       assign(socket, finder_error: "Describe what you are trying to do.")}
    else
      socket =
        socket
        |> assign(:finder_query, query)
        |> assign(:finder_loading?, true)
        |> assign(:finder_error, nil)
        |> assign(:finder_result, nil)

      send(self(), {:find_guide, query, socket.assigns.current_user.id})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:find_guide, query, user_id}, socket) do
    role = socket.assigns.admin_role

    result =
      case Assistant.find_guide(query, role, user_id) do
        {:ok, data} ->
          %{
            explanation: data.explanation,
            guide_slug: data.guide_slug,
            step: data.step,
            highlight: data.highlight
          }

        {:error, :rate_limited} ->
          assign(socket,
            finder_loading?: false,
            finder_error: "Too many requests — try again in a few minutes."
          )

        {:error, _} ->
          assign(socket,
            finder_loading?: false,
            finder_error:
              "Assistant unavailable right now. Browse the guides below."
          )
      end

    socket =
      if match?(%{explanation: _}, result) do
        socket
        |> assign(:finder_loading?, false)
        |> assign(:finder_result, result)
      else
        result
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu active_page={@active_page} user={@current_user} role={@admin_role}>
      <div class="py-6 max-w-5xl admin-help-page">
        <div class="print:hidden">
          <.admin_page_title>Help</.admin_page_title>
          <p class="mt-2 text-zinc-600">
            <%= if @admin_role == :volunteer do %>
              Step-by-step guides for the tools in your sidebar — posts, events, newsletters, media, and day-of check-in.
            <% else %>
              Step-by-step guides for posting news, sending newsletters, managing events, and day-of operations.
            <% end %>
          </p>
        </div>

        <.admin_help_finder
          id="admin-help-finder"
          query={@finder_query}
          result={@finder_result}
          loading?={@finder_loading?}
          error={@finder_error}
          enabled?={@assistant_enabled?}
        />

        <div class="space-y-10 print:hidden">
          <section
            :for={{category, guides} <- @guides_by_category}
            id={"admin-help-category-#{category}"}
          >
            <h2 class="text-lg font-semibold text-zinc-800 mb-4">
              {Guide.category_label(category)}
            </h2>
            <div class="grid gap-4 sm:grid-cols-2">
              <.link
                :for={guide_mod <- guides}
                navigate={~p"/admin/help/#{guide_mod.slug()}"}
                id={"admin-help-card-#{slug_id(guide_mod.slug())}"}
                class="block rounded-xl border border-zinc-200 bg-white p-5 shadow-sm hover:border-blue-300 hover:shadow-md transition-all"
              >
                <h3 class="font-semibold text-zinc-900">{guide_mod.title()}</h3>
                <p class="mt-1 text-sm text-zinc-600 line-clamp-2">
                  {guide_mod.summary()}
                </p>
                <span class="mt-3 inline-flex items-center text-sm text-blue-600 font-medium">
                  Start guide <.icon name="hero-arrow-right" class="w-4 h-4 ms-1" />
                </span>
              </.link>
            </div>
          </section>
        </div>

        <.admin_help_print_index guides_by_category={@guides_by_category} />
      </div>
    </.side_menu>
    """
  end

  defp slug_id(slug), do: String.replace(slug, "/", "-")
end
