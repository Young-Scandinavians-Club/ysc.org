defmodule Ysc.Repo.Migrations.CreateTicketReservations do
  use Ecto.Migration

  def change do
    create table(:ticket_reservations, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :ticket_tier_id,
          references(:ticket_tiers, column: :id, type: :binary_id, on_delete: :nothing),
          null: false

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: false

      add :quantity, :integer, null: false

      add :expires_at, :utc_datetime, null: true

      add :notes, :text, null: true

      add :created_by_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nothing),
          null: false

      add :status, :string, default: "active", null: false

      add :fulfilled_at, :utc_datetime, null: true

      add :cancelled_at, :utc_datetime, null: true

      add :ticket_order_id,
          references(:ticket_orders, column: :id, type: :binary_id, on_delete: :nothing),
          null: true

      timestamps()
    end

    create index(:ticket_reservations, [:ticket_tier_id])
    create index(:ticket_reservations, [:user_id])
    create index(:ticket_reservations, [:status])
    create index(:ticket_reservations, [:ticket_order_id])
    create index(:ticket_reservations, [:ticket_tier_id, :user_id, :status])
  end
end
