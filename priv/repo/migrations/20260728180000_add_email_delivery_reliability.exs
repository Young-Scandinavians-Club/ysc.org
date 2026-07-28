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
      add :updated_at, :utc_datetime, null: false
    end

    create table(:email_suppressions, primary_key: false) do
      add :email, :citext, null: false, primary_key: true
      add :reason, :string, null: false
      add :suppressed_at, :utc_datetime, null: false
      add :inserted_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
    end
  end
end
