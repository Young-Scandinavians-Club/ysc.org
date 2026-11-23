defmodule YscWeb.EventBadgeHelpers do
  @moduledoc """
  Shared event badge selection and formatting for cards, heroes, and core badge components.
  """

  alias Ysc.Events.EventHelpers
  alias Ysc.Tickets.Display, as: TicketDisplay
  alias YscWeb.DateDisplay

  @type badge_kind ::
          :cancelled
          | :sold_out
          | :save_the_date
          | :just_added
          | :today
          | :tomorrow
          | {:days_left, pos_integer()}
          | :going_fast
          | :almost_full

  @doc """
  Returns badge kinds when only one status group should show (cancelled and sold out
  suppress marketing/proximity badges).
  """
  @spec exclusive_badge_kinds(map(), keyword()) :: [badge_kind()]
  def exclusive_badge_kinds(event, opts \\ []) when is_map(event) do
    sold_out = Keyword.get(opts, :sold_out, false)
    selling_fast = Keyword.get(opts, :selling_fast, false)
    proximity = Keyword.get(opts, :proximity, :labels)
    include_save_the_date = Keyword.get(opts, :include_save_the_date, true)
    state = get_field(event, :state)

    cond do
      state in [:cancelled, "cancelled"] ->
        [:cancelled]

      sold_out ->
        [:sold_out]

      true ->
        published_at = get_field(event, :published_at)

        if published_at == nil do
          []
        else
          []
          |> maybe_append(
            :save_the_date,
            include_save_the_date && Ysc.Events.Event.tickets_tbd?(event)
          )
          |> maybe_append(:just_added, just_added?(published_at))
          |> append_proximity(event, proximity)
          |> append_kind(demand_badge_kind(event, selling_fast))
        end
    end
  end

  @doc """
  Returns stacked badge kinds for hero events (multiple badges shown together).
  """
  @spec hero_badge_kinds(map()) :: [badge_kind()]
  def hero_badge_kinds(event) when is_map(event) do
    sold_out = EventHelpers.event_sold_out?(event)

    []
    |> maybe_append(:save_the_date, Ysc.Events.Event.tickets_tbd?(event))
    |> maybe_append(:sold_out, sold_out)
    |> append_kind(
      if(sold_out,
        do: nil,
        else: demand_badge_kind(event, get_field(event, :selling_fast))
      )
    )
    |> maybe_append(
      :cancelled,
      get_field(event, :state) in [:cancelled, "cancelled"]
    )
  end

  @doc """
  Which demand badge an event earns, if any: `:almost_full` once it is 85%+
  full, `:going_fast` when it is selling fast, otherwise `nil`.

  Decided by the same `TicketDisplay.demand_indicator/3` as the event page's
  demand card, so a label never shows on one surface and not the other.
  Capacity comes from the list row's `max_attendees` and `ticket_count`;
  without them this degrades to the plain selling-fast badge.
  """
  @spec demand_badge_kind(map(), boolean() | nil) ::
          :going_fast | :almost_full | nil
  def demand_badge_kind(event, selling_fast) when is_map(event) do
    percentage =
      TicketDisplay.sold_percentage(
        get_field(event, :max_attendees),
        get_field(event, :ticket_count)
      )

    case TicketDisplay.demand_indicator(selling_fast == true, percentage, nil) do
      %{level: :scarce} -> :almost_full
      %{} -> :going_fast
      nil -> nil
    end
  end

  @doc """
  Formats badge kinds as maps for `EventCard` (`%{text:, class:, icon:}`).
  """
  @spec to_card_badges([badge_kind()]) :: [
          %{text: String.t(), class: String.t(), icon: String.t() | nil}
        ]
  def to_card_badges(kinds), do: Enum.map(kinds, &card_badge/1)

  @doc """
  Formats badge kinds as `{type, text}` tuples for `<.badge>`.
  """
  @spec to_core_badges([badge_kind()]) :: [{String.t(), String.t()}]
  def to_core_badges(kinds), do: Enum.map(kinds, &core_badge/1)

  @doc """
  Formats badge kinds as maps for hero list display.
  """
  @spec to_hero_badges([badge_kind()]) :: [
          %{text: String.t(), class: String.t(), icon: String.t()}
        ]
  def to_hero_badges(kinds), do: Enum.map(kinds, &hero_badge/1)

  @doc """
  Returns the number of Pacific calendar days until an event's start date, or `nil`.

  Events are hosted in California. "Today" is always Pacific, and stored
  event dates are not timezone-shifted.
  """
  @spec days_until_event_start(map()) :: non_neg_integer() | nil
  def days_until_event_start(event) when is_map(event) do
    DateDisplay.days_until_event(event)
  end

  defp append_proximity(acc, event, :labels) do
    case DateDisplay.event_day_label(event) do
      :today ->
        acc ++ [:today]

      :tomorrow ->
        acc ++ [:tomorrow]

      _ ->
        case days_until_event_start(event) do
          days when days in [2, 3] -> acc ++ [{:days_left, days}]
          _ -> acc
        end
    end
  end

  defp append_proximity(acc, event, :days_only) do
    case days_until_event_start(event) do
      days when days in 1..3 -> acc ++ [{:days_left, days}]
      _ -> acc
    end
  end

  # Canonical color + icon per badge kind. Every kind gets its own color so a
  # label reads the same way everywhere it appears (card, hero, TV poster).
  @badge_styles %{
    cancelled: {"bg-zinc-700", "hero-x-circle-solid"},
    sold_out: {"bg-red-600", "hero-no-symbol"},
    save_the_date: {"bg-blue-600", "hero-ticket"},
    just_added: {"bg-violet-600", "hero-sparkles-solid"},
    today: {"bg-rose-600 animate-attention-once", "hero-bolt-solid"},
    tomorrow: {"bg-orange-600", "hero-calendar-solid"},
    days_left: {"bg-sky-600", "hero-clock"},
    going_fast: {"bg-emerald-600", "hero-fire-solid"},
    almost_full: {"bg-amber-700", "hero-users-solid"}
  }

  defp badge_style(:cancelled), do: Map.fetch!(@badge_styles, :cancelled)
  defp badge_style(:sold_out), do: Map.fetch!(@badge_styles, :sold_out)

  defp badge_style(:save_the_date),
    do: Map.fetch!(@badge_styles, :save_the_date)

  defp badge_style(:just_added), do: Map.fetch!(@badge_styles, :just_added)
  defp badge_style(:today), do: Map.fetch!(@badge_styles, :today)
  defp badge_style(:tomorrow), do: Map.fetch!(@badge_styles, :tomorrow)
  defp badge_style({:days_left, _}), do: Map.fetch!(@badge_styles, :days_left)
  defp badge_style(:going_fast), do: Map.fetch!(@badge_styles, :going_fast)
  defp badge_style(:almost_full), do: Map.fetch!(@badge_styles, :almost_full)

  defp card_badge(:cancelled),
    do: card_badge_from_style(:cancelled, "Cancelled")

  defp card_badge(:sold_out), do: card_badge_from_style(:sold_out, "Sold Out")

  defp card_badge(:save_the_date),
    do: card_badge_from_style(:save_the_date, "Save the Date")

  defp card_badge(:just_added),
    do: card_badge_from_style(:just_added, "Just Added")

  defp card_badge(:today), do: card_badge_from_style(:today, "Today")
  defp card_badge(:tomorrow), do: card_badge_from_style(:tomorrow, "Tomorrow")

  defp card_badge({:days_left, days} = kind),
    do: card_badge_from_style(kind, "#{days} days left")

  defp card_badge(:going_fast),
    do: card_badge_from_style(:going_fast, "Going Fast!")

  defp card_badge(:almost_full),
    do: card_badge_from_style(:almost_full, "Almost Full")

  defp card_badge_from_style(kind, text) do
    {bg_class, icon} = badge_style(kind)
    %{text: text, class: "#{bg_class} text-white", icon: icon}
  end

  defp core_badge(:cancelled), do: {"red", "Cancelled"}
  defp core_badge(:sold_out), do: {"red", "Sold Out"}
  defp core_badge(:just_added), do: {"green", "Just Added"}

  defp core_badge({:days_left, 1}),
    do: {"sky", "1 day left"}

  defp core_badge({:days_left, days}),
    do: {"sky", "#{days} days left"}

  defp core_badge(:going_fast), do: {"yellow", "Going Fast!"}
  defp core_badge(:almost_full), do: {"orange", "Almost Full"}

  defp hero_badge(:save_the_date),
    do: hero_badge_from_style(:save_the_date, "Save the Date")

  defp hero_badge(:sold_out), do: hero_badge_from_style(:sold_out, "Sold Out")

  defp hero_badge(:going_fast),
    do: hero_badge_from_style(:going_fast, "Going Fast!")

  defp hero_badge(:almost_full),
    do: hero_badge_from_style(:almost_full, "Almost Full")

  defp hero_badge(:cancelled),
    do: hero_badge_from_style(:cancelled, "Cancelled")

  defp hero_badge_from_style(kind, text) do
    {bg_class, icon} = badge_style(kind)
    %{text: text, icon: icon, class: bg_class}
  end

  defp just_added?(published_at) do
    DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48
  end

  defp append_kind(acc, nil), do: acc
  defp append_kind(acc, kind), do: acc ++ [kind]

  defp maybe_append(acc, kind, true), do: acc ++ [kind]
  defp maybe_append(acc, _kind, _), do: acc

  defp get_field(map, field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end
end
