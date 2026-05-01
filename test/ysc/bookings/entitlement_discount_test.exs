defmodule Ysc.Bookings.EntitlementDiscountTest do
  use ExUnit.Case, async: true

  alias Ysc.Bookings.{BookingEntitlement, EntitlementDiscount}

  # ─── pick_best: multiple entitlements → single largest discount (no stacking) ───

  describe "pick_best/7" do
    @subtotal Money.new(:USD, "1000.00")
    @nights 4
    @room_ids ["room-a"]

    test "chooses the entitlement with the largest dollar discount" do
      smaller =
        percent_ent("01HQZPICKBEST000000001", Decimal.new("10"), :tahoe)

      larger =
        percent_ent("01HQZPICKBEST000000002", Decimal.new("40"), :tahoe)

      {ent, discount, final} =
        EntitlementDiscount.pick_best(
          [smaller, larger],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent.id == larger.id
      assert Money.cmp(discount, Money.new(:USD, "400.00")) == 0
      assert Money.cmp(final, Money.new(:USD, "600.00")) == 0
    end

    test "among three candidates, picks the maximum discount" do
      a = percent_ent("01HQZPICKBEST000000010", Decimal.new("10"), :tahoe)
      b = percent_ent("01HQZPICKBEST000000011", Decimal.new("35"), :tahoe)
      c = percent_ent("01HQZPICKBEST000000012", Decimal.new("20"), :tahoe)

      {_ent, discount, _final} =
        EntitlementDiscount.pick_best(
          [a, b, c],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert Money.cmp(discount, Money.new(:USD, "350.00")) == 0
    end

    test "ignores entitlements for the wrong property even if they would discount more" do
      wrong_property_big =
        percent_ent("01HQZPICKBEST000000020", Decimal.new("90"), :clear_lake)

      tahoe_small =
        percent_ent("01HQZPICKBEST000000021", Decimal.new("5"), :tahoe)

      {ent, discount, _} =
        EntitlementDiscount.pick_best(
          [wrong_property_big, tahoe_small],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent.id == tahoe_small.id
      assert Money.cmp(discount, Money.new(:USD, "50.00")) == 0
    end

    test "ignores expired entitlements" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      expired =
        percent_ent("01HQZPICKBEST000000030", Decimal.new("90"), :tahoe)
        |> Map.put(:expires_at, past)

      active =
        percent_ent("01HQZPICKBEST000000031", Decimal.new("10"), :tahoe)

      {ent, discount, final} =
        EntitlementDiscount.pick_best(
          [expired, active],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent.id == active.id
      assert Money.cmp(discount, Money.new(:USD, "100.00")) == 0
      assert Money.cmp(final, Money.new(:USD, "900.00")) == 0
    end

    test "when two entitlements yield the same discount, keeps the first in list order" do
      first =
        percent_ent("01HQZPICKBEST000000040", Decimal.new("15"), :tahoe)

      second =
        percent_ent("01HQZPICKBEST000000041", Decimal.new("15"), :tahoe)

      {ent, d1, _} =
        EntitlementDiscount.pick_best(
          [first, second],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent.id == first.id

      {ent2, d2, _} =
        EntitlementDiscount.pick_best(
          [second, first],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent2.id == second.id
      assert Money.cmp(d1, d2) == 0
    end

    test "room-specific entitlement is skipped when that room is not selected" do
      specific_room_id = "01HQZROOMSPECIFIC00001"

      for_room_only =
        percent_ent("01HQZPICKBEST000000050", Decimal.new("80"), :tahoe)
        |> Map.put(:room_id, specific_room_id)

      any_room =
        percent_ent("01HQZPICKBEST000000051", Decimal.new("10"), :tahoe)

      {ent, _, _} =
        EntitlementDiscount.pick_best(
          [for_room_only, any_room],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert ent.id == any_room.id
    end

    test "buyout mode: picks best after buyout caps (percent vs free nights)" do
      sub = Money.new(:USD, "2000.00")

      percent_big_raw =
        percent_ent("01HQZPICKBEST000000060", Decimal.new("80"), :tahoe)
        |> Map.put(:buyout_max_discount, Money.new(:USD, "300.00"))

      free_nights =
        %BookingEntitlement{
          id: "01HQZPICKBEST000000061",
          status: :active,
          benefit_kind: :free_nights,
          property: :tahoe,
          max_guests: nil,
          free_nights: 3,
          percent_off: nil,
          amount_off: nil,
          buyout_max_discount: Money.new(:USD, "2000.00"),
          expires_at: nil,
          room_id: nil
        }

      # 3/4 nights * 2000 = 1500 discount for free_nights; percent capped to 300
      {_ent, discount, _} =
        EntitlementDiscount.pick_best(
          [percent_big_raw, free_nights],
          :tahoe,
          :buyout,
          [],
          4,
          sub,
          4
        )

      assert Money.cmp(discount, Money.new(:USD, "1500.00")) == 0
    end

    test "empty input returns no entitlement and zero discount" do
      {nil, disc, final} =
        EntitlementDiscount.pick_best(
          [],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert Money.cmp(disc, Money.new(:USD, "0")) == 0
      assert final == @subtotal
    end

    test "no eligible entitlements returns nil and full subtotal" do
      past = DateTime.add(DateTime.utc_now(), -7200, :second)

      expired =
        percent_ent("01HQZPICKBEST000000070", Decimal.new("50"), :tahoe)
        |> Map.put(:expires_at, past)

      wrong_prop =
        percent_ent("01HQZPICKBEST000000071", Decimal.new("50"), :clear_lake)

      {nil, disc, final} =
        EntitlementDiscount.pick_best(
          [expired, wrong_prop],
          :tahoe,
          :room,
          @room_ids,
          4,
          @subtotal,
          @nights
        )

      assert Money.cmp(disc, Money.new(:USD, "0")) == 0
      assert final == @subtotal
    end
  end

  defp percent_ent(id, %Decimal{} = pct, property) do
    %BookingEntitlement{
      id: id,
      status: :active,
      benefit_kind: :percent_off,
      property: property,
      max_guests: nil,
      free_nights: nil,
      percent_off: pct,
      amount_off: nil,
      buyout_max_discount: Money.new(:USD, "5000.00"),
      expires_at: nil,
      room_id: nil
    }
  end

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
