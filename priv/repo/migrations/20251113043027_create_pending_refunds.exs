defmodule Ysc.Repo.Migrations.CreatePendingRefunds do
  use Ecto.Migration

  def change do
    create table(:pending_refunds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id, on_delete: :restrict), null: false
      add :payment_id, references(:payments, type: :binary_id, on_delete: :restrict), null: false
      add :policy_refund_amount, :money_with_currency, null: false
      add :admin_refund_amount, :money_with_currency
      add :status, :string, null: false, default: "pending"
      add :cancellation_reason, :text
      add :admin_notes, :text
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
      add :applied_rule_days_before_checkin, :integer
      add :applied_rule_refund_percentage, :decimal

      timestamps(type: :utc_datetime)
    end

    create index(:pending_refunds, [:booking_id])
    create index(:pending_refunds, [:payment_id])
    create index(:pending_refunds, [:status])
    create index(:pending_refunds, [:reviewed_by_id])
  end
end
