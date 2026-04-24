defmodule Ysc.ExpenseReportsTest do
  @moduledoc """
  Tests for the Ysc.ExpenseReports context module.
  """
  use Ysc.DataCase, async: true

  import Mox
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts
  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.BankAccount
  alias Ysc.Repo
  alias YscWeb.Workers.EmailNotifier

  setup do
    user = user_fixture()
    %{user: user}
  end

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "list_expense_reports/1" do
    test "returns empty list for user with no expense reports", %{user: user} do
      result = ExpenseReports.list_expense_reports(user)
      assert result == []
    end

    test "loads bank_account for each report when bank_account_id is set", %{
      user: user
    } do
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
            "status" => "draft",
            "purpose" => "List with bank account",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      [listed] =
        ExpenseReports.list_expense_reports(user)
        |> Enum.filter(&(&1.id == report.id))

      assert listed.bank_account_id == bank_account.id
      assert %BankAccount{} = listed.bank_account
      assert listed.bank_account.id == bank_account.id
    end

    test "list_expense_reports/1 and get_expense_report!/2 set bank_account nil when bank_account_id is nil",
         %{user: user} do
      {:ok, _} =
        Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "Oakland",
          "region" => "CA",
          "postal_code" => "94601",
          "country" => "US"
        })

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "status" => "draft",
            "purpose" => "Check reimbursement no bank on file",
            "reimbursement_method" => "check"
          },
          user
        )

      assert report.bank_account_id == nil

      [listed] =
        ExpenseReports.list_expense_reports(user)
        |> Enum.filter(&(&1.id == report.id))

      assert listed.bank_account_id == nil
      assert listed.bank_account == nil

      fetched = ExpenseReports.get_expense_report!(report.id, user)
      assert fetched.bank_account_id == nil
      assert fetched.bank_account == nil
    end

    test "preloads event association when event_id is set", %{user: user} do
      event = event_fixture(%{organizer_id: user.id})

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
            "status" => "draft",
            "purpose" => "Event-linked report",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "event_id" => event.id
          },
          user
        )

      [listed] =
        ExpenseReports.list_expense_reports(user)
        |> Enum.filter(&(&1.id == report.id))

      assert listed.event_id == event.id
      assert Ecto.assoc_loaded?(listed.event)
      assert listed.event.id == event.id

      fetched = ExpenseReports.get_expense_report!(report.id, user)
      assert fetched.event_id == event.id
      assert Ecto.assoc_loaded?(fetched.event)
      assert fetched.event.id == event.id
    end

    test "orders by inserted_at descending (newest first)", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      base = %{
        "status" => "draft",
        "reimbursement_method" => "bank_transfer",
        "bank_account_id" => bank_account.id
      }

      {:ok, older} =
        ExpenseReports.create_expense_report(
          Map.put(base, "purpose", "older report"),
          user
        )

      {:ok, newer} =
        ExpenseReports.create_expense_report(
          Map.put(base, "purpose", "newer report"),
          user
        )

      old_ts =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        older
        |> Ecto.Changeset.change(%{inserted_at: old_ts, updated_at: old_ts})
        |> Repo.update()

      ids =
        user
        |> ExpenseReports.list_expense_reports()
        |> Enum.map(& &1.id)

      newer_idx = Enum.find_index(ids, &(&1 == newer.id))
      older_idx = Enum.find_index(ids, &(&1 == older.id))
      assert newer_idx < older_idx
    end
  end

  describe "bank accounts" do
    test "create_bank_account/2 returns error when routing number fails checksum",
         %{
           user: user
         } do
      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.create_bank_account(
                 %{
                   "routing_number" => "111111111",
                   "account_number" => "1234567890"
                 },
                 user
               )

      assert cs.errors[:routing_number]
    end

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

    test "create_bank_account/2 returns error for invalid routing checksum" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.create_bank_account(
                 %{
                   "routing_number" => "111111111",
                   "account_number" => "1234567890"
                 },
                 user
               )

      assert Keyword.has_key?(cs.errors, :routing_number)
    end

    test "update_bank_account/2 returns error for invalid routing number" do
      user = user_fixture(%{phone_number: unique_user_phone()})

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.update_bank_account(bank_account, %{
                 "routing_number" => "111111111"
               })

      assert Keyword.has_key?(cs.errors, :routing_number)
    end
  end

  describe "receipt_url/1" do
    test "returns nil for nil input" do
      assert ExpenseReports.receipt_url(nil) == nil
    end

    test "returns nil for non-binary path" do
      assert ExpenseReports.receipt_url(:not_binary) == nil
      assert ExpenseReports.receipt_url(["receipts", "x"]) == nil
    end

    test "builds controller URL for empty binary path" do
      url = ExpenseReports.receipt_url("")
      assert is_binary(url)
      assert String.starts_with?(url, "/expensereport/files/")
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

  describe "upload_receipt_to_s3/2" do
    test "uses unique_key when upload result has no body key (fallback path)" do
      prev = Application.get_env(:ysc, :expense_reports_s3_upload)

      on_exit(fn ->
        Application.put_env(:ysc, :expense_reports_s3_upload, prev)
      end)

      Application.put_env(
        :ysc,
        :expense_reports_s3_upload,
        Ysc.ExpenseReports.S3UploadMockEmptyBodyKey
      )

      tmp_dir = System.tmp_dir!()

      path =
        Path.join(tmp_dir, "receipt_#{System.unique_integer([:positive])}.pdf")

      File.write!(path, "content")

      uid = Ecto.ULID.generate()

      try do
        key = ExpenseReports.upload_receipt_to_s3(path, user_id: uid)
        assert is_binary(key)
        assert String.match?(key, ~r/\Areceipts\/#{Regex.escape(uid)}\/\d+_/)
        assert String.ends_with?(key, ".pdf")
      after
        File.rm(path)
      end
    end

    test "uploads file and returns S3 key using mock", %{user: user} do
      # Create a temporary file (mock is configured in test.exs so ExAws is not called)
      tmp_dir = System.tmp_dir!()

      path =
        Path.join(tmp_dir, "receipt_#{System.unique_integer([:positive])}.pdf")

      File.write!(path, "fake receipt content")

      try do
        key = ExpenseReports.upload_receipt_to_s3(path, user_id: user.id)
        assert is_binary(key)

        assert String.match?(
                 key,
                 ~r/\Areceipts\/#{Regex.escape(user.id)}\/\d+_.*receipt_.*\.pdf/
               )

        assert String.ends_with?(key, ".pdf")
      after
        File.rm(path)
      end
    end

    test "sanitizes original_filename and preserves extension when provided", %{
      user: user
    } do
      tmp_dir = System.tmp_dir!()

      path =
        Path.join(tmp_dir, "temp_#{System.unique_integer([:positive])}.tmp")

      File.write!(path, "content")

      try do
        key =
          ExpenseReports.upload_receipt_to_s3(path,
            user_id: user.id,
            original_filename: "My Receipt (2024).pdf"
          )

        assert is_binary(key)

        assert String.match?(
                 key,
                 ~r/\Areceipts\/#{Regex.escape(user.id)}\/\d+_/
               )

        # Sanitized: parentheses and spaces -> underscores
        assert String.contains?(key, ".pdf")
      after
        File.rm(path)
      end
    end

    test "uses basename of path when original_filename not provided", %{
      user: user
    } do
      tmp_dir = System.tmp_dir!()
      basename = "custom_receipt_#{System.unique_integer([:positive])}.jpg"
      path = Path.join(tmp_dir, basename)
      File.write!(path, "content")

      try do
        key = ExpenseReports.upload_receipt_to_s3(path, user_id: user.id)
        assert String.ends_with?(key, basename)
      after
        File.rm(path)
      end
    end
  end

  describe "can_access_file?/2" do
    test "returns {:ok, report} when user owns expense report with receipt", %{
      user: user
    } do
      receipt_path = "receipts/123_owned_receipt.pdf"

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "Vendor",
                "description" => "Item",
                "amount" => "10.00",
                "receipt_s3_path" => receipt_path
              }
            ]
          },
          user
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{receipt_s3_path: receipt_path})
        |> Repo.update!()
      end

      assert {:ok, _} = ExpenseReports.can_access_file?(user, receipt_path)
    end

    test "returns {:ok, report} when user owns expense report with income proof",
         %{
           user: user
         } do
      proof_path = "proofs/999_income_proof.pdf"

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "income_items" => [
              %{
                "date" => "2024-01-15",
                "description" => "Income",
                "amount" => "20.00",
                "proof_s3_path" => proof_path
              }
            ]
          },
          user
        )

      report = Repo.preload(report, :income_items)
      item = hd(report.income_items)

      if is_nil(item.proof_s3_path) do
        item
        |> Ecto.Changeset.change(%{proof_s3_path: proof_path})
        |> Repo.update!()
      end

      assert {:ok, _} = ExpenseReports.can_access_file?(user, proof_path)
    end

    test "returns {:error, :unauthorized} when another user tries to access owner's receipt" do
      owner = user_fixture()
      other = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => "receipts/456_private.pdf"
              }
            ]
          },
          owner
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{receipt_s3_path: "receipts/456_private.pdf"})
        |> Repo.update!()
      end

      assert {:error, :unauthorized} =
               ExpenseReports.can_access_file?(
                 other,
                 "receipts/456_private.pdf"
               )
    end

    test "returns {:error, :unauthorized} when another user tries to access owner's income proof" do
      owner = user_fixture()
      other = user_fixture()
      proof_path = "proofs/777_private_income.pdf"

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "income_items" => [
              %{
                "date" => "2024-01-15",
                "description" => "Side income",
                "amount" => "25.00",
                "proof_s3_path" => proof_path
              }
            ]
          },
          owner
        )

      report = Repo.preload(report, :income_items)
      item = hd(report.income_items)

      if is_nil(item.proof_s3_path) do
        item
        |> Ecto.Changeset.change(%{proof_s3_path: proof_path})
        |> Repo.update!()
      end

      assert {:error, :unauthorized} =
               ExpenseReports.can_access_file?(other, proof_path)
    end

    test "returns {:ok, report} when admin accesses another user's receipt" do
      owner = user_fixture()
      admin = user_fixture(%{role: :admin})

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => "receipts/789_admin_test.pdf"
              }
            ]
          },
          owner
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{
          receipt_s3_path: "receipts/789_admin_test.pdf"
        })
        |> Repo.update!()
      end

      assert {:ok, _} =
               ExpenseReports.can_access_file?(
                 admin,
                 "receipts/789_admin_test.pdf"
               )
    end

    test "returns {:ok, nil} for recently uploaded file (within 24 hours)", %{
      user: user
    } do
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      path = "receipts/#{user.id}/#{ts}_preview.pdf"
      assert {:ok, nil} = ExpenseReports.can_access_file?(user, path)
    end

    test "returns {:ok, nil} for recently uploaded income proof under proofs/ path",
         %{
           user: user
         } do
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      path = "proofs/#{user.id}/#{ts}_income_preview.pdf"
      assert {:ok, nil} = ExpenseReports.can_access_file?(user, path)
    end

    test "rejects other user's recent user-scoped unsaved path (IDOR fix)", %{
      user: user
    } do
      other = user_fixture()
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      path = "receipts/#{other.id}/#{ts}_leaked.pdf"
      assert {:error, :not_found} = ExpenseReports.can_access_file?(user, path)
    end

    test "admin may access another user's recent unsaved scoped path" do
      owner = user_fixture()
      admin = user_fixture(%{role: :admin})
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      path = "receipts/#{owner.id}/#{ts}_admin_preview.pdf"
      assert {:ok, nil} = ExpenseReports.can_access_file?(admin, path)
    end

    test "rejects legacy flat receipt key for unsaved preview (no user segment)" do
      user = user_fixture()
      ts = DateTime.to_unix(DateTime.utc_now(), :second)
      path = "receipts/#{ts}_old_format.pdf"
      assert {:error, :not_found} = ExpenseReports.can_access_file?(user, path)
    end

    test "returns {:error, :not_found} for path with old timestamp" do
      user = user_fixture()

      old_ts =
        DateTime.to_unix(DateTime.add(DateTime.utc_now(), -25, :hour), :second)

      path = "receipts/#{old_ts}_old.pdf"
      assert {:error, :not_found} = ExpenseReports.can_access_file?(user, path)
    end

    test "returns {:error, :not_found} for path not in any report and not recent" do
      user = user_fixture()

      assert {:error, :not_found} =
               ExpenseReports.can_access_file?(user, "receipts/nonexistent.pdf")
    end

    test "returns {:error, :not_found} when first argument is not a user" do
      assert {:error, :not_found} =
               ExpenseReports.can_access_file?(nil, "receipts/123_file.pdf")
    end

    test "returns {:error, :not_found} when first argument is not a User struct" do
      assert {:error, :not_found} =
               ExpenseReports.can_access_file?(
                 "not-a-user",
                 "receipts/123_file.pdf"
               )
    end

    test "returns {:error, :not_found} when s3_path is not binary" do
      user = user_fixture()

      assert {:error, :not_found} = ExpenseReports.can_access_file?(user, nil)

      assert {:error, :not_found} =
               ExpenseReports.can_access_file?(user, :not_binary)
    end

    test "returns {:ok, report} when admin accesses another user's income proof" do
      owner = user_fixture()
      admin = user_fixture(%{role: :admin})
      proof_path = "proofs/888_admin_income_proof.pdf"

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Income proof admin",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "income_items" => [
              %{
                "date" => "2024-01-15",
                "description" => "Side income",
                "amount" => "30.00",
                "proof_s3_path" => proof_path
              }
            ]
          },
          owner
        )

      report = Repo.preload(report, :income_items)
      item = hd(report.income_items)

      if is_nil(item.proof_s3_path) do
        item
        |> Ecto.Changeset.change(%{proof_s3_path: proof_path})
        |> Repo.update!()
      end

      assert {:ok, fetched} = ExpenseReports.can_access_file?(admin, proof_path)
      assert fetched.id == report.id
    end

    test "normalizes path with bucket prefix" do
      owner = user_fixture()

      bucket =
        Application.get_env(:ysc, :expense_reports_s3_bucket, "expense-reports")

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => "receipts/normalized.pdf"
              }
            ]
          },
          owner
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{receipt_s3_path: "receipts/normalized.pdf"})
        |> Repo.update!()
      end

      # Path with bucket prefix should be normalized and match
      assert {:ok, _} =
               ExpenseReports.can_access_file?(
                 owner,
                 "#{bucket}/receipts/normalized.pdf"
               )
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

    test "create_expense_report with draft does not enqueue QuickBooks sync job",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} =
                 ExpenseReports.create_expense_report(
                   %{
                     "user_id" => user.id,
                     "status" => "draft",
                     "purpose" => "Draft no QB",
                     "reimbursement_method" => "bank_transfer",
                     "bank_account_id" => bank_account.id
                   },
                   user
                 )

        refute_enqueued(
          worker: YscWeb.Workers.QuickbooksSyncExpenseReportWorker
        )
      end)
    end

    test "create_expense_report returns error when purpose is missing", %{
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      attrs = %{
        "status" => "draft",
        "reimbursement_method" => "bank_transfer",
        "bank_account_id" => bank_account.id
      }

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.create_expense_report(attrs, user)

      assert cs.errors[:purpose]
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

    test "update_expense_report returns error for invalid status", %{user: user} do
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
            "purpose" => "Status validation",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report = Ysc.Repo.preload(report, :expense_items)

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.update_expense_report(report, %{status: "bogus"})

      assert cs.errors[:status]
    end

    test "update_expense_report can set status to rejected", %{user: user} do
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
            "purpose" => "Reject workflow",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report = Repo.preload(report, [:expense_items, :income_items])

      assert {:ok, updated} =
               ExpenseReports.update_expense_report(report, %{
                 status: "rejected"
               })

      assert updated.status == "rejected"
    end

    test "create_expense_report returns error when expense item is missing vendor",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.create_expense_report(
                 %{
                   "user_id" => user.id,
                   "status" => "draft",
                   "purpose" => "Missing vendor",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => bank_account.id,
                   "expense_items" => [
                     %{
                       "date" => "2024-01-15",
                       "description" => "D",
                       "amount" => "10.00"
                     }
                   ]
                 },
                 user
               )

      refute cs.valid?
    end

    test "submit_expense_report returns error when certification was not accepted",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Certification test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "certification_accepted" => false
          },
          user
        )

      report = Repo.preload(report, :expense_items)

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.submit_expense_report(report)

      assert Keyword.has_key?(cs.errors, :certification_accepted)
    end

    test "submit_expense_report updates status to submitted and enqueues QuickBooks sync",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Submit test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "certification_accepted" => true,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => "receipts/submit_receipt.pdf"
              }
            ]
          },
          user
        )

      report = Repo.preload(report, :expense_items)
      item = hd(report.expense_items)

      if is_nil(item.receipt_s3_path) do
        item
        |> Ecto.Changeset.change(%{
          receipt_s3_path: "receipts/submit_receipt.pdf"
        })
        |> Repo.update!()
      end

      # Set certification_accepted so submission is allowed
      report =
        report
        |> Ecto.Changeset.change(%{certification_accepted: true})
        |> Repo.update!()
        |> Repo.preload(:expense_items)

      # Use manual mode so QuickBooks sync job is enqueued but not run (avoids needing QB mocks)
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, updated} = ExpenseReports.submit_expense_report(report)
        assert updated.status == "submitted"
        assert updated.quickbooks_sync_status == "pending"

        assert_enqueued(
          worker: YscWeb.Workers.QuickbooksSyncExpenseReportWorker,
          args: %{"expense_report_id" => report.id}
        )
      end)
    end

    # Email notifications are sent when creating a report with status "submitted", not on submit_expense_report
    test "creating expense report with status submitted enqueues confirmation email to submitter",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, report} =
          ExpenseReports.create_expense_report(
            %{
              "user_id" => user.id,
              "status" => "submitted",
              "purpose" => "Email test",
              "reimbursement_method" => "bank_transfer",
              "bank_account_id" => bank_account.id,
              "certification_accepted" => true,
              "expense_items" => [
                %{
                  "date" => "2024-01-15",
                  "vendor" => "V",
                  "description" => "D",
                  "amount" => "10.00",
                  "receipt_s3_path" => "receipts/email_receipt.pdf"
                }
              ]
            },
            user
          )

        assert report.status == "submitted"

        assert_enqueued(
          worker: YscWeb.Workers.QuickbooksSyncExpenseReportWorker,
          args: %{"expense_report_id" => report.id}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "expense_report_confirmation",
            "recipient" => user.email,
            "idempotency_key" => "expense_report_confirmation_#{report.id}"
          }
        )
      end)
    end

    test "creating expense report with status submitted does not enqueue treasurer notification when no treasurer exists",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, report} =
          ExpenseReports.create_expense_report(
            %{
              "user_id" => user.id,
              "status" => "submitted",
              "purpose" => "No treasurer in org",
              "reimbursement_method" => "bank_transfer",
              "bank_account_id" => bank_account.id,
              "certification_accepted" => true,
              "expense_items" => [
                %{
                  "date" => "2024-01-15",
                  "vendor" => "V",
                  "description" => "D",
                  "amount" => "10.00",
                  "receipt_s3_path" => "receipts/no_treasurer_receipt.pdf"
                }
              ]
            },
            user
          )

        assert report.status == "submitted"

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "expense_report_confirmation",
            "recipient" => user.email,
            "idempotency_key" => "expense_report_confirmation_#{report.id}"
          }
        )

        refute Enum.any?(
                 all_enqueued(worker: YscWeb.Workers.EmailNotifier),
                 &(get_in(&1.args, ["template"]) ==
                     "expense_report_treasurer_notification")
               )
      end)
    end

    test "creating expense report with status submitted enqueues treasurer notification when treasurer exists",
         %{
           user: user
         } do
      _treasurer = user_fixture(%{board_position: :treasurer, state: :active})

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, report} =
          ExpenseReports.create_expense_report(
            %{
              "user_id" => user.id,
              "status" => "submitted",
              "purpose" => "Treasurer email test",
              "reimbursement_method" => "bank_transfer",
              "bank_account_id" => bank_account.id,
              "certification_accepted" => true,
              "expense_items" => [
                %{
                  "date" => "2024-01-15",
                  "vendor" => "V",
                  "description" => "D",
                  "amount" => "10.00",
                  "receipt_s3_path" => "receipts/treasurer_receipt.pdf"
                }
              ]
            },
            user
          )

        assert report.status == "submitted"

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "expense_report_confirmation"}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "expense_report_treasurer_notification",
            "idempotency_key" =>
              "expense_report_treasurer_notification_#{report.id}"
          }
        )
      end)
    end

    test "create with status submitted requires all expense items to have receipts",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      # Explicitly pass status "submitted" with an item that has no receipt
      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "submitted",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00"
                # no receipt_s3_path
              }
            ]
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :expense_items)

      assert Enum.any?(
               List.wrap(errors.expense_items),
               &String.contains?(&1, "receipt")
             )
    end

    test "create with status submitted rejects empty receipt_s3_path on expense item",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "submitted",
            "purpose" => "Empty receipt path",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "certification_accepted" => true,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => ""
              }
            ]
          },
          user
        )

      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :expense_items)
    end

    test "mark_expense_report_as_paid updates status to paid", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
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

      report = Repo.preload(report, :expense_items)
      assert {:ok, updated} = ExpenseReports.mark_expense_report_as_paid(report)
      assert updated.status == "paid"
    end

    test "get_expense_report! returns report for owner", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
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

      found = ExpenseReports.get_expense_report!(report.id, user)
      assert found.id == report.id
      assert found.user_id == user.id
      assert found.bank_account_id == bank_account.id
      assert %BankAccount{} = found.bank_account
      assert found.bank_account.id == bank_account.id
    end

    test "get_expense_report!/2 raises when another user requests the report" do
      owner = user_fixture()
      other = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          owner
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => owner.id,
            "status" => "draft",
            "purpose" => "Private",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          owner
        )

      assert_raise Ecto.NoResultsError, fn ->
        ExpenseReports.get_expense_report!(report.id, other)
      end
    end

    test "list_expense_reports returns reports for user", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, _} =
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

      reports = ExpenseReports.list_expense_reports(user)
      refute reports == []
      assert Enum.any?(reports, &(&1.user_id == user.id))
    end

    test "delete_expense_report removes report", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
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

      assert {:ok, _} = ExpenseReports.delete_expense_report(report)

      assert_raise Ecto.NoResultsError, fn ->
        ExpenseReports.get_expense_report!(report.id, user)
      end
    end
  end

  describe "calculate_totals/1" do
    test "returns zeros for report with no expense or income items", %{
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      totals = ExpenseReports.calculate_totals(report)
      assert Money.equal?(totals.expense_total, Money.new(0, :USD))
      assert Money.equal?(totals.income_total, Money.new(0, :USD))
      assert Money.equal?(totals.net_total, Money.new(0, :USD))
    end

    test "sums expense items only", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V1",
                "description" => "D1",
                "amount" => "10.00"
              },
              %{
                "date" => "2024-01-16",
                "vendor" => "V2",
                "description" => "D2",
                "amount" => "25.50"
              }
            ]
          },
          user
        )

      totals = ExpenseReports.calculate_totals(report)
      assert Money.equal?(totals.expense_total, Money.new(:USD, "35.50"))
      assert Money.equal?(totals.income_total, Money.new(0, :USD))
      assert Money.equal?(totals.net_total, Money.new(:USD, "35.50"))
    end

    test "sums income items only", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "income_items" => [
              %{
                "date" => "2024-01-15",
                "description" => "Income 1",
                "amount" => "50.00"
              },
              %{
                "date" => "2024-01-16",
                "description" => "Income 2",
                "amount" => "12.25"
              }
            ]
          },
          user
        )

      totals = ExpenseReports.calculate_totals(report)
      assert Money.equal?(totals.expense_total, Money.new(0, :USD))
      assert Money.equal?(totals.income_total, Money.new(:USD, "62.25"))
      assert Money.equal?(totals.net_total, Money.new(:USD, "-62.25"))
    end

    test "computes net_total as expense_total minus income_total", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "100.00"
              }
            ],
            "income_items" => [
              %{
                "date" => "2024-01-10",
                "description" => "Advance",
                "amount" => "40.00"
              }
            ]
          },
          user
        )

      totals = ExpenseReports.calculate_totals(report)
      assert Money.equal?(totals.expense_total, Money.new(:USD, "100.00"))
      assert Money.equal?(totals.income_total, Money.new(:USD, "40.00"))
      assert Money.equal?(totals.net_total, Money.new(:USD, "60.00"))
    end
  end

  describe "reimbursement validation" do
    test "bank_transfer without bank_account_id when user has no bank accounts adds error",
         %{
           user: user
         } do
      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer"
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :reimbursement_method)

      assert Enum.any?(
               List.wrap(errors.reimbursement_method),
               &String.contains?(&1, "bank account")
             )
    end

    test "bank_transfer without bank_account_id when user has bank accounts adds bank_account_id error",
         %{
           user: user
         } do
      {:ok, _bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "bank_transfer"
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :bank_account_id)

      assert Enum.any?(
               List.wrap(errors.bank_account_id),
               &String.contains?(&1, "choose")
             )
    end

    test "check without address_id when user has no billing address adds error",
         %{user: user} do
      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "check"
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :reimbursement_method)

      assert Enum.any?(
               List.wrap(errors.reimbursement_method),
               &String.contains?(&1, "billing address")
             )
    end

    test "check without address_id when user has billing address auto-sets address_id",
         %{
           user: user
         } do
      {:ok, _user} =
        Accounts.update_billing_address(user, %{
          "address" => "123 Main St",
          "city" => "Oakland",
          "region" => "CA",
          "postal_code" => "94601",
          "country" => "US"
        })

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "check"
          },
          user
        )

      assert report.address_id != nil
    end
  end

  describe "get_decrypted_bank_account/2 and get_decrypted_bank_account!/2" do
    test "returns decrypted routing and account numbers for owner", %{
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      decrypted =
        ExpenseReports.get_decrypted_bank_account(bank_account.id, user)

      assert decrypted.routing_number == "021000021"
      assert decrypted.account_number == "1234567890"

      decrypted! =
        ExpenseReports.get_decrypted_bank_account!(bank_account.id, user)

      assert decrypted!.routing_number == "021000021"
    end

    test "get_decrypted_bank_account/2 returns nil when id does not exist", %{
      user: user
    } do
      assert ExpenseReports.get_decrypted_bank_account(
               Ecto.ULID.generate(),
               user
             ) == nil
    end

    test "get_decrypted_bank_account!/2 raises when id does not exist", %{
      user: user
    } do
      assert_raise Ecto.NoResultsError, fn ->
        ExpenseReports.get_decrypted_bank_account!(Ecto.ULID.generate(), user)
      end
    end
  end

  describe "coverage — misc context functions" do
    test "update_expense_report returns error for empty purpose on draft", %{
      user: user
    } do
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
            "status" => "draft",
            "purpose" => "Original purpose",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report = Repo.preload(report, [:expense_items, :income_items])

      assert {:error, changeset} =
               ExpenseReports.update_expense_report(report, %{"purpose" => ""})

      refute changeset.valid?
    end

    test "delete_expense_report removes draft report", %{user: user} do
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
            "status" => "draft",
            "purpose" => "To delete",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      assert {:ok, _} = ExpenseReports.delete_expense_report(report)

      assert_raise Ecto.NoResultsError, fn ->
        ExpenseReports.get_expense_report!(report.id, user)
      end
    end

    test "list_expense_reports/1 returns single report for user", %{user: user} do
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
            "status" => "draft",
            "purpose" => "Single list test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      assert [%{id: id}] = ExpenseReports.list_expense_reports(user)
      assert id == report.id
    end

    test "normalize_s3_path via can_access_file? strips bucket prefix in path",
         %{
           user: user
         } do
      path = "receipts/#{System.unique_integer([:positive])}_doc.pdf"

      assert {:error, :not_found} =
               ExpenseReports.can_access_file?(
                 user,
                 "ysc-expense-reports/#{path}"
               )
    end

    test "receipt_url/1 encodes path for controller route" do
      path = "receipts/abc/file name.pdf"
      url = ExpenseReports.receipt_url(path)
      assert url =~ "/expensereport/files/"
      encoded = url |> String.split("/") |> List.last()
      assert Base.url_decode64(encoded, padding: false) == {:ok, path}
    end
  end

  describe "create_expense_report/2 — submitted: Swoosh email delivery" do
    import Swoosh.TestAssertions

    test "delivers confirmation and treasurer notification to Swoosh test adapter",
         %{
           user: user
         } do
      _treasurer =
        user_fixture(%{
          board_position: :treasurer,
          state: :active,
          phone_number: unique_user_phone()
        })

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, report} =
                 ExpenseReports.create_expense_report(
                   %{
                     "user_id" => user.id,
                     "status" => "submitted",
                     "purpose" => "Swoosh delivery via perform_job",
                     "reimbursement_method" => "bank_transfer",
                     "bank_account_id" => bank_account.id,
                     "certification_accepted" => true,
                     "expense_items" => [
                       %{
                         "date" => "2024-01-15",
                         "vendor" => "Vendor Co",
                         "description" => "Item",
                         "amount" => "10.00",
                         "receipt_s3_path" => "receipts/swoosh_perform_job.pdf"
                       }
                     ]
                   },
                   user
                 )

        assert report.status == "submitted"
      end)

      expense_templates = [
        "expense_report_confirmation",
        "expense_report_treasurer_notification"
      ]

      email_jobs =
        all_enqueued(worker: EmailNotifier)
        |> Enum.filter(&(get_in(&1.args, ["template"]) in expense_templates))
        |> Enum.sort_by(fn j ->
          case get_in(j.args, ["template"]) do
            "expense_report_confirmation" -> 0
            "expense_report_treasurer_notification" -> 1
          end
        end)

      Enum.each(email_jobs, fn job ->
        assert :ok = perform_job(EmailNotifier, job.args)
      end)

      assert_email_sent(subject: "Expense Report Submitted - Confirmation")

      assert_email_sent(
        subject: "New Expense Report Submitted - Action Required"
      )
    end
  end

  describe "submit_expense_report/1 vs expense report email jobs" do
    test "submit_expense_report enqueues QuickBooks sync but does not schedule expense report emails",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Submit without create-time emails",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "certification_accepted" => true,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "10.00",
                "receipt_s3_path" => "receipts/submit_flow_no_email.pdf"
              }
            ]
          },
          user
        )

      report =
        report
        |> Repo.preload(:expense_items)
        |> Ecto.Changeset.change(%{certification_accepted: true})
        |> Repo.update!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, submitted} = ExpenseReports.submit_expense_report(report)
        assert submitted.status == "submitted"

        assert_enqueued(
          worker: YscWeb.Workers.QuickbooksSyncExpenseReportWorker,
          args: %{"expense_report_id" => report.id}
        )

        email_jobs = all_enqueued(worker: YscWeb.Workers.EmailNotifier)

        refute Enum.any?(
                 email_jobs,
                 &(get_in(&1.args, ["template"]) ==
                     "expense_report_confirmation")
               )

        refute Enum.any?(
                 email_jobs,
                 &(get_in(&1.args, ["template"]) ==
                     "expense_report_treasurer_notification")
               )
      end)
    end
  end

  describe "upload_receipt_to_s3/2 — ExAws upload operation" do
    test "uses expense_reports_s3_request when ExAws branch is active (no upload mock)" do
      prev_upload = Application.get_env(:ysc, :expense_reports_s3_upload)
      prev_request = Application.get_env(:ysc, :expense_reports_s3_request)

      on_exit(fn ->
        Application.put_env(:ysc, :expense_reports_s3_upload, prev_upload)
        Application.put_env(:ysc, :expense_reports_s3_request, prev_request)
      end)

      Application.put_env(:ysc, :expense_reports_s3_upload, nil)

      Application.put_env(:ysc, :expense_reports_s3_request, fn _op ->
        %{body: %{key: "from_test_expense_reports_s3_request"}}
      end)

      tmp_dir = System.tmp_dir!()

      path =
        Path.join(
          tmp_dir,
          "receipt_exaws_#{System.unique_integer([:positive])}.pdf"
        )

      File.write!(path, "content")

      try do
        key =
          ExpenseReports.upload_receipt_to_s3(path,
            user_id: Ecto.ULID.generate()
          )

        assert key == "from_test_expense_reports_s3_request"
      after
        File.rm(path)
      end
    end
  end

  describe "coverage — create_expense_report nested items and logging paths" do
    test "draft report with multiple expense items and receipt_s3_path values",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      assert {:ok, report} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "Multi-item draft with receipts",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => bank_account.id,
                   "expense_items" => [
                     %{
                       "date" => "2024-01-15",
                       "vendor" => "Vendor A",
                       "description" => "First",
                       "amount" => "10.00",
                       "receipt_s3_path" => "receipts/coverage_a.pdf"
                     },
                     %{
                       "date" => "2024-01-16",
                       "vendor" => "Vendor B",
                       "description" => "Second",
                       "amount" => "5.00",
                       "receipt_s3_path" => "receipts/coverage_b.pdf"
                     }
                   ]
                 },
                 user
               )

      assert report.status == "draft"
    end

    test "failed create iterates expense_items in changes (nested changeset logging)",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      assert {:error, %Ecto.Changeset{} = cs} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "Invalid nested item",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => bank_account.id,
                   "expense_items" => [
                     %{
                       "date" => "2024-01-15",
                       "vendor" => "Vendor A",
                       "description" => "Ok",
                       "amount" => "10.00",
                       "receipt_s3_path" => "receipts/ok.pdf"
                     },
                     %{
                       "date" => "2024-01-16",
                       "description" => "Missing vendor",
                       "amount" => "5.00",
                       "receipt_s3_path" => "receipts/bad.pdf"
                     }
                   ]
                 },
                 user
               )

      refute cs.valid?
      assert Map.has_key?(cs.changes, :expense_items)
    end
  end
end
