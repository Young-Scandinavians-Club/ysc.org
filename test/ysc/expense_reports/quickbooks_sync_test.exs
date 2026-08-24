defmodule Ysc.ExpenseReports.QuickbooksSyncTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReportItem
  alias Ysc.ExpenseReports.QuickbooksSync
  alias Ysc.Quickbooks.ClientMock
  alias Ysc.S3Config

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "download_from_s3_to_temp/1 (via test seam)" do
    test "cleans up the temp file when S3 returns a non-200 response" do
      bucket = S3Config.expense_reports_bucket_name()
      key = "nonexistent-#{Ecto.UUID.generate()}.pdf"

      # Make sure nothing is left over from a previous run.
      bucket |> ExAws.S3.delete_object(key) |> ExAws.request()

      assert {:error, :s3_download_failed} =
               QuickbooksSync.download_from_s3_to_temp_for_test(key)

      # Scoped to this test's own PID so it can't be tripped up by another
      # async test's in-flight download in the same shared tmp dir.
      prefix = "qb_upload_#{:erlang.phash2(self())}_"

      tmp_files =
        System.tmp_dir!()
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, prefix))

      assert tmp_files == []
    end
  end

  describe "sync_expense_report/1 mileage line descriptions" do
    setup do
      stub(ClientMock, :query_account_by_name, fn _name ->
        {:ok, "account_test"}
      end)

      %{user: user_fixture()}
    end

    test "mileage bills include route and miles instead of the generic vendor line",
         %{user: user} do
      report =
        user
        |> submitted_mileage_report!()
        |> Repo.preload([
          :expense_items,
          :income_items,
          :address,
          :bank_account,
          :event,
          user: :billing_address
        ])

      bill_id = "bill_mileage_#{report.id}"

      expect(ClientMock, :get_or_create_vendor, fn _name, _params ->
        {:ok, "vendor_mileage_test"}
      end)

      expect(ClientMock, :create_bill, fn params, opts ->
        send(self(), {:qb_create_bill, params, opts})
        {:ok, %{"Id" => bill_id}}
      end)

      assert {:ok, %{"Id" => ^bill_id}} =
               QuickbooksSync.sync_expense_report(report)

      assert_received {:qb_create_bill, params, opts}

      assert opts[:idempotency_key] == "expense_report_#{report.id}"
      assert params.vendor_ref == %{value: "vendor_mileage_test"}

      [line] = params.line

      assert line.description ==
               "Mileage (Home to YSC Cabin) - 20 mi - Board meeting"

      assert line.amount == 6.0
    end
  end

  defp submitted_mileage_report!(user) do
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
          "purpose" => "Board meeting mileage",
          "reimbursement_method" => "bank_transfer",
          "bank_account_id" => bank_account.id
        },
        user
      )

    %ExpenseReportItem{}
    |> ExpenseReportItem.changeset(%{
      expense_report_id: report.id,
      date: Date.utc_today(),
      expense_type: "mileage",
      description: "Board meeting",
      mileage_from_to: "Home to YSC Cabin",
      miles_driven: 20
    })
    |> Repo.insert!()

    report
    |> Ecto.Changeset.change(%{
      status: "submitted",
      certification_accepted: true
    })
    |> Repo.update!()
  end
end
