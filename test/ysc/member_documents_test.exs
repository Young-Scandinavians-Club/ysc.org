defmodule Ysc.MemberDocumentsTest do
  use ExUnit.Case, async: true

  alias Ysc.MemberDocuments

  describe "validate_annual_meeting_relative_path/1" do
    test "accepts year/filename paths" do
      assert :ok =
               MemberDocuments.validate_annual_meeting_relative_path(
                 "2026/YSC_ANNUAL_REPORT_FY_2025.pdf"
               )
    end

    test "rejects path traversal" do
      assert :error =
               MemberDocuments.validate_annual_meeting_relative_path(
                 "2026/../../etc/passwd"
               )
    end

    test "rejects paths without a year directory" do
      assert :error =
               MemberDocuments.validate_annual_meeting_relative_path(
                 "YSC_ANNUAL_REPORT_FY_2025.pdf"
               )
    end
  end

  describe "annual_meeting_path/1" do
    test "returns path for an existing file" do
      relative = "2026/YSC_ANNUAL_REPORT_FY_2025.pdf"

      assert {:ok, absolute} = MemberDocuments.annual_meeting_path(relative)
      assert File.regular?(absolute)
      assert String.ends_with?(absolute, relative)
    end

    test "returns error for missing file" do
      assert :error =
               MemberDocuments.annual_meeting_path("2026/does-not-exist.pdf")
    end
  end
end
