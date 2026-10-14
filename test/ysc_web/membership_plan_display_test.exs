defmodule YscWeb.MembershipPlanDisplayTest do
  use ExUnit.Case, async: true

  alias YscWeb.MembershipPlanDisplay

  test "price/1 formats a configured plan's yearly price" do
    assert MembershipPlanDisplay.price(:single) =~ "$45"
    assert MembershipPlanDisplay.price(:family) =~ "$65"
  end

  test "price/1 is empty for an unknown plan" do
    assert MembershipPlanDisplay.price(:nope) == ""
  end

  test "price_per_year/1 adds the billing period, or nil when unavailable" do
    assert MembershipPlanDisplay.price_per_year(:single) =~ "per year"
    assert MembershipPlanDisplay.price_per_year(:nope) == nil
  end
end
