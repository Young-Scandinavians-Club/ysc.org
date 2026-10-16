defmodule Ysc.MerchFixtures do
  @moduledoc """
  Test helpers for the merch shop.
  """

  alias Ysc.Merch.{Order, OrderItem, Product, Variant}
  alias Ysc.Repo

  def product_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Product{}
    |> Product.sync_changeset(
      Map.merge(
        %{printful_product_id: n, name: "Product #{n}"},
        Map.drop(attrs, [:status, :sort_order, :description])
      )
    )
    # Club-owned fields aren't cast by the sync changeset.
    |> Ecto.Changeset.change(
      Map.take(attrs, [:status, :sort_order, :description])
    )
    |> Repo.insert!()
  end

  def variant_fixture(product \\ nil, attrs \\ %{}) do
    product = product || product_fixture()
    n = System.unique_integer([:positive])

    %Variant{}
    |> Variant.sync_changeset(
      Map.merge(
        %{
          product_id: product.id,
          printful_sync_variant_id: n,
          printful_variant_id: n + 1,
          name: "Variant #{n}",
          retail_price: Money.new(:USD, "25")
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  A club-paid order placed by `granted_by`. Pass `:status`, `:event_id`,
  `:estimated_cost`, `:printful_cost`, `:kind`, `:items` (list of
  `{variant, quantity}`) to shape it.
  """
  def admin_order_fixture(granted_by, attrs \\ %{}) do
    {extra, attrs} =
      Map.split(attrs, [
        :status,
        :printful_cost,
        :kind,
        :items,
        :inserted_at,
        :printful_order_id
      ])

    base = %{
      purpose: "Happy hour giveaway",
      recipient_name: "Ada Admin",
      address1: "1 Market St",
      city: "San Francisco",
      state_code: "CA",
      zip: "94105",
      country_code: "US",
      estimated_cost: Money.new(:USD, "50")
    }

    order =
      %Order{}
      |> Order.admin_comp_changeset(Map.merge(base, attrs), granted_by.id)
      |> Ecto.Changeset.change(
        extra
        |> Map.take([
          :status,
          :printful_cost,
          :kind,
          :inserted_at,
          :printful_order_id
        ])
        |> Map.to_list()
      )
      |> Repo.insert!()

    items = Map.get(extra, :items, [{variant_fixture(), 1}])

    for {variant, quantity} <- items do
      %OrderItem{order_id: order.id}
      |> OrderItem.changeset(%{
        variant_id: variant.id,
        quantity: quantity,
        name: variant.name,
        unit_price: variant.retail_price
      })
      |> Repo.insert!()
    end

    order
  end

  @doc "A valid `Ysc.Merch.ShippingAddress` for checkout tests."
  def shipping_address_fixture(attrs \\ %{}) do
    {:ok, address} =
      Ysc.Merch.ShippingAddress.validate(
        Map.merge(
          %{
            "name" => "Ada Lovelace",
            "address1" => "1 Market St",
            "city" => "San Francisco",
            "state_code" => "CA",
            "zip" => "94105",
            "phone" => "415-555-0100"
          },
          attrs
        )
      )

    address
  end

  @doc "A shipping option as returned by `Ysc.Merch.Shipping.options/2`."
  def shipping_option_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        id: "STANDARD",
        name: "Flat Rate",
        rate: Money.new(:USD, "5.95"),
        min_days: 3,
        max_days: 5
      },
      attrs
    )
  end

  @doc """
  Puts `quantity` of `variant` in `user`'s cart and returns the cart lines.
  """
  def cart_lines_fixture(user, entries) do
    for {variant, quantity} <- entries do
      {:ok, _} = Ysc.Merch.Cart.add(user, variant.id, quantity)
    end

    Ysc.Merch.Cart.list(user)
  end

  @doc """
  Stubs every QuickBooks call a merch sale makes, so the payment's accounting
  sync completes. Call after pointing `:quickbooks_client` at the mock.
  """
  def stub_quickbooks_sync! do
    alias Ysc.Quickbooks.ClientMock

    Mox.stub(ClientMock, :create_customer, fn _ ->
      {:ok, %{"Id" => "qb_customer"}}
    end)

    Mox.stub(ClientMock, :create_sales_receipt, fn _, _ ->
      {:ok, %{"Id" => "qb_sales_receipt", "TotalAmt" => "0.00"}}
    end)

    Mox.stub(ClientMock, :query_account_by_name, fn _ -> {:ok, "qb_account"} end)

    Mox.stub(ClientMock, :query_class_by_name, fn _ -> {:ok, "qb_class"} end)
    Mox.stub(ClientMock, :get_or_create_item, fn _, _ -> {:ok, "qb_item"} end)
  end

  @doc "A user with an active (lifetime) membership, able to use the shop."
  def member_fixture(attrs \\ %{}) do
    Ysc.AccountsFixtures.user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

  @doc """
  A member purchase in `status`, as if it had been checked out (real snapshot,
  totals $2 x $25 + $5.95 shipping), already known to Printful as
  `printful_order_id`.
  """
  def purchase_order_fixture(member, status \\ :submitted, attrs \\ %{}) do
    variant =
      variant_fixture(nil, %{
        retail_price: Money.new(:USD, "25"),
        name: "Club Tee / Black / M"
      })

    lines = cart_lines_fixture(member, [{variant, 2}])

    {:ok, order} =
      Ysc.Merch.Orders.create_pending_purchase(
        member,
        lines,
        shipping_address_fixture(),
        shipping_option_fixture()
      )

    printful_order_id =
      Map.get(
        attrs,
        :printful_order_id,
        System.unique_integer([:positive]) + 1_000
      )

    order
    |> Ecto.Changeset.change(
      status: status,
      printful_order_id:
        if(status in [:pending, :paid, :submitting],
          do: nil,
          else: printful_order_id
        )
    )
    |> Repo.update!()
    |> then(&Ysc.Merch.Orders.get_order!(&1.id))
  end

  @doc "A Printful shipment object as it appears in webhooks and order records."
  def printful_shipment(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => System.unique_integer([:positive]) + 5_000,
        "carrier" => "USPS",
        "service" => "Priority Mail",
        "tracking_number" => "9400111899223197428490",
        "tracking_url" =>
          "https://tools.usps.com/go/TrackConfirmAction?tLabels=9400111899223197428490",
        "reshipment" => false,
        "shipped_at" => System.os_time(:second)
      },
      attrs
    )
  end

  @doc """
  A Printful webhook payload (string keys, as received) for `order`.
  `data` is merged into the payload's `"data"` object.
  """
  def printful_event(type, order, data \\ %{}, order_fields \\ %{}) do
    printful_order =
      Map.merge(
        %{
          "id" => order.printful_order_id,
          "external_id" => order.reference_id,
          "status" => "inprocess"
        },
        order_fields
      )

    %{
      "type" => type,
      "created" => System.os_time(:second),
      "retries" => 0,
      "store" => 123,
      "data" => Map.merge(%{"order" => printful_order}, data)
    }
  end

  @doc "A media library image (no file behind it; fine for rendering and gallery tests)."
  def image_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])
    uploader = Ysc.AccountsFixtures.user_fixture(%{role: "admin"})

    struct!(
      Ysc.Media.Image,
      Map.merge(
        %{
          user_id: uploader.id,
          title: "Photo #{n}",
          raw_image_path: "https://media.example.test/photo-#{n}.jpg"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc """
  Puts `image` in `product`'s gallery. Pass `:color`, `:position`, `:source`.
  """
  def gallery_photo_fixture(product, image \\ nil, attrs \\ %{}) do
    image = image || image_fixture()

    %Ysc.Merch.ProductImage{}
    |> Ysc.Merch.ProductImage.changeset(
      Map.merge(
        %{
          product_id: product.id,
          image_id: image.id,
          position: 0,
          source: :admin
        },
        attrs
      )
    )
    |> Repo.insert!()
    |> Repo.preload(:image)
  end
end
