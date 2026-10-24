defmodule Ysc.Bookings.CabinOverview do
  @moduledoc """
  Public, signed-out overview of a cabin, built from the live booking and
  pricing rules so the guest pages never drift from what the booking pages
  charge or allow.

  It answers the questions a prospective member asks: how long has the club
  owned the cabin, what can I book, when, for how long and roughly what does it
  cost. It deliberately carries nothing operational (address, access, house
  details); those stay behind sign-in.

  Rates and seasons come from the cached `PricingRule` and `Season` lookups, and
  history years come from `Ysc.History.Timeline`, so editing either changes the
  public pages without a code change.
  """

  alias Ysc.Bookings.BookingModeDisplay
  alias Ysc.Bookings.PricingRule
  alias Ysc.Bookings.PricingRuleCache
  alias Ysc.Bookings.Season
  alias Ysc.History.Timeline

  @type property :: :tahoe | :clear_lake

  @type season_window :: %{name: String.t(), span: String.t()}

  @type stay_option :: %{
          mode: :room | :day | :buyout,
          label: String.t(),
          rate: Money.t() | nil,
          children_rate: Money.t() | nil,
          seasons: [season_window()],
          year_round?: boolean(),
          min_nights: pos_integer(),
          max_nights: pos_integer()
        }

  @type milestone :: %{
          year: String.t(),
          headline: String.t(),
          summary: String.t()
        }

  @type t :: %{
          property: property(),
          years_owned: non_neg_integer() | nil,
          history: [milestone()],
          seasons: [season_window()],
          stay_options: [stay_option()]
        }

  # {mode, price unit} for each bookable stay type, in the order a guest sees them.
  @stay_modes %{
    tahoe: [{:room, :per_person_per_night}, {:buyout, :buyout_fixed}],
    clear_lake: [{:day, :per_guest_per_day}, {:buyout, :buyout_fixed}]
  }

  # Curated milestones. `match` is the `{year, title}` of the club timeline
  # entry each one is drawn from; the year shown is read from that entry, and a
  # milestone whose entry is later renamed or removed simply drops out. The
  # first milestone is the acquisition and drives `years_owned`.
  @milestones %{
    tahoe: [
      %{
        match: {"1993", "Tahoe Cabin Purchase"},
        headline: "The club buys a cabin of its own",
        summary:
          "After years of renting winter cabins in the Sierra, members raised over $75,000 to buy the Tahoe cabin."
      },
      %{
        match: {"2004", "Tahoe Cabin Mortgage Paid Off"},
        headline: "Paid off, years early",
        summary:
          "The mortgage was cleared more than four years ahead of schedule, leaving both cabins owned debt-free."
      },
      %{
        match: {"2014", "Sauna in Tahoe"},
        headline: "A sauna, built by members",
        summary:
          "A member fundraising drive built the John Rollings Memorial Sauna."
      }
    ],
    clear_lake: [
      %{
        match: {"1963", "The Clear Lake Acquisition"},
        headline: "The club's first permanent home",
        summary:
          "After renting here through the 1950s, the club acquired the Clear Lake property."
      },
      %{
        match: {"1974", "Clear Lake Paid Off"},
        headline: "Paid off and ours",
        summary:
          "The loan was cleared, and the cabin and its three-quarter-acre lot belong to the members."
      },
      %{
        match: {"1986", "Executive Committee"},
        headline: "A dock built to last",
        summary:
          "New floating docks on steel pilings and a rebuilt sea wall, all member-led."
      }
    ]
  }

  @doc """
  Builds the overview for `property` from the given `seasons` (as loaded by the
  booking page) and the current pricing rules.
  """
  @spec for_property(property(), [struct()]) :: t()
  def for_property(property, seasons)
      when property in [:tahoe, :clear_lake] and is_list(seasons) do
    history = history(property)

    %{
      property: property,
      years_owned: years_owned(history),
      history: history,
      seasons: Enum.map(sorted_seasons(seasons), &season_window/1),
      stay_options:
        property
        |> stay_modes()
        |> Enum.map(fn {mode, unit} ->
          stay_option(property, mode, unit, seasons)
        end)
        |> Enum.reject(&is_nil/1)
    }
  end

  defp stay_modes(property), do: Map.fetch!(@stay_modes, property)

  # ---------------------------------------------------------------------------
  # History
  # ---------------------------------------------------------------------------

  defp history(property) do
    events = Timeline.events()

    @milestones
    |> Map.fetch!(property)
    |> Enum.flat_map(fn %{match: {year, title}} = milestone ->
      case Enum.find(events, &(&1.year == year and &1.title == title)) do
        nil ->
          []

        event ->
          [
            %{
              year: event.year,
              headline: milestone.headline,
              summary: milestone.summary
            }
          ]
      end
    end)
  end

  defp years_owned([%{year: year} | _]) do
    case Integer.parse(year) do
      {start, _} -> max(Date.utc_today().year - start, 0)
      :error -> nil
    end
  end

  defp years_owned([]), do: nil

  # ---------------------------------------------------------------------------
  # Seasons
  # ---------------------------------------------------------------------------

  defp sorted_seasons(seasons) do
    Enum.sort_by(seasons, fn season ->
      {season.start_date.month, season.start_date.day}
    end)
  end

  defp season_window(season) do
    %{name: season.name, span: season_span(season)}
  end

  defp season_span(%{start_date: start_date, end_date: end_date})
       when not is_nil(start_date) and not is_nil(end_date) do
    "#{Calendar.strftime(start_date, "%B")}–#{Calendar.strftime(end_date, "%B")}"
  end

  defp season_span(_), do: ""

  # ---------------------------------------------------------------------------
  # Stay options (booking types, rates and availability)
  # ---------------------------------------------------------------------------

  defp stay_option(property, mode, unit, seasons) do
    scopes = if seasons == [], do: [nil], else: sorted_seasons(seasons)

    available =
      Enum.filter(scopes, &offered?(property, mode, unit, &1))

    case available do
      [] ->
        nil

      _ ->
        windows =
          available |> Enum.reject(&is_nil/1) |> Enum.map(&season_window/1)

        nights = Enum.map(available, &max_nights(&1, property))

        %{
          mode: mode,
          label: BookingModeDisplay.stay_type_label(mode),
          rate: rate(property, mode, unit, available),
          children_rate: children_rate(property, mode, unit, available),
          seasons: windows,
          year_round?: length(available) == length(scopes),
          min_nights: Enum.min(nights),
          max_nights: Enum.max(nights)
        }
    end
  end

  # A stay type is offered in a season when a pricing rule covers it there. At
  # Tahoe the entire cabin is also never offered in the winter season (rooms
  # only), mirroring `Season.buyout_allowed_on_date?/2`.
  defp offered?(property, mode, unit, season) do
    pricing_rule(property, mode, unit, season) != nil and
      buyout_allowed?(property, mode, season)
  end

  defp buyout_allowed?(:tahoe, :buyout, %Season{} = season),
    do: Season.buyout_allowed_on_date?([season], season.start_date)

  defp buyout_allowed?(_property, _mode, _season), do: true

  defp pricing_rule(property, mode, unit, season) do
    PricingRule.find_most_specific(
      property,
      season_id(season),
      nil,
      nil,
      mode,
      unit
    )
  end

  # Per-person stays use the same "from" rate as the public home page; the
  # entire cabin is a fixed nightly price, so its "from" is the cheapest season.
  defp rate(property, mode, _unit, _available) when mode in [:room, :day] do
    PricingRuleCache.lowest_property_rate(property)
  end

  defp rate(property, mode, unit, available) do
    available
    |> Enum.flat_map(fn season ->
      case pricing_rule(property, mode, unit, season) do
        %{amount: %Money{} = amount} -> [amount]
        _ -> []
      end
    end)
    |> min_money()
  end

  defp children_rate(property, :room, unit, available) do
    available
    |> Enum.flat_map(fn season ->
      case PricingRule.find_children_pricing_rule(
             property,
             season_id(season),
             nil,
             nil,
             :room,
             unit
           ) do
        %{children_amount: %Money{} = amount} -> [amount]
        _ -> []
      end
    end)
    |> min_money()
  end

  defp children_rate(_property, _mode, _unit, _available), do: nil

  defp min_money([]), do: nil

  defp min_money(amounts),
    do: Enum.min_by(amounts, &Money.to_decimal/1, Decimal)

  defp max_nights(season, property),
    do: Season.get_max_nights(season, property)

  defp season_id(%Season{id: id}), do: id
  defp season_id(nil), do: nil
end
