defmodule EventDetailsLiveHelpers do
  @moduledoc """
  Test helpers for EventDetailsLive test suite.

  Provides reusable setup patterns, mocks, and test data builders for
  testing payment flows, registration, and other complex scenarios.
  """

  import Ysc.TestDataFactory
  import Ysc.EventsFixtures
  import Mox

  alias Ysc.Repo

  @doc """
  Builds a Stripe PaymentIntent for testing.

  ## Examples

      iex> build_payment_intent()
      %Stripe.PaymentIntent{id: "pi_test_...", status: "requires_payment_method"}

      iex> build_payment_intent(%{status: "succeeded", amount: 10_000})
      %Stripe.PaymentIntent{status: "succeeded", amount: 10_000}
  """
  def build_payment_intent(attrs \\ %{}) do
    defaults = %{
      id: "pi_test_#{System.unique_integer([:positive])}",
      client_secret: "pi_test_secret_#{System.unique_integer([:positive])}",
      status: "requires_payment_method",
      amount: 5000,
      currency: "usd",
      metadata: %{}
    }

    struct(Stripe.PaymentIntent, Map.merge(defaults, attrs))
  end

  @doc """
  Builds a Stripe Customer for testing.
  """
  def build_customer(attrs \\ %{}) do
    defaults = %{
      id: "cus_test_#{System.unique_integer([:positive])}",
      email: "test@example.com"
    }

    struct(Stripe.Customer, Map.merge(defaults, attrs))
  end

  @doc """
  Sets up common Stripe mocks that most tests need.

  This stubs out basic Stripe operations with reasonable defaults.
  Individual tests can override these with `expect/3`.
  """
  def setup_stripe_mocks do
    # Default customer creation
    stub(Ysc.StripeMock, :create_customer, fn params ->
      {:ok, build_customer(%{email: Map.get(params, :email)})}
    end)

    # Default payment intent cancellation
    stub(Ysc.StripeMock, :cancel_payment_intent, fn id, _params ->
      {:ok, build_payment_intent(%{id: id, status: "canceled"})}
    end)

    # Default customer update
    stub(Ysc.StripeMock, :update_customer, fn id, _params ->
      {:ok, build_customer(%{id: id})}
    end)

    :ok
  end

  @doc """
  Expects a successful payment intent creation with specific amount.

  ## Examples

      expect_payment_intent_creation(5000)
  """
  def expect_payment_intent_creation(amount) do
    expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      # Verify amount matches expected
      if params.amount != amount do
        raise "Expected amount #{amount} but got #{params.amount}"
      end

      if params.currency != "usd" do
        raise "Expected currency 'usd' but got '#{params.currency}'"
      end

      {:ok, build_payment_intent(%{amount: amount})}
    end)
  end

  @doc """
  Expects payment intent retrieval with succeeded status.
  """
  def expect_payment_success(payment_intent_id) do
    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok,
       build_payment_intent(%{
         id: payment_intent_id,
         status: "succeeded"
       })}
    end)
  end

  @doc """
  Expects payment intent retrieval with requires_action status (3D Secure).
  """
  def expect_payment_requires_action(payment_intent_id) do
    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok,
       build_payment_intent(%{
         id: payment_intent_id,
         status: "requires_action",
         next_action: %{
           type: "redirect_to_url",
           redirect_to_url: %{url: "https://stripe.com/3ds"}
         }
       })}
    end)
  end

  @doc """
  Expects payment intent retrieval with failed status.
  """
  def expect_payment_failure(payment_intent_id, reason \\ "card_declined") do
    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok,
       build_payment_intent(%{
         id: payment_intent_id,
         status: "requires_payment_method",
         last_payment_error: %{
           code: reason,
           message: "Your card was declined."
         }
       })}
    end)
  end

  @doc """
  Creates event with multiple ticket tiers for comprehensive testing.

  Returns event preloaded with ticket tiers.
  """
  def setup_complex_event do
    event = event_with_state(:upcoming, with_image: true)

    # Free tier
    _free_tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Free General Admission",
        type: :free,
        price: Money.new(0, :USD),
        quantity: 50
      })

    # Paid tier
    _paid_tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Standard Ticket",
        type: :paid,
        price: Money.new(5000, :USD),
        quantity: 100
      })

    # VIP tier
    _vip_tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "VIP Pass",
        type: :paid,
        price: Money.new(15_000, :USD),
        quantity: 20
      })

    # Registration tier
    _reg_tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Workshop with Registration",
        type: :paid,
        requires_registration: true,
        price: Money.new(7500, :USD),
        quantity: 30
      })

    Repo.preload(event, :ticket_tiers, force: true)
  end

  @doc """
  Creates a pending ticket order for restoration testing.

  Returns tuple of {event, tier, order, payment_intent}.
  """
  def setup_pending_order(user) do
    event = event_with_tickets(tier_count: 1, state: :upcoming)
    event = Repo.preload(event, :ticket_tiers, force: true)
    tier = hd(event.ticket_tiers)

    payment_intent = build_payment_intent(%{amount: tier.price.amount})

    # Create pending order
    {:ok, order} =
      Ysc.Tickets.TicketOrder.create_changeset(%Ysc.Tickets.TicketOrder{}, %{
        user_id: user.id,
        event_id: event.id,
        total_amount: tier.price,
        payment_intent_id: payment_intent.id,
        expires_at: DateTime.add(DateTime.utc_now(), 15, :minute),
        status: :pending
      })
      |> Repo.insert()

    {event, tier, order, payment_intent}
  end

  @doc """
  Waits for LiveView async operation to complete.

  ## Examples

      wait_for_async(view, 500)
  """
  def wait_for_async(view, timeout \\ 500) do
    :timer.sleep(timeout)
    view
  end

  @doc """
  Calculates expected total for ticket selection.
  Returns total in cents for comparison with Stripe amounts.
  """
  def calculate_total(tier, quantity, donation_dollars \\ 0) do
    ticket_cents = money_to_cents(tier.price) * quantity
    donation_cents = donation_dollars * 100
    ticket_cents + donation_cents
  end

  @doc """
  Converts Money to cents for Stripe API.

  Money struct stores amounts as base currency (dollars for USD).
  Stripe requires amounts in cents, so we multiply by 100.

  ## Examples

      iex> money_to_cents(Money.new(25, :USD))
      2500
  """
  def money_to_cents(%Money{amount: amount}) do
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end
end
