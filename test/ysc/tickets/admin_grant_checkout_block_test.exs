defmodule Ysc.Tickets.AdminGrantCheckoutBlockTest do
  @moduledoc """
  Admin grant blocking when a recipient has an in-flight Stripe checkout.

  Uses `async: false` because `:stripe_client` is pinned via Application env,
  which races with DataCase setup in parallel tests.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    admin = user_fixture(%{role: "admin"})
    organizer = user_fixture()
    event = event_fixture(%{organizer_id: organizer.id})

    tier1 =
      ticket_tier_fixture(%{event_id: event.id, name: "General Admission"})

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    original_quickbooks_client = Application.get_env(:ysc, :quickbooks_client)
    Ysc.TestHelpers.setup_quickbooks_mocks()

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
      Application.put_env(:ysc, :quickbooks_client, original_quickbooks_client)
    end)

    %{admin: admin, user: user, event: event, tier1: tier1}
  end

  test "rejects grant when recipient checkout payment is in flight", %{
    admin: admin,
    user: user,
    event: event,
    tier1: tier1
  } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_block_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: "processing",
         amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
       }}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end

  test "rejects grant when checkout payment starts after precheck but before commit",
       %{
         admin: admin,
         user: user,
         event: event,
         tier1: tier1
       } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_toctou_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    retrieve_calls = :counters.new(1, [])

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      call = :counters.add(retrieve_calls, 1, 1)

      status =
        if call == 1 do
          "requires_payment_method"
        else
          "processing"
        end

      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: status,
         amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
       }}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end

  test "cancels the Stripe PaymentIntent when superseding a still-open checkout",
       %{
         admin: admin,
         user: user,
         event: event,
         tier1: tier1
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, pending_order} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      payment_intent_id = "pi_grant_cancel_#{pending_order.id}"

      assert {:ok, pending_order} =
               Tickets.update_payment_intent(pending_order, payment_intent_id)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "requires_payment_method",
           amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
         }}
      end)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "canceled",
           amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
         }}
      end)

      assert {:ok, grant_order} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier1.id => 1
               })

      pending_order = Tickets.get_ticket_order(pending_order.id)
      assert pending_order.status == :cancelled

      assert pending_order.cancellation_reason ==
               "Superseded by admin ticket grant"

      assert grant_order.status == :completed
      assert grant_order.granted_by_id == admin.id
    end)
  end

  test "fulfills a succeeded checkout instead of orphaning the charge when granting",
       %{
         admin: admin,
         user: user,
         event: event,
         tier1: tier1
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, pending_order} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

      payment_intent_id = "pi_grant_succeeded_#{pending_order.id}"

      assert {:ok, pending_order} =
               Tickets.update_payment_intent(pending_order, payment_intent_id)

      amount_cents = Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)

      succeeded_payment_intent =
        struct(Stripe.PaymentIntent, %{
          id: payment_intent_id,
          status: "succeeded",
          amount: amount_cents,
          metadata: %{
            "ticket_order_id" => pending_order.id,
            "user_id" => pending_order.user_id
          }
        })

      cancel_attempted? = :counters.new(1, [])

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        if :counters.get(cancel_attempted?, 1) > 0 do
          {:ok, succeeded_payment_intent}
        else
          {:ok,
           %Stripe.PaymentIntent{
             id: payment_intent_id,
             status: "requires_payment_method",
             amount: amount_cents
           }}
        end
      end)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        :counters.add(cancel_attempted?, 1, 1)

        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message:
             "You cannot cancel this PaymentIntent because it has a status of succeeded",
           extra: %{}
         }}
      end)

      assert {:error, :checkout_payment_in_progress} =
               Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
                 tier1.id => 1
               })

      fulfilled = Tickets.get_ticket_order(pending_order.id)
      assert fulfilled.status == :completed
      assert fulfilled.payment_id
      refute fulfilled.granted_by_id

      assert [] ==
               Ysc.Repo.all(
                 from to in TicketOrder,
                   where:
                     to.user_id == ^user.id and to.event_id == ^event.id and
                       to.status == :completed and to.granted_by_id == ^admin.id
               )
    end)
  end

  test "rejects grant when Stripe cancel fails for a non-success reason", %{
    admin: admin,
    user: user,
    event: event,
    tier1: tier1
  } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_timeout_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: payment_intent_id,
         status: "requires_payment_method",
         amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
       }}
    end)

    expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:error, :timeout}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end

  test "rejects grant when succeeded checkout payment cannot be fulfilled", %{
    admin: admin,
    user: user,
    event: event,
    tier1: tier1
  } do
    assert {:ok, pending_order} =
             Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})

    payment_intent_id = "pi_grant_fulfill_fail_#{pending_order.id}"

    assert {:ok, pending_order} =
             Tickets.update_payment_intent(pending_order, payment_intent_id)

    cancel_attempted? = :counters.new(1, [])

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      if :counters.get(cancel_attempted?, 1) > 0 do
        {:ok,
         struct(Stripe.PaymentIntent, %{
           id: payment_intent_id,
           status: "succeeded",
           amount: 1,
           metadata: %{
             "ticket_order_id" => pending_order.id,
             "user_id" => pending_order.user_id
           }
         })}
      else
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "requires_payment_method",
           amount: Ysc.MoneyHelper.money_to_cents(pending_order.total_amount)
         }}
      end
    end)

    expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      :counters.add(cancel_attempted?, 1, 1)

      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :payment_intent_unexpected_state,
         message:
           "You cannot cancel this PaymentIntent because it has a status of succeeded",
         extra: %{}
       }}
    end)

    assert {:error, :checkout_payment_in_progress} =
             Tickets.grant_admin_tickets(admin.id, user.id, event.id, %{
               tier1.id => 1
             })

    pending_order = Tickets.get_ticket_order(pending_order.id)
    assert pending_order.status == :pending

    assert [] ==
             Ysc.Repo.all(
               from to in TicketOrder,
                 where:
                   to.user_id == ^user.id and to.event_id == ^event.id and
                     to.status == :completed and to.granted_by_id == ^admin.id
             )
  end
end
