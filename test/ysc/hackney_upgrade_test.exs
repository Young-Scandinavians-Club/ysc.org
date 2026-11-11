defmodule Ysc.HackneyUpgradeTest do
  @moduledoc """
  Guards the hackney 4.10.0 → 4.10.2 upgrade (tightly coupled with h2 0.15.1).

  4.10.1 makes `insecure` / `{verify, verify_none}` actually disable TLS
  verification. We do not pass `insecure`.

  4.10.2 releases pooled checkout slots if the caller dies or times out,
  returns from `close/1` within about a second (`abort_read/1`), resumes
  TLS 1.3 session tickets one-at-a-time per host, keeps `connect_options`
  socket opts on pooled connections, and sends streamed `Content-Length`
  bodies as declared instead of chunk-framing them.

  extras: h2 0.15.1 (TLS close without waiting for the peer),
  webtransport 0.5.5 (unused; needs h2 0.15.1), quic 2.6.1, ssl_verify_fun
  1.1.9. certifi stays 2.18.0. phoenix_template stays 1.0.4.

  App HTTP uses Req (`ExAws.Request.Req`, `Ysc.Stripe.HttpClient`,
  `Ysc.Tzdata.HttpClient`). We do not call hackney APIs, pin cacerts,
  follow redirects with `basic_auth`, use `proxy_auth_fun`, HTTP/3,
  WebTransport, or `insecure`. tzdata still lists `~> 1.17`.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @news Path.expand("../../deps/hackney/NEWS.md", __DIR__)
  @hackney_hrl Path.expand("../../deps/hackney/include/hackney.hrl", __DIR__)
  @hackney_erl Path.expand("../../deps/hackney/src/hackney.erl", __DIR__)
  @hackney_conn Path.expand("../../deps/hackney/src/hackney_conn.erl", __DIR__)
  @hackney_url Path.expand("../../deps/hackney/src/hackney_url.erl", __DIR__)
  @hackney_ssl Path.expand("../../deps/hackney/src/hackney_ssl.erl", __DIR__)
  @hackney_http_connect Path.expand(
                          "../../deps/hackney/src/hackney_http_connect.erl",
                          __DIR__
                        )
  @hackney_http Path.expand("../../deps/hackney/src/hackney_http.erl", __DIR__)
  @hackney_pool Path.expand("../../deps/hackney/src/hackney_pool.erl", __DIR__)
  @hackney_rebar Path.expand("../../deps/hackney/rebar.config", __DIR__)
  @webtransport_rebar Path.expand(
                        "../../deps/webtransport/rebar.config",
                        __DIR__
                      )
  @certifi_readme Path.expand("../../deps/certifi/README.md", __DIR__)
  @certifi_pem Path.expand("../../deps/certifi/priv/cacerts.pem", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)
  @runtime_exs Path.expand("../../config/runtime.exs", __DIR__)
  @stripe_client Path.expand("../../lib/ysc/stripe/http_client.ex", __DIR__)
  @tzdata_client Path.expand("../../lib/ysc/tzdata/http_client.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:hackney)
    {:ok, _} = Application.ensure_all_started(:certifi)
    {:module, :hackney} = Code.ensure_loaded(:hackney)
    {:module, :hackney_url} = Code.ensure_loaded(:hackney_url)
    {:module, :certifi} = Code.ensure_loaded(:certifi)
    :ok
  end

  describe "4.10.2 Hex lock and public APIs" do
    test "locks the Hex package to 4.10.2" do
      assert to_string(Application.spec(:hackney, :vsn)) == "4.10.2"
    end

    test "mix.exs pins the 4.10.2 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:hackney, "~> 4.10.2", override: true})
      refute mix_exs =~ ~s({:hackney, "~> 4.10.0", override: true})
      refute mix_exs =~ ~s({:hackney, "~> 4.9.1", override: true})

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      refute ignore =~ "EEF-CVE-2026-112880"
      refute ignore =~ "EEF-CVE-2026-97200"
      refute ignore =~ "EEF-CVE-2026-115700"
      refute ignore =~ "EEF-CVE-2026-115693"
      refute ignore =~ "EEF-CVE-2026-113440"
    end

    test "companion extras are h2 0.15.1, webtransport 0.5.5, quic 2.6.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"hackney": {:hex, :hackney, "4.10.2"|
      refute lock =~ ~s|"hackney": {:hex, :hackney, "4.10.0"|
      assert lock =~ ~s|"webtransport": {:hex, :webtransport, "0.5.5"|
      refute lock =~ ~s|"webtransport": {:hex, :webtransport, "0.5.3"|
      assert lock =~ ~s|"certifi": {:hex, :certifi, "2.18.0"|
      assert lock =~ ~s|"quic": {:hex, :quic, "2.6.1"|
      refute lock =~ ~s|"quic": {:hex, :quic, "2.1.3"|
      assert lock =~ ~s|"h2": {:hex, :h2, "0.15.1"|
      refute lock =~ ~s|"h2": {:hex, :h2, "0.15.0"|
      assert lock =~ ~s|"ssl_verify_fun": {:hex, :ssl_verify_fun, "1.1.9"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "rebar deps match the extras hackney 4.10.2 requires" do
      rebar = File.read!(@hackney_rebar)
      assert rebar =~ ~s|{quic, "~>2.6.1"}|
      assert rebar =~ ~s|{h2, "~>0.15.0"}|
      assert rebar =~ ~s|{webtransport, "~>0.5.3"}|
      assert rebar =~ ~s|{certifi, "~>2.18.0"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{quic, "~> 2.6.1"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{h2, "~> 0.15.1"}|
    end

    test "request APIs still exist" do
      {:module, :hackney} = Code.ensure_loaded(:hackney)
      {:module, :hackney_url} = Code.ensure_loaded(:hackney_url)
      assert function_exported?(:hackney, :request, 1)
      assert function_exported?(:hackney, :request, 5)
      assert function_exported?(:hackney, :body, 1)
      assert function_exported?(:hackney, :close, 1)
      assert function_exported?(:hackney, :send_body, 2)
      assert function_exported?(:hackney, :finish_send_body, 1)
      assert function_exported?(:hackney, :start_response, 1)
      assert function_exported?(:hackney_url, :normalize, 1)
      assert function_exported?(:hackney_url, :normalize, 2)
      assert function_exported?(:hackney_url, :same_origin, 2)
      assert function_exported?(:hackney_url, :parse_url, 1)
    end
  end

  describe "4.9.1 NEWS" do
    test "documents the 4.9.0 security fixes and 4.9.1 docs-only patch" do
      news = File.read!(@news)
      assert news =~ "4.9.1 - 2026-10-26"
      assert news =~ "4.9.0 - 2026-10-25"
      assert news =~ "max_body_size"
      assert news =~ "{error, body_too_large}"
      assert news =~ "percent-encoded"
      assert news =~ "trailing dot"
      assert news =~ "cacerts"
      assert news =~ "location_trusted"
      assert news =~ "proxy_auth_fun"
      assert news =~ "{error, {proxy_auth_error, invalid_header}}"
      assert news =~ "The documentation builds again"
    end
  end

  describe "4.10.0 NEWS" do
    test "documents chunked max_body_size, h2 0.15.0, and stream wait" do
      news = File.read!(@news)
      assert news =~ "4.10.0 - 2026-11-09"
      assert news =~ "chunked body"
      assert news =~ "4096 bytes"
      assert news =~ "16 hex digits"
      assert news =~ "checkout_timeout"
      assert news =~ "h2 0.15.0"
      assert news =~ "MadeYouReset"
      assert news =~ "SETTINGS flood"
      assert news =~ "quic 2.6.1"
      assert news =~ "webtransport 0.5.3"
    end
  end

  describe "4.10.1 NEWS" do
    test "documents insecure and verify_none actually disabling TLS checks" do
      news = File.read!(@news)
      assert news =~ "4.10.1 - 2026-11-10"
      assert news =~ "insecure"
      assert news =~ "{verify, verify_none}"
      assert news =~ "connect_options"
    end
  end

  describe "4.10.2 NEWS" do
    test "documents pool slot leaks, close abort, TLS tickets, and Content-Length" do
      news = File.read!(@news)
      assert news =~ "4.10.2 - 2026-11-10"
      assert news =~ "now returns within about a"
      assert news =~ "checkout_timeout"
      assert news =~ "bad_record_mac"
      assert news =~ "Content-Length"
      assert news =~ "h2 0.15.1"
      assert news =~ "webtransport 0.5.5"
    end
  end

  describe "app HTTP still uses Req, not hackney" do
    test "ExAws, Stripe, and tzdata keep their Req adapters" do
      config = File.read!(@config_exs)
      runtime = File.read!(@runtime_exs)
      assert config =~ "http_client: ExAws.Request.Req"
      assert config =~ "config :tzdata, :http_client, Ysc.Tzdata.HttpClient"
      assert runtime =~ "http_module: Ysc.Stripe.HttpClient"

      stripe = File.read!(@stripe_client)
      assert stripe =~ "Req.request("
      refute stripe =~ ":hackney"

      tzdata = File.read!(@tzdata_client)
      assert tzdata =~ "Req.get("
      assert tzdata =~ "Req.head("
      refute tzdata =~ ":hackney"
    end
  end

  describe "EEF-CVE-2026-97200 max_body_size" do
    test "default cap is 512 MiB and 1.x max_body is still accepted" do
      hrl = File.read!(@hackney_hrl)
      conn = File.read!(@hackney_conn)
      assert hrl =~ "-define(DEFAULT_MAX_BODY_SIZE, 16#20000000)."
      assert hrl =~ "512 MiB"
      assert conn =~ "{error, body_too_large}"

      assert conn =~
               "undefined -> proplists:get_value(max_body, ReqOpts, ?DEFAULT_MAX_BODY_SIZE)"
    end

    test "a body over max_body_size fails; a normal body still returns" do
      port =
        Ysc.HttpTestServer.ensure_started(Ysc.Tzdata.HttpTestPlug, :tzdata_get)

      url = "http://127.0.0.1:#{port}/tzdata"

      assert {:error, :body_too_large} =
               :hackney.request(:get, url, [], "",
                 max_body_size: 1,
                 pool: false
               )

      assert {:ok, 200, _headers, "IANA tzdata bytes"} =
               :hackney.request(:get, url, [], "", pool: false)
    end
  end

  describe "EEF-CVE-2026-115700 SSRF IP-literal spellings" do
    test "normalize rejects percent-encoded bracketed IPv6 and trailing-dot hosts" do
      assert {:invalid_url_host, _} =
               catch_error(:hackney_url.normalize("http://%5B%3A%3A1%5D/"))

      assert {:invalid_url_host, _} =
               catch_error(:hackney_url.normalize("http://127.0.0.1./"))
    end

    test "source strips brackets and a trailing dot before the IP gate" do
      source = File.read!(@hackney_url)
      assert source =~ "ip_candidate(dot_canonical(DecodedBin))"
      assert source =~ "GHSA-5643"
      assert source =~ ~S|ip_candidate("[" ++ Rest) ->|

      assert source =~
               ~S|"." ++ Inner when Inner =/= [] -> lists:reverse(Inner)|
    end
  end

  describe "EEF-CVE-2026-113440 redirect credentials" do
    test "same_origin is scheme, host, and port" do
      {:module, :hackney_url} = Code.ensure_loaded(:hackney_url)

      assert :hackney_url.same_origin(
               "https://example.com/a",
               "https://example.com/b"
             )

      refute :hackney_url.same_origin(
               "https://example.com/a",
               "http://example.com/a"
             )

      refute :hackney_url.same_origin(
               "https://example.com/a",
               "https://example.com:8443/a"
             )
    end

    test "redirects keep credentials only on the same origin unless location_trusted" do
      source = File.read!(@hackney_erl)
      assert source =~ "hackney_url:same_origin(CurrentURL, NewURL)"
      assert source =~ "location_trusted"
    end
  end

  describe "EEF-CVE-2026-112880 proxy_auth_fun control bytes" do
    test "CONNECT auth header with CR/LF/NUL is refused" do
      source = File.read!(@hackney_http_connect)

      assert source =~ "{error, {proxy_auth_error, invalid_header}}"
      assert source =~ "has_ctl_bytes(AuthHeader)"
    end
  end

  describe "EEF-CVE-2026-115693 pinned CA trust" do
    test "custom cacerts drop hackney partial_chain so public roots are not kept" do
      source = File.read!(@hackney_ssl)

      assert source =~ "lists:keymember(cacerts, 1, OverrideOpts)"
      assert source =~ "lists:keymember(cacertfile, 1, OverrideOpts)"

      assert source =~
               "lists:keydelete(partial_chain, 1, MergedOpts1)"
    end
  end

  describe "4.8.6 HTTP/2 connection window extra" do
    test "hackney starts h2 with a 32 MiB connection window" do
      conn = File.read!(@hackney_conn)
      assert conn =~ "-define(H2_STREAM_WINDOW, 8 * 1024 * 1024)."
      assert conn =~ "-define(H2_CONN_WINDOW, 32 * 1024 * 1024)."
      assert conn =~ ~S|connection_window_size => ?H2_CONN_WINDOW,|
    end
  end

  describe "4.10.0 chunked max_body_size" do
    test "parser hands chunk data on as it arrives and bounds the size line" do
      source = File.read!(@hackney_http)
      assert source =~ "-define(MAX_CHUNK_LINE, 4096)."
      assert source =~ "-define(MAX_CHUNK_SIZE_DIGITS, 16)."
      assert source =~ "Chunk data is handed out as it arrives"

      assert source =~
               "{chunk_part, Data, {remaining, R - byte_size(Data)}, <<>>}"

      assert source =~ "{error, invalid_chunk_size}"
    end

    test "chunk-size lines over 16 hex digits or 4096 bytes are refused" do
      {:module, _} = Code.ensure_loaded(:hackney_http)
      headers = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"

      parser = skip_to_body(:hackney_http.parser([:response]), headers)

      assert {:error, :invalid_chunk_size} =
               :hackney_http.execute(parser, "10000000000000000\r\n")

      parser = skip_to_body(:hackney_http.parser([:response]), headers)
      overlong = String.duplicate("1", 4097) <> "\r\n"

      assert {:error, :invalid_chunk_size} =
               :hackney_http.execute(parser, overlong)
    end

    test "a chunked body over max_body_size fails as data arrives" do
      {:ok, lsock} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true,
          ip: {127, 0, 0, 1}
        ])

      {:ok, port} = :inet.port(lsock)

      server =
        Task.async(fn ->
          {:ok, sock} = :gen_tcp.accept(lsock, 2_000)
          _ = :gen_tcp.recv(sock, 0, 2_000)
          chunk = String.duplicate("x", 64)

          resp = [
            "HTTP/1.1 200 OK\r\n",
            "Transfer-Encoding: chunked\r\n",
            "\r\n",
            Integer.to_string(byte_size(chunk), 16),
            "\r\n",
            chunk,
            "\r\n0\r\n\r\n"
          ]

          :ok = :gen_tcp.send(sock, resp)
          :gen_tcp.close(sock)
        end)

      url = "http://127.0.0.1:#{port}/"

      try do
        assert {:error, :body_too_large} =
                 :hackney.request(:get, url, [], "",
                   max_body_size: 8,
                   pool: false
                 )
      after
        _ = Task.shutdown(server, :brutal_kill)
        :gen_tcp.close(lsock)
      end
    end
  end

  describe "4.10.0 HTTP/2 stream wait extra" do
    test "hackney opts into notify_stream_available" do
      conn = File.read!(@hackney_conn)
      assert conn =~ "notify_stream_available => true"
      assert conn =~ "handle_h2_event(stream_available, Data)"
    end
  end

  describe "4.10.1 insecure TLS" do
    test "fold_insecure copies the option into ssl_options and verify_none skips hostname checks" do
      erl = File.read!(@hackney_erl)
      ssl = File.read!(@hackney_ssl)

      assert erl =~ "fold_insecure(Options0)"
      assert erl =~ "proplists:is_defined(insecure, ConnectOpts)"
      assert ssl =~ "proplists:get_value(verify, OverrideOpts) =:= verify_none"
      assert ssl =~ "would reject the peer the caller asked not to verify"
    end

    test "app HTTP adapters do not pass insecure" do
      stripe = File.read!(@stripe_client)
      tzdata = File.read!(@tzdata_client)
      refute stripe =~ "insecure"
      refute tzdata =~ "insecure"
      refute stripe =~ "verify_none"
      refute tzdata =~ "verify_none"
    end
  end

  describe "4.10.2 close, pool slots, and TLS tickets" do
    test "close aborts a pending read so it cannot hang on a silent server" do
      erl = File.read!(@hackney_erl)
      conn = File.read!(@hackney_conn)

      assert erl =~ "ok = hackney_conn:abort_read(ConnPid)"
      assert erl =~ "the close does not wait for it (#996)"
      assert conn =~ "{?MODULE, abort_read}"
      assert conn =~ "never (#996)"
      assert function_exported?(:hackney_conn, :abort_read, 1)
    end

    test "pool releases a slot when the requester dies while queued" do
      pool = File.read!(@hackney_pool)
      assert pool =~ "#974"
      assert pool =~ "leaking the slot"
    end

    test "TLS 1.3 session tickets are claimed one host at a time" do
      ssl = File.read!(@hackney_ssl)
      assert ssl =~ "claim_resumption(Host, SslOpts)"
      assert ssl =~ "bad_record_mac"
      assert ssl =~ "#995"
    end
  end

  describe "4.10.2 streamed Content-Length bodies" do
    test "source sends a declared length raw and refuses a mismatch" do
      conn = File.read!(@hackney_conn)
      assert conn =~ "stream_body_framing(Headers)"
      assert conn =~ "a Content-Length alone: the body is written raw"
      assert conn =~ "an empty piece sends nothing"
      assert conn =~ "{error, {content_length_mismatch,"
    end

    test "a streamed Content-Length body is sent raw, not chunked" do
      {:ok, lsock} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true,
          ip: {127, 0, 0, 1}
        ])

      {:ok, port} = :inet.port(lsock)

      server =
        Task.async(fn ->
          {:ok, sock} = :gen_tcp.accept(lsock, 2_000)
          {:ok, req} = recv_until_body(sock, 4, 2_000)

          :ok =
            :gen_tcp.send(
              sock,
              "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"
            )

          :gen_tcp.close(sock)
          req
        end)

      url = "http://127.0.0.1:#{port}/"

      try do
        assert {:ok, client} =
                 :hackney.request(
                   :post,
                   url,
                   [{"Content-Length", "4"}],
                   :stream,
                   pool: false
                 )

        assert :ok = :hackney.send_body(client, "abcd")
        assert :ok = :hackney.finish_send_body(client)
        assert {:ok, 200, _headers, ^client} = :hackney.start_response(client)
        assert {:ok, "ok"} = :hackney.body(client)

        req = Task.await(server, 3_000)
        refute req =~ "Transfer-Encoding: chunked"
        assert req =~ "Content-Length: 4"
        assert String.contains?(req, "\r\n\r\nabcd")
      after
        _ = Task.shutdown(server, :brutal_kill)
        :gen_tcp.close(lsock)
      end
    end

    test "finishing a short streamed Content-Length body is a mismatch" do
      {:ok, lsock} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true,
          ip: {127, 0, 0, 1}
        ])

      {:ok, port} = :inet.port(lsock)

      server =
        Task.async(fn ->
          {:ok, sock} = :gen_tcp.accept(lsock, 2_000)
          _ = :gen_tcp.recv(sock, 0, 2_000)
          :gen_tcp.close(sock)
        end)

      url = "http://127.0.0.1:#{port}/"

      try do
        assert {:ok, client} =
                 :hackney.request(
                   :post,
                   url,
                   [{"Content-Length", "4"}],
                   :stream,
                   pool: false
                 )

        assert :ok = :hackney.send_body(client, "ab")

        assert {:error, {:content_length_mismatch, 4, 2}} =
                 :hackney.finish_send_body(client)
      after
        _ = Task.shutdown(server, :brutal_kill)
        :gen_tcp.close(lsock)
      end
    end
  end

  describe "certifi 2.18.0 extra" do
    test "locks 2.18.0 and drops the distrusted emSign C1/C3/G3 roots" do
      assert to_string(Application.spec(:certifi, :vsn)) == "2.18.0"
      readme = File.read!(@certifi_readme)
      pem = File.read!(@certifi_pem)
      assert readme =~ "emSign C1, C3, and G3 roots are excluded"
      refute pem =~ "CN=emSign Root CA - C1"
      refute pem =~ "CN=emSign ECC Root CA - C3"
      refute pem =~ "CN=emSign ECC Root CA - G3"
      {:module, :certifi} = Code.ensure_loaded(:certifi)
      assert length(:certifi.cacerts()) == 118
    end
  end

  defp recv_until_body(sock, body_size, timeout) do
    recv_until_body(sock, body_size, timeout, <<>>)
  end

  defp recv_until_body(sock, body_size, timeout, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [_headers, rest] when byte_size(rest) >= body_size ->
        {:ok, acc}

      _ ->
        case :gen_tcp.recv(sock, 0, timeout) do
          {:ok, data} -> recv_until_body(sock, body_size, timeout, acc <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp skip_to_body(parser, data) do
    case call_parser(parser, data) do
      {:response, _version, _status, _reason, next} ->
        skip_to_body(next, :continue)

      {:header, _header, next} ->
        skip_to_body(next, :continue)

      {:headers_complete, next} ->
        next
    end
  end

  defp call_parser(parser, :continue), do: :hackney_http.execute(parser)
  defp call_parser(parser, data), do: :hackney_http.execute(parser, data)
end
