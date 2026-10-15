defmodule Ysc.Repo.Migrations.CreateMerchShipments do
  use Ecto.Migration

  def change do
    create table(:merch_shipments, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :order_id,
          references(:merch_orders, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      # Printful's shipment id; makes recording a shipment idempotent across
      # webhooks and polling.
      add :printful_shipment_id, :bigint, null: false
      add :carrier, :string
      add :service, :string
      add :tracking_number, :string
      add :tracking_url, :string
      add :status, :string, null: false, default: "shipped"
      add :reshipment, :boolean, null: false, default: false
      add :shipped_at, :utc_datetime
      add :delivered_at, :utc_datetime
      # Set (atomically with the notification jobs) when the member was told
      # about this shipment, so duplicates never notify twice.
      add :notified_at, :utc_datetime

      timestamps()
    end

    create unique_index(:merch_shipments, [:printful_shipment_id])
    create index(:merch_shipments, [:order_id])

    alter table(:merch_orders) do
      # When we last reconciled this order with Printful (webhook or poll).
      add :printful_synced_at, :utc_datetime
    end

    create index(:merch_orders, [:status, :printful_synced_at])
  end
end
