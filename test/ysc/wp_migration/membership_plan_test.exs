defmodule Ysc.WpMigration.MembershipPlanTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.MembershipPlan

  describe "from_product_name/1" do
    test "detects family and single membership products" do
      assert MembershipPlan.from_product_name("One Year Family Membership") ==
               "family"

      assert MembershipPlan.from_product_name("One Year Single Membership") ==
               "single"

      assert MembershipPlan.from_product_name(
               "Upgrade from single to family membership"
             ) == "family"

      assert MembershipPlan.from_product_name("YSC Family Membership") ==
               "family"

      assert MembershipPlan.from_product_name("YSC Single Membership") ==
               "single"
    end
  end

  describe "from_membership_type/1" do
    test "normalizes application and usermeta membership type values" do
      assert MembershipPlan.from_membership_type("family") == "family"
      assert MembershipPlan.from_membership_type("wc-family") == "family"
      assert MembershipPlan.from_membership_type("single") == "single"
      assert MembershipPlan.from_membership_type("unknown") == nil
      assert MembershipPlan.from_membership_type(nil) == nil
      assert MembershipPlan.from_membership_type("") == nil
    end
  end

  describe "resolve/1" do
    test "prefers membership_product_name over all other plan signals" do
      assert MembershipPlan.resolve(%{
               membership_product_name: "One Year Single Membership",
               wcm_product_name: "One Year Family Membership",
               sub_product_name: "One Year Family Membership",
               application_membership_type: "family",
               user_membership_type: "family"
             }) == "single"
    end

    test "prefers WooCommerce membership product over application and usermeta" do
      assert MembershipPlan.resolve(%{
               wcm_product_name: "One Year Family Membership",
               application_membership_type: "single",
               user_membership_type: "single"
             }) == "family"
    end

    test "uses subscription product when membership product is absent" do
      assert MembershipPlan.resolve(%{
               sub_product_name: "One Year Single Membership",
               application_membership_type: "family"
             }) == "single"
    end

    test "falls back to application membership type" do
      assert MembershipPlan.resolve(%{
               application_membership_type: "family",
               user_membership_type: "single"
             }) == "family"
    end

    test "falls back to user usermeta membership type" do
      assert MembershipPlan.resolve(%{
               user_membership_type: "family"
             }) == "family"
    end

    test "defaults to single when no plan signals exist" do
      assert MembershipPlan.resolve(%{}) == "single"
    end
  end
end
