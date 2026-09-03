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

    test "batch-loads bank_account for multiple reports in one query", %{
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

      for i <- 1..3 do
        {:ok, _} =
          ExpenseReports.create_expense_report(
            %{
              "status" => "draft",
              "purpose" => "Batch list #{i}",
              "reimbursement_method" => "bank_transfer",
              "bank_account_id" => bank_account.id
            },
            user
          )
      end

      reports = ExpenseReports.list_expense_reports(user)

      assert length(reports) >= 3

      assert Enum.all?(reports, fn report ->
               if report.bank_account_id do
                 report.bank_account.id == report.bank_account_id
               else
                 report.bank_account == nil
               end
             end)
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

    test "uses preloaded items without extra SUM queries when associations are loaded",
         %{
           user: user
         } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, _report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Preloaded totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "30.00"
              }
            ],
            "income_items" => [
              %{
                "date" => "2024-01-10",
                "description" => "Advance",
                "amount" => "10.00"
              }
            ]
          },
          user
        )

      [preloaded_report] = ExpenseReports.list_expense_reports(user)

      totals_from_preloaded = ExpenseReports.calculate_totals(preloaded_report)

      assert Money.equal?(
               totals_from_preloaded.expense_total,
               Money.new(:USD, "30.00")
             )

      assert Money.equal?(
               totals_from_preloaded.income_total,
               Money.new(:USD, "10.00")
             )

      assert Money.equal?(
               totals_from_preloaded.net_total,
               Money.new(:USD, "20.00")
             )
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

    test "reimbursement_method outside bank_transfer/check leaves the changeset untouched by the custom validators",
         %{user: user} do
      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test"
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)

      # Only the base schema's required-field error fires; none of the
      # bank_transfer/check-specific validators add anything since
      # reimbursement_method is neither "bank_transfer" nor "check".
      assert errors.reimbursement_method == ["can't be blank"]
    end

    test "a non-blank reimbursement_method outside bank_transfer/check fails schema inclusion but not the custom validators",
         %{user: user} do
      {:error, changeset} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "status" => "draft",
            "purpose" => "Test",
            "reimbursement_method" => "cash"
          },
          user
        )

      refute changeset.valid?
      errors = errors_on(changeset)

      # validate_inclusion/3 in ExpenseReport.submission_changeset/3 rejects
      # "cash" outright; ExpenseReports.validate_reimbursement_setup/2's
      # `_ -> changeset` fallback (neither "bank_transfer" nor "check") never
      # runs the bank-account/address validators, so those keys stay absent.
      assert errors.reimbursement_method == ["is invalid"]
      refute Map.has_key?(errors, :bank_account_id)
      refute Map.has_key?(errors, :address_id)
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
    test "update_expense_report rejects invalid status values", %{user: user} do
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

      assert {:error, changeset} =
               ExpenseReports.update_expense_report(report, %{
                 "status" => "not-a-status"
               })

      refute changeset.valid?

      assert {:ok, updated} =
               ExpenseReports.update_expense_report(report, %{
                 "status" => "approved"
               })

      assert updated.status == "approved"
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

  describe "create_expense_report/2 — mileage items" do
    test "submits successfully with a mileage-only item and no receipt", %{
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      report =
        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, report} =
                   ExpenseReports.create_expense_report(
                     %{
                       "user_id" => user.id,
                       "status" => "submitted",
                       "purpose" => "Board meeting mileage",
                       "reimbursement_method" => "bank_transfer",
                       "bank_account_id" => bank_account.id,
                       "certification_accepted" => true,
                       "expense_items" => [
                         %{
                           "date" => "2024-01-15",
                           "expense_type" => "mileage",
                           "description" => "Board meeting",
                           "mileage_from_to" => "Home to YSC Cabin",
                           "miles_driven" => "20"
                         }
                       ]
                     },
                     user
                   )

          report
        end)

      assert report.status == "submitted"
      [item] = report.expense_items
      assert item.vendor == "Mileage"
      assert item.amount == Money.new(:USD, "6.00")
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

  describe "security: submission mass assignment and reimbursement IDOR" do
    test "rejects another member's bank_account_id on bank_transfer submission" do
      victim = user_fixture()
      attacker = user_fixture()

      {:ok, victim_bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          victim
        )

      {:ok, attacker_bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "9876543210"},
          attacker
        )

      assert {:error, %Ecto.Changeset{} = changeset} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "Redirect reimbursement",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => victim_bank_account.id
                 },
                 attacker
               )

      assert "is invalid" in errors_on(changeset).bank_account_id

      assert {:ok, report} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "Legitimate reimbursement",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => attacker_bank_account.id
                 },
                 attacker
               )

      assert report.bank_account_id == attacker_bank_account.id
    end

    test "rejects another member's address_id on check reimbursement" do
      victim = user_fixture()
      attacker = user_fixture()

      {:ok, victim} =
        Accounts.update_billing_address(victim, %{
          "address" => "1 Victim Lane",
          "city" => "Oakland",
          "region" => "CA",
          "postal_code" => "94601",
          "country" => "US"
        })

      victim = Repo.preload(victim, :billing_address)

      {:ok, attacker} =
        Accounts.update_billing_address(attacker, %{
          "address" => "2 Attacker Road",
          "city" => "Oakland",
          "region" => "CA",
          "postal_code" => "94602",
          "country" => "US"
        })

      assert {:error, %Ecto.Changeset{} = changeset} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "Redirect check",
                   "reimbursement_method" => "check",
                   "address_id" => victim.billing_address.id
                 },
                 attacker
               )

      assert "is invalid" in errors_on(changeset).address_id
    end

    test "ignores forged quickbooks_bill_id and privileged status on create" do
      user = user_fixture()

      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      assert {:error, %Ecto.Changeset{} = status_changeset} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "approved",
                   "purpose" => "Status escalation attempt",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => bank_account.id
                 },
                 user
               )

      refute status_changeset.valid?

      assert {:ok, report} =
               ExpenseReports.create_expense_report(
                 %{
                   "status" => "draft",
                   "purpose" => "QB bypass attempt",
                   "reimbursement_method" => "bank_transfer",
                   "bank_account_id" => bank_account.id,
                   "quickbooks_bill_id" => "attacker-controlled-bill",
                   "quickbooks_sync_status" => "synced"
                 },
                 user
               )

      assert is_nil(report.quickbooks_bill_id)
      assert report.quickbooks_sync_status == "pending"
      assert report.status == "draft"
    end
  end

  describe "list_expense_reports_for_event/1" do
    test "lists reports for the given event, newest first, and excludes other events",
         %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      event = event_fixture()
      other_event = event_fixture()

      {:ok, report1} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "First",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      {:ok, report2} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Second",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      {:ok, _other_event_report} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => other_event.id,
            "status" => "draft",
            "purpose" => "Other event",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      results = ExpenseReports.list_expense_reports_for_event(event.id)

      assert MapSet.new(Enum.map(results, & &1.id)) ==
               MapSet.new([report1.id, report2.id])
    end

    test "returns empty list for an event with no expense reports" do
      assert ExpenseReports.list_expense_reports_for_event(Ecto.ULID.generate()) ==
               []
    end
  end

  describe "total_for_event/2 and totals_for_event/2" do
    test "only counts approved/paid reports by default, netting income against expenses",
         %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      event = event_fixture()

      {:ok, paid} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Venue",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "Venue Co",
                "description" => "Rental",
                "amount" => "1200.00"
              }
            ]
          },
          user
        )

      {:ok, _paid} =
        ExpenseReports.update_expense_report(paid, %{status: "paid"})

      {:ok, approved} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Catering",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-16",
                "vendor" => "Caterer",
                "description" => "Food",
                "amount" => "300.00"
              }
            ],
            "income_items" => [
              %{
                "date" => "2024-01-16",
                "description" => "Cash collected",
                "amount" => "50.00"
              }
            ]
          },
          user
        )

      {:ok, _approved} =
        ExpenseReports.update_expense_report(approved, %{status: "approved"})

      {:ok, _still_draft} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Pending review",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-17",
                "vendor" => "Vendor",
                "description" => "Should not count",
                "amount" => "9999.00"
              }
            ]
          },
          user
        )

      totals = ExpenseReports.totals_for_event(event.id)

      assert Money.equal?(totals.expense_total, Money.new(1500, :USD))
      assert Money.equal?(totals.income_total, Money.new(50, :USD))
      assert Money.equal?(totals.net_total, Money.new(1450, :USD))

      assert Money.equal?(
               ExpenseReports.total_for_event(event.id),
               Money.new(1450, :USD)
             )
    end

    test "accepts a custom statuses list", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{
            "routing_number" => "021000021",
            "account_number" => "1234567890"
          },
          user
        )

      event = event_fixture()

      {:ok, _draft} =
        ExpenseReports.create_expense_report(
          %{
            "user_id" => user.id,
            "event_id" => event.id,
            "status" => "draft",
            "purpose" => "Draft item",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "Vendor",
                "description" => "Draft",
                "amount" => "42.00"
              }
            ]
          },
          user
        )

      assert Money.equal?(
               ExpenseReports.total_for_event(event.id, ["draft"]),
               Money.new(42, :USD)
             )

      assert Money.equal?(
               ExpenseReports.total_for_event(event.id),
               Money.new(0, :USD)
             )
    end

    test "returns zero totals for an event with no expense reports" do
      totals = ExpenseReports.totals_for_event(Ecto.ULID.generate())
      assert Money.equal?(totals.expense_total, Money.new(0, :USD))
      assert Money.equal?(totals.income_total, Money.new(0, :USD))
      assert Money.equal?(totals.net_total, Money.new(0, :USD))
    end
  end

  describe "get_expense_report_by_quickbooks_bill_id/2" do
    test "returns {:ok, report} when a report with the bill id exists", %{
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
            "status" => "draft",
            "purpose" => "QB bill lookup",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report =
        report
        |> Ecto.Changeset.change(%{quickbooks_bill_id: "bill-42"})
        |> Repo.update!()

      assert {:ok, found} =
               ExpenseReports.get_expense_report_by_quickbooks_bill_id(
                 "bill-42"
               )

      assert found.id == report.id
    end

    test "returns {:error, :not_found} when no report has the bill id" do
      assert {:error, :not_found} =
               ExpenseReports.get_expense_report_by_quickbooks_bill_id(
                 "nonexistent-bill"
               )
    end

    test "supports lock: true option inside a transaction", %{user: user} do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, report} =
        ExpenseReports.create_expense_report(
          %{
            "status" => "draft",
            "purpose" => "QB bill lookup lock",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report =
        report
        |> Ecto.Changeset.change(%{quickbooks_bill_id: "bill-locked"})
        |> Repo.update!()

      {:ok, result} =
        Repo.transaction(fn ->
          ExpenseReports.get_expense_report_by_quickbooks_bill_id(
            "bill-locked",
            lock: true
          )
        end)

      assert {:ok, found} = result
      assert found.id == report.id
    end
  end

  describe "mark_expense_report_as_rejected_due_to_quickbooks_deletion/2" do
    test "sets status to rejected and stamps a system-generated note", %{
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
            "status" => "draft",
            "purpose" => "QB deletion rejection",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      report =
        report
        |> Ecto.Changeset.change(%{quickbooks_bill_id: "bill-deleted-1"})
        |> Repo.update!()

      assert {:ok, updated} =
               ExpenseReports.mark_expense_report_as_rejected_due_to_quickbooks_deletion(
                 report,
                 "bill-deleted-1"
               )

      assert updated.status == "rejected"
      assert updated.quickbooks_sync_error =~ "bill-deleted-1"
      assert updated.quickbooks_sync_error =~ "Automatically rejected"
    end
  end

  describe "calculate_totals/1 — non-preloaded (DB aggregate) path" do
    test "computes totals via SUM query when associations are not preloaded",
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
            "purpose" => "DB totals test",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id,
            "expense_items" => [
              %{
                "date" => "2024-01-15",
                "vendor" => "V",
                "description" => "D",
                "amount" => "75.00"
              }
            ],
            "income_items" => [
              %{
                "date" => "2024-01-16",
                "description" => "Income",
                "amount" => "15.00"
              }
            ]
          },
          user
        )

      # Fetch without preloading expense_items/income_items so
      # calculate_totals/1 goes through the DB-aggregate branch.
      not_preloaded = Repo.get!(Ysc.ExpenseReports.ExpenseReport, report.id)
      refute Ecto.assoc_loaded?(not_preloaded.expense_items)
      refute Ecto.assoc_loaded?(not_preloaded.income_items)

      totals = ExpenseReports.calculate_totals(not_preloaded)
      assert Money.equal?(totals.expense_total, Money.new(:USD, "75.00"))
      assert Money.equal?(totals.income_total, Money.new(:USD, "15.00"))
      assert Money.equal?(totals.net_total, Money.new(:USD, "60.00"))
    end

    test "returns zero totals from DB when report has no items", %{
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
            "purpose" => "DB totals empty",
            "reimbursement_method" => "bank_transfer",
            "bank_account_id" => bank_account.id
          },
          user
        )

      not_preloaded = Repo.get!(Ysc.ExpenseReports.ExpenseReport, report.id)
      totals = ExpenseReports.calculate_totals(not_preloaded)
      assert Money.equal?(totals.expense_total, Money.new(0, :USD))
      assert Money.equal?(totals.income_total, Money.new(0, :USD))
      assert Money.equal?(totals.net_total, Money.new(0, :USD))
    end
  end

  describe "upload_receipt_to_s3/2 — kind option" do
    test "uses proofs/ prefix when kind: :proof", %{user: user} do
      tmp_dir = System.tmp_dir!()

      path =
        Path.join(tmp_dir, "proof_#{System.unique_integer([:positive])}.pdf")

      File.write!(path, "content")

      try do
        key =
          ExpenseReports.upload_receipt_to_s3(path,
            user_id: user.id,
            kind: :proof
          )

        assert String.starts_with?(key, "proofs/#{user.id}/")
      after
        File.rm(path)
      end
    end

    test "falls back to receipts/ prefix for an unrecognized kind", %{
      user: user
    } do
      tmp_dir = System.tmp_dir!()

      path =
        Path.join(
          tmp_dir,
          "unknownkind_#{System.unique_integer([:positive])}.pdf"
        )

      File.write!(path, "content")

      try do
        key =
          ExpenseReports.upload_receipt_to_s3(path,
            user_id: user.id,
            kind: :something_else
          )

        assert String.starts_with?(key, "receipts/#{user.id}/")
      after
        File.rm(path)
      end
    end
  end

  describe "ci_query_explain_query/0" do
    test "builds a runnable Ecto query for CI query-plan diagnostics" do
      query = ExpenseReports.ci_query_explain_query()

      assert %Ecto.Query{} = query
      assert Repo.all(query) == []
    end
  end

  describe "drafts" do
    test "get_active_draft/1 returns nil when the user has none", %{user: user} do
      assert ExpenseReports.get_active_draft(user) == nil
    end

    test "save_draft/3 creates a draft, then updates the same row", %{
      user: user
    } do
      {:ok, draft} =
        ExpenseReports.save_draft(user, %{"purpose" => "Retreat supplies"})

      assert draft.status == "draft"
      assert draft.purpose == "Retreat supplies"
      assert ExpenseReports.get_active_draft(user).id == draft.id

      {:ok, updated} =
        ExpenseReports.save_draft(
          user,
          %{"purpose" => "Retreat supplies v2"},
          draft.id
        )

      assert updated.id == draft.id
      assert updated.purpose == "Retreat supplies v2"

      assert Repo.aggregate(
               from(er in Ysc.ExpenseReports.ExpenseReport,
                 where: er.user_id == ^user.id
               ),
               :count
             ) == 1
    end

    test "save_draft/3 persists a half-filled expense item", %{user: user} do
      {:ok, draft} =
        ExpenseReports.save_draft(user, %{
          "purpose" => "Partial",
          "expense_items" => %{
            "0" => %{"vendor" => "Costco", "amount" => "", "date" => ""}
          }
        })

      assert [item] = draft.expense_items
      assert item.vendor == "Costco"
      assert item.amount == nil
      assert item.date == nil
    end

    test "save_draft/3 replaces items rather than appending them", %{user: user} do
      {:ok, draft} =
        ExpenseReports.save_draft(user, %{
          "purpose" => "P",
          "expense_items" => %{
            "0" => %{"vendor" => "A"},
            "1" => %{"vendor" => "B"}
          }
        })

      {:ok, draft} =
        ExpenseReports.save_draft(
          user,
          %{
            "purpose" => "P",
            "expense_items" => %{"0" => %{"vendor" => "only"}}
          },
          draft.id
        )

      assert [%{vendor: "only"}] = draft.expense_items
    end

    test "submit_draft/3 creates a submitted report and removes the draft", %{
      user: user
    } do
      {:ok, bank_account} =
        ExpenseReports.create_bank_account(
          %{"routing_number" => "021000021", "account_number" => "1234567890"},
          user
        )

      {:ok, draft} =
        ExpenseReports.save_draft(user, %{
          "purpose" => "Conference travel",
          "reimbursement_method" => "bank_transfer",
          "bank_account_id" => bank_account.id
        })

      attrs = %{
        "purpose" => "Conference travel",
        "reimbursement_method" => "bank_transfer",
        "bank_account_id" => bank_account.id,
        "certification_accepted" => true,
        "status" => "submitted",
        "expense_items" => %{
          "0" => %{
            "date" => "2026-01-15",
            "vendor" => "Delta",
            "description" => "Flight",
            "amount" => "250.00",
            "receipt_s3_path" => "receipts/u/x.pdf"
          }
        }
      }

      {report, _} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, report} = ExpenseReports.submit_draft(draft.id, attrs, user)
          {report, nil}
        end)

      assert report.status == "submitted"
      assert ExpenseReports.get_active_draft(user) == nil
      assert Repo.get(Ysc.ExpenseReports.ExpenseReport, draft.id) == nil
    end

    test "discard_draft/2 deletes the draft and its items", %{user: user} do
      {:ok, draft} =
        ExpenseReports.save_draft(user, %{
          "purpose" => "Scratch",
          "expense_items" => %{"0" => %{"vendor" => "X"}}
        })

      assert {:ok, _} = ExpenseReports.discard_draft(draft.id, user)
      assert Repo.get(Ysc.ExpenseReports.ExpenseReport, draft.id) == nil

      assert Repo.aggregate(
               from(i in Ysc.ExpenseReports.ExpenseReportItem,
                 where: i.expense_report_id == ^draft.id
               ),
               :count
             ) == 0
    end

    test "discard_draft/2 will not touch another user's draft", %{user: user} do
      other = user_fixture()

      {:ok, draft} =
        ExpenseReports.save_draft(other, %{"purpose" => "Not yours"})

      assert ExpenseReports.discard_draft(draft.id, user) ==
               {:error, :not_found}

      assert Repo.get(Ysc.ExpenseReports.ExpenseReport, draft.id)
    end
  end
end
