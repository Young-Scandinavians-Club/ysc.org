defmodule Ysc.Tzdata.HttpClientTest do
  use ExUnit.Case, async: true

  alias Ysc.Tzdata.HttpClient

  describe "get/3" do
    test "returns tzdata-compatible status, header list, and binary body" do
      port =
        Ysc.HttpTestServer.ensure_started(Ysc.Tzdata.HttpTestPlug, :tzdata_get)

      url = "http://127.0.0.1:#{port}/tzdata"

      assert {:ok, {200, headers, "IANA tzdata bytes"}} =
               HttpClient.get(url, [], [])

      assert {"content-type", "application/octet-stream"} in headers
      assert {"etag", "release-2024a"} in headers
      assert Enum.all?(headers, fn {k, v} -> is_binary(k) and is_binary(v) end)
    end

    test "forwards request headers to the upstream server" do
      port =
        Ysc.HttpTestServer.ensure_started(
          Ysc.Tzdata.HttpTestPlug,
          :tzdata_echo_headers
        )

      url = "http://127.0.0.1:#{port}/echo-request-headers"
      request_headers = [{"if-none-match", "release-2024a"}]

      assert {:ok, {200, _headers, body}} =
               HttpClient.get(url, request_headers, [])

      assert body =~ "if-none-match=release-2024a"
    end

    test "follow_redirect enables Req redirect handling" do
      port =
        Ysc.HttpTestServer.ensure_started(
          Ysc.Tzdata.HttpTestPlug,
          :tzdata_redirect
        )

      url = "http://127.0.0.1:#{port}/redirect"

      assert {:ok, {200, _headers, "IANA tzdata bytes"}} =
               HttpClient.get(url, [], follow_redirect: true)
    end

    test "propagates transport errors" do
      assert {:error, _reason} =
               HttpClient.get("http://127.0.0.1:1/unreachable", [], [])
    end
  end

  describe "head/3" do
    test "returns tzdata-compatible status and header list without a body" do
      port =
        Ysc.HttpTestServer.ensure_started(Ysc.Tzdata.HttpTestPlug, :tzdata_head)

      url = "http://127.0.0.1:#{port}/tzdata"

      assert {:ok, {304, headers}} = HttpClient.head(url, [], [])
      assert {"last-modified", "Mon, 01 Jan 2024 00:00:00 GMT"} in headers
      assert Enum.all?(headers, fn {k, v} -> is_binary(k) and is_binary(v) end)
    end
  end

  describe "tzdata configuration" do
    test "uses the Req adapter instead of the broken Hackney 4.x client" do
      assert Application.get_env(:tzdata, :http_client) == Ysc.Tzdata.HttpClient
    end
  end
end
