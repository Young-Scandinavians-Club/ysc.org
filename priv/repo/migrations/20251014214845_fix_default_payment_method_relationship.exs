defmodule Ysc.Repo.Migrations.FixDefaultPaymentMethodRelationship do
  use Ecto.Migration

  def up do
    # Add is_default column to payment_methods table
    alter table(:payment_methods) do
      add :is_default, :boolean, default: false, null: false
    end

    # Create index for better query performance
    create index(:payment_methods, [:user_id, :is_default])

    # Remove the old default_membership_payment_method column from users table
    alter table(:users) do
      remove :default_membership_payment_method,
             references(:payment_methods, column: :id, type: :binary_id)
    end
  end

  def down do
    # Add back the old column to users table
    alter table(:users) do
      add :default_membership_payment_method,
          references(:payment_methods, column: :id, type: :binary_id),
          null: true
    end

    # Drop the index
    drop index(:payment_methods, [:user_id, :is_default])

    # Remove the is_default column from payment_methods table
    alter table(:payment_methods) do
      remove :is_default, :boolean
    end
  end
end
