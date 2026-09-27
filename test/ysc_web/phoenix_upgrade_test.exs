defmodule YscWeb.PhoenixUpgradeTest do
  @moduledoc """
  Guards the Phoenix 1.8.14 → 1.8.15 upgrade.

  1.8.15 is a patch. `replaceTransport` noops the old connection's
  handlers before `close()` so an asynchronous transport close cannot
  tear down the replacement (we import `phoenix` via esbuild
  `NODE_PATH=deps` and only mount the LiveView websocket). `phx.gen.cert`
  Chromium acceptance and `phx.new` Tailwind 4.3.3 are unused — we
  already ship Tailwind 4.3.3 and do not generate certs.

  1.8.14 remains: LongPoll `fetch` timers are cleared after success or
  abort, `use Phoenix.VerifiedRoutes` requires a compile-time `:router`
  module, and local-path checks are shared via `Phoenix.URL` so
  redirects, static paths, and `~p` all reject CR/LF in addition to tabs
  and backslashes. `host_to_binary/1` still treats a nil endpoint host
  as `"localhost"`.
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
  @phoenix_changelog Path.expand("../../deps/phoenix/CHANGELOG.md", __DIR__)
  @phoenix_cert Path.expand(
                  "../../deps/phoenix/lib/mix/tasks/phx.gen.cert.ex",
                  __DIR__
                )
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @endpoint_ex Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @ysc_web_ex Path.expand("../../lib/ysc_web.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)

  describe "1.8.15 lock and JS client" do
    test "locks the Hex package to 1.8.15" do
      assert to_string(Application.spec(:phoenix, :vsn)) == "1.8.15"
      assert File.read!(@mix_exs) =~ ~s({:phoenix, "~> 1.8.15"})
    end

    test "companion phoenix_pubsub lock is 2.3.0 with the APIs we use" do
      assert to_string(Application.spec(:phoenix_pubsub, :vsn)) == "2.3.0"
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

    test "app.js loads phoenix from deps and still reconnects after disconnect settles" do
      app = File.read!(@app_js)
      config = File.read!(@config_exs)

      assert app =~ ~s|import { Socket } from "phoenix"|
      assert config =~ ~s|"NODE_PATH" => Path.expand("../deps", __DIR__)|

      # We do not call replaceTransport; LiveView uses websocket only.
      # forceReconnect still waits a tick after disconnect() so the old
      # socket can close before connect() opens the replacement.
      refute app =~ "replaceTransport"
      assert app =~ "function forceReconnect()"
      assert app =~ "liveSocket.disconnect();"
      assert app =~ "setTimeout(() => liveSocket.connect(), 100)"
    end
  end

  describe "1.8.15 unused generator changes" do
    test "phx.gen.cert is unused; Chromium SAN extensions stay in the task" do
      cert = File.read!(@phoenix_cert)
      mix_exs = File.read!(@mix_exs)

      # mix.exs documents the unused generator in a comment; aliases do not run it.
      refute mix_exs =~ ~s|"phx.gen.cert"|
      refute mix_exs =~ "Mix.Tasks.Phx.Gen.Cert"
      assert cert =~ "@subjectAlternativeName"
      assert cert =~ "@extendedKeyUsage"
      assert cert =~ "@serverAuth"
    end

    test "phx.new Tailwind 4.3.3 is already the app Tailwind version" do
      changelog = File.read!(@phoenix_changelog)
      config = File.read!(@config_exs)

      assert changelog =~ "Update Tailwind version to 4.3.3"
      assert config =~ ~s|version: "4.3.3"|
    end
  end

  describe "1.8.14 VerifiedRoutes and local path validation" do
    test "app VerifiedRoutes pass a compile-time router module" do
      ast = YscWeb.verified_routes()

      assert {:use, _, [{:__aliases__, _, [:Phoenix, :VerifiedRoutes]}, opts]} =
               ast

      assert {:__aliases__, _, [:YscWeb, :Router]} =
               Keyword.fetch!(opts, :router)

      source = File.read!(@ysc_web_ex)
      assert source =~ "router: YscWeb.Router"
    end

    test "a dynamic :router option raises at compile time" do
      unique = System.unique_integer([:positive])
      module = Module.concat(YscWeb.PhoenixUpgradeTest, "BadRoutes#{unique}")

      ast =
        quote do
          defmodule unquote(module) do
            use Phoenix.VerifiedRoutes,
              endpoint: YscWeb.Endpoint,
              router: Module.concat(["YscWeb", "Router"]),
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
      assert Phoenix.URL.classify_local_path("/admin") == :ok
      assert Phoenix.URL.classify_local_path("/images/ysc_logo.png") == :ok

      assert Phoenix.URL.classify_local_path("//evil.example") ==
               {:error, :invalid}

      assert Phoenix.URL.classify_local_path("https://example.com") ==
               {:error, :invalid}

      assert Phoenix.URL.classify_local_path("/foo\nbar") == {:error, :unsafe}
      assert Phoenix.URL.classify_local_path("/foo\rbar") == {:error, :unsafe}
      assert Phoenix.URL.classify_local_path("/foo\\bar") == {:error, :unsafe}

      assert Phoenix.URL.validate_local_path!("/admin") == "/admin"

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
        Phoenix.Controller.redirect(Plug.Test.conn(:get, "/"), to: "/admin")

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/admin"]

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

  describe "1.8.14 endpoint host and transport" do
    test "nil endpoint host still becomes localhost" do
      assert Phoenix.Endpoint.Supervisor.host_to_binary(nil) == "localhost"
      assert Phoenix.Endpoint.Supervisor.host_to_binary("ysc.org") == "ysc.org"
    end

    test "LiveView socket is websocket-only (LongPoll leak does not apply)" do
      source = File.read!(@endpoint_ex)

      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket|
      assert source =~ "websocket: [connect_info:"
      refute source =~ "longpoll:"
    end
  end

  describe "app.js stale-socket reconnect after freeze" do
    test "listens for freeze and resume in addition to visibilitychange" do
      js = File.read!(@app_js)

      assert js =~ ~s|addEventListener("visibilitychange"|
      assert js =~ ~s|addEventListener("freeze", markPageHidden)|
      assert js =~ ~s|addEventListener("resume", verifyConnectionAfterHidden)|
    end

    test "does not blindly tear down a socket that is still connected" do
      js = File.read!(@app_js)

      # Regression guard for #1159: #1114 forced
      # `liveSocket.disconnect(() => liveSocket.connect())` on every
      # return-to-tab, cycling healthy desktop sockets and leaving the main
      # LiveView channel wedged on a topic the server had dropped
      # ("unmatched topic" on every click).
      refute js =~ "liveSocket.disconnect(() => liveSocket.connect())"

      # A return-to-tab only reconnects when the socket is actually gone, or
      # when a heartbeat round-trip fails to come back.
      assert js =~ "isConnected()"
      assert js =~ ~s|event: "heartbeat"|
      assert js =~ ~s|event === "phx_reply"|
    end

    test "reconnect path splits disconnect() and connect() across ticks" do
      js = File.read!(@app_js)

      # disconnect() must settle (channels -> "errored", old socket closed)
      # before connect() runs, otherwise the channel never rejoins.
      assert js =~ "function forceReconnect()"
      assert js =~ "liveSocket.disconnect();"
      assert js =~ "setTimeout(() => liveSocket.connect(), 100)"
    end
  end
end
