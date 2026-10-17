defmodule Ysc.Merch.Orders do
  @moduledoc """
  Creating and reading merch orders.

  A purchase order is created `:pending` at the payment step with everything
  snapshotted (items, prices, address, Printful's shipping quote), so later
  catalog edits never change what a member is charged. Payment, fulfillment and
  Printful submission live in `Ysc.Merch.Fulfillment`.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Ysc.Accounts.User
  alias Ysc.Media.Image
  alias Ysc.Merch.{Cart, Order, OrderItem, Shipment, ShippingAddress, Variant}
  alias Ysc.Repo

  @user_order_fields [:id, :reference_id, :status, :total_amount, :inserted_at]
  @user_order_item_fields [:id, :order_id, :name, :quantity, :variant_id]
  @user_order_variant_fields [:id, :image_id]
  @user_order_image_fields [
    :id,
    :title,
    :alt_text,
    :optimized_image_path,
    :raw_image_path,
    :thumbnail_path,
    :blur_hash,
    :width,
    :height
  ]

  # Receipt page: address, totals, payment-intent polling. Skip Printful ids,
  # the member User row, event, and granted_by (purchase orders have none).
  @user_order_detail_fields [
    :id,
    :user_id,
    :reference_id,
    :kind,
    :status,
    :inserted_at,
    :recipient_name,
    :address1,
    :address2,
    :city,
    :state_code,
    :zip,
    :subtotal,
    :shipping_amount,
    :total_amount,
    :payment_intent_id
  ]
  @user_order_detail_item_fields @user_order_item_fields ++ [:unit_price]
  @user_order_shipment_fields [
    :id,
    :order_id,
    :carrier,
    :service,
    :tracking_number,
    :tracking_url,
    :status,
    :shipped_at,
    :delivered_at
  ]

  @detail_preloads [
    items: [variant: [:image, product: :image]],
    shipments: [],
    user: [],
    event: [],
    granted_by: []
  ]

  @doc """
  Creates the `:pending` purchase order for a member's checkout.

  `lines` are the cart lines being bought, `option` the shipping option the
  member chose (from `Ysc.Merch.Shipping.options/2`). If the member already has
  an identical pending order (same items, prices, address and shipping), that
  one is returned instead of creating another.

  Errors: `:empty_cart`, `:unavailable_items` (a line is no longer sellable),
  or an `Ecto.Changeset`.
  """
  @spec create_pending_purchase(
          User.t(),
          [Cart.line()],
          ShippingAddress.t(),
          map()
        ) ::
          {:ok, Order.t()}
          | {:error, :empty_cart | :unavailable_items | Ecto.Changeset.t()}
  def create_pending_purchase(
        %User{} = user,
        lines,
        %ShippingAddress{} = address,
        option
      ) do
    cond do
      lines == [] ->
        {:error, :empty_cart}

      Enum.any?(lines, &(not &1.available?)) ->
        {:error, :unavailable_items}

      true ->
        attrs = purchase_attrs(user, lines, address, option)

        case find_reusable_pending(user, lines, attrs) do
          %Order{} = order -> {:ok, order}
          nil -> insert_purchase(user, lines, attrs)
        end
    end
  end

  defp purchase_attrs(user, lines, address, option) do
    subtotal = Cart.subtotal(lines)

    address
    |> ShippingAddress.to_order_attrs()
    |> Map.update(:email, user.email, &(&1 || user.email))
    |> Map.merge(%{
      shipping_method: option.id,
      subtotal: subtotal,
      shipping_amount: option.rate,
      total_amount: Money.add!(subtotal, option.rate)
    })
  end

  # Dialyzer false positive on Ecto.Multi pipelines (same as elsewhere in the app).
  @dialyzer {:nowarn_function, insert_purchase: 3}
  defp insert_purchase(user, lines, attrs) do
    Multi.new()
    |> Multi.run(:order, fn repo, _ ->
      %Order{}
      |> Order.purchase_changeset(attrs, user.id)
      |> repo.insert_with_reference_retry(Order)
    end)
    |> Multi.run(:items, fn repo, %{order: order} ->
      lines
      |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
        %OrderItem{order_id: order.id}
        |> OrderItem.changeset(%{
          variant_id: line.variant.id,
          quantity: line.quantity,
          name: item_name(line),
          unit_price: line.unit_price
        })
        |> repo.insert()
        |> case do
          {:ok, item} -> {:cont, {:ok, [item | acc]}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, get_order!(order.id)}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  # "Club Tee - Black / M" reads fine on a receipt; fall back to the product.
  defp item_name(%{variant: variant, product: product}) do
    if variant.name in [nil, ""], do: product.name, else: variant.name
  end

  defp find_reusable_pending(user, lines, attrs) do
    wanted = signature(lines, attrs)

    from(o in Order,
      where:
        o.user_id == ^user.id and o.kind == :purchase and o.status == :pending,
      where: o.inserted_at > ago(24, "hour"),
      order_by: [desc: o.inserted_at],
      limit: 5,
      preload: [:items]
    )
    |> Repo.all()
    |> Enum.find(&(order_signature(&1) == wanted))
  end

  defp signature(lines, attrs) do
    {
      lines
      |> Enum.map(
        &{&1.variant.id, &1.quantity, Money.to_decimal(&1.unit_price)}
      )
      |> Enum.sort(),
      address_signature(attrs),
      attrs.shipping_method,
      Money.to_decimal(attrs.shipping_amount)
    }
  end

  defp order_signature(order) do
    {
      order.items
      |> Enum.map(
        &{&1.variant_id, &1.quantity, Money.to_decimal(&1.unit_price)}
      )
      |> Enum.sort(),
      address_signature(order),
      order.shipping_method,
      Money.to_decimal(order.shipping_amount)
    }
  end

  defp address_signature(source) do
    for key <- [
          :recipient_name,
          :address1,
          :address2,
          :city,
          :state_code,
          :zip,
          :country_code
        ],
        do: Map.get(source, key)
  end

  ## Reading

  def get_order(id) do
    Order |> Repo.get(id) |> preload_detail()
  rescue
    Ecto.Query.CastError -> nil
  end

  def get_order!(id), do: Order |> Repo.get!(id) |> preload_detail()

  @doc """
  The member's own order for the receipt page, or `nil` (also for other
  members' orders).

  Receipt columns, slim item thumbs, and tracking parcels. Printful
  submission still uses fat `get_order/1`.
  """
  def get_user_order(%User{id: user_id}, id) do
    user_id
    |> user_order_query(id)
    |> Repo.one()
  rescue
    Ecto.Query.CastError -> nil
  end

  defp user_order_query(user_id, id) do
    from(o in Order,
      where: o.id == ^id and o.user_id == ^user_id,
      select: struct(o, ^@user_order_detail_fields),
      preload: [
        items: ^user_order_detail_item_query(),
        shipments: ^user_order_shipment_query()
      ]
    )
  end

  def get_order_by_payment_intent(payment_intent_id)
      when is_binary(payment_intent_id) do
    Order
    |> Repo.get_by(payment_intent_id: payment_intent_id)
    |> preload_detail()
  end

  def get_order_by_printful_id(printful_order_id)
      when is_integer(printful_order_id) do
    Order
    |> Repo.get_by(printful_order_id: printful_order_id)
    |> preload_detail()
  end

  def get_order_by_reference(reference_id) when is_binary(reference_id) do
    Order |> Repo.get_by(reference_id: reference_id) |> preload_detail()
  end

  @doc "A member's purchases, newest first (not their pending checkouts)."
  def list_user_orders(%User{id: user_id}) do
    from(o in Order,
      where:
        o.user_id == ^user_id and o.kind == :purchase and o.status != :pending,
      order_by: [desc: o.inserted_at],
      select: struct(o, ^@user_order_fields),
      preload: [items: ^user_order_item_query()]
    )
    |> Repo.all()
  end

  defp user_order_item_query do
    from(i in OrderItem,
      select: struct(i, ^@user_order_item_fields),
      preload: [variant: ^user_order_variant_query()]
    )
  end

  defp user_order_detail_item_query do
    from(i in OrderItem,
      select: struct(i, ^@user_order_detail_item_fields),
      preload: [variant: ^user_order_variant_query()]
    )
  end

  defp user_order_shipment_query do
    from(s in Shipment, select: struct(s, ^@user_order_shipment_fields))
  end

  defp user_order_variant_query do
    from(v in Variant,
      select: struct(v, ^@user_order_variant_fields),
      preload: [image: ^user_order_image_query()]
    )
  end

  defp user_order_image_query do
    from(i in Image, select: struct(i, ^@user_order_image_fields))
  end

  defp preload_detail(nil), do: nil
  defp preload_detail(order), do: Repo.preload(order, @detail_preloads)

  ## Updates

  @doc "Records the Stripe PaymentIntent used to pay for a pending order."
  def attach_payment_intent(%Order{status: :pending} = order, payment_intent_id) do
    order
    |> Ecto.Changeset.change(payment_intent_id: payment_intent_id)
    |> Repo.update()
  end

  def attach_payment_intent(%Order{}, _), do: {:error, :not_pending}

  @doc "Cancels a still-pending order. Paid orders are never touched here."
  def cancel_pending(%Order{id: id}, reason \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(o in Order, where: o.id == ^id and o.status == :pending)
      |> Repo.update_all(
        set: [
          status: :canceled,
          canceled_at: now,
          failure_reason: reason,
          updated_at: now
        ]
      )

    if count == 1, do: :ok, else: {:error, :not_pending}
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    from(o in Order,
      where:
        o.user_id == ^Fixtures.ulid() and o.kind == :purchase and
          o.status != :pending,
      order_by: [desc: o.inserted_at],
      select: struct(o, ^@user_order_fields),
      preload: [items: ^user_order_item_query()]
    )
  end

  @doc false
  def ci_query_explain_user_order_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_order_query(Fixtures.ulid(), Fixtures.ulid())
  end
end
