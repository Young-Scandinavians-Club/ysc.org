defmodule YscWeb.Plugs.ClientIPTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Plugs.ClientIP

  test "rewrites remote_ip from Fly-Client-IP when proxy headers are trusted" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {172, 16, 5, 9})
      |> put_req_header("fly-client-ip", "203.0.113.7")
      |> ClientIP.call(ClientIP.init(trust_proxy_headers: true))

    assert conn.remote_ip == {203, 0, 113, 7}
  end

  test "leaves remote_ip alone when proxy headers are not trusted" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("fly-client-ip", "203.0.113.7")
      |> ClientIP.call(ClientIP.init([]))

    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "sets the :remote_ip Logger metadata to the resolved address" do
    Logger.metadata(remote_ip: nil)

    build_conn()
    |> put_req_header("fly-client-ip", "2001:db8::7")
    |> ClientIP.call(ClientIP.init(trust_proxy_headers: true))

    assert Logger.metadata()[:remote_ip] == "2001:db8::7"
  end

  test "passes the conn through untouched when no IP can be resolved" do
    conn = %{build_conn() | remote_ip: nil}
    assert ClientIP.call(conn, ClientIP.init([])) == conn
  end
end
