defmodule Ysc.Tickets.ReservationDiscountTest do
  use ExUnit.Case, async: true

  alias Ysc.Tickets.ReservationDiscount

  describe "amount/3" do
    test "applies percentage to price times quantity" do
      assert Money.equal?(
               ReservationDiscount.amount(
                 Money.new(:USD, "25.00"),
                 1,
                 Decimal.new(50)
               ),
               Money.new(:USD, "12.50")
             )

      assert Money.equal?(
               ReservationDiscount.amount(
                 Money.new(:USD, "25.00"),
                 2,
                 Decimal.new(50)
               ),
               Money.new(:USD, "25.00")
             )
    end

    test "applies a 100 percent hold as the full original total" do
      assert Money.equal?(
               ReservationDiscount.amount(
                 Money.new(:USD, "40.00"),
                 3,
                 Decimal.new(100)
               ),
               Money.new(:USD, "120.00")
             )
    end

    test "returns zero for missing, zero, or invalid inputs" do
      price = Money.new(:USD, "25.00")
      pct = Decimal.new(50)

      assert Money.zero?(ReservationDiscount.amount(price, 1, Decimal.new(0)))
      assert Money.zero?(ReservationDiscount.amount(price, 1, nil))
      assert Money.zero?(ReservationDiscount.amount(price, 0, pct))
      assert Money.zero?(ReservationDiscount.amount(price, -1, pct))
      assert Money.zero?(ReservationDiscount.amount(nil, 1, pct))
    end
  end

  describe "per_ticket_amount/3" do
    test "splits the reservation discount evenly across tickets" do
      assert Money.equal?(
               ReservationDiscount.per_ticket_amount(
                 Money.new(:USD, "25.00"),
                 2,
                 Decimal.new(50)
               ),
               Money.new(:USD, "12.50")
             )
    end

    test "returns zero when quantity is not a positive integer" do
      assert Money.zero?(
               ReservationDiscount.per_ticket_amount(
                 Money.new(:USD, "25.00"),
                 0,
                 Decimal.new(50)
               )
             )
    end
  end
end
