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
  end
end
