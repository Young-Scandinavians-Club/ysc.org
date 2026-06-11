defmodule YscWeb.AdminHelpComponents do
  @moduledoc """
  Components for interactive admin help wizards.
  """
  use Phoenix.Component
  use Gettext, backend: YscWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  import Phoenix.HTML
  import YscWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias YscWeb.AdminHelp.Ghost.Registry, as: GhostRegistry
  alias YscWeb.AdminHelp.Guide
  alias YscWeb.AdminHelp.Hotspot

  @doc """
  Step navigation built for guide wizards, where step titles are full
  sentences. Each step gets an equal-width segment with a progress bar and a
  truncated label, so long titles can never break the layout. On small
  screens the labels collapse into a single "Step n of N" summary line.

  Clicking a segment sends `set-step` with the 0-based step index, matching
  the wizard's existing event handler.
  """
  attr :id, :string, default: "admin-help-stepper"
  attr :steps, :list, required: true, doc: "ordered step titles"

  attr :active_step, :integer,
    required: true,
    doc: "0-based index of the current step"

  attr :class, :string, default: nil

  def admin_help_stepper(assigns) do
    assigns = assign(assigns, :step_count, length(assigns.steps))

    ~H"""
    <nav id={@id} aria-label="Guide steps" class={@class}>
      <ol class="flex items-stretch gap-1.5 sm:gap-2">
        <li :for={{label, idx} <- Enum.with_index(@steps)} class="min-w-0 flex-1">
          <button
            type="button"
            phx-click="set-step"
            phx-value-step={idx}
            aria-current={if(idx == @active_step, do: "step")}
            aria-label={"Step #{idx + 1}: #{label}"}
            title={"Step #{idx + 1}: #{label}"}
            class="group block w-full cursor-pointer rounded text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
          >
            <span class={[
              "block h-1.5 rounded-full transition-colors duration-150",
              stepper_bar_class(idx, @active_step)
            ]}></span>
            <span class={[
              "mt-2 hidden items-center gap-1.5 text-xs leading-5 md:flex",
              stepper_label_class(idx, @active_step)
            ]}>
              <span class="shrink-0 tabular-nums">
                <%= if idx < @active_step do %>
                  <.icon name="hero-check" class="h-3.5 w-3.5 -mt-0.5" />
                <% else %>
                  {idx + 1}.
                <% end %>
              </span>
              <span class="truncate">{label}</span>
            </span>
          </button>
        </li>
      </ol>
      <p class="mt-2 text-sm text-zinc-600 md:hidden">
        <span class="font-semibold text-zinc-900">
          Step {@active_step + 1} of {@step_count}:
        </span>
        {Enum.at(@steps, @active_step)}
      </p>
    </nav>
    """
  end

  defp stepper_bar_class(idx, active) do
    cond do
      idx == active -> "bg-blue-600"
      idx < active -> "bg-blue-300 group-hover:bg-blue-400"
      true -> "bg-zinc-200 group-hover:bg-zinc-300"
    end
  end

  defp stepper_label_class(idx, active) do
    cond do
      idx == active -> "font-semibold text-blue-800"
      idx < active -> "text-zinc-600 group-hover:text-blue-700"
      true -> "text-zinc-400 group-hover:text-zinc-600"
    end
  end

  attr :id, :string, required: true
  attr :step, :map, required: true
  attr :step_index, :integer, required: true
  attr :step_count, :integer, required: true
  attr :highlight, :string, default: nil
  attr :sidebar_collapsed, :boolean, default: false
  attr :class, :string, default: nil

  def admin_help_step(assigns) do
    ~H"""
    <div
      id={@id}
      class={["admin-help-step", @class]}
      phx-mounted={
        JS.transition(
          {"transition ease-out duration-300", "opacity-0 translate-x-2",
           "opacity-100 translate-x-0"}
        )
      }
    >
      <p class="text-sm font-medium text-zinc-500 mb-1">
        Step {@step_index} of {@step_count}
      </p>
      <h2 class="text-xl font-semibold text-zinc-900 mb-3">{@step.title}</h2>
      <div class="prose prose-zinc prose-sm max-w-none mb-6">
        {raw(format_help_body(@step.body, @highlight))}
      </div>

      <.admin_help_screenshot
        :if={@step[:image]}
        id={"#{@id}-screenshot"}
        image={@step.image}
        image_scroll={Map.get(@step, :image_scroll)}
        hotspots={Map.get(@step, :hotspots, [])}
        sidebar_collapsed={@sidebar_collapsed}
        alt={@step.title}
      />

      <.admin_help_public_effect
        :if={@step[:public_image]}
        id={"#{@id}-public"}
        image={@step.public_image}
        image_scroll={Map.get(@step, :public_image_scroll)}
        hotspots={Map.get(@step, :public_hotspots, [])}
        sidebar_collapsed={@sidebar_collapsed}
        label={Map.get(@step, :public_label, "What members see on the website")}
      />

      <div :if={@step[:cta]} class="mt-6">
        <.button navigate={@step.cta.path} variant="outline" id={"#{@id}-cta"}>
          {@step.cta.label}
          <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4 -mt-0.5" />
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  Shows how the action appears on the public member-facing site, below the
  admin screenshot. Uses the same ghost iframe embed as admin illustrations.
  """
  attr :id, :string, required: true
  attr :image, :string, required: true
  attr :image_scroll, :string, default: nil
  attr :hotspots, :list, default: []
  attr :sidebar_collapsed, :boolean, default: false
  attr :label, :string, default: "What members see on the website"

  def admin_help_public_effect(assigns) do
    ~H"""
    <div class="mt-6 rounded-xl border border-emerald-200 bg-emerald-50/50 p-4 print:break-inside-avoid">
      <p class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-emerald-800">
        <.icon name="hero-globe-alt" class="w-4 h-4 shrink-0" />
        {@label}
      </p>
      <.admin_help_screenshot
        id={@id}
        image={@image}
        image_scroll={@image_scroll}
        hotspots={@hotspots}
        sidebar_collapsed={@sidebar_collapsed}
        alt={@label}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :image, :string, required: true
  attr :image_scroll, :string, default: nil
  attr :hotspots, :list, default: []
  attr :sidebar_collapsed, :boolean, default: false
  attr :alt, :string, required: true

  def admin_help_screenshot(assigns) do
    ghost_slug = ghost_slug(assigns.image)

    assigns =
      assigns
      |> assign(:ghost_slug, ghost_slug)
      |> assign(
        :image_src,
        screenshot_src(
          assigns.image,
          assigns.sidebar_collapsed,
          assigns.image_scroll
        )
      )
      |> assign(:hotspots, Hotspot.normalize(assigns.hotspots, ghost_slug))

    ~H"""
    <div
      id={@id}
      class={[
        "relative rounded-lg border border-zinc-200 bg-zinc-50 overflow-hidden shadow-sm",
        @ghost_slug && Hotspot.admin_ghost?(@ghost_slug) &&
          "admin-help-sidebar-aware"
      ]}
      phx-hook={
        if(@ghost_slug, do: "AdminHelpGhostFrame", else: "AdminHelpHotspots")
      }
    >
      <%= if @ghost_slug do %>
        <div
          class="admin-help-ghost-viewport admin-help-sidebar-aware"
          data-ghost-slug={@ghost_slug}
        >
          <iframe
            id={"#{@id}-iframe"}
            src={@image_src}
            data-ghost-src={@image_src}
            title={@alt}
            class="admin-help-ghost-iframe"
            tabindex="-1"
            loading="lazy"
          />
        </div>
      <% else %>
        <img src={@image_src} alt={@alt} class="w-full h-auto block" loading="lazy" />
      <% end %>
      <div
        :for={{hotspot, idx} <- Enum.with_index(@hotspots)}
        class="admin-help-hotspot-wrap"
      >
        <button
          type="button"
          id={"#{@id}-hotspot-#{idx}"}
          class={["admin-help-hotspot", Hotspot.style_class(hotspot)]}
          style={Hotspot.css_vars(hotspot)}
          aria-label={hotspot.label}
          data-hotspot-label={hotspot.label}
        >
          <span
            :if={Hotspot.hint?(hotspot)}
            class="admin-help-hotspot-beacon-wrap"
            aria-hidden="true"
          >
            <span class="admin-help-hotspot-beacon"></span>
            <span class="admin-help-hotspot-ping admin-help-hotspot-ping--hint"></span>
          </span>
          <span
            :if={!Hotspot.hint?(hotspot)}
            class="admin-help-hotspot-ping"
            aria-hidden="true"
          />
          <span
            :if={!Hotspot.hint?(hotspot)}
            class="admin-help-hotspot-dot"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Sleek contextual help affordance: a question mark icon meant to sit right of
  a page title. The hint text appears in a tooltip on hover/focus.
  """
  attr :topic, :string, required: true
  attr :label, :string, default: "Open the guide for this page"
  attr :role, :atom, default: nil
  attr :class, :string, default: nil

  def admin_help_link(assigns) do
    visible? =
      is_nil(assigns.role) or
        YscWeb.AdminHelp.Registry.accessible?(assigns.topic, assigns.role)

    assigns = assign(assigns, :visible?, visible?)

    ~H"""
    <span
      :if={@visible?}
      class={["group/help relative inline-flex shrink-0 print:hidden", @class]}
    >
      <.link
        navigate={~p"/admin/help/#{@topic}"}
        id={"admin-help-link-#{String.replace(@topic, "/", "-")}"}
        class="inline-flex items-center justify-center rounded-full text-zinc-300 hover:text-blue-600 focus-visible:text-blue-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2 transition-colors"
        aria-label={@label}
      >
        <.icon name="hero-question-mark-circle" class="w-5 h-5" />
      </.link>
      <span
        role="tooltip"
        class="pointer-events-none absolute left-1/2 top-full z-50 mt-1.5 -translate-x-1/2 whitespace-nowrap rounded-md bg-zinc-900 px-2.5 py-1.5 text-xs font-medium text-zinc-100 opacity-0 shadow-sm transition-opacity duration-150 group-hover/help:opacity-100 group-focus-within/help:opacity-100"
      >
        {@label}
      </span>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :expanded?, :boolean, default: false
  attr :form, Phoenix.HTML.Form, required: true
  attr :answer, :string, default: nil
  attr :loading?, :boolean, default: false
  attr :error, :string, default: nil
  attr :suggested_step, :integer, default: nil
  attr :enabled?, :boolean, default: false

  def admin_help_clarifier(assigns) do
    ~H"""
    <div :if={@enabled?} id={@id} class="mt-8 border-t border-zinc-200 pt-6">
      <button
        type="button"
        id={"#{@id}-toggle"}
        phx-click="toggle-clarifier"
        class="flex w-full items-center justify-between text-left text-sm font-medium text-zinc-700 hover:text-zinc-900"
        aria-expanded={to_string(@expanded?)}
      >
        <span class="inline-flex items-center gap-2">
          <.icon name="hero-light-bulb" class="w-5 h-5 text-amber-500" />
          Need this step explained differently?
        </span>
        <.icon
          name="hero-chevron-down"
          class={["w-5 h-5 transition-transform", @expanded? && "rotate-180"]}
        />
      </button>

      <div :if={@expanded?} id={"#{@id}-panel"} class="mt-4 space-y-3">
        <p class="text-xs text-zinc-500">
          AI-assisted — follow the steps and screenshots above if anything conflicts.
        </p>
        <.form for={@form} id={"#{@id}-form"} phx-submit="ask-clarifier">
          <.input
            field={@form[:question]}
            type="textarea"
            id={"#{@id}-input"}
            rows="2"
            placeholder="e.g. What if I don't have a cover image yet?"
            disabled={@loading?}
          />
          <div class="mt-2 flex items-center gap-3">
            <.button type="submit" disabled={@loading?}>
              Ask
            </.button>
          </div>
        </.form>
        <div
          :if={@loading?}
          id={"#{@id}-loading"}
          class="flex items-center gap-2 rounded-lg bg-zinc-50 border border-zinc-200 px-4 py-3 text-sm text-zinc-600"
          role="status"
          aria-live="polite"
        >
          <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin text-blue-500" />
          Thinking about your question…
        </div>
        <p :if={@error} class="text-sm text-red-600" role="alert">{@error}</p>
        <div
          :if={@answer}
          class="rounded-lg bg-zinc-50 border border-zinc-200 px-4 py-3 text-sm text-zinc-800"
        >
          {@answer}
          <div :if={@suggested_step} class="mt-3">
            <.button
              type="button"
              variant="outline"
              phx-click="set-step"
              phx-value-step={@suggested_step - 1}
              id={"#{@id}-jump-step"}
            >
              Jump to step {@suggested_step}
              <.icon name="hero-arrow-right" class="w-4 h-4 -mt-0.5" />
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :result, :map, default: nil
  attr :loading?, :boolean, default: false
  attr :error, :string, default: nil
  attr :enabled?, :boolean, default: false

  def admin_help_finder(assigns) do
    ~H"""
    <div
      :if={@enabled?}
      id={@id}
      class="rounded-xl border border-zinc-200 bg-zinc-50 px-5 py-5 mb-8 mt-4"
    >
      <h2 class="text-base font-semibold text-zinc-900 flex items-center gap-2">
        <.icon name="hero-sparkles" class="w-5 h-5 text-violet-500" />
        What are you trying to do?
      </h2>
      <p class="text-sm text-zinc-600 mt-1">
        Describe your task and we will suggest the right guide.
      </p>
      <.form for={@form} id={"#{@id}-form"} phx-submit="find-guide" class="mt-4">
        <div class="flex flex-col sm:flex-row sm:items-center gap-2">
          <div class="flex-1 [&_input]:mt-0 [&_input]:h-10">
            <.input
              field={@form[:query]}
              type="text"
              id={"#{@id}-input"}
              placeholder='e.g. "send the monthly email" or "check people in at the door"'
              disabled={@loading?}
              autocomplete="off"
            />
          </div>
          <.button
            type="submit"
            class="!min-h-10 h-10 shrink-0 py-0"
            disabled={@loading?}
          >
            Find guide
          </.button>
        </div>
      </.form>
      <div
        :if={@loading?}
        id={"#{@id}-loading"}
        class="mt-4 flex items-center gap-2 rounded-lg bg-white border border-zinc-200 px-4 py-3 text-sm text-zinc-600"
        role="status"
        aria-live="polite"
      >
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin text-violet-500" />
        Looking through the guides…
      </div>
      <p :if={@error} class="mt-3 text-sm text-red-600" role="alert">{@error}</p>
      <div
        :if={@result}
        class="mt-4 rounded-lg bg-white border border-zinc-200 px-4 py-3"
      >
        <p class="text-sm text-zinc-800">{@result.explanation}</p>
        <div class="mt-3 flex flex-wrap gap-2">
          <.button
            :if={@result.guide_slug}
            navigate={finder_result_path(@result)}
            id={"#{@id}-open-guide"}
          >
            <%= if @result[:step] do %>
              Open guide at step {@result.step}
            <% else %>
              Open guide
            <% end %>
          </.button>
          <.button
            :if={!@result.guide_slug}
            navigate={~p"/admin/help"}
            variant="outline"
            color="zinc"
            id={"#{@id}-browse-all"}
          >
            Browse all guides
          </.button>
        </div>
      </div>
    </div>
    """
  end

  def format_help_body(body, highlight \\ nil) when is_binary(body) do
    body
    |> String.split(~r/\n\n+/, trim: true)
    |> Enum.map_join(&format_paragraph(&1, highlight))
  end

  defp format_paragraph(text, highlight) do
    if is_binary(highlight) and highlight != "" and
         paragraph_contains?(text, highlight) do
      format_highlighted_paragraph(text, highlight)
    else
      format_plain_paragraph(text)
    end
  end

  defp format_plain_paragraph(text) do
    inner =
      text
      |> then(
        &Regex.split(~r/(\*\*[^*]+\*\*)/, &1,
          include_captures: true,
          trim: true
        )
      )
      |> Enum.map_join(fn part ->
        case Regex.run(~r/^\*\*([^*]+)\*\*$/, part) do
          [_, bold] -> "<strong>#{escape_html(bold)}</strong>"
          _ -> escape_html(part)
        end
      end)

    "<p class=\"mb-3\">#{inner}</p>"
  end

  defp paragraph_contains?(text, highlight) do
    plain = String.replace(text, "**", "")

    String.contains?(String.downcase(plain), String.downcase(highlight))
  end

  # Renders the paragraph containing the highlight without bold parsing
  # (the quote may span ** markers) and wraps the match in <mark>.
  defp format_highlighted_paragraph(text, highlight) do
    plain = String.replace(text, "**", "")
    pattern = Regex.compile!(Regex.escape(highlight), [:caseless, :unicode])

    case Regex.split(pattern, plain, include_captures: true, parts: 2) do
      [before, match, rest] ->
        "<p class=\"mb-3\">#{escape_html(before)}" <>
          "<mark class=\"admin-help-highlight rounded bg-amber-200/80 box-decoration-clone px-0.5 py-0.5\">#{escape_html(match)}</mark>" <>
          "#{escape_html(rest)}</p>"

      _ ->
        format_plain_paragraph(text)
    end
  end

  defp escape_html(text) do
    text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp ghost_slug("ghost:" <> slug) when is_binary(slug) and slug != "",
    do: slug

  defp ghost_slug(_), do: nil

  defp screenshot_src("ghost:" <> slug, sidebar_collapsed?, scroll_to)
       when is_binary(slug),
       do: Hotspot.ghost_src(slug, sidebar_collapsed?, scroll_to)

  defp screenshot_src(path, _sidebar_collapsed?, _scroll_to)
       when is_binary(path),
       do: path

  # Deep-links a finder result to the matched step (and highlight quote)
  # when the assistant pinpointed one.
  defp finder_result_path(%{guide_slug: slug} = result) do
    case result[:step] do
      step when is_integer(step) ->
        query = %{step: step}

        query =
          case result[:highlight] do
            highlight when is_binary(highlight) and highlight != "" ->
              Map.put(query, :highlight, highlight)

            _ ->
              query
          end

        ~p"/admin/help/#{slug}?#{query}"

      _ ->
        ~p"/admin/help/#{slug}"
    end
  end

  # ---------------------------------------------------------------------------
  # Print layouts (hidden on screen, shown when printing / saving to PDF)
  # ---------------------------------------------------------------------------

  attr :guide_mod, :atom, required: true
  attr :steps, :list, required: true
  attr :slug, :string, required: true

  def admin_help_print_document(assigns) do
    faq = assigns.guide_mod.faq()
    troubleshooting = assigns.guide_mod.troubleshooting()

    assigns =
      assigns
      |> assign(:faq, faq)
      |> assign(:troubleshooting, troubleshooting)
      |> assign(
        :category_label,
        Guide.category_label(assigns.guide_mod.category())
      )

    ~H"""
    <article
      id="admin-help-print-document"
      class="admin-help-print-document hidden print:block"
    >
      <header class="admin-help-print-cover">
        <p class="admin-help-print-brand">YSC Admin Guide</p>
        <h1 class="admin-help-print-title">{@guide_mod.title()}</h1>
        <p class="admin-help-print-summary">{@guide_mod.summary()}</p>
        <p class="admin-help-print-meta">
          {@category_label} · {length(@steps)} steps · ysc.org/admin/help/{@slug}
        </p>
      </header>

      <nav :if={length(@steps) > 1} class="admin-help-print-toc" aria-label="Steps">
        <h2 class="admin-help-print-section-heading">Contents</h2>
        <ol>
          <li :for={{step, idx} <- Enum.with_index(@steps, 1)}>
            <span class="admin-help-print-toc-num">{idx}.</span> {step.title}
          </li>
        </ol>
      </nav>

      <section
        :for={{step, idx} <- Enum.with_index(@steps, 1)}
        id={"admin-help-print-step-#{idx}"}
        class="admin-help-print-step"
      >
        <p class="admin-help-print-step-label">Step {idx} of {length(@steps)}</p>
        <h2 class="admin-help-print-step-title">{step.title}</h2>
        <div class="admin-help-print-body prose prose-zinc max-w-none">
          {raw(format_help_body(step.body))}
        </div>

        <.admin_help_print_screenshot
          :if={step[:image]}
          image={step.image}
          hotspots={Map.get(step, :hotspots, [])}
          alt={step.title}
        />

        <p :if={step[:cta]} class="admin-help-print-cta">
          <strong>{step.cta.label}:</strong> {absolute_admin_url(step.cta.path)}
        </p>
      </section>

      <section :if={@faq != []} class="admin-help-print-appendix">
        <h2 class="admin-help-print-section-heading">Frequently asked questions</h2>
        <dl class="admin-help-print-faq">
          <div :for={{question, answer} <- @faq}>
            <dt>{question}</dt>
            <dd>{answer}</dd>
          </div>
        </dl>
      </section>

      <section :if={@troubleshooting != []} class="admin-help-print-appendix">
        <h2 class="admin-help-print-section-heading">Troubleshooting</h2>
        <ul class="admin-help-print-troubleshooting">
          <li :for={item <- @troubleshooting}>{item}</li>
        </ul>
      </section>

      <footer class="admin-help-print-footer">
        <p>
          Interactive version with screenshots and step-by-step navigation:
          <strong>ysc.org/admin/help/{@slug}</strong>
        </p>
      </footer>
    </article>
    """
  end

  attr :image, :string, required: true
  attr :hotspots, :list, default: []
  attr :alt, :string, required: true

  def admin_help_print_screenshot(assigns) do
    ghost_slug = ghost_slug(assigns.image)

    assigns =
      assigns
      |> assign(:image_src, GhostRegistry.print_image_path(assigns.image))
      |> assign(:hotspots, Hotspot.normalize(assigns.hotspots, ghost_slug))

    ~H"""
    <figure class="admin-help-print-figure">
      <div class="admin-help-print-screenshot">
        <img src={@image_src} alt={@alt} />
        <span
          :for={{hotspot, idx} <- Enum.with_index(@hotspots)}
          class={["admin-help-print-marker", Hotspot.print_marker_class(hotspot)]}
          style={Hotspot.print_css_vars(hotspot)}
          aria-hidden="true"
        >
          {idx + 1}
        </span>
      </div>
      <figcaption :if={@hotspots != []}>
        <ol class="admin-help-print-hotspot-legend">
          <li :for={hotspot <- @hotspots}>{hotspot.label}</li>
        </ol>
      </figcaption>
    </figure>
    """
  end

  attr :guides_by_category, :list, required: true

  def admin_help_print_index(assigns) do
    ~H"""
    <article
      id="admin-help-print-index-document"
      class="admin-help-print-document hidden print:block"
    >
      <header class="admin-help-print-cover">
        <p class="admin-help-print-brand">YSC Admin Guide</p>
        <h1 class="admin-help-print-title">Help guides</h1>
        <p class="admin-help-print-summary">
          Step-by-step instructions for posting news, sending newsletters, managing events, and day-of operations.
        </p>
        <p class="admin-help-print-meta">ysc.org/admin/help</p>
      </header>

      <section
        :for={{category, guides} <- @guides_by_category}
        class="admin-help-print-category"
      >
        <h2 class="admin-help-print-section-heading">
          {Guide.category_label(category)}
        </h2>
        <div class="admin-help-print-guide-list">
          <div :for={guide_mod <- guides} class="admin-help-print-guide-card">
            <h3>{guide_mod.title()}</h3>
            <p>{guide_mod.summary()}</p>
            <p class="admin-help-print-guide-url">
              ysc.org/admin/help/{guide_mod.slug()}
            </p>
          </div>
        </div>
      </section>

      <footer class="admin-help-print-footer">
        <p>
          Open any guide in the admin area for interactive walkthroughs with screenshots.
        </p>
      </footer>
    </article>
    """
  end

  attr :label, :string, default: "Print / Save PDF"
  attr :id, :string, default: "admin-help-print-button"
  attr :class, :string, default: nil

  def admin_help_print_button(assigns) do
    assigns =
      assign(
        assigns,
        :button_class,
        String.trim("print:hidden #{assigns.class}")
      )

    ~H"""
    <.button
      type="button"
      id={@id}
      phx-click="print-help"
      variant="outline"
      color="zinc"
      loading_text="Preparing…"
      class={@button_class}
    >
      <.icon name="hero-printer" class="w-5 h-5" />
      {@label}
    </.button>
    """
  end

  defp absolute_admin_url(path) when is_binary(path) do
    YscWeb.Endpoint.url() <> path
  end
end
