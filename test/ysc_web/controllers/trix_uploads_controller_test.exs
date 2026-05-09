defmodule YscWeb.TrixUploadsControllerTest.MockS3Plug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    dispatch(conn)
  end

  # Initiate multipart upload: POST /{bucket}/{key}?uploads
  defp dispatch(%{method: "POST", query_params: %{"uploads" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Bucket>media</Bucket>
      <Key>key</Key>
      <UploadId>mock-upload-id-12345</UploadId>
    </InitiateMultipartUploadResult>
    """)
  end

  # Upload part: PUT /{bucket}/{key}?partNumber=N&uploadId=xxx
  defp dispatch(%{method: "PUT", query_params: %{"partNumber" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)

    conn
    |> put_resp_header("etag", ~s("mock-etag-abc123"))
    |> send_resp(200, "")
  end

  # Complete multipart upload: POST /{bucket}/{key}?uploadId=xxx
  defp dispatch(%{method: "POST", query_params: %{"uploadId" => _}} = conn) do
    {:ok, _body, conn} = read_body(conn)
    path = conn.request_path |> String.trim_leading("/")

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
      <Location>http://localhost/#{path}</Location>
      <Bucket>media</Bucket>
      <Key>key</Key>
      <ETag>"mock-etag-final"</ETag>
    </CompleteMultipartUploadResult>
    """)
  end

  defp dispatch(conn), do: send_resp(conn, 200, "")
end

defmodule YscWeb.TrixUploadsControllerTest do
  # async: false required because the image deduplication tests override
  # Application.put_env(:ex_aws, :s3, ...) which is global process state.
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Media
  alias Ysc.Media.Image

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

  defp start_mock_s3_server do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    ref = :"trix_uploads_s3_#{port}_#{System.unique_integer([:positive])}"

    {:ok, _} =
      Plug.Cowboy.http(YscWeb.TrixUploadsControllerTest.MockS3Plug, [],
        port: port,
        ref: ref
      )

    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    port
  end

  defp override_exaws_s3_port(port) do
    original = Application.get_env(:ex_aws, :s3)

    Application.put_env(:ex_aws, :s3,
      scheme: "http://",
      host: "localhost",
      port: port
    )

    on_exit(fn ->
      if original do
        Application.put_env(:ex_aws, :s3, original)
      else
        Application.delete_env(:ex_aws, :s3)
      end
    end)
  end

  describe "create/2 — image deduplication" do
    @tiny_png_path "test/support/fixtures/tiny.png"

    setup do
      port = start_mock_s3_server()
      override_exaws_s3_port(port)
      :ok
    end

    test "returns the existing image URL when the same file is uploaded again",
         %{conn: conn, user: user} do
      tiny_content = File.read!(@tiny_png_path)
      path = write_tmp(tiny_content, "photo.png")

      hash = Media.compute_file_hash(path)

      {:ok, existing} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://s3.example.com/original_raw.png",
          optimized_image_path: "https://cdn.example.com/existing_opt.webp",
          thumbnail_path: "https://cdn.example.com/existing_thumb.webp",
          blur_hash: "L6Pj0^jE",
          width: 1,
          height: 1,
          processing_state: :completed,
          content_hash: hash
        }
        |> Ysc.Repo.insert()

      image_count_before = Media.count_images()

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "photo.png")
        })

      assert json_response(conn, 201)["url"] == existing.optimized_image_path
      assert Media.count_images() == image_count_before
    end

    test "creates a new image when no existing image has the same hash",
         %{conn: conn} do
      tiny_content = File.read!(@tiny_png_path)
      path = write_tmp(tiny_content, "new_image.png")
      hash = Media.compute_file_hash(path)

      assert Media.find_image_by_content_hash(hash) == nil

      count_before = Media.count_images()

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "new_image.png")
        })

      assert json_response(conn, 201)
      assert Media.count_images() == count_before + 1
      assert %Image{} = Media.find_image_by_content_hash(hash)
    end

    test "returns the raw_image_path when the completed duplicate has no optimized path",
         %{conn: conn, user: user} do
      tiny_content = File.read!(@tiny_png_path)
      path = write_tmp(tiny_content, "photo.png")

      hash = Media.compute_file_hash(path)

      {:ok, existing} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://cdn.example.com/raw_only.png",
          optimized_image_path: nil,
          processing_state: :completed,
          content_hash: hash
        }
        |> Ysc.Repo.insert()

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => plain_text_upload(path, "photo.png")
        })

      assert json_response(conn, 201)["url"] == existing.raw_image_path
    end
  end
end
