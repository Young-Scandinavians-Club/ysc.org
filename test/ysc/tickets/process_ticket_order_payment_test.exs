defmodule Ysc.Tickets.ProcessTicketOrderPaymentTest do
  @moduledoc """
  Tests for `Ysc.Tickets.process_ticket_order_payment/2`, including the
  payment-timeout race where a succeeded Stripe charge must still complete
  an expired order.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Ledgers
  alias Ysc.Tickets

  defp user_fixture_unique(attrs \\ %{}) do
    email =
      Map.get_lazy(attrs, :email, fn ->
        "tu#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
      end)

    user_fixture(Map.put(attrs, :email, email))
  end

  defp with_stripe_payment_intent_mock(
         payment_intent_id,
         amount_cents,
         metadata,
         fun
       )
       when is_map(metadata) do
    unique = System.unique_integer([:positive])
    module_name = :"TestStripeClientTickets#{unique}"
    amount = amount_cents
    escaped_metadata = Macro.escape(metadata)

    mod =
      quote do
        defmodule unquote(module_name) do
          @behaviour Ysc.StripeBehaviour
          @mock_amount unquote(amount)
          @mock_metadata unquote(escaped_metadata)

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def retrieve_payment_method(_id), do: {:error, :not_implemented}
          def list_events(_params, _opts), do: {:error, :not_implemented}
          def retrieve_charge(_id, _opts), do: {:error, :not_implemented}
          def retrieve_payout(_id, _opts), do: {:error, :not_implemented}

          def list_balance_transactions(_params, _opts),
            do: {:error, :not_implemented}

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               status: "succeeded",
               amount: @mock_amount,
               metadata: @mock_metadata
             }}
          end
        end
      end

    Code.eval_quoted(mod, [], __ENV__)

    original_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, module_name)

    try do
      fun.(payment_intent_id)
    after
      Application.put_env(:ysc, :stripe_client, original_client)
    end
  end

  defp payment_intent_metadata(%{id: order_id, user_id: user_id}) do
    %{"ticket_order_id" => order_id, "user_id" => user_id}
  end

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture_unique()

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    organizer = user_fixture_unique()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier1} =
      Ysc.Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 50,
        event_id: event.id
      })

    %{user: user, event: event, tier1: tier1}
  end

  test "completes expired order when payment succeeds after timeout race", %{
    user: user,
    event: event,
    tier1: tier1
  } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    assert {:ok, expired} = Tickets.expire_ticket_order(order)
    assert expired.status == :expired

    payment_intent_id = "pi_expired_race_#{order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(expired.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(expired),
      fn pi_id ->
        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(expired, pi_id)

        assert completed.status == :completed
        assert completed.payment_id

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id
          )

        assert Enum.all?(tickets, &(&1.status == :confirmed))
      end
    )
  end

  test "rejects expired order fulfillment when capacity was taken after expiry",
       %{
         user: user,
         event: event,
         tier1: tier1
       } do
    {:ok, limited_event} =
      Ysc.Events.update_event(event, %{max_attendees: 1})

    {:ok, limited_tier} =
      Ysc.Events.update_ticket_tier(tier1, %{quantity: 1})

    other_user =
      user_fixture_unique()
      |> then(fn u ->
        u
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
      end)

    {:ok, expired_order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, limited_event.id, %{
          limited_tier.id => 1
        })
      end)

    assert {:ok, expired} = Tickets.expire_ticket_order(expired_order)
    assert expired.status == :expired

    assert {:ok, _other_order} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Tickets.create_ticket_order(other_user.id, limited_event.id, %{
                 limited_tier.id => 1
               })
             end)

    payment_intent_id = "pi_expired_overbook_#{expired_order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(expired.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(expired),
      fn pi_id ->
        assert {:error, reason} =
                 Tickets.process_ticket_order_payment(expired, pi_id)

        assert reason in [
                 :event_capacity_exceeded,
                 :tier_validation_failed,
                 :insufficient_capacity
               ]

        reloaded = Ysc.Repo.get!(Ysc.Tickets.TicketOrder, expired_order.id)
        assert reloaded.status == :expired

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket,
              where: t.ticket_order_id == ^expired_order.id
          )

        assert Enum.all?(tickets, &(&1.status == :expired))

        confirmed_count =
          Ysc.Repo.aggregate(
            from(t in Ysc.Events.Ticket,
              where: t.event_id == ^limited_event.id and t.status == :confirmed
            ),
            :count
          )

        pending_count =
          Ysc.Repo.aggregate(
            from(t in Ysc.Events.Ticket,
              where: t.event_id == ^limited_event.id and t.status == :pending
            ),
            :count
          )

        assert confirmed_count + pending_count == 1
      end
    )
  end

  test "does not complete cancelled orders when payment succeeds", %{
    user: user,
    event: event,
    tier1: tier1
  } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    assert {:ok, cancelled} =
             Tickets.cancel_ticket_order(order, "changed mind")

    payment_intent_id = "pi_cancelled_#{order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(cancelled.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(cancelled),
      fn pi_id ->
        assert {:error, :cannot_complete_order} =
                 Tickets.process_ticket_order_payment(cancelled, pi_id)

        refute Ledgers.get_payment_by_external_id(pi_id)
      end
    )
  end

  test "concurrent checkout cancel does not orphan ledger payment", %{
    user: user,
    event: event,
    tier1: tier1
  } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    payment_intent_id = "pi_cancel_race_#{order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(order),
      fn pi_id ->
        payment_task =
          Task.async(fn ->
            Tickets.process_ticket_order_payment(order, pi_id)
          end)

        assert {:ok, _cancelled} =
                 Tickets.cancel_ticket_order(order, "User closed checkout")

        payment_result = Task.await(payment_task, 5_000)

        assert {:error, :cannot_complete_order} = payment_result
        refute Ledgers.get_payment_by_external_id(pi_id)

        reloaded = Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        assert reloaded.status == :cancelled
      end
    )
  end

  test "retrying an already-completed order is idempotent", %{
    user: user,
    event: event,
    tier1: tier1
  } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    payment_intent_id = "pi_completed_retry_#{order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(order),
      fn pi_id ->
        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(order, pi_id)

        assert completed.status == :completed
        assert completed.payment_id
        assert Ledgers.get_payment_by_external_id(pi_id)

        assert {:ok, retried} =
                 Tickets.process_ticket_order_payment(completed, pi_id)

        assert retried.id == completed.id
        assert retried.payment_id == completed.payment_id
        assert Ledgers.get_payment_by_external_id(pi_id)
      end
    )
  end

  test "does not expire completed orders when timeout worker races payment", %{
    user: user,
    event: event,
    tier1: tier1
  } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    payment_intent_id = "pi_timeout_race_#{order.id}"
    amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      amount_cents,
      payment_intent_metadata(order),
      fn pi_id ->
        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(order, pi_id)

        assert completed.status == :completed

        stale_pending = %{order | status: :pending}

        assert {:ok, returned} = Tickets.expire_ticket_order(stale_pending)
        assert returned.status == :completed

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket,
              where: t.ticket_order_id == ^order.id
          )

        assert Enum.all?(tickets, &(&1.status == :confirmed))
      end
    )
  end

  test "completes payment when tier price increased and PI matches synced total",
       %{
         user: user,
         event: event
       } do
    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "Early Bird",
        type: :paid,
        price: Money.new(30, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
      end)

    assert Money.equal?(order.total_amount, Money.new(30, :USD))

    {:ok, _tier} =
      Ysc.Events.update_ticket_tier(tier, %{
        price: Money.new(50, :USD)
      })

    payment_intent_id = "pi_repriced_paid_#{order.id}"
    synced_amount_cents = 5_000

    with_stripe_payment_intent_mock(
      payment_intent_id,
      synced_amount_cents,
      payment_intent_metadata(order),
      fn pi_id ->
        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(order, pi_id)

        assert completed.status == :completed
        assert completed.payment_id
        assert Money.equal?(completed.total_amount, Money.new(50, :USD))
        assert Ledgers.get_payment_by_external_id(pi_id)
      end
    )
  end

  test "completes expired order when tier price increased after expiry and PI matches synced total",
       %{
         user: user,
         event: event,
         tier1: tier1
       } do
    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

    assert {:ok, expired} = Tickets.expire_ticket_order(order)
    assert expired.status == :expired

    {:ok, _tier} =
      Ysc.Events.update_ticket_tier(tier1, %{
        price: Money.new(75, :USD)
      })

    payment_intent_id = "pi_expired_repriced_#{order.id}"
    synced_amount_cents = 7_500

    with_stripe_payment_intent_mock(
      payment_intent_id,
      synced_amount_cents,
      payment_intent_metadata(expired),
      fn pi_id ->
        assert {:ok, completed} =
                 Tickets.process_ticket_order_payment(expired, pi_id)

        assert completed.status == :completed
        assert Money.equal?(completed.total_amount, Money.new(75, :USD))

        tickets =
          Ysc.Repo.all(
            from t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id
          )

        assert Enum.all?(tickets, &(&1.status == :confirmed))
      end
    )
  end

  test "rejects payment when tier price increased after order and PI were created",
       %{
         user: user,
         event: event
       } do
    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "Early Bird",
        type: :paid,
        price: Money.new(30, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
      end)

    assert Money.equal?(order.total_amount, Money.new(30, :USD))

    {:ok, _tier} =
      Ysc.Events.update_ticket_tier(tier, %{
        price: Money.new(50, :USD)
      })

    payment_intent_id = "pi_stale_paid_#{order.id}"
    stale_amount_cents = Ysc.MoneyHelper.money_to_cents(order.total_amount)

    with_stripe_payment_intent_mock(
      payment_intent_id,
      stale_amount_cents,
      payment_intent_metadata(order),
      fn pi_id ->
        assert {:error, :amount_mismatch} =
                 Tickets.process_ticket_order_payment(order, pi_id)

        reloaded = Tickets.get_ticket_order(order.id)
        assert reloaded.status == :pending
        assert Money.equal?(reloaded.total_amount, Money.new(50, :USD))
      end
    )
  end

  test "rejects succeeded payment intent when user_id metadata does not match order owner",
       %{
         user: user,
         event: event
       } do
    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "General",
        type: :paid,
        price: Money.new(40, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
      end)

    other_user = user_fixture_unique()

    payment_intent = %Stripe.PaymentIntent{
      id: "pi_wrong_user_#{order.id}",
      status: "succeeded",
      amount: Ysc.MoneyHelper.money_to_cents(order.total_amount),
      metadata: %{
        "ticket_order_id" => order.id,
        "user_id" => other_user.id
      }
    }

    assert {:error, :payment_metadata_mismatch} =
             Tickets.process_ticket_order_payment(order, payment_intent)

    assert Tickets.get_ticket_order(order.id).status == :pending
  end

  test "accepts atom-key metadata on succeeded payment intents", %{
    user: user,
    event: event
  } do
    {:ok, tier} =
      Ysc.Events.create_ticket_tier(%{
        name: "General",
        type: :paid,
        price: Money.new(40, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, order} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
      end)

    payment_intent = %Stripe.PaymentIntent{
      id: "pi_atom_metadata_#{order.id}",
      status: "succeeded",
      amount: Ysc.MoneyHelper.money_to_cents(order.total_amount),
      metadata: %{
        ticket_order_id: order.id,
        user_id: user.id
      }
    }

    assert {:ok, completed} =
             Tickets.process_ticket_order_payment(order, payment_intent)

    assert completed.status == :completed
  end
end
