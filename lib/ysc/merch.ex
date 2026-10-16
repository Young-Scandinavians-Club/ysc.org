defmodule Ysc.Merch do
  @moduledoc """
  Club merch shop, fulfilled by Printful.

  Products and variants are designed and priced in Printful and mirrored into
  our database (see `Ysc.Merch.CatalogSync`), so shop pages never call
  Printful. Orders, carts and fulfillment are added on top of this catalog.
  """
  import Ecto.Query, warn: false

  alias Ysc.Media.Image
  alias Ysc.Merch.{CatalogSync, Product, ProductImage, Variant}
  alias Ysc.Repo

  # Shop tiles and product pages only need display paths. Skipping
  # `upload_data` / `content_hash` keeps Printful mockup JSON off the listing.
  @shop_image_fields [
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

  # Listing tiles: name, sort, "new" badge, starting price, colors/sizes.
  # Omits `description` (up to 5k) and Printful sync columns.
  @shop_listing_product_fields [
    :id,
    :name,
    :status,
    :sort_order,
    :image_id,
    :inserted_at
  ]

  # Product page also renders the club-written description.
  @shop_product_fields @shop_listing_product_fields ++ [:description]

  @shop_variant_fields [
    :id,
    :product_id,
    :name,
    :size,
    :color,
    :retail_price,
    :available,
    :image_id
  ]

  @shop_gallery_fields [:id, :product_id, :image_id, :color, :position]

  ## Catalog (member-facing)

  @doc """
  Products shown in the shop: active, with at least one available variant.

  Listing columns only: name, sort, timestamps, available variants (color /
  size / price), and display-image paths. Skips descriptions, Printful ids,
  and `images.upload_data`.
  """
  def list_shop_products do
    shop_products_query(@shop_listing_product_fields)
    |> Repo.all()
  end

  @doc """
  A single shop product with its available variants, or `nil` when it is
  hidden, removed or has nothing left to sell.
  """
  def get_shop_product(id) do
    shop_products_query(@shop_product_fields)
    |> where([p], p.id == ^id)
    |> Repo.one()
  end

  defp shop_products_query(product_fields) do
    from(p in Product,
      as: :product,
      where: p.status == :active,
      where:
        exists(
          from(v in Variant,
            where:
              v.product_id == parent_as(:product).id and v.available == true,
            select: 1
          )
        ),
      order_by: [asc: p.sort_order, asc: p.name],
      select: struct(p, ^product_fields),
      preload: [
        image: ^shop_image_query(),
        variants: ^shop_variants_query(),
        gallery_images: ^gallery_images_query()
      ]
    )
  end

  defp shop_variants_query do
    from(v in Variant,
      where: v.available == true,
      order_by: [asc: fragment("(?).amount", v.retail_price), asc: v.name],
      select: struct(v, ^@shop_variant_fields),
      preload: [image: ^shop_image_query()]
    )
  end

  defp gallery_images_query do
    from(g in ProductImage,
      order_by: [asc: g.position, asc: g.inserted_at],
      select: struct(g, ^@shop_gallery_fields),
      preload: [image: ^shop_image_query()]
    )
  end

  # Admin photo controls key off `source` (`:printful` vs `:admin`). The shop
  # gallery query omits that enum so listing structs default it to `:admin`.
  defp admin_gallery_images_query do
    from(g in ProductImage,
      order_by: [asc: g.position, asc: g.inserted_at],
      preload: [image: ^shop_image_query()]
    )
  end

  defp shop_image_query do
    from(i in Image, select: struct(i, ^@shop_image_fields))
  end

  ## Gallery

  @doc """
  The photos to show for `product` while `color` is selected, in display order.

  Photos tied to that color come first, then photos that belong to every
  color. With no gallery at all it falls back to the color's variant image,
  then the product image. May be empty (the page then shows a placeholder).

  Expects `gallery_images` (with images) and `variants` to be loaded, as
  `get_shop_product/1` does.
  """
  @spec gallery(Product.t(), String.t() | nil) :: [struct()]
  def gallery(%Product{} = product, color) do
    photos = product.gallery_images
    specific = if color, do: Enum.filter(photos, &(&1.color == color)), else: []
    general = Enum.filter(photos, &is_nil(&1.color))

    case Enum.uniq_by(specific ++ general, & &1.image_id) do
      [] -> fallback_gallery(product, color)
      photos -> Enum.map(photos, & &1.image)
    end
  end

  defp fallback_gallery(product, color) do
    variant_image =
      Enum.find_value(product.variants, fn variant ->
        if variant.color == color and variant.image, do: variant.image
      end)

    case variant_image || product.image do
      nil -> []
      image -> [image]
    end
  end

  @doc """
  Adds a photo from the media library to a product's gallery. With a `color`
  it only shows while that color is selected; without, for every color.
  """
  @spec add_product_photo(Product.t(), String.t(), String.t() | nil) ::
          {:ok, ProductImage.t()} | {:error, Ecto.Changeset.t()}
  def add_product_photo(%Product{id: product_id}, image_id, color \\ nil) do
    position =
      from(g in ProductImage,
        where: g.product_id == ^product_id,
        select: max(g.position)
      )
      |> Repo.one()
      |> then(&((&1 || -1) + 1))

    %ProductImage{}
    |> ProductImage.changeset(%{
      product_id: product_id,
      image_id: image_id,
      color: color,
      position: position,
      source: :admin
    })
    |> Repo.insert()
  end

  @doc """
  Removes a photo the club added. Photos that come from Printful are managed
  by the sync (it would only bring them back), so they can't be removed here.
  """
  @spec remove_product_photo(String.t()) ::
          :ok | {:error, :managed_by_printful | :not_found}
  def remove_product_photo(photo_id) do
    case Repo.get(ProductImage, photo_id) do
      nil ->
        {:error, :not_found}

      %ProductImage{source: :printful} ->
        {:error, :managed_by_printful}

      photo ->
        Repo.delete!(photo)
        :ok
    end
  end

  @doc "Ties a club-added photo to a color (or, with `nil`/blank, to every color)."
  @spec set_photo_color(String.t(), String.t() | nil) ::
          {:ok, ProductImage.t()} | {:error, :managed_by_printful | :not_found}
  def set_photo_color(photo_id, color) do
    case Repo.get(ProductImage, photo_id) do
      nil ->
        {:error, :not_found}

      %ProductImage{source: :printful} ->
        {:error, :managed_by_printful}

      photo ->
        photo |> ProductImage.changeset(%{color: color}) |> Repo.update()
    end
  end

  @doc "Moves a photo to the front of its product's gallery."
  @spec move_photo_first(String.t()) :: :ok | {:error, :not_found}
  def move_photo_first(photo_id) do
    case Repo.get(ProductImage, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        lowest =
          from(g in ProductImage,
            where: g.product_id == ^photo.product_id,
            select: min(g.position)
          )
          |> Repo.one()

        photo
        |> Ecto.Changeset.change(position: (lowest || 0) - 1)
        |> Repo.update!()

        :ok
    end
  end

  @doc """
  The lowest available variant price for a product loaded by
  `list_shop_products/0`.
  """
  def starting_price(%Product{variants: [first | _]}), do: first.retail_price
  def starting_price(_product), do: nil

  ## Catalog (admin)

  @doc """
  Every product, including hidden and removed ones, with all variants.
  """
  def list_admin_products do
    from(p in Product,
      order_by: [asc: p.sort_order, asc: p.name],
      preload: [
        image: ^shop_image_query(),
        variants:
          ^from(v in Variant,
            order_by: [asc: v.name],
            preload: [image: ^shop_image_query()]
          ),
        gallery_images: ^admin_gallery_images_query()
      ]
    )
    |> Repo.all()
  end

  def get_product!(id), do: Repo.get!(Product, id)

  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.admin_changeset(product, attrs)
  end

  @doc """
  Updates the club-managed fields (description, visibility, sort order).
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.admin_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Pulls the latest products, variants, retail prices and images from Printful.
  `uploader` (the admin running the sync) owns any images imported into the
  media library. See `Ysc.Merch.CatalogSync.run/1`.
  """
  defdelegate sync_catalog(uploader), to: CatalogSync, as: :run

  @doc false
  def ci_query_explain_query,
    do: shop_products_query(@shop_listing_product_fields)
end
