defmodule Ysc.Merch.StaleOrderWorkerTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders, StaleOrderWorker}
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

    on_exit(fn ->
      Enum.each(originals, fn {k, v} -> Application.put_env(:ysc, k, v) end)
    end)

    stub_quickbooks_sync!()

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

    %{order: order}
  end

  defp age(order, minutes, intent \\ nil) do
    inserted_at =
      DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
      |> DateTime.truncate(:second)

    order
    |> Ecto.Changeset.change(
      inserted_at: inserted_at,
      payment_intent_id: intent
    )
    |> Repo.update!()
  end

  defp intent(order, status) do
    %Stripe.PaymentIntent{
      id: order.payment_intent_id,
      status: status,
      amount: 1595,
      metadata: %{"merch_order_id" => order.id}
    }
  end

  defp run, do: assert(:ok = StaleOrderWorker.perform(%Oban.Job{}))

  test "fulfils an order whose payment succeeded but whose webhook was missed",
       %{order: order} do
    order = age(order, 30, "pi_missed")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_missed", _ ->
      {:ok, intent(order, "succeeded")}
    end)

    run()
    assert %Order{status: :submitted} = Orders.get_order!(order.id)
  end

  test "leaves recent orders alone", %{order: order} do
    order = age(order, 3, "pi_recent")
    run()
    assert Orders.get_order!(order.id).status == :pending
  end

  test "leaves an open checkout alone until it is a day old", %{order: order} do
    order = age(order, 120, "pi_open")

    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:ok, intent(order, "requires_payment_method")}
    end)

    run()
    assert Orders.get_order!(order.id).status == :pending
  end

  test "cancels an abandoned checkout and its PaymentIntent", %{order: order} do
    order = age(order, 25 * 60, "pi_abandoned")

    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:ok, intent(order, "requires_payment_method")}
    end)

    expect(StripeMock, :cancel_payment_intent, fn "pi_abandoned", _ ->
      {:ok, %Stripe.PaymentIntent{id: "pi_abandoned", status: "canceled"}}
    end)

    run()
    canceled = Orders.get_order!(order.id)
    assert canceled.status == :canceled
    assert canceled.failure_reason == "Abandoned checkout"
  end

  test "fulfils instead of canceling when the member paid just before the sweep",
       %{order: order} do
    order = age(order, 25 * 60, "pi_race")

    # Open when the sweep looks, paid by the time the cancel is attempted.
    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:ok, intent(order, "requires_payment_method")}
    end)

    expect(StripeMock, :cancel_payment_intent, fn _, _ ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :invalid_request_error,
         message: "status of succeeded"
       }}
    end)

    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:ok, intent(order, "succeeded")}
    end)

    run()
    assert %Order{status: :submitted} = Orders.get_order!(order.id)
  end

  test "cancels an old order that never got a PaymentIntent", %{order: order} do
    age(order, 25 * 60)
    run()
    assert Orders.get_order!(order.id).status == :canceled
  end

  test "a canceled Intent cancels the order", %{order: order} do
    order = age(order, 30, "pi_gone")

    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:ok, intent(order, "canceled")}
    end)

    run()
    assert Orders.get_order!(order.id).status == :canceled
  end

  test "a Stripe outage changes nothing", %{order: order} do
    order = age(order, 25 * 60, "pi_outage")

    expect(StripeMock, :retrieve_payment_intent, fn _, _ ->
      {:error,
       %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
    end)

    run()
    assert Orders.get_order!(order.id).status == :pending
  end
end
