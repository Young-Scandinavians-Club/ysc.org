defmodule Ysc.H2UpgradeTest do
  @moduledoc """
  Guards the h2 0.11.0 → 0.12.0 upgrade.

  0.12.0 is a minor: `h2:serve_socket/2` serves HTTP/2 over a socket the
  caller already accepted and handshook (TLS ALPN dispatch or prior-knowledge
  h2c), and the TLS handshake moves from the acceptor into the per-connection
  process so a stalled client cannot block the accept queue.

  We do not call h2 APIs in app code. hackney 4.7.4 drives HTTP/2 through
  `h2_connection` (`start_link/4`, `activate/1`, `wait_connected/2`,
  `send_request_headers/3,4`, `send_data/4,5`, `cancel_stream/2`,
  `consume/3`, `close/1`). webtransport uses `h2:connect/3` and
  `h2:request/4` for WebTransport-over-h2; we do not call that either.
  `serve_socket/2` is unused. Public client APIs are unchanged.
  """
  use ExUnit.Case, async: false

  @h2_src Path.expand("../../deps/h2/src/h2.erl", __DIR__)
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

  describe "0.12.0 Hex lock and public APIs" do
    test "locks the Hex package to 0.12.0" do
      assert to_string(Application.spec(:h2, :vsn)) == "0.12.0"
    end

    test "mix.exs override matches hackney and webtransport" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:h2, "~> 0.12.0", override: true})

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

    test "0.12.0 serve_socket/2 is exported and requires a handler" do
      assert function_exported?(:h2, :serve_socket, 2)

      assert {:error, {:missing_required_option, [:handler]}} =
               :h2.serve_socket(:ignored, %{})
    end
  end

  describe "0.12.0 handshake move and serve_socket stay unused" do
    test "TLS handshake runs in the per-connection process not the acceptor" do
      source = File.read!(@h2_src)

      assert source =~
               "The TLS handshake runs in the spawned connection process"

      assert source =~ "accept_handshake(Sock, Handler, ConnOpts)"
      assert source =~ "ssl:handshake(Socket, ?DEFAULT_TIMEOUT_MS)"
    end

    test "hackney still talks to h2_connection not serve_socket/2" do
      conn = File.read!(@hackney_conn)
      assert conn =~ ~S|h2_connection:start_link(client, Socket, self(), #{})|
      refute conn =~ "serve_socket"
      refute File.read!(@webtransport_h2) =~ "serve_socket"
    end
  end

  describe "0.12.0 h2c client still answers GET" do
    test "start_server/2 plus connect/3 round-trip on prior-knowledge TCP" do
      handler = fn conn, stream_id, _method, _path, _headers ->
        :ok =
          :h2.send_response(conn, stream_id, 200, [
            {<<"content-type">>, <<"text/plain">>}
          ])

        :ok = :h2.send_data(conn, stream_id, "h2-upgrade-ok", true)
      end

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

      assert {:ok, stream_id} =
               :h2.request(conn, "GET", "/", [{<<"host">>, <<"127.0.0.1">>}])

      assert_receive {:h2, ^conn, {:response, ^stream_id, 200, _headers}}, 2_000

      assert_receive {:h2, ^conn, {:data, ^stream_id, "h2-upgrade-ok", true}},
                     2_000
    end
  end
end
