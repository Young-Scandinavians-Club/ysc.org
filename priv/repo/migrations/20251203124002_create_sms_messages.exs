defmodule Ysc.Repo.Migrations.CreateSmsMessages do
  use Ecto.Migration

  def change do
    # Table for outbound SMS messages sent via SMS providers
    create table(:sms_messages, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # Provider and provider-specific message ID
      add :provider, :string, null: false, default: "flowroute"
      add :provider_message_id, :string, null: false

      # Message details
      add :to, :text, null: false
      add :from, :text, null: false
      add :body, :text, null: false
      add :is_mms, :boolean, default: false, null: false
      add :media_urls, {:array, :string}, default: [], null: false

      # Link to user if available
      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      # Link to message idempotency entry
      add :message_idempotency_id,
          references(:message_idempotency_entries,
            column: :id,
            type: :binary_id,
            on_delete: :nothing
          ),
          null: true

      # Status tracking
      add :status, :string, default: "sent", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_messages, [:provider, :provider_message_id])
    create index(:sms_messages, [:to])
    create index(:sms_messages, [:from])
    create index(:sms_messages, [:user_id])
    create index(:sms_messages, [:message_idempotency_id])
    create index(:sms_messages, [:status])
    create index(:sms_messages, [:provider])
    create index(:sms_messages, [:inserted_at])
  end
end
