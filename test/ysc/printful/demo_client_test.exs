defmodule Ysc.Printful.DemoClientTest do
  # Swaps global app env, and the demo store is a named process.
  use Ysc.DataCase, async: false

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.MerchFixtures

  alias Ysc.Merch
  alias Ysc.Merch.{Cart, Fulfillment, Order, Orders, Product, Shipping, Variant}
  alias Ysc.Printful
  alias Ysc.Printful.{DemoClient, Error}

  setup :verify_on_exit!

  @png File.read!(Path.expand("../../support/fixtures/tiny.png", __DIR__))

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    keys = [:printful_client, :stripe_client, :quickbooks_client]
    originals = for key <- keys, do: {key, Application.get_env(:ysc, key)}
    Application.put_env(:ysc, :printful_client, DemoClient)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    on_exit(fn ->
      Enum.each(originals, fn {k, v} -> Application.put_env(:ysc, k, v) end)
    end)

    stub_quickbooks_sync!()

    Req.Test.stub(Ysc.Merch.ImageImport, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/png")
      |> Plug.Conn.send_resp(200, @png)
    end)

    %{admin: user_fixture(%{role: "admin"})}
  end

  test "demo mode is detected" do
    assert Printful.demo_mode?()
    Application.put_env(:ysc, :printful_client, Ysc.Printful.Client)
    refute Printful.demo_mode?()
  end

  describe "catalog" do
    test "syncs a realistic catalog, images included", %{admin: admin} do
      assert {:ok,
              %{products: 4, variants: variants, failed: 0, images_failed: 0}} =
               Merch.sync_catalog(admin)

      # tee 2x5, hoodie 2x4, sticker 1, mug 2
      assert variants == 10 + 8 + 1 + 2

      products = Merch.list_shop_products()

      assert Enum.map(products, & &1.name) |> Enum.sort() == [
               "Camp Mug",
               "Club Hoodie",
               "Tomte Sticker",
               "Viking Tee"
             ]

      assert Enum.all?(products, & &1.image_id)

      tee = Enum.find(products, &(&1.name == "Viking Tee"))

      assert Enum.map(tee.variants, & &1.color) |> Enum.uniq() |> Enum.sort() ==
               ["Black", "White"]

      assert Money.equal?(Merch.starting_price(tee), Money.new(:USD, "28"))
    end

    test "syncing twice changes nothing" do
      admin = user_fixture(%{role: "admin"})
      assert {:ok, _} = Merch.sync_catalog(admin)

      counts =
        {Repo.aggregate(Product, :count), Repo.aggregate(Variant, :count)}

      assert {:ok, %{removed: 0}} = Merch.sync_catalog(admin)

      assert {Repo.aggregate(Product, :count), Repo.aggregate(Variant, :count)} ==
               counts
    end
  end

  describe "shipping" do
    setup %{admin: admin} do
      {:ok, _} = Merch.sync_catalog(admin)
      %{variant: Repo.one(from(v in Variant, where: v.name == "Tomte Sticker"))}
    end

    test "quotes two methods that grow with quantity", %{variant: variant} do
      address = shipping_address_fixture()

      assert {:ok, [standard, express]} =
               Shipping.options(address, [%{variant: variant, quantity: 1}])

      assert standard.id == "STANDARD"
      assert Money.equal?(standard.rate, Money.new(:USD, "4.99"))
      assert Money.equal?(express.rate, Money.new(:USD, "14.99"))

      assert {:ok, [standard3, _]} =
               Shipping.options(address, [%{variant: variant, quantity: 3}])

      assert Money.equal?(standard3.rate, Money.new(:USD, "8.97"))
    end

    test "rejects the demo's bad ZIP so the error path can be tried", %{
      variant: variant
    } do
      address = shipping_address_fixture(%{"zip" => "00000"})

      assert {:error, {:rejected, "Zip code does not match state"}} =
               Shipping.options(address, [%{variant: variant, quantity: 1}])
    end
  end

  describe "orders" do
    test "create, find by external id, confirm and cancel" do
      payload = %{
        external_id: "MRC-DEMO-1",
        shipping: "STANDARD",
        recipient: %{name: "A"},
        items: [%{sync_variant_id: 900_300, quantity: 2}]
      }

      assert {:ok, %{"id" => id, "status" => "draft"}} =
               DemoClient.create_order(payload, false)

      assert {:ok, %{"id" => ^id}} =
               DemoClient.get_order_by_external_id("MRC-DEMO-1")

      assert {:ok, %{"status" => "pending"}} = DemoClient.confirm_order(id)
      assert {:ok, %{"status" => "canceled"}} = DemoClient.cancel_order(id)
    end

    test "creating the same external id twice returns the first order" do
      payload = %{
        external_id: "MRC-DEMO-2",
        shipping: "STANDARD",
        recipient: %{},
        items: []
      }

      {:ok, first} = DemoClient.create_order(payload, true)
      {:ok, second} = DemoClient.create_order(payload, true)
      assert first["id"] == second["id"]
    end

    test "unknown orders are not found" do
      assert {:error, %Error{type: :not_found}} =
               DemoClient.get_order_by_external_id("nope")

      assert {:error, %Error{type: :not_found}} =
               DemoClient.get_order(123_456_789)

      assert {:error, %Error{type: :not_found}} =
               DemoClient.confirm_order(123_456_789)
    end

    test "costs come from item base cost plus shipping" do
      payload = %{items: [%{sync_variant_id: 900_300, quantity: 2}]}
      assert {:ok, %{"costs" => costs}} = DemoClient.estimate_costs(payload)
      # 2 x 1.80 base cost + (4.99 + 1.99) shipping
      assert costs["subtotal"] == "3.60"
      assert costs["shipping"] == "6.98"
      assert costs["total"] == "10.58"
    end
  end

  test "a member can shop, pay and have the order land in the demo printer", %{
    admin: admin
  } do
    {:ok, _} = Merch.sync_catalog(admin)

    member =
      member_fixture()
      |> Ecto.Changeset.change(stripe_id: "cus_demo")
      |> Repo.update!()

    mug = Repo.one(from(v in Variant, where: v.name == "Camp Mug / Black"))
    {:ok, _} = Cart.add(member, mug.id, 2)

    {:ok, [option | _]} =
      Shipping.options(shipping_address_fixture(), [
        %{variant: mug, quantity: 2}
      ])

    {:ok, order} =
      Orders.create_pending_purchase(
        member,
        Cart.list(member),
        shipping_address_fixture(),
        option
      )

    # 2 x 16.00 + 6.98 shipping
    assert Money.equal?(order.total_amount, Money.new(:USD, "38.98"))

    {:ok, order} = Orders.attach_payment_intent(order, "pi_demo")

    paid =
      struct!(Stripe.PaymentIntent,
        id: "pi_demo",
        status: "succeeded",
        amount: 3898,
        metadata: %{"merch_order_id" => order.id}
      )

    assert {:ok,
            %Order{status: :submitted, printful_order_id: printful_id} = done} =
             Fulfillment.process_successful_payment(paid)

    assert Money.positive?(done.printful_cost)

    assert {:ok, %{"external_id" => ref, "status" => "pending"}} =
             DemoClient.get_order(printful_id)

    assert ref == order.reference_id
  end
end
