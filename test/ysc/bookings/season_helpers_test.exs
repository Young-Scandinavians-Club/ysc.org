defmodule Ysc.Bookings.SeasonHelpersTest do
  use Ysc.DataCase, async: false

  alias Ysc.Bookings.{Season, SeasonHelpers}
  alias Ysc.Repo

  setup do
    Ysc.Bookings.SeasonCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  describe "get_current_season_info/2" do
    test "returns season and date range when a season matches" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Summer Helpers",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-09-30],
          max_nights: 4
        })
        |> Repo.insert()

      today = ~D[2025-07-15]

      assert {season, start_d, end_d} =
               SeasonHelpers.get_current_season_info(:tahoe, today)

      assert season.name == "Summer Helpers"
      assert %Date{} = start_d
      assert %Date{} = end_d
    end

    test "returns nil tuple when no season matches the date" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Narrow Window",
          property: :tahoe,
          start_date: ~D[2024-06-01],
          end_date: ~D[2024-06-15],
          max_nights: 2
        })
        |> Repo.insert()

      today = ~D[2025-12-01]

      assert SeasonHelpers.get_current_season_info(:tahoe, today) ==
               {nil, nil, nil}
    end
  end

  describe "get_season_date_range/2" do
    test "returns calendar range for a same-year season" do
      season = %Season{
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      {start_d, end_d} =
        SeasonHelpers.get_season_date_range(season, ~D[2025-07-01])

      assert start_d == Date.new!(2025, 5, 1)
      assert end_d == Date.new!(2025, 9, 30)
    end

    test "handles year-spanning season when reference is in Jan-Apr (later segment)" do
      season = %Season{
        start_date: ~D[2024-11-01],
        end_date: ~D[2024-04-30]
      }

      {start_d, end_d} =
        SeasonHelpers.get_season_date_range(season, ~D[2026-02-10])

      assert start_d == Date.new!(2025, 11, 1)
      assert end_d == Date.new!(2026, 4, 30)
    end

    test "handles year-spanning season when reference is in Nov-Dec (earlier segment)" do
      season = %Season{
        start_date: ~D[2024-11-01],
        end_date: ~D[2024-04-30]
      }

      {start_d, end_d} =
        SeasonHelpers.get_season_date_range(season, ~D[2026-12-05])

      assert start_d == Date.new!(2026, 11, 1)
      assert end_d == Date.new!(2027, 4, 30)
    end
  end

  describe "calculate_max_booking_date/2" do
    test "uses advance_booking_days when the current season sets a limit" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Limited",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-09-30],
          max_nights: 4,
          advance_booking_days: 14
        })
        |> Repo.insert()

      today = ~D[2025-07-01]

      assert SeasonHelpers.calculate_max_booking_date(:tahoe, today) ==
               Date.add(today, 14)
    end

    test "uses conservative default when no season exists for the property" do
      today = ~D[2025-07-01]

      assert SeasonHelpers.calculate_max_booking_date(:clear_lake, today) ==
               Date.add(today, 365)
    end

    test "when current season has no advance limit, extends max date using next season limit" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Summer Max Test",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-09-30],
          max_nights: 4,
          advance_booking_days: nil
        })
        |> Repo.insert()

      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Winter Max Test",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30],
          max_nights: 4,
          advance_booking_days: 100
        })
        |> Repo.insert()

      Ysc.Bookings.SeasonCache.invalidate()

      today = ~D[2025-07-15]
      expected = Date.add(today, 100)

      assert SeasonHelpers.calculate_max_booking_date(:tahoe, today) == expected
    end
  end

  describe "date_selectable?/3" do
    test "returns false when date is beyond advance booking window" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Selectable Test",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          max_nights: 4,
          advance_booking_days: 5
        })
        |> Repo.insert()

      today = ~D[2026-01-01]
      far_future = ~D[2026-02-01]

      refute SeasonHelpers.date_selectable?(:tahoe, far_future, today)
    end

    test "returns true when season has no advance limit" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Open",
          property: :clear_lake,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          max_nights: 10,
          advance_booking_days: nil
        })
        |> Repo.insert()

      today = ~D[2026-01-01]

      assert SeasonHelpers.date_selectable?(:clear_lake, ~D[2027-06-01], today)
    end

    test "returns true when date is on the advance booking boundary" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Boundary",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          max_nights: 4,
          advance_booking_days: 10
        })
        |> Repo.insert()

      today = ~D[2026-06-01]
      last_ok = Date.add(today, 10)

      assert SeasonHelpers.date_selectable?(:tahoe, last_ok, today)
    end
  end

  describe "validate_season_date_range/4" do
    test "returns an empty map (cross-season bookings allowed)" do
      assert SeasonHelpers.validate_season_date_range(
               :tahoe,
               ~D[2025-01-01],
               ~D[2025-06-01]
             ) == %{}
    end
  end

  describe "validate_advance_booking_limit/4" do
    test "returns error when check-in is beyond the advance window" do
      {:ok, season} =
        %Season{}
        |> Season.changeset(%{
          name: "Advance Limit",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          max_nights: 4,
          advance_booking_days: 10
        })
        |> Repo.insert()

      today = ~D[2026-01-01]
      checkin = ~D[2026-12-01]
      checkout = ~D[2026-12-03]

      errors =
        SeasonHelpers.validate_advance_booking_limit(
          :tahoe,
          checkin,
          checkout,
          today
        )

      assert Map.has_key?(errors, :advance_booking_limit)
      assert errors.advance_booking_limit =~ "#{season.advance_booking_days}"
    end

    test "returns error when check-out is beyond the advance window (check-in ok)" do
      {:ok, _} =
        %Season{}
        |> Season.changeset(%{
          name: "Checkout Window",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          max_nights: 4,
          advance_booking_days: 5
        })
        |> Repo.insert()

      today = ~D[2026-01-01]
      checkin = ~D[2026-01-05]
      checkout = ~D[2026-01-20]

      errors =
        SeasonHelpers.validate_advance_booking_limit(
          :tahoe,
          checkin,
          checkout,
          today
        )

      assert Map.has_key?(errors, :advance_booking_limit)
      assert errors.advance_booking_limit =~ "check-out"
    end

    test "applies checkout season limit when booking spans a different season" do
      {:ok, summer} =
        %Season{}
        |> Season.changeset(%{
          name: "Span Summer",
          property: :tahoe,
          start_date: ~D[2024-05-01],
          end_date: ~D[2024-09-30],
          max_nights: 4,
          advance_booking_days: nil
        })
        |> Repo.insert()

      {:ok, winter} =
        %Season{}
        |> Season.changeset(%{
          name: "Span Winter",
          property: :tahoe,
          start_date: ~D[2024-11-01],
          end_date: ~D[2025-04-30],
          max_nights: 4,
          advance_booking_days: 7
        })
        |> Repo.insert()

      Ysc.Bookings.SeasonCache.invalidate()

      # Check-in still in summer; check-out in winter; winter's 7-day window from
      # `today` does not reach September check-in.
      today = ~D[2026-08-22]
      checkin = ~D[2026-09-01]
      checkout = ~D[2026-11-05]

      errors =
        SeasonHelpers.validate_advance_booking_limit(
          :tahoe,
          checkin,
          checkout,
          today
        )

      assert Map.has_key?(errors, :advance_booking_limit)
      assert errors.advance_booking_limit =~ winter.name
      refute errors.advance_booking_limit =~ summer.name
    end
  end
end
