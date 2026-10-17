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
    :color_hex,
    :retail_price,
    :available,
    :image_id
  ]

  @shop_gallery_fields [:id, :product_id, :image_id, :color, :position]

  # Admin catalog table: name, status, prices, variant/gallery counts.
  # Omits `description` (up to 5k) and Printful sync columns.
  @admin_listing_product_fields [
    :id,
    :name,
    :status,
    :sort_order,
    :image_id,
    :synced_at,
    :removed_from_printful_at,
    :inserted_at
  ]

  # Edit modal also needs the club-written description.
  @admin_product_fields @admin_listing_product_fields ++ [:description]

  @admin_variant_fields [
    :id,
    :product_id,
    :name,
    :size,
    :color,
    :retail_price,
    :available
  ]

  @admin_gallery_fields [
    :id,
    :product_id,
    :image_id,
    :color,
    :position,
    :source
  ]

  @orderable_product_fields [:id, :name, :sort_order]
  @orderable_variant_fields [:id, :product_id, :name, :available]

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
      select: struct(g, ^@admin_gallery_fields),
      preload: [image: ^shop_image_query()]
    )
  end

  defp admin_gallery_count_query do
    from(g in ProductImage, select: struct(g, [:id, :product_id]))
  end

  defp admin_variants_query do
    from(v in Variant,
      order_by: [asc: v.name],
      select: struct(v, ^@admin_variant_fields)
    )
  end

  defp orderable_variants_query do
    from(v in Variant,
      where: v.available == true,
      order_by: [asc: v.name],
      select: struct(v, ^@orderable_variant_fields)
    )
  end

  defp shop_image_query do
    from(i in Image, select: struct(i, ^@shop_image_fields))
  end

  ## Gallery

  @doc """
  The photos to show for `product` while `color` is selected, in display order.

  That color's photos and the photos that belong to every color are ordered
  together by position (so "Make first" on any photo puts it first). At the same
  position a color's own photo wins. With no gallery at all it falls back to the
  color's variant image, then the product image. May be empty (the page then
  shows a placeholder).

  Expects `gallery_images` (with images) and `variants` to be loaded, as
  `get_shop_product/1` does.
  """
  @spec gallery(Product.t(), String.t() | nil) :: [struct()]
  def gallery(%Product{} = product, color) do
    # `sort_by` is stable, so equal keys keep the query's order (position, then
    # when the photo was added).
    applicable =
      product.gallery_images
      |> Enum.filter(&(is_nil(&1.color) or &1.color == color))
      |> Enum.sort_by(&{&1.position, if(is_nil(&1.color), do: 1, else: 0)})

    case Enum.uniq_by(applicable, & &1.image_id) do
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
  Every product, including hidden and removed ones, for the admin catalog
  table.

  Listing columns, slim variants (counts / prices / colors), gallery ids for
  the photo count, and display-image paths. Skips descriptions, Printful ids,
  and gallery image blobs. The edit modal uses `get_admin_product/1`.
  """
  def list_admin_products do
    admin_products_query(@admin_listing_product_fields,
      gallery_images: admin_gallery_count_query()
    )
    |> Repo.all()
  end

  @doc """
  One admin catalog product with its description, variants, and gallery, or
  `nil` when the id is missing or not a product id.
  """
  def get_admin_product(id) do
    admin_products_query(@admin_product_fields,
      gallery_images: admin_gallery_images_query()
    )
    |> where([p], p.id == ^id)
    |> Repo.one()
  rescue
    Ecto.Query.CastError -> nil
  end

  defp admin_products_query(product_fields, gallery_images: gallery_query) do
    from(p in Product,
      order_by: [asc: p.sort_order, asc: p.name],
      select: struct(p, ^product_fields),
      preload: [
        image: ^shop_image_query(),
        variants: ^admin_variants_query(),
        gallery_images: ^gallery_query
      ]
    )
  end

  @doc """
  Products an admin can put on a club-paid order: not removed from Printful,
  with at least one available variant.

  Name + available variant id/name only. Printful ids are loaded later by
  fat `Orders.get_order/1` when submitting.
  """
  def list_orderable_products do
    from(p in Product,
      as: :product,
      where: is_nil(p.removed_from_printful_at),
      where:
        exists(
          from(v in Variant,
            where:
              v.product_id == parent_as(:product).id and v.available == true,
            select: 1
          )
        ),
      order_by: [asc: p.sort_order, asc: p.name],
      select: struct(p, ^@orderable_product_fields),
      preload: [variants: ^orderable_variants_query()]
    )
    |> Repo.all()
    |> Enum.map(&{&1, &1.variants})
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

  @doc false
  def ci_query_explain_admin_products_query do
    admin_products_query(@admin_listing_product_fields,
      gallery_images: admin_gallery_count_query()
    )
  end

  @doc false
  def ci_query_explain_admin_product_query do
    admin_products_query(@admin_product_fields,
      gallery_images: admin_gallery_images_query()
    )
    |> where([p], p.id == ^Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_orderable_products_query do
    from(p in Product,
      as: :product,
      where: is_nil(p.removed_from_printful_at),
      where:
        exists(
          from(v in Variant,
            where:
              v.product_id == parent_as(:product).id and v.available == true,
            select: 1
          )
        ),
      order_by: [asc: p.sort_order, asc: p.name],
      select: struct(p, ^@orderable_product_fields),
      preload: [variants: ^orderable_variants_query()]
    )
  end
end
