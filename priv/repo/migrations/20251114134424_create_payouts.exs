defmodule Ysc.Repo.Migrations.CreatePayouts do
  use Ecto.Migration

  def change do
    # Create payouts table
    create table(:payouts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :stripe_payout_id, :text, null: false
      add :amount, :money_with_currency, null: false
      add :currency, :string, null: false
      add :status, :string, null: false
      add :arrival_date, :utc_datetime
      add :description, :text
      add :metadata, :map

      # Link to the payment record created for this payout in the ledger
      add :payment_id, references(:payments, column: :id, type: :binary_id), null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payouts, [:stripe_payout_id])
    create index(:payouts, [:payment_id])
    create index(:payouts, [:status])
    create index(:payouts, [:arrival_date])

    # Create join table for payout_payments (many-to-many)
    create table(:payout_payments, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :payout_id, references(:payouts, column: :id, type: :binary_id, on_delete: :delete_all),
        null: false

      add :payment_id,
          references(:payments, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payout_payments, [:payout_id, :payment_id])
    create index(:payout_payments, [:payout_id])
    create index(:payout_payments, [:payment_id])

    # Create join table for payout_refunds (many-to-many)
    # Note: Refunds are stored as ledger_transactions with type: :refund
    create table(:payout_refunds, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :payout_id, references(:payouts, column: :id, type: :binary_id, on_delete: :delete_all),
        null: false

      add :refund_transaction_id,
          references(:ledger_transactions, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payout_refunds, [:payout_id, :refund_transaction_id])
    create index(:payout_refunds, [:payout_id])
    create index(:payout_refunds, [:refund_transaction_id])
  end
end
