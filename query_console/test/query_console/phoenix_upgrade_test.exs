defmodule QueryConsole.PhoenixUpgradeTest do
  @moduledoc """
  Guards the Phoenix 1.8.9 → 1.8.15 upgrade.

  1.8.15 is a patch. Query Console enables LongPoll on the LiveView
  socket (`longpoll:` plus `longPollFallbackMs: 2500`) and imports
  `phoenix` via esbuild `NODE_PATH=deps`, so the JS transport patches
  apply:

  * 1.8.15: `replaceTransport` noops the old connection's handlers
    before `close()` so an asynchronous transport close cannot tear
    down the replacement (#6852).
  * 1.8.14: LongPoll `fetch` timers are cleared after success or abort
    (#6811). `use Phoenix.VerifiedRoutes` requires a compile-time
    `:router` module. Local-path checks are shared via `Phoenix.URL`.
  * 1.8.13: phoenix.js reconnects after Chrome freeze/resume when
    `visibilitychange` is skipped (#6804).
  * 1.8.10: longpoll batch POST timeouts call `ontimeout` /
    `closeAndRetry` (#6769).

  Unused here: `phx.gen.auth` return_to, `phx.gen.cert` Chromium SAN,
  `phx.new` Tailwind 4.3.3 (we ship Tailwind 4.1.7), Mix-not-started
  boot (#6789), and channel `join_ref` (no user socket).
  """
  use ExUnit.Case, async: true

  @phoenix_js Path.expand("../../deps/phoenix/priv/static/phoenix.js", __DIR__)
  @phoenix_ajax_js Path.expand(
                     "../../deps/phoenix/assets/js/phoenix/ajax.js",
                     __DIR__
                   )
  @phoenix_socket_js Path.expand(
                       "../../deps/phoenix/assets/js/phoenix/socket.js",
                       __DIR__
                     )
  @phoenix_longpoll_js Path.expand(
                         "../../deps/phoenix/assets/js/phoenix/longpoll.js",
                         __DIR__
                       )
  @phoenix_changelog Path.expand("../../deps/phoenix/CHANGELOG.md", __DIR__)
  @phoenix_cert Path.expand(
                  "../../deps/phoenix/lib/mix/tasks/phx.gen.cert.ex",
                  __DIR__
                )
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @endpoint_ex Path.expand("../../lib/query_console_web/endpoint.ex", __DIR__)
  @web_ex Path.expand("../../lib/query_console_web.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)

  describe "1.8.15 lock and JS client" do
    test "locks the Hex package to 1.8.15" do
      assert to_string(Application.spec(:phoenix, :vsn)) == "1.8.15"
      assert File.read!(@mix_exs) =~ ~s({:phoenix, "~> 1.8.15"})
    end

    test "companion phoenix_pubsub lock stays 2.2.0 with the APIs we use" do
      assert to_string(Application.spec(:phoenix_pubsub, :vsn)) == "2.2.0"
      assert {:module, _} = Code.ensure_loaded(Phoenix.PubSub)
      assert function_exported?(Phoenix.PubSub, :subscribe, 2)
      assert function_exported?(Phoenix.PubSub, :broadcast, 3)
      assert function_exported?(Phoenix.PubSub, :unsubscribe, 2)
    end

    test "phoenix.js reconnects on document resume when visibilitychange is skipped" do
      js = File.read!(@phoenix_js)
      source = File.read!(@phoenix_socket_js)

      assert js =~ ~s|addEventListener("resume"|
      assert js =~ "handleVisibilityChange"
      assert js =~ "document.visibilityState === \"hidden\""
      assert source =~ "issues.chromium.org/issues/547062449"
    end

    test "LongPoll fetch timeouts are cleared after success or abort" do
      ajax = File.read!(@phoenix_ajax_js)
      js = File.read!(@phoenix_js)

      assert ajax =~ "let timeoutId = null"
      assert ajax =~ "if(timeoutId){ clearTimeout(timeoutId) }"
      assert js =~ "clearTimeout(timeoutId)"
    end

    test "socket and endpoint modules we use still load" do
      assert {:module, Phoenix.Socket} = Code.ensure_loaded(Phoenix.Socket)
      assert {:module, Phoenix.Endpoint} = Code.ensure_loaded(Phoenix.Endpoint)
      assert {:module, Phoenix.URL} = Code.ensure_loaded(Phoenix.URL)

      assert {:module, Phoenix.LiveView.Socket} =
               Code.ensure_loaded(Phoenix.LiveView.Socket)
    end
  end

  describe "1.8.15 replaceTransport does not tear down the replacement" do
    test "changelog documents the async transport-close fix" do
      changelog = File.read!(@phoenix_changelog)

      assert changelog =~ "## v1.8.15 (2026-09-25)"

      assert changelog =~
               "Fix asynchronous transport close tearing down the replacement transport"

      assert changelog =~ "#6852"
    end

    test "source detaches old handlers before close so late events stay off the new conn" do
      source = File.read!(@phoenix_socket_js)

      assert source =~ "replaceTransport(newTransport)"

      assert source =~
               "the old conn closes asynchronously, so detach its handlers"

      assert source =~ "belonged to the new transport"
      assert source =~ "const wasOpen = this.isConnected()"
      assert source =~ "this.conn.onopen = function (){ } // noop"
      assert source =~ "this.conn.onerror = function (){ } // noop"
      assert source =~ "this.conn.onmessage = function (){ } // noop"
      assert source =~ "this.conn.onclose = function (){ } // noop"
      assert source =~ "this.conn.close()"
      assert source =~ "this.conn = null"
      assert source =~ "this.clearHeartbeats()"

      assert source =~
               ~s|if(wasOpen){ this.triggerChanError("connection_closed") }|
    end

    test "bundled phoenix.js ships the same detach-before-close replaceTransport" do
      js = File.read!(@phoenix_js)

      assert js =~ "replaceTransport(newTransport)"
      assert js =~ "const wasOpen = this.isConnected()"
      assert js =~ "this.conn.onopen = function()"
      assert js =~ "this.conn.onerror = function()"
      assert js =~ "this.conn.onmessage = function()"
      assert js =~ "this.conn.onclose = function()"
      assert js =~ "this.conn.close()"
      assert js =~ "this.clearHeartbeats()"
      assert js =~ ~s|this.triggerChanError("connection_closed")|
    end

    test "app.js loads phoenix from deps and enables longpoll fallback" do
      app = File.read!(@app_js)
      config = File.read!(@config_exs)

      assert app =~ ~s|import {Socket} from "phoenix"|
      assert config =~ ~s|"NODE_PATH"|
      assert config =~ ~s|Path.expand("../deps", __DIR__)|

      # LiveSocket falls back to LongPoll, which calls replaceTransport.
      assert app =~ "longPollFallbackMs: 2500"
      refute app =~ "replaceTransport"
    end
  end

  describe "1.8.14 VerifiedRoutes and local path validation" do
    test "app VerifiedRoutes pass a compile-time router module" do
      ast = QueryConsoleWeb.verified_routes()

      assert {:use, _, [{:__aliases__, _, [:Phoenix, :VerifiedRoutes]}, opts]} =
               ast

      assert {:__aliases__, _, [:QueryConsoleWeb, :Router]} =
               Keyword.fetch!(opts, :router)

      source = File.read!(@web_ex)
      assert source =~ "router: QueryConsoleWeb.Router"
    end

    test "a dynamic :router option raises at compile time" do
      unique = System.unique_integer([:positive])

      module =
        Module.concat(QueryConsole.PhoenixUpgradeTest, "BadRoutes#{unique}")

      ast =
        quote do
          defmodule unquote(module) do
            use Phoenix.VerifiedRoutes,
              endpoint: QueryConsoleWeb.Endpoint,
              router: Module.concat(["QueryConsoleWeb", "Router"]),
              statics: []
          end
        end

      assert_raise ArgumentError,
                   ~r/:router option in VerifiedRoutes must be a literal module/,
                   fn ->
                     Code.eval_quoted(ast)
                   end
    end

    test "Phoenix.URL classifies local paths and rejects CR/LF and scheme-relative URLs" do
      assert Phoenix.URL.classify_local_path("/auth/ysc") == :ok
      assert Phoenix.URL.classify_local_path("/images/logo.png") == :ok

      assert Phoenix.URL.classify_local_path("//evil.example") ==
               {:error, :invalid}

      assert Phoenix.URL.classify_local_path("https://example.com") ==
               {:error, :invalid}

      assert Phoenix.URL.classify_local_path("/foo\nbar") == {:error, :unsafe}
      assert Phoenix.URL.classify_local_path("/foo\rbar") == {:error, :unsafe}
      assert Phoenix.URL.classify_local_path("/foo\\bar") == {:error, :unsafe}

      assert Phoenix.URL.validate_local_path!("/auth/ysc") == "/auth/ysc"

      assert_raise ArgumentError, ~r/unsafe characters detected for path/, fn ->
        Phoenix.URL.validate_local_path!("/foo\nbar")
      end

      assert_raise ArgumentError,
                   ~r/expected a path starting with a single \//,
                   fn ->
                     Phoenix.URL.validate_local_path!("//evil.example")
                   end
    end

    test "Controller.redirect/2 uses the shared local-path classifier" do
      conn =
        Phoenix.Controller.redirect(Plug.Test.conn(:get, "/"), to: "/auth/ysc")

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/auth/ysc"]

      assert_raise ArgumentError,
                   ~r/unsafe characters detected for local redirect/,
                   fn ->
                     Phoenix.Controller.redirect(Plug.Test.conn(:get, "/"),
                       to: "/foo\nbar"
                     )
                   end

      assert_raise ArgumentError,
                   ~r/the :to option in redirect expects a path/,
                   fn ->
                     Phoenix.Controller.redirect(Plug.Test.conn(:get, "/"),
                       to: "//evil.example"
                     )
                   end
    end
  end

  describe "1.8.14 endpoint host and LongPoll transport" do
    test "nil endpoint host still becomes localhost" do
      assert Phoenix.Endpoint.Supervisor.host_to_binary(nil) == "localhost"

      assert Phoenix.Endpoint.Supervisor.host_to_binary("query.ysc.org") ==
               "query.ysc.org"
    end

    test "LiveView socket enables websocket and longpoll" do
      source = File.read!(@endpoint_ex)

      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket|
      assert source =~ "websocket: [connect_info:"
      assert source =~ "longpoll: [connect_info:"
    end

    test "changelog documents the LongPoll fetch timer leak fix" do
      changelog = File.read!(@phoenix_changelog)

      assert changelog =~ "## v1.8.14 (2026-09-14)"
      assert changelog =~ "Fix timer leak in LongPoll fetch requests"
      assert changelog =~ "#6811"
    end
  end

  describe "1.8.10 longpoll POST timeout close-and-retry" do
    test "changelog documents the batch POST timeout retry" do
      changelog = File.read!(@phoenix_changelog)

      assert changelog =~ "## v1.8.10 (2026-08-10)"

      assert changelog =~
               "Close and retry the longpoll transport when a batch POST times out"

      assert changelog =~ "#6769"
    end

    test "source POST batchSend times out via ontimeout/closeAndRetry" do
      source = File.read!(@phoenix_longpoll_js)

      assert source =~ "closeAndRetry(code, reason, wasClean)"
      assert source =~ "this.onerror(\"timeout\")"
      assert source =~ ~s|this.closeAndRetry(1005, "timeout", false)|

      assert source =~
               ~s|this.ajax("POST", {"Content-Type": "application/x-ndjson"}|

      assert source =~ ~s|() => this.ontimeout()|
    end

    test "bundled phoenix.js ships the same POST timeout retry" do
      js = File.read!(@phoenix_js)

      assert js =~ "closeAndRetry(code, reason, wasClean)"
      assert js =~ ~s|this.closeAndRetry(1005, "timeout", false)|
      assert js =~ ~s|"Content-Type": "application/x-ndjson"|
      assert js =~ "() => this.ontimeout()"
    end
  end

  describe "1.8.15 unused generator changes" do
    test "phx.gen.cert is unused; Chromium SAN extensions stay in the task" do
      cert = File.read!(@phoenix_cert)
      mix_exs = File.read!(@mix_exs)

      refute mix_exs =~ ~s|"phx.gen.cert"|
      refute mix_exs =~ "Mix.Tasks.Phx.Gen.Cert"
      assert cert =~ "@subjectAlternativeName"
      assert cert =~ "@extendedKeyUsage"
      assert cert =~ "@serverAuth"
    end

    test "phx.new Tailwind 4.3.3 is unused; we still ship 4.1.7" do
      changelog = File.read!(@phoenix_changelog)
      config = File.read!(@config_exs)

      assert changelog =~ "Update Tailwind version to 4.3.3"
      assert config =~ ~s|version: "4.1.7"|
      refute config =~ ~s|version: "4.3.3"|
    end

    test "SSO auth does not use phx.gen.auth return_to" do
      mix_exs = File.read!(@mix_exs)
      app = File.read!(@app_js)

      refute mix_exs =~ ~s|"phx.gen.auth"|
      refute mix_exs =~ "Mix.Tasks.Phx.Gen.Auth"
      # Stock comment only; channels stay unmounted.
      assert app =~ ~s|// import "./user_socket.js"|
      refute app =~ ~r/^import "\.\/user_socket\.js"/m
    end
  end
end
