defmodule Ysc.S3ConfigTest do
  use ExUnit.Case, async: false

  alias Ysc.S3Config

  describe "custom_public_base_url (Tigris host ignored)" do
    test "avatars_upload_url uses bucket virtual host when public URL is fly.storage" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_avatars_bucket = Application.get_env(:ysc, :avatars_s3_bucket)
      previous_avatars_pub = Application.get_env(:ysc, :s3_avatars_public_url)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_base_url, previous_base},
              {:avatars_s3_bucket, previous_avatars_bucket},
              {:s3_avatars_public_url, previous_avatars_pub}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "https://fly.storage.tigris.dev")
      Application.put_env(:ysc, :avatars_s3_bucket, "ysc-sandbox-avatars")

      Application.put_env(
        :ysc,
        :s3_avatars_public_url,
        "https://avatars.fly.storage.tigris.dev"
      )

      assert S3Config.avatars_upload_url() ==
               "https://ysc-sandbox-avatars.fly.storage.tigris.dev"
    end
  end

  describe "include_tigris_virtual_host_in_csp?/0" do
    test "is true unless media, avatars, and expense public URLs are all set" do
      keys = [
        :s3_media_public_url,
        :s3_avatars_public_url,
        :s3_expense_reports_public_url
      ]

      previous = Enum.map(keys, &Application.get_env(:ysc, &1))

      on_exit(fn ->
        Enum.zip(keys, previous)
        |> Enum.each(fn {k, v} ->
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end)
      end)

      Application.put_env(
        :ysc,
        :s3_media_public_url,
        "https://assets.example.com"
      )

      Application.put_env(
        :ysc,
        :s3_avatars_public_url,
        "https://avatars.example.com"
      )

      Application.delete_env(:ysc, :s3_expense_reports_public_url)
      assert S3Config.include_tigris_virtual_host_in_csp?()

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.example.com"
      )

      refute S3Config.include_tigris_virtual_host_in_csp?()
    end

    test "is true when env URLs are only fly.storage hosts (sandbox-style)" do
      keys = [
        :s3_media_public_url,
        :s3_avatars_public_url,
        :s3_expense_reports_public_url
      ]

      previous = Enum.map(keys, &Application.get_env(:ysc, &1))

      on_exit(fn ->
        Enum.zip(keys, previous)
        |> Enum.each(fn {k, v} ->
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end)
      end)

      Application.put_env(
        :ysc,
        :s3_media_public_url,
        "https://ysc-sandbox-assets.fly.storage.tigris.dev"
      )

      Application.put_env(
        :ysc,
        :s3_avatars_public_url,
        "https://avatars.fly.storage.tigris.dev"
      )

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://ysc-sandbox-expense.fly.storage.tigris.dev"
      )

      assert S3Config.include_tigris_virtual_host_in_csp?()
    end
  end

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

    test "object_url/2 uses bucket name, not a virtual-hosted endpoint hostname label" do
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

      # Endpoint already virtual-hosted for avatars; media URLs must still use media bucket.
      Application.put_env(
        :ysc,
        :s3_base_url,
        "https://ysc-prod-avatars.fly.storage.tigris.dev"
      )

      Application.put_env(:ysc, :s3_bucket, "ysc-prod-assets")

      assert S3Config.object_url("media/x.jpg", "ysc-prod-assets") ==
               "https://ysc-prod-assets.fly.storage.tigris.dev/media/x.jpg"

      assert S3Config.upload_url() ==
               "https://ysc-prod-assets.fly.storage.tigris.dev"
    end

    test "upload_url falls back to Tigris virtual host when base URL is blank" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)
      previous_public = Application.get_env(:ysc, :s3_media_public_url)

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

        if previous_public == nil do
          Application.delete_env(:ysc, :s3_media_public_url)
        else
          Application.put_env(:ysc, :s3_media_public_url, previous_public)
        end
      end)

      Application.delete_env(:ysc, :s3_media_public_url)
      Application.put_env(:ysc, :s3_base_url, "")
      Application.put_env(:ysc, :s3_bucket, "fallback-bucket")

      upload = S3Config.upload_url()
      assert upload == "https://fallback-bucket.fly.storage.tigris.dev"
    end

    test "public base URLs override upload and object URLs" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)
      previous_avatars_bucket = Application.get_env(:ysc, :avatars_s3_bucket)

      previous_expense_bucket =
        Application.get_env(:ysc, :expense_reports_s3_bucket)

      previous_media_pub = Application.get_env(:ysc, :s3_media_public_url)
      previous_avatars_pub = Application.get_env(:ysc, :s3_avatars_public_url)

      previous_expense_pub =
        Application.get_env(:ysc, :s3_expense_reports_public_url)

      on_exit(fn ->
        for {key, val} <- [
              {:s3_base_url, previous_base},
              {:s3_bucket, previous_bucket},
              {:avatars_s3_bucket, previous_avatars_bucket},
              {:expense_reports_s3_bucket, previous_expense_bucket},
              {:s3_media_public_url, previous_media_pub},
              {:s3_avatars_public_url, previous_avatars_pub},
              {:s3_expense_reports_public_url, previous_expense_pub}
            ] do
          if val == nil,
            do: Application.delete_env(:ysc, key),
            else: Application.put_env(:ysc, key, val)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "https://fly.storage.tigris.dev")
      Application.put_env(:ysc, :s3_bucket, "media-b")
      Application.put_env(:ysc, :avatars_s3_bucket, "avatars-b")
      Application.put_env(:ysc, :expense_reports_s3_bucket, "expense-b")

      Application.put_env(
        :ysc,
        :s3_media_public_url,
        "https://assets.example.com/"
      )

      Application.put_env(
        :ysc,
        :s3_avatars_public_url,
        "https://avatars.example.com"
      )

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.example.com"
      )

      assert S3Config.upload_url() == "https://assets.example.com"
      assert S3Config.avatars_upload_url() == "https://avatars.example.com"

      assert S3Config.object_url("k/m.jpg", "media-b") ==
               "https://assets.example.com/k/m.jpg"

      assert S3Config.object_url("k/a.jpg", "avatars-b") ==
               "https://avatars.example.com/k/a.jpg"

      assert S3Config.object_url("receipts/x.pdf", "expense-b") ==
               "https://expenses.example.com/receipts/x.pdf"

      assert "https://assets.example.com" in S3Config.storage_csp_connect_sources()

      assert "https://avatars.example.com" in S3Config.storage_csp_connect_sources()

      assert "https://expenses.example.com" in S3Config.storage_csp_connect_sources()
    end

    test "expense_report_file_presigned_url_args uses bucket_as_host when public URL set" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)
      previous_bucket = Application.get_env(:ysc, :expense_reports_s3_bucket)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end

        if previous_bucket == nil do
          Application.delete_env(:ysc, :expense_reports_s3_bucket)
        else
          Application.put_env(:ysc, :expense_reports_s3_bucket, previous_bucket)
        end
      end)

      Application.put_env(:ysc, :expense_reports_s3_bucket, "real-bucket")

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.example.com"
      )

      {config, :get, host, path, opts} =
        S3Config.expense_report_file_presigned_url_args("receipts/a.pdf", 3600)

      assert is_map(config)
      assert config[:scheme] == "https://"
      assert config[:host] == "expenses.example.com"
      assert config[:port] == nil
      assert host == "expenses.example.com"
      assert path == "receipts/a.pdf"
      assert opts[:expires_in] == 3600
      assert opts[:virtual_host] == true
      assert opts[:bucket_as_host] == true
    end

    test "expense_report_file_presigned_url_args passes scheme and non-default port to ExAws" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.example.com:8443"
      )

      {config, :get, host, _path, _opts} =
        S3Config.expense_report_file_presigned_url_args("k", 60)

      assert config[:scheme] == "https://"
      assert config[:host] == "expenses.example.com"
      assert config[:port] == 8443
      assert host == "expenses.example.com"
    end

    test "expense_report_file_presigned_url_args supports http origin (e.g. MinIO)" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "http://127.0.0.1:9000"
      )

      {config, :get, host, _, _} =
        S3Config.expense_report_file_presigned_url_args("k", 60)

      assert config[:scheme] == "http://"
      assert config[:host] == "127.0.0.1"
      assert config[:port] == 9000
      assert host == "127.0.0.1"
    end

    test "expense_report_file_presigned_url_args raises on invalid public URL" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "expenses.example.com"
      )

      assert_raise ArgumentError, fn ->
        S3Config.expense_report_file_presigned_url_args("k", 60)
      end
    end

    test "expense_report_file_presigned_url_args treats whitespace-only public URL as unset" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)
      previous_bucket = Application.get_env(:ysc, :expense_reports_s3_bucket)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end

        if previous_bucket == nil do
          Application.delete_env(:ysc, :expense_reports_s3_bucket)
        else
          Application.put_env(:ysc, :expense_reports_s3_bucket, previous_bucket)
        end
      end)

      Application.put_env(:ysc, :s3_expense_reports_public_url, "   \t  ")
      Application.put_env(:ysc, :expense_reports_s3_bucket, "only-bucket")

      assert {_c, :get, "only-bucket", "k", [expires_in: 30]} =
               S3Config.expense_report_file_presigned_url_args("k", 30)
    end

    test "expense_report_file_presigned_url_args uses bucket name without public URL" do
      previous = Application.get_env(:ysc, :s3_expense_reports_public_url)
      previous_bucket = Application.get_env(:ysc, :expense_reports_s3_bucket)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_expense_reports_public_url)
        else
          Application.put_env(:ysc, :s3_expense_reports_public_url, previous)
        end

        if previous_bucket == nil do
          Application.delete_env(:ysc, :expense_reports_s3_bucket)
        else
          Application.put_env(:ysc, :expense_reports_s3_bucket, previous_bucket)
        end
      end)

      Application.delete_env(:ysc, :s3_expense_reports_public_url)
      Application.put_env(:ysc, :expense_reports_s3_bucket, "exp-local")

      {_config, :get, bucket, path, opts} =
        S3Config.expense_report_file_presigned_url_args("receipts/b.pdf", 1800)

      assert bucket == "exp-local"
      assert path == "receipts/b.pdf"
      assert opts == [expires_in: 1800]
    end
  end

  describe "credentials / region" do
    test "returns configured or default aws credential keys" do
      assert is_binary(S3Config.aws_access_key_id())
      assert is_binary(S3Config.aws_secret_access_key())
    end
  end
end
