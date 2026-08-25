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
  alias Ysc.Tickets.BookingLocker
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

  defp stripe_unexpected_state_error do
    %Stripe.Error{
      source: :stripe,
      code: :payment_intent_unexpected_state,
      message: "cannot cancel",
      extra: %{}
    }
  end

  defp stripe_api_error(message) do
    %Stripe.Error{
      source: :stripe,
      code: :api_error,
      message: message,
      extra: %{}
    }
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

      safe_order = ticket_order_fixture(%{user: user, event: event, tier: tier})

      assert {:ok, unsafe_order} =
               BookingLocker.atomic_booking(user.id, event.id, %{tier.id => 1})

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

  describe "checkout_payment_in_flight?/2" do
    test "returns false when order has no payment intent" do
      refute CheckoutCancel.checkout_payment_in_flight?(order_struct())
    end

    test "returns true for blocked payment intent statuses" do
      for status <-
            ~w(requires_action processing requires_confirmation succeeded) do
        payment_intent_id = "pi_in_flight_#{status}"

        order =
          order_struct(payment_intent_id: payment_intent_id)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent(status, payment_intent_id)}
        end)

        assert CheckoutCancel.checkout_payment_in_flight?(order)
      end
    end
  end

  describe "cancel_payment_intent_for_abandoned_checkout/2" do
    test "returns {:cancel, nil} when the order has no payment intent" do
      assert {:cancel, nil} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order_struct()
               )
    end

    test "returns {:cancel, payment_intent} when Stripe accepts the cancel" do
      payment_intent_id = "pi_abandon_ok"

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok, payment_intent("canceled", payment_intent_id)}
      end)

      assert {:cancel, %Stripe.PaymentIntent{id: ^payment_intent_id}} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end

    test "returns {:already_succeeded, payment_intent} when Stripe refuses because payment succeeded" do
      payment_intent_id = "pi_abandon_succeeded"

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("succeeded", payment_intent_id)}
      end)

      assert {:already_succeeded, %Stripe.PaymentIntent{status: "succeeded"}} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end

    test "returns {:cancel, payment_intent} when Stripe refused cancel but PI is already canceled" do
      payment_intent_id = "pi_abandon_already_canceled"

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("canceled", payment_intent_id)}
      end)

      assert {:cancel, %Stripe.PaymentIntent{status: "canceled"}} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end

    test "returns {:in_progress, payment_intent} when Stripe refuses cancel while processing" do
      payment_intent_id = "pi_abandon_processing"

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:in_progress, %Stripe.PaymentIntent{status: "processing"}} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end

    test "returns {:error, reason} when retrieve fails after Stripe refused the cancel" do
      payment_intent_id = "pi_abandon_retrieve_fail"
      retrieve_error = stripe_api_error("not found")

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:error, retrieve_error}
      end)

      assert {:error, ^retrieve_error} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end

    test "returns {:error, reason} when cancel fails with a non-Stripe error" do
      payment_intent_id = "pi_abandon_timeout"

      order = order_struct(payment_intent_id: payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
                 order
               )
    end
  end

  describe "sync_pending_order_pricing/1 payment guards" do
    test "skips repricing while checkout payment is in flight" do
      order =
        ticket_order_fixture()
        |> Ysc.Repo.preload(tickets: :ticket_tier)

      tier = hd(order.tickets).ticket_tier
      payment_intent_id = "pi_sync_blocked_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("requires_action", payment_intent_id)}
      end)

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier, %{price: Money.new(99, :USD)})

      assert {:ok, synced} = Tickets.sync_pending_order_pricing(order)
      assert Money.equal?(synced.total_amount, order.total_amount)

      reloaded = Tickets.get_ticket_order(order.id)
      assert Money.equal?(reloaded.total_amount, order.total_amount)
    end
  end

  describe "expire_ticket_order/1 payment guards" do
    test "skips expiration when payment intent is processing" do
      order = ticket_order_fixture()
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

    test "skips expiration when Stripe cannot retrieve payment intent" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_missing_expire_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

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

      assert {:ok, returned} = Tickets.expire_ticket_order(order)
      assert returned.status == :pending
      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end
  end

  describe "cancel_ticket_order/2 payment guards" do
    test "rejects cancellation when payment intent is processing" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_processing_cancel_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message: "cannot cancel",
           extra: %{}
         }}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "rejects cancellation when payment intent requires action and Stripe refuses to cancel it" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_requires_action_cancel_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message: "cannot cancel",
           extra: %{}
         }}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("requires_action", payment_intent_id)}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "allows cancellation when Stripe confirms the payment intent is cancelled" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_cancellable_cancel_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok, payment_intent("canceled", payment_intent_id)}
      end)

      assert {:ok, cancelled} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert cancelled.status == :cancelled
    end

    test "fulfills the order instead of orphaning the payment when Stripe reveals it already succeeded" do
      original_quickbooks_client = Application.get_env(:ysc, :quickbooks_client)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      on_exit(fn ->
        Application.put_env(
          :ysc,
          :quickbooks_client,
          original_quickbooks_client
        )
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
        {:ok, %{"Id" => "qb_account_default"}}
      end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        order = ticket_order_fixture()
        payment_intent_id = "pi_already_succeeded_#{order.id}"

        assert {:ok, order} =
                 Tickets.update_payment_intent(order, payment_intent_id)

        amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

        succeeded_payment_intent =
          struct(Stripe.PaymentIntent, %{
            id: payment_intent_id,
            status: "succeeded",
            amount: amount_cents,
            metadata: %{
              "ticket_order_id" => order.id,
              "user_id" => order.user_id
            }
          })

        expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
          {:error,
           %Stripe.Error{
             source: :stripe,
             code: :payment_intent_unexpected_state,
             message:
               "You cannot cancel this PaymentIntent because it has a status of succeeded",
             extra: %{}
           }}
        end)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, succeeded_payment_intent}
        end)

        assert {:ok, fulfilled} =
                 Tickets.cancel_ticket_order(order, "User left checkout")

        assert fulfilled.id == order.id
        assert fulfilled.status == :completed
        assert fulfilled.payment_id

        assert Ysc.Repo.get!(TicketOrder, order.id).status == :completed
      end)
    end

    test "cancels the order when Stripe refused cancel but the PaymentIntent is already canceled" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_already_canceled_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, payment_intent("canceled", payment_intent_id)}
      end)

      assert {:ok, cancelled} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert cancelled.status == :cancelled
    end

    test "rejects cancellation when Stripe cancel fails with a non-Stripe error" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_cancel_timeout_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, :timeout}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "rejects cancellation when retrieve fails after Stripe refused the cancel" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_cancel_retrieve_fail_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:error, stripe_api_error("not found")}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.cancel_ticket_order(order, "User cancelled")

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "rejects cancellation when a payment redirect is in progress" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_redirect_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.cancel_ticket_order(order, "User cancelled",
                 payment_redirect_in_progress: true
               )

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "returns fulfillment error when succeeded payment cannot complete the order" do
      order = ticket_order_fixture()
      payment_intent_id = "pi_fulfillment_fail_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      succeeded_payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: payment_intent_id,
          status: "succeeded",
          amount: 1,
          metadata: %{
            "ticket_order_id" => order.id,
            "user_id" => order.user_id
          }
        })

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, stripe_unexpected_state_error()}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok, succeeded_payment_intent}
      end)

      assert {:error, {:payment_succeeded_fulfillment_failed, :amount_mismatch}} =
               Tickets.cancel_ticket_order(order, "User left checkout")

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "still cancels completed orders after refund without payment guard" do
      order = ticket_order_fixture()

      {:ok, completed} =
        order
        |> Ecto.Changeset.change(%{status: :completed})
        |> Ysc.Repo.update!()
        |> then(&{:ok, &1})

      assert {:ok, cancelled} =
               Tickets.cancel_ticket_order(
                 completed,
                 "Refund processed - tickets released",
                 from_statuses: [:completed]
               )

      assert cancelled.status == :cancelled
    end
  end

  describe "create_ticket_order/3 checkout supersede" do
    test "rejects a second checkout while payment is in flight" do
      order =
        ticket_order_fixture()
        |> Ysc.Repo.preload(tickets: :ticket_tier)

      [ticket] = order.tickets
      payment_intent_id = "pi_processing_new_checkout_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      # The safety pre-check (matching maybe_cancel_pending_ticket_order/3)
      # sees "processing" and skips the atomic cancel entirely - Stripe can
      # in rare cases accept a cancel while processing, and this order might
      # be an active ACH payment in another tab. blocking_pending_orders/2
      # then does its own read to confirm it's still blocking.
      expect(Ysc.StripeMock, :retrieve_payment_intent, 2, fn ^payment_intent_id,
                                                             _opts ->
        {:ok, payment_intent("processing", payment_intent_id)}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.create_ticket_order(order.user_id, order.event_id, %{
                 ticket.ticket_tier_id => 1
               })

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
    end

    test "blocks a second checkout instead of double-charging when cleanup fulfills the old order" do
      original_quickbooks_client = Application.get_env(:ysc, :quickbooks_client)
      Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

      on_exit(fn ->
        Application.put_env(
          :ysc,
          :quickbooks_client,
          original_quickbooks_client
        )
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
        {:ok, %{"Id" => "qb_customer_default"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params,
                                                                _opts ->
        {:ok, %{"Id" => "qb_sr_default", "TotalAmt" => "0.00"}}
      end)

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
        {:ok, %{"Id" => "qb_account_default"}}
      end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        order =
          ticket_order_fixture()
          |> Ysc.Repo.preload(tickets: :ticket_tier)

        [ticket] = order.tickets
        payment_intent_id = "pi_already_succeeded_new_checkout_#{order.id}"

        assert {:ok, order} =
                 Tickets.update_payment_intent(order, payment_intent_id)

        amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

        succeeded_payment_intent =
          struct(Stripe.PaymentIntent, %{
            id: payment_intent_id,
            status: "succeeded",
            amount: amount_cents,
            metadata: %{
              "ticket_order_id" => order.id,
              "user_id" => order.user_id
            }
          })

        # Simulates the TOCTOU race the atomic cancel exists to close: the
        # safety pre-check reads a still-safe status (so prepare_new_checkout_session
        # doesn't skip this order the way it would for a genuinely in-flight
        # one), but by the time the atomic cancel reaches Stripe moments
        # later, the client has actually finished confirming the payment.
        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, payment_intent("requires_payment_method", payment_intent_id)}
        end)

        expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
          {:error,
           %Stripe.Error{
             source: :stripe,
             code: :payment_intent_unexpected_state,
             message:
               "You cannot cancel this PaymentIntent because it has a status of succeeded",
             extra: %{}
           }}
        end)

        expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                            _opts ->
          {:ok, succeeded_payment_intent}
        end)

        # Simulates the user re-clicking "buy tickets" for the same event
        # while their earlier (seemingly abandoned) checkout's payment had
        # actually already gone through with Stripe. The cleanup step fulfills
        # that old order instead of orphaning the charge - starting a brand
        # new checkout here must be blocked, not silently allowed, or the
        # user would pay twice for the same event.
        assert {:error, :checkout_payment_in_progress} =
                 Tickets.create_ticket_order(order.user_id, order.event_id, %{
                   ticket.ticket_tier_id => 1
                 })

        assert Ysc.Repo.get!(TicketOrder, order.id).status == :completed
      end)
    end
  end
end
