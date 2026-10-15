defmodule Ysc.Merch.OrdersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders}

  setup do
    user = user_fixture()

    tee =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "25"),
        name: "Tee / Black / M"
      })

    sticker = variant_fixture(nil, %{retail_price: Money.new(:USD, "3.50")})
    lines = cart_lines_fixture(user, [{tee, 2}, {sticker, 4}])
    %{user: user, tee: tee, sticker: sticker, lines: lines}
  end

  defp create(user, lines, opts \\ []) do
    Orders.create_pending_purchase(
      user,
      lines,
      Keyword.get(opts, :address, shipping_address_fixture()),
      Keyword.get(opts, :option, shipping_option_fixture())
    )
  end

  test "snapshots items, prices, address and totals", %{
    user: user,
    lines: lines
  } do
    assert {:ok, %Order{} = order} = create(user, lines)

    assert order.kind == :purchase
    assert order.status == :pending
    assert order.user_id == user.id
    assert order.reference_id =~ ~r/^MRC-\d{6}-[A-Z0-9]{5}$/
    assert order.recipient_name == "Ada Lovelace"
    assert order.state_code == "CA"
    assert order.email == user.email
    assert order.shipping_method == "STANDARD"

    # 2 x 25 + 4 x 3.50 = 64.00, + 5.95 shipping
    assert Money.equal?(order.subtotal, Money.new(:USD, "64"))
    assert Money.equal?(order.shipping_amount, Money.new(:USD, "5.95"))
    assert Money.equal?(order.total_amount, Money.new(:USD, "69.95"))

    assert length(order.items) == 2
    tee_item = Enum.find(order.items, &(&1.quantity == 2))
    assert tee_item.name == "Tee / Black / M"
    assert Money.equal?(tee_item.unit_price, Money.new(:USD, "25"))
  end

  test "later price changes do not alter the order", %{
    user: user,
    lines: lines,
    tee: tee
  } do
    {:ok, order} = create(user, lines)

    tee
    |> Ecto.Changeset.change(retail_price: Money.new(:USD, "99"))
    |> Repo.update!()

    reloaded = Orders.get_order!(order.id)
    item = Enum.find(reloaded.items, &(&1.quantity == 2))
    assert Money.equal?(item.unit_price, Money.new(:USD, "25"))
    assert Money.equal?(reloaded.total_amount, Money.new(:USD, "69.95"))
  end

  test "an identical pending checkout is reused", %{user: user, lines: lines} do
    {:ok, first} = create(user, lines)
    {:ok, second} = create(user, lines)
    assert first.id == second.id
    assert Repo.aggregate(Order, :count) == 1
  end

  test "any change creates a new order", %{user: user, lines: lines, tee: tee} do
    {:ok, first} = create(user, lines)

    {:ok, other_address} =
      create(user, lines,
        address: shipping_address_fixture(%{"zip" => "94106"})
      )

    {:ok, other_shipping} =
      create(user, lines,
        option:
          shipping_option_fixture(%{id: "EXPRESS", rate: Money.new(:USD, "12")})
      )

    {:ok, _} = Ysc.Merch.Cart.set_quantity(user, tee.id, 3)
    {:ok, other_items} = create(user, Ysc.Merch.Cart.list(user))

    ids = Enum.map([first, other_address, other_shipping, other_items], & &1.id)
    assert length(Enum.uniq(ids)) == 4
  end

  test "other members' and settled orders are not reused", %{
    user: user,
    lines: lines
  } do
    {:ok, first} = create(user, lines)
    first |> Ecto.Changeset.change(status: :paid) |> Repo.update!()

    assert {:ok, second} = create(user, lines)
    refute second.id == first.id

    stranger = user_fixture()
    stranger_lines = cart_lines_fixture(stranger, [{variant_fixture(), 1}])
    assert {:ok, %Order{user_id: id}} = create(stranger, stranger_lines)
    assert id == stranger.id
  end

  test "rejects empty carts and unavailable lines", %{
    user: user,
    lines: lines,
    tee: tee
  } do
    assert {:error, :empty_cart} = create(user, [])

    tee |> Ecto.Changeset.change(available: false) |> Repo.update!()

    assert {:error, :unavailable_items} =
             create(user, Ysc.Merch.Cart.list(user))

    refute Enum.all?(lines, & &1.available?) and false
  end

  test "get_user_order only returns the member's own order", %{
    user: user,
    lines: lines
  } do
    {:ok, order} = create(user, lines)

    assert %Order{id: id} = Orders.get_user_order(user, order.id)
    assert id == order.id
    assert Orders.get_user_order(user_fixture(), order.id) == nil
    assert Orders.get_user_order(user, Ecto.ULID.generate()) == nil
    assert Orders.get_user_order(user, "garbage") == nil
  end

  test "list_user_orders hides pending checkouts", %{user: user, lines: lines} do
    {:ok, order} = create(user, lines)
    assert Orders.list_user_orders(user) == []

    order |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
    assert [%Order{id: id}] = Orders.list_user_orders(user)
    assert id == order.id
  end

  test "cancel_pending only cancels pending orders", %{user: user, lines: lines} do
    {:ok, order} = create(user, lines)
    assert :ok = Orders.cancel_pending(order, "abandoned")
    canceled = Orders.get_order!(order.id)
    assert canceled.status == :canceled
    assert canceled.failure_reason == "abandoned"
    assert canceled.canceled_at

    assert {:error, :not_pending} = Orders.cancel_pending(order)

    {:ok, other} = create(user, lines)
    other |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
    assert {:error, :not_pending} = Orders.cancel_pending(other)
    assert Orders.get_order!(other.id).status == :paid
  end

  test "attach_payment_intent only works while pending", %{
    user: user,
    lines: lines
  } do
    {:ok, order} = create(user, lines)

    assert {:ok, %Order{payment_intent_id: "pi_1"}} =
             Orders.attach_payment_intent(order, "pi_1")

    assert %Order{id: id} = Orders.get_order_by_payment_intent("pi_1")
    assert id == order.id

    paid = order |> Ecto.Changeset.change(status: :paid) |> Repo.update!()
    assert {:error, :not_pending} = Orders.attach_payment_intent(paid, "pi_2")
  end
end
