defmodule Ysc.Merch.WebhookHandlerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders, WebhookHandler}
  alias Ysc.Printful.{ClientMock, Error}
  alias Ysc.StripeMock

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    originals =
      for key <- [:stripe_client, :quickbooks_client],
          do: {key, Application.get_env(:ysc, key)}

    Application.put_env(:ysc, :stripe_client, StripeMock)
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)
    stub_quickbooks_sync!()

    on_exit(fn ->
      Enum.each(originals, fn {k, v} -> Application.put_env(:ysc, k, v) end)
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _ ->
      {:ok, %{"Id" => "c"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _, _ ->
      {:ok, %{"Id" => "sr", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _ ->
      {:ok, %{"Id" => "a"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _, _ ->
      {:ok, "item"}
    end)

    stub(ClientMock, :get_order_by_external_id, fn _ ->
      {:error, %Error{type: :not_found, message: "x"}}
    end)

    stub(ClientMock, :create_order, fn _, true ->
      {:ok, %{"id" => 1, "status" => "pending"}}
    end)

    user = user_fixture()

    lines =
      cart_lines_fixture(user, [
        {variant_fixture(nil, %{retail_price: Money.new(:USD, "10")}), 1}
      ])

    {:ok, order} =
      Orders.create_pending_purchase(
        user,
        lines,
        shipping_address_fixture(),
        shipping_option_fixture()
      )

    {:ok, order} =
      Orders.attach_payment_intent(order, "pi_hook_#{order.reference_id}")

    %{order: order}
  end

  defp succeeded_intent(order, attrs \\ %{}) do
    struct!(
      Stripe.PaymentIntent,
      Map.merge(
        %{
          id: order.payment_intent_id,
          status: "succeeded",
          amount: 1595,
          metadata: %{"merch_order_id" => order.id}
        },
        attrs
      )
    )
  end

  defp stripe_event(type, intent) do
    %Stripe.Event{
      id: "evt_#{System.unique_integer([:positive])}",
      type: type,
      data: %{object: intent},
      api_version: "2025-10-29.clover",
      created: System.os_time(:second),
      livemode: false,
      pending_webhooks: 1,
      request: %{id: "req_1", idempotency_key: "k"},
      object: "event",
      account: "acct_test"
    }
  end

  describe "handle_webhook_event/2" do
    test "payment_intent.succeeded fulfils the order", %{order: order} do
      expect(StripeMock, :retrieve_payment_intent, fn id, _ ->
        assert id == order.payment_intent_id
        {:ok, succeeded_intent(order)}
      end)

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.succeeded",
                 %{"id" => order.payment_intent_id}
               )

      assert %Order{status: :submitted} = Orders.get_order!(order.id)
    end

    test "a payment problem never raises or asks Stripe to retry forever", %{
      order: order
    } do
      expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
        {:ok, succeeded_intent(order, %{amount: 1})}
      end)

      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.succeeded",
                 %{"id" => order.payment_intent_id}
               )

      assert Orders.get_order!(order.id).status == :pending
    end

    test "payment_intent.canceled cancels the pending order", %{order: order} do
      assert :ok =
               WebhookHandler.handle_webhook_event("payment_intent.canceled", %{
                 "id" => order.payment_intent_id
               })

      assert Orders.get_order!(order.id).status == :canceled
    end

    test "payment_intent.canceled never touches an order that was paid", %{
      order: order
    } do
      order |> Ecto.Changeset.change(status: :submitted) |> Repo.update!()

      assert :ok =
               WebhookHandler.handle_webhook_event("payment_intent.canceled", %{
                 "id" => order.payment_intent_id
               })

      assert Orders.get_order!(order.id).status == :submitted
    end

    test "payment_intent.canceled for an unknown Intent is ignored" do
      assert :ok =
               WebhookHandler.handle_webhook_event("payment_intent.canceled", %{
                 "id" => "pi_nope"
               })
    end

    test "a failed attempt leaves the order pending so the member can retry", %{
      order: order
    } do
      assert :ok =
               WebhookHandler.handle_webhook_event(
                 "payment_intent.payment_failed",
                 %{"id" => order.payment_intent_id}
               )

      assert Orders.get_order!(order.id).status == :pending
    end
  end

  describe "routing from the Stripe webhook handler" do
    test "succeeded events with a merch_order_id reach the merch handler", %{
      order: order
    } do
      expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
        {:ok, succeeded_intent(order)}
      end)

      event = stripe_event("payment_intent.succeeded", succeeded_intent(order))
      assert :ok = Ysc.Stripe.WebhookHandler.handle_event(event)
      assert %Order{status: :submitted} = Orders.get_order!(order.id)
    end

    test "a lost pending-to-paid claim still marks the webhook processed", %{
      order: order
    } do
      intent = succeeded_intent(order)
      handler_id = "merch-webhook-lost-claim-#{inspect(self())}"

      expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
        {:ok, intent}
      end)

      :telemetry.attach(
        handler_id,
        [:ysc, :ledgers, :payment_recorded],
        fn _event, _measurements, metadata, _config ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {1, _} =
            from(o in Order,
              where: o.id == ^order.id and o.status == :pending
            )
            |> Repo.update_all(
              set: [
                status: :paid,
                payment_id: metadata.payment_id,
                payment_intent_id: intent.id,
                updated_at: now
              ]
            )
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      event = stripe_event("payment_intent.succeeded", intent)
      assert :ok = Ysc.Stripe.WebhookHandler.handle_event(event)

      webhook =
        Repo.get_by!(Ysc.Webhooks.WebhookEvent, event_id: event.id)

      assert webhook.state == :processed
      assert %Order{status: :paid} = Orders.get_order!(order.id)
    end

    test "canceled events with a merch_order_id reach the merch handler", %{
      order: order
    } do
      event =
        stripe_event(
          "payment_intent.canceled",
          succeeded_intent(order, %{status: "canceled"})
        )

      assert :ok = Ysc.Stripe.WebhookHandler.handle_event(event)
      assert Orders.get_order!(order.id).status == :canceled
    end
  end
end
