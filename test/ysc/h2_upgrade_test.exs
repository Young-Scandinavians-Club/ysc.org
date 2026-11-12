defmodule Ysc.H2UpgradeTest do
  @moduledoc """
  Guards the h2 0.15.0 → 0.15.1 upgrade (pulled by hackney 4.10.2).

  0.15.1 tells the owner and stream handlers the peer is gone before
  the socket closes, and TLS close no longer waits ~5s for the peer.
  0.15.0 optional `notify_stream_available` (off by default) is
  unchanged. We do not start h2 servers in production. hackney 4.10.2
  still calls `h2_connection:start_link/4` with `connection_window_size`
  32 MiB and `notify_stream_available => true`. Public client APIs are
  unchanged. Do not take 0.16.0: hackney still lists `h2 ~> 0.15.0`.
  """
  use ExUnit.Case, async: false

  @h2_src Path.expand("../../deps/h2/src/h2.erl", __DIR__)
  @h2_connection_src Path.expand("../../deps/h2/src/h2_connection.erl", __DIR__)
  @h2_client_src Path.expand("../../deps/h2/src/h2_client.erl", __DIR__)
  @h2_changelog Path.expand("../../deps/h2/CHANGELOG.md", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @hackney_rebar Path.expand("../../deps/hackney/rebar.config", __DIR__)
  @hackney_conn Path.expand("../../deps/hackney/src/hackney_conn.erl", __DIR__)
  @webtransport_rebar Path.expand(
                        "../../deps/webtransport/rebar.config",
                        __DIR__
                      )
  @webtransport_h2 Path.expand(
                     "../../deps/webtransport/src/webtransport_h2.erl",
                     __DIR__
                   )
  @hackney_h2_stream Path.expand(
                       "../../deps/hackney/src/hackney_h2_stream.erl",
                       __DIR__
                     )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:h2)
    {:module, :h2} = Code.ensure_loaded(:h2)
    {:module, :h2_connection} = Code.ensure_loaded(:h2_connection)
    :ok
  end

  describe "0.15.1 Hex lock and public APIs" do
    test "locks the Hex package to 0.15.1" do
      assert to_string(Application.spec(:h2, :vsn)) == "0.15.1"
    end

    test "companion lock is 0.15.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"h2": {:hex, :h2, "0.15.1"|
      refute lock =~ ~s|"h2": {:hex, :h2, "0.15.0"|
    end

    test "mix.exs override matches hackney and webtransport" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:h2, "~> 0.15.1", override: true}|
      refute mix_exs =~ ~s|{:h2, "~> 0.15.0", override: true}|

      assert File.read!(@hackney_rebar) =~ ~s|{h2, "~>0.15.0"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{h2, "~> 0.15.1"}|
    end

    test "client APIs hackney and webtransport use still exist" do
      assert {:module, _} = Code.ensure_loaded(:h2)
      assert function_exported?(:h2, :connect, 2)
      assert function_exported?(:h2, :connect, 3)
      assert function_exported?(:h2, :wait_connected, 1)
      assert function_exported?(:h2, :wait_connected, 2)
      assert function_exported?(:h2, :request, 4)
      assert function_exported?(:h2, :request, 5)
      assert function_exported?(:h2, :send_data, 4)
      assert function_exported?(:h2, :send_data, 5)
      assert function_exported?(:h2, :close, 1)
      assert function_exported?(:h2, :set_stream_handler, 3)
      assert function_exported?(:h2, :cancel, 2)
      assert function_exported?(:h2, :cancel, 3)
      assert function_exported?(:h2, :goaway, 1)
      assert function_exported?(:h2, :goaway, 2)
      assert function_exported?(:h2, :send_trailers, 3)
      assert function_exported?(:h2, :send_response, 4)
      assert function_exported?(:h2, :send_response, 5)
      assert function_exported?(:h2, :respond, 5)
      assert function_exported?(:h2, :peercert, 1)
      assert function_exported?(:h2, :connection_info, 1)

      assert {:module, _} = Code.ensure_loaded(:h2_connection)
      assert function_exported?(:h2_connection, :start_link, 3)
      assert function_exported?(:h2_connection, :start_link, 4)
      assert function_exported?(:h2_connection, :activate, 1)
      assert function_exported?(:h2_connection, :wait_connected, 2)
      assert function_exported?(:h2_connection, :send_request_headers, 3)
      assert function_exported?(:h2_connection, :send_request_headers, 4)
      assert function_exported?(:h2_connection, :send_data, 4)
      assert function_exported?(:h2_connection, :send_data, 5)
      assert function_exported?(:h2_connection, :cancel_stream, 2)
      assert function_exported?(:h2_connection, :consume, 3)
      assert function_exported?(:h2_connection, :close, 1)
    end

    test "0.12.0 serve_socket/2 is still exported and requires a handler" do
      assert {:module, _} = Code.ensure_loaded(:h2)
      assert function_exported?(:h2, :serve_socket, 2)

      assert {:error, {:missing_required_option, [:handler]}} =
               :h2.serve_socket(:ignored, %{})
    end
  end

  describe "0.12.1 decode rejected HEADERS before drop" do
    test "connection source decodes discarded HEADERS for HPACK (RFC 9113 §4.3)" do
      source = File.read!(@h2_connection_src)

      assert source =~ "RFC 9113 §4.3: every field block updates the HPACK"
      assert source =~ "discarded_block ::"

      assert source =~
               "reject_header_block(StreamId, protocol_error, HeaderBlock, EndHeaders, State)"

      assert source =~
               "reject_header_block(StreamId, stream_closed, HeaderBlock, EndHeaders, State)"

      assert source =~ "reject_header_block(StreamId, refused_stream,"
      assert source =~ "decode_discarded_block("

      refute source =~
               ~S|handle_frame(_StateName, {headers, StreamId, _HeaderBlock, _EndStream, _EndHeaders,|
    end

    test "changelog documents the RST_STREAM HPACK desync fix" do
      changelog = File.read!(@h2_changelog)

      assert changelog =~ "## [0.12.1] - 2026-09-21"
      assert changelog =~ "RFC 9113 §4.3"
      assert changelog =~ "COMPRESSION_ERROR"
      assert changelog =~ "RST_STREAM"
    end

    test "hackney still talks to h2_connection not serve_socket/2" do
      conn = File.read!(@hackney_conn)

      assert conn =~
               ~S|h2_connection:start_link(client, Socket, self(), H2Opts)|

      refute conn =~ "serve_socket"
      refute File.read!(@webtransport_h2) =~ "serve_socket"
      refute File.read!(@h2_src) =~ "reject_header_block"
    end
  end

  describe "0.12.2 owner close message" do
    test "docs and CLI match {closed, Reason} that h2_connection actually sends" do
      assert File.read!(@h2_src) =~ ~S|{h2, Conn, {closed, Reason}}|
      refute File.read!(@h2_src) =~ ~S|{h2, Conn, closed}'|

      client = File.read!(@h2_client_src)
      assert client =~ "{h2, Conn, {closed, Reason}}"
      refute client =~ "{h2, Conn, closed}"

      changelog = File.read!(@h2_changelog)
      assert changelog =~ "## [0.12.2] - 2026-09-24"
      assert changelog =~ "{h2, Conn, {closed, Reason}}"
    end

    test "hackney already handles {closed, Reason}" do
      assert File.read!(@hackney_conn) =~ "handle_h2_event({closed, Reason}"
    end

    test "owner receives {closed, Reason} not a bare closed atom" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-closed-ok", true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-closed-ok", true}},
                     2_000

      assert :ok = :h2.close(conn)
      assert_receive {:h2, ^conn, {:closed, _reason}}, 2_000
      refute_received {:h2, ^conn, :closed}
    end
  end

  describe "0.12.3 SETTINGS_INITIAL_WINDOW_SIZE drains buffered DATA" do
    test "connection source flushes send buffers when the initial window grows" do
      source = File.read!(@h2_connection_src)

      assert source =~ "RFC 9113 §6.9.2: a larger initial window"
      assert source =~ "can unblock data already buffered on"
      assert source =~ "window_grew(OldSettings, MergedSettings)"
      assert source =~ "true -> flush_send_buffers(State1)"

      assert source =~
               "window_grew(OldSettings, NewSettings) ->"

      changelog = File.read!(@h2_changelog)
      assert changelog =~ "## [0.12.3] - 2026-09-24"
      assert changelog =~ "SETTINGS_INITIAL_WINDOW_SIZE"
      assert changelog =~ "RFC 9113 §6.9.2"
      assert changelog =~ "WINDOW_UPDATE"

      # h2 has no public API to send SETTINGS after connect; the drain path
      # is covered by the source assertions above. The client IWS=0 test
      # below proves the zero-window stall that 0.12.3 unblocks.
    end

    test "client initial_window_size 0 delivers HEADERS and buffers DATA" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        assert :ok = :h2.send_data(conn, stream_id, "h2-window-ok", true)
      end

      {server, port} = start_h2c_server(handler)

      assert {:ok, conn} =
               :h2.connect("127.0.0.1", port, %{
                 transport: :tcp,
                 settings: %{initial_window_size: 0}
               })

      true = Process.unlink(conn)

      on_exit(fn ->
        if Process.alive?(conn) do
          try do
            :h2.close(conn)
          catch
            :exit, _ -> :ok
          end
        end

        try do
          :h2.stop_server(server)
        catch
          :exit, _ -> :ok
        end
      end)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000
      refute_receive {:h2, ^conn, {:data, ^stream_id, _, _}}, 150
      assert Process.alive?(conn)
    end
  end

  describe "0.12.4 GOAWAY keeps existing streams alive" do
    test "changelog documents RFC 9113 §6.8 dispatcher and sticky goaway_received" do
      changelog = File.read!(@h2_changelog)

      v0124 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.12.4]"))

      assert v0124
      assert v0124 =~ "RFC 9113 §6.8"
      assert v0124 =~ "goaway_received"
      assert v0124 =~ "{error, goaway_received}"
      assert v0124 =~ "per-stream calls now share one dispatcher"
      assert v0124 =~ "h2:goaway/1,2"
      refute v0124 =~ "Breaking"
    end

    test "connection source dispatches per-stream calls in goaway states" do
      source = File.read!(@h2_connection_src)

      assert source =~ "handle_stream_call(From, {cancel_stream,"
      assert source =~ "handle_stream_call(From, {send_trailers,"
      assert source =~ "handle_stream_call(From, {send_response,"
      assert source =~ "handle_stream_call(From, {respond,"

      assert source =~
               "next_frame_state(goaway_received, _NewStateName) -> goaway_received"

      assert source =~ "determine_state_transition(goaway_received, State) ->"

      assert source =~
               "{keep_state, State, [{reply, From, {error, goaway_received}}]}"
    end

    test "hackney still cancels streams and sends trailers on h2_connection" do
      assert File.read!(@hackney_conn) =~
               "h2_connection:cancel_stream(H2Conn, StreamId)"

      assert File.read!(@hackney_h2_stream) =~
               "h2_connection:send_trailers(H2Conn, Sid, Trailers)"

      assert File.read!(@hackney_h2_stream) =~
               "h2_connection:cancel_stream(H2Conn, Sid)"
    end

    test "server can still respond after sending GOAWAY; client refuses new requests" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        assert :ok = :h2.goaway(conn)

        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-goaway-ok", true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:goaway, _last, _code}}, 2_000

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-goaway-ok", true}},
                     2_000

      assert {:error, :goaway_received} =
               :h2.request(conn, "GET", "/again", [
                 {<<"host">>, <<"127.0.0.1">>}
               ])

      # The connection must stay up after a received GOAWAY so in-flight
      # streams can finish. A subsequent goaway/1 from this side may then
      # tear the process down (RFC 9113 §6.8); do not assert alive after.
      assert Process.alive?(conn)
      assert :ok = :h2.goaway(conn)
    end

    test "client can cancel an existing stream after the peer GOAWAY" do
      test_pid = self()

      handler = fn conn, stream_id, _method, _path, _headers ->
        send(test_pid, {:server_ready, conn, self(), stream_id})

        receive do
          :stop -> :ok
        after
          2_000 -> :ok
        end
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:server_ready, server_conn, handler_pid, _sid}, 2_000
      assert :ok = :h2.goaway(server_conn)
      assert_receive {:h2, ^conn, {:goaway, _last, _code}}, 2_000
      assert :ok = :h2.cancel(conn, stream_id)
      assert Process.alive?(conn)
      send(handler_pid, :stop)
    end
  end

  describe "0.12.5 connection_window_size" do
    test "changelog documents the optional window and keeps the 64 KB default" do
      changelog = File.read!(@h2_changelog)

      v0125 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.12.5]"))

      assert v0125
      assert v0125 =~ "connection_window_size"
      assert v0125 =~ "Default stays 64 KB"
      assert v0125 =~ "initial_window_size"
      refute v0125 =~ "Breaking"
    end

    test "public types and connect opts forward connection_window_size" do
      source = File.read!(@h2_src)

      assert source =~ "connection_window_size => 65535..2147483647"

      assert source =~
               "maps:with([settings, connection_window_size, notify_peer_settings,"

      assert source =~
               "maps:merge(maps:with([connection_window_size, notify_peer_settings], Opts),"
    end

    test "connection source validates, grants, and refills the target window" do
      source = File.read!(@h2_connection_src)

      assert source =~
               "{error, {invalid_option, {connection_window_size, V}}}"

      assert source =~
               "recv_conn_window_target = maps:get(connection_window_size, Opts,"

      assert source =~ "grow_conn_window("
      assert source =~ "h2_frame:window_update(0, Target - Window)"

      assert source =~
               "maybe_send_conn_window_update(_DataSize, #state{recv_conn_window_size = ConnWindow,"
    end

    test "hackney raises the connection window; webtransport still omits it" do
      conn = File.read!(@hackney_conn)

      assert conn =~
               ~S|H2Opts = #{settings => #{initial_window_size => ?H2_STREAM_WINDOW},|

      assert conn =~ ~S|connection_window_size => ?H2_CONN_WINDOW,|
      assert conn =~ ~S|notify_stream_available => true}|

      assert conn =~
               ~S|h2_connection:start_link(client, Socket, self(), H2Opts)|

      assert conn =~ "-define(H2_STREAM_WINDOW, 8 * 1024 * 1024)."
      assert conn =~ "-define(H2_CONN_WINDOW, 32 * 1024 * 1024)."
      refute File.read!(@webtransport_h2) =~ "connection_window_size"
    end

    test "invalid connection_window_size values are rejected" do
      {:module, _} = Code.ensure_loaded(:h2_connection)

      {:ok, lsock} =
        :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])

      try do
        for v <- [0, 65_534, 2_147_483_648, :big] do
          assert {:error, {:invalid_option, {:connection_window_size, ^v}}} =
                   :h2_connection.start_link(:client, lsock, %{
                     connection_window_size: v
                   })
        end
      after
        :gen_tcp.close(lsock)
      end
    end

    test "a larger connection_window_size still round-trips a small body" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-conn-window-ok", true)
      end

      {server, port} = start_h2c_server(handler)

      assert {:ok, conn} =
               :h2.connect("127.0.0.1", port, %{
                 transport: :tcp,
                 connection_window_size: 131_070,
                 settings: %{initial_window_size: 131_070}
               })

      true = Process.unlink(conn)

      on_exit(fn ->
        if Process.alive?(conn) do
          try do
            :h2.close(conn)
          catch
            :exit, _ -> :ok
          end
        end

        try do
          :h2.stop_server(server)
        catch
          :exit, _ -> :ok
        end
      end)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn,
                      {:data, ^stream_id, "h2-conn-window-ok", true}},
                     2_000
    end
  end

  describe "0.12.0 handshake move stays unused" do
    test "TLS handshake runs in the per-connection process not the acceptor" do
      source = File.read!(@h2_src)

      assert source =~
               "The TLS handshake runs in the spawned connection process"

      assert source =~ "accept_handshake(Sock, Handler, ConnOpts)"
      assert source =~ "ssl:handshake(Socket, ?DEFAULT_TIMEOUT_MS)"
    end
  end

  describe "0.12.1 h2c client" do
    test "start_server/2 plus connect/3 round-trip on prior-knowledge TCP" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-upgrade-ok", true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-upgrade-ok", true}},
                     2_000
    end

    test "HEADERS after RST_STREAM still leave the connection usable" do
      test_pid = self()

      handler = fn conn, stream_id, _method, path, _headers ->
        if path == "/slow" do
          # Block the connection process until the client has RST_STREAM'd so
          # HEADERS land on a reset stream — the 0.12.1 race.
          send(test_pid, {:slow_ready, self()})

          receive do
            :send_headers -> :ok
          after
            2_000 -> :ok
          end
        end

        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>},
            {<<"x-h2-upgrade">>, <<"ok">>}
          ])

        body = if path == "/slow", do: "h2-slow", else: "h2-fast"
        :ok = :h2.send_data(conn, stream_id, body, true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, slow_id} =
               :h2.request(conn, "GET", "/slow", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:slow_ready, server_conn}, 2_000
      assert :ok = :h2.cancel(conn, slow_id)
      send(server_conn, :send_headers)

      assert Process.alive?(conn)

      assert {:ok, fast_id} =
               :h2.request(conn, "GET", "/fast", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^fast_id, 200, headers}}, 2_000
      assert {<<"content-type">>, <<"text/plain">>} in headers
      assert_receive {:h2, ^conn, {:data, ^fast_id, "h2-fast", true}}, 2_000
      assert Process.alive?(conn)
    end
  end

  describe "0.12.6 extension settings" do
    test "changelog and encoder keep raw integer setting keys" do
      changelog = File.read!(@h2_changelog)

      v0126 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.12.6]"))

      assert v0126
      assert v0126 =~ "16#2b67"
      refute v0126 =~ "Breaking"

      source = File.read!(@h2_connection_src)
      assert source =~ ~S|settings_to_list(#{16#2b67 => 1, enable_push => 0,|
    end
  end

  describe "0.12.7 MadeYouReset" do
    test "changelog documents CVE-2025-8671 and the per-second reset cap" do
      changelog = File.read!(@h2_changelog)

      v0127 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.12.7]"))

      assert v0127
      assert v0127 =~ "MadeYouReset"
      assert v0127 =~ "CVE-2025-8671"
      assert v0127 =~ "max_concurrent_streams"
      refute v0127 =~ "Breaking"
    end

    test "connection source caps sent RST_STREAM frames for peer abuse" do
      source = File.read!(@h2_connection_src)
      assert source =~ "-define(SENT_RST_FLOOD_LIMIT_PER_SEC, 100)."
      assert source =~ "MadeYouReset (CVE-2025-8671)"
      assert source =~ "over_sent_rst_budget("
      assert source =~ "sent_rst(StreamId, ErrorCode,"
    end
  end

  describe "0.13.0 SETTINGS flood" do
    test "changelog documents CVE-2019-9515 and the 20-per-second cap" do
      changelog = File.read!(@h2_changelog)

      v0130 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.13.0]"))

      assert v0130
      assert v0130 =~ "SETTINGS flood"
      assert v0130 =~ "CVE-2019-9515"
      assert v0130 =~ "20 SETTINGS frames per second"
      assert v0130 =~ "notify_peer_settings"
      assert v0130 =~ "connection_info/1"
      refute v0130 =~ "Breaking"
    end

    test "connection source counts SETTINGS like PING and GOAWAYs past the cap" do
      source = File.read!(@h2_connection_src)
      assert source =~ "-define(SETTINGS_FLOOD_LIMIT_PER_SEC, 20)."
      assert source =~ "settings_flood = {0, 0}"
      assert source =~ "bump_flood_counter(settings, State)"
      assert source =~ "flood        -> {error, enhance_your_calm, State}"
    end

    test "notify_peer_settings stays off; h2c round-trip still works" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-settings-ok", true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-settings-ok", true}},
                     2_000

      refute_received {:h2, ^conn, {:peer_settings, _}}
    end
  end

  describe "0.14.0 peercert and connection_info" do
    test "changelog documents peercert/1 and listen-socket ownership" do
      changelog = File.read!(@h2_changelog)

      v0140 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.14.0]"))

      assert v0140
      assert v0140 =~ "h2:peercert/1"
      assert v0140 =~ "stop_server/1"
      refute v0140 =~ "Breaking"
    end

    test "h2c reports tcp transport and has no peer certificate" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-info-ok", true)
      end

      {_server, conn} = start_h2c_client(handler)

      assert {:ok, %{transport: :tcp}} = :h2.connection_info(conn)
      assert {:error, :no_peercert} = :h2.peercert(conn)

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-info-ok", true}},
                     2_000
    end
  end

  describe "0.15.0 notify_stream_available" do
    test "changelog documents the opt-in client option" do
      changelog = File.read!(@h2_changelog)

      v0150 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.15.0]"))

      assert v0150
      assert v0150 =~ "notify_stream_available"
      assert v0150 =~ "Off by default"
      refute v0150 =~ "Breaking"
    end

    test "option defaults to false; hackney opts in" do
      source = File.read!(@h2_connection_src)
      assert source =~ "notify_stream_available = false :: boolean()"
      assert source =~ "maps:get(notify_stream_available, Opts, false) =:= true"

      conn = File.read!(@hackney_conn)
      assert conn =~ "notify_stream_available => true"
      assert conn =~ "handle_h2_event(stream_available, Data)"
    end
  end

  describe "0.15.1 TLS close without waiting for the peer" do
    test "changelog documents the five-second close delay fix" do
      changelog = File.read!(@h2_changelog)

      v0151 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.15.1]"))

      assert v0151
      assert v0151 =~ "five seconds"
      assert v0151 =~ "TLS"
      refute v0151 =~ "Breaking"
    end

    test "terminate notifies owner and handlers before closing the socket" do
      source = File.read!(@h2_connection_src)

      assert source =~
               "notify_owner({h2, self(), {closed, PeeledReason}}, State)"

      assert source =~ "notify_all_handlers({closed, PeeledReason}, State)"

      assert source =~
               "Close last, so a slow close never delays the notifications"
    end

    test "ssl close shuts down both directions instead of waiting 5s" do
      source = File.read!(@h2_connection_src)
      assert source =~ "ssl:close/1 sends close_notify, then waits up to 5 s"
      assert source =~ "ssl:shutdown(Socket, read_write)"
    end
  end

  defp start_h2c_server(handler) do
    assert {:ok, server} =
             :h2.start_server(0, %{
               transport: :tcp,
               acceptors: 1,
               ip: {127, 0, 0, 1},
               handler: handler
             })

    port = :h2.server_port(server)
    assert is_integer(port) and port > 0
    {server, port}
  end

  defp start_h2c_client(handler) do
    {server, port} = start_h2c_server(handler)

    assert {:ok, conn} = :h2.connect("127.0.0.1", port, %{transport: :tcp})
    true = Process.unlink(conn)

    on_exit(fn ->
      if Process.alive?(conn) do
        try do
          :h2.close(conn)
        catch
          :exit, _ -> :ok
        end
      end

      try do
        :h2.stop_server(server)
      catch
        :exit, _ -> :ok
      end
    end)

    {server, conn}
  end
end
