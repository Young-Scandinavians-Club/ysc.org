defmodule Ysc.Merch do
  @moduledoc """
  Club merch shop, fulfilled by Printful.

  Products and variants are designed and priced in Printful and mirrored into
  our database (see `Ysc.Merch.CatalogSync`), so shop pages never call
  Printful. Orders, carts and fulfillment are added on top of this catalog.
  """
  import Ecto.Query, warn: false

  alias Ysc.Media.Image

  alias Ysc.Merch.{
    CatalogSync,
    Product,
    ProductImage,
    Variant,
    VariantSelection
  }

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
  The product's colors in the order the shop shows them, which is also the
  default: the color whose photo comes first leads ("Make first" in the admin
  picks the default color), then the rest by photo position. Colors with no
  photo of their own follow, in variant order.

  Expects `gallery_images` and `variants` to be loaded.
  """
  @spec colors(Product.t()) :: [String.t()]
  def colors(%Product{} = product) do
    rank =
      product.gallery_images
      |> Enum.reject(&is_nil(&1.color))
      |> Enum.group_by(& &1.color, & &1.position)
      |> Map.new(fn {color, positions} -> {color, Enum.min(positions)} end)

    # `sort_by` is stable, so colors that tie (or have no photo, ranked last as
    # an atom) keep the variants' order.
    product.variants
    |> VariantSelection.colors()
    |> Enum.sort_by(&Map.get(rank, &1, :no_photo))
  end

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
  def add_product_photo(%Product{} = product, image_id, color \\ nil) do
    case add_product_photos(product, [image_id], color) do
      [result] -> result
      [] -> {:error, ProductImage.changeset(%ProductImage{}, %{})}
    end
  end

  @doc """
  Adds many media-library photos to a product's gallery in selection order.

  One round-trip reads the current gallery, one checks that the images exist,
  and one `INSERT` writes every new row. Duplicates (already in the gallery or
  repeated in `image_ids`) and missing images are returned as changeset errors
  in the same order as `image_ids`, matching `add_product_photo/3`.
  """
  @spec add_product_photos(Product.t(), [String.t()], String.t() | nil) :: [
          {:ok, ProductImage.t()} | {:error, Ecto.Changeset.t()}
        ]
  def add_product_photos(%Product{} = product, image_ids, color \\ nil)
      when is_list(image_ids) do
    image_ids = Enum.reject(image_ids, &is_nil/1)

    case image_ids do
      [] ->
        []

      [image_id] ->
        [insert_product_photo(product.id, image_id, color)]

      image_ids ->
        insert_product_photos(product.id, image_ids, color)
    end
  end

  defp insert_product_photo(product_id, image_id, color) do
    position =
      product_id
      |> max_product_gallery_position_query()
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

  defp insert_product_photos(product_id, image_ids, color) do
    gallery = Repo.all(product_gallery_photos_query(product_id))

    max_position =
      gallery
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> -1 end)

    existing_gallery_ids = MapSet.new(gallery, & &1.image_id)

    present_image_ids =
      MapSet.new(Repo.all(existing_image_ids_query(image_ids)))

    {entries, rows, _next_position, _seen} =
      Enum.reduce(
        image_ids,
        {[], [], max_position + 1, existing_gallery_ids},
        fn image_id, {entries, rows, position, seen} ->
          cond do
            MapSet.member?(seen, image_id) ->
              {[duplicate_photo_error(product_id, image_id) | entries], rows,
               position, seen}

            not MapSet.member?(present_image_ids, image_id) ->
              {[missing_photo_error(product_id, image_id) | entries], rows,
               position, seen}

            true ->
              row =
                product_photo_insert_row(product_id, image_id, color, position)

              {[{:insert, image_id} | entries], [row | rows], position + 1,
               MapSet.put(seen, image_id)}
          end
        end
      )

    inserted_by_image_id = insert_product_photo_rows(Enum.reverse(rows))

    entries
    |> Enum.reverse()
    |> Enum.map(fn
      {:error, changeset} -> {:error, changeset}
      {:insert, image_id} -> {:ok, Map.fetch!(inserted_by_image_id, image_id)}
    end)
  end

  defp insert_product_photo_rows([]), do: %{}

  defp insert_product_photo_rows(rows) do
    {_count, inserted} = Repo.insert_all(ProductImage, rows, returning: true)
    Map.new(inserted, &{&1.image_id, &1})
  end

  defp product_photo_insert_row(product_id, image_id, color, position) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    photo =
      %ProductImage{}
      |> ProductImage.changeset(%{
        product_id: product_id,
        image_id: image_id,
        color: color,
        position: position,
        source: :admin
      })
      |> Ecto.Changeset.apply_changes()

    %{
      id: Ecto.ULID.generate(),
      product_id: photo.product_id,
      image_id: photo.image_id,
      color: photo.color,
      position: photo.position,
      source: photo.source,
      source_image_url: photo.source_image_url,
      inserted_at: now,
      updated_at: now
    }
  end

  defp duplicate_photo_error(product_id, image_id) do
    {:error,
     %ProductImage{}
     |> ProductImage.changeset(%{product_id: product_id, image_id: image_id})
     |> Ecto.Changeset.add_error(
       :product_id,
       "is already in this gallery",
       constraint: :unique,
       constraint_name: :merch_product_images_product_id_image_id_index
     )}
  end

  defp missing_photo_error(product_id, image_id) do
    {:error,
     %ProductImage{}
     |> ProductImage.changeset(%{product_id: product_id, image_id: image_id})
     |> Ecto.Changeset.add_error(:image_id, "does not exist",
       constraint: :foreign,
       constraint_name: :merch_product_images_image_id_fkey
     )}
  end

  defp product_gallery_photos_query(product_id) do
    from(g in ProductImage,
      where: g.product_id == ^product_id,
      select: %{image_id: g.image_id, position: g.position}
    )
  end

  defp max_product_gallery_position_query(product_id) do
    from(g in ProductImage,
      where: g.product_id == ^product_id,
      select: max(g.position)
    )
  end

  defp existing_image_ids_query(image_ids) do
    from(i in Image, where: i.id in ^image_ids, select: i.id)
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

  @doc false
  def ci_query_explain_product_gallery_photos_query do
    product_gallery_photos_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_max_product_gallery_position_query do
    max_product_gallery_position_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  @doc false
  def ci_query_explain_existing_image_ids_query do
    existing_image_ids_query([Ysc.Ci.QueryExplain.Fixtures.ulid()])
  end
end
