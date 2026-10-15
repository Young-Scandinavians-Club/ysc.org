defmodule Ysc.Repo.Migrations.CreateMerchProductImages do
  use Ecto.Migration

  def change do
    create table(:merch_product_images, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :product_id,
          references(:merch_products, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      # Removing a photo from the media library removes it from the product.
      add :image_id,
          references(:images, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      # The color this photo shows. Null means it belongs to every color.
      add :color, :string
      add :position, :integer, null: false, default: 0
      # "printful" photos are managed by catalog sync; "admin" photos are the
      # club's own and are never touched by a sync.
      add :source, :string, null: false, default: "admin"
      # Printful URL a synced photo came from, so a re-sync skips unchanged ones.
      add :source_image_url, :string

      timestamps()
    end

    create unique_index(:merch_product_images, [:product_id, :image_id])
    create index(:merch_product_images, [:product_id, :color, :position])
    create index(:merch_product_images, [:image_id])
  end
end
