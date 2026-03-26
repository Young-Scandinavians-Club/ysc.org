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
