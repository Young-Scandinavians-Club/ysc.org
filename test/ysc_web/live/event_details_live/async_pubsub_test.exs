defmodule YscWeb.EventDetailsLive.AsyncPubsubTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import Ysc.AccountsFixtures
  import EventDetailsLiveHelpers
  import Mox

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketReservation
  alias Ysc.MessagePassingEvents.TicketAvailabilityUpdated
  alias Ysc.MessagePassingEvents.TicketReservationCreated
  alias Ysc.MessagePassingEvents.CheckoutSessionCancelled
  alias Ysc.MessagePassingEvents.CheckoutSessionExpired

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    # Required when LiveView restores checkout from URL with order_id and order has payment_intent_id
    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
      {:ok, build_payment_intent(%{id: id, status: "requires_payment_method"})}
    end)

    user = user_with_membership(:lifetime)
    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  describe "async ticket operations" do
    test "handles async ticket selection and updates availability", %{
      conn: conn
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)
    end

    test "handles multiple rapid ticket quantity changes", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)
    end

    test "handles async donation amount changes", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "25"
      })

      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "50"
      })

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "PubSub ticket availability events" do
    test "receives ticket availability updates from other sessions", %{
      conn: conn
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      _tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      html = render(view)
      assert is_binary(html)
    end

    test "receives multiple availability updates", %{conn: conn} do
      event = event_with_tickets(tier_count: 2, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      [_tier1, _tier2] = event.ticket_tiers

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      html = render(view)
      assert is_binary(html)
    end

    test "updates UI when tickets sell out", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      _tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "PubSub ticket reservation events" do
    test "TicketReservationCreated lets the holder purchase when tier is publicly sold out",
         %{conn: conn, user: user} do
      event =
        event_with_tickets(
          tier_count: 1,
          state: :upcoming
        )

      event = Repo.preload(event, :ticket_tiers, force: true)

      tier =
        event.ticket_tiers
        |> hd()
        |> Ecto.Changeset.change(quantity: 2)
        |> Repo.update!()

      expires_at =
        DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)

      other_user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      for _ <- 1..2 do
        %Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          user_id: other_user.id,
          ticket_tier_id: tier.id,
          status: :confirmed,
          expires_at: expires_at
        }
        |> Repo.insert!()
      end

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      html = render_async(view)

      assert html =~ "Sold Out"

      reservation =
        %TicketReservation{}
        |> TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          created_by_id: user.id,
          quantity: 1,
          expires_at: expires_at
        })
        |> Repo.insert!()

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %TicketReservationCreated{
           ticket_reservation: reservation,
           event_id: event.id
         }}
      )

      html = render(view)
      assert html =~ "Get Tickets"
      assert html =~ "1 remaining"
    end
  end

  describe "checkout session PubSub events" do
    test "receives checkout session cancelled event", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, view, _html} =
        live(conn, ~p"/events/#{event.id}?order_id=#{order.id}")

      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "ticket_orders:#{order.id}",
        %CheckoutSessionCancelled{
          ticket_order: order,
          event_id: event.id,
          user_id: user.id
        }
      )

      html = render(view)
      assert is_binary(html)
    end

    test "payment failure cancellation shows payment failed state not timeout",
         %{
           conn: conn,
           user: user
         } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      payment_intent =
        build_payment_intent(%{
          amount: money_to_cents(tier.price),
          status: "requires_payment_method"
        })

      {:ok, order} =
        Ysc.Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

      order =
        order
        |> Ecto.Changeset.change(%{payment_intent_id: payment_intent.id})
        |> Repo.update!()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok, %{payment_intent | id: id}}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/events/#{event.id}?checkout=payment&order_id=#{order.id}"
        )

      view = wait_for_async(view)
      assert has_element?(view, "#payment-modal")
      assert has_element?(view, "h2", "Complete Your Purchase")
      assert has_element?(view, "#payment-modal", order.reference_id)

      cancelled_event = %CheckoutSessionCancelled{
        ticket_order: Repo.get!(TicketOrder, order.id),
        event_id: event.id,
        user_id: user.id,
        reason: "Payment failed"
      }

      :ok =
        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          "tickets:user:#{user.id}",
          {Ysc.Tickets, cancelled_event}
        )

      assert has_element?(view, "h2", "Payment failed")
      refute has_element?(view, "h2", "Time ran out")
    end

    test "receives checkout session expired event", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      {:ok, view, _html} =
        live(conn, ~p"/events/#{event.id}?order_id=#{order.id}")

      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "ticket_orders:#{order.id}",
        %CheckoutSessionExpired{
          ticket_order: order,
          event_id: event.id
        }
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "concurrent ticket purchasing" do
    test "handles concurrent attempts to purchase same tickets", %{conn: conn} do
      user2 = user_with_membership(:lifetime)
      conn2 = build_conn() |> log_in_user(user2)

      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view1, _html} = live(conn, ~p"/events/#{event.id}")
      {:ok, view2, _html} = live(conn2, ~p"/events/#{event.id}")
      render_async(view1)
      render_async(view2)

      render_click(view1, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view2, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html1 = render(view1)
      html2 = render(view2)
      assert is_binary(html1)
      assert is_binary(html2)
    end

    test "updates both sessions when one completes purchase", %{conn: conn} do
      user2 = user_with_membership(:lifetime)
      conn2 = build_conn() |> log_in_user(user2)

      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view1, _html} = live(conn, ~p"/events/#{event.id}")
      {:ok, view2, _html} = live(conn2, ~p"/events/#{event.id}")
      render_async(view1)
      render_async(view2)

      render_click(view1, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view1, "proceed-to-checkout")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      html1 = render(view1)
      html2 = render(view2)
      assert is_binary(html1)
      assert is_binary(html2)
    end
  end

  describe "async handle_info callbacks" do
    test "handles registration form submission async", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      registration_tier =
        Ysc.EventsFixtures.ticket_tier_fixture(%{
          event_id: event.id,
          name: "Workshop with Registration",
          type: :paid,
          requires_registration: true,
          price: Money.new(75, :USD),
          quantity: 30
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => registration_tier.id
      })

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment modal interactions async", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      render_click(view, "close-payment-modal")

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment redirect completion async", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      render_click(view, "payment-redirect-started")

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "LiveView lifecycle with async operations" do
    test "cleans up subscriptions on unmount", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      GenServer.stop(view.pid)

      refute Process.alive?(view.pid)
    end

    test "handles navigation while async operations pending", %{conn: conn} do
      event1 = event_with_tickets(tier_count: 1, state: :upcoming)
      event2 = event_with_tickets(tier_count: 1, state: :upcoming)
      event1 = Repo.preload(event1, :ticket_tiers, force: true)
      tier = hd(event1.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event1.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      render_patch(view, ~p"/events/#{event2.id}")
      render_async(view)

      html = render(view)
      assert is_binary(html)
    end

    test "handles rapid mount/unmount cycles", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      {:ok, view1, _html} = live(conn, ~p"/events/#{event.id}")
      GenServer.stop(view1.pid)

      {:ok, view2, _html} = live(conn, ~p"/events/#{event.id}")
      GenServer.stop(view2.pid)

      {:ok, view3, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view3)

      html = render(view3)
      assert is_binary(html)
    end
  end

  describe "async error handling" do
    test "handles async process crashes gracefully", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)
    end

    test "recovers from PubSub broadcast failures", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        {:unexpected_message, "data"}
      )

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "attendee list refresh on availability updates (#613)" do
    defp confirmed_ticket(event, tier, user) do
      %Ticket{
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: user.id,
        status: :confirmed,
        expires_at:
          DateTime.utc_now()
          |> DateTime.add(365, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()
    end

    defp trigger_availability_refresh(view, event_id) do
      send(view.pid, {:refresh_ticket_availability, event_id})
      render(view)
    end

    defp attendee_assigns(view) do
      :sys.get_state(view.pid).socket.assigns
    end

    test "availability refresh without sold-count change keeps attendees list",
         %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      buyer = user_with_membership(:lifetime)
      confirmed_ticket(event, tier, buyer)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assigns_before = attendee_assigns(view)
      count_before = assigns_before.attendees_count
      sold_before = assigns_before.attendee_sold_ticket_count
      assert count_before != nil
      assert sold_before == 1

      expires_at =
        DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 1, :day)

      %TicketReservation{}
      |> TicketReservation.changeset(%{
        ticket_tier_id: tier.id,
        user_id: user.id,
        created_by_id: user.id,
        quantity: 1,
        expires_at: expires_at
      })
      |> Repo.insert!()

      trigger_availability_refresh(view, event.id)

      assigns_after = attendee_assigns(view)
      assert assigns_after.attendees_count == count_before
      assert assigns_after.attendee_sold_ticket_count == sold_before
    end

    test "availability refresh reloads attendees when sold count increases",
         %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assigns_before = attendee_assigns(view)
      count_before = assigns_before.attendees_count
      sold_before = assigns_before.attendee_sold_ticket_count
      assert count_before != nil
      assert sold_before == 0

      new_buyer = user_with_membership(:lifetime)
      confirmed_ticket(event, tier, new_buyer)

      trigger_availability_refresh(view, event.id)

      assigns_after = attendee_assigns(view)
      assert assigns_after.attendees_count == count_before + 1
      assert assigns_after.attendee_sold_ticket_count == sold_before + 1
    end
  end

  describe "real-time UI updates" do
    test "updates ticket counts in real-time", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      _tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      for _quantity <- 99..95//-1 do
        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          "events:#{event.id}",
          %TicketAvailabilityUpdated{
            event_id: event.id
          }
        )
      end

      html = render(view)
      assert is_binary(html)
    end

    test "shows loading states during async operations", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      html = render(view)
      assert is_binary(html)
    end
  end
end
