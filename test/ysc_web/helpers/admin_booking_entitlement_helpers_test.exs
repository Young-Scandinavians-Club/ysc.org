defmodule YscWeb.AdminBookingEntitlementHelpersTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Ysc.Bookings.BookingEntitlement
  alias YscWeb.AdminBookingEntitlementHelpers

  describe "benefit_kind_form_value/1" do
    test "defaults to percent_off when benefit_kind is unset" do
      form = to_form(%{"benefit_kind" => nil}, as: :entitlement)

      assert AdminBookingEntitlementHelpers.benefit_kind_form_value(form) ==
               "percent_off"
    end

    test "returns string benefit kind from form" do
      form = to_form(%{"benefit_kind" => "free_nights"}, as: :entitlement)

      assert AdminBookingEntitlementHelpers.benefit_kind_form_value(form) ==
               "free_nights"
    end
  end

  describe "status_label/1" do
    test "maps known statuses" do
      assert AdminBookingEntitlementHelpers.status_label(:active) == "Active"

      assert AdminBookingEntitlementHelpers.status_label(:consumed) ==
               "Consumed"

      assert AdminBookingEntitlementHelpers.status_label(:revoked) == "Revoked"
      assert AdminBookingEntitlementHelpers.status_label(:expired) == "Expired"
    end
  end

  describe "property_label/1" do
    test "maps property atoms" do
      assert AdminBookingEntitlementHelpers.property_label(nil) == "Any"
      assert AdminBookingEntitlementHelpers.property_label(:tahoe) == "Tahoe"

      assert AdminBookingEntitlementHelpers.property_label(:clear_lake) ==
               "Clear Lake"
    end
  end

  describe "benefit_summary/2" do
    test "list context includes max guests for free nights" do
      ent = %BookingEntitlement{
        benefit_kind: :free_nights,
        free_nights: 2,
        max_guests: 6
      }

      assert AdminBookingEntitlementHelpers.benefit_summary(ent, :list) ==
               "2 free night(s), max guests 6"
    end

    test "user_detail context includes buyout cap for free nights" do
      ent = %BookingEntitlement{
        benefit_kind: :free_nights,
        free_nights: 2,
        buyout_max_discount: Money.new(:USD, 500)
      }

      summary =
        AdminBookingEntitlementHelpers.benefit_summary(ent, :user_detail)

      assert summary =~ "2 free night(s), buyout cap"
      assert summary =~ "$500.00"
    end

    test "percent_off summaries include buyout cap" do
      ent = %BookingEntitlement{
        benefit_kind: :percent_off,
        percent_off: Decimal.new("50"),
        buyout_max_discount: Money.new(:USD, 100)
      }

      list_summary = AdminBookingEntitlementHelpers.benefit_summary(ent, :list)
      assert list_summary =~ "50% off, buyout cap"
      assert list_summary =~ "$100.00"

      detail_summary =
        AdminBookingEntitlementHelpers.benefit_summary(ent, :user_detail)

      assert detail_summary =~ "50% off, buyout cap"
      assert detail_summary =~ "$100.00"
    end

    test "fixed_amount_off summary" do
      ent = %BookingEntitlement{
        benefit_kind: :fixed_amount_off,
        amount_off: Money.new(:USD, 25)
      }

      assert AdminBookingEntitlementHelpers.benefit_summary(ent, :list) ==
               "$25.00 off"
    end
  end

  describe "grant_benefit_kind_options/0" do
    test "returns three benefit kinds" do
      assert length(AdminBookingEntitlementHelpers.grant_benefit_kind_options()) ==
               3
    end
  end
end
