defmodule YscWeb.EventBadgeHelpers do
  @moduledoc """
  Shared event badge selection and formatting for cards, heroes, and core badge components.
  """

  alias Ysc.Events.EventHelpers
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
            include_save_the_date && get_field(event, :tickets_tbd)
          )
          |> maybe_append(:just_added, just_added?(published_at))
          |> append_proximity(event, proximity)
          |> maybe_append(:going_fast, selling_fast)
        end
    end
  end

  @doc """
  Returns stacked badge kinds for hero events (multiple badges shown together).
  """
  @spec hero_badge_kinds(map()) :: [badge_kind()]
  def hero_badge_kinds(event) when is_map(event) do
    []
    |> maybe_append(:save_the_date, get_field(event, :tickets_tbd))
    |> maybe_append(:sold_out, EventHelpers.event_sold_out?(event))
    |> maybe_append(:going_fast, get_field(event, :selling_fast))
    |> maybe_append(
      :cancelled,
      get_field(event, :state) in [:cancelled, "cancelled"]
    )
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
  """
  @spec days_until_event_start(map()) :: non_neg_integer() | nil
  def days_until_event_start(event) when is_map(event) do
    start_date = get_field(event, :start_date)

    if start_date == nil do
      nil
    else
      event_date_only = DateTime.to_date(start_date)

      now_date_only =
        DateTime.utc_now()
        |> DateTime.shift_zone!("America/Los_Angeles")
        |> DateTime.to_date()

      case Date.diff(event_date_only, now_date_only) do
        diff when diff >= 0 -> diff
        _ -> nil
      end
    end
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

  defp card_badge(:cancelled),
    do: %{text: "Cancelled", class: "bg-red-500 text-white", icon: nil}

  defp card_badge(:sold_out),
    do: %{text: "Sold Out", class: "bg-red-500 text-white", icon: nil}

  defp card_badge(:save_the_date),
    do: %{
      text: "Save the Date",
      class: "bg-blue-500 text-white",
      icon: "hero-ticket"
    }

  defp card_badge(:just_added),
    do: %{text: "Just Added", class: "bg-zinc-600 text-white", icon: nil}

  defp card_badge(:today),
    do: %{
      text: "Today",
      class: "bg-red-600 text-white animate-pulse",
      icon: "hero-bolt-solid"
    }

  defp card_badge(:tomorrow),
    do: %{text: "Tomorrow", class: "bg-orange-500 text-white", icon: nil}

  defp card_badge({:days_left, days}),
    do: %{
      text: "#{days} days left",
      class: "bg-sky-500 text-white",
      icon: nil
    }

  defp card_badge(:going_fast),
    do: %{
      text: "Going Fast!",
      class: "bg-emerald-600 text-white",
      icon: "hero-bolt-solid"
    }

  defp core_badge(:cancelled), do: {"red", "Cancelled"}
  defp core_badge(:sold_out), do: {"red", "Sold Out"}
  defp core_badge(:just_added), do: {"green", "Just Added"}

  defp core_badge({:days_left, 1}),
    do: {"sky", "1 day left"}

  defp core_badge({:days_left, days}),
    do: {"sky", "#{days} days left"}

  defp core_badge(:going_fast), do: {"yellow", "Going Fast!"}

  defp hero_badge(:save_the_date),
    do: %{text: "Save the Date", icon: "hero-ticket", class: "bg-blue-600"}

  defp hero_badge(:sold_out),
    do: %{text: "Sold Out", icon: "hero-ticket", class: "bg-red-600"}

  defp hero_badge(:going_fast),
    do: %{text: "Going Fast!", icon: "hero-fire", class: "bg-emerald-600"}

  defp hero_badge(:cancelled),
    do: %{text: "Cancelled", icon: "hero-x-circle", class: "bg-zinc-600"}

  defp just_added?(published_at) do
    DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48
  end

  defp maybe_append(acc, kind, true), do: acc ++ [kind]
  defp maybe_append(acc, _kind, _), do: acc

  defp get_field(map, field) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end
end
