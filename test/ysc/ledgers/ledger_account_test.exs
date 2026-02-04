defmodule Ysc.Ledgers.LedgerAccountTest do
  @moduledoc """
  Tests for LedgerAccount schema.

  These tests verify:
  - Changeset validations for all fields
  - EctoEnum handling (account_type, normal_balance)
  - Unique constraint on account name
  - Field length validations
  - Required fields enforcement
  """
  use Ysc.DataCase, async: true

  alias Ysc.Ledgers.LedgerAccount
  alias Ysc.Repo

  describe "changeset/2" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Sales Revenue"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
      assert changeset.changes.account_type == :revenue
      assert changeset.changes.normal_balance == :credit
      assert changeset.changes.name == "Sales Revenue"
    end

    test "creates valid changeset with optional description" do
      attrs = %{
        account_type: :asset,
        normal_balance: :debit,
        name: "Cash Account",
        description: "Main operating cash account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
      assert changeset.changes.description == "Main operating cash account"
    end

    test "requires account_type" do
      attrs = %{
        normal_balance: :debit,
        name: "Test Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:account_type] != nil
    end

    test "requires normal_balance" do
      attrs = %{
        account_type: :revenue,
        name: "Test Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:normal_balance] != nil
    end

    test "requires name" do
      attrs = %{
        account_type: :revenue,
        normal_balance: :credit
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "validates name minimum length" do
      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: ""
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "validates name maximum length" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: long_name
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:name] != nil
    end

    test "accepts name with exactly 255 characters" do
      valid_name = String.duplicate("a", 255)

      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: valid_name
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
    end

    test "validates description maximum length" do
      long_description = String.duplicate("a", 1001)

      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Test Account",
        description: long_description
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:description] != nil
    end

    test "accepts description with exactly 1000 characters" do
      valid_description = String.duplicate("a", 1000)

      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Test Account",
        description: valid_description
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
    end
  end

  describe "EctoEnum handling" do
    test "accepts all valid account_type values" do
      account_types = [:revenue, :liability, :expense, :asset, :equity]

      for account_type <- account_types do
        attrs = %{
          account_type: account_type,
          normal_balance: :debit,
          name: "Test #{account_type}"
        }

        changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

        assert changeset.valid?,
               "Expected account_type #{account_type} to be valid"
      end
    end

    test "rejects invalid account_type values" do
      # EctoEnum converts invalid atoms to nil, which then fails validation
      attrs = %{
        account_type: :invalid_type,
        normal_balance: :debit,
        name: "Test Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)
      refute changeset.valid?
    end

    test "accepts debit normal_balance" do
      attrs = %{
        account_type: :asset,
        normal_balance: :debit,
        name: "Asset Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
      assert changeset.changes.normal_balance == :debit
    end

    test "accepts credit normal_balance" do
      attrs = %{
        account_type: :liability,
        normal_balance: :credit,
        name: "Liability Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert changeset.valid?
      assert changeset.changes.normal_balance == :credit
    end

    test "rejects invalid normal_balance values" do
      # EctoEnum converts invalid atoms to nil, which then fails validation
      attrs = %{
        account_type: :asset,
        normal_balance: :invalid_balance,
        name: "Test Account"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)
      refute changeset.valid?
    end
  end

  describe "database constraints" do
    test "enforces unique constraint on account_type and name combination" do
      # The database has a composite unique constraint on (account_type, name)
      # but the changeset uses unique_constraint(:name), so the error will be on :name
      attrs = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Unique Account #{System.unique_integer()}"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)
      {:ok, _account1} = Repo.insert(changeset)

      # Try to insert another account with the same account_type and name
      # The constraint name in DB is "ledger_accounts_account_type_name_index"
      # but changeset.unique_constraint(:name) expects "ledger_accounts_name_index"
      # so this will raise ConstraintError instead of adding to changeset.errors
      changeset2 = LedgerAccount.changeset(%LedgerAccount{}, attrs)

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert(changeset2)
      end
    end

    test "allows different accounts with different names" do
      attrs1 = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Account One"
      }

      attrs2 = %{
        account_type: :revenue,
        normal_balance: :credit,
        name: "Account Two"
      }

      changeset1 = LedgerAccount.changeset(%LedgerAccount{}, attrs1)
      changeset2 = LedgerAccount.changeset(%LedgerAccount{}, attrs2)

      {:ok, account1} = Repo.insert(changeset1)
      {:ok, account2} = Repo.insert(changeset2)

      assert account1.name == "Account One"
      assert account2.name == "Account Two"
    end

    test "can insert valid account and retrieve it" do
      attrs = %{
        account_type: :expense,
        normal_balance: :debit,
        name: "Operating Expenses",
        description: "General operating expenses"
      }

      changeset = LedgerAccount.changeset(%LedgerAccount{}, attrs)
      {:ok, account} = Repo.insert(changeset)

      retrieved = Repo.get(LedgerAccount, account.id)

      assert retrieved.account_type == :expense
      assert retrieved.normal_balance == :debit
      assert retrieved.name == "Operating Expenses"
      assert retrieved.description == "General operating expenses"
      assert retrieved.inserted_at != nil
      assert retrieved.updated_at != nil
    end
  end
end
