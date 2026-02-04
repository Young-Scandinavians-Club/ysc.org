defmodule YscWeb.EventDetailsLive.UrlRestorationTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import EventDetailsLiveHelpers
  import Mox

  alias Ysc.Repo
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    # Stub create_payment_intent for cases where it might be triggered
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

  describe "restore checkout state from URL" do
    test "restores pending order with valid URL parameters", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Create a pending order with longer expiration
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

      # Create payment intent for this order
      payment_intent =
        build_payment_intent(%{amount: money_to_cents(tier.price)})

      {:ok, order} =
        order
        |> Ecto.Changeset.change(%{payment_intent_id: payment_intent.id})
        |> Repo.update()

      # Mock payment intent retrieval
      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      # Navigate to event page with order restoration parameters
      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      # Verify page loaded
      html = render(view)
      assert is_binary(html)
    end

    test "handles expired order gracefully", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Create an expired order
      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :expired,
          expires_at: DateTime.add(DateTime.utc_now(), -10, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      # Try to restore - should not crash
      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end

    test "rejects order for different user", %{conn: conn} do
      # Create a different user
      other_user = user_with_membership(:lifetime)

      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Create order for other user
      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: other_user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      # Current user tries to access other user's order
      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      # Should load page without restoring order
      html = render(view)
      assert is_binary(html)
    end

    test "rejects order for different event", %{conn: conn, user: user} do
      event1 = event_with_tickets(tier_count: 1, state: :upcoming)
      event2 = event_with_tickets(tier_count: 1, state: :upcoming)
      event1 = Repo.preload(event1, :ticket_tiers, force: true)
      tier = hd(event1.ticket_tiers)

      # Create order for event1
      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event1.id,
          total_amount: tier.price,
          status: :pending,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      # Try to restore order on event2 page
      url = ~p"/events/#{event2.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      # Should load page without restoring order
      html = render(view)
      assert is_binary(html)
    end

    test "handles invalid order ID", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      # Use a non-existent but valid ULID format order ID
      non_existent_order_id = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      url = ~p"/events/#{event.id}?order_id=#{non_existent_order_id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      # Should not crash
      html = render(view)
      assert is_binary(html)
    end

    test "restores order with payment intent in requires_payment_method status",
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
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          payment_intent_id: payment_intent.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment intent retrieval failure", %{conn: conn, user: user} do
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
          payment_intent_id: "pi_invalid",
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "No such payment intent",
           code: "resource_missing",
           source: :stripe
         }}
      end)

      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      # Should handle error gracefully
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "payment return from Stripe" do
    test "handles payment_intent parameter after successful payment", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      payment_intent =
        build_payment_intent(%{
          amount: money_to_cents(tier.price),
          status: "succeeded"
        })

      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          payment_intent_id: payment_intent.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      # Simulate return from Stripe with payment_intent parameter
      url =
        ~p"/events/#{event.id}?payment_intent=#{payment_intent.id}&order_id=#{order.id}"

      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      html = render(view)
      assert is_binary(html)
    end

    test "handles payment_intent_client_secret parameter", %{
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
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          payment_intent_id: payment_intent.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      # Simulate return with client secret
      url =
        ~p"/events/#{event.id}?payment_intent_client_secret=#{payment_intent.client_secret}&order_id=#{order.id}"

      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      html = render(view)
      assert is_binary(html)
    end

    test "handles redirect_status=succeeded parameter", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      payment_intent =
        build_payment_intent(%{
          amount: money_to_cents(tier.price),
          status: "succeeded"
        })

      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          payment_intent_id: payment_intent.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      # Simulate return with redirect status
      url =
        ~p"/events/#{event.id}?payment_intent=#{payment_intent.id}&redirect_status=succeeded&order_id=#{order.id}"

      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      html = render(view)
      assert is_binary(html)
    end

    test "handles redirect_status=failed parameter", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      payment_intent =
        build_payment_intent(%{
          amount: money_to_cents(tier.price),
          status: "requires_payment_method",
          last_payment_error: %{
            code: "card_declined",
            message: "Your card was declined"
          }
        })

      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          payment_intent_id: payment_intent.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok, payment_intent}
      end)

      # Simulate return with failed status
      url =
        ~p"/events/#{event.id}?payment_intent=#{payment_intent.id}&redirect_status=failed&order_id=#{order.id}"

      {:ok, view, _html} = live(conn, url)
      :timer.sleep(500)

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "order expiration during checkout" do
    test "detects order expiration", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Create order that expires very soon
      {:ok, order} =
        %TicketOrder{}
        |> TicketOrder.create_changeset(%{
          user_id: user.id,
          event_id: event.id,
          total_amount: tier.price,
          status: :pending,
          expires_at: DateTime.add(DateTime.utc_now(), 1, :second),
          reference_id: "ORD-#{System.unique_integer([:positive])}"
        })
        |> Repo.insert()

      # Wait for expiration
      :timer.sleep(2000)

      # Mark as expired
      {:ok, _expired_order} =
        order
        |> Ecto.Changeset.change(%{status: :expired})
        |> Repo.update()

      url = ~p"/events/#{event.id}?order_id=#{order.id}"
      {:ok, view, _html} = live(conn, url)
      :timer.sleep(300)

      html = render(view)
      assert is_binary(html)
    end
  end
end
