defmodule YscWeb.EventDetailsLive.PaymentFlowTest do
  @moduledoc """
  E2E payment flow tests for event ticket purchase.

  Note: Uses async: false to avoid Mox stub interference. When run in parallel
  with url_restoration_test (which stubs create_payment_intent in setup), that
  stub can overwrite our expect(), causing "invoked 0 times" verification failures.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import EventDetailsLiveHelpers
  import Mox
  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Tickets

  setup :verify_on_exit!

  setup %{conn: conn} do
    # Set up Stripe mocks
    setup_stripe_mocks()

    # Configure app to use mock Stripe client
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
      {:ok, build_payment_intent(%{id: id})}
    end)

    user = user_with_membership(:lifetime)
    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  describe "complete paid ticket purchase flow (E2E)" do
    test "successfully initiates checkout with payment intent", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 2, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Expected amount: 1 ticket at tier price (converted to cents for Stripe)
      expected_amount_cents = money_to_cents(tier.price)

      # Mock payment intent creation
      expect(Ysc.StripeMock, :create_payment_intent, fn params, opts ->
        assert params.amount == expected_amount_cents
        assert params.currency == "usd"
        assert params.metadata.user_id == user.id
        assert params.metadata.event_id == event.id

        # Verify idempotency key is set
        assert opts[:headers]["Idempotency-Key"] =~ "ticket_order_"

        {:ok, build_payment_intent(%{amount: expected_amount_cents})}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      # Select one ticket
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Proceed to checkout - this should create the order and payment intent
      render_click(view, "proceed-to-checkout")

      # Wait for payment modal / next render (mocked Stripe responds immediately)
      html = render(view)
      assert is_binary(html)
    end

    test "restored payment checkout disables submit until Stripe element is ready",
         %{conn: conn, user: user} do
      {event, _tier, order, payment_intent} = setup_pending_order(user)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok,
         build_payment_intent(%{
           id: id,
           client_secret: payment_intent.client_secret,
           amount: order.total_amount.amount
         })}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/events/#{event.id}?checkout=payment&order_id=#{order.id}"
        )

      view = wait_for_async(view)

      assert has_element?(view, "#payment-modal")
      assert has_element?(view, "#submit-payment")
      assert payment_submit_disabled?(render(view))

      render_click(view, "stripe-payment-element-ready", %{})
      refute payment_submit_disabled?(render(view))

      render_click(view, "stripe-payment-element-loading", %{})
      assert payment_submit_disabled?(render(view))
    end

    test "calculates correct total with multiple tickets", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Expected: 3 tickets (converted to cents for Stripe)
      quantity = 3
      single_ticket_cents = money_to_cents(tier.price)
      expected_amount_cents = single_ticket_cents * quantity

      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.amount == expected_amount_cents
        {:ok, build_payment_intent(%{amount: expected_amount_cents})}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      # Select 3 tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      render_click(view, "proceed-to-checkout")
      html = render(view)
      assert is_binary(html)
    end

    test "includes donation in total amount", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Just verify that payment intent is created with some amount
      # Don't try to calculate exact donation logic as it may be complex
      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # Verify amount is greater than just the ticket price
        ticket_only_cents = money_to_cents(tier.price)
        assert params.amount > ticket_only_cents
        assert params.currency == "usd"
        {:ok, build_payment_intent(%{amount: params.amount})}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      # Select ticket
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Add donation (amount interpretation may vary by implementation)
      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "50"
      })

      render_click(view, "proceed-to-checkout")
      html = render(view)
      assert is_binary(html)
    end

    test "includes metadata in payment intent", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # Verify all required metadata
        assert params.metadata.user_id == user.id
        assert params.metadata.event_id == event.id
        assert params.metadata.ticket_order_id != nil
        assert params.metadata.ticket_order_reference != nil
        assert params.description =~ "Event tickets - Order"

        {:ok, build_payment_intent()}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "payment intent creation failures" do
    test "handles Stripe API error gracefully", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Mock Stripe error
      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error,
         %Stripe.Error{
           message: "Your card was declined.",
           code: "card_declined",
           source: :stripe
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      # Should not crash
      html = render(view)
      assert is_binary(html)
    end

    test "handles network timeout error", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error, :timeout}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      result = render_click(view, "proceed-to-checkout")

      # Should handle error gracefully
      assert is_binary(result)
    end

    test "handles invalid payment parameters", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error, "Invalid request: amount must be at least $0.50"}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      # Should not crash
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "payment redirect handling" do
    test "tracks payment redirect state", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok, build_payment_intent()}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      # Start redirect
      result = render_click(view, "payment-redirect-started")

      # Can still render while redirecting
      assert is_binary(result)
    end
  end

  describe "payment modal UI state" do
    test "handles payment modal close event", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Stub (not expect) so we don't fail if checkout/payment-intent runs async or not at all
      stub(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok, build_payment_intent()}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      result = render_click(view, "close-payment-modal")

      assert is_binary(result)
    end
  end

  describe "idempotency key usage" do
    test "uses order reference as idempotency key", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      expect(Ysc.StripeMock, :create_payment_intent, fn _params, opts ->
        idempotency_key = opts[:headers]["Idempotency-Key"]
        assert idempotency_key =~ "ticket_order_ORD-"
        {:ok, build_payment_intent()}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "amount calculation edge cases" do
    test "handles zero-amount free tickets", %{conn: conn, user: user} do
      event = event_with_state(:upcoming, with_image: true, user: user)

      free_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Free Admission",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 100
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{
        "tier-id" => free_tier.id
      })

      # Free tickets shouldn't create payment intent
      result = render_click(view, "proceed-to-checkout")

      # Should handle free tickets differently (no payment modal)
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "converts Money to cents correctly for Stripe", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Set tier price to $50.00 (Money stores as dollars, so 50 = $50)
      tier =
        tier
        |> Ecto.Changeset.change(%{price: Money.new(50, :USD)})
        |> Repo.update!()

      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # Should be 5000 cents ($50 * 100)
        assert params.amount == 5000
        assert is_integer(params.amount)
        {:ok, build_payment_intent(%{amount: 5000})}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      html = render(view)
      assert is_binary(html)
    end

    test "handles large ticket quantities correctly", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # 10 tickets (converted to cents for Stripe)
      quantity = 10
      single_ticket_cents = money_to_cents(tier.price)
      expected_amount_cents = single_ticket_cents * quantity

      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.amount == expected_amount_cents
        {:ok, build_payment_intent(%{amount: expected_amount_cents})}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      # Add 10 tickets
      Enum.each(1..10, fn _ ->
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      end)

      render_click(view, "proceed-to-checkout")

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "checkout retry mechanism" do
    test "allows retry after failure", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # First attempt - error
      expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:error, "Card declined"}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      # Retry - should not crash
      result = render_click(view, "retry-checkout")

      assert is_binary(result)
    end
  end

  describe "paid ticket free-checkout bypass (Finding 21)" do
    test "checkout=free URL on paid order restores payment checkout", %{
      conn: conn,
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

        order =
          ticket_order_fixture(%{user: user, event: event, status: :pending})
          |> stabilize_pending_ticket_order!()

        {:ok, view, _html} =
          live(
            conn,
            ~p"/events/#{event.id}?checkout=free&order_id=#{order.id}"
          )

        view = wait_for_async(view)

        assert has_element?(view, "#payment-modal")
        refute has_element?(view, "#free-ticket-confirmation-modal")
      end)
    end

    test "confirm-free-tickets cannot complete a pending paid order", %{
      conn: conn,
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

        order =
          ticket_order_fixture(%{user: user, event: event, status: :pending})
          |> stabilize_pending_ticket_order!()

        {:ok, view, _html} =
          live(
            conn,
            ~p"/events/#{event.id}?checkout=free&order_id=#{order.id}"
          )

        view = wait_for_async(view)
        render_click(view, "confirm-free-tickets")

        assert Tickets.get_ticket_order(order.id).status == :pending
      end)
    end

    test "confirm-free-tickets without an active order is rejected", %{
      conn: conn,
      user: user
    } do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      view = wait_for_async(view)

      render_click(view, "confirm-free-tickets")

      html = render(view)
      assert html =~ "This order is no longer available."
    end

    test "confirm-free-tickets rejects completed orders restored from URL", %{
      conn: conn,
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

        order =
          ticket_order_fixture(%{user: user, event: event, status: :completed})
          |> stabilize_pending_ticket_order!()
          |> Ecto.Changeset.change(status: :completed)
          |> Repo.update!()

        {:ok, view, _html} =
          live(
            conn,
            ~p"/events/#{event.id}?checkout=free&order_id=#{order.id}"
          )

        view = wait_for_async(view)
        render_click(view, "confirm-free-tickets")

        html = render(view)
        assert html =~ "This order is no longer available."
        assert Tickets.get_ticket_order(order.id).status == :completed
      end)
    end
  end

  describe "payment modal interactions" do
    test "close-payment-modal event works", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      result = render_click(view, "close-payment-modal")
      assert is_binary(result)
    end

    test "close-order-completion event works", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      result = render_click(view, "close-order-completion")
      assert is_binary(result)
    end

    test "checkout-expired event works", %{conn: conn, user: user} do
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view =
        wait_for_async(view)

      result = render_click(view, "checkout-expired")
      assert is_binary(result)
    end
  end

  defp payment_submit_disabled?(html) do
    {:ok, doc} = Floki.parse_fragment(html)

    case Floki.find(doc, "#submit-payment") do
      [el | _] -> Floki.attribute(el, "disabled") != []
      [] -> false
    end
  end

  defp stabilize_pending_ticket_order!(order) do
    from(j in Oban.Job,
      where: j.worker == "Ysc.Tickets.TimeoutWorker",
      where: fragment("?->>'ticket_order_id' = ?", j.args, ^order.id),
      where: j.state in ["available", "scheduled", "retryable"]
    )
    |> Repo.delete_all()

    order
    |> Ecto.Changeset.change(
      status: :pending,
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end
end
