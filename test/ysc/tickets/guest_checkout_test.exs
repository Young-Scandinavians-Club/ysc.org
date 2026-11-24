defmodule Ysc.Tickets.GuestCheckoutTest do
  @moduledoc """
  Buying public-sale tickets without an account: order creation, validation,
  payment completion and the confirmation email.
  """
  use Ysc.DataCase, async: false

  import Ecto.Query
  import Mox
  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Events.Ticket
  alias Ysc.MoneyHelper
  alias Ysc.Tickets
  alias Ysc.Tickets.GuestCheckout
  alias Ysc.Tickets.StripeService
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  @guest %{
    email: "  Guest.Buyer@Example.COM ",
    first_name: "Gus",
    last_name: "Buyer"
  }

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
      {:ok, %{"Id" => "qb_customer"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _ ->
      {:ok, %{"Id" => "qb_sr", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _ ->
      {:ok, %{"Id" => "qb_deposit", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
      {:ok, %{"Id" => "qb_account"}}
    end)

    organizer = user_fixture()

    {:ok, event} =
      Events.create_event(%{
        title: "Open Event",
        description: "Everyone welcome",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    tier = fn name, attrs ->
      {:ok, tier} =
        Events.create_ticket_tier(
          Map.merge(
            %{
              name: name,
              type: :paid,
              price: Money.new(25, :USD),
              quantity: 50,
              event_id: event.id
            },
            attrs
          )
        )

      tier
    end

    %{
      event: event,
      public_tier: tier.("Public GA", %{sale_audience: :public}),
      limited_tier:
        tier.("Public limited", %{sale_audience: :public, max_per_buyer: 2}),
      free_tier:
        tier.("Public free", %{
          sale_audience: :public,
          type: :free,
          price: Money.new(0, :USD)
        }),
      member_tier: tier.("Members", %{sale_audience: :member_guests})
    }
  end

  defp cancel_timeout_jobs!(order_id) do
    from(j in Oban.Job,
      where: j.worker == "Ysc.Tickets.TimeoutWorker",
      where: fragment("?->>'ticket_order_id' = ?", j.args, ^order_id)
    )
    |> Repo.delete_all()
  end

  describe "create_order/3" do
    test "creates a pending guest order with no user and normalized email", %{
      event: event,
      public_tier: tier
    } do
      assert {:ok, %TicketOrder{} = order} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})

      assert order.user_id == nil
      assert order.guest_email == "guest.buyer@example.com"
      assert order.guest_first_name == "Gus"
      assert order.status == :pending
      assert TicketOrder.guest?(order)
      assert TicketOrder.buyer_email(order) == "guest.buyer@example.com"
      assert TicketOrder.buyer_name(order) == "Gus Buyer"
      assert Money.equal?(order.total_amount, Money.new(50, :USD))

      tickets =
        Repo.all(from(t in Ticket, where: t.ticket_order_id == ^order.id))

      assert length(tickets) == 2
      assert Enum.all?(tickets, &(&1.user_id == nil and &1.status == :pending))
    end

    test "rejects member tiers, alone or mixed", %{
      event: event,
      public_tier: public_tier,
      member_tier: member_tier
    } do
      assert {:error, :guest_checkout_not_allowed} =
               GuestCheckout.create_order(@guest, event.id, %{
                 member_tier.id => 1
               })

      assert {:error, :guest_checkout_not_allowed} =
               GuestCheckout.create_order(@guest, event.id, %{
                 public_tier.id => 1,
                 member_tier.id => 1
               })

      assert Repo.aggregate(TicketOrder, :count) == 0
    end

    test "rejects bad contact details", %{event: event, public_tier: tier} do
      assert {:error, {:invalid_guest, cs}} =
               GuestCheckout.create_order(
                 %{email: "nope", first_name: "", last_name: "X"},
                 event.id,
                 %{tier.id => 1}
               )

      assert Keyword.has_key?(cs.errors, :guest_email)
      assert Keyword.has_key?(cs.errors, :guest_first_name)
    end

    test "rejects unknown tiers and tiers of another event", %{
      event: event,
      public_tier: tier
    } do
      assert {:error, :tier_validation_failed} =
               GuestCheckout.create_order(@guest, event.id, %{
                 Ecto.ULID.generate() => 1
               })

      assert {:error, :tier_validation_failed} =
               GuestCheckout.create_order(@guest, Ecto.ULID.generate(), %{
                 tier.id => 1
               })
    end

    test "a new checkout never cancels another hold for the same email", %{
      event: event,
      public_tier: tier
    } do
      {:ok, first} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      {:ok, second} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      assert Repo.reload!(first).status == :pending
      assert Repo.reload!(second).status == :pending
    end

    test "refuses an unbounded admission quantity", %{
      event: event,
      public_tier: tier
    } do
      assert {:error, :ticket_quantity_exceeds_limit} =
               GuestCheckout.create_order(@guest, event.id, %{
                 tier.id => Tickets.max_checkout_quantity_per_tier() + 1
               })

      assert Repo.aggregate(TicketOrder, :count) == 0
      assert Repo.aggregate(Ticket, :count) == 0
    end

    test "one email can't stack up more than three open holds", %{
      event: event,
      public_tier: tier
    } do
      for _ <- 1..3 do
        assert {:ok, _} =
                 GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})
      end

      assert {:error, :too_many_open_holds} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      assert {:ok, _} =
               GuestCheckout.create_order(
                 %{@guest | email: "someone.else@example.com"},
                 event.id,
                 %{tier.id => 1}
               )
    end

    test "max_per_buyer counts confirmed tickets bought with the same email", %{
      event: event,
      limited_tier: tier
    } do
      assert {:error, :tier_purchase_limit_exceeded} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 3})

      {:ok, order} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      Repo.update_all(from(t in Ticket, where: t.ticket_order_id == ^order.id),
        set: [status: :confirmed]
      )

      Repo.update_all(from(o in TicketOrder, where: o.id == ^order.id),
        set: [status: :completed]
      )

      # One of two is used up, whatever the case or padding of the email.
      assert {:error, :tier_purchase_limit_exceeded} =
               GuestCheckout.create_order(
                 %{@guest | email: "  GUEST.buyer@example.com "},
                 event.id,
                 %{tier.id => 2}
               )

      assert {:ok, _} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})
    end

    test "max_per_buyer counts unexpired pending holds for the same email", %{
      event: event,
      limited_tier: tier
    } do
      {:ok, first} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})

      assert first.status == :pending

      # A second tab / reload must not hold another 2 when the first 2 are
      # still payable — paying both would confirm 4 against max_per_buyer: 2.
      assert {:error, :tier_purchase_limit_exceeded} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})

      assert {:error, :tier_purchase_limit_exceeded} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      assert Repo.reload!(first).status == :pending
    end

    test "expired pending holds do not count toward max_per_buyer", %{
      event: event,
      limited_tier: tier
    } do
      {:ok, expired} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.update_all(from(o in TicketOrder, where: o.id == ^expired.id),
        set: [expires_at: past]
      )

      assert {:ok, _} =
               GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})
    end

    test "ci_query_explain_owned_by_tier_query/0 builds an Ecto.Query" do
      assert %Ecto.Query{} =
               GuestCheckout.ci_query_explain_owned_by_tier_query()
    end
  end

  describe "booking re-checks guest eligibility against locked tier rows" do
    @guest_selection_lock ~r/FROM "ticket_tiers".*FOR SHARE/is

    test "share-locks the selected tiers while booking", %{
      event: event,
      public_tier: tier
    } do
      {result, locking_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})
          end,
          pattern: @guest_selection_lock,
          caller_pids: [self()]
        )

      assert {:ok, _order} = result
      assert locking_queries == 1
    end

    test "a tier that stopped being public after validation is refused", %{
      event: event,
      public_tier: tier
    } do
      # Simulates an admin edit landing after `GuestCheckout` loaded the tier
      # but before the booking reads it.
      {:ok, _} =
        Events.update_ticket_tier(tier, %{sale_audience: "members_only"})

      guest = %{email: "g@example.com", first_name: "Gus", last_name: "Buyer"}

      assert {:error, :guest_checkout_not_allowed} =
               Ysc.Tickets.BookingLocker.atomic_booking(
                 nil,
                 event.id,
                 %{tier.id => 1},
                 guest: guest
               )

      assert Repo.aggregate(TicketOrder, :count) == 0
    end

    test "a tier of another event or an unknown tier is refused", %{
      event: event
    } do
      guest = %{email: "g@example.com", first_name: "Gus", last_name: "Buyer"}

      assert {:error, :tier_validation_failed} =
               Ysc.Tickets.BookingLocker.atomic_booking(
                 nil,
                 event.id,
                 %{Ecto.ULID.generate() => 1},
                 guest: guest
               )
    end
  end

  describe "selection tokens" do
    test "round-trip for the same event only", %{event: event} do
      token = GuestCheckout.sign_selection(event.id, %{"t" => 1})

      assert {:ok, %{"t" => 1}} =
               GuestCheckout.verify_selection(token, event.id)

      assert {:error, :invalid} =
               GuestCheckout.verify_selection(token, Ecto.ULID.generate())

      assert {:error, :invalid} =
               GuestCheckout.verify_selection("garbage", event.id)

      assert {:error, :invalid} = GuestCheckout.verify_selection(nil, event.id)
    end
  end

  describe "payment" do
    test "creates a Stripe intent without a customer or user metadata", %{
      event: event,
      public_tier: tier
    } do
      {:ok, order} =
        GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

      expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        refute Map.has_key?(params.metadata, :user_id)
        assert params.metadata.ticket_order_id == order.id
        assert params.receipt_email == "guest.buyer@example.com"
        refute Map.has_key?(params, :customer)

        {:ok,
         struct(Stripe.PaymentIntent, %{
           id: "pi_guest_1",
           amount: params.amount,
           status: "requires_payment_method",
           client_secret: "pi_guest_1_secret_x"
         })}
      end)

      assert {:ok, %{id: "pi_guest_1"}} =
               StripeService.create_payment_intent(order,
                 receipt_email: order.guest_email
               )
    end

    test "a succeeded payment completes the order and emails the guest", %{
      event: event,
      public_tier: tier
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, order} =
          GuestCheckout.create_order(@guest, event.id, %{tier.id => 2})

        cancel_timeout_jobs!(order.id)

        payment_intent =
          struct(Stripe.PaymentIntent, %{
            id: "pi_guest_paid",
            status: "succeeded",
            amount: MoneyHelper.money_to_cents(order.total_amount),
            metadata: %{
              "ticket_order_id" => order.id,
              "ticket_order_reference" => order.reference_id,
              "event_id" => event.id
            }
          })

        assert {:ok, completed} =
                 StripeService.process_successful_payment(payment_intent)

        assert completed.status == :completed
        assert completed.payment_id
        assert completed.user_id == nil

        tickets =
          Repo.all(from(t in Ticket, where: t.ticket_order_id == ^order.id))

        assert length(tickets) == 2
        assert Enum.all?(tickets, &(&1.status == :confirmed))

        assert [job] =
                 Repo.all(
                   from(j in Oban.Job,
                     where:
                       fragment(
                         "?::text LIKE ?",
                         j.args,
                         "%guest.buyer@example.com%"
                       )
                   )
                 )

        assert job.args |> inspect() =~ "ticket_purchase_confirmation"
      end)
    end

    test "a free guest order completes without payment", %{
      event: event,
      free_tier: tier
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, order} =
          GuestCheckout.create_order(@guest, event.id, %{tier.id => 1})

        cancel_timeout_jobs!(order.id)

        assert Tickets.pending_order_still_complimentary?(order)
        assert {:ok, completed} = Tickets.process_free_ticket_order(order)
        assert completed.status == :completed
        assert completed.user_id == nil
      end)
    end
  end
end
