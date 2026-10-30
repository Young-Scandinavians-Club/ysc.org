defmodule QueryConsole.BanditUpgradeTest do
  @moduledoc """
  Guards the bandit 1.14.0 → 1.14.1 upgrade.

  1.14.1 is a patch with no Breaking heading. It collects HTTP/2 request
  bodies into one binary so a body sent as many 1-byte DATA frames cannot
  amplify stream-process memory (EEF-CVE-2026-116078 HIGH /
  GHSA-pxjf-g536-7r93). It also strips connection-specific HTTP/2
  response headers, rejects `host` vs `:authority` mismatch, closes
  HTTP/1 after a 2xx CONNECT, trims HTTP/1 header trailing whitespace,
  parses Accept-Encoding q-values with the RFC 9110 grammar, and rejects
  IPv6 authorities missing the colon before the port.

  1.14.0 remains the HTTP/2 receive-window / HPACK / HTTP/1 request-line
  floor. Defaults stay `max_concurrent_streams` 500 and
  `max_header_list_size` 262144. HTTP/2 `read_body` may still return more
  than `:length`.

  We serve Phoenix through `Bandit.PhoenixAdapter` and use `bandit_pid/1`
  plus `ThousandIsland.connection_pids/1` for idle shutdown. We do not
  set `http_2_options` or call `Plug.Conn.read_body` in app code.
  Public adapter APIs are unchanged.
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
  @http1_socket_src Path.expand(
                      "../../deps/bandit/lib/bandit/http1/socket.ex",
                      __DIR__
                    )
  @settings_src Path.expand(
                  "../../deps/bandit/lib/bandit/http2/settings.ex",
                  __DIR__
                )
  @bandit_src Path.expand("../../deps/bandit/lib/bandit.ex", __DIR__)
  @adapter_src Path.expand("../../deps/bandit/lib/bandit/adapter.ex", __DIR__)
  @compression_src Path.expand(
                     "../../deps/bandit/lib/bandit/compression.ex",
                     __DIR__
                   )
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

    {:module, Bandit.HTTP2.Settings} = Code.ensure_loaded(Bandit.HTTP2.Settings)
    {:module, Bandit.Compression} = Code.ensure_loaded(Bandit.Compression)
    {:module, ThousandIsland} = Code.ensure_loaded(ThousandIsland)
    :ok
  end

  describe "1.14.1 Hex lock and public APIs" do
    test "locks the Hex package to 1.14.1" do
      assert to_string(Application.spec(:bandit, :vsn)) == "1.14.1"
    end

    test "mix.exs pins the 1.14.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:bandit, "~> 1.14.1"})
      refute mix_exs =~ ~s({:bandit, "~> 1.14.0"})
    end

    test "companion locks stay thousand_island 1.6.0 and hpax 1.1.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"bandit": {:hex, :bandit, "1.14.1"|
      refute lock =~ ~s|"bandit": {:hex, :bandit, "1.14.0"|
      assert lock =~ ~s|"thousand_island": {:hex, :thousand_island, "1.6.0"|
      refute lock =~ ~s|"thousand_island": {:hex, :thousand_island, "1.5.0"|
      assert lock =~ ~s|"hpax": {:hex, :hpax, "1.1.0"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
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

      # 1.14.0 stores pending sends in a :queue and only scans once
      # pending_sends_expire_at has passed (CVE-2026-108529).
      connection = %Bandit.HTTP2.Connection{
        pending_sends: :queue.from_list([expired, live]),
        pending_sends_expire_at: now - 1
      }

      updated = Bandit.HTTP2.Connection.expire_pending_sends(connection)

      assert :queue.to_list(updated.pending_sends) == [live]
      assert updated.pending_sends_expire_at == now + 60_000
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

  describe "1.14.0 changelog" do
    test "documents the HTTP/2 and HTTP/1 security fixes and has no Breaking heading" do
      v1140 = changelog_section("1.14.0")
      assert v1140
      refute v1140 =~ "Breaking"
      assert v1140 =~ "CVE-2026-108525"
      assert v1140 =~ "CVE-2026-109584"
      assert v1140 =~ "CVE-2026-108529"
      assert v1140 =~ "CVE-2026-110499"
      assert v1140 =~ "CVE-2026-111103"
      assert v1140 =~ "CVE-2026-115269"
      assert v1140 =~ "CVE-2026-111101"
      assert v1140 =~ "CVE-2026-114216"
      assert v1140 =~ "CVE-2026-113436"
      assert v1140 =~ "CVE-2026-114213"
      assert v1140 =~ "CVE-2026-110314"
      assert v1140 =~ "max_concurrent_streams"
      assert v1140 =~ "262144"
    end
  end

  describe "1.14.0 HTTP/2 receive windows and defaults" do
    test "Settings defaults cap concurrent streams and header list size" do
      defaults = %Bandit.HTTP2.Settings{}
      assert defaults.max_concurrent_streams == 500
      assert defaults.max_header_list_size == 262_144
      assert defaults.header_table_size == 4_096
      assert defaults.initial_window_size == 65_535

      settings = File.read!(@settings_src)
      assert settings =~ "max_concurrent_streams: 500"
      assert settings =~ "max_header_list_size: 262_144"

      bandit = File.read!(@bandit_src)
      assert bandit =~ "default_local_settings"
      assert bandit =~ "max_concurrent_streams"
      assert bandit =~ "262_144"
    end

    test "connection source enforces DATA against the receive window including padding" do
      connection = File.read!(@connection_src)
      flow = File.read!(@flow_src)

      assert connection =~ "@recv_window_target 16_777_216"
      assert connection =~ "@max_send_header_table_size 4_096"
      assert connection =~ "size = byte_size(frame.data) + frame.padding"
      assert connection =~ "DATA exceeds the connection receive window (RFC9113§6.9)"
      assert connection =~ "Bandit.HTTP2.Errors.flow_control_error()"
      assert connection =~ "overrun_stream_recv_window("
      assert connection =~ "pending_sends: :queue.new()"

      assert flow =~ "@stream_recv_window_target 1_048_576"
      assert flow =~ "def compute_recv_window(recv_window_size, data_size, target)"
      assert function_exported?(Bandit.HTTP2.FlowControl, :compute_recv_window, 3)
      assert function_exported?(Bandit.HTTP2.FlowControl, :stream_recv_window_target, 1)
      refute function_exported?(Bandit.HTTP2.FlowControl, :compute_recv_window, 2)
    end

    test "compute_recv_window/3 refills to target once the window falls below half" do
      target = 16_777_216

      assert Bandit.HTTP2.FlowControl.compute_recv_window(target, 100, target) ==
               {target - 100, 0}

      {window, increment} =
        Bandit.HTTP2.FlowControl.compute_recv_window(8_000_000, 100, target)

      assert window == target
      assert increment == target - 7_999_900
    end

    test "stream receive window target is at least 1 MiB" do
      assert Bandit.HTTP2.FlowControl.stream_recv_window_target(65_535) == 1_048_576
      assert Bandit.HTTP2.FlowControl.stream_recv_window_target(2_000_000) == 2_000_000
    end

    test "1.13.1 stale-conn revert is still in effect" do
      pipeline = File.read!(@pipeline_src)
      adapter = File.read!(@adapter_src)
      refute pipeline =~ "stale"
      refute adapter =~ "stale"
    end
  end

  describe "1.14.0 HTTP/1 request-line and chunked-body hardening" do
    test "HTTP/1 socket requires three request-line words and exact versions" do
      socket = File.read!(@http1_socket_src)
      assert socket =~ "Request line does not have exactly three words (RFC9112§3)"
      assert socket =~ "Invalid HTTP version:"
      assert socket =~ ~s("HTTP/1.1")
      assert socket =~ ~s("HTTP/1.0")
      assert socket =~ "Request target has an ambiguous path (RFC9112§3.2.2)"
      assert socket =~ "Invalid chunk extension (RFC9112§7.1.1)"
      assert socket =~ "defp valid_chunk_ext?(<<>>), do: true"
    end

    test "headers cap content-length and port digit counts" do
      headers = File.read!(@headers_src)
      assert headers =~ "@max_port_digits 5"
      assert headers =~ "@max_content_length_digits 19"
      assert headers =~ "quadratic time"
    end

    test "origin-form GET still answers 200" do
      port = start_echo_listener()
      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
      assert response.body == "bandit-upgrade-ok"
    end

    test "absolute-form empty path with query is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET http://127.0.0.1:#{port}?a=b HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end

    test "request line with a fourth word is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET / HTTP/1.1 extra\r\nHost: 127.0.0.1\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end

    test "HTTP/1.1x version is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET / HTTP/1.1x\r\nHost: 127.0.0.1\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end

    test "chunked body with optional whitespace before the extension semicolon is accepted" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n" <>
            "5 ; foo=bar\r\nhello\r\n0\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 200/
      assert response =~ "hello"
    end

    test "chunked body with a bare LF in the extension is rejected with 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n" <>
            "5;\nfoo=bar\r\nhello\r\n0\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end
  end

  describe "1.14.1 changelog" do
    test "documents the HTTP/2 body-collection CVE and has no Breaking heading" do
      v1141 = changelog_section("1.14.1")
      assert v1141
      refute v1141 =~ "Breaking"
      assert v1141 =~ "GHSA-pxjf-g536-7r93"
      assert v1141 =~ "tiny DATA frames"
      assert v1141 =~ "CONNECT"
      assert v1141 =~ ":authority"
      assert v1141 =~ "connection-specific header"
      assert v1141 =~ "Accept-Encoding"
      assert v1141 =~ "trailing whitespace"
      assert v1141 =~ "[::1]80"
    end
  end

  describe "1.14.1 HTTP/2 request-body collection" do
    test "do_read_data/5 appends DATA frames into one binary instead of a list" do
      stream = File.read!(@stream_src)

      assert stream =~ "do_read_data(stream, max_bytes, timeout, deadline, <<>>)"
      refute stream =~ "do_read_data(stream, max_bytes, timeout, deadline, [])"

      assert stream =~ "IO.iodata_to_binary([acc, data])"
      assert stream =~ "<<acc::binary, data::binary>>"
      assert stream =~ "one-byte DATA"
      refute stream =~ "[data | acc]"
    end

    test "content-length POST still echoes the body" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n\r\nhello"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 200/
      assert response =~ "hello"
    end
  end

  describe "1.14.1 HTTP/2 host vs authority and hop-by-hop headers" do
    test "host_matches_authority! rejects a Host that differs from :authority" do
      stream = File.read!(@stream_src)

      assert stream =~ "defp host_matches_authority!"
      assert stream =~ "Host header differs from :authority (RFC9113§8.3.1)"
      assert stream =~ "at_most_one_instance_of!(headers, \"host\", stream)"
      assert stream =~ "host_matches_authority!(headers, request_target, stream)"
    end

    test "HTTP/2 responses drop connection-specific header fields" do
      stream = File.read!(@stream_src)

      assert stream =~
               "@connection_specific_headers ~w[connection keep-alive proxy-connection transfer-encoding upgrade]"

      assert stream =~ "when header in @connection_specific_headers ->"
      assert stream =~ "[]"
      assert stream =~ "defp prepare_headers(headers) do"
    end

    test "oversized decoded header lists stay stream errors after HPACK decode" do
      connection = File.read!(@connection_src)

      assert connection =~ "connection = %{connection | recv_hpack_state: recv_hpack_state}"
      assert connection =~ "deliver_headers(connection, frame, headers, socket)"

      assert connection =~
               "A stream error raised while opening the stream must not discard the HPACK state"

      assert connection =~
               "Decoded header list exceeds max_header_list_size (RFC9113§6.5.2)"
    end
  end

  describe "1.14.1 HTTP/1 header whitespace, q-values, CONNECT, and IPv6" do
    test "HTTP/1 header reads trim trailing OWS before validating the value" do
      socket = File.read!(@http1_socket_src)
      assert socket =~ "value = trim_trailing_ows(value)"
      assert socket =~ "defp trim_trailing_ows(value) do"
      assert socket =~ "RFC9110§5.5"
    end

    test "Host with trailing space is accepted" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET / HTTP/1.1\r\nHost: 127.0.0.1 \r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 200/
      assert response =~ "bandit-upgrade-ok"
    end

    test "IPv6 literal authority without a colon before the port is rejected" do
      assert_raise Bandit.HTTPError, fn ->
        Bandit.Headers.parse_hostlike_header!("[::1]80")
      end

      assert Bandit.Headers.parse_hostlike_header!("[::1]:80") == {"[::1]", 80}
      assert Bandit.Headers.parse_hostlike_header!("[::1]") == {"[::1]", nil}

      headers = File.read!(@headers_src)
      assert headers =~ "defp parse_port_suffix!(_suffix)"
      assert headers =~ "Header contains invalid host"
    end

    test "Host with an IPv6 literal and no colon before the port is 400" do
      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET / HTTP/1.1\r\nHost: [::1]80\r\n\r\n"
        )

      assert response =~ ~r/^HTTP\/1\.[01] 400/
    end

    test "overlong Accept-Encoding q-values no longer 500" do
      compression = File.read!(@compression_src)
      assert compression =~ "@max_qvalue_length 5"
      assert compression =~ "defp parse_qvalue(value) when byte_size(value) <= @max_qvalue_length"
      assert compression =~ "defp parse_qvalue(_value), do: 1.0"

      encodings =
        Bandit.Compression.negotiate_content_encodings(
          "gzip;q=" <> String.duplicate("9", 400),
          []
        )

      assert "gzip" in encodings

      port = start_echo_listener()

      response =
        raw_http(
          port,
          "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept-Encoding: gzip;q=" <>
            String.duplicate("9", 400) <> "\r\n\r\n"
        )

      # 1.14.0 raised inside Float.parse/1 (500). 1.14.1 treats the
      # overlong q-value as 1.0 and may gzip the body, so do not assert
      # the plaintext payload.
      assert response =~ ~r/^HTTP\/1\.[01] 200/
      refute response =~ ~r/^HTTP\/1\.[01] 500/
    end

    test "2xx CONNECT closes the HTTP/1 connection instead of serving a later request" do
      adapter = File.read!(@adapter_src)

      assert adapter =~
               "defp maybe_close_for_connect(%Bandit.HTTP1.Socket{} = socket, \"CONNECT\""

      assert adapter =~ "when status in 200..299"
      assert adapter =~ "%{socket | keepalive: false}"

      port = start_echo_listener()
      follow_up = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"

      {connect_response, follow_up_result} =
        raw_http_reuse(
          port,
          "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n",
          follow_up
        )

      assert connect_response =~ ~r/^HTTP\/1\.[01] 200/
      assert follow_up_result == {:error, :closed}

      {first_get, second_get} =
        raw_http_reuse(
          port,
          "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
          follow_up
        )

      assert first_get =~ ~r/^HTTP\/1\.[01] 200/
      assert first_get =~ "bandit-upgrade-ok"
      assert match?({:ok, _}, second_get)
      {:ok, second_body} = second_get
      assert second_body =~ ~r/^HTTP\/1\.[01] 200/
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

  defp raw_http_reuse(port, first, second) do
    {:ok, sock} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        port,
        [:binary, packet: :raw, active: false],
        5_000
      )

    :ok = :gen_tcp.send(sock, first)

    first_resp =
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, response} ->
          response

        {:error, reason} ->
          :gen_tcp.close(sock)
          flunk("expected a first HTTP response, got #{inspect(reason)}")
      end

    second_result =
      case :gen_tcp.send(sock, second) do
        :ok -> :gen_tcp.recv(sock, 0, 5_000)
        {:error, reason} -> {:error, reason}
      end

    :gen_tcp.close(sock)
    {first_resp, second_result}
  end
end
