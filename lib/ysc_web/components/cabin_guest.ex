defmodule YscWeb.Components.CabinGuest do
  @moduledoc """
  The signed-out face of the cabin booking pages (Tahoe and Clear Lake).

  Guests get a short, inviting overview and a way in, and nothing operational:
  no rates, sleeping setup, directions or house details. Those stay behind
  sign-in so the cabins are only visited by members who have booked.

  Both cabins share one structure so the pages read as a pair: a hero with the
  two ways in (`guest_hero/1`), three highlights (`guest_highlights/1`) and a
  closing invitation (`guest_invite/1`). Each cabin supplies its own photos,
  copy and accent.
  """
  use Phoenix.Component
  use YscWeb, :verified_routes

  import YscWeb.CoreComponents, only: [icon: 1, button: 1]

  @doc """
  Full-bleed hero for signed-out visitors: eyebrow, cabin name, one line about
  the cabin and the two ways in (sign in, or apply for membership).

  The `:media` slot holds the background (a `hero-media-stage` photo or the
  hero carousel). `redirect_to` brings a signed-in member straight back to the
  cabin page.
  """
  attr :id, :string, default: "hero-section"
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :redirect_to, :string, required: true

  slot :media, required: true

  def guest_hero(assigns) do
    ~H"""
    <section
      id={@id}
      class="relative w-full overflow-hidden hero-nav-overlap min-h-[60vh] md:min-h-[75vh] bg-white"
    >
      {render_slot(@media)}
      <div class="absolute bottom-0 left-0 right-0 z-10 px-4 py-10 md:py-20 pointer-events-none">
        <div class="max-w-(--breakpoint-xl) mx-auto pointer-events-auto">
          <p class="text-sm text-zinc-200 mb-3 md:mb-4 drop-shadow-md type-eyebrow">
            {@eyebrow}
          </p>
          <h1 class="text-4xl md:text-7xl text-white drop-shadow-lg mb-4 type-display">
            {@title}
          </h1>
          <p class="text-base md:text-xl text-zinc-100 max-w-2xl font-normal drop-shadow-md">
            {@subtitle}
          </p>
          <div class="mt-6 md:mt-8 flex flex-col sm:flex-row gap-3 sm:gap-4">
            <.link
              id={"#{@id}-sign-in"}
              navigate={~p"/users/log-in?#{%{redirect_to: @redirect_to}}"}
              class="group inline-flex items-center justify-center gap-2 min-h-12 px-8 py-3 text-base font-semibold text-zinc-900 bg-white rounded-sm shadow-lg hover:bg-zinc-100 active:bg-zinc-200 transition-colors duration-200 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-transparent"
            >
              Sign in to book
              <.icon
                name="hero-arrow-right"
                class="w-4 h-4 group-hover:translate-x-1 transition-transform duration-300"
              />
            </.link>
            <.link
              id={"#{@id}-apply"}
              navigate={~p"/users/register"}
              class="inline-flex items-center justify-center min-h-12 px-8 py-3 text-base font-medium text-white border border-white/60 rounded-sm hover:bg-white/10 hover:border-white active:bg-white/20 transition-colors duration-200 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-transparent"
            >
              Apply for membership
            </.link>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Three short highlights in a row, set on the page with no box around them.
  Each `:item` takes a hero `icon` and a short `title`; the slot body is one
  sentence.
  """
  attr :id, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]

  slot :item, required: true do
    attr :icon, :string, required: true
    attr :title, :string, required: true
  end

  def guest_highlights(assigns) do
    ~H"""
    <ul
      id={@id}
      class="grid grid-cols-1 md:grid-cols-3 gap-6 md:gap-10"
    >
      <li :for={item <- @item} class="flex items-start gap-4">
        <span class={[
          "inline-flex size-10 shrink-0 items-center justify-center rounded-full",
          tint(@accent)
        ]}>
          <.icon name={item.icon} class="size-5" />
        </span>
        <div class="min-w-0">
          <h3 class="text-base text-zinc-900 type-subhead">{item.title}</h3>
          <p class="mt-1 text-sm text-zinc-600 leading-relaxed">
            {render_slot(item)}
          </p>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Closing invitation under the sections: the same two ways in as the hero, with
  signing in as the main action and applying as a quiet link beside it.
  """
  attr :id, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]
  attr :redirect_to, :string, required: true

  def guest_invite(assigns) do
    ~H"""
    <div class="border-t border-zinc-200 pt-10 md:pt-14">
      <section id={@id} class="max-w-2xl mx-auto text-center">
        <p class={["text-xs mb-3 type-eyebrow", eyebrow_text(@accent)]}>
          Members only
        </p>
        <h2 class="text-2xl md:text-3xl text-zinc-900 type-title">
          Ready to book?
        </h2>
        <p class="mt-3 text-base text-zinc-600 leading-relaxed">
          Sign in to check availability and book your dates, or apply to join the club.
        </p>
        <div class="mt-6 flex flex-col sm:flex-row items-stretch sm:items-center justify-center gap-3">
          <.button
            id={"#{@id}-sign-in"}
            navigate={~p"/users/log-in?#{%{redirect_to: @redirect_to}}"}
            color={Atom.to_string(@accent)}
            class="px-8 py-3"
          >
            Sign in to book
          </.button>
          <.link
            id={"#{@id}-apply"}
            navigate={~p"/users/register"}
            class={[
              "inline-flex items-center justify-center gap-1 min-h-11 px-4 text-sm font-semibold hover:underline",
              link_text(@accent)
            ]}
          >
            Apply for membership <.icon name="hero-arrow-right" class="w-4 h-4" />
          </.link>
        </div>
      </section>
    </div>
    """
  end

  @doc "Formats a money label for guest copy: `$45.00` becomes `$45`."
  def whole_dollars(label) when is_binary(label),
    do: String.replace_suffix(label, ".00", "")

  @doc """
  The cabin's stay types side by side (rooms or shared cabin, and the entire
  cabin), each with its price, when it is offered and how long a stay can be.
  `options` is `Ysc.Bookings.CabinOverview.t()`'s `:stay_options`, so rates,
  seasons and night limits follow the live booking and pricing rules.
  """
  attr :id, :string, default: nil
  attr :property, :atom, required: true, values: [:tahoe, :clear_lake]
  attr :accent, :atom, default: :blue, values: [:blue, :teal]
  attr :options, :list, required: true

  def guest_stay_options(assigns) do
    ~H"""
    <ul
      id={@id}
      class="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6"
    >
      <li
        :for={option <- @options}
        id={@id && "#{@id}-#{option.mode}"}
        class="flex flex-col gap-4 rounded-xl border border-zinc-200 bg-zinc-50 p-5 md:p-6"
      >
        <div>
          <h3 class="text-lg text-zinc-900 type-subhead">{option.label}</h3>
          <p class="mt-1 text-sm text-zinc-600 leading-relaxed">
            {blurb(@property, option.mode)}
          </p>
        </div>
        <div :if={option.rate}>
          <p class="text-xs text-zinc-500 type-eyebrow">From</p>
          <p class="text-2xl font-bold text-zinc-900 tabular-nums">
            {format_rate(option.rate)}
            <span class="text-sm font-normal text-zinc-500">
              {rate_unit(@property, option.mode)}
            </span>
          </p>
          <p
            :if={
              @property == :tahoe && option.mode == :room && option.children_rate
            }
            class="mt-1 text-sm text-zinc-600"
          >
            Ages 5–17 from {format_rate(option.children_rate)} · under 5 free
          </p>
        </div>
        <ul class="mt-auto space-y-2 pt-2 text-sm text-zinc-600">
          <li class="flex items-start gap-2.5">
            <.icon
              name="hero-calendar-days"
              class={["w-4 h-4 shrink-0 mt-0.5", icon_tone(@accent)]}
            />
            <span>{availability(option)}</span>
          </li>
          <li class="flex items-start gap-2.5">
            <.icon
              name="hero-moon"
              class={["w-4 h-4 shrink-0 mt-0.5", icon_tone(@accent)]}
            />
            <span>{night_limit(option)}</span>
          </li>
        </ul>
      </li>
    </ul>
    """
  end

  @doc """
  A few dated milestones from the club's own history, with a link to the full
  timeline. `milestones` is `Ysc.Bookings.CabinOverview.t()`'s `:history`.
  """
  attr :id, :string, default: nil
  attr :accent, :atom, default: :blue, values: [:blue, :teal]
  attr :milestones, :list, required: true

  def guest_milestones(assigns) do
    ~H"""
    <div>
      <ol id={@id} class="divide-y divide-zinc-200">
        <li
          :for={milestone <- @milestones}
          class="grid grid-cols-[4rem_1fr] gap-4 py-5 first:pt-0 md:grid-cols-[5rem_1fr]"
        >
          <span class={["text-sm font-semibold tabular-nums", link_text(@accent)]}>
            {milestone.year}
          </span>
          <div class="min-w-0">
            <h3 class="text-base text-zinc-900 type-subhead">
              {milestone.headline}
            </h3>
            <p class="mt-1 text-sm text-zinc-600 leading-relaxed">
              {milestone.summary}
            </p>
          </div>
        </li>
      </ol>
      <.link
        navigate={~p"/history"}
        class={[
          "mt-4 inline-flex items-center gap-1 min-h-11 text-sm font-semibold hover:underline",
          link_text(@accent)
        ]}
      >
        Read the full club history <.icon name="hero-arrow-right" class="w-4 h-4" />
      </.link>
    </div>
    """
  end

  @doc """
  Short description line for the history section, e.g. `"Owned by our members
  for 33 years."`, or `nil` when the acquisition year is unknown.
  """
  def owned_for_label(%{years_owned: years}) when is_integer(years),
    do: "Owned and looked after by our members for #{years} years."

  def owned_for_label(_overview), do: nil

  @doc """
  The month span of the named season (e.g. `"May–October"`), or `"see the
  booking calendar"` when that season is not configured.
  """
  def season_span(%{seasons: seasons}, name) do
    case Enum.find(seasons, &(&1.name == name)) do
      %{span: span} when span != "" -> span
      _ -> "see the booking calendar"
    end
  end

  defp format_rate(%Money{} = money),
    do: money |> Ysc.MoneyHelper.format_money!() |> whole_dollars()

  defp rate_unit(:tahoe, :room), do: "per adult, per night"
  defp rate_unit(_property, :day), do: "per guest, per night"
  defp rate_unit(_property, :buyout), do: "per night, whole cabin"

  defp blurb(:tahoe, :room),
    do:
      "Book one or more bedrooms and share the cabin with other members. Smaller groups are welcome."

  defp blurb(:tahoe, :buyout),
    do:
      "The whole cabin for your group alone: every bedroom, the bathrooms and the sauna."

  defp blurb(:clear_lake, :day),
    do:
      "Book space for your group. Other members may stay at the cabin on the same dates."

  defp blurb(:clear_lake, :buyout),
    do: "Exclusive use of the whole property. Great for large families."

  defp availability(%{year_round?: true}), do: "Offered year-round"

  defp availability(%{seasons: seasons}) do
    "Offered in " <>
      Enum.map_join(
        seasons,
        " and ",
        &"#{String.downcase(&1.name)} (#{&1.span})"
      )
  end

  defp night_limit(%{min_nights: nights, max_nights: nights}),
    do: "Up to #{nights} nights per stay"

  defp night_limit(%{min_nights: min, max_nights: max}),
    do: "Up to #{min}–#{max} nights per stay, depending on the season"

  defp tint(:blue), do: "bg-blue-50 text-blue-700"
  defp tint(:teal), do: "bg-teal-50 text-teal-700"

  defp icon_tone(:blue), do: "text-blue-600"
  defp icon_tone(:teal), do: "text-teal-600"

  defp link_text(:blue), do: "text-blue-700"
  defp link_text(:teal), do: "text-teal-700"

  defp eyebrow_text(:blue), do: "text-blue-600"
  defp eyebrow_text(:teal), do: "text-teal-600"
end
