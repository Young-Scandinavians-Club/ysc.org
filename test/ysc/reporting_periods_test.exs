defmodule Ysc.ReportingPeriodsTest do
  use ExUnit.Case, async: true

  alias Ysc.ReportingPeriods

  describe "start_of_month/2" do
    test "stays in October at 5pm Pacific on Oct 31 (already Nov 1 in UTC)" do
      now = ~U[2026-11-01 00:30:00Z]

      assert ReportingPeriods.start_of_month(now) == ~U[2026-10-01 07:00:00Z]
    end

    test "rolls over at Pacific midnight" do
      assert ReportingPeriods.start_of_month(~U[2026-11-01 07:00:00Z]) ==
               ~U[2026-11-01 07:00:00Z]
    end

    test "uses the standard-time offset after DST ends" do
      assert ReportingPeriods.start_of_month(~U[2026-12-15 12:00:00Z]) ==
               ~U[2026-12-01 08:00:00Z]
    end

    test "offsets by calendar months across a DST change" do
      now = ~U[2026-11-15 12:00:00Z]

      assert ReportingPeriods.start_of_month(now, -1) ==
               ~U[2026-10-01 07:00:00Z]

      assert ReportingPeriods.start_of_month(now, -12) ==
               ~U[2025-11-01 07:00:00Z]

      assert ReportingPeriods.start_of_month(now, 1) == ~U[2026-12-01 08:00:00Z]
    end
  end

  describe "start_of_year/2" do
    test "stays in the prior year until Pacific New Year" do
      now = ~U[2027-01-01 03:00:00Z]

      assert ReportingPeriods.start_of_year(now) == ~U[2026-01-01 08:00:00Z]
      assert ReportingPeriods.start_of_year(now, -1) == ~U[2025-01-01 08:00:00Z]
    end
  end

  test "local_date/1 returns the Pacific calendar date" do
    assert ReportingPeriods.local_date(~U[2026-11-01 00:30:00Z]) ==
             ~D[2026-10-31]
  end

  test "today/0 matches the Pacific date of the current instant" do
    assert ReportingPeriods.today() ==
             ReportingPeriods.local_date(DateTime.utc_now())
  end
end
