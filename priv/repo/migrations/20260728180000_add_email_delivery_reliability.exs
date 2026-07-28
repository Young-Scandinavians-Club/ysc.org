defmodule Ysc.Repo.Migrations.AddEmailDeliveryReliability do
  use Ecto.Migration

  def change do
    alter table(:message_idempotency_entries) do
      add :delivery_status, :string, null: false, default: "accepted"
      add :delivery_attempts, :integer, null: false, default: 0
      add :delivery_lease_expires_at, :utc_datetime
      add :last_delivery_error, :map
      add :provider_message_id, :string
      add :provider_request_id, :string
      add :accepted_at, :utc_datetime
    end

    create index(:message_idempotency_entries, [:delivery_status])
    create index(:message_idempotency_entries, [:delivery_lease_expires_at])

    create table(:email_rate_limits, primary_key: false) do
      add :key, :string, null: false, primary_key: true
      add :window_started_at, :utc_datetime, null: false
      add :used, :integer, null: false, default: 0
      add :cooldown_until, :utc_datetime
      timestamps(updated_at: true, inserted_at: false)
    end
  end
end
