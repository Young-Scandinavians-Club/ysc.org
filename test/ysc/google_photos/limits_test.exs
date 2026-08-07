defmodule Ysc.GooglePhotos.LimitsTest do
  use ExUnit.Case, async: true

  alias Ysc.GooglePhotos.Limits

  describe "normalize_album_title/1" do
    test "truncates to 500 characters" do
      long = String.duplicate("a", 600)
      assert String.length(Limits.normalize_album_title(long)) == 500
    end

    test "trims whitespace" do
      assert Limits.normalize_album_title("  Gala  ") == "Gala"
    end
  end

  describe "normalize_filename/1" do
    test "uses basename and truncates to 255" do
      name = String.duplicate("x", 300) <> ".jpg"
      normalized = Limits.normalize_filename("/tmp/evil/#{name}")
      assert String.length(normalized) == 255
      refute String.contains?(normalized, "/")
    end
  end

  describe "validate_upload/2" do
    test "accepts valid photo" do
      assert :ok = Limits.validate_upload("photo.jpg", 1024)
    end

    test "accepts valid video" do
      assert :ok = Limits.validate_upload("clip.mov", 50_000_000)
    end

    test "rejects photo over 200 MB" do
      assert {:error, :photo_too_large} =
               Limits.validate_upload("big.jpg", Limits.max_photo_bytes() + 1)
    end

    test "rejects video over 20 GB" do
      assert {:error, :video_too_large} =
               Limits.validate_upload("big.mp4", Limits.max_video_bytes() + 1)
    end

    test "allows video up to 20 GB" do
      assert :ok =
               Limits.validate_upload("big.mp4", Limits.max_video_bytes())
    end

    test "rejects empty filename" do
      assert {:error, :empty_filename} = Limits.validate_upload("   ", 100)
    end

    test "rejects non-binary filename" do
      assert {:error, :invalid_filename} = Limits.validate_upload(nil, 100)
    end

    test "rejects filename longer than 255 characters before normalization" do
      long_name = String.duplicate("a", 256) <> ".jpg"

      assert {:error, :filename_too_long} =
               Limits.validate_upload(long_name, 1024)
    end

    test "rejects unsupported extension" do
      assert {:error, :unsupported_type} =
               Limits.validate_upload("file.xyz", 100)
    end
  end

  describe "video?/1 and photo?/1" do
    test "detects common types" do
      assert Limits.video?("a.MP4")
      assert Limits.photo?("b.jpeg")
      refute Limits.video?("c.png")
    end

    test "video?/1 returns false for non-binary input" do
      refute Limits.video?(nil)
      refute Limits.video?(123)
    end

    test "photo?/1 returns false for non-binary input" do
      refute Limits.photo?(nil)
      refute Limits.photo?(%{})
    end
  end

  describe "max_upload_bytes/0" do
    test "equals max_video_bytes/0 (the larger of the two limits)" do
      assert Limits.max_upload_bytes() == Limits.max_video_bytes()
    end
  end

  describe "accepted_extensions/0" do
    test "includes both photo and video extensions" do
      extensions = Limits.accepted_extensions()
      assert ".jpg" in extensions
      assert ".mp4" in extensions
    end
  end

  describe "max_bytes_for_filename/1" do
    test "returns video limit for video filenames" do
      assert Limits.max_bytes_for_filename("clip.mov") == Limits.max_video_bytes()
    end

    test "returns photo limit for photo filenames" do
      assert Limits.max_bytes_for_filename("photo.png") ==
               Limits.max_photo_bytes()
    end
  end

  describe "content_type_for_filename/1" do
    test "maps known photo extensions to their MIME types" do
      assert Limits.content_type_for_filename("a.png") == "image/png"
      assert Limits.content_type_for_filename("a.webp") == "image/webp"
      assert Limits.content_type_for_filename("a.heic") == "image/heic"
      assert Limits.content_type_for_filename("a.heif") == "image/heif"
      assert Limits.content_type_for_filename("a.gif") == "image/gif"
      assert Limits.content_type_for_filename("a.bmp") == "image/bmp"
      assert Limits.content_type_for_filename("a.tif") == "image/tiff"
      assert Limits.content_type_for_filename("a.tiff") == "image/tiff"
      assert Limits.content_type_for_filename("a.jpg") == "image/jpeg"
      assert Limits.content_type_for_filename("a.JPEG") == "image/jpeg"
    end

    test "maps known video extensions to their MIME types" do
      assert Limits.content_type_for_filename("a.mp4") == "video/mp4"
      assert Limits.content_type_for_filename("a.mov") == "video/quicktime"
      assert Limits.content_type_for_filename("a.m4v") == "video/x-m4v"
      assert Limits.content_type_for_filename("a.avi") == "video/x-msvideo"
      assert Limits.content_type_for_filename("a.mkv") == "video/x-matroska"
      assert Limits.content_type_for_filename("a.webm") == "video/webm"
      assert Limits.content_type_for_filename("a.3gp") == "video/3gpp"
      assert Limits.content_type_for_filename("a.3g2") == "video/3gpp2"
      assert Limits.content_type_for_filename("a.mpeg") == "video/mpeg"
      assert Limits.content_type_for_filename("a.mpg") == "video/mpeg"
      assert Limits.content_type_for_filename("a.wmv") == "video/x-ms-wmv"
      assert Limits.content_type_for_filename("a.asf") == "video/x-ms-asf"
      assert Limits.content_type_for_filename("a.m2ts") == "video/mp2t"
      assert Limits.content_type_for_filename("a.mts") == "video/mp2t"
    end

    test "falls back to application/octet-stream for unknown extensions" do
      assert Limits.content_type_for_filename("a.xyz") ==
               "application/octet-stream"

      assert Limits.content_type_for_filename("no_extension") ==
               "application/octet-stream"
    end
  end

  describe "max_album_title_length/0 and max_filename_length/0" do
    test "expose the configured limits" do
      assert Limits.max_album_title_length() == 500
      assert Limits.max_filename_length() == 255
    end
  end

  describe "normalize_album_title/1 non-binary input" do
    test "returns empty string for non-binary input" do
      assert Limits.normalize_album_title(nil) == ""
      assert Limits.normalize_album_title(123) == ""
    end
  end

  describe "normalize_filename/1 non-binary input" do
    test "returns empty string for non-binary input" do
      assert Limits.normalize_filename(nil) == ""
      assert Limits.normalize_filename(%{}) == ""
    end
  end

  describe "validate_upload/2 additional branches" do
    test "rejects negative size for an otherwise-valid photo" do
      assert {:error, :invalid_size} = Limits.validate_upload("photo.jpg", -1)
    end
  end

  describe "error_message/1" do
    test "returns a human-readable message for every known reason" do
      assert Limits.error_message(:photo_too_large) =~ "200 MB"
      assert Limits.error_message(:video_too_large) =~ "20 GB"
      assert Limits.error_message(:file_too_large) =~ "maximum allowed size"
      assert Limits.error_message(:filename_too_long) =~ "too long"
      assert Limits.error_message(:empty_filename) =~ "required"
      assert Limits.error_message(:unsupported_type) =~ "not supported"
      assert Limits.error_message(:album_title_too_long) =~ "too long"
    end

    test "falls back to a generic message for unknown reasons" do
      assert Limits.error_message(:something_else) ==
               "Invalid upload (something_else)."
    end
  end
end
