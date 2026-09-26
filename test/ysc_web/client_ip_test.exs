defmodule YscWeb.ClientIPTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias YscWeb.ClientIP

  @peer {172, 16, 5, 9}
  @trusted [trust_proxy_headers: true]

  describe "resolve/3 when proxy headers are not trusted" do
    test "ignores Fly and Cloudflare headers and uses the peer address" do
      headers = [
        {"fly-client-ip", "203.0.113.7"},
        {"cf-connecting-ip", "198.51.100.1"}
      ]

      assert ClientIP.resolve(headers, @peer, trust_proxy_headers: false) ==
               @peer
    end

    test "defaults to untrusted in the test environment" do
      refute ClientIP.trust_proxy_headers?()

      assert ClientIP.resolve([{"fly-client-ip", "203.0.113.7"}], @peer) ==
               @peer
    end
  end

  describe "resolve/3 behind Fly Proxy" do
    test "uses Fly-Client-IP" do
      assert ClientIP.resolve(
               [{"fly-client-ip", "203.0.113.7"}],
               @peer,
               @trusted
             ) ==
               {203, 0, 113, 7}
    end

    test "ignores X-Forwarded-For (rightmost entry is the app's own Fly IP)" do
      headers = [
        {"x-forwarded-for", "198.51.100.1, 66.241.125.41"},
        {"fly-client-ip", "203.0.113.7"}
      ]

      assert ClientIP.resolve(headers, @peer, @trusted) == {203, 0, 113, 7}
    end

    test "supports IPv6 and normalises IPv4-mapped addresses" do
      assert ClientIP.resolve(
               [{"fly-client-ip", "2001:db8::1"}],
               @peer,
               @trusted
             ) ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}

      assert ClientIP.resolve(
               [{"fly-client-ip", "::ffff:203.0.113.7"}],
               @peer,
               @trusted
             ) ==
               {203, 0, 113, 7}
    end

    test "falls back to the peer when Fly-Client-IP is missing or invalid" do
      # e.g. Prometheus scraping over the Fly private network
      assert ClientIP.resolve([], @peer, @trusted) == @peer

      assert ClientIP.resolve([{"fly-client-ip", "not-an-ip"}], @peer, @trusted) ==
               @peer

      assert ClientIP.resolve(
               [{"fly-client-ip", "1.2.3.4, 5.6.7.8"}],
               @peer,
               @trusted
             ) == @peer
    end

    test "uses CF-Connecting-IP when the Fly client is a Cloudflare edge" do
      headers = [
        {"fly-client-ip", "172.70.1.2"},
        {"cf-connecting-ip", "203.0.113.7"}
      ]

      assert ClientIP.resolve(headers, @peer, @trusted) == {203, 0, 113, 7}

      v6_headers = [
        {"fly-client-ip", "2a06:98c1:3120::3"},
        {"cf-connecting-ip", "2001:db8::42"}
      ]

      assert ClientIP.resolve(v6_headers, @peer, @trusted) ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x42}
    end

    test "keeps the Cloudflare address when CF-Connecting-IP is missing or invalid" do
      assert ClientIP.resolve(
               [{"fly-client-ip", "172.70.1.2"}],
               @peer,
               @trusted
             ) ==
               {172, 70, 1, 2}

      headers = [
        {"fly-client-ip", "172.70.1.2"},
        {"cf-connecting-ip", "garbage"}
      ]

      assert ClientIP.resolve(headers, @peer, @trusted) == {172, 70, 1, 2}
    end

    test "ignores a spoofed CF-Connecting-IP from a client not coming through Cloudflare" do
      headers = [
        {"fly-client-ip", "203.0.113.7"},
        {"cf-connecting-ip", "10.0.0.1"}
      ]

      assert ClientIP.resolve(headers, @peer, @trusted) == {203, 0, 113, 7}
    end
  end

  describe "cloudflare?/1" do
    test "matches range boundaries" do
      assert ClientIP.cloudflare?({173, 245, 48, 0})
      assert ClientIP.cloudflare?({173, 245, 63, 255})
      refute ClientIP.cloudflare?({173, 245, 64, 0})
      assert ClientIP.cloudflare?({104, 16, 0, 1})
      refute ClientIP.cloudflare?({66, 241, 125, 41})
      assert ClientIP.cloudflare?({0x2606, 0x4700, 0, 0, 0, 0, 0, 1})
      refute ClientIP.cloudflare?({0x2606, 0x4701, 0, 0, 0, 0, 0, 1})
    end
  end

  describe "live_session/1 and from_socket/2" do
    test "round-trips the conn's remote_ip through the LiveView session" do
      session =
        ClientIP.live_session(%{build_conn() | remote_ip: {203, 0, 113, 7}})

      assert session == %{"client_ip" => "203.0.113.7"}

      socket = socket_with_peer({127, 0, 0, 1})
      assert ClientIP.from_socket(socket, session) == {203, 0, 113, 7}
    end

    test "falls back to the socket peer, then 0.0.0.0" do
      assert ClientIP.from_socket(socket_with_peer({127, 0, 0, 1}), %{}) ==
               {127, 0, 0, 1}

      assert ClientIP.from_socket(socket_with_peer({127, 0, 0, 1}), %{
               "client_ip" => "bogus"
             }) ==
               {127, 0, 0, 1}

      socket = %Phoenix.LiveView.Socket{private: %{connect_info: %{}}}
      assert ClientIP.from_socket(socket, %{}) == {0, 0, 0, 0}
    end

    test "a mounted LiveView receives the IP resolved for the HTTP request", %{
      conn: conn
    } do
      {:ok, view, _html} =
        live(%{conn | remote_ip: {203, 0, 113, 7}}, ~p"/contact")

      assert %{socket: %{assigns: %{remote_ip: {203, 0, 113, 7}}}} =
               :sys.get_state(view.pid)
    end
  end

  describe "YscWeb.Plugs.ClientIP through the endpoint" do
    setup do
      previous = Application.get_env(:ysc, ClientIP)
      Application.put_env(:ysc, ClientIP, trust_proxy_headers: true)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ysc, ClientIP, previous),
          else: Application.delete_env(:ysc, ClientIP)
      end)
    end

    test "sets conn.remote_ip from Fly-Client-IP", %{conn: conn} do
      conn =
        conn
        |> put_req_header("fly-client-ip", "203.0.113.7")
        |> put_req_header("x-forwarded-for", "203.0.113.7, 66.241.125.41")
        |> get(~p"/up")

      assert conn.remote_ip == {203, 0, 113, 7}
    end

    test "keeps the peer address when Fly-Client-IP is absent", %{conn: conn} do
      conn = get(%{conn | remote_ip: {172, 16, 5, 9}}, ~p"/up")
      assert conn.remote_ip == {172, 16, 5, 9}
    end
  end

  defp socket_with_peer(address) do
    %Phoenix.LiveView.Socket{
      private: %{
        connect_info: %{
          peer_data: %{address: address, port: 4000, ssl_cert: nil}
        }
      }
    }
  end
end
