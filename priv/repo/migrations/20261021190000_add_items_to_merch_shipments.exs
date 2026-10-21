defmodule Ysc.Repo.Migrations.AddItemsToMerchShipments do
  use Ecto.Migration

  def change do
    alter table(:merch_shipments) do
      # What is in this parcel: [%{"order_item_id" => id, "quantity" => n}],
      # worked out from Printful's shipment and order items when the shipment is
      # recorded. Empty when we could not tell (older shipments, or Printful
      # sent no item detail); emails then fall back to the whole order.
      add :items, {:array, :map}, null: false, default: []

      # Carriers' tracking links can run past varchar(255); a link that does
      # not fit would stop the shipment from being recorded at all.
      modify :tracking_url, :text, from: :string
    end
  end
end
