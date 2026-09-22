defmodule Ysc.H2UpgradeTest do
  @moduledoc """
  Guards the h2 0.12.0 → 0.12.1 upgrade.

  0.12.1 is a patch: a HEADERS frame rejected with a stream error is decoded
  before it is dropped (RFC 9113 §4.3), including CONTINUATION frames. Skipping
  the block used to leave the HPACK decoder behind the peer's encoder, so the
  next block that referenced the missing dynamic table entries failed with
  COMPRESSION_ERROR and closed the connection. A client hit this when a
  response crossed its own RST_STREAM.

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

  describe "0.12.1 Hex lock and public APIs" do
    test "locks the Hex package to 0.12.1" do
      assert to_string(Application.spec(:h2, :vsn)) == "0.12.1"
    end

    test "mix.exs override matches hackney and webtransport" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:h2, "~> 0.12.1", override: true})

      assert File.read!(@hackney_rebar) =~ ~s|{h2, "~>0.12.0"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{h2, "~> 0.12"}|
    end

    test "client APIs hackney and webtransport use still exist" do
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

  defp start_h2c_client(handler) do
    assert {:ok, server} =
             :h2.start_server(0, %{
               transport: :tcp,
               acceptors: 1,
               ip: {127, 0, 0, 1},
               handler: handler
             })

    port = :h2.server_port(server)
    assert is_integer(port) and port > 0

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
