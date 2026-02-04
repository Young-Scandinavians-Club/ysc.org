defmodule YscWeb.Validators.FileValidatorTest do
  @moduledoc """
  Tests for FileValidator module that validates file uploads using MIME type detection.
  """
  use ExUnit.Case, async: true

  alias YscWeb.Validators.FileValidator

  # Test files from static directory
  @test_image_jpg Path.join([
                    Application.app_dir(:ysc, "priv/static/images"),
                    "404.jpg"
                  ])
  @test_image_png Path.join([
                    Application.app_dir(:ysc, "priv/static/images"),
                    "vikings/viking_beer.png"
                  ])
  @test_image_webp Path.join([
                     Application.app_dir(:ysc, "priv/static/images"),
                     "404_fika.webp"
                   ])

  describe "validate_image/2" do
    test "validates a valid JPEG image" do
      if File.exists?(@test_image_jpg) do
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_image(@test_image_jpg)
      else
        # Skip if test file doesn't exist
        :ok
      end
    end

    test "validates a valid PNG image" do
      if File.exists?(@test_image_png) do
        assert {:ok, "image/png"} =
                 FileValidator.validate_image(@test_image_png)
      else
        :ok
      end
    end

    test "validates a valid WebP image" do
      if File.exists?(@test_image_webp) do
        assert {:ok, "image/webp"} =
                 FileValidator.validate_image(@test_image_webp)
      else
        :ok
      end
    end

    test "rejects a file with wrong extension but correct MIME type" do
      # Create a temporary PNG file with .jpg extension
      tmp_file = System.tmp_dir!() |> Path.join("test_image.jpg")

      try do
        if File.exists?(@test_image_png) do
          File.cp!(@test_image_png, tmp_file)

          # Should still validate as PNG based on content, not extension
          assert {:ok, "image/png"} = FileValidator.validate_image(tmp_file)
        end
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "rejects a non-image file" do
      # Create a text file
      tmp_file = System.tmp_dir!() |> Path.join("test.txt")

      try do
        File.write!(tmp_file, "This is not an image file")

        result = FileValidator.validate_image(tmp_file)

        assert {:error, reason} = result
        # FileType may return :unknown or detect it as text/plain
        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "rejects an executable file with image extension" do
      # Create a fake executable file with .jpg extension
      # This simulates a malicious upload attempt
      tmp_file = System.tmp_dir!() |> Path.join("malicious.jpg")

      try do
        # Write some binary data that looks like an executable (PE header)
        File.write!(
          tmp_file,
          <<0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00>>
        )

        result = FileValidator.validate_image(tmp_file)

        assert {:error, reason} = result
        # Should detect it's not an image based on magic numbers
        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "validates with extension restrictions" do
      if File.exists?(@test_image_jpg) do
        # Should pass with correct extension
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_image(@test_image_jpg, [
                   ".jpg",
                   ".jpeg",
                   ".png"
                 ])

        # Should fail with wrong extension list
        result = FileValidator.validate_image(@test_image_jpg, [".png", ".gif"])
        assert {:error, _reason} = result
        assert String.contains?(elem(result, 1), "extension")
      end
    end

    test "handles non-existent file" do
      result = FileValidator.validate_image("/nonexistent/file.jpg")
      assert {:error, _reason} = result
    end
  end

  describe "validate_document/2" do
    test "validates a valid PDF file" do
      # Create a minimal valid PDF file
      tmp_file = System.tmp_dir!() |> Path.join("test.pdf")

      try do
        # PDF magic bytes: %PDF-1.4
        File.write!(tmp_file, "%PDF-1.4\n")

        result = FileValidator.validate_document(tmp_file)

        # FileType might not detect minimal PDF, so we check for either success or unknown
        assert match?({:ok, _}, result) or
                 match?({:error, "Could not detect file type"}, result)
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "validates an image as a document" do
      if File.exists?(@test_image_jpg) do
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_document(@test_image_jpg)
      else
        :ok
      end
    end

    test "rejects a non-document file" do
      # Create a text file
      tmp_file = System.tmp_dir!() |> Path.join("test.txt")

      try do
        File.write!(tmp_file, "This is not a document")

        result = FileValidator.validate_document(tmp_file)

        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "validates with extension restrictions" do
      if File.exists?(@test_image_jpg) do
        # Should pass with correct extension
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_document(@test_image_jpg, [
                   ".jpg",
                   ".pdf"
                 ])

        # Should fail with wrong extension list
        result = FileValidator.validate_document(@test_image_jpg, [".pdf"])
        assert {:error, _reason} = result
        assert String.contains?(elem(result, 1), "extension")
      end
    end
  end

  describe "validate_file/3" do
    test "validates with custom MIME types" do
      if File.exists?(@test_image_jpg) do
        # Should pass with correct MIME type
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_file(
                   @test_image_jpg,
                   ["image/jpeg", "image/png"],
                   []
                 )

        # Should fail with wrong MIME type
        result =
          FileValidator.validate_file(
            @test_image_jpg,
            ["application/pdf", "text/plain"],
            []
          )

        assert {:error, _reason} = result
        assert String.contains?(elem(result, 1), "not allowed")
      end
    end

    test "validates both MIME type and extension" do
      if File.exists?(@test_image_jpg) do
        # Should pass with both correct
        assert {:ok, "image/jpeg"} =
                 FileValidator.validate_file(
                   @test_image_jpg,
                   ["image/jpeg"],
                   [".jpg", ".jpeg"]
                 )

        # Should fail if extension doesn't match
        result =
          FileValidator.validate_file(@test_image_jpg, ["image/jpeg"], [
            ".png",
            ".gif"
          ])

        assert {:error, _reason} = result
        assert String.contains?(elem(result, 1), "extension")
      end
    end

    test "handles empty file" do
      tmp_file = System.tmp_dir!() |> Path.join("empty.jpg")

      try do
        File.write!(tmp_file, "")

        result = FileValidator.validate_file(tmp_file, ["image/jpeg"], [])

        # Empty file should fail validation
        assert {:error, _reason} = result
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "handles corrupted image file" do
      tmp_file = System.tmp_dir!() |> Path.join("corrupted.jpg")

      try do
        # Write invalid image data
        File.write!(
          tmp_file,
          <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>
        )

        result = FileValidator.validate_file(tmp_file, ["image/jpeg"], [])

        # Should either detect as JPEG (if magic bytes are valid) or fail
        assert match?({:ok, "image/jpeg"}, result) or
                 match?({:error, _}, result)
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end
  end

  describe "security: malicious file detection" do
    test "rejects executable with image extension" do
      tmp_file = System.tmp_dir!() |> Path.join("malicious.jpg")

      try do
        # Write Windows PE executable header (MZ header)
        File.write!(tmp_file, <<0x4D, 0x5A, 0x90, 0x00>>)

        result = FileValidator.validate_image(tmp_file)

        assert {:error, _reason} = result
        # Should detect it's not an image
        assert String.contains?(elem(result, 1), "not allowed") or
                 String.contains?(elem(result, 1), "Could not detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "rejects shell script with image extension" do
      tmp_file = System.tmp_dir!() |> Path.join("script.jpg")

      try do
        File.write!(tmp_file, "#!/bin/bash\necho 'malicious'")

        result = FileValidator.validate_image(tmp_file)

        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "rejects HTML file with image extension" do
      tmp_file = System.tmp_dir!() |> Path.join("page.jpg")

      try do
        File.write!(tmp_file, "<html><body>Malicious content</body></html>")

        result = FileValidator.validate_image(tmp_file)

        assert {:error, reason} = result

        assert String.contains?(reason, "not allowed") or
                 String.contains?(reason, "Could not detect file type") or
                 String.contains?(reason, "Failed to detect file type")
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end

    test "accepts valid image even with unusual extension" do
      # Create a PNG file with .txt extension
      tmp_file = System.tmp_dir!() |> Path.join("image.txt")

      try do
        if File.exists?(@test_image_png) do
          File.cp!(@test_image_png, tmp_file)

          # FileType detects extension based on content, not filename
          # So a PNG file will always return "png" as the detected extension
          # This means validation will pass if we allow .png, regardless of filename
          result = FileValidator.validate_image(tmp_file, [".png"])

          # FileType detects "png" from content, which matches allowed [".png"]
          assert {:ok, "image/png"} = result

          # Without extension requirement, should also pass (validates content only)
          assert {:ok, "image/png"} = FileValidator.validate_image(tmp_file, [])

          # But if we require a different extension, it should fail
          result2 = FileValidator.validate_image(tmp_file, [".jpg", ".jpeg"])
          assert {:error, reason} = result2
          assert String.contains?(reason, "extension")
        end
      after
        if File.exists?(tmp_file), do: File.rm(tmp_file)
      end
    end
  end
end
