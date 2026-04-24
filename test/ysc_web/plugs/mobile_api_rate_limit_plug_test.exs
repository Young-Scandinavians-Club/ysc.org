defmodule YscWeb.Plugs.MobileAPIRateLimitPlugTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias YscWeb.Plugs.MobileAPIRateLimitPlug

  @unique_ip {10, 99, 0, 1}

  setup do
    prev = Application.get_env(:ysc, Ysc.MobileAPIRateLimit, [])
    Application.put_env(:ysc, Ysc.MobileAPIRateLimit, ip_limit: 1)

    on_exit(fn ->
      Application.put_env(:ysc, Ysc.MobileAPIRateLimit, prev)
    end)

    :ok
  end

  test "second request from the same IP within the window is 429" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, @unique_ip)
      |> MobileAPIRateLimitPlug.call([])

    refute conn.halted

    conn2 =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, @unique_ip)
      |> MobileAPIRateLimitPlug.call([])

    assert conn2.halted
    assert conn2.status == 429
    assert [retry] = Plug.Conn.get_resp_header(conn2, "retry-after")
    assert String.to_integer(retry) >= 1
  end
end
