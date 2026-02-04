defmodule YscWeb.Validators.FileUploadIntegrationTest do
  @moduledoc """
  Integration tests demonstrating file validation in upload handlers.

  These tests verify that file validation works correctly in the context
  of actual upload processing, ensuring malicious files are rejected.
  """
  use Ysc.DataCase, async: true

  alias YscWeb.Validators.FileValidator

  # Test files from static directory
  @test_image_jpg Path.join([
                    Application.app_dir(:ysc, "priv/static/images"),
                    "404.jpg"
                  ])

  describe "file validation in upload context" do
    test "valid image file passes validation" do
      if File.exists?(@test_image_jpg) do
        # Simulate what happens in consume_entry
        result =
          FileValidator.validate_image(@test_image_jpg, [
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp"
          ])

        assert {:ok, "image/jpeg"} = result
      end
    end

    test "malicious executable with image extension is rejected" do
      # Simulate a malicious upload: executable file renamed to .jpg
      tmp_file = System.tmp_dir!() |> Path.join("malicious_upload.jpg")

      try do
        # Write Windows PE executable header
        File.write!(
          tmp_file,
          <<0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00, 0x04, 0x00>>
        )

        # This is what would happen in consume_entry before upload
        result =
          FileValidator.validate_image(tmp_file, [
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp"
          ])

        # Should be rejected even though it has .jpg extension
        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "shell script with image extension is rejected" do
      # Simulate a malicious upload: shell script renamed to .jpg
      tmp_file = System.tmp_dir!() |> Path.join("script_upload.jpg")

      try do
        File.write!(tmp_file, "#!/bin/bash\nrm -rf /\n")

        result =
          FileValidator.validate_image(tmp_file, [
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp"
          ])

        # Should be rejected
        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "valid PNG with wrong extension is accepted (content-based validation)" do
      # This demonstrates that we validate based on content, not filename
      tmp_file = System.tmp_dir!() |> Path.join("image_with_wrong_ext.txt")

      try do
        # Copy a valid PNG but with .txt extension
        png_file =
          Path.join([
            Application.app_dir(:ysc, "priv/static/images"),
            "vikings/viking_beer.png"
          ])

        if File.exists?(png_file) do
          File.cp!(png_file, tmp_file)

          # FileType detects PNG from content, so validation passes
          # This is correct behavior - we validate content, not filename
          result =
            FileValidator.validate_image(tmp_file, [".png", ".jpg", ".jpeg"])

          assert {:ok, "image/png"} = result
        end
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "document validation for expense receipts" do
      # Test document validation as used in expense report uploads
      if File.exists?(@test_image_jpg) do
        # JPEG images are valid documents for receipts
        result =
          FileValidator.validate_document(@test_image_jpg, [
            ".pdf",
            ".jpg",
            ".jpeg",
            ".png",
            ".webp"
          ])

        assert {:ok, "image/jpeg"} = result
      end
    end

    test "non-document file rejected for expense receipts" do
      # Create a text file (not a valid receipt document)
      tmp_file = System.tmp_dir!() |> Path.join("receipt.txt")

      try do
        File.write!(tmp_file, "This is not a receipt document")

        result =
          FileValidator.validate_document(tmp_file, [
            ".pdf",
            ".jpg",
            ".jpeg",
            ".png",
            ".webp"
          ])

        # Should be rejected
        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end
  end

  describe "edge cases" do
    test "handles empty file gracefully" do
      tmp_file = System.tmp_dir!() |> Path.join("empty.jpg")

      try do
        File.write!(tmp_file, "")

        result = FileValidator.validate_image(tmp_file)

        # Empty file should fail
        assert {:error, _reason} = result
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "handles very small file" do
      tmp_file = System.tmp_dir!() |> Path.join("tiny.jpg")

      try do
        # Write just a few bytes
        File.write!(tmp_file, <<0xFF, 0xD8>>)

        result = FileValidator.validate_image(tmp_file)

        # May or may not be detected, but should not crash
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "handles non-existent file" do
      result = FileValidator.validate_image("/nonexistent/path/file.jpg")

      assert {:error, _reason} = result
    end
  end
end
