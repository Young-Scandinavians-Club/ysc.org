defmodule Ysc.S3ConfigTest do
  use ExUnit.Case, async: false

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
    test "returns empty list when s3_endpoint is not configured" do
      previous = Application.get_env(:ysc, :s3_endpoint)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_endpoint)
        else
          Application.put_env(:ysc, :s3_endpoint, previous)
        end
      end)

      Application.delete_env(:ysc, :s3_endpoint)
      assert S3Config.endpoint_config() == []
    end

    test "returns configured endpoint when set" do
      previous = Application.get_env(:ysc, :s3_endpoint)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_endpoint)
        else
          Application.put_env(:ysc, :s3_endpoint, previous)
        end
      end)

      Application.put_env(:ysc, :s3_endpoint, host: "localhost", port: 9000)
      assert S3Config.endpoint_config() == [host: "localhost", port: 9000]
    end
  end

  describe "base_url/0 and upload_url/0 with explicit config" do
    test "uses configured s3_base_url when set" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "https://fly.storage.tigris.dev")
      assert S3Config.base_url() == "https://fly.storage.tigris.dev"

      upload = S3Config.upload_url()
      bucket = S3Config.bucket_name()
      assert String.contains?(upload, "#{bucket}.fly.storage.tigris.dev")
    end

    test "object_url/2 uses Tigris virtual-hosted style when base URL is Tigris" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "https://fly.storage.tigris.dev")
      url = S3Config.object_url("path/to/file.png", "my-bucket")

      assert String.starts_with?(
               url,
               "https://my-bucket.fly.storage.tigris.dev/"
             )

      assert String.ends_with?(url, "path/to/file.png")
    end

    test "upload_url falls back to Tigris virtual host when base URL is blank" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)

      on_exit(fn ->
        if previous_base == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous_base)
        end

        if previous_bucket == nil do
          Application.delete_env(:ysc, :s3_bucket)
        else
          Application.put_env(:ysc, :s3_bucket, previous_bucket)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "")
      Application.put_env(:ysc, :s3_bucket, "fallback-bucket")

      upload = S3Config.upload_url()
      assert upload == "https://fallback-bucket.fly.storage.tigris.dev"
    end
  end

  describe "credentials / region" do
    test "returns configured or default aws credential keys" do
      assert is_binary(S3Config.aws_access_key_id())
      assert is_binary(S3Config.aws_secret_access_key())
    end
  end
end
