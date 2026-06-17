defmodule YscWeb.Components.History.HistoryComponents do
  @moduledoc """
  Functional components for the YSC history page.
  """
  use Phoenix.Component

  import Phoenix.HTML
  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  attr :years, :integer, required: true

  def history_masthead(assigns) do
    ~H"""
    <div id="history-hero" class="max-w-screen-xl mx-auto px-4 mb-12 md:mb-16">
      <.page_masthead
        id="history-masthead"
        eyebrow="History"
        title={"#{@years}+ Years"}
        title_class="tracking-tighter"
      >
        <p class="history-serif text-zinc-500 italic text-sm mt-4 tracking-wide">
          Established 1950
        </p>
        <p class="text-zinc-400 uppercase tracking-[0.25em] text-xs mt-2">
          San Francisco, California
        </p>
      </.page_masthead>

      <div class="max-w-2xl mx-auto mt-10 md:mt-12 text-center">
        <h2 class="text-2xl md:text-3xl font-medium text-zinc-900 mb-6 history-serif">
          A Legacy of Friendship: The YSC Story
        </h2>

        <div class="space-y-5 text-lg text-zinc-600 leading-relaxed text-left">
          <p>
            The Young Scandinavians Club was founded in 1950 by <strong class="text-zinc-800">Arnold Rolkert</strong>, <strong class="text-zinc-800">Gunnar Engen</strong>, <strong class="text-zinc-800">Carlo Hojsgaard</strong>, <strong class="text-zinc-800">Peter Larsen Bernard</strong>, and <strong class="text-zinc-800">Ulla Lindberg</strong>.
            The idea was to build a club for newly settled Scandinavians who were far from home—where they could speak their native language and celebrate time-honored Scandinavian traditions here in San Francisco.
          </p>
          <p>
            The founding members also wanted to offer a fun, active, festive alternative to some of the more traditional Scandinavian lodges in the city. With an active social calendar, it became much easier for newly arrived Scandinavians to feel that they had a community in the Bay Area, far from home.
          </p>
          <p>
            Members eventually wrote the bylaws and elected the club's first president in 1951: Arnold Rolkert, a Swede. By 1963, membership had grown significantly and the Clear Lake cabin was purchased. Thirty years later, in 1993, the Lake Tahoe cabin followed—giving the club two homes in Northern California.
          </p>
        </div>

        <blockquote class="border-l-2 border-zinc-300 pl-6 italic text-zinc-600 text-left max-w-xl mx-auto history-serif mt-8">
          <p class="text-base leading-relaxed">
            Today the YSC remains one of the most active Scandinavian organizations in the Bay Area—offering endless opportunities to enjoy all that Northern California has to offer, and to share American culture with fellow Scandinavians along the way.
          </p>
        </blockquote>
      </div>
    </div>
    """
  end

  def timeline_filters(assigns) do
    ~H"""
    <div class="not-prose mb-10">
      <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-6 border-b border-zinc-200">
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <.icon name="hero-clock" class="w-4 h-4" />
          <span>~12 min read</span>
        </div>
        <div class="text-sm text-zinc-400 hidden sm:block">
          <.icon name="hero-funnel" class="w-4 h-4 inline" /> Filter by category
        </div>
      </div>

      <div
        id="timeline-filters"
        phx-hook="TimelineFilter"
        class="flex flex-wrap gap-2 mt-4"
      >
        <.filter_button
          filter="all"
          label="All Events"
          icon="hero-squares-2x2"
          active={true}
        />
        <.filter_button filter="founding" label="Founding" icon="hero-sparkles" />
        <.filter_button
          filter="club leadership"
          label="Leadership"
          icon="hero-user-group"
        />
        <.filter_button filter="cabin life" label="Cabins" icon="hero-home-modern" />
        <.filter_button filter="anniversary" label="Anniversaries" icon="hero-cake" />
      </div>
    </div>
    """
  end

  attr :filter, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false

  defp filter_button(assigns) do
    assigns =
      assign(
        assigns,
        :filter_id,
        "timeline-filter-" <> String.replace(assigns.filter, " ", "-")
      )

    ~H"""
    <button
      id={@filter_id}
      data-filter={@filter}
      data-active={to_string(@active)}
      class={[
        "px-4 py-2 rounded-md text-sm font-medium transition-colors duration-150",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2",
        if(@active,
          do: "bg-blue-600 text-white border-blue-600",
          else: "border border-zinc-300 text-zinc-500 hover:border-zinc-400"
        )
      ]}
    >
      <.icon name={@icon} class="w-4 h-4 inline mr-1" />
      {@label}
    </button>
    """
  end

  slot :inner_block, required: true

  def timeline(assigns) do
    ~H"""
    <div id="history-timeline" class="post-render relative" phx-hook="GLightboxHook">
      <div class="hidden md:block absolute left-8 top-0 bottom-0 w-px bg-zinc-200 z-0">
      </div>
      <div class="space-y-16 md:space-y-20">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true

  def timeline_decade(assigns) do
    ~H"""
    <div class="relative py-4">
      <div class="decade-watermark history-serif">{@label}</div>
    </div>
    """
  end

  attr :event, :map, required: true

  def timeline_event_from_data(assigns) do
    event = assigns.event
    era = era_for_year(event.year)

    assigns =
      assigns
      |> assign(:era, era)
      |> assign(:tags_string, Enum.join(event.tags, ", "))

    ~H"""
    <.timeline_event
      year={@event.year}
      title={@event.title}
      tags={@event.tags}
      extra_tags={@event.extra_tags}
      tags_string={@tags_string}
      type={@event.type}
    >
      <%= if @event.images != [] do %>
        <div class={[
          "my-6",
          if(length(@event.images) > 1, do: "grid md:grid-cols-2 gap-6", else: "")
        ]}>
          <%= for image <- @event.images do %>
            <.archival_photo
              src={image.src}
              alt={image.alt}
              caption={image.caption}
              era={image.era || @era}
              aspect={image.aspect || "4/3"}
            />
          <% end %>
        </div>
      <% end %>

      <%= if @event.blockquote do %>
        <blockquote class="border-l-2 border-zinc-300 pl-4 italic text-zinc-600 my-6 history-serif">
          <p>{@event.blockquote}</p>
        </blockquote>
      <% end %>

      <%= if @event.ledger do %>
        <div class="ledger-callout my-6">
          {raw(String.replace(@event.ledger, "\n", "<br />"))}
        </div>
      <% end %>

      <%= if @event.body_html do %>
        <p class="text-zinc-600 leading-relaxed">{raw(@event.body_html)}</p>
      <% else %>
        <%= if @event.body do %>
          <p class="text-zinc-600 leading-relaxed">{@event.body}</p>
        <% end %>
      <% end %>
    </.timeline_event>
    """
  end

  attr :year, :string, required: true
  attr :title, :string, default: nil
  attr :tags, :list, default: []
  attr :extra_tags, :list, default: []
  attr :tags_string, :string, default: ""
  attr :type, :atom, default: :event

  slot :inner_block, required: true

  def timeline_event(assigns) do
    tags_string =
      if assigns.tags_string == "" do
        Enum.join(assigns.tags, ", ")
      else
        assigns.tags_string
      end

    assigns = assign(assigns, :tags_string, tags_string)

    ~H"""
    <div
      data-timeline-item
      data-tags={@tags_string}
      class="relative group md:pl-16"
      phx-viewport-enter="[[&quot;transition-opacity&quot;, &quot;duration-1000&quot;, &quot;ease-out&quot;],[&quot;transition-transform&quot;, &quot;duration-1000&quot;, &quot;ease-out&quot;]]"
      phx-viewport-enter-start="opacity-0 translate-y-8"
      phx-viewport-enter-end="opacity-100 translate-y-0"
    >
      <div class="hidden md:block absolute left-8 top-2 w-2 h-2 -translate-x-1/2 rounded-full bg-zinc-400 z-10">
      </div>

      <div class="mb-3 md:mb-4">
        <span class="text-2xl md:text-3xl history-serif text-zinc-400 font-medium">
          {@year}
        </span>
      </div>

      <div class="md:pl-4">
        <div
          :if={@tags != [] or @extra_tags != []}
          class="flex flex-wrap gap-2 mb-3"
        >
          <%= for tag <- @extra_tags do %>
            <.timeline_tag label={tag} />
          <% end %>
          <%= for tag <- @tags do %>
            <.timeline_tag label={tag} />
          <% end %>
        </div>

        <h3
          :if={@title}
          class={[
            "text-zinc-900 mb-4 leading-snug",
            if(@type in [:milestone, :featured],
              do: "text-2xl md:text-3xl font-medium history-serif",
              else: "text-xl md:text-2xl font-medium"
            )
          ]}
        >
          {@title}
        </h3>

        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true

  def timeline_tag(assigns) do
    ~H"""
    <span class="px-2.5 py-0.5 text-xs uppercase tracking-wide text-zinc-500 border border-zinc-300 rounded">
      {format_tag(@label)}
    </span>
    """
  end

  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :caption, :string, default: nil
  attr :era, :string, default: nil
  attr :aspect, :string, default: "4/3"

  def archival_photo(assigns) do
    ~H"""
    <figure class={["archival-photo", @era && "era-#{@era}"]}>
      <%!-- img must be a direct child of <a>; GLightboxHook moves caption to a single figcaption --%>
      <a href={@src} class="block cursor-zoom-in">
        <img
          src={@src}
          alt={@alt}
          class={["w-full object-cover rounded", aspect_class(@aspect)]}
          loading="lazy"
          decoding="async"
        />
        <span :if={@caption} class="text-sm text-zinc-500 italic mt-2 block">
          {@caption}
        </span>
      </a>
    </figure>
    """
  end

  attr :presidents, :list, required: true

  def presidents_section(assigns) do
    presidents_by_decade =
      assigns.presidents
      |> Enum.group_by(fn {years, _} ->
        years
        |> String.split("-")
        |> List.first()
        |> String.slice(0, 3)
        |> Kernel.<>("0s")
      end)
      |> Enum.sort_by(fn {decade, _} -> decade end)

    assigns = assign(assigns, :presidents_by_decade, presidents_by_decade)

    ~H"""
    <div class="mb-16 mt-20">
      <div class="prose prose-zinc prose-a:text-blue-600 mb-8 scroll-mt-24">
        <h2 id="presidents">YSC Presidents</h2>
      </div>

      <div class="not-prose">
        <%= for {decade, presidents} <- @presidents_by_decade do %>
          <div
            class="mb-8 scroll-mt-24"
            id={"presidents-#{String.replace(decade, "s", "")}"}
          >
            <h3 class="text-lg font-medium text-zinc-600 mb-4 history-serif">
              {decade}
            </h3>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
              <%= for {years, president} <- presidents do %>
                <.president_card years={years} name={president} />
              <% end %>
              <.next_president_invite_card :if={decade == "2020s"} />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :years, :string, required: true
  attr :name, :string, required: true

  def president_card(assigns) do
    assigns =
      assigns
      |> assign(:badge, president_badge(assigns.years, assigns.name))
      |> assign(:icon, president_icon(assigns.years, assigns.name))

    ~H"""
    <div class="p-4 rounded-xl border border-zinc-200 bg-white flex flex-col items-center text-center relative">
      <div :if={@icon} class="absolute top-2 right-2">
        <.icon name={@icon} class="w-4 h-4 text-zinc-400" />
      </div>
      <span class="text-xs font-medium text-zinc-500 uppercase mb-2 tracking-wide">
        {@years}
      </span>
      <h4 class="font-medium text-zinc-900 text-sm mb-1 leading-tight">
        {@name}
      </h4>
      <span
        :if={@badge}
        class="text-xs px-2 py-0.5 rounded border border-zinc-300 text-zinc-500 mt-1"
      >
        {@badge}
      </span>
    </div>
    """
  end

  def next_president_invite_card(assigns) do
    ~H"""
    <div class="p-4 rounded-xl border-2 border-dashed border-zinc-300 bg-stone-50 flex flex-col items-center text-center justify-center min-h-[8rem]">
      <.icon name="hero-user-plus" class="w-5 h-5 text-zinc-400 mb-2" />
      <span class="text-xs font-medium text-zinc-500 uppercase mb-2 tracking-wide">
        The Next Chapter
      </span>
      <h4 class="font-medium text-zinc-900 text-sm mb-2 leading-tight">
        Could you be our next president?
      </h4>
      <p class="text-xs text-zinc-500 leading-relaxed mb-3">
        Annual board elections are held each year. Passionate members are always welcome to step up and lead.
      </p>
      <.link
        navigate={
          ~p"/contact?subject=Board%20of%20Directors&message=#{URI.encode("Hi, I'm interested in learning more about serving on the YSC Board of Directors—including the president role. I'd love to hear how I can get involved.")}"
        }
        class="text-xs font-medium text-blue-600 hover:text-blue-700 hover:underline"
      >
        Get Involved →
      </.link>
    </div>
    """
  end

  attr :years, :integer, required: true

  def history_cta(assigns) do
    ~H"""
    <div class="not-prose border-y border-zinc-200 py-16 text-center">
      <h3 class="text-3xl md:text-4xl font-medium text-zinc-900 mb-4 history-serif">
        Write the Next Chapter.
      </h3>
      <p class="text-lg text-zinc-600 mb-8 max-w-2xl mx-auto leading-relaxed">
        Our history isn't just about the past—it's about the friendships, traditions, and community that members carry forward for the next {@years} years and beyond.
        <strong class="text-zinc-900">Will you be part of it?</strong>
      </p>
      <div class="flex flex-col sm:flex-row gap-4 justify-center">
        <.link
          navigate={~p"/users/register"}
          class="px-8 py-3 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700 transition-colors duration-150 min-h-[44px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
        >
          Become a Member
        </.link>
        <.link
          navigate={~p"/contact"}
          class="px-8 py-3 text-zinc-700 font-medium rounded-md border border-zinc-300 hover:border-zinc-400 transition-colors duration-150 min-h-[44px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
        >
          Ask a Question
        </.link>
      </div>
    </div>
    """
  end

  def back_to_top(assigns) do
    ~H"""
    <button
      phx-hook="BackToTop"
      id="back-to-top"
      class="fixed bottom-8 right-8 z-20 opacity-0 pointer-events-none transition-opacity duration-300 bg-blue-600 text-white p-3 rounded-full hover:bg-blue-700"
      aria-label="Back to top"
    >
      <.icon name="hero-arrow-up" class="w-6 h-6" />
    </button>
    """
  end

  defp format_tag(tag) do
    tag
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp aspect_class("3/4"), do: "aspect-[3/4]"
  defp aspect_class("4/3"), do: "aspect-[4/3]"
  defp aspect_class(_), do: "aspect-[4/3]"

  defp era_for_year(year) do
    cond do
      String.starts_with?(year, "195") -> "1950s"
      String.starts_with?(year, "196") -> "1960s"
      String.starts_with?(year, "197") -> "1970s"
      String.starts_with?(year, "198") -> "1980s"
      String.starts_with?(year, "199") -> "1990s"
      String.starts_with?(year, "200") -> "2000s"
      String.starts_with?(year, "201") -> "2010s"
      String.starts_with?(year, "202") -> "2020s"
      true -> nil
    end
  end

  defp president_badge(years, name) do
    cond do
      founder?(name) -> "Founder"
      longest_serving?(name) -> "Longest Serving"
      youngest?(name) -> "Youngest"
      clear_lake_purchase?(years, name) -> "Purchased Clear Lake"
      tahoe_purchase?(years) -> "Purchased Tahoe"
      true -> nil
    end
  end

  defp president_icon(years, name) do
    cond do
      founder?(name) -> "hero-star"
      longest_serving?(name) -> "hero-trophy"
      youngest?(name) -> "hero-sparkles"
      clear_lake_purchase?(years, name) -> "hero-home"
      tahoe_purchase?(years) -> "hero-home-modern"
      true -> nil
    end
  end

  defp founder?(name) do
    String.contains?(name, "Arnold Rolkert") or
      String.contains?(name, "Gunnar Engen") or
      String.contains?(name, "Carlo Hojsgaard")
  end

  defp longest_serving?(name), do: String.contains?(name, "Peter Nordström")
  defp youngest?(name), do: String.contains?(name, "Andrew Vik")

  defp clear_lake_purchase?(years, name) do
    String.contains?(name, "Lisa") and String.contains?(years, "1961")
  end

  defp tahoe_purchase?(years), do: String.contains?(years, "1993")
end
