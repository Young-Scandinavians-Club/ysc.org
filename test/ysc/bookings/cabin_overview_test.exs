defmodule Ysc.Bookings.CabinOverviewTest do
  @moduledoc """
  The signed-out cabin overview must follow the live pricing rules and
  seasons, never a copy of them.
  """
  # Pricing and season caches are process-wide.
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  import Ysc.BookingsFixtures

  alias Ysc.Bookings.{
    CabinOverview,
    PricingRule,
    PricingRuleCache,
    Room,
    Season
  }

  alias Ysc.Repo

  setup do
    seed_canonical_seasons!()
    Repo.delete_all(PricingRule)
    PricingRuleCache.invalidate()
    :ok
  end

  defp seasons(property), do: Season.list_all_for_property_db(property)

  defp season(property, name),
    do: Enum.find(seasons(property), &(&1.name == name))

  defp create_rule(attrs) do
    {:ok, rule} =
      %PricingRule{}
      |> PricingRule.changeset(attrs)
      |> Repo.insert()

    PricingRuleCache.invalidate()
    rule
  end

  defp tahoe_rules do
    create_rule(%{
      property: :tahoe,
      booking_mode: :room,
      price_unit: :per_person_per_night,
      amount: Money.new(45, :USD),
      children_amount: Money.new(25, :USD)
    })

    create_rule(%{
      property: :tahoe,
      booking_mode: :buyout,
      price_unit: :buyout_fixed,
      amount: Money.new(425, :USD),
      season_id: season(:tahoe, "Summer").id
    })
  end

  defp option(overview, mode),
    do: Enum.find(overview.stay_options, &(&1.mode == mode))

  describe "for_property/2 at Tahoe" do
    test "offers rooms year-round and the entire cabin only outside winter" do
      tahoe_rules()
      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))

      assert Enum.map(overview.stay_options, & &1.mode) == [:room, :buyout]

      room = option(overview, :room)
      assert room.label == "Individual room(s)"
      assert room.rate == Money.new(45, :USD)
      assert room.children_rate == Money.new(25, :USD)
      assert room.year_round?
      assert room.max_nights == 4

      buyout = option(overview, :buyout)
      assert buyout.label == "Entire cabin"
      assert buyout.rate == Money.new(425, :USD)
      refute buyout.year_round?
      assert [%{name: "Summer", span: "May–October"}] = buyout.seasons
    end

    test "follows pricing rule changes" do
      rule =
        create_rule(%{
          property: :tahoe,
          booking_mode: :room,
          price_unit: :per_person_per_night,
          amount: Money.new(45, :USD)
        })

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))
      assert option(overview, :room).rate == Money.new(45, :USD)

      {:ok, _} =
        rule
        |> PricingRule.changeset(%{amount: Money.new(60, :USD)})
        |> Repo.update()

      PricingRuleCache.invalidate()

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))
      assert option(overview, :room).rate == Money.new(60, :USD)
    end

    test "ignores cheaper room-specific rules for the public from rate" do
      tahoe_rules()

      {:ok, room} =
        %Room{}
        |> Room.changeset(%{
          name: "Overlook",
          property: :tahoe,
          capacity_max: 2,
          is_active: true
        })
        |> Repo.insert()

      create_rule(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        amount: Money.new(10, :USD),
        room_id: room.id
      })

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))
      assert option(overview, :room).rate == Money.new(45, :USD)
    end

    test "season-specific buyout beats a cheaper year-round rule" do
      # Tahoe buyout is summer-only. A cheaper year-round row must not become
      # the public "from" rate — guests actually pay the summer-specific amount.
      create_rule(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        amount: Money.new(45, :USD)
      })

      create_rule(%{
        property: :tahoe,
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        amount: Money.new(300, :USD)
      })

      create_rule(%{
        property: :tahoe,
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        amount: Money.new(425, :USD),
        season_id: season(:tahoe, "Summer").id
      })

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))
      buyout = option(overview, :buyout)

      assert buyout.rate == Money.new(425, :USD)
      refute buyout.year_round?
      assert [%{name: "Summer", span: "May–October"}] = buyout.seasons
    end

    test "season-specific children rate beats year-round for the from price" do
      create_rule(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        amount: Money.new(45, :USD),
        children_amount: Money.new(25, :USD)
      })

      create_rule(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        amount: Money.new(45, :USD),
        children_amount: Money.new(10, :USD),
        season_id: season(:tahoe, "Summer").id
      })

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))
      assert option(overview, :room).children_rate == Money.new(10, :USD)
    end

    test "omits a stay type with no pricing rule" do
      create_rule(%{
        property: :tahoe,
        booking_mode: :room,
        price_unit: :per_person_per_night,
        amount: Money.new(45, :USD)
      })

      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))

      assert Enum.map(overview.stay_options, & &1.mode) == [:room]
    end

    test "reports the night limit per season" do
      tahoe_rules()
      summer = season(:tahoe, "Summer")

      {:ok, _} =
        summer
        |> Season.changeset(%{max_nights: 6})
        |> Repo.update()

      Ysc.Bookings.SeasonCache.invalidate()

      room =
        :tahoe
        |> CabinOverview.for_property(seasons(:tahoe))
        |> option(:room)

      assert room.min_nights == 4
      assert room.max_nights == 6
    end
  end

  describe "for_property/2 at Clear Lake" do
    test "offers shared and entire-cabin stays in every season" do
      create_rule(%{
        property: :clear_lake,
        booking_mode: :day,
        price_unit: :per_guest_per_day,
        amount: Money.new(50, :USD)
      })

      create_rule(%{
        property: :clear_lake,
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        amount: Money.new(500, :USD)
      })

      overview = CabinOverview.for_property(:clear_lake, seasons(:clear_lake))

      assert Enum.map(overview.stay_options, & &1.mode) == [:day, :buyout]

      day = option(overview, :day)
      assert day.label == "Shared cabin"
      assert day.rate == Money.new(50, :USD)
      assert day.year_round?
      assert day.max_nights == 30

      buyout = option(overview, :buyout)
      assert buyout.rate == Money.new(500, :USD)
      assert buyout.year_round?

      assert [
               %{name: "Summer", span: "May–October"},
               %{name: "Winter", span: "November–April"}
             ] = overview.seasons
    end
  end

  describe "query load" do
    @pricing_rules_query ~r/FROM "pricing_rules"/i

    test "cold overview loads property-level rules in one query" do
      tahoe_rules()
      PricingRuleCache.invalidate()
      property_seasons = seasons(:tahoe)

      {overview, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> CabinOverview.for_property(:tahoe, property_seasons) end,
          pattern: @pricing_rules_query,
          caller_pids: [self()]
        )

      assert query_count == 1
      assert option(overview, :room).rate == Money.new(45, :USD)
      assert option(overview, :buyout).rate == Money.new(425, :USD)
    end

    test "warm overview does not query pricing_rules" do
      tahoe_rules()
      property_seasons = seasons(:tahoe)
      CabinOverview.for_property(:tahoe, property_seasons)

      {_overview, query_count} =
        Ysc.QueryCounter.with_query_counter(
          fn -> CabinOverview.for_property(:tahoe, property_seasons) end,
          pattern: @pricing_rules_query,
          caller_pids: [self()]
        )

      assert query_count == 0
    end

    test "without process caches still uses one query per overview" do
      tahoe_rules()
      property_seasons = seasons(:tahoe)
      previous = Application.get_env(:ysc, :process_caches_enabled)

      Application.put_env(:ysc, :process_caches_enabled, false)

      try do
        {_overview, query_count} =
          Ysc.QueryCounter.with_query_counter(
            fn -> CabinOverview.for_property(:tahoe, property_seasons) end,
            pattern: @pricing_rules_query,
            caller_pids: [self()]
          )

        assert query_count == 1
      after
        Application.put_env(:ysc, :process_caches_enabled, previous)
      end
    end
  end

  describe "history" do
    test "dates the milestones from the club timeline" do
      overview = CabinOverview.for_property(:tahoe, seasons(:tahoe))

      assert Enum.map(overview.history, & &1.year) == ["1993", "2004", "2014"]
      assert overview.years_owned == Date.utc_today().year - 1993

      overview = CabinOverview.for_property(:clear_lake, seasons(:clear_lake))

      assert hd(overview.history).year == "1963"
      assert overview.years_owned == Date.utc_today().year - 1963
    end
  end
end
