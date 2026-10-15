defmodule Ysc.Repo.Migrations.CreateMerchOrders do
  use Ecto.Migration

  def change do
    create table(:merch_orders, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reference_id, :string, null: false
      # "purchase" (member pays) or "admin_comp" (the club pays)
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"

      # The member the order is for. Null when an admin ships to a custom
      # address that isn't tied to a member.
      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing)

      # Admin who placed a club-paid order.
      add :granted_by_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nothing)

      # Club-paid orders can be tied to an event so the cost shows up in the
      # event's statistics.
      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :nothing)

      add :purpose, :text

      # Shipping address snapshot, so later profile edits don't alter history.
      add :recipient_name, :string, null: false
      add :address1, :string, null: false
      add :address2, :string
      add :city, :string, null: false
      add :state_code, :string
      add :zip, :string, null: false
      add :country_code, :string, null: false, default: "US"
      add :phone, :string
      add :email, :string

      # What the member is charged (all zero for club-paid orders).
      add :subtotal, :money_with_currency, null: false
      add :shipping_amount, :money_with_currency, null: false
      add :total_amount, :money_with_currency, null: false
      add :shipping_method, :string

      add :payment_intent_id, :string

      add :payment_id,
          references(:payments, column: :id, type: :binary_id, on_delete: :nothing)

      # What Printful charges the club: the estimate shown when the order is
      # placed, replaced by the actual figure once Printful reports it.
      add :printful_order_id, :bigint
      add :estimated_cost, :money_with_currency
      add :printful_cost, :money_with_currency

      add :submitted_at, :utc_datetime
      add :canceled_at, :utc_datetime
      add :failure_reason, :string

      timestamps()
    end

    create unique_index(:merch_orders, [:reference_id])
    create index(:merch_orders, [:user_id])
    create index(:merch_orders, [:granted_by_id])
    create index(:merch_orders, [:event_id])
    create index(:merch_orders, [:status])
    create index(:merch_orders, [:payment_intent_id])
    create index(:merch_orders, [:payment_id])
    create index(:merch_orders, [:printful_order_id])

    create table(:merch_order_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :order_id,
          references(:merch_orders, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :variant_id,
          references(:merch_variants, column: :id, type: :binary_id, on_delete: :nothing),
          null: false

      add :quantity, :integer, null: false
      # Snapshots, so catalog changes never rewrite what was ordered.
      add :name, :string, null: false
      add :unit_price, :money_with_currency, null: false

      timestamps()
    end

    create index(:merch_order_items, [:order_id])
    create index(:merch_order_items, [:variant_id])
  end
end
