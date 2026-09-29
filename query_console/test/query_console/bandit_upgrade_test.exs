defmodule QueryConsole.BanditUpgradeTest do
  @moduledoc """
  Guards the bandit 1.12.4 → 1.12.5 upgrade.

  1.12.5 is a patch: HTTP/2 sends blocked on the connection window are
  bounded (15s) and cancelled on RST_STREAM / stream exit
  (EEF-CVE-2026-74836), and HTTP/2 header values containing CR, LF, or
  NUL are rejected (EEF-CVE-2026-75484). Query Console serves Phoenix
  through `Bandit.PhoenixAdapter` and uses `bandit_pid/1` plus
  `ThousandIsland.connection_pids/1` for idle shutdown. Public adapter
  APIs are unchanged.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @connection_src Path.expand(
                    "../../deps/bandit/lib/bandit/http2/connection.ex",
                    __DIR__
                  )
  @handler_src Path.expand(
                 "../../deps/bandit/lib/bandit/http2/handler.ex",
                 __DIR__
               )
  @stream_src Path.expand(
                "../../deps/bandit/lib/bandit/http2/stream.ex",
                __DIR__
              )
  @headers_src Path.expand("../../deps/bandit/lib/bandit/headers.ex", __DIR__)
  @changelog Path.expand("../../deps/bandit/CHANGELOG.md", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)
    {:module, Bandit} = Code.ensure_loaded(Bandit)
    {:module, Bandit.PhoenixAdapter} = Code.ensure_loaded(Bandit.PhoenixAdapter)
    {:module, Bandit.Headers} = Code.ensure_loaded(Bandit.Headers)

    {:module, Bandit.HTTP2.Connection} =
      Code.ensure_loaded(Bandit.HTTP2.Connection)

    {:module, ThousandIsland} = Code.ensure_loaded(ThousandIsland)
    :ok
  end

  describe "1.12.5 Hex lock and public APIs" do
    test "locks the Hex package to 1.12.5" do
      assert to_string(Application.spec(:bandit, :vsn)) == "1.12.5"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:bandit, "~> 1.12.5"})
    end

    test "PhoenixAdapter APIs used for idle shutdown still exist" do
      assert function_exported?(Bandit.PhoenixAdapter, :bandit_pid, 1)
      assert function_exported?(Bandit.PhoenixAdapter, :bandit_pid, 2)
      assert function_exported?(ThousandIsland, :connection_pids, 1)
    end

    test "endpoint still uses the Bandit Phoenix adapter" do
      assert QueryConsoleWeb.Endpoint.config(:adapter) == Bandit.PhoenixAdapter
    end

    test "Bandit.start_link/1 still exists" do
      assert function_exported?(Bandit, :start_link, 1)
    end
  end

  describe "1.12.5 HTTP/2 connection-window starvation fix" do
    test "pending sends carry a 15s expiry and are swept on inbound data" do
      connection = File.read!(@connection_src)
      handler = File.read!(@handler_src)

      assert connection =~ "@pending_send_timeout 15_000"

      assert connection =~
               "expires_at = :erlang.monotonic_time(:millisecond) + @pending_send_timeout"

      assert connection =~ "def expire_pending_sends(connection) do"
      assert connection =~ "on_unblock.({:error, :timeout})"
      assert connection =~ "purge_pending_send(connection, stream_id, {:error, :closed})"

      assert connection =~
               "purge_pending_send(connection, frame.stream_id, {:error, {:rst_stream, frame.error_code}})"

      assert handler =~ "Bandit.HTTP2.Connection.expire_pending_sends(state.connection)"
    end

    test "expire_pending_sends/1 unblocks timed-out sends and keeps live ones" do
      test_pid = self()
      now = :erlang.monotonic_time(:millisecond)

      # monotonic_time/1 is often negative, so an absolute 0 is still "in the
      # future". Expire relative to `now` the way Bandit compares expires_at.
      expired =
        {1, <<"rest">>, false, fn reply -> send(test_pid, {:expired, reply}) end, now - 1}

      live =
        {3, <<"rest">>, true, fn reply -> send(test_pid, {:live, reply}) end, now + 60_000}

      connection = %Bandit.HTTP2.Connection{pending_sends: [expired, live]}
      updated = Bandit.HTTP2.Connection.expire_pending_sends(connection)

      assert updated.pending_sends == [live]
      assert_receive {:expired, {:error, :timeout}}
      refute_received {:live, _}
    end
  end

  describe "1.12.5 HTTP/2 header CR/LF/NUL validation" do
    test "HTTP/2 header reads reject CR, LF, and NUL field values" do
      stream = File.read!(@stream_src)
      headers = File.read!(@headers_src)

      assert stream =~ "valid_field_values!(headers, stream)"
      assert stream =~ "Field value contains invalid characters (RFC9113§8.2.1)"
      assert headers =~ ":binary.compile_pattern([\"\\r\", \"\\n\", \"\\0\"])"
    end

    test "field_value_valid?/1 accepts plain values and rejects CR/LF/NUL" do
      assert Bandit.Headers.field_value_valid?("plain-value")
      refute Bandit.Headers.field_value_valid?("aaa\r\nx-injected: yes")
      refute Bandit.Headers.field_value_valid?("line\nfeed")
      refute Bandit.Headers.field_value_valid?("nul\0value")
    end
  end

  describe "1.12.5 changelog" do
    test "documents both security advisories" do
      changelog = File.read!(@changelog)
      assert changelog =~ "# 1.12.5"
      assert changelog =~ "GHSA-xj8g-532w-jv94"
      assert changelog =~ "GHSA-x3gh-xhj4-3vq8"
    end
  end

  describe "Bandit still serves HTTP" do
    test "Bandit.start_link/1 starts a listener that answers GET" do
      {:ok, socket} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true
        ])

      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      start_supervised!(
        {Bandit,
         plug: QueryConsole.BanditUpgradeEchoPlug,
         scheme: :http,
         port: port,
         ip: {127, 0, 0, 1},
         startup_log: false}
      )

      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
      assert response.body == "bandit-upgrade-ok"
    end
  end
end
