defmodule Ysc.Merch.CartTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Cart, CartItem}

  setup do
    %{
      user: user_fixture(),
      variant: variant_fixture(nil, %{retail_price: Money.new(:USD, "20")})
    }
  end

  test "an empty cart", %{user: user} do
    assert Cart.list(user) == []
    assert Cart.count(user) == 0
    assert Money.zero?(Cart.subtotal([]))
  end

  test "add merges quantities and totals lines", %{user: user, variant: variant} do
    other = variant_fixture(nil, %{retail_price: Money.new(:USD, "5.50")})

    assert {:ok, %CartItem{quantity: 2}} = Cart.add(user, variant.id, 2)
    assert {:ok, %CartItem{quantity: 3}} = Cart.add(user, variant.id, 1)
    assert {:ok, _} = Cart.add(user, other.id, 2)

    lines = Cart.list(user)
    assert length(lines) == 2
    assert Cart.item_count(lines) == 5
    assert Money.equal?(Cart.subtotal(lines), Money.new(:USD, "71.00"))
    assert Cart.count(user) == 5

    line = Enum.find(lines, &(&1.variant.id == variant.id))
    assert Money.equal?(line.line_total, Money.new(:USD, "60"))
    assert line.available?
  end

  test "quantity is capped", %{user: user, variant: variant} do
    assert {:ok, %CartItem{quantity: 25}} = Cart.add(user, variant.id, 1000)
    assert {:ok, %CartItem{quantity: 25}} = Cart.add(user, variant.id, 1)

    assert {:ok, %CartItem{quantity: 25}} =
             Cart.set_quantity(user, variant.id, 999)
  end

  test "set_quantity updates, and zero removes", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 2)

    assert {:ok, %CartItem{quantity: 5}} =
             Cart.set_quantity(user, variant.id, 5)

    assert {:ok, nil} = Cart.set_quantity(user, variant.id, 0)
    assert Cart.list(user) == []
    assert {:ok, nil} = Cart.set_quantity(user, variant.id, 3)
  end

  test "remove and clear", %{user: user, variant: variant} do
    other = variant_fixture()
    {:ok, _} = Cart.add(user, variant.id, 1)
    {:ok, _} = Cart.add(user, other.id, 1)

    assert :ok = Cart.remove(user, variant.id)
    assert [%{variant: %{id: id}}] = Cart.list(user)
    assert id == other.id

    assert :ok = Cart.clear(user)
    assert Cart.list(user) == []
  end

  test "carts are per user", %{user: user, variant: variant} do
    {:ok, _} = Cart.add(user, variant.id, 2)
    assert Cart.list(user_fixture()) == []
  end

  test "unavailable variants cannot be added", %{user: user} do
    sold_out = variant_fixture(nil, %{available: false})

    hidden_product =
      product_fixture()
      |> Ecto.Changeset.change(status: :hidden)
      |> Repo.update!()

    hidden = variant_fixture(hidden_product)

    assert {:error, :unavailable} = Cart.add(user, sold_out.id, 1)
    assert {:error, :unavailable} = Cart.add(user, hidden.id, 1)
    assert {:error, :unavailable} = Cart.add(user, Ecto.ULID.generate(), 1)
    assert {:error, :unavailable} = Cart.add(user, "not-a-ulid", 1)
  end

  test "lines that become unavailable stay visible but are not bought", %{
    user: user,
    variant: variant
  } do
    keep = variant_fixture(nil, %{retail_price: Money.new(:USD, "10")})
    {:ok, _} = Cart.add(user, variant.id, 1)
    {:ok, _} = Cart.add(user, keep.id, 2)

    variant |> Ecto.Changeset.change(available: false) |> Repo.update!()

    lines = Cart.list(user)
    assert length(lines) == 2
    assert [%{variant: %{id: id}}] = Cart.available_lines(lines)
    assert id == keep.id
    assert Money.equal?(Cart.subtotal(lines), Money.new(:USD, "20"))
    assert Cart.item_count(lines) == 2
    assert Cart.count(user) == 2
  end

  describe "add/3 and set_quantity/3" do
    test "adding the same variant again merges into one line, capped", %{
      user: user,
      variant: variant
    } do
      assert {:ok, %CartItem{quantity: 3}} = Cart.add(user, variant.id, 3)
      assert {:ok, %CartItem{quantity: 5}} = Cart.add(user, variant.id, 2)

      assert {:ok, %CartItem{quantity: max}} = Cart.add(user, variant.id, 500)
      assert max == CartItem.max_quantity()

      assert Repo.aggregate(CartItem, :count) == 1
    end

    test "a first add over the cap is capped too", %{
      user: user,
      variant: variant
    } do
      assert {:ok, %CartItem{quantity: max}} = Cart.add(user, variant.id, 500)
      assert max == CartItem.max_quantity()
    end

    test "set_quantity changes an existing line and returns it", %{
      user: user,
      variant: variant
    } do
      {:ok, _} = Cart.add(user, variant.id, 1)

      assert {:ok, %CartItem{quantity: 7}} =
               Cart.set_quantity(user, variant.id, 7)

      assert [%{quantity: 7}] = Cart.list(user)

      assert {:ok, %CartItem{quantity: max}} =
               Cart.set_quantity(user, variant.id, 999)

      assert max == CartItem.max_quantity()
    end

    test "set_quantity never creates a line", %{user: user, variant: variant} do
      assert {:ok, nil} = Cart.set_quantity(user, variant.id, 3)
      assert Cart.list(user) == []
    end

    test "other members' lines are untouched", %{user: user, variant: variant} do
      other = user_fixture()
      {:ok, _} = Cart.add(other, variant.id, 2)
      {:ok, _} = Cart.add(user, variant.id, 1)

      {:ok, _} = Cart.set_quantity(user, variant.id, 9)

      assert [%{quantity: 2}] = Cart.list(other)
    end
  end

  describe "summary/1" do
    test "is empty for no cart and for no user", %{user: user} do
      assert %{count: 0, subtotal: subtotal} = Cart.summary(user)
      assert Money.zero?(subtotal)
      assert %{count: 0} = Cart.summary(nil)
    end

    test "counts and prices what can be bought", %{user: user, variant: variant} do
      other = variant_fixture(nil, %{retail_price: Money.new(:USD, "5.50")})
      {:ok, _} = Cart.add(user, variant.id, 2)
      {:ok, _} = Cart.add(user, other.id, 3)

      assert %{count: 5, subtotal: subtotal} = Cart.summary(user)
      assert Money.equal?(subtotal, Money.new(:USD, "56.50"))
    end

    test "agrees with the full cart listing, ignoring unavailable lines", %{
      user: user,
      variant: variant
    } do
      gone = variant_fixture(nil, %{retail_price: Money.new(:USD, "99")})
      {:ok, _} = Cart.add(user, variant.id, 1)
      {:ok, _} = Cart.add(user, gone.id, 4)
      gone |> Ecto.Changeset.change(available: false) |> Repo.update!()

      lines = Cart.list(user)
      summary = Cart.summary(user)

      assert summary.count == Cart.item_count(lines)
      assert Money.equal?(summary.subtotal, Cart.subtotal(lines))
      assert summary.count == 1
    end

    test "never includes another member's cart", %{user: user, variant: variant} do
      {:ok, _} = Cart.add(user_fixture(), variant.id, 7)
      assert %{count: 0} = Cart.summary(user)
    end
  end

  test "omits image upload_data and unused catalog columns", %{
    user: user,
    variant: variant
  } do
    image =
      image_fixture(%{
        upload_data: %{"original" => "fat-json"},
        content_hash: "abc123"
      })

    variant
    |> Ecto.Changeset.change(%{
      image_id: image.id,
      sku: "TEE-BLK-M",
      source_image_url: "https://printful.example/tee.png"
    })
    |> Repo.update!()

    {:ok, _} = Cart.add(user, variant.id, 1)

    {lines, fat_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Cart.list(user) end,
        pattern: ~r/upload_data|content_hash|source_image_url|sku/i,
        caller_pids: [self()]
      )

    [line] = lines
    assert line.variant.id == variant.id
    assert line.variant.printful_variant_id
    assert line.variant.image.id == image.id
    assert is_nil(line.variant.image.upload_data)
    assert is_nil(line.variant.sku)
    assert fat_cols == 0
  end
end
