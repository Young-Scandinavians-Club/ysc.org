defmodule YscWeb.PhoenixUpgradeTest do
  @moduledoc """
  Guards the Phoenix 1.8.13 → 1.8.14 upgrade.

  1.8.14 is a patch: LongPoll `fetch` timers are cleared after success or
  abort (we only mount the LiveView websocket, not longpoll), `use
  Phoenix.VerifiedRoutes` requires a compile-time `:router` module, and
  local-path checks are shared via `Phoenix.URL` so redirects, static
  paths, and `~p` all reject CR/LF in addition to tabs and backslashes.
  `host_to_binary/1` still treats a nil endpoint host as `"localhost"`.
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
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @endpoint_ex Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @ysc_web_ex Path.expand("../../lib/ysc_web.ex", __DIR__)

  describe "1.8.14 lock and JS client" do
    test "locks the Hex package to 1.8.14" do
      assert to_string(Application.spec(:phoenix, :vsn)) == "1.8.14"
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
