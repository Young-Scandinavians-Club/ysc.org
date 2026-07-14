defmodule Ysc.Media.ImageTest do
  use Ysc.DataCase, async: true

  alias Ysc.Media.Image

  describe "default_blur_hash/0" do
    test "returns the app-wide placeholder blur hash" do
      assert Image.default_blur_hash() == "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
    end
  end

  describe "blur_hash_for_display/1" do
    test "returns default for nil" do
      assert Image.blur_hash_for_display(nil) == Image.default_blur_hash()
    end

    test "returns default when blur_hash is nil" do
      image = %Image{blur_hash: nil}
      assert Image.blur_hash_for_display(image) == Image.default_blur_hash()
    end

    test "returns the image blur_hash when set" do
      image = %Image{blur_hash: "custom-hash"}
      assert Image.blur_hash_for_display(image) == "custom-hash"
    end

    test "returns default for non-image values" do
      assert Image.blur_hash_for_display(%{}) == Image.default_blur_hash()
    end
  end

  describe "display_path/1" do
    test "prefers optimized over raw" do
      image = %Image{
        optimized_image_path: "/opt.jpg",
        raw_image_path: "/raw.jpg"
      }

      assert Image.display_path(image) == "/opt.jpg"
    end

    test "falls back to raw when optimized is nil" do
      image = %Image{optimized_image_path: nil, raw_image_path: "/raw.jpg"}
      assert Image.display_path(image) == "/raw.jpg"
    end

    test "returns nil for nil image" do
      assert Image.display_path(nil) == nil
    end
  end

  describe "default_placeholder_path/0" do
    test "returns the app-wide placeholder image path" do
      assert Image.default_placeholder_path() == "/images/ysc_logo.webp"
    end
  end

  describe "display_path_with_fallback/2" do
    test "returns fallback for nil" do
      assert Image.display_path_with_fallback(nil) == Image.default_placeholder_path()
    end

    test "returns custom fallback for nil" do
      assert Image.display_path_with_fallback(nil, "/placeholder.jpg") ==
               "/placeholder.jpg"
    end

    test "returns optimized path when present" do
      image = %Image{
        optimized_image_path: "/opt.jpg",
        raw_image_path: "/raw.jpg"
      }

      assert Image.display_path_with_fallback(image) == "/opt.jpg"
    end

    test "falls back to raw then placeholder" do
      image = %Image{optimized_image_path: nil, raw_image_path: "/raw.jpg"}
      assert Image.display_path_with_fallback(image) == "/raw.jpg"

      image = %Image{optimized_image_path: nil, raw_image_path: nil}
      assert Image.display_path_with_fallback(image) == Image.default_placeholder_path()
    end
  end

  describe "optimized_path_with_fallback/2" do
    test "returns optimized path only" do
      image = %Image{
        optimized_image_path: "/opt.jpg",
        raw_image_path: "/raw.jpg"
      }

      assert Image.optimized_path_with_fallback(image) == "/opt.jpg"
    end

    test "does not fall back to raw" do
      image = %Image{optimized_image_path: nil, raw_image_path: "/raw.jpg"}

      assert Image.optimized_path_with_fallback(image) ==
               Image.default_placeholder_path()
    end
  end

  describe "thumbnail_path_with_fallback/2" do
    test "prefers thumbnail, then optimized, then raw" do
      image = %Image{
        thumbnail_path: "/thumb.jpg",
        optimized_image_path: "/opt.jpg",
        raw_image_path: "/raw.jpg"
      }

      assert Image.thumbnail_path_with_fallback(image) == "/thumb.jpg"

      image = %Image{
        thumbnail_path: nil,
        optimized_image_path: "/opt.jpg",
        raw_image_path: "/raw.jpg"
      }

      assert Image.thumbnail_path_with_fallback(image) == "/opt.jpg"

      image = %Image{
        thumbnail_path: nil,
        optimized_image_path: nil,
        raw_image_path: "/raw.jpg"
      }

      assert Image.thumbnail_path_with_fallback(image) == "/raw.jpg"
    end
  end

  describe "responsive_srcset/1" do
    test "builds srcset when thumbnail and optimized exist" do
      image = %Image{
        thumbnail_path: "/thumb.jpg",
        optimized_image_path: "/opt.jpg"
      }

      assert Image.responsive_srcset(image) == "/thumb.jpg 500w, /opt.jpg 1920w"
    end

    test "returns nil when paths are missing" do
      assert Image.responsive_srcset(nil) == nil
      assert Image.responsive_srcset(%Image{thumbnail_path: nil}) == nil
      assert Image.responsive_srcset(%Image{optimized_image_path: nil}) == nil
    end
  end
end
