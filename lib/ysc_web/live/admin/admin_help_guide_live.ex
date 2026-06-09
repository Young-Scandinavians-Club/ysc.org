defmodule YscWeb.AdminHelpGuideLive do
  @moduledoc """
  Interactive step-by-step wizard for a single admin help guide.
  """
  use YscWeb, :admin_live_view

  import YscWeb.AdminHelpComponents

  alias Ysc.AdminHelp.Assistant
  alias YscWeb.AdminHelp.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :help)
     |> assign(:guide_mod, nil)
     |> assign(:steps, [])
     |> assign(:step_labels, [])
     |> assign(:current_step, 0)
     |> assign(:clarifier_expanded?, false)
     |> assign(:clarifier_question, "")
     |> assign(:clarifier_answer, nil)
     |> assign(:clarifier_suggested_step, nil)
     |> assign(:clarifier_loading?, false)
     |> assign(:clarifier_error, nil)
     |> assign(:assistant_enabled?, Assistant.enabled?())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = slug_from_params(params)

    case Registry.fetch_for_role(slug, socket.assigns.admin_role) do
      {:ok, guide_mod} ->
        steps = guide_mod.steps()
        step_labels = Enum.map(steps, & &1.title)

        {:noreply,
         socket
         |> assign(:page_title, guide_mod.title())
         |> assign(:guide_mod, guide_mod)
         |> assign(:guide_slug, slug)
         |> assign(:steps, steps)
         |> assign(:step_labels, step_labels)
         |> assign(:current_step, initial_step(params, steps))
         |> assign(:highlight, highlight_from_params(params))
         |> assign(:clarifier_answer, nil)
         |> assign(:clarifier_error, nil)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, "That guide is not available for your role.")
         |> push_navigate(to: ~p"/admin/help")}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Guide not found.")
         |> push_navigate(to: ~p"/admin/help")}
    end
  end

  @impl true
  def handle_event("set-step", %{"step" => step}, socket) do
    step =
      String.to_integer(step) |> max(0) |> min(length(socket.assigns.steps) - 1)

    {:noreply, socket |> assign(:current_step, step) |> assign(:highlight, nil)}
  end

  @impl true
  def handle_event("prev-step", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_step, max(0, socket.assigns.current_step - 1))
     |> assign(:highlight, nil)}
  end

  @impl true
  def handle_event("next-step", _params, socket) do
    max_idx = length(socket.assigns.steps) - 1

    {:noreply,
     socket
     |> assign(:current_step, min(max_idx, socket.assigns.current_step + 1))
     |> assign(:highlight, nil)}
  end

  @impl true
  def handle_event("print-help", _params, socket) do
    title = "YSC Admin Guide — #{socket.assigns.guide_mod.title()}"

    {:noreply, push_event(socket, "print-page", %{title: title})}
  end

  @impl true
  def handle_event("toggle-clarifier", _params, socket) do
    {:noreply,
     assign(socket, :clarifier_expanded?, !socket.assigns.clarifier_expanded?)}
  end

  @impl true
  def handle_event("ask-clarifier", %{"question" => question}, socket) do
    question = String.trim(question)

    if question == "" do
      {:noreply, assign(socket, :clarifier_error, "Enter a question.")}
    else
      socket =
        socket
        |> assign(:clarifier_question, question)
        |> assign(:clarifier_loading?, true)
        |> assign(:clarifier_error, nil)
        |> assign(:clarifier_answer, nil)

      send(self(), {:clarify_step, question, socket.assigns.current_user.id})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:clarify_step, question, user_id}, socket) do
    guide_mod = socket.assigns.guide_mod
    step_index = socket.assigns.current_step + 1
    role = socket.assigns.admin_role

    result =
      Assistant.clarify_step(guide_mod, step_index, question, role, user_id)

    socket =
      case result do
        {:ok, %{answer: answer, suggested_step: suggested}} ->
          socket
          |> assign(:clarifier_loading?, false)
          |> assign(:clarifier_answer, answer)
          |> assign(:clarifier_suggested_step, suggested)

        {:error, :rate_limited} ->
          socket
          |> assign(:clarifier_loading?, false)
          |> assign(
            :clarifier_error,
            "Too many requests — try again in a few minutes."
          )

        {:error, _} ->
          socket
          |> assign(:clarifier_loading?, false)
          |> assign(:clarifier_error, "Assistant unavailable right now.")
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu active_page={@active_page} user={@current_user} role={@admin_role}>
      <div :if={@guide_mod} class="py-6 max-w-3xl admin-help-page">
        <div class="print:hidden">
          <.link
            navigate={~p"/admin/help"}
            class="inline-flex items-center text-sm text-zinc-500 hover:text-zinc-800 mb-4"
            id="admin-help-back"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 me-1" /> All guides
          </.link>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <.admin_page_title>{@guide_mod.title()}</.admin_page_title>
              <p class="mt-2 text-zinc-600">{@guide_mod.summary()}</p>
            </div>
            <.admin_help_print_button id="admin-help-print-guide" class="shrink-0" />
          </div>

          <div class="mt-8 mb-6">
            <.admin_help_stepper
              id="admin-help-stepper"
              active_step={@current_step}
              steps={@step_labels}
            />
          </div>
        </div>

        <div class="bg-white rounded-xl border border-zinc-200 p-6 md:p-8 shadow-sm print:hidden">
          <.admin_help_step
            id={"admin-help-step-#{@current_step}"}
            step={Enum.at(@steps, @current_step)}
            step_index={@current_step + 1}
            step_count={length(@steps)}
            highlight={@highlight}
            sidebar_collapsed={@sidebar_collapsed}
          />

          <.admin_help_clarifier
            id="admin-help-clarifier"
            expanded?={@clarifier_expanded?}
            question={@clarifier_question}
            answer={@clarifier_answer}
            loading?={@clarifier_loading?}
            error={@clarifier_error}
            suggested_step={@clarifier_suggested_step}
            enabled?={@assistant_enabled?}
          />
        </div>

        <div class="mt-6 flex justify-between items-center print:hidden">
          <.button
            :if={@current_step > 0}
            type="button"
            phx-click="prev-step"
            id="admin-help-prev"
            variant="outline"
            color="zinc"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 -mt-0.5" /> Previous
          </.button>
          <span :if={@current_step == 0}></span>

          <.button
            :if={@current_step < length(@steps) - 1}
            type="button"
            phx-click="next-step"
            id="admin-help-next"
          >
            Next <.icon name="hero-arrow-right" class="w-4 h-4 -mt-0.5" />
          </.button>
          <.button
            :if={@current_step == length(@steps) - 1}
            navigate={~p"/admin/help"}
            id="admin-help-finish"
          >
            Done — back to all guides
          </.button>
        </div>

        <.admin_help_print_document
          guide_mod={@guide_mod}
          steps={@steps}
          slug={@guide_slug}
        />
      </div>
    </.side_menu>
    """
  end

  defp slug_from_params(%{"slug" => slug}) when is_binary(slug), do: slug

  defp slug_from_params(%{"parts" => parts}) when is_list(parts),
    do: Enum.join(parts, "/")

  defp slug_from_params(_), do: ""

  # ?step= is 1-based (matching what the finder shows users).
  defp initial_step(%{"step" => step}, steps) when is_binary(step) do
    case Integer.parse(step) do
      {n, _} -> (n - 1) |> max(0) |> min(length(steps) - 1)
      :error -> 0
    end
  end

  defp initial_step(_, _), do: 0

  defp highlight_from_params(%{"highlight" => highlight})
       when is_binary(highlight) and highlight != "",
       do: String.slice(highlight, 0, 200)

  defp highlight_from_params(_), do: nil
end
