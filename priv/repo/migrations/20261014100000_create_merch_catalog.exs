defmodule Ysc.Repo.Migrations.CreateMerchCatalog do
  use Ecto.Migration

  def change do
    create table(:merch_products, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :printful_product_id, :bigint, null: false
      add :name, :string, null: false
      add :description, :text

      add :image_id,
          references(:images, column: :id, type: :binary_id, on_delete: :nilify_all)

      # Printful URL the image was imported from; lets a re-sync skip the
      # download when Printful's image has not changed.
      add :source_image_url, :string
      add :status, :string, null: false, default: "active"
      add :sort_order, :integer, null: false, default: 0
      add :synced_at, :utc_datetime
      # Set when a sync no longer finds the product in Printful; the product
      # is hidden from the shop but kept so past orders keep their snapshots.
      add :removed_from_printful_at, :utc_datetime

      timestamps()
    end

    create unique_index(:merch_products, [:printful_product_id])
    create index(:merch_products, [:status, :sort_order])
    create index(:merch_products, [:image_id])

    create table(:merch_variants, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :product_id,
          references(:merch_products,
            column: :id,
            type: :binary_id,
            on_delete: :nothing
          ),
          null: false

      add :printful_sync_variant_id, :bigint, null: false
      # Catalog variant id; Printful needs it for shipping rate lookups.
      add :printful_variant_id, :bigint, null: false
      add :name, :string, null: false
      add :size, :string
      add :color, :string
      add :sku, :string
      add :retail_price, :money_with_currency, null: false

      add :image_id,
          references(:images, column: :id, type: :binary_id, on_delete: :nilify_all)

      add :source_image_url, :string
      add :available, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:merch_variants, [:printful_sync_variant_id])
    create index(:merch_variants, [:product_id])
    create index(:merch_variants, [:image_id])
  end
end
