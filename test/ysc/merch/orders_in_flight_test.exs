defmodule Ysc.Merch.OrdersInFlightTest do
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders}
  alias Ysc.StripeMock

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, StripeMock)
    on_exit(fn -> Application.put_env(:ysc, :stripe_client, original) end)

    user = user_fixture()

    tee =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "25"),
        name: "Tee / Black / M"
      })

    lines = cart_lines_fixture(user, [{tee, 2}])
    %{user: user, tee: tee, lines: lines}
  end

  defp create(user, lines, opts \\ []) do
    Orders.create_pending_purchase(
      user,
      lines,
      Keyword.get(opts, :address, shipping_address_fixture()),
      Keyword.get(opts, :option, shipping_option_fixture())
    )
  end

  test "refuses a different cart while a processing PaymentIntent is in flight",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_processing")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_processing",
         status: "processing",
         amount: 5595
       }}
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_processing"
  end

  test "refuses a different address while a processing PaymentIntent is in flight",
       %{user: user, lines: lines} do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_processing")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_processing",
         status: "processing",
         amount: 5595
       }}
    end)

    assert {:error, :payment_in_progress} =
             create(user, lines,
               address: shipping_address_fixture(%{"zip" => "94106"})
             )

    assert Repo.aggregate(Order, :count) == 1
  end

  test "still allows a different cart when the stored Intent is unpaid", %{
    user: user,
    lines: lines,
    tee: tee
  } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_open")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_open", _ ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_open",
         status: "requires_payment_method",
         amount: 5595
       }}
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)
    assert {:ok, second} = create(user, Ysc.Merch.Cart.list(user))
    refute second.id == first.id
  end

  test "refuses a different cart for every other in-flight PaymentIntent status",
       %{tee: tee} do
    for status <- ~w(requires_action requires_confirmation succeeded) do
      user = user_fixture()
      lines = cart_lines_fixture(user, [{tee, 2}])
      {:ok, first} = create(user, lines)
      payment_intent_id = "pi_#{status}"
      {:ok, _} = Orders.attach_payment_intent(first, payment_intent_id)

      expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id, _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: status,
           amount: 5595
         }}
      end)

      {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

      assert {:error, :payment_in_progress} =
               create(user, Ysc.Merch.Cart.list(user))

      assert Orders.get_order!(first.id).status == :pending
      assert Orders.get_order!(first.id).payment_intent_id == payment_intent_id
    end
  end

  test "refuses a different cart when Stripe cannot say the stored Intent is idle",
       %{
         user: user,
         lines: lines,
         tee: tee
       } do
    {:ok, first} = create(user, lines)
    {:ok, _} = Orders.attach_payment_intent(first, "pi_outage")

    expect(StripeMock, :retrieve_payment_intent, fn "pi_outage", _ ->
      {:error,
       %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
    end)

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)

    assert {:error, :payment_in_progress} =
             create(user, Ysc.Merch.Cart.list(user))

    assert Repo.aggregate(Order, :count) == 1
    assert Orders.get_order!(first.id).status == :pending
    assert Orders.get_order!(first.id).payment_intent_id == "pi_outage"
  end
end
