defmodule YscWeb.Plugs.MetricsAuthTest do
  @moduledoc """
  Tests for MetricsAuth plug: restricts /metrics to private IPs in production.
  """
  use ExUnit.Case, async: false

  import Plug.Test

  alias YscWeb.Plugs.MetricsAuth

  describe "call/2 when request path is not /metrics" do
    test "passes through for any path and IP in production" do
      Ysc.Test.EnvHelper.with_environment(:prod, fn ->
        conn =
          conn(:get, "/")
          |> Map.put(:remote_ip, {8, 8, 8, 8})
          |> MetricsAuth.call([])

        refute conn.halted
        refute conn.status == 404
      end)
    end

    test "passes through for /dashboard and other paths" do
      Ysc.Test.EnvHelper.with_environment(:prod, fn ->
        conn =
          conn(:get, "/dashboard")
          |> Map.put(:remote_ip, {8, 8, 8, 8})
          |> MetricsAuth.call([])

        refute conn.halted
      end)
    end
  end

  describe "call/2 for /metrics in development" do
    test "allows any IP when env is dev" do
      Ysc.Test.EnvHelper.with_environment(:dev, fn ->
        conn =
          conn(:get, "/metrics")
          |> Map.put(:remote_ip, {8, 8, 8, 8})
          |> MetricsAuth.call([])

        refute conn.halted
        refute conn.status == 404
      end)
    end
  end

  describe "call/2 for /metrics in production" do
    setup do
      original = Ysc.Test.EnvHelper.capture_environment!(:prod)
      on_exit(fn -> Ysc.Test.EnvHelper.restore_environment!(original) end)
      :ok
    end

    test "allows private IPv4 loopback (127.0.0.1)" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> MetricsAuth.call([])

      refute conn.halted
      refute conn.status == 404
    end

    test "allows private IPv4 10.x" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {10, 1, 2, 3})
        |> MetricsAuth.call([])

      refute conn.halted
    end

    test "allows private IPv4 172.16-31.x" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {172, 16, 0, 1})
        |> MetricsAuth.call([])

      refute conn.halted

      conn2 =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {172, 31, 255, 255})
        |> MetricsAuth.call([])

      refute conn2.halted
    end

    test "allows private IPv4 192.168.x" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {192, 168, 1, 100})
        |> MetricsAuth.call([])

      refute conn.halted
    end

    test "allows IPv6 loopback (::1)" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0, 0, 1})
        |> MetricsAuth.call([])

      refute conn.halted
    end

    test "allows Fly internal IPv6 (fdaa::/16)" do
      # fdaa:0:0:0:0:0:0:0:1
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {0xFDA0, 0, 0, 0, 0, 0, 0, 1})
        |> MetricsAuth.call([])

      refute conn.halted
    end

    test "returns 404 and halts for public IPv4" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {8, 8, 8, 8})
        |> MetricsAuth.call([])

      assert conn.halted
      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end

    test "returns 404 and halts for public IPv4 (other range)" do
      conn =
        conn(:get, "/metrics")
        |> Map.put(:remote_ip, {203, 0, 113, 1})
        |> MetricsAuth.call([])

      assert conn.halted
      assert conn.status == 404
    end

    test "returns 404 for path prefix /metrics/foo" do
      # Plug matches request_path which would be "/metrics/foo"
      conn =
        conn(:get, "/metrics/foo")
        |> Map.put(:remote_ip, {8, 8, 8, 8})
        |> MetricsAuth.call([])

      assert conn.halted
      assert conn.status == 404
    end
  end

  describe "init/1" do
    test "returns opts unchanged" do
      assert MetricsAuth.init(:some_opts) == :some_opts
    end
  end
end
