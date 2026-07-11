defmodule Ysc.Tickets.CheckoutCancelTest do
  @moduledoc """
  Unit tests for `Ysc.Tickets.CheckoutCancel` payment-intent guards.

  Extracted in #663 to block admin grants and checkout cancellation from racing
  Stripe when a payment is in flight.
  """
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.Tickets
  alias Ysc.Tickets.CheckoutCancel
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    :ok
  end

  defp order_struct(overrides \\ []) do
    struct(
      TicketOrder,
      Keyword.merge(
        [id: Ecto.ULID.generate(), payment_intent_id: nil],
        overrides
      )
    )
  end

  defp payment_intent(status, id) do
    %Stripe.PaymentIntent{id: id, status: status, amount: 2500}
  end

  describe "pending_order_safe_to_cancel?/2" do
    test "returns true when order has no payment intent" do
      assert CheckoutCancel.pending_order_safe_to_cancel?(order_struct())
    end

    test "returns false when payment redirect is in progress" do
      refute CheckoutCancel.pending_order_safe_to_cancel?(order_struct(),
               payment_redirect_in_progress: true
             )
    end

    test "returns false for blocked payment intent statuses" do
      for status <-
            ~w(requires_action processing requires_confirmation succeeded) do
        payment_intent_id = "pi_blocked_#{status}"

        order =
          order_struct(payment_intent_id: payment_intent_id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent(status, payment_intent_id)}
        end)

        refute CheckoutCancel.pending_order_safe_to_cancel?(order)
      end
    end

    test "returns true for cancellable payment intent statuses" do
      for status <- ~w(requires_payment_method canceled) do
        payment_intent_id = "pi_safe_#{status}"

        order =
          order_struct(payment_intent_id: payment_intent_id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent(status, payment_intent_id)}
        end)

        assert CheckoutCancel.pending_order_safe_to_cancel?(order)
      end
    end

    test "returns false when Stripe cannot retrieve payment intent" do
      payment_intent_id = "pi_missing"

      order =
        order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :api_error,
           message: "not found",
           extra: %{}
         }}
      end)

      refute CheckoutCancel.pending_order_safe_to_cancel?(order,
               context: "checkout"
             )
    end
  end

  describe "blocking_pending_orders/2" do
    test "returns empty list when user has no pending orders" do
      order = ticket_order_fixture()

      assert CheckoutCancel.blocking_pending_orders(
               order.user_id,
               order.event_id
             ) ==
               []
    end

    test "returns empty list when pending order has no payment intent" do
      order = ticket_order_fixture()

      assert order.status == :pending
      assert is_nil(order.payment_intent_id)

      assert CheckoutCancel.blocking_pending_orders(
               order.user_id,
               order.event_id
             ) ==
               []
    end

    test "returns pending orders with in-flight payment intents" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_blocking_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      [blocking_order] =
        CheckoutCancel.blocking_pending_orders(order.user_id, order.event_id)

      assert blocking_order.id == order.id
    end

    test "ignores pending orders with cancellable payment intents" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_cancellable_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("requires_payment_method", payment_intent_id)}
      end)

      assert CheckoutCancel.blocking_pending_orders(
               order.user_id,
               order.event_id
             ) ==
               []
    end

    test "returns only unsafe pending orders when user has mixed checkout state" do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()

      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      assert {:ok, safe_order} =
               Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

      assert {:ok, unsafe_order} =
               Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

      safe_pi = "pi_safe_mixed_#{safe_order.id}"
      unsafe_pi = "pi_unsafe_mixed_#{unsafe_order.id}"

      assert {:ok, safe_order} =
               Tickets.update_payment_intent(safe_order, safe_pi)

      assert {:ok, unsafe_order} =
               Tickets.update_payment_intent(unsafe_order, unsafe_pi)

      expect(Ysc.StripeMock, :retrieve_payment_intent, 2, fn pi_id, _opts ->
        case pi_id do
          ^safe_pi ->
            {:ok, payment_intent("requires_payment_method", safe_pi)}

          ^unsafe_pi ->
            {:ok, payment_intent("requires_confirmation", unsafe_pi)}
        end
      end)

      blocking =
        CheckoutCancel.blocking_pending_orders(user.id, event.id)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert blocking == [unsafe_order.id]
      refute safe_order.id in blocking
    end
  end

  describe "expire_ticket_order/1 payment guards" do
    test "skips expiration when payment intent is processing" do
      user = user_fixture()
      event = event_fixture(%{max_attendees: 100})
      tier = ticket_tier_fixture(%{event_id: event.id})

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

      payment_intent_id = "pi_processing_expire_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:ok, returned} = Tickets.expire_ticket_order(order)
      assert returned.status == :pending
      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end
  end
end
