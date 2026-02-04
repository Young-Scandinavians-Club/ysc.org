defmodule Ysc.Repo.Migrations.CreateSmsReceived do
  use Ecto.Migration

  def change do
    # Table for inbound SMS messages received via SMS provider webhooks
    create table(:sms_received, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # Provider and provider-specific message ID
      add :provider, :string, null: false, default: "flowroute"
      add :provider_message_id, :text, null: false

      # Message details from webhook
      add :from, :text, null: false
      add :to, :text, null: false
      add :body, :text, null: true
      add :is_mms, :boolean, default: false, null: false
      add :direction, :string, null: false, default: "inbound"
      add :message_type, :string, null: true
      add :message_encoding, :integer, null: true
      add :status, :string, null: true

      # Financial details
      add :amount_display, :string, null: true
      add :amount_nanodollars, :bigint, null: true

      # Callback URL (if provided)
      add :message_callback_url, :text, null: true

      # Timestamp from provider
      add :provider_timestamp, :utc_datetime, null: true

      # Link to user if we can match by phone number
      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      # Raw webhook payload for debugging
      add :raw_payload, :map, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_received, [:provider, :provider_message_id])
    create index(:sms_received, [:from])
    create index(:sms_received, [:to])
    create index(:sms_received, [:user_id])
    create index(:sms_received, [:provider])
    create index(:sms_received, [:provider_timestamp])
    create index(:sms_received, [:inserted_at])
  end
end
