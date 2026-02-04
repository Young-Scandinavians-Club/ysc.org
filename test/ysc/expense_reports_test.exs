defmodule Ysc.ExpenseReportsTest do
  @moduledoc """
  Tests for the Ysc.ExpenseReports context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.{BankAccount}

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "list_expense_reports/1" do
    test "returns empty list for user with no expense reports", %{user: user} do
      result = ExpenseReports.list_expense_reports(user)
      assert result == []
    end
  end

  describe "bank accounts" do
    test "list_bank_accounts/1 returns empty list for user with no bank accounts",
         %{user: user} do
      assert ExpenseReports.list_bank_accounts(user) == []
    end

    test "create_bank_account/2 creates a bank account", %{user: user} do
      # Use valid ABA routing number (Bank of America)
      attrs = %{
        "routing_number" => "021000021",
        "account_number" => "987654321"
      }

      assert {:ok, %BankAccount{} = bank_account} =
               ExpenseReports.create_bank_account(attrs, user)

      assert bank_account.account_number_last_4 == "4321"
      assert bank_account.user_id == user.id
    end

    test "get_bank_account!/2 returns a bank account", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "987654321"
          },
          user
        )

      result = ExpenseReports.get_bank_account!(bank_account.id, user)
      assert result.id == bank_account.id
    end

    test "get_bank_account!/2 raises when not found", %{user: user} do
      assert_raise Ecto.NoResultsError, fn ->
        ExpenseReports.get_bank_account!(Ecto.ULID.generate(), user)
      end
    end

    test "get_bank_account/2 returns nil when not found", %{user: user} do
      assert ExpenseReports.get_bank_account(Ecto.ULID.generate(), user) == nil
    end

    test "update_bank_account/2 updates the bank account", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "987654321"
          },
          user
        )

      # Update with new account number (last 4 should change)
      {:ok, updated} =
        ExpenseReports.update_bank_account(bank_account, %{
          "account_number" => "123456789"
        })

      assert updated.account_number_last_4 == "6789"
    end

    test "delete_bank_account/1 deletes the bank account", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "987654321"
          },
          user
        )

      {:ok, _} = ExpenseReports.delete_bank_account(bank_account)
      assert ExpenseReports.get_bank_account(bank_account.id, user) == nil
    end

    # Note: unique constraint on user_id prevents multiple bank accounts per user
    # Removed "list_bank_accounts returns multiple" test as it violates the constraint

    test "user cannot access another user's bank accounts" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "987654321"
          },
          user1
        )

      # User2 cannot get user1's bank account
      assert ExpenseReports.get_bank_account(bank_account.id, user2) == nil

      # User2's list should be empty
      assert ExpenseReports.list_bank_accounts(user2) == []
    end
  end

  describe "receipt_url/1" do
    test "returns nil for nil input" do
      assert ExpenseReports.receipt_url(nil) == nil
    end

    test "constructs URL for valid S3 path" do
      s3_path = "receipts/test.pdf"
      url = ExpenseReports.receipt_url(s3_path)
      assert is_binary(url)
      # The path is base64 encoded in the URL
      encoded_path = Base.url_encode64(s3_path, padding: false)
      assert String.contains?(url, encoded_path)
      assert String.starts_with?(url, "/expensereport/files/")
    end
  end

  describe "expense report creation and workflow" do
    test "creates expense report", %{user: user} do
      # Create bank account for user (required for bank_transfer)
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      attrs = %{
        "user_id" => user.id,
        "status" => "draft",
        "purpose" => "Test expense report",
        "reimbursement_method" => "bank_transfer",
        "bank_account_id" => bank_account.id
      }

      assert {:ok, %Ysc.ExpenseReports.ExpenseReport{} = report} =
               ExpenseReports.create_expense_report(attrs, user)

      assert report.user_id == user.id
      assert report.status == "draft"
    end

    test "updates expense report status", %{user: user} do
      # Create bank account for user (required for bank_transfer)
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      # Preload expense_items association before updating to avoid changeset error
      report = Ysc.Repo.preload(report, :expense_items)

      assert {:ok, updated} =
               ExpenseReports.update_expense_report(report, %{
                 status: "approved"
               })

      assert updated.status == "approved"
    end
  end
end
