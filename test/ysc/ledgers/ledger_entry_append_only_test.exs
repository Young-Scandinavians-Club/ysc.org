defmodule Ysc.Ledgers.LedgerEntryAppendOnlyTest do
  @moduledoc """
  Tests for the ledger_entries table append-only trigger.

  This ensures financial data cannot be modified after insertion,
  maintaining audit compliance and data integrity.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Repo
  alias Ysc.Ledgers
  alias Ysc.Ledgers.LedgerEntry

  import Ysc.AccountsFixtures

  describe "ledger_entries append-only trigger" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "allows inserting new ledger entries", %{user: user} do
      # Create a payment which creates ledger entries
      {:ok, {payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_insert",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      # Should create 4 entries (2 for payment + 2 for stripe fee)
      assert length(entries) == 4
      assert payment.id != nil

      # Verify entries were persisted
      Enum.each(entries, fn entry ->
        persisted = Repo.get(LedgerEntry, entry.id)
        assert persisted != nil
        assert persisted.id == entry.id
      end)
    end

    test "prevents updating ledger entries", %{user: user} do
      # Create a payment with ledger entries
      {:ok, {_payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_update",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      entry = List.first(entries)

      # Try to update the entry's description
      changeset =
        entry
        |> Ecto.Changeset.change(%{description: "Modified description"})

      # Should raise an exception with the trigger's error message
      assert_raise Postgrex.Error, fn ->
        Repo.update!(changeset)
      end
    end

    test "prevents deleting ledger entries", %{user: user} do
      # Create a payment with ledger entries
      {:ok, {_payment, _transaction, entries}} =
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

      entry = List.first(entries)

      # Try to delete the entry
      # Should raise an exception with the trigger's error message
      assert_raise Postgrex.Error, fn ->
        Repo.delete!(entry)
      end

      # Verify entry still exists
      assert Repo.get(LedgerEntry, entry.id) != nil
    end

    test "trigger error message mentions append-only requirement", %{
      user: user
    } do
      # Create a payment with ledger entries
      {:ok, {_payment, _transaction, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_error_msg",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      entry = List.first(entries)

      # Try to update - capture the error to inspect message
      error =
        try do
          entry
          |> Ecto.Changeset.change(%{description: "Modified"})
          |> Repo.update!()

          nil
        rescue
          e in Postgrex.Error -> e
        end

      assert error != nil

      # Check that error message mentions append-only
      error_message = Exception.message(error)
      assert error_message =~ ~r/append-only/i
      assert error_message =~ ~r/audit compliance/i
    end

    test "allows creating multiple entries in sequence", %{user: user} do
      # Create first payment
      {:ok, {payment1, _t1, entries1}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_seq_1",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "First payment",
          property: :general,
          payment_method_id: nil
        })

      # Create second payment
      {:ok, {payment2, _t2, entries2}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(15_000, :USD),
          external_payment_id: "pi_test_seq_2",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(450, :USD),
          description: "Second payment",
          property: :general,
          payment_method_id: nil
        })

      # Both should succeed (4 entries each: 2 for payment + 2 for stripe fee)
      assert length(entries1) == 4
      assert length(entries2) == 4
      assert payment1.id != payment2.id

      # All entries should be in database
      all_entry_ids = (entries1 ++ entries2) |> Enum.map(& &1.id)

      Enum.each(all_entry_ids, fn id ->
        assert Repo.get(LedgerEntry, id) != nil
      end)
    end

    test "refund entries are also protected from modification", %{user: user} do
      # Create payment
      {:ok, {payment, _t, _entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(20_000, :USD),
          external_payment_id: "pi_test_refund_protect",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(600, :USD),
          description: "Test payment",
          property: :general,
          payment_method_id: nil
        })

      # Create refund
      {:ok, {_refund, _transaction, refund_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(10_000, :USD),
          reason: "Test refund",
          external_refund_id: "re_test_protect"
        })

      refund_entry = List.first(refund_entries)

      # Try to update the refund entry
      assert_raise Postgrex.Error, fn ->
        refund_entry
        |> Ecto.Changeset.change(%{description: "Modified refund"})
        |> Repo.update!()
      end

      # Try to delete the refund entry
      assert_raise Postgrex.Error, fn ->
        Repo.delete!(refund_entry)
      end

      # Verify entry still exists unchanged
      persisted = Repo.get(LedgerEntry, refund_entry.id)
      assert persisted.description == refund_entry.description
    end
  end

  describe "proper correction workflow without trigger" do
    setup do
      Ledgers.ensure_basic_accounts()
      user = user_fixture()
      {:ok, user: user}
    end

    test "demonstrates correct way to handle corrections with reversing entries",
         %{user: user} do
      # Create original payment
      {:ok, {payment, _t, entries}} =
        Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(10_000, :USD),
          external_payment_id: "pi_test_correct",
          entity_type: :membership,
          entity_id: Ecto.ULID.generate(),
          stripe_fee: Money.new(300, :USD),
          description: "Original payment",
          property: :general,
          payment_method_id: nil
        })

      original_entry_count = length(entries)

      # Instead of modifying, create a refund (reversing entry)
      {:ok, {_refund, _transaction, _reversing_entries}} =
        Ledgers.process_refund(%{
          payment_id: payment.id,
          refund_amount: Money.new(10_000, :USD),
          reason: "Correction via refund",
          external_refund_id: "re_test_correct"
        })

      # Now we have original entries + reversing entries
      all_entries = Ledgers.get_entries_by_payment(payment.id)

      assert length(all_entries) == original_entry_count + 2

      # All entries are preserved and immutable
      Enum.each(all_entries, fn entry ->
        # Verify each entry cannot be modified
        assert_raise Postgrex.Error, fn ->
          entry
          |> Ecto.Changeset.change(%{description: "Cannot change"})
          |> Repo.update!()
        end
      end)

      # This demonstrates the audit trail is complete and immutable
    end
  end
end
