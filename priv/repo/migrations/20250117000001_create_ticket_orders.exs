defmodule Ysc.Repo.Migrations.CreateTicketOrders do
  use Ecto.Migration

  def change do
    create table(:ticket_orders, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reference_id, :string, null: false

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: false

      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :nothing),
        null: false

      add :status, :string, default: "pending", null: false
      add :total_amount, :money_with_currency, null: false
      add :payment_intent_id, :string, null: true

      add :payment_id, references(:payments, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      add :expires_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime, null: true
      add :cancelled_at, :utc_datetime, null: true
      add :cancellation_reason, :string, null: true

      timestamps()
    end

    create unique_index(:ticket_orders, [:reference_id])
    create index(:ticket_orders, [:user_id])
    create index(:ticket_orders, [:event_id])
    create index(:ticket_orders, [:status])
    create index(:ticket_orders, [:expires_at])
    create index(:ticket_orders, [:payment_intent_id])
    create index(:ticket_orders, [:payment_id])

    # Add ticket_order_id to existing tickets table
    alter table(:tickets) do
      add :ticket_order_id,
          references(:ticket_orders, column: :id, type: :binary_id, on_delete: :nothing),
          null: true
    end

    create index(:tickets, [:ticket_order_id])
  end
end
