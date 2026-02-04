defmodule Ysc.Ledgers.RefundIdTest do
  use Ysc.DataCase, async: false

  alias Ysc.Ledgers
  alias Ysc.Ledgers.{Refund, Payment}

  import Ysc.AccountsFixtures

  describe "refund_id foreign key constraint" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "ledger entries can be created with refund_id", %{user: user} do
      # Create a payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_123",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      # Create a refund
      {:ok, {refund, _transaction, entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Test refund",
          external_refund_id: "re_test_123"
        })

      # Verify all entries have refund_id set
      assert length(entries) == 2

      Enum.each(entries, fn entry ->
        assert entry.refund_id == refund.id
        assert entry.payment_id == payment.id
      end)
    end

    test "refund_id foreign key constraint prevents invalid refund_id" do
      account = Ledgers.get_account_by_name("membership_revenue")

      # Try to create an entry with invalid refund_id
      invalid_refund_id = Ecto.ULID.generate()

      assert {:error, changeset} =
               Ledgers.create_entry(%{
                 account_id: account.id,
                 refund_id: invalid_refund_id,
                 amount: Money.new(1_000, :USD),
                 debit_credit: :debit,
                 description: "Test entry"
               })

      assert "does not exist" in errors_on(changeset).refund_id
    end

    test "deleting a refund is prevented when ledger entries exist (RESTRICT)",
         %{
           user: user
         } do
      # Create payment and refund with entries
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_delete",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Test refund",
          external_refund_id: "re_test_delete"
        })

      # Try to delete the refund - should fail due to RESTRICT
      # Can raise either Postgrex.Error or Ecto.ConstraintError depending on Ecto's internal state
      error =
        try do
          Repo.delete!(refund)

          flunk(
            "Expected either Postgrex.Error or Ecto.ConstraintError to be raised"
          )
        rescue
          e in [Postgrex.Error, Ecto.ConstraintError] -> e
        end

      assert error.__struct__ in [Postgrex.Error, Ecto.ConstraintError]

      # Verify refund still exists
      assert Repo.get(Refund, refund.id) != nil
    end
  end

  describe "get_entries_by_refund/1" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "returns all entries for a specific refund", %{user: user} do
      # Create payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          external_payment_id: "pi_test_query",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(600, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      # Create first refund
      {:ok, {refund1, _transaction1, entries1}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "First refund",
          external_refund_id: "re_test_1"
        })

      # Create second refund
      {:ok, {refund2, _transaction2, _entries2}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(3_000, :USD),
          reason: "Second refund",
          external_refund_id: "re_test_2"
        })

      # Query entries for refund1
      refund1_entries = Ledgers.get_entries_by_refund(refund1.id)
      assert length(refund1_entries) == 2
      assert Enum.all?(refund1_entries, &(&1.refund_id == refund1.id))

      # Verify entry IDs match
      refund1_entry_ids = Enum.map(entries1, & &1.id) |> Enum.sort()
      queried_entry_ids = Enum.map(refund1_entries, & &1.id) |> Enum.sort()
      assert refund1_entry_ids == queried_entry_ids

      # Query entries for refund2
      refund2_entries = Ledgers.get_entries_by_refund(refund2.id)
      assert length(refund2_entries) == 2
      assert Enum.all?(refund2_entries, &(&1.refund_id == refund2.id))

      # Verify no overlap between refund entries
      refund1_ids = MapSet.new(refund1_entries, & &1.id)
      refund2_ids = MapSet.new(refund2_entries, & &1.id)
      assert MapSet.disjoint?(refund1_ids, refund2_ids)
    end

    test "returns empty list for refund with no entries" do
      # Create a refund directly without entries (shouldn't happen in practice)
      user = user_fixture()

      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_orphan",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, refund} =
        Ledgers.create_refund(%{
          payment_id: payment.id,
          user_id: user.id,
          amount: Money.new(1_000, :USD),
          external_provider: :stripe,
          external_refund_id: "re_orphan",
          reason: "Orphan refund",
          status: :completed
        })

      # Should return empty list
      entries = Ledgers.get_entries_by_refund(refund.id)
      assert entries == []
    end

    test "preloads account association", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_preload",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Test refund",
          external_refund_id: "re_preload"
        })

      entries = Ledgers.get_entries_by_refund(refund.id)

      # Verify account is loaded
      Enum.each(entries, fn entry ->
        assert Ecto.assoc_loaded?(entry.account)
        assert entry.account.id != nil
        assert entry.account.name != nil
      end)
    end
  end

  describe "reconciliation with refund_id" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "check_refund_consistency finds refund entries using refund_id", %{
      user: user
    } do
      # Create payment and refund
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(15_000, :USD),
          external_payment_id: "pi_reconcile",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(450, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, {_refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(7_500, :USD),
          reason: "Test refund",
          external_refund_id: "re_reconcile"
        })

      # Run reconciliation
      {:ok, report} = Ledgers.Reconciliation.run_full_reconciliation()

      # Should have no issues
      assert report.overall_status == :ok
      assert report.checks.refunds.status == :ok
      assert report.checks.refunds.discrepancies == []
      assert report.checks.refunds.total_refunds > 0
    end

    test "detects missing refund entries", %{user: user} do
      # Create payment and refund
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_missing",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, refund} =
        Ledgers.create_refund(%{
          payment_id: payment.id,
          user_id: user.id,
          amount: Money.new(5_000, :USD),
          external_provider: :stripe,
          external_refund_id: "re_missing",
          reason: "Refund without entries",
          status: :completed
        })

      # Create transaction but skip entries
      Ledgers.create_transaction(%{
        type: :refund,
        payment_id: payment.id,
        refund_id: refund.id,
        total_amount: Money.new(5_000, :USD),
        status: :completed
      })

      # Run reconciliation - should detect missing entries
      {:ok, report} = Ledgers.Reconciliation.run_full_reconciliation()

      assert report.overall_status == :error
      assert report.checks.refunds.status == :error

      # Find the discrepancy for our refund
      discrepancy =
        Enum.find(report.checks.refunds.discrepancies, fn d ->
          d.refund_id == refund.id
        end)

      assert discrepancy != nil
      assert "No refund ledger entries found" in discrepancy.issues
    end

    test "handles multiple partial refunds correctly", %{user: user} do
      # Create a payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(30_000, :USD),
          external_payment_id: "pi_multi_refund",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(900, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      # Create three partial refunds
      {:ok, {refund1, _t1, entries1}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(10_000, :USD),
          reason: "First partial refund",
          external_refund_id: "re_partial_1"
        })

      {:ok, {refund2, _t2, entries2}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(8_000, :USD),
          reason: "Second partial refund",
          external_refund_id: "re_partial_2"
        })

      {:ok, {refund3, _t3, entries3}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Third partial refund",
          external_refund_id: "re_partial_3"
        })

      # Verify each refund has exactly 2 entries with correct refund_id
      assert length(entries1) == 2
      assert Enum.all?(entries1, &(&1.refund_id == refund1.id))

      assert length(entries2) == 2
      assert Enum.all?(entries2, &(&1.refund_id == refund2.id))

      assert length(entries3) == 2
      assert Enum.all?(entries3, &(&1.refund_id == refund3.id))

      # Verify entries can be queried independently
      assert length(Ledgers.get_entries_by_refund(refund1.id)) == 2
      assert length(Ledgers.get_entries_by_refund(refund2.id)) == 2
      assert length(Ledgers.get_entries_by_refund(refund3.id)) == 2

      # Verify all entries for the payment include refund entries
      all_payment_entries = Ledgers.get_entries_by_payment(payment.id)

      # Should have original payment entries (2) + refund entries (6)
      assert length(all_payment_entries) >= 8

      # Verify no duplicate entries across refunds
      all_refund_entry_ids =
        (entries1 ++ entries2 ++ entries3)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert length(all_refund_entry_ids) ==
               length(Enum.uniq(all_refund_entry_ids))

      # Run reconciliation - should pass
      {:ok, report} = Ledgers.Reconciliation.run_full_reconciliation()
      assert report.overall_status == :ok
      assert report.checks.refunds.status == :ok
    end
  end

  describe "refund entry amounts and accounts" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "creates correct double-entry bookkeeping for refund", %{user: user} do
      # Create payment
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          external_payment_id: "pi_double_entry",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(600, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      refund_amount = Money.new(12_000, :USD)

      {:ok, {refund, _transaction, entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: refund_amount,
          reason: "Customer request",
          external_refund_id: "re_double_entry"
        })

      assert length(entries) == 2

      # Find debit and credit entries
      [entry1, entry2] = entries

      debit_entry =
        if entry1.debit_credit == :debit, do: entry1, else: entry2

      credit_entry =
        if entry1.debit_credit == :credit, do: entry1, else: entry2

      # Verify debit entry (revenue reversal)
      assert debit_entry.debit_credit == :debit
      assert debit_entry.amount == refund_amount
      assert debit_entry.refund_id == refund.id
      assert debit_entry.payment_id == payment.id

      assert String.contains?(
               String.downcase(debit_entry.description),
               "revenue"
             )

      # Verify credit entry (stripe account reduction)
      assert credit_entry.debit_credit == :credit
      assert credit_entry.amount == refund_amount
      assert credit_entry.refund_id == refund.id
      assert credit_entry.payment_id == payment.id

      assert String.contains?(
               String.downcase(credit_entry.description),
               "stripe"
             )

      # Verify accounts are different
      assert debit_entry.account_id != credit_entry.account_id

      # Verify both entries are equal amounts (double-entry bookkeeping)
      assert Money.equal?(debit_entry.amount, credit_entry.amount)
    end

    test "refund entries reference both payment and refund", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_references",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, {refund, _transaction, entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Test",
          external_refund_id: "re_references"
        })

      # Every refund entry should have both payment_id and refund_id
      Enum.each(entries, fn entry ->
        assert entry.payment_id == payment.id
        assert entry.refund_id == refund.id

        # Verify we can query by either
        payment_entries = Ledgers.get_entries_by_payment(payment.id)
        refund_entries = Ledgers.get_entries_by_refund(refund.id)

        assert Enum.any?(payment_entries, &(&1.id == entry.id))
        assert Enum.any?(refund_entries, &(&1.id == entry.id))
      end)
    end
  end

  describe "edge cases and data integrity" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "cannot set refund_id without payment_id", %{user: user} do
      {:ok, {payment, _transaction, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_edge",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      {:ok, {refund, _transaction, _entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(5_000, :USD),
          reason: "Test",
          external_refund_id: "re_edge"
        })

      account = Ledgers.get_account_by_name("membership_revenue")

      # Try to create entry with refund_id but no payment_id
      # This should work at the schema level but may be semantically wrong
      {:ok, entry} =
        Ledgers.create_entry(%{
          account_id: account.id,
          refund_id: refund.id,
          # No payment_id
          amount: Money.new(1_000, :USD),
          debit_credit: :debit,
          description: "Test entry"
        })

      # Schema allows it but we should ensure our process_refund always sets both
      assert entry.refund_id == refund.id
      assert entry.payment_id == nil
    end

    test "full refund scenario with accurate tracking", %{user: user} do
      # Create payment
      original_amount = Money.new(25_000, :USD)

      {:ok, {payment, _transaction, payment_entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: original_amount,
          external_payment_id: "pi_full_refund",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(750, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      initial_entry_count = length(payment_entries)

      # Do a full refund
      {:ok, {refund, _transaction, refund_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: original_amount,
          reason: "Full refund",
          external_refund_id: "re_full_refund"
        })

      # Verify refund entries
      assert length(refund_entries) == 2
      assert Enum.all?(refund_entries, &(&1.refund_id == refund.id))
      assert Enum.all?(refund_entries, &(&1.payment_id == payment.id))

      # Verify we can distinguish payment entries from refund entries
      all_entries = Ledgers.get_entries_by_payment(payment.id)

      assert length(all_entries) == initial_entry_count + 2

      payment_only_entries =
        Enum.filter(all_entries, &is_nil(&1.refund_id))

      refund_only_entries =
        Enum.filter(all_entries, &(&1.refund_id == refund.id))

      assert length(payment_only_entries) == initial_entry_count
      assert length(refund_only_entries) == 2

      # Verify payment status updated to refunded
      updated_payment = Repo.get(Payment, payment.id)
      assert updated_payment.status == :refunded
    end
  end
end
