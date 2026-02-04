defmodule Ysc.Bookings.SeasonTest do
  @moduledoc """
  Tests for Season schema.

  These tests verify:
  - Required field validation
  - Date range validation (including year-spanning ranges)
  - Property enum validation
  - Default season uniqueness per property
  - Max nights validation
  - Advance booking days validation
  - String length validations
  - Database constraints
  """
  use Ysc.DataCase, async: true

  alias Ysc.Bookings.Season
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "Summer"
      assert changeset.changes.property == :tahoe
      assert changeset.changes.start_date == ~D[2024-05-01]
      assert changeset.changes.end_date == ~D[2024-09-30]
    end

    test "creates valid changeset with optional fields" do
      attrs = %{
        name: "Peak Season",
        description: "Peak holiday season with premium pricing",
        property: :tahoe,
        start_date: ~D[2024-12-15],
        end_date: ~D[2025-01-15],
        is_default: true,
        # Use true to see it in changes
        advance_booking_days: 180,
        max_nights: 3
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?

      assert changeset.changes.description ==
               "Peak holiday season with premium pricing"

      assert changeset.changes.is_default == true
      assert changeset.changes.advance_booking_days == 180
      assert changeset.changes.max_nights == 3
    end

    test "requires name" do
      attrs = %{
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "requires property" do
      attrs = %{
        name: "Summer",
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:property] != nil
    end

    test "requires start_date" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:start_date] != nil
    end

    test "requires end_date" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:end_date] != nil
    end

    test "validates name maximum length (255 characters)" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        name: long_name,
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "accepts name with exactly 255 characters" do
      valid_name = String.duplicate("a", 255)

      attrs = %{
        name: valid_name,
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "validates description maximum length (1000 characters)" do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        name: "Summer",
        description: long_description,
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 1000 characters" do
      valid_description = String.duplicate("a", 1000)

      attrs = %{
        name: "Summer",
        description: valid_description,
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end
  end

  describe "date range validation" do
    test "accepts valid same-year date range" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "accepts year-spanning range that looks backwards (Sept to May)" do
      # The schema interprets month 9 > month 5 as year-spanning (recurring annually)
      # So Sept 30 to May 1 is valid (means Sept 30 of any year to May 1 next year)
      attrs = %{
        name: "Fall/Winter/Spring",
        property: :tahoe,
        start_date: ~D[2024-09-30],
        end_date: ~D[2024-05-01]
      }

      changeset = Season.changeset(%Season{}, attrs)

      # This is valid because start_month (9) > end_month (5) = year-spanning
      assert changeset.valid?
    end

    test "rejects same-year range where end equals start" do
      attrs = %{
        name: "Invalid Season",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-05-01]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:end_date] != nil
    end

    test "accepts year-spanning range (winter season Nov to Apr)" do
      attrs = %{
        name: "Winter",
        property: :tahoe,
        start_date: ~D[2024-11-01],
        # November
        end_date: ~D[2025-04-30]
        # April next year
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "accepts year-spanning range (Dec to Jan)" do
      attrs = %{
        name: "Holiday Season",
        property: :tahoe,
        start_date: ~D[2024-12-15],
        end_date: ~D[2025-01-15]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end
  end

  describe "property enum" do
    test "accepts tahoe property" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :tahoe
    end

    test "accepts clear_lake property" do
      attrs = %{
        name: "Year Round",
        property: :clear_lake,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31]
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
      assert changeset.changes.property == :clear_lake
    end

    test "rejects invalid property" do
      attrs = %{
        name: "Summer",
        property: :invalid_property,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
    end
  end

  describe "advance_booking_days validation" do
    test "accepts positive advance booking days" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        advance_booking_days: 180
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "accepts zero advance booking days (no limit)" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        advance_booking_days: 0
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "rejects negative advance booking days" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        advance_booking_days: -30
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:advance_booking_days] != nil
    end

    test "accepts nil advance booking days (default)" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        advance_booking_days: nil
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end
  end

  describe "max_nights validation" do
    test "accepts positive max nights" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        max_nights: 7
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end

    test "rejects zero max nights" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        max_nights: 0
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:max_nights] != nil
    end

    test "rejects negative max nights" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        max_nights: -5
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:max_nights] != nil
    end

    test "accepts nil max nights (use property default)" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30],
        max_nights: nil
      }

      changeset = Season.changeset(%Season{}, attrs)

      assert changeset.valid?
    end
  end

  describe "default season uniqueness" do
    test "allows setting a season as default when none exists" do
      attrs = %{
        name: "Default Season",
        property: :tahoe,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31],
        is_default: true
      }

      changeset = Season.changeset(%Season{}, attrs)
      assert changeset.valid?

      {:ok, _season} = Repo.insert(changeset)
    end

    test "rejects setting second default season for same property" do
      # Create first default season
      {:ok, _season1} =
        %Season{}
        |> Season.changeset(%{
          name: "First Default",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-06-30],
          is_default: true
        })
        |> Repo.insert()

      # Try to create second default season for same property
      attrs = %{
        name: "Second Default",
        property: :tahoe,
        start_date: ~D[2024-07-01],
        end_date: ~D[2024-12-31],
        is_default: true
      }

      changeset = Season.changeset(%Season{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:is_default] != nil
      {message, _} = changeset.errors[:is_default]
      assert message =~ "only one default season allowed per property"
    end

    test "allows default season for different property" do
      # Create default season for tahoe
      {:ok, _season1} =
        %Season{}
        |> Season.changeset(%{
          name: "Tahoe Default",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          is_default: true
        })
        |> Repo.insert()

      # Create default season for clear_lake (different property)
      attrs = %{
        name: "Clear Lake Default",
        property: :clear_lake,
        start_date: ~D[2024-01-01],
        end_date: ~D[2024-12-31],
        is_default: true
      }

      changeset = Season.changeset(%Season{}, attrs)
      assert changeset.valid?

      {:ok, _season2} = Repo.insert(changeset)
    end

    test "allows non-default season when default exists" do
      # Create default season
      {:ok, _season1} =
        %Season{}
        |> Season.changeset(%{
          name: "Default Season",
          property: :tahoe,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-12-31],
          is_default: true
        })
        |> Repo.insert()

      # Create non-default season (should be allowed)
      attrs = %{
        name: "Peak Season",
        property: :tahoe,
        start_date: ~D[2024-12-15],
        end_date: ~D[2025-01-15],
        is_default: false
      }

      changeset = Season.changeset(%Season{}, attrs)
      assert changeset.valid?

      {:ok, _season2} = Repo.insert(changeset)
    end
  end

  describe "database operations" do
    test "can insert and retrieve complete season" do
      attrs = %{
        name: "Peak Summer",
        description: "July and August peak season with maximum pricing",
        property: :tahoe,
        start_date: ~D[2024-07-01],
        end_date: ~D[2024-08-31],
        is_default: false,
        advance_booking_days: 90,
        max_nights: 3
      }

      changeset = Season.changeset(%Season{}, attrs)
      {:ok, season} = Repo.insert(changeset)

      retrieved = Repo.get(Season, season.id)

      assert retrieved.name == "Peak Summer"

      assert retrieved.description ==
               "July and August peak season with maximum pricing"

      assert retrieved.property == :tahoe
      assert retrieved.start_date == ~D[2024-07-01]
      assert retrieved.end_date == ~D[2024-08-31]
      assert retrieved.is_default == false
      assert retrieved.advance_booking_days == 90
      assert retrieved.max_nights == 3
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "defaults is_default to false" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)
      {:ok, season} = Repo.insert(changeset)

      assert season.is_default == false
    end

    test "defaults advance_booking_days to nil" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)
      {:ok, season} = Repo.insert(changeset)

      assert is_nil(season.advance_booking_days)
    end

    test "defaults max_nights to nil" do
      attrs = %{
        name: "Summer",
        property: :tahoe,
        start_date: ~D[2024-05-01],
        end_date: ~D[2024-09-30]
      }

      changeset = Season.changeset(%Season{}, attrs)
      {:ok, season} = Repo.insert(changeset)

      assert is_nil(season.max_nights)
    end
  end

  describe "get_max_nights/2" do
    test "returns season's max_nights when set" do
      season = %Season{
        property: :tahoe,
        max_nights: 7
      }

      assert Season.get_max_nights(season, :tahoe) == 7
    end

    test "returns Tahoe default (4) when season max_nights is nil" do
      season = %Season{
        property: :tahoe,
        max_nights: nil
      }

      assert Season.get_max_nights(season, :tahoe) == 4
    end

    test "returns Clear Lake default (30) when season max_nights is nil" do
      season = %Season{
        property: :clear_lake,
        max_nights: nil
      }

      assert Season.get_max_nights(season, :clear_lake) == 30
    end

    test "returns Tahoe default (4) when season is nil" do
      assert Season.get_max_nights(nil, :tahoe) == 4
    end

    test "returns Clear Lake default (30) when season is nil" do
      assert Season.get_max_nights(nil, :clear_lake) == 30
    end
  end
end
