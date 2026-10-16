defmodule QueryConsole.BanditUpgradeTest do
  @moduledoc """
  Guards the bandit 1.12.5 → 1.13.1 upgrade.

  1.13.0/1.13.1 is a minor. It patches:

  * EEF-CVE-2026-105659 (HIGH / GHSA-69m6-wcv4-rwcf) — HTTP/2 sends blocked
    on a send window are bounded by *progress* (`FlowControl.extend_send_deadline/4`)
    so a trickle of `WINDOW_UPDATE` (or empty SETTINGS) cannot reset the 15s
    deadline and pin stream processes indefinitely.
  * EEF-CVE-2026-105660 (MEDIUM / GHSA-v53v-9hvg-37jf) — HTTP/1 absolute-form
    and authority-form request-target hosts are validated with the same
    grammar as the `Host` header (`parse_target_authority!/2`).

  1.13.1 reverts the 1.13.0 stale-conn check (#668) that broke
  `Phoenix.Endpoint.RenderErrors` for `Plug.Parsers` errors.

  Requires Thousand Island 1.6 (peername cached at accept). We serve Phoenix
  through `Bandit.PhoenixAdapter` and use `bandit_pid/1` plus
  `ThousandIsland.connection_pids/1` for idle shutdown. Public adapter APIs
  are unchanged. We do not call `ThousandIsland.Socket.peername/1`,
  `compress_chunked`, or CONNECT.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @application Path.expand("../../lib/query_console/application.ex", __DIR__)
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
  @pipeline_src Path.expand("../../deps/bandit/lib/bandit/pipeline.ex", __DIR__)
  @flow_src Path.expand(
              "../../deps/bandit/lib/bandit/http2/flow_control.ex",
              __DIR__
            )
  @headers_src Path.expand("../../deps/bandit/lib/bandit/headers.ex", __DIR__)
  @changelog Path.expand("../../deps/bandit/CHANGELOG.md", __DIR__)
  @ti_changelog Path.expand("../../deps/thousand_island/CHANGELOG.md", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)
    {:module, Bandit} = Code.ensure_loaded(Bandit)
    {:module, Bandit.PhoenixAdapter} = Code.ensure_loaded(Bandit.PhoenixAdapter)
    {:module, Bandit.Headers} = Code.ensure_loaded(Bandit.Headers)
    {:module, Bandit.HTTPError} = Code.ensure_loaded(Bandit.HTTPError)

    {:module, Bandit.HTTP2.Connection} =
      Code.ensure_loaded(Bandit.HTTP2.Connection)

    {:module, Bandit.HTTP2.FlowControl} =
      Code.ensure_loaded(Bandit.HTTP2.FlowControl)

    {:module, ThousandIsland} = Code.ensure_loaded(ThousandIsland)
    :ok
  end

  describe "1.13.1 Hex lock and public APIs" do
    test "locks the Hex package to 1.13.1" do
      assert to_string(Application.spec(:bandit, :vsn)) == "1.13.1"
    end

    test "mix.exs pins the 1.13.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:bandit, "~> 1.13.1"})
    end

    test "companion locks are bandit 1.13.1 and thousand_island 1.6.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"bandit": {:hex, :bandit, "1.13.1"|
      refute lock =~ ~s|"bandit": {:hex, :bandit, "1.12.5"|
      assert lock =~ ~s|"thousand_island": {:hex, :thousand_island, "1.6.0"|
      refute lock =~ ~s|"thousand_island": {:hex, :thousand_island, "1.5.0"|
      assert lock =~ ~s|"hpax": {:hex, :hpax, "1.1.0"|
    end

    test "PhoenixAdapter APIs used for idle shutdown still exist" do
      assert function_exported?(Bandit.PhoenixAdapter, :bandit_pid, 1)
      assert function_exported?(Bandit.PhoenixAdapter, :bandit_pid, 2)
      assert function_exported?(ThousandIsland, :connection_pids, 1)
    end

    test "endpoint still uses the Bandit Phoenix adapter" do
      assert QueryConsoleWeb.Endpoint.config(:adapter) == Bandit.PhoenixAdapter
    end

    test "application still idle-shuts down via bandit_pid and connection_pids" do
      application = File.read!(@application)

      assert application =~
               "Bandit.PhoenixAdapter.bandit_pid(QueryConsoleWeb.Endpoint)"

      assert application =~ "ThousandIsland.connection_pids(bandit_pid)"
      refute application =~ "ThousandIsland.Socket.peername"
    end

    test "Bandit.start_link/1 still exists" do
      assert function_exported?(Bandit, :start_link, 1)
    end
  end

  describe "1.13.0/1.13.1 changelog" do
    test "1.13.1 reverts the stale-conn check and has no Breaking heading" do
      v1313 = changelog_section("1.13.1")
      assert v1313
      assert v1313 =~ "Revert the stale conn check added in 1.13.0"
      assert v1313 =~ "Phoenix.Endpoint.RenderErrors"
      refute v1313 =~ "Breaking"
    end

    test "1.13.0 documents both CVEs and has no Breaking heading" do
      v1310 = changelog_section("1.13.0")
      assert v1310
      assert v1310 =~ "GHSA-69m6-wcv4-rwcf"
      assert v1310 =~ "GHSA-v53v-9hvg-37jf"
      assert v1310 =~ "Require Thousand Island 1.6"
      refute v1310 =~ "Breaking"
    end

    test "Thousand Island 1.6 still exports connection_pids/1" do
      changelog = File.read!(@ti_changelog)
      assert changelog =~ "## 1.6.0"
      assert function_exported?(ThousandIsland, :connection_pids, 1)
      assert function_exported?(ThousandIsland, :status, 1)
    end
  end

  describe "1.13.0 HTTP/2 progress-based send deadline" do
    test "blocked sends extend the deadline in proportion to bytes sent" do
      connection = File.read!(@connection_src)
      stream = File.read!(@stream_src)
      flow = File.read!(@flow_src)
      handler = File.read!(@handler_src)

      assert connection =~ "@pending_send_timeout 15_000"
      assert connection =~ "Bandit.HTTP2.FlowControl.extend_send_deadline("
      assert stream =~ "Bandit.HTTP2.FlowControl.extend_send_deadline("
      assert flow =~ "def extend_send_deadline(deadline, bytes_sent, now, timeout)"
      assert flow =~ "@min_send_rate 1_024"

      refute connection =~
               "expires_at = :erlang.monotonic_time(:millisecond) + @pending_send_timeout"

      assert handler =~
               "Bandit.HTTP2.Connection.expire_pending_sends(state.connection)"
    end

    test "a one-byte trickle does not reset the original 15s deadline" do
      now = 5_000
      timeout = 15_000
      original = 15_000

      extended =
        Bandit.HTTP2.FlowControl.extend_send_deadline(original, 1, now, timeout)

      # credit = div(1 * 1000, 1024) == 0, so the original deadline is kept
      # instead of being rewritten to now + timeout (the 1.12.5 reset).
      assert extended == original
      refute extended == now + timeout
    end

    test "an honest drain at min_send_rate is credited, capped at now + timeout" do
      now = 5_000
      timeout = 15_000
      original = 15_000
      # 10_240 bytes → 10s of credit; min(15_000 + 10_000, 5_000 + 15_000)
      extended =
        Bandit.HTTP2.FlowControl.extend_send_deadline(
          original,
          10_240,
          now,
          timeout
        )

      assert extended == now + timeout
    end

    test "expire_pending_sends/1 still unblocks timed-out sends and keeps live ones" do
      test_pid = self()
      now = :erlang.monotonic_time(:millisecond)

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

  describe "1.13.0 HTTP/1 request-target authority validation" do
    test "pipeline parses the request-target authority with the Host grammar" do
      pipeline = File.read!(@pipeline_src)

      assert pipeline =~ "defp parse_target_authority!(host, port) do"
      assert pipeline =~ "Bandit.Headers.parse_hostlike_header!(IO.iodata_to_binary(authority))"
      assert pipeline =~ "request_error!(\"Request target contains invalid host\")"
    end

    test "parse_hostlike_header!/1 still accepts a host and rejects userinfo" do
      assert Bandit.Headers.parse_hostlike_header!("example.com") ==
               {"example.com", nil}

      assert Bandit.Headers.parse_hostlike_header!("example.com:443") ==
               {"example.com", 443}

      assert_raise Bandit.HTTPError, fn ->
        Bandit.Headers.parse_hostlike_header!("good.example@evil.example")
      end

      assert_raise Bandit.HTTPError, fn ->
        Bandit.Headers.parse_hostlike_header!("example.com:99999")
      end
    end

    test "origin-form GET still answers 200" do
      port = start_echo_listener()
      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
      assert response.body == "bandit-upgrade-ok"
    end

    test "absolute-form userinfo authority is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET http://good.example@evil.example/x HTTP/1.1\r\nHost: good.example\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end

    test "absolute-form out-of-range port is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET http://example.com:99999/x HTTP/1.1\r\nHost: example.com\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end
  end

  describe "1.12.5 HTTP/2 header CR/LF/NUL validation still holds" do
    test "HTTP/2 header reads still reject CR, LF, and NUL field values" do
      stream = File.read!(@stream_src)
      headers = File.read!(@headers_src)

      assert stream =~ "valid_field_values!(headers, stream)"
      assert stream =~ "Field value contains invalid characters (RFC9113§8.2.1)"
      assert headers =~ "char == 0x09 or char in 0x20..0x7E or char in 0x80..0xFF"
    end

    test "field_value_valid?/1 accepts plain values and rejects CR/LF/NUL" do
      assert Bandit.Headers.field_value_valid?("plain-value")
      refute Bandit.Headers.field_value_valid?("aaa\r\nx-injected: yes")
      refute Bandit.Headers.field_value_valid?("line\nfeed")
      refute Bandit.Headers.field_value_valid?("nul\0value")
    end
  end

  defp changelog_section(version) do
    @changelog
    |> File.read!()
    |> String.split("\n## ")
    |> Enum.map(&String.replace_prefix(&1, "## ", ""))
    |> Enum.find(&String.starts_with?(&1, version))
  end

  defp start_echo_listener do
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

    port
  end

  defp raw_http(port, payload) do
    {:ok, sock} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        port,
        [:binary, packet: :raw, active: false],
        5_000
      )

    :ok = :gen_tcp.send(sock, payload)

    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, response} ->
        :gen_tcp.close(sock)
        response

      {:error, reason} ->
        :gen_tcp.close(sock)
        flunk("expected an HTTP response, got #{inspect(reason)}")
    end
  end
end
