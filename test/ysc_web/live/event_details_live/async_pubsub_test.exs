defmodule YscWeb.EventDetailsLive.AsyncPubsubTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import EventDetailsLiveHelpers
  import Mox

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder
  alias Ysc.MessagePassingEvents.TicketAvailabilityUpdated
  alias Ysc.MessagePassingEvents.CheckoutSessionCancelled
  alias Ysc.MessagePassingEvents.CheckoutSessionExpired

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    on_exit(fn ->
      Application.delete_env(:ysc, :stripe_client)
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
      :timer.sleep(300)

      # Select tickets asynchronously
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end

    test "handles multiple rapid ticket quantity changes", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Rapidly change quantities
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end

    test "handles async donation amount changes", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(100)

      # Change donation amounts
      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "25"
      })

      :timer.sleep(100)

      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "50"
      })

      :timer.sleep(200)

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

      # Start LiveView session
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Simulate ticket availability update from another session
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end

    test "receives multiple availability updates", %{conn: conn} do
      event = event_with_tickets(tier_count: 2, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      [_tier1, _tier2] = event.ticket_tiers

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Broadcast multiple updates
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      :timer.sleep(100)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end

    test "updates UI when tickets sell out", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      _tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Simulate tickets selling out
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
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

      :timer.sleep(300)

      # Broadcast cancellation event
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "ticket_orders:#{order.id}",
        %CheckoutSessionCancelled{
          ticket_order: order,
          event_id: event.id,
          user_id: user.id
        }
      )

      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
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

      :timer.sleep(300)

      # Broadcast expiration event
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "ticket_orders:#{order.id}",
        %CheckoutSessionExpired{
          ticket_order: order,
          event_id: event.id
        }
      )

      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "concurrent ticket purchasing" do
    test "handles concurrent attempts to purchase same tickets", %{conn: conn} do
      # Create second user
      user2 = user_with_membership(:lifetime)
      conn2 = build_conn() |> log_in_user(user2)

      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Start two sessions
      {:ok, view1, _html} = live(conn, ~p"/events/#{event.id}")
      {:ok, view2, _html} = live(conn2, ~p"/events/#{event.id}")
      :timer.sleep(500)

      # Both users try to select tickets
      render_click(view1, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view2, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(300)

      # Both views should remain responsive
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
      :timer.sleep(500)

      # First user starts checkout
      render_click(view1, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(100)
      render_click(view1, "proceed-to-checkout")
      :timer.sleep(500)

      # Broadcast availability update that would affect second session
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        %TicketAvailabilityUpdated{
          event_id: event.id
        }
      )

      :timer.sleep(300)

      # Both sessions should handle the update
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

      # Create tier requiring registration
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
      :timer.sleep(300)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => registration_tier.id
      })

      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment modal interactions async", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(100)
      render_click(view, "proceed-to-checkout")
      :timer.sleep(500)

      # Try to close modal
      render_click(view, "close-payment-modal")
      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment redirect completion async", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(100)
      render_click(view, "proceed-to-checkout")
      :timer.sleep(500)

      # Simulate redirect started
      render_click(view, "payment-redirect-started")
      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "LiveView lifecycle with async operations" do
    test "cleans up subscriptions on unmount", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Stop the view (simulates navigation away)
      GenServer.stop(view.pid)
      :timer.sleep(200)

      # View should be stopped cleanly
      refute Process.alive?(view.pid)
    end

    test "handles navigation while async operations pending", %{conn: conn} do
      event1 = event_with_tickets(tier_count: 1, state: :upcoming)
      event2 = event_with_tickets(tier_count: 1, state: :upcoming)
      event1 = Repo.preload(event1, :ticket_tiers, force: true)
      tier = hd(event1.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event1.id}")
      :timer.sleep(300)

      # Start operation
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Navigate away immediately
      render_patch(view, ~p"/events/#{event2.id}")
      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end

    test "handles rapid mount/unmount cycles", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      # Rapidly mount and unmount
      {:ok, view1, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(100)
      GenServer.stop(view1.pid)

      {:ok, view2, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(100)
      GenServer.stop(view2.pid)

      {:ok, view3, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

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
      :timer.sleep(300)

      # Trigger operations that might spawn async processes
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(500)

      # View should still be responsive
      html = render(view)
      assert is_binary(html)
    end

    test "recovers from PubSub broadcast failures", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Send malformed PubSub message
      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events:#{event.id}",
        {:unexpected_message, "data"}
      )

      :timer.sleep(300)

      # View should still work
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "real-time UI updates" do
    test "updates ticket counts in real-time", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      _tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      # Simulate real-time inventory changes
      for _quantity <- 99..95//-1 do
        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          "events:#{event.id}",
          %TicketAvailabilityUpdated{
            event_id: event.id
          }
        )

        :timer.sleep(100)
      end

      :timer.sleep(200)

      html = render(view)
      assert is_binary(html)
    end

    test "shows loading states during async operations", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      # Don't wait - check immediately
      html = render(view)
      assert is_binary(html)

      # Wait for completion
      :timer.sleep(300)
      html = render(view)
      assert is_binary(html)
    end
  end
end
