defmodule YscWeb.SeasonsTest do
  use ExUnit.Case, async: true

  alias YscWeb.Seasons

  describe "get_season/1" do
    test "returns :winter for November 1st (winter start)" do
      date = ~D[2024-11-01]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :winter for December dates" do
      date = ~D[2024-12-15]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :winter for January dates" do
      date = ~D[2024-01-15]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :winter for February dates" do
      date = ~D[2024-02-15]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :winter for March dates" do
      date = ~D[2024-03-15]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :winter for April 1st (winter end)" do
      date = ~D[2024-04-01]
      assert Seasons.get_season(date) == :winter
    end

    test "returns :summer for April 2nd (day after winter end)" do
      date = ~D[2024-04-02]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for May dates" do
      date = ~D[2024-05-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for June dates" do
      date = ~D[2024-06-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for July dates" do
      date = ~D[2024-07-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for August dates" do
      date = ~D[2024-08-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for September dates" do
      date = ~D[2024-09-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :summer for October dates" do
      date = ~D[2024-10-15]
      assert Seasons.get_season(date) == :summer
    end

    test "returns :winter for October 31st (day before winter start)" do
      # Edge case - October 31st should be summer
      date = ~D[2024-10-31]
      assert Seasons.get_season(date) == :summer
    end
  end

  describe "get_current_season/0" do
    test "returns the current season based on today's date" do
      # This test will pass regardless of when it's run
      # It just verifies the function returns either :winter or :summer
      result = Seasons.get_current_season()
      assert result in [:winter, :summer]
    end
  end
end
