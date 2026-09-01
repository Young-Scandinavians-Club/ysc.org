defmodule Ysc.Tickets.TicketOrderTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Tickets.TicketOrder

  describe "create_changeset/2" do
    test "keeps an explicitly provided reference_id on the struct" do
      user = user_fixture()
      event = event_fixture()

      expires =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      cs =
        %TicketOrder{reference_id: "ORD-FIXED-REF"}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: Money.new(10, :USD),
          expires_at: expires
        })

      assert Ecto.Changeset.get_field(cs, :reference_id) == "ORD-FIXED-REF"
    end
  end

  describe "admin_grant_changeset/3" do
    test "casts payment_channel and offline_amount_collected onto a $0 grant" do
      user = user_fixture()
      granter = user_fixture()
      event = event_fixture()

      expires =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      collected = Money.new(:USD, "45.00")

      cs =
        TicketOrder.admin_grant_changeset(
          %TicketOrder{},
          %{
            user_id: user.id,
            event_id: event.id,
            total_amount: Money.new(0, :USD),
            expires_at: expires,
            payment_channel: "check",
            offline_amount_collected: collected
          },
          granter.id
        )

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :status) == :completed
      assert Ecto.Changeset.get_field(cs, :granted_by_id) == granter.id
      assert Ecto.Changeset.get_field(cs, :payment_channel) == "check"

      assert Money.equal?(
               Ecto.Changeset.get_field(cs, :offline_amount_collected),
               collected
             )

      assert Ecto.Changeset.get_field(cs, :total_amount) == Money.new(0, :USD)
    end
  end

  describe "status_changeset/2" do
    test "rejects negative total_amount" do
      cs =
        %TicketOrder{total_amount: Money.new(-1, :USD)}
        |> TicketOrder.status_changeset(%{status: :completed})

      assert %{total_amount: ["must be greater than or equal to zero"]} =
               errors_on(cs)
    end

    test "accepts zero total_amount" do
      cs =
        %TicketOrder{total_amount: Money.new(0, :USD)}
        |> TicketOrder.status_changeset(%{status: :completed})

      assert cs.valid?
    end
  end

  describe "payment_changeset/2" do
    test "requires payment_intent_id" do
      cs = %TicketOrder{} |> TicketOrder.payment_changeset(%{})
      assert "can't be blank" in errors_on(cs).payment_intent_id
    end
  end

  describe "put_new_reference_id/1" do
    test "generates a new reference when one is already set" do
      cs =
        %TicketOrder{}
        |> Ecto.Changeset.change(%{reference_id: "ORD-OLD-REF"})
        |> TicketOrder.put_new_reference_id()

      new_ref = Ecto.Changeset.get_change(cs, :reference_id)
      assert new_ref != "ORD-OLD-REF"
      assert new_ref =~ ~r/^ORD-\d{6}-[A-Z0-9]{5}$/
    end
  end
end
