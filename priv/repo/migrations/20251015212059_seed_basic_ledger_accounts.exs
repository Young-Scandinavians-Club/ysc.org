defmodule Ysc.Repo.Migrations.SeedBasicLedgerAccounts do
  use Ecto.Migration

  def up do
    # Only accounts that are actually used in the codebase
    # Format: {name, account_type, normal_balance, description}
    # Assets and Expenses are debit-normal
    # Revenue is credit-normal
    basic_accounts = [
      # Asset accounts (debit-normal)
      {"cash", "asset", "debit", "Cash account for holding funds"},
      {"stripe_account", "asset", "debit", "Stripe account balance"},
      {"accounts_receivable", "asset", "debit", "Outstanding payments from customers"},

      # Revenue accounts (credit-normal)
      {"membership_revenue", "revenue", "credit", "Revenue from membership subscriptions"},
      {"event_revenue", "revenue", "credit", "Revenue from event registrations"},
      {"tahoe_booking_revenue", "revenue", "credit", "Revenue from Tahoe cabin bookings"},
      {"clear_lake_booking_revenue", "revenue", "credit",
       "Revenue from Clear Lake cabin bookings"},
      {"donation_revenue", "revenue", "credit", "Revenue from donations"},

      # Expense accounts (debit-normal)
      {"stripe_fees", "expense", "debit", "Stripe processing fees"},
      {"discount_expense", "expense", "debit", "Reserved ticket discounts"}
    ]

    # Insert basic accounts
    # Note: normal_balance is conditionally included if the column exists.
    # If it doesn't exist yet, it will be backfilled by the add_normal_balance_to_ledger_accounts migration.
    Enum.each(basic_accounts, fn {name, account_type, normal_balance, description} ->
      # Use a DO block to conditionally include normal_balance if the column exists
      execute """
        DO $$
        DECLARE
          column_exists boolean;
        BEGIN
          SELECT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'ledger_accounts'
            AND column_name = 'normal_balance'
          ) INTO column_exists;

          IF column_exists THEN
            INSERT INTO ledger_accounts (id, account_type, normal_balance, name, description, inserted_at, updated_at)
            VALUES (
              gen_random_uuid(),
              '#{account_type}',
              '#{normal_balance}',
              '#{name}',
              '#{description}',
              NOW(),
              NOW()
            )
            ON CONFLICT (account_type, name) DO NOTHING;
          ELSE
            INSERT INTO ledger_accounts (id, account_type, name, description, inserted_at, updated_at)
            VALUES (
              gen_random_uuid(),
              '#{account_type}',
              '#{name}',
              '#{description}',
              NOW(),
              NOW()
            )
            ON CONFLICT (account_type, name) DO NOTHING;
          END IF;
        END $$;
      """
    end)
  end

  def down do
    # Remove basic accounts
    execute """
      DELETE FROM ledger_accounts
      WHERE name IN (
        'cash', 'stripe_account', 'accounts_receivable',
        'membership_revenue', 'event_revenue',
        'tahoe_booking_revenue', 'clear_lake_booking_revenue', 'donation_revenue',
        'stripe_fees', 'discount_expense'
      );
    """
  end
end
