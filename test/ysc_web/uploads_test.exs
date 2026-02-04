defmodule YscWeb.UploadsTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Uploads

  describe "uploads_dir/0" do
    test "returns the uploads directory path" do
      dir = Uploads.uploads_dir()

      assert String.ends_with?(dir, "/priv/static/uploads")
      assert is_binary(dir)
    end
  end

  describe "upload_path/1" do
    test "returns static path for given file" do
      path = Uploads.upload_path("test.jpg")

      assert path == "/uploads/test.jpg"
    end

    test "handles files with different extensions" do
      assert Uploads.upload_path("image.png") == "/uploads/image.png"
      assert Uploads.upload_path("document.pdf") == "/uploads/document.pdf"
    end

    test "handles files with special characters in name" do
      path = Uploads.upload_path("my-file_123.jpg")

      assert path == "/uploads/my-file_123.jpg"
    end
  end
end
