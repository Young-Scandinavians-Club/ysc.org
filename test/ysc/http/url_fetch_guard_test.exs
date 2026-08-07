defmodule Ysc.Http.UrlFetchGuardTest do
  use ExUnit.Case, async: false

  alias Ysc.Http.UrlFetchGuard

  describe "validate_url_for_server_fetch/1" do
    test "rejects non-http(s) schemes" do
      assert {:error, :unsupported_scheme} =
               UrlFetchGuard.validate_url_for_server_fetch("file:///etc/passwd")

      assert {:error, :missing_scheme} =
               UrlFetchGuard.validate_url_for_server_fetch("/relative/path.jpg")
    end

    test "rejects URLs with embedded credentials" do
      assert {:error, :userinfo_not_allowed} =
               UrlFetchGuard.validate_url_for_server_fetch(
                 "http://user:pass@example.com/file.jpg"
               )
    end

    test "rejects localhost hostname" do
      assert {:error, :blocked_host} =
               UrlFetchGuard.validate_url_for_server_fetch(
                 "http://localhost/image.jpg"
               )
    end

    test "allows loopback in test environment (integration with local HTTP servers)" do
      assert :ok ==
               UrlFetchGuard.validate_url_for_server_fetch(
                 "http://127.0.0.1:9/x.jpg"
               )
    end

    test "in prod mode rejects loopback literal IP" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        assert {:error, :blocked_ip} =
                 UrlFetchGuard.validate_url_for_server_fetch(
                   "http://127.0.0.1:9/x.jpg"
                 )
      end)
    end

    test "rejects URLs with no host" do
      assert {:error, :missing_host} =
               UrlFetchGuard.validate_url_for_server_fetch("http:///path")
    end

    test "allows plain domain names (non-IP-literal hosts) in test environment" do
      assert :ok ==
               UrlFetchGuard.validate_url_for_server_fetch(
                 "http://example.com/img.jpg"
               )
    end
  end

  describe "validate_url_for_server_fetch/1 in prod mode (private/special-use IPv4 literals)" do
    test "blocks the various private/special-use IPv4 ranges" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        for host <- [
              "0.0.0.0",
              "10.0.0.1",
              "192.168.1.1",
              "172.16.0.1",
              "169.254.1.1",
              "100.64.0.1",
              "255.255.255.255",
              "224.0.0.1"
            ] do
          result =
            UrlFetchGuard.validate_url_for_server_fetch("http://#{host}/x.jpg")

          assert result == {:error, :blocked_ip},
                 "expected #{host} to be blocked, got: #{inspect(result)}"
        end
      end)
    end
  end

  describe "validate_url_for_server_fetch/1 in prod mode (private/special-use IPv6 literals)" do
    test "blocks loopback, unique-local, link-local, multicast, and IPv4-mapped-private IPv6 literals" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        for host <- [
              "[::1]",
              "[fc00::1]",
              "[fe80::1]",
              "[ff02::1]",
              "[::ffff:10.0.0.1]"
            ] do
          result =
            UrlFetchGuard.validate_url_for_server_fetch("http://#{host}/x.jpg")

          assert result == {:error, :blocked_ip},
                 "expected #{host} to be blocked, got: #{inspect(result)}"
        end
      end)
    end
  end

  describe "validate_url_for_server_fetch/1 in prod mode (real DNS resolution)" do
    @describetag :external_dns

    test "returns dns_resolution_failed for a public IPv6 literal (literal-IP check passes, DNS lookup fails)" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        assert {:error, :dns_resolution_failed} =
                 UrlFetchGuard.validate_url_for_server_fetch(
                   "http://[2001:4860:4860::8888]/x.jpg"
                 )
      end)
    end

    test "rejects hosts whose DNS resolution fails" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        assert {:error, :dns_resolution_failed} =
                 UrlFetchGuard.validate_url_for_server_fetch(
                   "http://nonexistent-domain-abc123xyz.invalid/x.jpg"
                 )
      end)
    end

    test "allows a domain that resolves only to public addresses" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        assert :ok ==
                 UrlFetchGuard.validate_url_for_server_fetch(
                   "http://one.one.one.one/x.jpg"
                 )
      end)
    end

    test "rejects a domain that resolves to a private/loopback address" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        assert {:error, :blocked_resolved_ip} =
                 UrlFetchGuard.validate_url_for_server_fetch(
                   "http://127.0.0.1.nip.io/x.jpg"
                 )
      end)
    end
  end
end
