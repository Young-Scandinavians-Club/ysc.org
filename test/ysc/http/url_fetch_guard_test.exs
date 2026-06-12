defmodule Ysc.Http.UrlFetchGuardTest do
  use ExUnit.Case, async: true

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
  end
end
