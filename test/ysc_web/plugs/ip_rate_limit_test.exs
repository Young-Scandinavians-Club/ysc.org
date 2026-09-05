defmodule YscWeb.Plugs.IpRateLimitTest do
  use YscWeb.ConnCase, async: false

  alias YscWeb.Plugs.IpRateLimit

  setup do
    Application.put_env(:ysc, Ysc.AuthRateLimit,
      ip_limit: 1,
      identifier_limit: 10_000
    )

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.AuthRateLimit,
        ip_limit: 10_000,
        identifier_limit: 10_000
      )
    end)

    :ok
  end

  defp call_limited(ip, format) do
    build_conn()
    |> Map.put(:remote_ip, ip)
    |> IpRateLimit.call(limiter: Ysc.AuthRateLimit, format: format)
  end

  describe "call/2" do
    test "allows the first request and returns HTML 429 after the limit" do
      ip = {10, 77, 0, 1}

      allowed = call_limited(ip, :html)
      refute allowed.halted
      refute allowed.status == 429

      limited = call_limited(ip, :html)
      assert limited.halted
      assert limited.status == 429
      [retry_after] = get_resp_header(limited, "retry-after")
      assert String.to_integer(retry_after) > 0
      [content_type] = get_resp_header(limited, "content-type")
      assert content_type =~ "text/html"
      assert limited.resp_body =~ "Too many attempts"
      assert limited.resp_body =~ retry_after
    end

    test "returns JSON 429 for API clients" do
      ip = {10, 77, 0, 2}

      _allowed = call_limited(ip, :json)
      limited = call_limited(ip, :json)

      assert limited.status == 429
      [content_type] = get_resp_header(limited, "content-type")
      assert content_type =~ "application/json"

      assert Jason.decode!(limited.resp_body) == %{
               "error" => "Too many requests"
             }
    end

    test "returns plain-text 429 without a content-type override" do
      ip = {10, 77, 0, 3}

      _allowed = call_limited(ip, :text)
      limited = call_limited(ip, :text)

      assert limited.status == 429
      assert limited.resp_body == "Too many requests"
    end
  end
end
