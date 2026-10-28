defmodule Ysc.HackneyUpgradeTest do
  @moduledoc """
  Guards the hackney 4.7.4 → 4.9.1 upgrade.

  4.9.1 is docs-only over 4.9.0. 4.9.0 patches:

  * EEF-CVE-2026-97200 (HIGH) — buffered / auto_decompress bodies stop at
    `max_body_size` (default 512 MiB; 1.x name `max_body`) with
    `{error, body_too_large}`.
  * EEF-CVE-2026-115693 (CRITICAL) — `cacerts` / `cacertfile` actually
    restrict trust; hackney's `partial_chain` no longer keeps bundled
    public roots when the caller pins a CA.
  * EEF-CVE-2026-113440 (MEDIUM) — redirects keep `basic_auth` / `cookie`
    only on the same scheme+host+port unless `location_trusted`.
  * EEF-CVE-2026-115700 (MEDIUM) — percent-encoded bracketed IPv6 and
    trailing-dot IP literals are refused like other IP literals.
  * EEF-CVE-2026-112880 (LOW) — `proxy_auth_fun` values with CR/LF/NUL
    return `{error, {proxy_auth_error, invalid_header}}`.

  4.8.x is pooling / HTTP/2 / HTTP/3 correctness plus extras: h2 0.12.5,
  certifi 2.18.0 (drops compromised eMudhra CAs), webtransport 0.4.8,
  and quic 2.1.2 (lock 2.1.3). hackney now starts h2 with a 32 MiB
  connection window so HTTP/2 downloads are not stuck at 64 KB/RTT.

  App HTTP uses Req (`ExAws.Request.Req`, `Ysc.Stripe.HttpClient`,
  `Ysc.Tzdata.HttpClient`). We do not call hackney APIs, pin cacerts,
  follow redirects with `basic_auth`, use `proxy_auth_fun`, HTTP/3, or
  WebTransport. tzdata still lists `~> 1.17`.
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

  describe "4.9.1 Hex lock and public APIs" do
    test "locks the Hex package to 4.9.1" do
      assert to_string(Application.spec(:hackney, :vsn)) == "4.9.1"
    end

    test "mix.exs pins the 4.9.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:hackney, "~> 4.9.1", override: true})
      refute mix_exs =~ ~s({:hackney, "~> 4.7", override: true})

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

    test "companion extras are webtransport 0.4.8, certifi 2.18.0, quic 2.1.3" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"hackney": {:hex, :hackney, "4.9.1"|
      refute lock =~ ~s|"hackney": {:hex, :hackney, "4.7.4"|
      assert lock =~ ~s|"webtransport": {:hex, :webtransport, "0.4.8"|
      refute lock =~ ~s|"webtransport": {:hex, :webtransport, "0.4.5"|
      assert lock =~ ~s|"certifi": {:hex, :certifi, "2.18.0"|
      refute lock =~ ~s|"certifi": {:hex, :certifi, "2.17.0"|
      assert lock =~ ~s|"quic": {:hex, :quic, "2.1.3"|
      refute lock =~ ~s|"quic": {:hex, :quic, "1.8.1"|
      assert lock =~ ~s|"h2": {:hex, :h2, "0.12.5"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "rebar deps match the extras hackney 4.9.1 requires" do
      rebar = File.read!(@hackney_rebar)
      assert rebar =~ ~s|{quic, "~>2.1.2"}|
      assert rebar =~ ~s|{h2, "~>0.12.5"}|
      assert rebar =~ ~s|{webtransport, "~>0.4.8"}|
      assert rebar =~ ~s|{certifi, "~>2.18.0"}|
      assert File.read!(@webtransport_rebar) =~ ~s|{quic, "~> 2.0"}|
    end

    test "request APIs still exist" do
      {:module, :hackney} = Code.ensure_loaded(:hackney)
      {:module, :hackney_url} = Code.ensure_loaded(:hackney_url)
      assert function_exported?(:hackney, :request, 1)
      assert function_exported?(:hackney, :request, 5)
      assert function_exported?(:hackney, :body, 1)
      assert function_exported?(:hackney, :close, 1)
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
      assert conn =~ ~S|connection_window_size => ?H2_CONN_WINDOW}|
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
end
