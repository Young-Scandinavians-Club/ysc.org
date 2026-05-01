defmodule Ysc.Bookings.EntitlementDiscountTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.{BookingEntitlement, EntitlementDiscount}

  describe "free_nights with max_guests" do
    test "scales discount when party is larger than max_guests (2 of 4 adults, 2 of 4 nights)" do
      ent = %BookingEntitlement{
        id: "01HQZTESTENTITLEMENT00000",
        status: :active,
        benefit_kind: :free_nights,
        property: :tahoe,
        max_guests: 2,
        free_nights: 2,
        percent_off: nil,
        amount_off: nil,
        buyout_max_discount: Money.new(:USD, "500.00"),
        expires_at: nil,
        room_id: nil
      }

      subtotal = Money.new(:USD, "720.00")

      # 4 adults × 4 nights linear total; entitlement = 2 nights for up to 2 guests
      # => (2/4 nights) * (2/4 guest coverage) = 1/4 of subtotal
      d = EntitlementDiscount.discount_for(ent, :room, subtotal, 4, 4)
      assert Money.cmp(d, Money.new(:USD, "180.00")) == 0
    end

    test "full guest coverage when headcount matches max_guests" do
      ent = %BookingEntitlement{
        id: "01HQZTESTENTITLEMENT00001",
        status: :active,
        benefit_kind: :free_nights,
        property: :tahoe,
        max_guests: 2,
        free_nights: 2,
        percent_off: nil,
        amount_off: nil,
        buyout_max_discount: Money.new(:USD, "500.00"),
        expires_at: nil,
        room_id: nil
      }

      subtotal = Money.new(:USD, "360.00")
      d = EntitlementDiscount.discount_for(ent, :room, subtotal, 4, 2)
      assert Money.cmp(d, Money.new(:USD, "180.00")) == 0
    end

    test "eligible? does not reject larger parties" do
      ent = %BookingEntitlement{
        id: "01HQZTESTENTITLEMENT00002",
        status: :active,
        benefit_kind: :free_nights,
        property: :tahoe,
        max_guests: 2,
        free_nights: 2,
        percent_off: nil,
        amount_off: nil,
        buyout_max_discount: Money.new(:USD, "500.00"),
        expires_at: nil,
        room_id: nil
      }

      assert EntitlementDiscount.eligible?(ent, :tahoe, :room, ["room1"], 4)
    end
  end
end
