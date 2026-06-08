defmodule Ysc.Tickets.ProcessTicketOrderPaymentTest do
  @moduledoc """
  Tests for `Ysc.Tickets.process_ticket_order_payment/2`, including the
  payment-timeout race where a succeeded Stripe charge must still complete
  an expired order.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Tickets

  defp user_fixture_unique(attrs \\ %{}) do
    email =
      Map.get_lazy(attrs, :email, fn ->
        "tu#{:erlang.unique_integer([:positive, :monotonic])}@example.com"
      end)

    user_fixture(Map.put(attrs, :email, email))
  end

  defp with_stripe_payment_intent_mock(payment_intent_id, amount_cents, fun) do
    unique = System.unique_integer([:positive])
    module_name = :"TestStripeClientTickets#{unique}"
    amount = amount_cents

    mod =
      quote do
        defmodule unquote(module_name) do
          @behaviour Ysc.StripeBehaviour
          @mock_amount unquote(amount)

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def retrieve_payment_method(_id), do: {:error, :not_implemented}

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               status: "succeeded",
               amount: @mock_amount,
               metadata: %{}
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
      fn pi_id ->
        assert {:error, :cannot_complete_order} =
                 Tickets.process_ticket_order_payment(cancelled, pi_id)
      end
    )
  end
end
