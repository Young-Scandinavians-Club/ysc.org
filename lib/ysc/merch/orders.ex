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
  alias Ysc.Merch.{Cart, Order, OrderItem, ShippingAddress}
  alias Ysc.Repo

  @detail_preloads [
    items: [variant: :image],
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
      preload: [items: [variant: :image]]
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

  @doc "The member's own order, or `nil` (also for other members' orders)."
  def get_user_order(%User{id: user_id}, id) do
    case get_order(id) do
      %Order{user_id: ^user_id} = order -> order
      _ -> nil
    end
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
      preload: [items: [variant: :image]]
    )
    |> Repo.all()
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
      preload: [items: [variant: :image]]
    )
  end
end
