defmodule Ysc.Events.TicketTierTest do
  use Ysc.DataCase, async: true

  alias Ysc.Events.TicketTier
  import Ysc.AccountsFixtures

  setup do
    org = user_fixture()
    %{event_id: Ysc.EventsFixtures.event_fixture(%{organizer_id: org.id}).id}
  end

  describe "changeset/2" do
    test "enforces $0 price for free tiers", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Freebie",
          "type" => "free",
          "event_id" => event_id
        })

      assert cs.valid?

      assert Money.equal?(
               Ecto.Changeset.get_field(cs, :price),
               Money.new(0, :USD)
             )
    end

    test "allows nil price for donation tiers", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Pay what you want",
          "type" => "donation",
          "event_id" => event_id
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :price) == nil
    end

    test "requires price for paid tiers", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Paid",
          "type" => "paid",
          "event_id" => event_id
        })

      refute cs.valid?
      assert {_msg, _} = cs.errors[:price]
    end

    test "maps quantity 0 to nil (unlimited)", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "GA",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "quantity" => 0,
          "event_id" => event_id
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :quantity) == nil
    end

    test "rejects negative quantity", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Bad",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "quantity" => -1,
          "event_id" => event_id
        })

      refute cs.valid?
      assert {_msg, _} = cs.errors[:quantity]
    end

    test "rejects end_date before start_date", %{event_id: event_id} do
      start_ts = ~U[2026-06-01 12:00:00Z]
      end_ts = ~U[2026-05-01 12:00:00Z]

      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Window",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "start_date" => start_ts,
          "end_date" => end_ts
        })

      refute cs.valid?
      assert {_msg, _} = cs.errors[:end_date]
    end

    test "normalizes invalid ISO datetime string for start_date to nil", %{
      event_id: event_id
    } do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "start_date" => "not-a-date"
        })

      assert Ecto.Changeset.get_field(cs, :start_date) == nil
    end

    test "normalizes description 'nil' string to nil", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "description" => "nil"
        })

      assert Ecto.Changeset.get_field(cs, :description) == nil
    end

    test "rejects non-USD money", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :EUR),
          "event_id" => event_id
        })

      refute cs.valid?
      assert {msg, _} = cs.errors[:price]
      assert msg == "must be in USD"
    end

    test "enforces $0 price for free tiers with atom type", %{
      event_id: event_id
    } do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          name: "Free atom",
          type: :free,
          event_id: event_id
        })

      assert cs.valid?

      assert Money.equal?(
               Ecto.Changeset.get_field(cs, :price),
               Money.new(0, :USD)
             )
    end

    test "normalizes empty description with atom key", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          name: "Tier",
          type: :paid,
          price: Money.new(10, :USD),
          event_id: event_id,
          description: ""
        })

      assert Ecto.Changeset.get_field(cs, :description) == nil
    end

    test "normalizes empty string description key", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "description" => ""
        })

      assert Ecto.Changeset.get_field(cs, :description) == nil
    end

    test "normalizes empty end_date string to nil", %{event_id: event_id} do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "end_date" => ""
        })

      assert Ecto.Changeset.get_field(cs, :end_date) == nil
    end

    test "requires price for paid tier when price is empty string", %{
      event_id: event_id
    } do
      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Paid",
          "type" => "paid",
          "price" => "",
          "event_id" => event_id
        })

      refute cs.valid?
      assert {_msg, _} = cs.errors[:price]
    end

    test "accepts valid ISO8601 datetime string for start_date unchanged", %{
      event_id: event_id
    } do
      iso = "2026-07-01T12:00:00Z"

      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Tier",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "start_date" => iso
        })

      assert %DateTime{} = Ecto.Changeset.get_field(cs, :start_date)
    end

    test "allows end_date after start_date when both set", %{event_id: event_id} do
      start_ts = ~U[2026-06-01 12:00:00Z]
      end_ts = ~U[2026-06-15 12:00:00Z]

      cs =
        %TicketTier{}
        |> TicketTier.changeset(%{
          "name" => "Window",
          "type" => "paid",
          "price" => Money.new(10, :USD),
          "event_id" => event_id,
          "start_date" => start_ts,
          "end_date" => end_ts
        })

      assert cs.valid?
    end

    test "member_only defaults to false and casts from params", %{
      event_id: event_id
    } do
      default_cs =
        TicketTier.changeset(%TicketTier{}, %{
          "name" => "GA",
          "type" => "free",
          "event_id" => event_id
        })

      assert Ecto.Changeset.get_field(default_cs, :member_only) == false

      cs =
        TicketTier.changeset(%TicketTier{}, %{
          "name" => "Members GA",
          "type" => "free",
          "event_id" => event_id,
          "member_only" => "true"
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :member_only) == true
    end
  end
end
