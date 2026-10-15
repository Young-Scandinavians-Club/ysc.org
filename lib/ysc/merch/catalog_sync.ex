defmodule Ysc.Merch.CatalogSync do
  @moduledoc """
  Mirrors the Printful store's sync products and variants into
  `merch_products` / `merch_variants`.

  Printful owns names, images, variants and retail prices; the club owns
  description, status and ordering (see `Ysc.Merch.Product.admin_changeset/2`),
  which a sync never touches. Products that disappear from Printful are hidden
  rather than deleted so past orders keep their references.

  Product and variant images are copied into the internal `images` table (see
  `Ysc.Merch.ImageImport`) so the shop never serves Printful URLs. Each distinct
  Printful image URL is downloaded at most once, and not at all again while the
  URL is unchanged. Image failures never fail the sync; the previous image (if
  any) is kept and the import is retried next sync.
  """
  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Accounts.User
  alias Ysc.Merch.{ImageImport, Product, ProductImage, Variant}
  alias Ysc.MoneyHelper
  alias Ysc.Repo

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  @type summary :: %{
          products: non_neg_integer(),
          variants: non_neg_integer(),
          removed: non_neg_integer(),
          failed: non_neg_integer(),
          images_failed: non_neg_integer()
        }

  @doc """
  Runs a full sync. `uploader` owns any images imported into the media library.

  Returns `{:ok, summary}`, or `{:error, error}` when the product list itself
  could not be fetched (nothing is changed in that case).

  A product whose detail fetch fails is skipped and counted in `failed`; it is
  also excluded from the "removed" sweep so a flaky response can't hide it.
  """
  @spec run(User.t()) :: {:ok, summary()} | {:error, Ysc.Printful.Error.t()}
  def run(%User{} = uploader) do
    with {:ok, listed} <- printful_client().list_sync_products() do
      listed = Enum.reject(listed, &(&1["is_ignored"] == true))
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {results, image_cache} =
        Enum.map_reduce(listed, %{}, &sync_product(&1, now, uploader, &2))

      failed_ids = for {:error, id} <- results, do: id
      removed = mark_removed(Enum.map(listed, & &1["id"]), failed_ids, now)

      {:ok,
       %{
         products: Enum.count(results, &match?({:ok, _}, &1)),
         variants: results |> Enum.map(&variant_count/1) |> Enum.sum(),
         removed: removed,
         failed: length(failed_ids),
         images_failed:
           Enum.count(image_cache, fn {_url, value} -> value == :failed end)
       }}
    end
  end

  defp variant_count({:ok, count}), do: count
  defp variant_count(_), do: 0

  defp sync_product(%{"id" => printful_id} = listed, now, uploader, cache) do
    case printful_client().get_sync_product(printful_id) do
      {:ok, %{"sync_product" => sync_product, "sync_variants" => variants}} ->
        upsert_product(sync_product || listed, variants, now, uploader, cache)

      {:ok, _unexpected} ->
        log_failure(printful_id, "unexpected response")
        {{:error, printful_id}, cache}

      {:error, error} ->
        log_failure(printful_id, Exception.message(error))
        {{:error, printful_id}, cache}
    end
  end

  defp upsert_product(sync_product, sync_variants, now, uploader, cache) do
    printful_id = sync_product["id"]
    usable = Enum.reject(sync_variants, &(&1["is_ignored"] == true))

    existing_product = Repo.get_by(Product, printful_product_id: printful_id)
    existing_variants = existing_variants_by_sync_id(usable)

    # Network I/O (image downloads) happens before the transaction opens.
    {product_image, cache} =
      resolve_image(
        sync_product["thumbnail_url"],
        sync_product["name"],
        existing_product,
        uploader,
        cache
      )

    {variant_images, cache} =
      Enum.map_reduce(usable, cache, fn sync_variant, cache ->
        {image, cache} =
          resolve_image(
            variant_image_url(sync_variant),
            variant_image_title(sync_product, sync_variant),
            Map.get(existing_variants, sync_variant["id"]),
            uploader,
            cache
          )

        {{sync_variant["id"], image}, cache}
      end)

    {gallery, cache} = resolve_gallery(sync_product, usable, uploader, cache)

    attrs =
      Map.merge(product_image, %{
        printful_product_id: printful_id,
        name: sync_product["name"],
        synced_at: now,
        removed_from_printful_at: nil
      })

    result =
      Repo.transaction(fn ->
        changeset =
          Product.sync_changeset(existing_product || %Product{}, attrs)

        # A product that reappears after being swept as removed becomes visible
        # again; otherwise status belongs to the club and is left alone.
        changeset =
          if existing_product && existing_product.removed_from_printful_at do
            Ecto.Changeset.put_change(changeset, :status, :active)
          else
            changeset
          end

        product = Repo.insert_or_update!(changeset)

        count =
          upsert_variants(
            product,
            usable,
            existing_variants,
            Map.new(variant_images)
          )

        sync_gallery(product, gallery)
        count
      end)

    case result do
      {:ok, count} ->
        {{:ok, count}, cache}

      {:error, reason} ->
        log_failure(printful_id, inspect(reason))
        {{:error, printful_id}, cache}
    end
  rescue
    error in [Ecto.InvalidChangesetError] ->
      log_failure(sync_product["id"], Exception.message(error))
      {{:error, sync_product["id"]}, cache}
  end

  defp existing_variants_by_sync_id(usable) do
    ids = Enum.map(usable, & &1["id"])

    from(v in Variant, where: v.printful_sync_variant_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.printful_sync_variant_id, &1})
  end

  defp upsert_variants(product, usable, existing_variants, variant_images) do
    kept_ids = Enum.map(usable, & &1["id"])

    Enum.each(usable, fn sync_variant ->
      upsert_variant(
        product,
        sync_variant,
        Map.get(existing_variants, sync_variant["id"]),
        Map.fetch!(variant_images, sync_variant["id"])
      )
    end)

    # Variants Printful dropped can't be sold any more; keep the row for
    # order history but make it unavailable.
    from(v in Variant,
      where:
        v.product_id == ^product.id and
          v.printful_sync_variant_id not in ^kept_ids
    )
    |> Repo.update_all(set: [available: false])

    length(usable)
  end

  defp upsert_variant(product, sync_variant, existing, image_attrs) do
    attrs =
      Map.merge(image_attrs, %{
        product_id: product.id,
        printful_sync_variant_id: sync_variant["id"],
        printful_variant_id: sync_variant["variant_id"],
        name: sync_variant["name"],
        size: sync_variant["size"],
        color: sync_variant["color"],
        sku: sync_variant["sku"],
        retail_price: MoneyHelper.parse_money(sync_variant["retail_price"]),
        available: available?(sync_variant)
      })

    (existing || %Variant{})
    |> Variant.sync_changeset(attrs)
    |> Repo.insert_or_update!()
  end

  ## Gallery

  # Each color's mockup photos, imported into the media library. Only
  # Printful's "preview" files are mockups; the other file types are the print
  # artwork. Returns `{[%{color:, image_id:, position:, url:}], cache}`.
  defp resolve_gallery(sync_product, usable, uploader, cache) do
    usable
    |> Enum.group_by(& &1["color"])
    |> Enum.sort_by(fn {color, _} -> color || "" end)
    |> Enum.flat_map_reduce(cache, fn {color, variants}, cache ->
      urls = variants |> Enum.flat_map(&preview_urls/1) |> Enum.uniq()

      title =
        if color in [nil, ""],
          do: sync_product["name"],
          else: "#{sync_product["name"]} - #{color}"

      urls
      |> Enum.with_index()
      |> Enum.flat_map_reduce(cache, fn {url, position}, cache ->
        case import_once(url, title, uploader, cache) do
          {{:ok, image_id}, cache} ->
            {[
               %{
                 color: blank_to_nil(color),
                 image_id: image_id,
                 position: position,
                 url: url
               }
             ], cache}

          {:failed, cache} ->
            {[], cache}
        end
      end)
    end)
  end

  defp preview_urls(sync_variant) do
    sync_variant
    |> Map.get("files", [])
    |> Enum.filter(&(&1["type"] == "preview"))
    |> Enum.map(&(&1["preview_url"] || &1["thumbnail_url"]))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp blank_to_nil(color) when color in [nil, ""], do: nil
  defp blank_to_nil(color), do: color

  # Mirrors Printful's photos into the product's gallery. Photos the club added
  # are never touched; Printful ones that are no longer offered are removed.
  defp sync_gallery(product, entries) do
    entries = Enum.uniq_by(entries, & &1.image_id)

    existing =
      from(g in ProductImage, where: g.product_id == ^product.id)
      |> Repo.all()
      |> Map.new(&{&1.image_id, &1})

    Enum.each(entries, fn entry ->
      attrs = %{
        product_id: product.id,
        image_id: entry.image_id,
        color: entry.color,
        position: entry.position,
        source: :printful,
        source_image_url: entry.url
      }

      case Map.get(existing, entry.image_id) do
        nil ->
          %ProductImage{} |> ProductImage.changeset(attrs) |> Repo.insert!()

        %ProductImage{source: :printful} = photo ->
          photo |> ProductImage.changeset(attrs) |> Repo.update!()

        %ProductImage{source: :admin} ->
          # The club already uses this photo; theirs wins.
          :ok
      end
    end)

    keep = Enum.map(entries, & &1.image_id)

    from(g in ProductImage,
      where:
        g.product_id == ^product.id and g.source == :printful and
          g.image_id not in ^keep
    )
    |> Repo.delete_all()
  end

  ## Images

  # Returns `{%{image_id: _, source_image_url: _}, cache}` for the record's
  # image columns. `existing` is the stored product/variant, if any.
  defp resolve_image(url, title, existing, uploader, cache) do
    current = %{
      image_id: existing && existing.image_id,
      source_image_url: existing && existing.source_image_url
    }

    cond do
      is_nil(url) or url == "" ->
        {current, cache}

      current.image_id && current.source_image_url == url ->
        {current, cache}

      true ->
        case import_once(url, title, uploader, cache) do
          {{:ok, image_id}, cache} ->
            {%{image_id: image_id, source_image_url: url}, cache}

          {:failed, cache} ->
            # Keep the old image and old source URL so the next sync retries.
            {current, cache}
        end
    end
  end

  defp import_once(url, title, uploader, cache) do
    case Map.fetch(cache, url) do
      {:ok, :failed} ->
        {:failed, cache}

      {:ok, image_id} ->
        {{:ok, image_id}, cache}

      :error ->
        case image_for_source_url(url) do
          image_id when is_binary(image_id) ->
            {{:ok, image_id}, Map.put(cache, url, image_id)}

          nil ->
            import_new(url, title, uploader, cache)
        end
    end
  end

  defp import_new(url, title, uploader, cache) do
    case ImageImport.import(url, title, uploader) do
      {:ok, image} ->
        {{:ok, image.id}, Map.put(cache, url, image.id)}

      {:error, reason} ->
        Ysc.Logging.warning("Merch image import failed",
          url: url,
          reason: inspect(reason)
        )

        {:failed, Map.put(cache, url, :failed)}
    end
  end

  # An image already imported for this Printful URL by any product/variant.
  defp image_for_source_url(url) do
    Repo.one(
      from(v in Variant,
        where: v.source_image_url == ^url and not is_nil(v.image_id),
        select: v.image_id,
        limit: 1
      )
    ) ||
      Repo.one(
        from(p in Product,
          where: p.source_image_url == ^url and not is_nil(p.image_id),
          select: p.image_id,
          limit: 1
        )
      )
  end

  defp variant_image_url(sync_variant) do
    preview =
      sync_variant
      |> Map.get("files", [])
      |> Enum.find(&(&1["type"] == "preview"))

    (preview && (preview["preview_url"] || preview["thumbnail_url"])) ||
      get_in(sync_variant, ["product", "image"])
  end

  defp variant_image_title(sync_product, sync_variant) do
    case sync_variant["color"] do
      color when is_binary(color) and color != "" ->
        "#{sync_product["name"]} - #{color}"

      _ ->
        sync_variant["name"] || sync_product["name"]
    end
  end

  # Printful reports "active", "discontinued", "out_of_stock", ... Treat a
  # missing status as sellable so older payloads without the field still work.
  defp available?(sync_variant) do
    sync_variant["availability_status"] in [nil, "active"]
  end

  defp mark_removed(listed_ids, failed_ids, now) do
    {count, _} =
      (listed_ids ++ failed_ids)
      |> unlisted_products_query()
      |> Repo.update_all(
        set: [status: :hidden, removed_from_printful_at: now, updated_at: now]
      )

    count
  end

  defp unlisted_products_query(keep_printful_ids) do
    from(p in Product,
      where:
        p.printful_product_id not in ^keep_printful_ids and
          is_nil(p.removed_from_printful_at)
    )
  end

  @doc false
  def ci_query_explain_query, do: unlisted_products_query([1, 2, 3])

  defp log_failure(printful_id, message) do
    Ysc.Logging.warning("Printful catalog sync skipped a product",
      printful_product_id: printful_id,
      error: message
    )
  end
end
