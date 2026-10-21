defmodule YscWeb.PhoenixUpgradeTest do
  @moduledoc """
  Guards the Phoenix 1.8.15 → 1.8.16 upgrade.

  1.8.16 is a patch. phoenix.js rewrites connection lifecycle around a
  per-transport `Connection` object so late close/error events, overlapping
  disconnect/connect, heartbeat timeouts, and LongPoll fallback cannot tear
  down a healthy replacement (#6867). Close code 1000 is no longer treated
  as a permanent disconnect (#6880); any close that we did not initiate
  reconnects, because proxies also use 1000. `Phoenix.Endpoint.socket/3`
  accepts `:max_channels_per_transport` (default 100).

  Phoenix 1.8.16 requires `phoenix_pubsub ~> 2.4` (lock 2.4.1). That adds
  `Phoenix.PubSub.Sender` and `unsubscribe_sender/3`. We only call
  `subscribe/2`, `unsubscribe/2`, and `broadcast/3` with the default
  dispatcher. `phoenix_template` stays 1.0.4.

  We import `phoenix` via esbuild `NODE_PATH=deps` and mount only the
  LiveView websocket. Logout still broadcasts `"disconnect"`. We do not
  set `:max_channels_per_transport` on the LiveView socket.
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
  @phoenix_connection_js Path.expand(
                           "../../deps/phoenix/assets/js/phoenix/connection.js",
                           __DIR__
                         )
  @phoenix_changelog Path.expand("../../deps/phoenix/CHANGELOG.md", __DIR__)
  @phoenix_cert Path.expand(
                  "../../deps/phoenix/lib/mix/tasks/phx.gen.cert.ex",
                  __DIR__
                )
  @phoenix_endpoint_ex Path.expand(
                         "../../deps/phoenix/lib/phoenix/endpoint.ex",
                         __DIR__
                       )
  @phoenix_socket_ex Path.expand(
                       "../../deps/phoenix/lib/phoenix/socket.ex",
                       __DIR__
                     )
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @endpoint_ex Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @ysc_web_ex Path.expand("../../lib/ysc_web.ex", __DIR__)
  @user_auth_ex Path.expand("../../lib/ysc_web/user_auth.ex", __DIR__)
  @application_ex Path.expand("../../lib/ysc/application.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)

  describe "1.8.16 lock and JS client" do
    test "locks the Hex package to 1.8.16" do
      assert to_string(Application.spec(:phoenix, :vsn)) == "1.8.16"
      assert File.read!(@mix_exs) =~ ~s({:phoenix, "~> 1.8.16"})
    end

    test "companion phoenix_pubsub lock is 2.4.1 with the APIs we use" do
      assert to_string(Application.spec(:phoenix_pubsub, :vsn)) == "2.4.1"
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_pubsub": {:hex, :phoenix_pubsub, "2.4.1"|
      refute lock =~ ~s|"phoenix_pubsub": {:hex, :phoenix_pubsub, "2.3.0"|

      assert {:module, _} = Code.ensure_loaded(Phoenix.PubSub)
      assert function_exported?(Phoenix.PubSub, :subscribe, 2)
      assert function_exported?(Phoenix.PubSub, :broadcast, 3)
      assert function_exported?(Phoenix.PubSub, :unsubscribe, 2)
      assert function_exported?(Phoenix.PubSub, :unsubscribe_sender, 3)

      assert {:module, Phoenix.PubSub.Sender} =
               Code.ensure_loaded(Phoenix.PubSub.Sender)
    end

    test "companion phoenix_template lock stays 1.0.4" do
      assert to_string(Application.spec(:phoenix_template, :vsn)) == "1.0.4"
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      refute lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
    end

    test "app PubSub uses the default dispatcher and no sender metadata" do
      source = File.read!(@application_ex)
      assert source =~ "{Phoenix.PubSub, name: Ysc.PubSub}"
      refute source =~ "dispatcher:"
      refute source =~ "unsubscribe_sender"
      refute source =~ "unsubscribe_match"
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

  describe "1.8.16 connection races and close code 1000" do
    test "changelog documents the JS race and close-code 1000 fixes" do
      changelog = File.read!(@phoenix_changelog)

      assert changelog =~ "## v1.8.16 (2026-10-20)"
      assert changelog =~ "Fix a lot of connection handling races"
      assert changelog =~ "#6867"
      assert changelog =~ "Don't treat WebSocket close code 1000 as special"
      assert changelog =~ "#6880"
      assert changelog =~ "max_channels_per_transport"
    end

    test "Connection only forwards events while it is the socket's current transport" do
      source = File.read!(@phoenix_connection_js)

      assert source =~ "export default class Connection"
      assert source =~ "this.ended = false"
      assert source =~ "this.closing = false"
      assert source =~ "isCurrent(){ return this.socket.connection === this }"

      assert source =~
               "transport.onopen = () => { if(this.isCurrent()){ socket.onConnOpen() } }"

      assert source =~
               "transport.onerror = error => { if(this.isCurrent()){ socket.onConnError(error) } }"

      assert source =~
               "transport.onmessage = event => { if(this.isCurrent()){ socket.onConnMessage(event) } }"

      assert source =~ "if(this.isCurrent() && !this.closeHandled)"
    end

    test "replaceTransport ends the old connection before close so late events stay off the new one" do
      source = File.read!(@phoenix_socket_js)

      assert source =~ "replaceTransport(newTransport)"
      assert source =~ "this.connection = null"
      assert source =~ "connection.ended = true"
      assert source =~ "connection.close()"
      assert source =~ "this.clearHeartbeats()"

      assert source =~
               ~s|if(wasOpen){ this.triggerChanError("connection_closed", connection) }|

      assert source =~ "teardownAndReconnect(reconnect)"
      assert source =~ "stillUses(connection)"
    end

    test "onConnClose reconnects on any close we did not initiate, including 1000" do
      source = File.read!(@phoenix_socket_js)

      assert source =~
               "proxies and load balancers also close with 1000 (normal closure)"

      assert source =~ "const closedByUs = !!(connection && connection.closing)"

      assert source =~
               "if(this.stillUses(connection) && !closedByUs && !this.closeWasClean)"

      refute source =~ "closeCode !== 1000"
      refute source =~ "closeCode !== 1e3"
    end

    test "bundled phoenix.js ships Connection isolation and 1000 reconnect" do
      js = File.read!(@phoenix_js)

      assert js =~ "isCurrent()"
      assert js =~ "this.ended = false"
      assert js =~ "connection.ended = true"
      assert js =~ "stillUses(connection)"
      assert js =~ "const closedByUs = !!(connection && connection.closing)"

      # Bundled phoenix.js strips comments; reconnect on 1000 is the
      # `!closedByUs && !this.closeWasClean` gate, not a closeCode check.
      refute js =~ "closeCode !== 1e3"
      refute js =~ "closeCode !== 1000"
    end

    test "logout still broadcasts disconnect; the socket stop no longer pins close 1001" do
      auth = File.read!(@user_auth_ex)
      socket = File.read!(@phoenix_socket_ex)

      assert auth =~
               ~s|YscWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})|

      assert socket =~
               ~s|def __info__(%Broadcast{event: "disconnect"}, state) do|

      assert socket =~ "{:stop, {:shutdown, :disconnected}, state}"
      refute socket =~ "{:stop, {:shutdown, :disconnected}, 1001, state}"
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

  describe "1.8.16 max_channels_per_transport on Endpoint.socket/3" do
    test "Endpoint.socket/3 copies a positive cap into the transport config" do
      endpoint = File.read!(@phoenix_endpoint_ex)
      socket = File.read!(@phoenix_socket_ex)

      assert endpoint =~ ~s|* `:max_channels_per_transport`|
      assert endpoint =~ "defp put_socket_opts(transport_opts, opts)"
      assert endpoint =~ "Keyword.fetch(opts, :max_channels_per_transport)"

      assert endpoint =~
               ~s|:max_channels_per_transport must be a positive integer|

      assert socket =~
               "max_channels_per_transport: Keyword.get(options, :max_channels_per_transport, 100)"
    end

    test "LiveView socket keeps the default cap" do
      source = File.read!(@endpoint_ex)

      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket|
      assert source =~ "websocket: [connect_info:"
      refute source =~ "max_channels_per_transport"
      refute source =~ "longpoll:"
    end
  end

  describe "1.8.16 unused generator changes" do
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

  describe "phoenix_pubsub 2.4.1 subscribe APIs we do not use" do
    test "list-shaped :metadata is reserved for senders and raises" do
      name = :"ysc_phoenix_upgrade_pubsub_#{System.unique_integer([:positive])}"
      start_supervised!({Phoenix.PubSub, name: name})

      assert Phoenix.PubSub.subscribe(name, "users:1") == :ok
      assert Phoenix.PubSub.broadcast(name, "users:1", :ping) == :ok
      assert_receive :ping
      assert Phoenix.PubSub.unsubscribe(name, "users:1") == :ok

      assert_raise RuntimeError,
                   "passing metadata in the shape of [module | term] to subscribe is unsupported",
                   fn ->
                     Phoenix.PubSub.subscribe(name, "users:1",
                       metadata: [:reserved_sender]
                     )
                   end
    end
  end
end
