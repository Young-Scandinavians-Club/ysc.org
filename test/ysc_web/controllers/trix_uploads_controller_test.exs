defmodule YscWeb.TrixUploadsControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: :admin})
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  # --- Helpers ---

  defp minimal_jpeg do
    # Valid JPEG magic bytes (SOI + APP0 marker)
    <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>
  end

  defp minimal_png do
    # Valid PNG magic bytes
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  end

  defp minimal_pe_exe do
    # PE executable magic bytes (MZ header)
    <<0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00>>
  end

  defp write_tmp(content, filename) do
    path = "/tmp/trix_test_#{System.unique_integer([:positive])}_#{filename}"
    File.write!(path, content)
    on_exit(fn -> if File.exists?(path), do: File.rm(path) end)
    path
  end

  defp plain_text_upload(path, filename) do
    %Plug.Upload{path: path, filename: filename, content_type: "text/plain"}
  end

  describe "create/2 — no file" do
    test "returns 400 when no file param is provided", %{conn: conn} do
      conn = post(conn, ~p"/admin/trix-uploads", %{})
      assert json_response(conn, 400)["error"] =~ "No file"
    end
  end

  describe "create/2 — file size limit" do
    test "returns 413 when file exceeds 25 MB", %{conn: conn} do
      path = write_tmp(String.duplicate("x", 26 * 1024 * 1024), "big.pdf")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "big.pdf")
        })

      assert json_response(conn, 413)["error"] =~ "too large"
    end
  end

  describe "create/2 — dangerous file blocking" do
    test "returns 422 for a PE executable (.exe magic bytes)", %{conn: conn} do
      path = write_tmp(minimal_pe_exe(), "malware.exe")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "malware.exe")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a renamed PE executable (.pdf extension, EXE magic bytes)",
         %{
           conn: conn
         } do
      path = write_tmp(minimal_pe_exe(), "invoice.pdf")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "invoice.pdf")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a .bat script file", %{conn: conn} do
      path = write_tmp("@echo off\necho pwned", "run.bat")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "run.bat")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a .ps1 PowerShell script", %{conn: conn} do
      path = write_tmp("Write-Host 'pwned'", "exploit.ps1")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "exploit.ps1")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a .sh shell script", %{conn: conn} do
      path = write_tmp("#!/bin/bash\nrm -rf /", "payload.sh")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "payload.sh")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for double-extension attack (report.exe.pdf)", %{
      conn: conn
    } do
      path = write_tmp("harmless looking content", "report.exe.pdf")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "report.exe.pdf")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a macro-enabled Office file (.xlsm)", %{conn: conn} do
      path = write_tmp("fake xlsm content", "budget.xlsm")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "budget.xlsm")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end

    test "returns 422 for a .dll file", %{conn: conn} do
      path = write_tmp(minimal_pe_exe(), "evil.dll")

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "evil.dll")
        })

      assert json_response(conn, 422)["error"] =~ "not allowed"
    end
  end

  describe "FileValidator — image?/1" do
    alias YscWeb.Validators.FileValidator

    test "returns true for JPEG magic bytes" do
      path = write_tmp(minimal_jpeg(), "photo.jpg")
      assert FileValidator.image?(path) == true
    end

    test "returns true for PNG magic bytes" do
      path = write_tmp(minimal_png(), "image.png")
      assert FileValidator.image?(path) == true
    end

    test "returns false for PE executable magic bytes" do
      path = write_tmp(minimal_pe_exe(), "not_an_image.exe")
      assert FileValidator.image?(path) == false
    end

    test "returns false for plain text content" do
      path = write_tmp("hello world", "text.txt")
      assert FileValidator.image?(path) == false
    end
  end

  describe "FileValidator — validate_attachment/2" do
    alias YscWeb.Validators.FileValidator

    test "allows a plain-text file with safe name" do
      path = write_tmp("hello world", "notes.txt")
      assert {:ok, _mime} = FileValidator.validate_attachment(path, "notes.txt")
    end

    test "allows a PDF file (magic bytes unknown to FileType, safe extension)" do
      path = write_tmp("%PDF-1.4 fake content", "document.pdf")

      assert {:ok, _mime} =
               FileValidator.validate_attachment(path, "document.pdf")
    end

    test "blocks a PE executable by magic bytes regardless of extension" do
      path = write_tmp(minimal_pe_exe(), "totally_safe.pdf")

      assert {:error, _reason} =
               FileValidator.validate_attachment(path, "totally_safe.pdf")
    end

    test "blocks a .bat file even with plain text content" do
      path = write_tmp("@echo off", "run.bat")

      assert {:error, _reason} =
               FileValidator.validate_attachment(path, "run.bat")
    end

    test "blocks double-extension filenames containing a dangerous extension" do
      path = write_tmp("normal content", "report.exe.docx")

      assert {:error, _reason} =
               FileValidator.validate_attachment(path, "report.exe.docx")
    end

    test "blocks filenames with null bytes" do
      path = write_tmp("content", "file.pdf")

      assert {:error, _reason} =
               FileValidator.validate_attachment(path, "file\x00.pdf")
    end

    test "blocks filenames with path traversal sequences" do
      path = write_tmp("content", "file.pdf")

      assert {:error, _reason} =
               FileValidator.validate_attachment(path, "../../../etc/passwd")
    end

    test "returns application/octet-stream for unrecognised file types" do
      path = write_tmp("random binary \x00\x01\x02 data", "data.bin")
      assert {:ok, mime} = FileValidator.validate_attachment(path, "data.bin")
      assert mime == "application/octet-stream"
    end
  end
end
