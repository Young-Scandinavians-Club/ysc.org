defmodule Ysc.ExpenseReports.QuickbooksSyncTest do
  use ExUnit.Case, async: false

  alias Ysc.ExpenseReports.QuickbooksSync
  alias Ysc.S3Config

  describe "download_from_s3_to_temp/1 (via test seam)" do
    test "cleans up the temp file when S3 returns a non-200 response" do
      bucket = S3Config.expense_reports_bucket_name()
      key = "nonexistent-#{Ecto.UUID.generate()}.pdf"

      # Make sure nothing is left over from a previous run.
      bucket |> ExAws.S3.delete_object(key) |> ExAws.request()

      assert {:error, :s3_download_failed} =
               QuickbooksSync.download_from_s3_to_temp_for_test(key)

      tmp_files =
        System.tmp_dir!()
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "qb_upload_"))

      assert tmp_files == []
    end
  end
end
