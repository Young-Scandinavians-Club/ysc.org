defmodule YscWeb.AdminExportFilesTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias YscWeb.AdminExportFiles

  test "valid_filename? rejects path traversal attempts" do
    refute AdminExportFiles.valid_filename?("../secrets.csv")
    refute AdminExportFiles.valid_filename?("..%2F..%2Fetc%2Fpasswd")

    refute AdminExportFiles.valid_filename?(
             "ysc-user-export-2026-05-31-01ARZ3NDEKTSV4RRFFQ69G5FAV-../../../etc/passwd.csv"
           )
  end

  test "read/1 rejects filenames outside the export naming scheme" do
    assert {:error, :invalid} = AdminExportFiles.read("../../../etc/passwd")
  end

  test "read_for_user/2 rejects another admin's export file" do
    owner = user_fixture(%{role: :admin})
    other = user_fixture(%{role: :admin})

    filename =
      "ysc-user-export-2026-05-26-#{owner.id}-01ARZ3NDEKTSV4RRFFQ69G5FAV.csv"

    exports_root = AdminExportFiles.exports_root()
    File.mkdir_p!(exports_root)
    file_path = Path.join(exports_root, filename)
    File.write!(file_path, "id,email\n1,secret@example.com")
    on_exit(fn -> File.rm(file_path) end)

    assert {:error, :forbidden} =
             AdminExportFiles.read_for_user(filename, other)

    assert {:ok, "id,email\n1,secret@example.com", ^filename} =
             AdminExportFiles.read_for_user(filename, owner)
  end
end
