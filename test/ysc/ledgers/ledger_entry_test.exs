defmodule Ysc.Ledgers.LedgerEntryTest do
  @moduledoc """
  Tests for LedgerEntry schema.

  These tests verify:
  - Debit/credit enum validation
  - Money type handling and precision
  - Required associations (account)
  - Related entity tracking
  - Description validation
  - Database constraints
  """
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers.{LedgerEntry, LedgerAccount}
  alias Ysc.Repo

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    {:ok, account} =
      %LedgerAccount{}
      |> LedgerAccount.changeset(%{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Test Revenue #{System.unique_integer()}"
      })
      |> Repo.insert()

    %{account: account}
  end

  describe "changeset/2" do
    test "creates valid changeset with all required fields", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      assert changeset.valid?
      assert changeset.changes.account_id == account.id
      assert changeset.changes.amount == Money.new(10_000, :USD)
      assert changeset.changes.debit_credit == :credit
    end

    test "creates valid changeset with optional fields", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :debit,
        description: "Test entry description",
        related_entity_type: :booking,
        related_entity_id: Ecto.ULID.generate()
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      assert changeset.valid?
      assert changeset.changes.description == "Test entry description"
      assert changeset.changes.related_entity_type == :booking
      assert changeset.changes.related_entity_id != nil
    end

    test "requires account_id" do
      attrs = %{
        amount: Money.new(10_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:account_id] != nil
    end

    test "requires amount" do
      attrs = %{
        account_id: Ecto.ULID.generate(),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:amount] != nil
    end

    test "requires debit_credit" do
      attrs = %{
        account_id: Ecto.ULID.generate(),
        amount: Money.new(10_000, :USD)
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:debit_credit] != nil
    end

    test "validates description maximum length", %{account: account} do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit,
        description: long_description
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 1000 characters", %{account: account} do
      valid_description = String.duplicate("a", 1000)

      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit,
        description: valid_description
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      assert changeset.valid?
    end
  end

  describe "Money type handling" do
    test "handles positive amounts", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :debit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      assert entry.amount == Money.new(10_000, :USD)
    end

    test "handles zero amounts", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(0, :USD),
        debit_credit: :debit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      assert entry.amount == Money.new(0, :USD)
    end

    test "handles fractional amounts with precision", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_050, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      assert entry.amount == Money.new(10_050, :USD)
      assert Money.to_decimal(entry.amount) == Decimal.new("10050")
    end

    test "maintains precision for small amounts", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(1, :USD),
        debit_credit: :debit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      assert entry.amount == Money.new(1, :USD)
      assert Money.to_decimal(entry.amount) == Decimal.new("1")
    end

    test "handles large amounts", %{account: account} do
      # Large amount
      attrs = %{
        account_id: account.id,
        amount: Money.new(100_000_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      assert entry.amount == Money.new(100_000_000, :USD)
      assert Money.to_decimal(entry.amount) == Decimal.new("100000000")
    end
  end

  describe "debit_credit enum" do
    test "accepts debit value", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :debit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      assert changeset.valid?
      assert changeset.changes.debit_credit == :debit
    end

    test "accepts credit value", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

      assert changeset.valid?
      assert changeset.changes.debit_credit == :credit
    end

    test "rejects invalid debit_credit values" do
      attrs = %{
        account_id: Ecto.ULID.generate(),
        amount: Money.new(10_000, :USD),
        debit_credit: :invalid
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      refute changeset.valid?
    end
  end

  describe "related_entity_type enum" do
    test "accepts all valid entity types", %{account: account} do
      entity_types = [:event, :membership, :booking, :donation, :administration]

      for entity_type <- entity_types do
        attrs = %{
          account_id: account.id,
          amount: Money.new(10_000, :USD),
          debit_credit: :debit,
          related_entity_type: entity_type,
          related_entity_id: Ecto.ULID.generate()
        }

        changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)

        assert changeset.valid?,
               "Expected entity_type #{entity_type} to be valid"
      end
    end

    test "rejects invalid entity_type values" do
      attrs = %{
        account_id: Ecto.ULID.generate(),
        amount: Money.new(10_000, :USD),
        debit_credit: :debit,
        related_entity_type: :invalid_type
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      refute changeset.valid?
    end
  end

  describe "database constraints" do
    test "enforces foreign key constraint on account_id" do
      invalid_account_id = Ecto.ULID.generate()

      attrs = %{
        account_id: invalid_account_id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:account_id] != nil
    end

    test "can insert and retrieve complete entry", %{account: account} do
      related_entity_id = Ecto.ULID.generate()

      attrs = %{
        account_id: account.id,
        amount: Money.new(50_000, :USD),
        debit_credit: :debit,
        description: "Test entry for retrieval",
        related_entity_type: :membership,
        related_entity_id: related_entity_id
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      retrieved = Repo.get(LedgerEntry, entry.id)

      assert retrieved.account_id == account.id
      assert retrieved.amount == Money.new(50_000, :USD)
      assert retrieved.debit_credit == :debit
      assert retrieved.description == "Test entry for retrieval"
      assert retrieved.related_entity_type == :membership
      assert retrieved.related_entity_id == related_entity_id
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end

    test "can retrieve entry with preloaded account", %{account: account} do
      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      retrieved =
        LedgerEntry
        |> Repo.get(entry.id)
        |> Repo.preload(:account)

      assert retrieved.account.id == account.id
      assert retrieved.account.name == account.name
    end
  end

  describe "payment association" do
    test "can associate entry with payment", %{account: account} do
      user = Ysc.AccountsFixtures.user_fixture()
      payment = Ysc.LedgersFixtures.payment_fixture(user_id: user.id)

      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :debit,
        payment_id: payment.id
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:ok, entry} = Repo.insert(changeset)

      retrieved =
        LedgerEntry
        |> Repo.get(entry.id)
        |> Repo.preload(:payment)

      assert retrieved.payment.id == payment.id
    end

    test "enforces foreign key constraint on payment_id", %{account: account} do
      invalid_payment_id = Ecto.ULID.generate()

      attrs = %{
        account_id: account.id,
        amount: Money.new(10_000, :USD),
        debit_credit: :credit,
        payment_id: invalid_payment_id
      }

      changeset = LedgerEntry.changeset(%LedgerEntry{}, attrs)
      {:error, changeset_error} = Repo.insert(changeset)

      assert changeset_error.errors[:payment_id] != nil
    end
  end
end
