defmodule Ysc.H2UpgradeTest do
  @moduledoc """
  Guards the h2 0.12.1 → 0.12.3 upgrade.

  0.12.3 drains DATA already buffered on open streams when a SETTINGS frame
  raises `SETTINGS_INITIAL_WINDOW_SIZE` (RFC 9113 §6.9.2). The larger window
  was applied, but nothing flushed the buffers, so a body queued against a
  zero window stalled until an unrelated WINDOW_UPDATE.

  0.12.2 is CLI-only: `h2_client` now matches `{closed, Reason}`.
  `h2_connection` never sent a bare `closed` atom. hackney already handles
  `{closed, Reason}`. We do not run `h2_client`.

  We do not call h2 APIs in app code. hackney 4.7.4 drives HTTP/2 through
  `h2_connection` (`start_link/4`, `activate/1`, `wait_connected/2`,
  `send_request_headers/3,4`, `send_data/4,5`, `cancel_stream/2`,
  `consume/3`, `close/1`). webtransport uses `h2:connect/3` and
  `h2:request/4` for WebTransport-over-h2; we do not call that either.
  `serve_socket/2` is unused. Public client APIs are unchanged.
  """
  use ExUnit.Case, async: false

  @h2_src Path.expand("../../deps/h2/src/h2.erl", __DIR__)
  @h2_connection_src Path.expand("../../deps/h2/src/h2_connection.erl", __DIR__)
  @h2_client_src Path.expand("../../deps/h2/src/h2_client.erl", __DIR__)
  @h2_changelog Path.expand("../../deps/h2/CHANGELOG.md", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
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

  setup_all do
    {:ok, _} = Application.ensure_all_started(:h2)
    {:module, :h2} = Code.ensure_loaded(:h2)
    {:module, :h2_connection} = Code.ensure_loaded(:h2_connection)
    :ok
  end

  describe "0.12.3 Hex lock and public APIs" do
    test "locks the Hex package to 0.12.3" do
      assert to_string(Application.spec(:h2, :vsn)) == "0.12.3"
    end

    test "mix.exs override matches hackney and webtransport" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:h2, "~> 0.12.3", override: true})

      assert File.read!(@hackney_rebar) =~ ~s|{h2, "~>0.12.0"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{h2, "~> 0.12"}|
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
      assert conn =~ ~S|h2_connection:start_link(client, Socket, self(), #{})|
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
