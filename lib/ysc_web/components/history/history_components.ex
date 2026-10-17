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
    <div
      id="history-hero"
      class="max-w-(--breakpoint-xl) mx-auto px-4"
    >
      <div class="lg:grid lg:grid-cols-12 lg:gap-16">
        <div class="lg:col-span-7">
          <.page_masthead
            id="history-masthead"
            eyebrow="History"
            title={"#{@years}+ Years"}
            title_class="tracking-tighter"
          >
            <p class="history-serif text-zinc-500 italic text-sm mt-4 tracking-wide">
              Established 1950
            </p>
            <p class="text-zinc-500 text-xs mt-2 type-eyebrow">
              San Francisco, California
            </p>
          </.page_masthead>

          <div class="max-w-2xl">
            <h2 class="text-2xl md:text-3xl text-zinc-900 mb-6 history-serif type-title">
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

            <blockquote class="border-l-2 border-zinc-300 pl-6 italic text-zinc-600 max-w-xl history-serif mt-8">
              <p class="text-base leading-relaxed">
                Today the YSC remains one of the most active Scandinavian organizations in the Bay Area—offering endless opportunities to enjoy all that Northern California has to offer, and to share American culture with fellow Scandinavians along the way.
              </p>
            </blockquote>
          </div>
        </div>

        <aside class="mt-12 lg:mt-4 lg:col-span-5" aria-label="From the archive">
          <figure
            id="history-hero-photo"
            class="era-1960s mx-auto max-w-md lg:max-w-none"
          >
            <div class="p-3 pb-4 bg-stone-50 border border-zinc-200 shadow-xs rotate-1 motion-safe:transition-transform motion-safe:duration-500 motion-safe:hover:rotate-0">
              <img
                src="/images/history/SAS 1963.webp"
                alt="YSC members on the SAS flight to Scandinavia in 1963"
                width="1024"
                height="825"
                class="w-full h-auto rounded-xs"
                fetchpriority="high"
                decoding="async"
              />
            </div>
            <figcaption class="mt-5 text-center text-sm italic text-zinc-500 history-serif">
              1963 — forty members on the club's legendary group flight back to Scandinavia
            </figcaption>
          </figure>
        </aside>
      </div>
    </div>
    """
  end

  attr :decades, :list,
    required: true,
    doc: "Decade labels (e.g. `\"1960s\"`) in display order, for the jump links"

  def timeline_filters(assigns) do
    ~H"""
    <div
      id="timeline-filters"
      phx-hook="TimelineFilter"
      class="history-toolbar not-prose sticky top-(--nav-height) z-30 -mx-4 mb-10 px-4 border-b border-zinc-200/80 bg-white/80 backdrop-blur-xl backdrop-saturate-150"
    >
      <div class="flex items-center justify-between gap-6 py-3">
        <div
          role="group"
          aria-label="Filter the timeline by category"
          class="flex min-w-0 items-center gap-2 overflow-x-auto no-scrollbar"
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
          <.filter_button
            filter="cabin life"
            label="Cabins"
            icon="hero-home-modern"
          />
          <.filter_button
            filter="anniversary"
            label="Anniversaries"
            icon="hero-cake"
          />
          <.filter_button
            filter="organization"
            label="Organization"
            icon="hero-building-library"
          />
        </div>

        <div class="hidden xl:flex shrink-0 items-center text-sm text-zinc-500">
          <nav aria-label="Jump to a decade" class="flex items-center gap-0.5">
            <a
              :for={decade <- @decades}
              href={"#decade-#{decade}"}
              data-jump={"decade-#{decade}"}
              data-decade-link={decade}
              class="px-2 py-1 rounded-md font-medium transition-colors hover:bg-zinc-100 hover:text-zinc-900 aria-[current=true]:bg-zinc-900 aria-[current=true]:text-white"
            >
              {short_decade(decade)}
            </a>
            <a
              href="#presidents"
              data-jump="presidents"
              class="ml-1 px-2 py-1 rounded-md font-medium text-blue-600 transition-colors hover:bg-blue-50 aria-[current=true]:bg-blue-600 aria-[current=true]:text-white"
            >
              Presidents
            </a>
          </nav>
        </div>
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
      type="button"
      data-filter={@filter}
      data-active={to_string(@active)}
      aria-pressed={to_string(@active)}
      class={[
        "shrink-0 whitespace-nowrap px-3.5 py-1.5 rounded-md text-sm font-medium transition duration-150 active:scale-[0.97]",
        "focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2",
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
    <div
      id="history-timeline"
      class="post-render relative max-w-4xl mx-auto"
      phx-hook="GLightboxHook"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def timeline_decade(assigns) do
    ~H"""
    <section
      id={@id}
      data-decade-section={@label}
      aria-labelledby={"#{@id}-heading"}
      class="mt-16 first:mt-0"
    >
      <h3
        id={"#{@id}-heading"}
        class="mb-6 pl-8 md:pl-0 text-5xl md:text-6xl text-zinc-300 history-serif type-display"
      >
        {@label}
      </h3>
      <div class="relative">
        <div
          aria-hidden="true"
          class="absolute left-3 md:left-[9.5rem] top-0 bottom-0 w-px bg-zinc-200"
        >
        </div>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :event, :map, required: true

  def timeline_event_from_data(assigns) do
    event = assigns.event

    assigns =
      assigns
      |> assign(:era, era_for_year(event.year))
      |> assign(:featured, event.type in [:milestone, :featured])
      |> assign(:compact, compact_event?(event))
      |> assign(:single_image, length(event.images) == 1)

    ~H"""
    <.timeline_event
      year={@event.year}
      title={@event.title}
      tags={@event.tags}
      extra_tags={@event.extra_tags}
      featured={@featured}
      compact={@compact}
    >
      <%= if @event.images != [] do %>
        <div class={[
          "my-5",
          if(@single_image, do: "", else: "grid sm:grid-cols-2 gap-4")
        ]}>
          <%= for image <- @event.images do %>
            <.archival_photo
              src={image.src}
              alt={image.alt}
              caption={image.caption}
              era={image.era || @era}
              aspect={image.aspect || "4/3"}
              document={Map.get(image, :document, false)}
              class={@single_image && single_photo_width(image)}
            />
          <% end %>
        </div>
      <% end %>

      <%= if @event.blockquote do %>
        <blockquote class="border-l-2 border-zinc-300 pl-4 italic text-zinc-600 my-5 history-serif">
          <p>{@event.blockquote}</p>
        </blockquote>
      <% end %>

      <%= if @event.ledger do %>
        <div class="ledger-callout my-5">
          {raw(String.replace(@event.ledger, "\n", "<br />"))}
        </div>
      <% end %>

      <%= if @event.body_html do %>
        <p class="text-zinc-600 leading-relaxed text-pretty">
          {raw(@event.body_html)}
        </p>
      <% else %>
        <%= if @event.body do %>
          <p class={[
            "text-zinc-600 leading-relaxed text-pretty",
            @compact && "text-sm md:text-base"
          ]}>
            {@event.body}
          </p>
        <% end %>
      <% end %>
    </.timeline_event>
    """
  end

  attr :year, :string, required: true
  attr :title, :string, default: nil
  attr :tags, :list, default: []
  attr :extra_tags, :list, default: []

  attr :featured, :boolean,
    default: false,
    doc: "Major milestone: larger node, serif heading and more breathing room"

  attr :compact, :boolean,
    default: false,
    doc: "One-line note: condensed row with a small node"

  slot :inner_block, required: true

  def timeline_event(assigns) do
    assigns = assign(assigns, :tags_string, Enum.join(assigns.tags, ", "))

    ~H"""
    <article
      data-timeline-item
      data-tags={@tags_string}
      class={[
        "relative group pl-8 md:pl-0 md:grid md:grid-cols-[8rem_minmax(0,1fr)] md:gap-x-12",
        cond do
          @featured -> "py-6 md:py-8"
          @compact -> "py-2"
          true -> "py-4 md:py-5"
        end
      ]}
      phx-viewport-enter="[[&quot;transition-opacity&quot;, &quot;duration-1000&quot;, &quot;ease-out&quot;],[&quot;transition-transform&quot;, &quot;duration-1000&quot;, &quot;ease-out&quot;]]"
      phx-viewport-enter-start="opacity-0 translate-y-8"
      phx-viewport-enter-end="opacity-100 translate-y-0"
    >
      <span
        aria-hidden="true"
        class={[
          "absolute z-10 -translate-x-1/2 -translate-y-1/2 rounded-full transition duration-200 motion-safe:group-hover:scale-125",
          "left-3 md:left-[9.5rem]",
          if(@featured,
            do:
              "top-[2.75rem] md:top-[3.25rem] w-3.5 h-3.5 bg-blue-600 ring-4 ring-blue-50",
            else:
              if(@compact,
                do:
                  "top-[1.125rem] w-1.5 h-1.5 bg-zinc-300 group-hover:bg-zinc-500",
                else:
                  "top-[2rem] md:top-[2.25rem] w-2 h-2 bg-zinc-400 group-hover:bg-zinc-600"
              )
          )
        ]}
      ></span>

      <div class="mb-2 md:mb-0 md:text-right">
        <p class={[
          "history-serif whitespace-nowrap",
          cond do
            @featured -> "text-3xl md:text-4xl leading-10 text-zinc-900"
            @compact -> "text-lg leading-6 text-zinc-500"
            true -> "text-xl md:text-2xl leading-8 text-zinc-500"
          end
        ]}>
          {@year}
        </p>
        <div
          :if={@tags != [] or @extra_tags != []}
          class="mt-2 flex flex-wrap gap-1.5 md:flex-col md:items-end"
        >
          <span
            :for={tag <- @extra_tags}
            class="px-2 py-0.5 text-xs rounded-sm border border-amber-200/80 bg-amber-50/70 text-amber-900 type-eyebrow"
          >
            {format_tag(tag)}
          </span>
          <.timeline_tag :for={tag <- @tags} label={tag} />
        </div>
      </div>

      <div class="min-w-0 max-w-2xl">
        <h3
          :if={@title}
          class={[
            "text-zinc-900 type-subhead text-pretty",
            cond do
              @featured -> "mb-4 text-2xl md:text-3xl history-serif"
              @compact -> "mb-1 text-base md:text-lg"
              true -> "mb-3 text-xl md:text-2xl"
            end
          ]}
        >
          {@title}
        </h3>

        {render_slot(@inner_block)}
      </div>
    </article>
    """
  end

  attr :label, :string, required: true

  def timeline_tag(assigns) do
    ~H"""
    <button
      type="button"
      data-filter-trigger={@label}
      aria-label={"Show only #{format_tag(@label)} events"}
      class="px-2 py-0.5 text-xs text-zinc-500 border border-zinc-300 rounded-sm type-eyebrow cursor-pointer transition-colors hover:border-blue-400 hover:text-blue-700 active:scale-[0.97] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-600"
    >
      {format_tag(@label)}
    </button>
    """
  end

  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :caption, :string, default: nil
  attr :era, :string, default: nil
  attr :aspect, :string, default: "4/3"

  attr :document, :boolean,
    default: false,
    doc:
      "Scanned document: shown at its natural proportions on a paper mat so no text is cropped"

  attr :class, :any, default: nil

  def archival_photo(assigns) do
    ~H"""
    <%!-- The GLightboxHook wraps the <a> in its own <figure>, so this wrapper stays a <div>. --%>
    <div class={["archival-photo group/photo", @era && "era-#{@era}", @class]}>
      <%!-- img must be a direct child of <a>; GLightboxHook moves caption to a single figcaption --%>
      <a
        href={@src}
        class={[
          "archival-photo-link block relative cursor-zoom-in overflow-hidden rounded-sm",
          @document && "bg-stone-100/60 border border-zinc-200 p-2"
        ]}
      >
        <img
          src={@src}
          alt={@alt}
          class={[
            "w-full rounded-sm",
            if(@document,
              do: "h-auto object-contain",
              else: [
                "object-cover motion-safe:transition-transform motion-safe:duration-500 motion-safe:group-hover/photo:scale-[1.02]",
                aspect_class(@aspect)
              ]
            )
          ]}
          loading="lazy"
          decoding="async"
        />
        <span :if={@caption} class="text-sm text-zinc-500 italic mt-2 block">
          {@caption}
        </span>
      </a>
    </div>
    """
  end

  attr :presidents, :list, required: true

  def presidents_section(assigns) do
    {entries, _seen} =
      Enum.map_reduce(assigns.presidents, MapSet.new(), fn {years, name},
                                                           seen ->
        {%{years: years, name: name, returning?: MapSet.member?(seen, name)},
         MapSet.put(seen, name)}
      end)

    presidents_by_decade =
      entries
      |> Enum.group_by(fn %{years: years} ->
        years
        |> String.split("-")
        |> List.first()
        |> String.slice(0, 3)
        |> Kernel.<>("0s")
      end)
      |> Enum.sort_by(fn {decade, _} -> decade end)

    assigns = assign(assigns, :presidents_by_decade, presidents_by_decade)

    ~H"""
    <section
      id="presidents"
      aria-labelledby="presidents-heading"
      class="mb-16 mt-20"
    >
      <div class="prose prose-zinc prose-a:text-blue-600 mb-8">
        <h2 id="presidents-heading">YSC Presidents</h2>
      </div>

      <div class="not-prose">
        <%= for {decade, presidents} <- @presidents_by_decade do %>
          <div
            class="mb-8"
            id={"presidents-#{String.replace(decade, "s", "")}"}
          >
            <h3 class="text-lg text-zinc-600 mb-4 history-serif type-subhead">
              {decade}
            </h3>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
              <%= for entry <- presidents do %>
                <.president_card
                  years={entry.years}
                  name={entry.name}
                  returning={entry.returning?}
                />
              <% end %>
              <.next_president_invite_card :if={decade == "2020s"} />
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  attr :years, :string, required: true
  attr :name, :string, required: true

  attr :returning, :boolean,
    default: false,
    doc:
      "True when this person has already appeared as president earlier in the list"

  def president_card(assigns) do
    assigns =
      assigns
      |> assign(
        :badge,
        president_badge(assigns.years, assigns.name, assigns.returning)
      )
      |> assign(:names, String.split(assigns.name, ", "))

    ~H"""
    <div class="p-4 rounded-xl border border-zinc-200 bg-white flex flex-col h-full">
      <span class="text-xs text-zinc-500 mb-2 type-eyebrow">
        {@years}
      </span>
      <h4 class="text-zinc-900 text-sm type-subhead">
        <span :for={name <- @names} class="block">{name}</span>
      </h4>
      <span
        :if={@badge}
        class={[
          "mt-3 self-start inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-sm border",
          badge_tone_class(elem(@badge, 2))
        ]}
      >
        <.icon name={elem(@badge, 1)} class="w-3.5 h-3.5" />
        {elem(@badge, 0)}
      </span>
    </div>
    """
  end

  def next_president_invite_card(assigns) do
    ~H"""
    <div class="p-4 rounded-xl border-2 border-dashed border-zinc-300 bg-stone-50 flex flex-col items-start justify-center min-h-32">
      <.icon name="hero-user-plus" class="w-5 h-5 text-zinc-500 mb-2" />
      <span class="text-xs text-zinc-500 mb-2 type-eyebrow">
        The Next Chapter
      </span>
      <h4 class="text-zinc-900 text-sm mb-2 type-subhead">
        Could you be our next president?
      </h4>
      <p class="text-xs text-zinc-500 leading-relaxed mb-3">
        Annual board elections are held each year. Passionate members are always welcome to step up and lead.
      </p>
      <.link
        navigate={
          ~p"/contact?#{[subject: "Board of Directors", message: "Hi, I'm interested in learning more about serving on the YSC Board of Directors—including the president role. I'd love to hear how I can get involved."]}"
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
          class="px-8 py-3 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700 transition-colors duration-150 min-h-[44px] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
        >
          Apply for Membership
        </.link>
        <.link
          navigate={~p"/contact"}
          class="px-8 py-3 text-zinc-700 font-medium rounded-md border border-zinc-300 hover:border-zinc-400 transition-colors duration-150 min-h-[44px] focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
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

  defp aspect_class("3/4"), do: "aspect-3/4"
  defp aspect_class("4/3"), do: "aspect-4/3"
  defp aspect_class(_), do: "aspect-4/3"

  # A lone portrait scan or document would otherwise stretch to the full column.
  defp single_photo_width(%{aspect: "3/4"}), do: "max-w-sm"
  defp single_photo_width(%{document: true}), do: "max-w-md"
  defp single_photo_width(_image), do: nil

  # Short, picture-less entries (a new dock, a bathroom remodel) get a condensed row.
  defp compact_event?(%{type: :event} = event) do
    event.images == [] and is_nil(event.ledger) and is_nil(event.blockquote) and
      String.length(event.body || "") <= 120
  end

  defp compact_event?(_event), do: false

  defp short_decade(decade), do: "’" <> String.slice(decade, 2, 2) <> "s"

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

  # {label, icon, tone}
  defp president_badge(years, name, returning?) do
    cond do
      founder?(name) and not returning? ->
        {"Founder", "hero-star", :archival}

      longest_serving?(years, name) ->
        {"Longest Serving", "hero-trophy", :archival}

      youngest?(name) ->
        {"Youngest", "hero-sparkles", :archival}

      clear_lake_purchase?(years, name) ->
        {"Purchased Clear Lake", "hero-home", :archival}

      tahoe_purchase?(years) ->
        {"Purchased Tahoe", "hero-home-modern", :archival}

      returning? ->
        {"Returning", "hero-arrow-path", :returning}

      true ->
        nil
    end
  end

  defp badge_tone_class(:archival),
    do: "bg-amber-50/70 text-amber-900 border-amber-200/80"

  defp badge_tone_class(:returning),
    do: "bg-blue-50 text-blue-800 border-blue-200"

  defp founder?(name) do
    String.contains?(name, "Arnold Rolkert") or
      String.contains?(name, "Gunnar Engen") or
      String.contains?(name, "Carlo Hojsgaard")
  end

  defp longest_serving?(years, name) do
    String.contains?(name, "Peter Nordström") and years == "2014-2019"
  end

  defp youngest?(name), do: String.contains?(name, "Andrew Vik")

  defp clear_lake_purchase?(years, name) do
    String.contains?(name, "Lisa") and String.contains?(years, "1961")
  end

  defp tahoe_purchase?(years), do: String.contains?(years, "1993")
end
