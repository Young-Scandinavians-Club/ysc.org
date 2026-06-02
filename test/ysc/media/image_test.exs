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
      image = %Image{optimized_image_path: "/opt.jpg", raw_image_path: "/raw.jpg"}
      assert Image.display_path(image) == "/opt.jpg"
    end

    test "falls back to raw when optimized is nil" do
      image = %Image{optimized_image_path: nil, raw_image_path: "/raw.jpg"}
      assert Image.display_path(image) == "/raw.jpg"
    end
  end
end
