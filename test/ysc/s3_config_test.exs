defmodule Ysc.S3ConfigTest do
  use ExUnit.Case, async: false

  alias Ysc.S3Config

  describe "assert_direct_upload_url!/2" do
    test "allows any host when custom domain flag is off" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end
      end)

      Application.delete_env(:ysc, :s3_use_custom_domain)

      assert :ok ==
               S3Config.assert_direct_upload_url!(
                 "https://y.fly.storage.tigris.dev",
                 :media
               )
    end

    test "rejects fly.storage host when custom domain flag is on" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)

      assert_raise ArgumentError, fn ->
        S3Config.assert_direct_upload_url!(
          "https://y.fly.storage.tigris.dev",
          :avatars
        )
      end

      assert :ok ==
               S3Config.assert_direct_upload_url!(
                 "https://avatars.ysc.org",
                 :avatars
               )
    end

    test "allows a malformed URL (no parseable host) when custom domain flag is on" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)

      assert :ok ==
               S3Config.assert_direct_upload_url!("not-a-url", :media)
    end
  end

  describe "S3_USE_CUSTOM_DOMAIN (s3_use_custom_domain)" do
    test "avatars_upload_url uses public URL verbatim when flag is true" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_pub = Application.get_env(:ysc, :s3_avatars_public_url)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end

        if previous_pub == nil do
          Application.delete_env(:ysc, :s3_avatars_public_url)
        else
          Application.put_env(:ysc, :s3_avatars_public_url, previous_pub)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)

      Application.put_env(
        :ysc,
        :s3_avatars_public_url,
        "https://avatars.ysc.org"
      )

      assert S3Config.avatars_upload_url() == "https://avatars.ysc.org"
    end

    test "avatars_upload_url raises when flag is true but public URL missing" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_pub = Application.get_env(:ysc, :s3_avatars_public_url)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end

        if previous_pub == nil do
          Application.delete_env(:ysc, :s3_avatars_public_url)
        else
          Application.put_env(:ysc, :s3_avatars_public_url, previous_pub)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)
      Application.delete_env(:ysc, :s3_avatars_public_url)

      assert_raise ArgumentError, fn -> S3Config.avatars_upload_url() end
    end
  end

  describe "custom_public_base_url (Tigris host ignored)" do
    test "avatars_upload_url uses bucket virtual host when public URL is fly.storage" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_avatars_bucket = Application.get_env(:ysc, :avatars_s3_bucket)
      previous_avatars_pub = Application.get_env(:ysc, :s3_avatars_public_url)
      previous_use_custom = Application.get_env(:ysc, :s3_use_custom_domain)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_base_url, previous_base},
              {:avatars_s3_bucket, previous_avatars_bucket},
              {:s3_avatars_public_url, previous_avatars_pub},
              {:s3_use_custom_domain, previous_use_custom}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.delete_env(:ysc, :s3_use_custom_domain)
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

    test "uses trimmed_nonempty_public_url check when custom domain flag is on" do
      keys = [
        :s3_use_custom_domain,
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

      Application.put_env(:ysc, :s3_use_custom_domain, true)

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

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.example.com"
      )

      refute S3Config.include_tigris_virtual_host_in_csp?()

      # Whitespace-only is treated as unset even though the flag is on, so
      # not all three are configured.
      Application.put_env(:ysc, :s3_avatars_public_url, "   ")
      assert S3Config.include_tigris_virtual_host_in_csp?()
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

  describe "app_resources_bucket_name/0" do
    test "returns configured app resources bucket name" do
      previous = Application.get_env(:ysc, :app_resources_s3_bucket)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :app_resources_s3_bucket)
        else
          Application.put_env(:ysc, :app_resources_s3_bucket, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :app_resources_s3_bucket,
        "ysc-app-resources-test"
      )

      assert S3Config.app_resources_bucket_name() == "ysc-app-resources-test"
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

    test "percent-encodes unsafe characters in the key without touching '/' separators" do
      key = "public/YSC LOGO 4 color straight text 091222.ai.webp"
      url = S3Config.object_url(key, "custom-bucket")

      refute String.contains?(url, " ")
      assert String.contains?(url, "/public/YSC%20LOGO%204%20color")
      assert URI.parse(url).path |> URI.decode() |> String.ends_with?(key)
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

  describe "storage_csp_connect_sources/0 additional branches" do
    test "uses trimmed_nonempty_public_url check and drops whitespace-only URLs when custom domain flag is on" do
      keys = [
        :s3_use_custom_domain,
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

      Application.put_env(:ysc, :s3_use_custom_domain, true)

      Application.put_env(
        :ysc,
        :s3_media_public_url,
        "https://assets.example.com"
      )

      Application.put_env(:ysc, :s3_avatars_public_url, "   ")
      Application.delete_env(:ysc, :s3_expense_reports_public_url)

      sources = S3Config.storage_csp_connect_sources()

      assert "https://assets.example.com" in sources
      assert length(sources) == 1
    end

    test "includes a non-default port in the connect origin" do
      previous = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_media_public_url)
        else
          Application.put_env(:ysc, :s3_media_public_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_media_public_url,
        "https://assets.example.com:8443"
      )

      assert "https://assets.example.com:8443" in S3Config.storage_csp_connect_sources()
    end

    test "drops a public URL without a parseable scheme/host" do
      previous = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_media_public_url)
        else
          Application.put_env(:ysc, :s3_media_public_url, previous)
        end
      end)

      # No scheme, so custom_public_base_url/1 accepts it (non-empty, not a
      # Tigris host) but csp_connect_origin/1 cannot derive an origin from it.
      Application.put_env(:ysc, :s3_media_public_url, "assets.example.com")

      refute Enum.any?(
               S3Config.storage_csp_connect_sources(),
               &String.contains?(&1, "assets.example.com")
             )
    end
  end

  describe "upload_url/0 with S3_USE_CUSTOM_DOMAIN" do
    test "uses the media public URL verbatim when the flag is true" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_pub = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end

        if previous_pub == nil do
          Application.delete_env(:ysc, :s3_media_public_url)
        else
          Application.put_env(:ysc, :s3_media_public_url, previous_pub)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)
      Application.put_env(:ysc, :s3_media_public_url, "https://assets.ysc.org")

      assert S3Config.upload_url() == "https://assets.ysc.org"
    end

    test "raises when the flag is true but the media public URL is missing" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_pub = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        if previous_flag == nil do
          Application.delete_env(:ysc, :s3_use_custom_domain)
        else
          Application.put_env(:ysc, :s3_use_custom_domain, previous_flag)
        end

        if previous_pub == nil do
          Application.delete_env(:ysc, :s3_media_public_url)
        else
          Application.put_env(:ysc, :s3_media_public_url, previous_pub)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)
      Application.delete_env(:ysc, :s3_media_public_url)

      assert_raise ArgumentError, fn -> S3Config.upload_url() end
    end
  end

  describe "tigris_scheme_and_port_frag (via upload_url/0)" do
    test "omits the fragment when the scheme's default port is used (http/80)" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "http://fly.storage.tigris.dev")
      bucket = S3Config.bucket_name()

      assert S3Config.upload_url() ==
               "http://#{bucket}.fly.storage.tigris.dev"
    end

    test "includes a non-default explicit port in the fragment" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_base_url,
        "https://fly.storage.tigris.dev:8443"
      )

      bucket = S3Config.bucket_name()

      assert S3Config.upload_url() ==
               "https://#{bucket}.fly.storage.tigris.dev:8443"
    end

    test "falls back to https with no port fragment for an unrecognized scheme" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(
        :ysc,
        :s3_base_url,
        "customproto://fly.storage.tigris.dev"
      )

      bucket = S3Config.bucket_name()

      assert S3Config.upload_url() ==
               "https://#{bucket}.fly.storage.tigris.dev"
    end
  end

  describe "server_side_encryption?/0" do
    test "is true when the base URL points at Tigris" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "https://fly.storage.tigris.dev")
      assert S3Config.server_side_encryption?()
    end

    test "is false for a non-Tigris base URL (e.g. MinIO)" do
      previous = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous)
        end
      end)

      Application.put_env(:ysc, :s3_base_url, "http://localhost:9000")
      refute S3Config.server_side_encryption?()
    end
  end

  describe "object_url/2 additional branches" do
    test "uses the public URL verbatim when custom domain flag is true" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)
      previous_pub = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_use_custom_domain, previous_flag},
              {:s3_bucket, previous_bucket},
              {:s3_media_public_url, previous_pub}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)
      Application.put_env(:ysc, :s3_bucket, "media-bucket")
      Application.put_env(:ysc, :s3_media_public_url, "https://assets.ysc.org")

      assert S3Config.object_url("k.jpg", "media-bucket") ==
               "https://assets.ysc.org/k.jpg"
    end

    test "raises when custom domain flag is true but the bucket's public URL is invalid" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)
      previous_pub = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_use_custom_domain, previous_flag},
              {:s3_bucket, previous_bucket},
              {:s3_media_public_url, previous_pub}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)
      Application.put_env(:ysc, :s3_bucket, "media-bucket")
      Application.put_env(:ysc, :s3_media_public_url, "   ")

      assert_raise ArgumentError, fn ->
        S3Config.object_url("k.jpg", "media-bucket")
      end
    end

    test "falls back to the Tigris virtual host when base URL is blank and bucket has no public URL" do
      previous_base = Application.get_env(:ysc, :s3_base_url)
      previous_bucket = Application.get_env(:ysc, :s3_bucket)
      previous_pub = Application.get_env(:ysc, :s3_media_public_url)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_base_url, previous_base},
              {:s3_bucket, previous_bucket},
              {:s3_media_public_url, previous_pub}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.delete_env(:ysc, :s3_media_public_url)
      Application.put_env(:ysc, :s3_base_url, "")
      Application.put_env(:ysc, :s3_bucket, "blank-base-bucket")

      assert S3Config.object_url("k.jpg", "blank-base-bucket") ==
               "https://blank-base-bucket.fly.storage.tigris.dev/k.jpg"
    end
  end

  describe "expense_report_file_presigned_url_args/2 with S3_USE_CUSTOM_DOMAIN" do
    test "uses trimmed_nonempty_public_url check when the flag is true" do
      previous_flag = Application.get_env(:ysc, :s3_use_custom_domain)
      previous_pub = Application.get_env(:ysc, :s3_expense_reports_public_url)

      on_exit(fn ->
        for {k, v} <- [
              {:s3_use_custom_domain, previous_flag},
              {:s3_expense_reports_public_url, previous_pub}
            ] do
          if v == nil,
            do: Application.delete_env(:ysc, k),
            else: Application.put_env(:ysc, k, v)
        end
      end)

      Application.put_env(:ysc, :s3_use_custom_domain, true)

      Application.put_env(
        :ysc,
        :s3_expense_reports_public_url,
        "https://expenses.ysc.org"
      )

      {_config, :get, host, _path, opts} =
        S3Config.expense_report_file_presigned_url_args("k", 60)

      assert host == "expenses.ysc.org"
      assert opts[:bucket_as_host] == true
    end
  end

  describe "parse_public_http_origin! (via expense_report_file_presigned_url_args/2)" do
    test "raises when the public URL has no host" do
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
        "https:///no-host-here"
      )

      assert_raise ArgumentError, fn ->
        S3Config.expense_report_file_presigned_url_args("k", 60)
      end
    end
  end

  describe "default_base_url (via base_url/0)" do
    test "returns the MinIO URL for the :dev environment" do
      previous_env = Application.get_env(:ysc, :environment)
      previous_base = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous_env == nil do
          Application.delete_env(:ysc, :environment)
        else
          Application.put_env(:ysc, :environment, previous_env)
        end

        if previous_base == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous_base)
        end
      end)

      Application.delete_env(:ysc, :s3_base_url)
      Application.put_env(:ysc, :environment, "dev")

      assert S3Config.base_url() == "http://localhost:9000"
    end

    test "returns the Tigris URL for a deployed environment" do
      previous_env = Application.get_env(:ysc, :environment)
      previous_base = Application.get_env(:ysc, :s3_base_url)

      on_exit(fn ->
        if previous_env == nil do
          Application.delete_env(:ysc, :environment)
        else
          Application.put_env(:ysc, :environment, previous_env)
        end

        if previous_base == nil do
          Application.delete_env(:ysc, :s3_base_url)
        else
          Application.put_env(:ysc, :s3_base_url, previous_base)
        end
      end)

      Application.delete_env(:ysc, :s3_base_url)
      Application.put_env(:ysc, :environment, "prod")

      assert S3Config.base_url() == "https://fly.storage.tigris.dev"
    end
  end
end
