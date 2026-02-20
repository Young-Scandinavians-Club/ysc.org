defmodule Ysc.Repo.Migrations.BackfillRefundIdInLedgerEntries do
  use Ecto.Migration

  @moduledoc """
  Backfills the `refund_id` column on `ledger_entries` rows that were created
  during the window between:
    - 2025-11-20: `refund_id` was added to `ledger_transactions`
    - 2026-02-03: `refund_id` was added to `ledger_entries`

  During that window, `create_refund_entries/1` wrote entries without
  `refund_id` because the column did not yet exist. Those entries have
  `refund_id = NULL` even though the corresponding `LedgerTransaction` has
  `refund_id` set correctly.

  We can identify the affected entries unambiguously for payments that have
  exactly one refund transaction:
    - Revenue DEBIT entries (only ever created by create_refund_entries)
    - Stripe account CREDIT entries with a matching entity type (only ever
      created by create_refund_entries for refund-type transactions)

  Payments with multiple refunds are skipped to avoid ambiguous assignment.
  The append-only trigger is temporarily disabled so the UPDATE can run.
  """

  def up do
    execute "ALTER TABLE ledger_entries DISABLE TRIGGER ledger_entries_append_only_trigger"

    # MAX() is not supported on UUID columns in PostgreSQL, so we use a two-step
    # CTE: first find payment_ids with exactly one distinct refund, then join
    # back to retrieve the actual refund_id value.
    #
    # NOTE: ledger_accounts is listed in the FROM clause alongside
    # single_refund_payments (comma-separated, not JOINed). PostgreSQL does not
    # allow referencing the UPDATE target table (le) inside a JOIN condition
    # within the FROM clause, so the join condition is placed in the WHERE
    # clause instead.
    execute """
    WITH payments_with_one_refund AS (
      SELECT payment_id
      FROM ledger_transactions
      WHERE type = 'refund'
        AND refund_id IS NOT NULL
      GROUP BY payment_id
      HAVING COUNT(DISTINCT refund_id) = 1
    ),
    single_refund_payments AS (
      SELECT DISTINCT lt.payment_id, lt.refund_id
      FROM ledger_transactions lt
      JOIN payments_with_one_refund p ON lt.payment_id = p.payment_id
      WHERE lt.type = 'refund'
        AND lt.refund_id IS NOT NULL
    )
    UPDATE ledger_entries le
    SET refund_id = srp.refund_id
    FROM single_refund_payments srp, ledger_accounts la
    WHERE le.payment_id = srp.payment_id
      AND le.account_id = la.id
      AND le.refund_id IS NULL
      AND (
        (la.account_type = 'revenue' AND le.debit_credit = 'debit')
        OR
        (la.name = 'stripe_account' AND le.debit_credit = 'credit')
      )
    """

    execute "ALTER TABLE ledger_entries ENABLE TRIGGER ledger_entries_append_only_trigger"
  end

  def down do
    :ok
  end
end
