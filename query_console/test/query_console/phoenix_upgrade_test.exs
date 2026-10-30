defmodule QueryConsole.PhoenixUpgradeTest do
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
  `Phoenix.PubSub.Sender` and `unsubscribe_sender/3`. Query Console only
  starts `{Phoenix.PubSub, name: QueryConsole.PubSub}` with the default
  dispatcher. `phoenix_template` is 1.1.0 (via LiveView 1.2).

  We import `phoenix` via esbuild `NODE_PATH=deps`, enable LongPoll on the
  LiveView socket (`longpoll:` plus `longPollFallbackMs: 2500`), and keep
  the default channel cap. Logout is SSO redirect, not a `"disconnect"`
  broadcast. 1.8.15 `replaceTransport` detach-before-close is superseded
  by the Connection class.
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
  @phoenix_longpoll_js Path.expand(
                         "../../deps/phoenix/assets/js/phoenix/longpoll.js",
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
  @endpoint_ex Path.expand("../../lib/query_console_web/endpoint.ex", __DIR__)
  @web_ex Path.expand("../../lib/query_console_web.ex", __DIR__)
  @application_ex Path.expand("../../lib/query_console/application.ex", __DIR__)
  @user_auth_ex Path.expand("../../lib/query_console_web/user_auth.ex", __DIR__)
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
      refute lock =~ ~s|"phoenix_pubsub": {:hex, :phoenix_pubsub, "2.2.0"|
      refute lock =~ ~s|"phoenix_pubsub": {:hex, :phoenix_pubsub, "2.3.0"|

      assert {:module, _} = Code.ensure_loaded(Phoenix.PubSub)
      assert function_exported?(Phoenix.PubSub, :subscribe, 2)
      assert function_exported?(Phoenix.PubSub, :broadcast, 3)
      assert function_exported?(Phoenix.PubSub, :unsubscribe, 2)
      assert function_exported?(Phoenix.PubSub, :unsubscribe_sender, 3)

      assert {:module, Phoenix.PubSub.Sender} =
               Code.ensure_loaded(Phoenix.PubSub.Sender)
    end

    test "companion phoenix_template lock is 1.1.0" do
      assert to_string(Application.spec(:phoenix_template, :vsn)) == "1.1.0"
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
      refute lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "app PubSub uses the default dispatcher and no sender metadata" do
      source = File.read!(@application_ex)
      assert source =~ "{Phoenix.PubSub, name: QueryConsole.PubSub}"
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

    test "logout is SSO redirect, not a LiveView disconnect broadcast" do
      auth = File.read!(@user_auth_ex)
      socket = File.read!(@phoenix_socket_ex)

      refute auth =~ "broadcast"
      refute auth =~ ~s|"disconnect"|
      assert auth =~ "renew_session()"
      assert auth =~ "delete_session(:user_id)"

      # Phoenix still stops the socket on a disconnect broadcast; we do not
      # send one. The 1.8.16 stop tuple no longer pins close code 1001.
      assert socket =~
               ~s|def __info__(%Broadcast{event: "disconnect"}, state) do|

      assert socket =~ "{:stop, {:shutdown, :disconnected}, state}"
      refute socket =~ "{:stop, {:shutdown, :disconnected}, 1001, state}"
    end

    test "app.js loads phoenix from deps and enables longpoll fallback" do
      app = File.read!(@app_js)
      config = File.read!(@config_exs)

      assert app =~ ~s|import {Socket} from "phoenix"|
      assert config =~ ~s|"NODE_PATH"|
      assert config =~ ~s|Path.expand("../deps", __DIR__)|

      # LiveSocket falls back to LongPoll, which calls replaceTransport.
      # We do not call replaceTransport ourselves.
      assert app =~ "longPollFallbackMs: 2500"
      refute app =~ "replaceTransport"
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

    test "LiveView socket keeps the default cap and enables longpoll" do
      source = File.read!(@endpoint_ex)

      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket|
      assert source =~ "websocket: [connect_info:"
      assert source =~ "longpoll: [connect_info:"
      refute source =~ "max_channels_per_transport"
    end
  end

  describe "1.8.16 unused generator changes" do
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

      # 1.8.16 (#6867) added an error argument so LongPoll can emit onerror
      # before close, matching WebSocket. Timeout still maps to close 1005.
      assert source =~ "closeAndRetry(error, code, reason, wasClean)"
      assert source =~ "this.onerror(error)"
      assert source =~ ~s|this.closeAndRetry("timeout", 1005, "timeout", false)|

      assert source =~
               ~s|this.ajax("POST", {"Content-Type": "application/x-ndjson"}|

      assert source =~ ~s|() => this.ontimeout()|
    end

    test "bundled phoenix.js ships the same POST timeout retry" do
      js = File.read!(@phoenix_js)

      assert js =~ "closeAndRetry(error, code, reason, wasClean)"
      assert js =~ ~s|this.closeAndRetry("timeout", 1005, "timeout", false)|
      assert js =~ ~s|"Content-Type": "application/x-ndjson"|
      assert js =~ "() => this.ontimeout()"
    end
  end

  describe "phoenix_pubsub 2.4.1 subscribe APIs we do not use" do
    test "list-shaped :metadata is reserved for senders and raises" do
      name =
        :"qc_phoenix_upgrade_pubsub_#{System.unique_integer([:positive])}"

      start_supervised!({Phoenix.PubSub, name: name})

      assert Phoenix.PubSub.subscribe(name, "users:1") == :ok
      assert Phoenix.PubSub.broadcast(name, "users:1", :ping) == :ok
      assert_receive :ping
      assert Phoenix.PubSub.unsubscribe(name, "users:1") == :ok

      assert_raise RuntimeError,
                   "passing metadata in the shape of [module | term] to subscribe is unsupported",
                   fn ->
                     Phoenix.PubSub.subscribe(name, "users:1", metadata: [:reserved_sender])
                   end
    end
  end
end
