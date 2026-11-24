defmodule Ysc.ExAwsUpgradeTest do
  @moduledoc """
  Guards the ex_aws 2.7.0 → 2.8.1 and ex_aws_s3 2.5.9 → 2.6.0 upgrades.

  2.8.0/2.8.1 patch:

  * EEF-CVE-2026-59697 — IMDSv2 token request no longer follows HTTP redirects
  * EEF-CVE-2026-59698 — S3 keys no longer normalize `..` client-side
  * EEF-CVE-2026-62269 — S3 request paths are percent-encoded so `?` in a key
    cannot start the query string
  * EEF-CVE-2026-120720 — virtual-host bucket names are restricted to
    letters, digits, `.`, `-`, and `_`

  ex_aws_s3 2.6.0 XML-escapes caller-supplied values in request bodies and
  rejects control characters in grant/header options (EEF-CVE-2026-131902,
  62273, 63581, 63582, 63583, 65621, 63585, 63584).

  We upload with configured bucket names and generated keys via
  `ExAws.Request.Req`. `bucket_as_host` is only used with hostnames from
  `Ysc.S3Config`. Do not add these CVEs to `ignore_advisories`.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @ex_aws_changelog Path.expand("../../deps/ex_aws/CHANGELOG.md", __DIR__)
  @ex_aws_s3_mix Path.expand("../../deps/ex_aws_s3/mix.exs", __DIR__)
  @token_provider Path.expand(
                    "../../deps/ex_aws/lib/ex_aws/instance_meta_token_provider.ex",
                    __DIR__
                  )
  @s3_operation Path.expand(
                  "../../deps/ex_aws/lib/ex_aws/operation/s3.ex",
                  __DIR__
                )
  @s3_utils Path.expand("../../deps/ex_aws_s3/lib/ex_aws/s3/utils.ex", __DIR__)

  @ignored_cves [
    "EEF-CVE-2026-59697",
    "EEF-CVE-2026-59698",
    "EEF-CVE-2026-62269",
    "EEF-CVE-2026-120720",
    "EEF-CVE-2026-131902",
    "EEF-CVE-2026-62273",
    "EEF-CVE-2026-63581",
    "EEF-CVE-2026-63582",
    "EEF-CVE-2026-63583",
    "EEF-CVE-2026-65621",
    "EEF-CVE-2026-63585",
    "EEF-CVE-2026-63584"
  ]

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ex_aws)
    {:ok, _} = Application.ensure_all_started(:ex_aws_s3)
    {:module, ExAws} = Code.ensure_loaded(ExAws)
    {:module, ExAws.S3} = Code.ensure_loaded(ExAws.S3)
    :ok
  end

  describe "2.8.1 / 2.6.0 Hex locks" do
    test "locks ex_aws to 2.8.1 and ex_aws_s3 to 2.6.0" do
      assert to_string(Application.spec(:ex_aws, :vsn)) == "2.8.1"
      assert to_string(Application.spec(:ex_aws_s3, :vsn)) == "2.6.0"
    end

    test "mix.exs pins the patched floors" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:ex_aws, "~> 2.8"})
      assert mix_exs =~ ~s({:ex_aws_s3, "~> 2.6"})
      refute mix_exs =~ ~s({:ex_aws, "~> 2.7"})
      refute mix_exs =~ ~s({:ex_aws_s3, "~> 2.5"})
    end

    test "companion lock is 2.8.1 / 2.6.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"ex_aws": {:hex, :ex_aws, "2.8.1"|
      assert lock =~ ~s|"ex_aws_s3": {:hex, :ex_aws_s3, "2.6.0"|
      refute lock =~ ~s|"ex_aws": {:hex, :ex_aws, "2.7.0"|
      refute lock =~ ~s|"ex_aws_s3": {:hex, :ex_aws_s3, "2.5.9"|
    end

    test "does not ignore the patched ex_aws advisories" do
      mix_exs = File.read!(@mix_exs)

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      Enum.each(@ignored_cves, fn cve ->
        refute ignore =~ cve
      end)
    end

    test "request and S3 APIs we use still exist" do
      {:module, ExAws} = Code.ensure_loaded(ExAws)
      {:module, ExAws.S3} = Code.ensure_loaded(ExAws.S3)
      assert function_exported?(ExAws, :request, 1)
      assert function_exported?(ExAws, :request, 2)
      assert function_exported?(ExAws.S3, :put_object, 3)
      assert function_exported?(ExAws.S3, :get_object, 2)
      assert function_exported?(ExAws.S3, :presigned_url, 5)
      assert function_exported?(ExAws.S3, :upload, 3)
    end
  end

  describe "2.8.0 / 2.6.0 changelogs" do
    test "ex_aws documents the 2026-11-24 CVEs" do
      changelog = File.read!(@ex_aws_changelog)
      assert changelog =~ "v2.8.1"
      assert changelog =~ "v2.8.0"
      assert changelog =~ "GHSA-mww9-g5mj-j664"
      assert changelog =~ "GHSA-96q9-mcc7-hqj8"
      assert changelog =~ "GHSA-rcv9-2jx2-63xh"
      assert changelog =~ "no longer follows HTTP redirects"
    end

    test "ex_aws_s3 2.6.0 ships the XML-escape helpers" do
      mix = File.read!(@ex_aws_s3_mix)
      assert mix =~ ~s(@version "2.6.0")

      source = File.read!(@s3_utils)
      assert source =~ "def escape_xml_string"
    end
  end

  describe "security patches in source" do
    test "IMDSv2 token request disables redirect following" do
      source = File.read!(@token_provider)
      assert source =~ "follow_redirect: false"
    end

    test "virtual-host S3 operations validate the bucket name" do
      source = File.read!(@s3_operation)
      assert source =~ "bucket_as_host_allowlist"
    end

    test "S3 utils XML-escape caller-supplied values" do
      source = File.read!(@s3_utils)
      assert source =~ "xml_escape" or source =~ "escape_xml"
    end
  end
end
