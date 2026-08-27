defmodule YscWeb.AdminTicketListLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketDetail
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  # Inserts a confirmed ticket. When `user_id` is present, also creates a
  # matching TicketOrder (as real tickets always have) so the ticket renders
  # inside an order group; pass `user_id: nil` to exercise the orphaned
  # "no order" fallback.
  defp insert_confirmed_ticket(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    order_id =
      if attrs.user_id do
        insert_ticket_order!(attrs).id
      end

    %Ticket{
      id: Ecto.ULID.generate(),
      event_id: attrs.event_id,
      ticket_tier_id: attrs.ticket_tier_id,
      ticket_order_id: order_id,
      user_id: attrs.user_id,
      status: :confirmed,
      inserted_at: Map.get(attrs, :inserted_at, now),
      expires_at: DateTime.add(now, 1, :day)
    }
    |> Repo.insert!()
  end

  defp insert_ticket_order!(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tier = Events.get_ticket_tier!(attrs.ticket_tier_id)

    %TicketOrder{}
    |> TicketOrder.admin_grant_changeset(
      %{
        user_id: attrs.user_id,
        event_id: attrs.event_id,
        total_amount: tier.price || Money.new(0, :USD),
        expires_at: DateTime.add(now, 1, :day),
        completed_at: Map.get(attrs, :inserted_at, now)
      },
      attrs.user_id
    )
    |> Repo.insert!()
  end

  defp completed_ticket_order_with_payment!(opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
    user = Keyword.get_lazy(opts, :user, fn -> user_fixture() end)

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    event = Keyword.get_lazy(opts, :event, fn -> event_fixture() end)

    tier =
      Keyword.get_lazy(opts, :tier, fn ->
        ticket_tier_fixture(%{event_id: event.id})
      end)

    {:ok, order} =
      Tickets.create_ticket_order(user.id, event.id, %{tier.id => quantity})

    {:ok, {payment, _transaction, _entries}} =
      Ledgers.process_event_payment_with_donations(%{
        user_id: user.id,
        total_amount: order.total_amount,
        event_amount: order.total_amount,
        donation_amount: Money.new(0, :USD),
        event_id: event.id,
        external_payment_id:
          "pi_admin_ticket_list_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(320, :USD),
        description: "Event tickets",
        payment_method_id: nil
      })

    {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)

    import Ecto.Query

    from(t in Ticket, where: t.ticket_order_id == ^order.id)
    |> Repo.update_all(set: [status: :confirmed])

    tickets =
      from(t in Ticket, where: t.ticket_order_id == ^order.id, order_by: t.id)
      |> Repo.all()

    %{
      user: user,
      event: event,
      payment: payment,
      ticket_order: completed,
      tickets: tickets
    }
  end

  defp order_index(html, order_id) do
    :binary.match(html, "ticket-order-#{order_id}") |> elem(0)
  end

  describe "order grouping" do
    setup [:create_admin]

    test "groups tickets under their order, showing purchaser, ref, count, total, and date",
         %{conn: conn} do
      %{event: event, ticket_order: order, tickets: [ticket]} =
        completed_ticket_order_with_payment!()

      buyer = Repo.get!(Ysc.Accounts.User, order.user_id)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(
               view,
               "#ticket-order-#{order.id}",
               "#{buyer.first_name} #{buyer.last_name}"
             )

      assert has_element?(view, "#ticket-order-#{order.id}", order.reference_id)
      assert has_element?(view, "#ticket-order-#{order.id}", "1 ticket")

      assert has_element?(
               view,
               "#ticket-order-#{order.id}",
               Money.to_string!(order.total_amount)
             )

      assert has_element?(view, "#ticket-row-#{ticket.id}")
    end

    test "renders an orphaned ticket with no order under a 'No order' group", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-order-", "No order")
      assert has_element?(view, "#ticket-row-#{ticket.id}", "Add name & email")
    end
  end

  describe "collapsing an order" do
    setup [:create_admin]

    test "hides and reveals its ticket rows, expanded by default", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture()

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-row-#{ticket.id}")

      view
      |> element(
        "#ticket-order-toggle-#{Repo.get!(Ticket, ticket.id).ticket_order_id}"
      )
      |> render_click()

      refute has_element?(view, "#ticket-row-#{ticket.id}")

      view
      |> element(
        "#ticket-order-toggle-#{Repo.get!(Ticket, ticket.id).ticket_order_id}"
      )
      |> render_click()

      assert has_element?(view, "#ticket-row-#{ticket.id}")
    end

    test "collapses the orphaned 'No order' group, whose toggle has no id", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-row-#{ticket.id}")

      view |> element("#ticket-order-toggle-") |> render_click()
      refute has_element?(view, "#ticket-row-#{ticket.id}")

      view |> element("#ticket-order-toggle-") |> render_click()
      assert has_element?(view, "#ticket-row-#{ticket.id}")
    end
  end

  describe "sorting orders by purchase date" do
    setup [:create_admin]

    test "toggles between newest-first and oldest-first", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      older_ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user_fixture().id,
          inserted_at: ~U[2026-08-01 10:00:00Z]
        })

      newer_ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user_fixture().id,
          inserted_at: ~U[2026-08-10 10:00:00Z]
        })

      {:ok, view, html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      older_order_id = Repo.get!(Ticket, older_ticket.id).ticket_order_id
      newer_order_id = Repo.get!(Ticket, newer_ticket.id).ticket_order_id

      assert order_index(html, newer_order_id) <
               order_index(html, older_order_id)

      html =
        view
        |> element("#ticket-orders-sort-purchased")
        |> render_click()

      assert order_index(html, older_order_id) <
               order_index(html, newer_order_id)
    end
  end

  describe "ticket tier badge" do
    setup [:create_admin]

    test "renders the tier name as a badge", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id, name: "VIP Pass"})
      buyer = user_fixture()

      insert_confirmed_ticket(%{
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: buyer.id
      })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "span.inline-block", "VIP Pass")
    end
  end

  describe "per-ticket amount" do
    setup [:create_admin]

    test "shows each ticket's price so the rows add up to the order total", %{
      conn: conn
    } do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{event_id: event.id, price: Money.new(50, :USD)})

      %{ticket_order: order, tickets: tickets} =
        completed_ticket_order_with_payment!(
          event: event,
          tier: tier,
          quantity: 2
        )

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      for ticket <- tickets do
        assert has_element?(
                 view,
                 "#ticket-row-#{ticket.id}",
                 Money.to_string!(tier.price)
               )
      end

      assert has_element?(
               view,
               "#ticket-order-#{order.id}",
               Money.to_string!(order.total_amount)
             )
    end

    test "shows the reservation discount and the discounted price on the ticket",
         %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})

      tier =
        ticket_tier_fixture(%{event_id: event.id, price: Money.new(50, :USD)})

      buyer = user_fixture()

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      Repo.get!(Ticket, ticket.id)
      |> Ecto.Changeset.change(discount_amount: Money.new(20, :USD))
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      assert has_element?(view, "#ticket-row-#{ticket.id}", "-$20.00")
      # net price after the $20 reservation discount comes off the $50 tier
      assert has_element?(view, "#ticket-row-#{ticket.id}", "$30.00")
    end
  end

  describe "row action menu direction" do
    setup [:create_admin]

    test "opens upward only for the very last ticket row, downward for the rest",
         %{
           conn: conn,
           admin: admin
         } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      first_ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user_fixture().id,
          inserted_at: ~U[2026-08-01 10:00:00Z]
        })

      last_ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user_fixture().id,
          inserted_at: ~U[2026-08-10 10:00:00Z]
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Newest-first sort, so last_ticket's order renders first and
      # first_ticket's order renders last on the page.
      assert has_element?(view, "#ticket-actions-#{last_ticket.id}.mt-1")
      refute has_element?(view, "#ticket-actions-#{last_ticket.id}.bottom-full")

      assert has_element?(
               view,
               "#ticket-actions-#{first_ticket.id}.bottom-full"
             )

      refute has_element?(view, "#ticket-actions-#{first_ticket.id}.mt-1")
    end
  end

  describe "attendee info" do
    setup [:create_admin]

    test "shows the purchaser as attendee by default and lets admin override it",
         %{
           conn: conn,
           admin: admin
         } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture()

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # No separate registration was collected, so the attendee shown is the
      # purchaser (matches the CSV export's fallback) rather than a blank
      # "missing info" state.
      assert has_element?(
               view,
               "#ticket-row-#{ticket.id}",
               "#{buyer.first_name} #{buyer.last_name}"
             )

      assert has_element?(view, "#ticket-row-#{ticket.id}", buyer.email)

      assert has_element?(
               view,
               "#ticket-actions-#{ticket.id}-edit",
               "Add attendee info"
             )

      view
      |> element("#ticket-actions-#{ticket.id}-edit")
      |> render_click()

      assert has_element?(view, "#ticket-detail-form")

      view
      |> form("#ticket-detail-form", %{
        "ticket_detail" => %{
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "email" => "ada@example.com"
        }
      })
      |> render_submit()

      refute has_element?(view, "#ticket-detail-form")
      assert has_element?(view, "#ticket-row-#{ticket.id}", "Ada Lovelace")
      assert has_element?(view, "#ticket-row-#{ticket.id}", "ada@example.com")

      assert Repo.get_by!(TicketDetail, ticket_id: ticket.id).first_name ==
               "Ada"
    end

    test "edits existing attendee info", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture()

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, _registration} =
        Ysc.Events.create_registration(%{
          "ticket_id" => ticket.id,
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "email" => "ada@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-edit")
      |> render_click()

      view
      |> form("#ticket-detail-form", %{
        "ticket_detail" => %{
          "first_name" => "Grace",
          "last_name" => "Hopper",
          "email" => "grace@example.com"
        }
      })
      |> render_submit()

      assert has_element?(view, "#ticket-row-#{ticket.id}", "Grace Hopper")
      refute has_element?(view, "#ticket-row-#{ticket.id}", "Ada Lovelace")
    end
  end

  describe "reassign ticket" do
    setup [:create_admin]

    test "moves the ticket to a different member and flags it as reassigned", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture(%{first_name: "Original", last_name: "Owner"})

      new_owner =
        user_fixture(%{
          first_name: "New",
          last_name: "Owner",
          email: "new-owner-#{System.unique_integer([:positive])}@example.com"
        })

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-reassign")
      |> render_click()

      assert has_element?(view, "#reassign-ticket-modal")

      view
      |> element("#ticket-reassign-user-autocomplete-input")
      |> render_keyup(%{"value" => new_owner.email})

      view
      |> element(
        "#ticket-reassign-user-autocomplete button[phx-click='select-user'][phx-value-id='#{new_owner.id}']"
      )
      |> render_click()

      view
      |> element("button[phx-click='confirm-reassign']")
      |> render_click()

      refute has_element?(view, "#reassign-ticket-modal")
      assert Repo.get!(Ticket, ticket.id).user_id == new_owner.id

      assert has_element?(
               view,
               "#ticket-row-#{ticket.id}",
               "Reassigned to New Owner"
             )
    end

    test "refuses to reassign a ticket to its current holder", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture(%{first_name: "Same", last_name: "Owner"})

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-reassign")
      |> render_click()

      view
      |> element("#ticket-reassign-user-autocomplete-input")
      |> render_keyup(%{"value" => buyer.email})

      view
      |> element(
        "#ticket-reassign-user-autocomplete button[phx-click='select-user'][phx-value-id='#{buyer.id}']"
      )
      |> render_click()

      view
      |> element("button[phx-click='confirm-reassign']")
      |> render_click()

      assert has_element?(view, "#reassign-ticket-modal")
      assert Repo.get!(Ticket, ticket.id).user_id == buyer.id
    end
  end

  describe "refund ticket" do
    setup [:create_admin]

    test "refunds a single ticket and releases stock", %{conn: conn} do
      %{event: event, ticket_order: order, tickets: [ticket]} =
        completed_ticket_order_with_payment!()

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-refund")
      |> render_click()

      assert has_element?(view, "#refund-ticket-modal")

      view
      |> form("#refund-ticket-form", %{"reason" => "Customer request"})
      |> render_submit()

      refute has_element?(view, "#refund-ticket-modal")
      assert Repo.get!(Ticket, ticket.id).status == :cancelled
      assert Repo.get!(TicketOrder, order.id).status == :cancelled
    end

    test "does not refund an orphaned ticket with no order", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: nil
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-refund")
      |> render_click()

      refute has_element?(view, "#refund-ticket-modal")
      assert Repo.get!(Ticket, ticket.id).status == :confirmed
    end

    test "does not refund a grant order that has no Stripe payment", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      tier = ticket_tier_fixture(%{event_id: event.id})
      buyer = user_fixture()

      ticket =
        insert_confirmed_ticket(%{
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: buyer.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      view
      |> element("#ticket-actions-#{ticket.id}-refund")
      |> render_click()

      assert has_element?(view, "#refund-ticket-modal")

      view
      |> form("#refund-ticket-form", %{"reason" => "Complimentary"})
      |> render_submit()

      assert has_element?(view, "#refund-ticket-modal")
      assert Repo.get!(Ticket, ticket.id).status == :confirmed
    end
  end
end
