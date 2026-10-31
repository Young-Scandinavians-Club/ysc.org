defmodule Ysc.Merch.CartEventsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Cart, CartEvent, CartEvents}

  setup do
    %{user: user_fixture(), variant: variant_fixture()}
  end

  defp events(user) do
    from(e in CartEvent,
      where: e.user_id == ^user.id,
      order_by: [asc: e.inserted_at, asc: e.id]
    )
    |> Repo.all()
    |> Enum.map(&{&1.action, &1.quantity})
  end

  test "add logs the units added by each click", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 2)
    {:ok, _} = Cart.add(user, variant.id, 1)

    assert events(user) == [added: 2, added: 1]
  end

  test "add logs the capped quantity", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 1000)

    assert events(user) == [added: 25]
  end

  test "a variant that cannot be added logs nothing", %{user: user} do
    sold_out = variant_fixture(nil, %{available: false})

    assert {:error, :unavailable} = Cart.add(user, sold_out.id, 1)
    assert events(user) == []
  end

  test "set_quantity logs the new quantity, and zero logs a removal", %{
    user: user,
    variant: variant
  } do
    {:ok, _} = Cart.add(user, variant.id, 2)
    {:ok, _} = Cart.set_quantity(user, variant.id, 5)
    {:ok, nil} = Cart.set_quantity(user, variant.id, 0)

    assert events(user) == [added: 2, quantity_set: 5, removed: 5]
  end

  test "set_quantity on a line that is not in the cart logs nothing", %{
    user: user,
    variant: variant
  } do
    assert {:ok, nil} = Cart.set_quantity(user, variant.id, 3)
    assert events(user) == []
  end

  test "remove logs the units that were in the line", %{
    user: user,
    variant: variant
  } do
    {:ok, _} = Cart.add(user, variant.id, 3)
    :ok = Cart.remove(user, variant.id)
    :ok = Cart.remove(user, variant.id)

    assert events(user) == [added: 3, removed: 3]
  end

  test "remove can log the line as purchased", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 3)
    :ok = Cart.remove(user, variant.id, :purchased)

    assert events(user) == [added: 3, purchased: 3]
  end

  test "clear logs every line as removed", %{user: user, variant: variant} do
    other = variant_fixture()
    {:ok, _} = Cart.add(user, variant.id, 1)
    {:ok, _} = Cart.add(user, other.id, 4)
    :ok = Cart.clear(user)

    assert [added: 1, added: 4, removed: _, removed: _] = events(user)

    assert Enum.sort(Enum.drop(events(user), 2)) == [removed: 1, removed: 4]
  end

  test "events are per user", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 1)

    assert events(user_fixture()) == []
  end

  test "a failed write is swallowed so the cart keeps working", %{user: user} do
    assert :ok = CartEvents.record(user.id, [{"not-a-ulid", :added, 1}])
    assert :ok = CartEvents.record(user.id, [])
  end
end
