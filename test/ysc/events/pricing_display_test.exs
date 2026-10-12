defmodule Ysc.Events.PricingDisplayTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.PricingDisplay
  alias Ysc.Events.TicketTier

  describe "pricing_info/2" do
    test "returns coming-soon placeholder when tickets_tbd is true" do
      event = %{tickets_tbd: true}
      tiers = [%TicketTier{type: :paid, price: Money.new(25, :USD)}]

      assert PricingDisplay.pricing_info(event, tiers) == %{
               display_text: "Tickets Coming Soon",
               has_free_tiers: false,
               lowest_price: nil
             }
    end

    test "uses from_tiers/1 when tickets_tbd is false" do
      event = %{tickets_tbd: false}
      tier = %TicketTier{type: :paid, price: Money.new(25, :USD)}

      assert PricingDisplay.pricing_info(event, [tier]).display_text == "$25.00"
    end
  end

  describe "from_tiers/1" do
    test "empty tiers are free" do
      assert PricingDisplay.from_tiers([]) == %{
               display_text: "Free",
               has_free_tiers: true,
               lowest_price: nil
             }
    end

    test "only free tiers are free" do
      tiers = [%TicketTier{type: :free}, %TicketTier{type: "free"}]

      assert PricingDisplay.from_tiers(tiers) == %{
               display_text: "Free",
               has_free_tiers: true,
               lowest_price: nil
             }
    end

    test "mixed free and paid tiers start from $0.00" do
      tiers = [
        %TicketTier{type: :free},
        %TicketTier{type: :paid, price: Money.new(25, :USD)}
      ]

      assert PricingDisplay.from_tiers(tiers) == %{
               display_text: "From $0.00",
               has_free_tiers: true,
               lowest_price: nil
             }
    end

    test "only donation tiers are free" do
      tiers = [%TicketTier{type: :donation, price: nil}]

      assert PricingDisplay.from_tiers(tiers) == %{
               display_text: "Free",
               has_free_tiers: false,
               lowest_price: nil
             }
    end

    test "a single paid tier shows the exact price" do
      tier = %TicketTier{type: :paid, price: Money.new(25, :USD)}

      assert %{
               display_text: "$25.00",
               has_free_tiers: false,
               lowest_price: ^tier
             } = PricingDisplay.from_tiers([tier])
    end

    test "multiple paid tiers show From the lowest price" do
      cheap = %TicketTier{type: :paid, price: Money.new(10, :USD)}
      expensive = %TicketTier{type: :paid, price: Money.new(40, :USD)}

      assert %{
               display_text: "From $10.00",
               has_free_tiers: false,
               lowest_price: ^cheap
             } = PricingDisplay.from_tiers([expensive, cheap])
    end

    test "paid tiers with string type are included" do
      tier = %TicketTier{type: "paid", price: Money.new(15, :USD)}
      assert PricingDisplay.from_tiers([tier]).display_text == "$15.00"
    end

    test "non-Money paid prices fall back to $0.00" do
      tier = %TicketTier{type: :paid, price: %{amount: Decimal.new(100)}}
      assert PricingDisplay.from_tiers([tier]).display_text == "$0.00"
    end
  end
end
