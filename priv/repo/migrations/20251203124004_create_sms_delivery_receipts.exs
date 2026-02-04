defmodule Ysc.Repo.Migrations.CreateSmsDeliveryReceipts do
  use Ecto.Migration

  def change do
    # Table for delivery receipts (DLRs) from SMS providers
    create table(:sms_delivery_receipts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # Provider and provider-specific message ID - links to sms_messages
      add :provider, :string, null: false, default: "flowroute"
      add :provider_message_id, :text, null: false

      # Link to the original outbound SMS message
      add :sms_message_id,
          references(:sms_messages, column: :id, type: :binary_id, on_delete: :nothing),
          null: true

      # Delivery receipt details
      add :body, :text, null: true
      add :level, :integer, null: true
      add :status, :string, null: false
      add :status_code, :text, null: true
      add :status_code_description, :text, null: true

      # Timestamp from provider
      add :provider_timestamp, :utc_datetime, null: true

      # Raw webhook payload for debugging
      add :raw_payload, :map, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :sms_delivery_receipts,
             [:provider, :provider_message_id, :provider_timestamp],
             name: :sms_delivery_receipts_provider_message_timestamp_unique
           )

    create index(:sms_delivery_receipts, [:sms_message_id])
    create index(:sms_delivery_receipts, [:provider, :provider_message_id])
    create index(:sms_delivery_receipts, [:provider])
    create index(:sms_delivery_receipts, [:status])
    create index(:sms_delivery_receipts, [:provider_timestamp])
    create index(:sms_delivery_receipts, [:inserted_at])
  end
end
