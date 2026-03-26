defmodule YscWeb.Emails.TicketPurchaseConfirmationTest do
  use Ysc.DataCase, async: true

  import Ecto.Query

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Events
  alias Ysc.Events.{Agenda, AgendaItem}
  alias Ysc.Ledgers
  alias Ysc.Payments.PaymentMethod
  alias Ysc.Repo
  alias Ysc.Tickets
  alias YscWeb.Emails.TicketPurchaseConfirmation

  setup do
    Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "prepare_email_data/1" do
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
            "pi_tpc_email_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: completed_at
        })
        |> Repo.update!()

      %{ticket_order: Tickets.get_ticket_order(ticket_order.id)}
    end

    test "builds full purchase confirmation data from database order", %{
      ticket_order: ticket_order
    } do
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      assert data.first_name ==
               (ticket_order.user.first_name || "Valued Member")

      assert data.event.title == ticket_order.event.title
      assert data.event_url =~ ticket_order.event.id
      assert data.tickets_qr_url =~ ticket_order.id
      assert data.ticket_order.reference_id == ticket_order.reference_id
      assert data.total_amount =~ "$"
      assert data.purchase_date =~ "20"
      assert data.payment.reference_id != "N/A"
      assert data.tickets != []
      assert data.ticket_summaries != []
    end

    test "formats event date with time when start_time is set", %{
      ticket_order: ticket_order
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{start_time: ~T[15:30:00]})
      |> Repo.update!()

      ticket_order = Tickets.get_ticket_order(ticket_order.id)
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      assert data.event_date_time =~ " at "
      assert data.event_date_time =~ "PM" or data.event_date_time =~ "AM"
    end

    test "formats event date as date only when start_time is nil", %{
      ticket_order: ticket_order
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{start_time: nil})
      |> Repo.update!()

      ticket_order = Tickets.get_ticket_order(ticket_order.id)
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      refute data.event_date_time =~ " at "
      assert data.event_date_time =~ ~r/\d{4}/
    end

    test "describes payment as default Stripe card when payment_method is absent",
         %{
           ticket_order: ticket_order
         } do
      payment = ticket_order.payment |> Repo.preload(:payment_method)
      assert payment.payment_method_id == nil

      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      assert data.payment_method == "Credit Card (Stripe)"
    end

    test "describes card with brand and last four when present", %{
      ticket_order: ticket_order
    } do
      user = ticket_order.user

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_tpc_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_tpc_#{System.unique_integer([:positive])}",
        provider_type: "card",
        type: :card,
        last_four: "4242",
        display_brand: "visa",
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      ticket_order.payment
      |> Ecto.Changeset.change(%{payment_method_id: pm.id})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert data.payment_method =~ "Visa"
      assert data.payment_method =~ "4242"
    end

    test "describes card without last four as Credit Card", %{
      ticket_order: ticket_order
    } do
      user = ticket_order.user

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_tpc2_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_tpc2_#{System.unique_integer([:positive])}",
        provider_type: "card",
        type: :card,
        last_four: nil,
        display_brand: nil,
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      ticket_order.payment
      |> Ecto.Changeset.change(%{payment_method_id: pm.id})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert data.payment_method == "Credit Card"
    end

    test "describes bank account payment method", %{ticket_order: ticket_order} do
      user = ticket_order.user

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_ba_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_ba_#{System.unique_integer([:positive])}",
        provider_type: "us_bank_account",
        type: :bank_account,
        last_four: "6789",
        bank_name: "Chase",
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      ticket_order.payment
      |> Ecto.Changeset.change(%{payment_method_id: pm.id})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert data.payment_method =~ "Chase"
      assert data.payment_method =~ "6789"
    end

    test "describes bank account without last four as Bank Account", %{
      ticket_order: ticket_order
    } do
      user = ticket_order.user

      %PaymentMethod{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_ba_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_ba_#{System.unique_integer([:positive])}",
        provider_type: "us_bank_account",
        type: :bank_account,
        last_four: nil,
        bank_name: "Chase",
        is_default: true
      }
      |> Repo.insert!()

      pm =
        Repo.one!(
          from(p in PaymentMethod,
            where: p.user_id == ^user.id,
            limit: 1
          )
        )

      ticket_order.payment
      |> Ecto.Changeset.change(%{payment_method_id: pm.id})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert data.payment_method == "Bank Account"
    end

    test "raises when ticket order is nil" do
      assert_raise ArgumentError, "Ticket order cannot be nil", fn ->
        TicketPurchaseConfirmation.prepare_email_data(nil)
      end
    end

    test "raises when ticket order id is nil" do
      assert_raise ArgumentError, fn ->
        TicketPurchaseConfirmation.prepare_email_data(%{id: nil})
      end
    end

    test "raises when ticket order is not found" do
      fake =
        struct!(Ysc.Tickets.TicketOrder, %{
          id: Ecto.ULID.generate(),
          user_id: Ecto.ULID.generate(),
          event_id: Ecto.ULID.generate(),
          reference_id: "ORD-X",
          total_amount: Money.new(50, :USD),
          status: :completed
        })

      assert_raise ArgumentError, fn ->
        TicketPurchaseConfirmation.prepare_email_data(fake)
      end
    end

    test "free completed order uses Free payment and N/A payment refs" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      event = event_fixture()

      {:ok, free_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Complimentary",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 20,
          event_id: event.id
        })

      {:ok, ticket_order} =
        Tickets.create_ticket_order(user.id, event.id, %{free_tier.id => 1})

      {:ok, completed} = Tickets.process_free_ticket_order(ticket_order)
      assert completed.payment_id == nil

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(completed.id)
        )

      assert data.payment_method == "Free"
      assert data.payment.reference_id == "N/A"
      assert data.payment.external_payment_id == "N/A"
      assert data.payment_date == "N/A"
    end

    test "event with no start_date shows TBD for event_date_time" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      event = event_fixture()

      {:ok, free_tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Complimentary",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 20,
          event_id: event.id
        })

      {:ok, ticket_order} =
        Tickets.create_ticket_order(user.id, event.id, %{free_tier.id => 1})

      {:ok, completed} = Tickets.process_free_ticket_order(ticket_order)

      event
      |> Ecto.Changeset.change(%{start_date: nil})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(completed.id)
        )

      assert data.event_date_time == "TBD"
    end

    test "includes agenda sections when event has agendas", %{
      ticket_order: ticket_order
    } do
      event = ticket_order.event

      {:ok, agenda} =
        %Agenda{}
        |> Agenda.changeset(%{event_id: event.id, title: "Day 1"})
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      {:ok, _} =
        %AgendaItem{}
        |> AgendaItem.changeset(%{
          agenda_id: agenda.id,
          title: "Doors",
          description: "Open",
          start_time: ~T[09:00:00],
          end_time: ~T[09:30:00]
        })
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert length(data.agenda) == 1
      [section] = data.agenda
      assert section.title == "Day 1"
      assert length(section.items) == 1
      [item] = section.items
      assert item.title == "Doors"
      assert item.start_time =~ "09:00"
    end

    test "agenda section with no items still appears with empty items", %{
      ticket_order: ticket_order
    } do
      event = ticket_order.event

      {:ok, _} =
        %Agenda{}
        |> Agenda.changeset(%{event_id: event.id, title: "Empty day"})
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert [_section] = data.agenda

      assert Enum.any?(
               data.agenda,
               &(&1.title == "Empty day" and &1.items == [])
             )
    end

    test "raises when ticket order has no tickets" do
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

      Repo.delete_all(
        from(t in Ysc.Events.Ticket,
          where: t.ticket_order_id == ^ticket_order.id
        )
      )

      assert_raise ArgumentError, fn ->
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )
      end
    end
  end

  describe "prepare_email_data/1 with donation tier" do
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
          title: "Purchase donation #{System.unique_integer([:positive])}",
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
          price: Money.new(25, :USD),
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

      ticket_selections = %{paid_tier.id => 1, donation_tier.id => 2_500}

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
            "pi_tpc_don_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(200, :USD),
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

      %{ticket_order: Tickets.get_ticket_order(ticket_order.id)}
    end

    test "builds donation tier summaries", %{ticket_order: ticket_order} do
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      donation_row =
        Enum.find(data.ticket_summaries, &(&1.ticket_tier_name == "Donation"))

      assert donation_row
      assert donation_row.quantity == 1
    end

    test "render/1 produces HTML", %{ticket_order: ticket_order} do
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)
      html = TicketPurchaseConfirmation.render(data)

      assert is_binary(html)
      assert html =~ "ticket" or html =~ "Ticket" or html =~ "confirm"
    end
  end

  describe "URL helpers" do
    test "get_template_name, get_subject, event_url, tickets_qr_url" do
      assert TicketPurchaseConfirmation.get_template_name() ==
               "ticket_purchase_confirmation"

      assert TicketPurchaseConfirmation.get_subject() =~ "confirmed"

      id = Ecto.ULID.generate()
      assert TicketPurchaseConfirmation.event_url(id) =~ "/events/#{id}"

      assert TicketPurchaseConfirmation.tickets_qr_url(id) =~
               "/tickets/#{id}/qr"
    end
  end

  describe "prepare_email_data/1 template branches" do
    setup do
      Ledgers.ensure_basic_accounts()

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
            "pi_tpc_branch_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: completed_at
        })
        |> Repo.update!()

      %{ticket_order: Tickets.get_ticket_order(ticket_order.id)}
    end

    test "renders age restriction when event has age_restriction > 0", %{
      ticket_order: ticket_order
    } do
      ticket_order.event
      |> Ecto.Changeset.change(%{age_restriction: 21})
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      html = TicketPurchaseConfirmation.render(data)
      assert html =~ "Age Restriction"
      assert html =~ "21"
    end

    test "renders multiple agenda sections with section titles when multiple agendas",
         %{
           ticket_order: ticket_order
         } do
      event = ticket_order.event

      {:ok, a1} =
        %Agenda{}
        |> Agenda.changeset(%{event_id: event.id, title: "Morning"})
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      {:ok, _} =
        %AgendaItem{}
        |> AgendaItem.changeset(%{
          agenda_id: a1.id,
          title: "Coffee",
          description: nil,
          start_time: ~T[09:00:00],
          end_time: nil
        })
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      {:ok, a2} =
        %Agenda{}
        |> Agenda.changeset(%{event_id: event.id, title: "Afternoon"})
        |> Ecto.Changeset.put_change(:position, 1)
        |> Repo.insert()

      {:ok, _} =
        %AgendaItem{}
        |> AgendaItem.changeset(%{
          agenda_id: a2.id,
          title: "Talk",
          description: "Details",
          start_time: ~T[14:00:00],
          end_time: ~T[15:00:00]
        })
        |> Ecto.Changeset.put_change(:position, 0)
        |> Repo.insert()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order(ticket_order.id)
        )

      assert length(data.agenda) == 2
      html = TicketPurchaseConfirmation.render(data)
      assert html =~ "Morning"
      assert html =~ "Afternoon"
      assert html =~ "Coffee"
    end
  end

  describe "prepare_email_data/1 discount and template edge cases" do
    import Swoosh.TestAssertions

    setup do
      Ledgers.ensure_basic_accounts()

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
            "pi_tpc_disc_#{System.unique_integer([:positive])}",
          stripe_fee: Money.new(320, :USD),
          description: "Event tickets",
          payment_method_id: nil
        })

      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      ticket_order =
        ticket_order
        |> Ecto.Changeset.change(%{
          payment_id: payment.id,
          completed_at: completed_at,
          discount_amount: nil
        })
        |> Repo.update!()

      disc = Money.new(100, :USD)

      [t] =
        ticket_order
        |> Ecto.assoc(:tickets)
        |> Repo.all()

      t
      |> Ecto.Changeset.change(discount_amount: disc)
      |> Repo.update!()

      %{ticket_order: Tickets.get_ticket_order(ticket_order.id)}
    end

    test "uses sum of per-ticket discounts when order discount_amount is nil",
         %{
           ticket_order: ticket_order
         } do
      data = TicketPurchaseConfirmation.prepare_email_data(ticket_order)

      assert data.has_discounts
      assert data.total_discount =~ "$100.00"
      assert_no_email_sent()
    end
  end
end
