defmodule YscWeb.PhoenixUpgradeTest do
  use ExUnit.Case, async: true

  @phoenix_js Path.expand("../../deps/phoenix/priv/static/phoenix.js", __DIR__)
  @phoenix_socket_js Path.expand(
                       "../../deps/phoenix/assets/js/phoenix/socket.js",
                       __DIR__
                     )
  @app_js Path.expand("../../assets/js/app.js", __DIR__)

  describe "1.8.13 lock and JS client" do
    test "locks the Hex package to 1.8.13" do
      assert to_string(Application.spec(:phoenix, :vsn)) == "1.8.13"
    end

    test "companion phoenix_pubsub lock is 2.3.0 with the APIs we use" do
      assert to_string(Application.spec(:phoenix_pubsub, :vsn)) == "2.3.0"
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

    test "socket and endpoint modules we use still load" do
      assert {:module, Phoenix.Socket} = Code.ensure_loaded(Phoenix.Socket)
      assert {:module, Phoenix.Endpoint} = Code.ensure_loaded(Phoenix.Endpoint)

      assert {:module, Phoenix.LiveView.Socket} =
               Code.ensure_loaded(Phoenix.LiveView.Socket)
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

    test "reconnect path separates disconnect() and connect() onto different ticks" do
      js = File.read!(@app_js)

      # disconnect() must settle (channels -> "errored", old socket closed)
      # before connect() runs, otherwise the channel never rejoins.
      assert js =~ "function forceReconnect()"
      assert js =~ ~r/liveSocket\.disconnect\(\);\s*\n\s*setTimeout\(\(\) => liveSocket\.connect\(\), \d+\)/
    end
  end
end
