defmodule Ysc.Merch.FulfillmentTest do
  use Ysc.DataCase, async: false

  import Mox
  import Swoosh.TestAssertions
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Ledgers.Payment
  alias Ysc.Merch.{Cart, Fulfillment, Order, Orders}
  alias Ysc.Printful.{ClientMock, Error}
  alias Ysc.StripeMock
  alias YscWeb.Workers.MerchSubmitOrder

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    original_stripe = Application.get_env(:ysc, :stripe_client)
    original_qb = Application.get_env(:ysc, :quickbooks_client)
    Application.put_env(:ysc, :stripe_client, StripeMock)
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)
    stub_quickbooks_sync!()

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe)
      Application.put_env(:ysc, :quickbooks_client, original_qb)
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
      {:ok, %{"Id" => "qb_c"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _ ->
      {:ok, %{"Id" => "qb_sr", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
      {:ok, %{"Id" => "qb_a"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn name, _opts ->
      send(self(), {:quickbooks_item, name})
      {:ok, "qb_item"}
    end)

    user = user_fixture()

    tee =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "25"),
        name: "Tee / Black / M"
      })

    sticker =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "3.50"),
        name: "Sticker"
      })

    lines = cart_lines_fixture(user, [{tee, 2}, {sticker, 4}])

    {:ok, order} =
      Orders.create_pending_purchase(
        user,
        lines,
        shipping_address_fixture(),
        shipping_option_fixture()
      )

    # 2 x 25 + 4 x 3.50 + 5.95 shipping
    %{user: user, order: order, tee: tee, sticker: sticker, cents: 6995}
  end

  defp payment_intent(order, attrs \\ %{}) do
    struct!(
      Stripe.PaymentIntent,
      Map.merge(
        %{
          id: "pi_#{order.reference_id}",
          status: "succeeded",
          amount: 6995,
          metadata: %{"merch_order_id" => order.id}
        },
        attrs
      )
    )
  end

  defp printful_accepts(printful_id \\ 4242, total \\ "31.20") do
    stub(ClientMock, :get_order_by_external_id, fn _ ->
      {:error, %Error{type: :not_found, status: 404, message: "Not found"}}
    end)

    stub(ClientMock, :create_order, fn payload, true ->
      send(self(), {:printful_payload, payload})

      {:ok,
       %{
         "id" => printful_id,
         "status" => "pending",
         "costs" => %{"total" => total}
       }}
    end)
  end

  describe "process_successful_payment/1" do
    test "records the payment, fulfils the order and emails the member", %{
      order: order,
      user: user
    } do
      printful_accepts()

      assert {:ok, %Order{} = paid} =
               Fulfillment.process_successful_payment(payment_intent(order))

      # The submit job runs inline in tests, so the order has moved on to Printful.
      assert paid.status == :submitted
      assert paid.printful_order_id == 4242
      assert Money.equal?(paid.printful_cost, Money.new(:USD, "31.20"))
      assert paid.submitted_at

      payment = Repo.get!(Payment, paid.payment_id)
      assert Money.equal?(payment.amount, Money.new(:USD, "69.95"))
      assert payment.user_id == user.id
      assert payment.external_payment_id == "pi_#{order.reference_id}"

      assert_email_sent(
        subject: "We've got your merch order (#{order.reference_id})",
        to: {nil, user.email}
      )

      assert_received {:printful_payload, payload}
      assert payload.external_id == order.reference_id
      assert payload.shipping == "STANDARD"
      assert payload.recipient.name == "Ada Lovelace"
      assert payload.recipient.state_code == "CA"

      assert Enum.sort_by(payload.items, & &1.quantity) ==
               Enum.sort_by(
                 Enum.map(
                   paid.items,
                   &%{
                     sync_variant_id: &1.variant.printful_sync_variant_id,
                     quantity: &1.quantity
                   }
                 ),
                 & &1.quantity
               )
    end

    test "books the sale to merch revenue", %{order: order} do
      printful_accepts()

      {:ok, paid} =
        Fulfillment.process_successful_payment(payment_intent(order))

      entries =
        Repo.all(
          from(e in Ysc.Ledgers.LedgerEntry,
            join: a in assoc(e, :account),
            where:
              e.payment_id == ^paid.payment_id and a.name == "merch_revenue",
            select: {e.debit_credit, e.related_entity_type, e.related_entity_id}
          )
        )

      assert [{:credit, :merch, entity_id}] = entries
      assert entity_id == order.id
    end

    test "syncs the sale to QuickBooks as a merch item", %{order: order} do
      printful_accepts()
      {:ok, _} = Fulfillment.process_successful_payment(payment_intent(order))

      assert_received {:quickbooks_item, "Merch Sales"}
    end

    test "books merch to the Merch Sales income account", %{order: order} do
      printful_accepts()

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn name ->
        {:ok, "account:#{name}"}
      end)

      stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn name, opts ->
        send(self(), {:quickbooks_item, name, opts[:income_account_ref]})
        {:ok, "qb_item"}
      end)

      {:ok, _} = Fulfillment.process_successful_payment(payment_intent(order))

      assert_received {:quickbooks_item, "Merch Sales",
                       %{value: "account:Merch Sales"}}
    end

    test "falls back to General Revenue while the Merch Sales account is missing",
         %{order: order} do
      printful_accepts()

      stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn
        "General Revenue" -> {:ok, "account:general"}
        _ -> {:error, :not_found}
      end)

      stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn name, opts ->
        send(self(), {:quickbooks_item, name, opts[:income_account_ref]})
        {:ok, "qb_item"}
      end)

      {:ok, _} = Fulfillment.process_successful_payment(payment_intent(order))

      assert_received {:quickbooks_item, "Merch Sales",
                       %{value: "account:general"}}
    end

    test "is idempotent across webhook, return page and retries", %{
      order: order
    } do
      printful_accepts()
      pi = payment_intent(order)

      assert {:ok, first} = Fulfillment.process_successful_payment(pi)
      assert {:ok, second} = Fulfillment.process_successful_payment(pi)
      assert {:ok, third} = Fulfillment.process_successful_payment(pi)

      assert first.payment_id == second.payment_id
      assert second.payment_id == third.payment_id
      assert Repo.aggregate(Payment, :count) == 1

      # Printful was only ever asked to create the order once.
      assert_received {:printful_payload, _}
      refute_received {:printful_payload, _}
    end

    test "a settled order does not record the payment again", %{order: order} do
      printful_accepts()
      pi = payment_intent(order)
      test_pid = self()

      :telemetry.attach(
        "merch-payment-recorded-#{inspect(test_pid)}",
        [:ysc, :ledgers, :payment_recorded],
        fn _event, _measurements, _metadata, _config ->
          send(test_pid, :payment_recorded)
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("merch-payment-recorded-#{inspect(test_pid)}")
      end)

      {:ok, _} = Fulfillment.process_successful_payment(pi)

      # A second caller finds the order already paid (here: still waiting for
      # Printful) and must not touch the ledger or QuickBooks again.
      Repo.update_all(from(o in Order, where: o.id == ^order.id),
        set: [status: :paid]
      )

      assert {:ok, %Order{status: :paid}} =
               Fulfillment.process_successful_payment(pi)

      assert_received :payment_recorded
      refute_received :payment_recorded
    end

    test "fetches the PaymentIntent when given an id", %{order: order} do
      printful_accepts()
      pi = payment_intent(order)

      expect(StripeMock, :retrieve_payment_intent, fn id, _ ->
        assert id == pi.id
        {:ok, pi}
      end)

      assert {:ok, %Order{status: :submitted}} =
               Fulfillment.process_successful_payment(pi.id)
    end

    test "removes the ordered variants from the member's cart", %{
      order: order,
      user: user,
      tee: tee
    } do
      printful_accepts()
      other = variant_fixture()
      {:ok, _} = Cart.add(user, other.id, 1)
      assert Cart.count(user) == 7

      {:ok, _} = Fulfillment.process_successful_payment(payment_intent(order))

      assert [%{variant: %{id: id}}] = Cart.list(user)
      assert id == other.id
      refute Enum.any?(Cart.list(user), &(&1.variant.id == tee.id))
    end

    test "waits for Stripe to capture the payment", %{order: order} do
      assert {:error, :not_succeeded} =
               Fulfillment.process_successful_payment(
                 payment_intent(order, %{status: "processing"})
               )

      assert Orders.get_order!(order.id).status == :pending
      assert Repo.aggregate(Payment, :count) == 0
    end

    test "refuses a payment for the wrong amount", %{order: order} do
      assert {:error, :amount_mismatch} =
               Fulfillment.process_successful_payment(
                 payment_intent(order, %{amount: 100})
               )

      assert Orders.get_order!(order.id).status == :pending
      assert Repo.aggregate(Payment, :count) == 0
    end

    test "refuses a second PaymentIntent for the same order", %{order: order} do
      {:ok, order} = Orders.attach_payment_intent(order, "pi_original")

      assert {:error, :payment_intent_mismatch} =
               Fulfillment.process_successful_payment(
                 payment_intent(order, %{id: "pi_other"})
               )

      assert Orders.get_order!(order.id).status == :pending
    end

    test "unknown orders are an error, not a crash" do
      pi =
        struct!(Stripe.PaymentIntent,
          id: "pi_x",
          status: "succeeded",
          amount: 1,
          metadata: %{"merch_order_id" => Ecto.ULID.generate()}
        )

      assert {:error, :order_not_found} =
               Fulfillment.process_successful_payment(pi)

      pi =
        struct!(Stripe.PaymentIntent,
          id: "pi_y",
          status: "succeeded",
          amount: 1,
          metadata: %{}
        )

      assert {:error, :order_not_found} =
               Fulfillment.process_successful_payment(pi)
    end

    test "does not revive canceled or failed orders", %{order: order} do
      :ok = Orders.cancel_pending(order, "abandoned")

      assert {:ok, %Order{status: :canceled}} =
               Fulfillment.process_successful_payment(payment_intent(order))

      assert Repo.aggregate(Payment, :count) == 0
    end
  end

  describe "submit_to_printful/1" do
    setup %{order: order} do
      paid = order |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
      %{paid: paid}
    end

    test "adopts an order Printful already has for our external id", %{
      paid: paid
    } do
      expect(ClientMock, :get_order_by_external_id, fn ref ->
        assert ref == paid.reference_id

        {:ok,
         %{"id" => 99, "status" => "pending", "costs" => %{"total" => "12.00"}}}
      end)

      assert :ok = Fulfillment.submit_to_printful(paid.id)

      order = Orders.get_order!(paid.id)
      assert order.status == :submitted
      assert order.printful_order_id == 99
    end

    test "confirms a draft found by external id instead of recording it as submitted",
         %{paid: paid} do
      expect(ClientMock, :get_order_by_external_id, fn ref ->
        assert ref == paid.reference_id
        {:ok, %{"id" => 7, "status" => "draft"}}
      end)

      expect(ClientMock, :confirm_order, fn 7 ->
        {:ok,
         %{"id" => 7, "status" => "pending", "costs" => %{"total" => "18.00"}}}
      end)

      assert :ok = Fulfillment.submit_to_printful(paid.id)

      order = Orders.get_order!(paid.id)
      assert order.status == :submitted
      assert order.printful_order_id == 7
      assert Money.equal?(order.printful_cost, Money.new(:USD, "18.00"))
    end

    test "keeps a draft-adoption retryable when confirm fails", %{paid: paid} do
      error = %Error{type: :server, status: 503, message: "down"}

      expect(ClientMock, :get_order_by_external_id, fn _ ->
        {:ok, %{"id" => 8, "status" => "draft"}}
      end)

      expect(ClientMock, :confirm_order, fn 8 -> {:error, error} end)

      assert {:error, ^error} = Fulfillment.submit_to_printful(paid.id)

      order = Orders.get_order!(paid.id)
      assert order.status == :submitting
      assert is_nil(order.printful_order_id)
    end

    test "confirms an order Printful left as a draft", %{paid: paid} do
      expect(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, message: "x"}}
      end)

      expect(ClientMock, :create_order, fn _, true ->
        {:ok, %{"id" => 5, "status" => "draft"}}
      end)

      expect(ClientMock, :confirm_order, fn 5 ->
        {:ok,
         %{"id" => 5, "status" => "pending", "costs" => %{"total" => "20.00"}}}
      end)

      assert :ok = Fulfillment.submit_to_printful(paid.id)

      assert %Order{status: :submitted, printful_order_id: 5} =
               Orders.get_order!(paid.id)
    end

    test "leaves cost empty when Printful has not priced it yet", %{paid: paid} do
      expect(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, message: "x"}}
      end)

      expect(ClientMock, :create_order, fn _, true ->
        {:ok, %{"id" => 6, "status" => "pending", "costs" => %{"total" => nil}}}
      end)

      assert :ok = Fulfillment.submit_to_printful(paid.id)
      assert Orders.get_order!(paid.id).printful_cost == nil
    end

    test "returns transient errors for retry and keeps the order submittable",
         %{paid: paid} do
      error = %Error{type: :server, status: 503, message: "down"}
      expect(ClientMock, :get_order_by_external_id, fn _ -> {:error, error} end)

      assert {:error, ^error} = Fulfillment.submit_to_printful(paid.id)
      assert Orders.get_order!(paid.id).status == :submitting
    end

    test "does nothing for orders that are not waiting to be submitted", %{
      paid: paid
    } do
      for status <- [:pending, :submitted, :shipped, :failed, :canceled] do
        paid |> Ecto.Changeset.change(status: status) |> Repo.update!()
        assert :ok = Fulfillment.submit_to_printful(paid.id)
      end

      assert :ok = Fulfillment.submit_to_printful(Ecto.ULID.generate())
    end
  end

  describe "MerchSubmitOrder worker" do
    setup %{order: order} do
      paid = order |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
      %{paid: paid}
    end

    defp run(paid, attempt) do
      MerchSubmitOrder.perform(%Oban.Job{
        args: %{"order_id" => paid.id},
        attempt: attempt,
        max_attempts: 8
      })
    end

    test "retries transient failures", %{paid: paid} do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :network, message: "timeout"}}
      end)

      assert {:error, %Error{type: :network}} = run(paid, 1)
      assert Orders.get_order!(paid.id).status == :submitting
    end

    test "marks the order failed once attempts run out", %{paid: paid} do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :network, message: "timeout"}}
      end)

      assert :ok = run(paid, 8)
      order = Orders.get_order!(paid.id)
      assert order.status == :failed
      assert order.failure_reason =~ "unreachable after 8 attempts"
    end

    test "marks the order failed straight away on a permanent rejection", %{
      paid: paid,
      user: user
    } do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, message: "x"}}
      end)

      stub(ClientMock, :create_order, fn _, true ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Recipient address is invalid"
         }}
      end)

      assert :ok = run(paid, 1)
      order = Orders.get_order!(paid.id)
      assert order.status == :failed

      assert order.failure_reason ==
               "Printful rejected the order: Recipient address is invalid"

      # The member is told, and so is the board.
      assert_email_sent(
        subject: ~r/problem with your order/,
        to: {"", user.email}
      )

      assert_email_sent(fn email ->
        assert email.to == [{"", Ysc.EmailConfig.board_email()}]
        assert email.subject =~ "couldn't be sent to Printful"
        assert email.html_body =~ "Recipient address is invalid"
        assert email.html_body =~ "Refund the payment"
      end)
    end

    test "failing twice only alerts once", %{paid: paid} do
      stub(ClientMock, :get_order_by_external_id, fn _ ->
        {:error, %Error{type: :not_found, message: "x"}}
      end)

      stub(ClientMock, :create_order, fn _, true ->
        {:error, %Error{type: :invalid, status: 400, message: "bad"}}
      end)

      run(paid, 1)
      assert_email_sent()
      assert_email_sent()

      run(paid, 1)
      refute_email_sent()
    end

    test "backs off exponentially, capped at an hour" do
      assert MerchSubmitOrder.backoff(%Oban.Job{attempt: 1}) == 30
      assert MerchSubmitOrder.backoff(%Oban.Job{attempt: 3}) == 120
      assert MerchSubmitOrder.backoff(%Oban.Job{attempt: 20}) == 3_600
    end
  end
end
