defmodule Ysc.Events.EventHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.EventHelpers

  @now ~U[2026-07-15 12:00:00Z]
  @past ~U[2026-07-10 12:00:00Z]
  @future ~U[2026-07-20 12:00:00Z]

  describe "event_sold_out?/2" do
    test "returns false when there are no non-donation tiers" do
      event = %{
        ticket_tiers: [
          %{type: :donation, quantity: 10, sold_tickets_count: 10}
        ]
      }

      refute EventHelpers.event_sold_out?(event, @now)
    end

    test "returns false when ticket tiers are empty" do
      refute EventHelpers.event_sold_out?(%{ticket_tiers: []}, @now)
    end

    test "returns false when tiers are only pre-sale" do
      event = %{
        ticket_tiers: [
          %{
            type: :paid,
            quantity: 50,
            sold_tickets_count: 50,
            start_date: @future,
            end_date: nil
          }
        ]
      }

      refute EventHelpers.event_sold_out?(event, @now)
    end

    test "returns true when all on-sale tiers are sold out" do
      event = %{
        ticket_tiers: [
          %{
            type: :paid,
            quantity: 10,
            sold_tickets_count: 10,
            start_date: @past,
            end_date: @future
          }
        ]
      }

      assert EventHelpers.event_sold_out?(event, @now)
    end

    test "returns false when an on-sale tier still has capacity" do
      event = %{
        ticket_tiers: [
          %{
            type: :paid,
            quantity: 10,
            sold_tickets_count: 5,
            start_date: @past,
            end_date: @future
          }
        ]
      }

      refute EventHelpers.event_sold_out?(event, @now)
    end

    test "returns false when a tier has unlimited quantity" do
      event = %{
        ticket_tiers: [
          %{
            type: :paid,
            quantity: nil,
            sold_tickets_count: 100,
            start_date: @past,
            end_date: @future
          }
        ]
      }

      refute EventHelpers.event_sold_out?(event, @now)
    end

    test "returns true when ticket_count reaches max_attendees" do
      event = %{
        max_attendees: 50,
        ticket_count: 50,
        ticket_tiers: [
          %{
            type: :paid,
            quantity: 100,
            sold_tickets_count: 10,
            start_date: @past,
            end_date: @future
          }
        ]
      }

      assert EventHelpers.event_sold_out?(event, @now)
    end

    test "returns true when sale-ended tier is sold out" do
      event = %{
        ticket_tiers: [
          %{
            type: :paid,
            quantity: 5,
            sold_tickets_count: 5,
            start_date: @past,
            end_date: @past
          }
        ]
      }

      assert EventHelpers.event_sold_out?(event, @now)
    end

    test "ignores donation tiers when checking tier capacity" do
      event = %{
        ticket_tiers: [
          %{
            type: :donation,
            quantity: 1,
            sold_tickets_count: 1,
            start_date: @past,
            end_date: @future
          },
          %{
            type: :paid,
            quantity: 20,
            sold_tickets_count: 0,
            start_date: @past,
            end_date: @future
          }
        ]
      }

      refute EventHelpers.event_sold_out?(event, @now)
    end

    test "works with string keys on maps" do
      event = %{
        "max_attendees" => 2,
        "ticket_count" => 2,
        "ticket_tiers" => [
          %{
            "type" => "paid",
            "quantity" => 50,
            "sold_tickets_count" => 0,
            "start_date" => @past,
            "end_date" => @future
          }
        ]
      }

      assert EventHelpers.event_sold_out?(event, @now)
    end
  end
end
