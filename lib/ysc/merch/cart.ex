defmodule Ysc.Merch.Cart do
  @moduledoc """
  A member's merch cart, stored in the database so it follows them across
  devices.

  Lines whose variant has since been hidden, sold out or removed are reported
  as `:unavailable` rather than silently dropped, so the member sees why the
  cart changed. Checkout only ever uses `available_lines/1`.
  """
  import Ecto.Query, warn: false

  alias Ysc.Accounts.User
  alias Ysc.Media.Image
  alias Ysc.Merch.{CartEvents, CartItem, Product, Variant}
  alias Ysc.Repo

  # Cart / checkout need Printful's variant id for shipping quotes. Skip
  # sku / source URLs and image `upload_data`.
  @cart_image_fields [
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
  @cart_product_fields [:id, :name, :status, :image_id]
  @cart_variant_fields [
    :id,
    :product_id,
    :name,
    :size,
    :color,
    :retail_price,
    :available,
    :image_id,
    :printful_variant_id
  ]

  @type line :: %{
          item: CartItem.t(),
          variant: Variant.t(),
          product: Product.t(),
          quantity: pos_integer(),
          unit_price: Money.t(),
          line_total: Money.t(),
          available?: boolean()
        }

  @doc """
  The member's cart lines, oldest first, with variant, product and display
  images loaded. Keeps `printful_variant_id` for shipping quotes.
  """
  @spec list(User.t()) :: [line()]
  def list(%User{id: user_id}) do
    from(c in CartItem,
      where: c.user_id == ^user_id,
      order_by: [asc: c.inserted_at, asc: c.id],
      preload: [variant: ^cart_variant_query()]
    )
    |> Repo.all()
    |> Enum.map(&to_line/1)
  end

  defp cart_variant_query do
    from(v in Variant,
      select: struct(v, ^@cart_variant_fields),
      preload: [
        image: ^cart_image_query(),
        product: ^cart_product_query()
      ]
    )
  end

  defp cart_product_query do
    from(p in Product,
      select: struct(p, ^@cart_product_fields),
      preload: [image: ^cart_image_query()]
    )
  end

  defp cart_image_query do
    from(i in Image, select: struct(i, ^@cart_image_fields))
  end

  defp to_line(%CartItem{variant: variant} = item) do
    product = variant.product

    %{
      item: item,
      variant: variant,
      product: product,
      quantity: item.quantity,
      unit_price: variant.retail_price,
      line_total: Money.mult!(variant.retail_price, item.quantity),
      available?: variant.available and product.status == :active
    }
  end

  @doc "Lines that can actually be bought right now."
  @spec available_lines([line()]) :: [line()]
  def available_lines(lines), do: Enum.filter(lines, & &1.available?)

  @doc "Sum of the available lines."
  @spec subtotal([line()]) :: Money.t()
  def subtotal(lines) do
    lines
    |> available_lines()
    |> Enum.reduce(Money.new(0, :USD), fn line, acc ->
      Money.add!(acc, line.line_total)
    end)
  end

  @doc "Total number of items across available lines."
  @spec item_count([line()]) :: non_neg_integer()
  def item_count(lines) do
    lines |> available_lines() |> Enum.map(& &1.quantity) |> Enum.sum()
  end

  @doc """
  Number of items in the cart, for the nav badge. One cheap query.
  """
  @spec count(User.t() | nil) :: non_neg_integer()
  def count(nil), do: 0

  def count(%User{id: user_id}) do
    from(c in CartItem,
      join: v in assoc(c, :variant),
      join: p in assoc(v, :product),
      where:
        c.user_id == ^user_id and v.available == true and p.status == :active,
      select: coalesce(sum(c.quantity), 0)
    )
    |> Repo.one()
    |> to_integer()
  end

  @doc """
  Item count and subtotal of what can be bought, in one query. Powers the
  floating cart dock, so it avoids loading lines and images.
  """
  @spec summary(User.t() | nil) :: %{
          count: non_neg_integer(),
          subtotal: Money.t()
        }
  def summary(nil), do: %{count: 0, subtotal: Money.new(0, :USD)}

  def summary(%User{id: user_id}) do
    {count, amount} =
      from(c in CartItem,
        join: v in assoc(c, :variant),
        join: p in assoc(v, :product),
        where:
          c.user_id == ^user_id and v.available == true and p.status == :active,
        select:
          {coalesce(sum(c.quantity), 0),
           coalesce(
             sum(
               type(c.quantity, :decimal) *
                 fragment("(?).amount", v.retail_price)
             ),
             0
           )}
      )
      |> Repo.one()

    %{count: to_integer(count), subtotal: Money.new(amount || 0, :USD)}
  end

  defp to_integer(%Decimal{} = decimal), do: Decimal.to_integer(decimal)
  defp to_integer(int) when is_integer(int), do: int

  @doc """
  Adds `quantity` of a variant, merging with any existing line. The result is
  capped at `CartItem.max_quantity/0`.

  Returns `{:error, :unavailable}` for a hidden, sold-out or unknown variant.
  """
  @spec add(User.t(), String.t(), integer()) ::
          {:ok, CartItem.t()} | {:error, :unavailable | Ecto.Changeset.t()}
  def add(%User{} = user, variant_id, quantity)
      when is_binary(variant_id) and is_integer(quantity) and quantity > 0 do
    with {:ok, _variant} <- fetch_available_variant(variant_id) do
      max = CartItem.max_quantity()

      # One statement, so two requests adding the same variant at once both
      # count instead of one hitting the unique index.
      result =
        %CartItem{user_id: user.id, variant_id: variant_id}
        |> CartItem.changeset(%{quantity: min(quantity, max)})
        |> Repo.insert(
          on_conflict:
            from(c in CartItem,
              update: [
                set: [
                  quantity:
                    fragment("LEAST(? + ?, ?)", c.quantity, ^quantity, ^max),
                  updated_at: ^now()
                ]
              ]
            ),
          conflict_target: [:user_id, :variant_id],
          returning: true
        )

      with {:ok, _item} <- result do
        CartEvents.record(user.id, [{variant_id, :added, min(quantity, max)}])
      end

      result
    end
  end

  @doc """
  Sets a line's quantity. A quantity of zero or less removes the line.
  """
  @spec set_quantity(User.t(), String.t(), integer()) ::
          {:ok, CartItem.t() | nil} | {:error, Ecto.Changeset.t()}
  def set_quantity(%User{} = user, variant_id, quantity)
      when is_binary(variant_id) and is_integer(quantity) do
    cond do
      quantity <= 0 ->
        remove(user, variant_id)
        {:ok, nil}

      true ->
        {_count, items} =
          from(c in CartItem,
            where: c.user_id == ^user.id and c.variant_id == ^variant_id,
            select: c
          )
          |> Repo.update_all(
            set: [
              quantity: min(quantity, CartItem.max_quantity()),
              updated_at: now()
            ]
          )

        case List.first(items) do
          nil ->
            {:ok, nil}

          item ->
            CartEvents.record(user.id, [
              {variant_id, :quantity_set, item.quantity}
            ])

            {:ok, item}
        end
    end
  end

  @doc """
  Removes a line. Always succeeds.

  `reason` is what the cart event log records: `:removed` when the member
  took the line out, `:purchased` when its order was fulfilled.
  """
  @spec remove(User.t(), String.t(), :removed | :purchased) :: :ok
  def remove(%User{id: user_id}, variant_id, reason \\ :removed)
      when is_binary(variant_id) and reason in [:removed, :purchased] do
    {_count, quantities} =
      from(c in CartItem,
        where: c.user_id == ^user_id and c.variant_id == ^variant_id,
        select: c.quantity
      )
      |> Repo.delete_all()

    CartEvents.record(
      user_id,
      Enum.map(quantities, &{variant_id, reason, &1})
    )
  end

  @doc "Empties the cart."
  @spec clear(User.t()) :: :ok
  def clear(%User{id: user_id}) do
    {_count, lines} =
      from(c in CartItem,
        where: c.user_id == ^user_id,
        select: {c.variant_id, c.quantity}
      )
      |> Repo.delete_all()

    CartEvents.record(
      user_id,
      Enum.map(lines, fn {variant_id, quantity} ->
        {variant_id, :removed, quantity}
      end)
    )
  end

  defp fetch_available_variant(variant_id) do
    query =
      from(v in Variant,
        join: p in assoc(v, :product),
        where:
          v.id == ^variant_id and v.available == true and p.status == :active
      )

    case Repo.one(query) do
      nil -> {:error, :unavailable}
      variant -> {:ok, variant}
    end
  rescue
    Ecto.Query.CastError -> {:error, :unavailable}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    from(c in CartItem,
      where: c.user_id == ^Fixtures.ulid(),
      order_by: [asc: c.inserted_at, asc: c.id],
      preload: [variant: ^cart_variant_query()]
    )
  end
end
