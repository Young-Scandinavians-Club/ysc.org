defmodule YscWeb.DateDisplayTest do
  use ExUnit.Case, async: true

  alias YscWeb.DateDisplay

  describe "format_date_long/1" do
    test "formats Date values" do
      assert DateDisplay.format_date_long(~D[2024-06-15]) == "June 15, 2024"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-06-15 23:30:00Z]

      assert DateDisplay.format_date_long(dt) == "June 15, 2024"
    end

    test "returns empty string for nil and invalid values by default" do
      assert DateDisplay.format_date_long(nil) == ""
      assert DateDisplay.format_date_long("invalid") == ""
    end

    test "accepts a custom default for nil and invalid values" do
      assert DateDisplay.format_date_long(nil, "TBD") == "TBD"
      assert DateDisplay.format_date_long(%{}, "—") == "—"
    end
  end

  describe "format_date_short/1" do
    test "formats Date values without zero-padded day" do
      assert DateDisplay.format_date_short(~D[2024-03-05]) == "Mar 5"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-03-05 18:00:00Z]

      assert DateDisplay.format_date_short(dt) == "Mar 5"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_date_short(nil) == ""
      assert DateDisplay.format_date_short(123) == ""
    end
  end

  describe "format_datetime_display/1" do
    test "formats Date values" do
      assert DateDisplay.format_datetime_display(~D[2024-12-01]) ==
               "Dec 1, 2024"
    end

    test "formats DateTime values using the UTC calendar date" do
      dt = ~U[2024-12-01 06:00:00Z]

      assert DateDisplay.format_datetime_display(dt) == "Dec 1, 2024"
    end

    test "returns empty string for nil and invalid values" do
      assert DateDisplay.format_datetime_display(nil) == ""
      assert DateDisplay.format_datetime_display(:atom) == ""
    end
  end
end
