defmodule YscWeb.Emails.TicketOrderRefundTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder
  alias YscWeb.Emails.TicketOrderRefund

  setup do
    Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "prepare_email_data/3" do
    setup do
      user = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: ticket_order.total_amount,
          event_amount: ticket_order.total_amount,
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_tor_email_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      ticket_order = Tickets.get_ticket_order(ticket_order.id)
      [t1 | _] = ticket_order.tickets

      assert {:ok, %{refunded_tickets: refunded}} =
               Tickets.refund_tickets(ticket_order, [t1.id], "Test refund")

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(25, :USD),
          reason: "Partial refund test",
          external_refund_id:
            "re_tor_email_#{System.unique_integer([:positive])}"
        })

      %{
        refund: refund,
        ticket_order: ticket_order,
        refunded_tickets: refunded
      }
    end

    test "builds email data with refund, order, and refunded tickets", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.first_name ==
               ticket_order.user.first_name ||
               data.first_name == "Valued Member"

      assert data.event.title == ticket_order.event.title
      assert data.event_url =~ ticket_order.event.id
      assert data.refund.reference_id == refund.reference_id
      assert data.refund.amount =~ "$"
      assert data.refund.reason == "Partial refund test"
      assert data.refund_date =~ "20"
      assert data.ticket_order.reference_id == ticket_order.reference_id
      assert data.refunded_tickets != []
      assert Enum.all?(data.refunded_tickets, &Map.has_key?(&1, :reference_id))
    end

    test "formats event date without time when start_time is nil", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{start_time: nil})
      |> Repo.update!()

      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      refute data.event_date_time =~ " at "

      event = Repo.get!(Event, ticket_order.event_id)
      year = event.start_date.year
      assert data.event_date_time =~ to_string(year)
    end

    test "formats event as TBD when start_date is nil", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{start_date: nil})
      |> Repo.update!()

      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.event_date_time == "TBD"
    end

    test "uses default refund reason when reason is nil", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      {:ok, refund} =
        refund
        |> Ecto.Changeset.change(%{reason: nil})
        |> Repo.update()

      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.refund.reason == "Refund processed"
    end

    test "raises when refund is nil", %{
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      assert_raise ArgumentError, "Refund cannot be nil", fn ->
        TicketOrderRefund.prepare_email_data(nil, ticket_order, refunded)
      end
    end

    test "raises when ticket order is nil", %{
      refund: refund,
      refunded_tickets: refunded
    } do
      assert_raise ArgumentError, "Ticket order cannot be nil", fn ->
        TicketOrderRefund.prepare_email_data(refund, nil, refunded)
      end
    end

    test "raises when ticket order is not found in database", %{
      refund: refund,
      refunded_tickets: refunded
    } do
      missing =
        struct!(TicketOrder, %{
          id: Ecto.ULID.generate(),
          user_id: Ecto.ULID.generate(),
          event_id: Ecto.ULID.generate(),
          reference_id: "ORD-MISS",
          total_amount: Money.new(50, :USD),
          status: :completed
        })

      assert_raise ArgumentError, fn ->
        TicketOrderRefund.prepare_email_data(refund, missing, refunded)
      end
    end

    test "uses Valued Member when user first_name is nil", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      ticket_order.user
      |> Ecto.Changeset.change(%{first_name: nil})
      |> Repo.update!()

      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.first_name == "Valued Member"
    end

    test "formats refund_date as N/A when refund inserted_at is nil", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      refund_without_ts = %{refund | inserted_at: nil}

      data =
        TicketOrderRefund.prepare_email_data(
          refund_without_ts,
          ticket_order,
          refunded
        )

      assert data.refund_date == "N/A"
      assert data.refund.refund_date == "N/A"
    end

    test "raises when refunded ticket is missing ticket_tier for tier summary row",
         %{
           refund: refund,
           ticket_order: ticket_order
         } do
      [t1 | _] = ticket_order.tickets
      bad = %{t1 | ticket_tier: nil}

      assert_raise ArgumentError, ~r/missing ticket_tier association/, fn ->
        TicketOrderRefund.prepare_email_data(refund, ticket_order, [bad])
      end
    end

    test "formats event with DateTime start_date and start_time", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{
        start_date: ~U[2026-08-01 12:00:00Z],
        start_time: ~T[18:00:00]
      })
      |> Repo.update!()

      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.event_date_time =~ " at "
    end
  end

  describe "prepare_email_data/3 multiple ticket tiers" do
    setup do
      user = user_fixture()
      event = event_fixture()

      tier_a =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Tier A",
          price: Money.new(25, :USD)
        })

      tier_b =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Tier B",
          price: Money.new(75, :USD)
        })

      ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          ticket_selections: %{tier_a.id => 1, tier_b.id => 1},
          status: :completed
        })

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: ticket_order.total_amount,
          event_amount: ticket_order.total_amount,
          donation_amount: Money.new(0, :USD),
          event_id: event.id,
          external_payment_id:
            "pi_tor_multi_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      ticket_order = Tickets.get_ticket_order(ticket_order.id)
      ticket_ids = Enum.map(ticket_order.tickets, & &1.id)

      assert {:ok, %{refunded_tickets: refunded}} =
               Tickets.refund_tickets(
                 ticket_order,
                 ticket_ids,
                 "Full refund all tickets"
               )

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: ticket_order.total_amount,
          reason: "Full refund",
          external_refund_id:
            "re_tor_full_#{System.unique_integer([:positive])}"
        })

      %{
        refund: refund,
        ticket_order: ticket_order,
        refunded_tickets: refunded
      }
    end

    test "builds separate ticket_summaries rows per tier", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      names =
        data.ticket_summaries |> Enum.map(& &1.ticket_tier_name) |> Enum.sort()

      assert names == ["Tier A", "Tier B"]
      assert Enum.all?(data.ticket_summaries, &(&1.quantity == 1))
      assert data.refund.reason == "Full refund"
      assert data.refund.amount =~ "$"
    end
  end

  describe "helpers" do
    test "get_template_name/0 and get_subject/0" do
      assert TicketOrderRefund.get_template_name() == "ticket_order_refund"
      assert TicketOrderRefund.get_subject() =~ "refund"
    end

    test "event_url/1 includes events path" do
      id = Ecto.ULID.generate()
      assert TicketOrderRefund.event_url(id) =~ "/events/#{id}"
    end
  end

  describe "prepare_email_data/3 with donation tier" do
    setup do
      Ledgers.ensure_basic_accounts()

      user = user_fixture()

      user =
        user
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      organizer = user_fixture()

      {:ok, event} =
        Events.create_event(%{
          title: "Refund donation #{System.unique_integer([:positive])}",
          description: "D",
          state: :published,
          organizer_id: organizer.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 30, :day)
            |> DateTime.truncate(:second),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, paid_tier} =
        Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 100,
          event_id: event.id
        })

      {:ok, donation_tier} =
        Events.create_ticket_tier(%{
          name: "Donation",
          type: :donation,
          price: nil,
          quantity: nil,
          event_id: event.id
        })

      ticket_selections = %{paid_tier.id => 1, donation_tier.id => 4_000}

      {:ok, ticket_order} =
        Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      donation_amount =
        Money.sub!(ticket_order.total_amount, paid_tier.price)

      {:ok, {payment, _, _}} =
        Ledgers.process_event_payment_with_donations(%{
          user_id: user.id,
          total_amount: ticket_order.total_amount,
          event_amount: paid_tier.price,
          donation_amount: donation_amount,
          event_id: event.id,
          external_payment_id:
            "pi_tor_don_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      ticket_order = Tickets.get_ticket_order(ticket_order.id)

      donation_ticket =
        Enum.find(ticket_order.tickets, fn t ->
          t.ticket_tier_id == donation_tier.id
        end)

      assert {:ok, %{refunded_tickets: refunded}} =
               Tickets.refund_tickets(
                 ticket_order,
                 [donation_ticket.id],
                 "Donation refund"
               )

      {:ok, {refund, _, _}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(40, :USD),
          reason: "Donation refund test",
          external_refund_id: "re_tor_don_#{System.unique_integer([:positive])}"
        })

      %{
        refund: refund,
        ticket_order: ticket_order,
        refunded_tickets: refunded
      }
    end

    test "builds donation tier summary with calculated amounts", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      data =
        TicketOrderRefund.prepare_email_data(
          refund,
          ticket_order,
          refunded
        )

      assert data.ticket_summaries != []

      donation_row =
        Enum.find(data.ticket_summaries, &(&1.ticket_tier_name == "Donation"))

      assert donation_row
      assert donation_row.quantity == 1
      assert donation_row.price_per_ticket =~ "$"
      assert donation_row.total_price =~ "$"
    end

    test "render/1 produces HTML", %{
      refund: refund,
      ticket_order: ticket_order,
      refunded_tickets: refunded
    } do
      data =
        TicketOrderRefund.prepare_email_data(refund, ticket_order, refunded)

      html = TicketOrderRefund.render(data)

      assert is_binary(html)
      assert html =~ "refund" or html =~ "Refund" or html =~ "$"
    end
  end
end
