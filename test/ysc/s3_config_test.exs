defmodule Ysc.S3ConfigTest do
  use ExUnit.Case, async: true

  alias Ysc.S3Config

  describe "bucket_name/0" do
    test "returns bucket name" do
      bucket = S3Config.bucket_name()
      assert is_binary(bucket)
      assert bucket != ""
    end
  end

  describe "expense_reports_bucket_name/0" do
    test "returns expense reports bucket name" do
      bucket = S3Config.expense_reports_bucket_name()
      assert is_binary(bucket)
      assert bucket != ""
    end
  end

  describe "base_url/0" do
    test "returns base URL" do
      url = S3Config.base_url()
      assert is_binary(url)
      assert url != ""
    end
  end

  describe "upload_url/0" do
    test "returns upload URL" do
      url = S3Config.upload_url()
      assert is_binary(url)
      assert url != ""
    end
  end

  describe "region/0" do
    test "returns region" do
      region = S3Config.region()
      assert is_binary(region)
    end
  end

  describe "object_url/1" do
    test "constructs object URL from key" do
      key = "test/image.jpg"
      url = S3Config.object_url(key)
      assert is_binary(url)
      assert String.contains?(url, key)
    end

    test "handles key with leading slash" do
      key = "/test/image.jpg"
      url = S3Config.object_url(key)
      assert is_binary(url)
      # Check for double slashes in the path portion (after the protocol)
      # Split on :// to get the path portion
      [_protocol, path] = String.split(url, "://", parts: 2)
      refute String.contains?(path, "//")
    end
  end

  describe "object_url/2" do
    test "constructs object URL from key and bucket" do
      key = "test/image.jpg"
      bucket = "custom-bucket"
      url = S3Config.object_url(key, bucket)
      assert is_binary(url)
      assert String.contains?(url, key)
    end
  end

  describe "endpoint_config/0" do
    test "returns endpoint config" do
      config = S3Config.endpoint_config()
      assert is_list(config) || is_nil(config)
    end
  end
end
