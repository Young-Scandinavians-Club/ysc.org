defmodule Ysc.CowboyUpgradeTest do
  @moduledoc """
  Guards the cowboy 2.18.0 → 2.19.0 and cowlib 2.19.0 → 2.20.0 upgrade.

  Cowboy 2.19 requires cowlib 2.20 and OTP 27+ (we run OTP 27/28). It labels
  connection processes, only indexes known-safe HPACK fields (HTTP/2 messages
  may be larger), and tightens protocol number parsing (digit limit 17 → 20).
  We serve HTTP via `Phoenix.Endpoint.Cowboy2Adapter` and `Plug.Cowboy` in
  tests; we do not call Cowboy or Cowlib APIs directly. Hex still reports
  EEF-CVE-2026-43966/43969/43971 on cowlib 2.20.0 (ignored in mix.exs).
  """
  use ExUnit.Case, async: false

  @cowboy_http Path.expand("../../deps/cowboy/src/cowboy_http.erl", __DIR__)
  @cow_hpack Path.expand("../../deps/cowlib/src/cow_hpack.erl", __DIR__)
  @cow_http_hd Path.expand("../../deps/cowlib/src/cow_http_hd.erl", __DIR__)

  describe "2.19 / 2.20 Hex lock and public APIs" do
    test "locks cowboy to 2.19.0 and cowlib to 2.20.0" do
      assert to_string(Application.spec(:cowboy, :vsn)) == "2.19.0"
      assert to_string(Application.spec(:cowlib, :vsn)) == "2.20.0"
    end

    test "ranch companion lock is 2.3.0 from the matching ninenines release" do
      assert to_string(Application.spec(:ranch, :vsn)) == "2.3.0"
    end

    test "OTP 27 floor is satisfied" do
      otp =
        :erlang.system_info(:otp_release)
        |> List.to_string()
        |> String.to_integer()

      assert otp >= 27
    end

    test "Plug.Cowboy APIs we call still exist" do
      assert function_exported?(Plug.Cowboy, :http, 3)
      assert function_exported?(Plug.Cowboy, :shutdown, 1)
    end

    test "endpoint still uses the Cowboy2 adapter" do
      assert YscWeb.Endpoint.config(:adapter) == Phoenix.Endpoint.Cowboy2Adapter
    end
  end

  describe "2.19 process labels and HPACK indexing" do
    test "HTTP connection processes set a proc_lib label" do
      http = File.read!(@cowboy_http)
      assert http =~ "proc_lib:set_label({?MODULE, Ref})"
    end

    test "HPACK encode only indexes known-safe field names" do
      hpack = File.read!(@cow_hpack)
      assert hpack =~ "can_index(Name)"
      assert hpack =~ "can_index(_) -> false."
    end

    test "protocol number parsing allows 20 digits" do
      http_hd = File.read!(@cow_http_hd)
      assert http_hd =~ "-define(MAX_DIGITS, 20)."
    end
  end

  describe "Plug.Cowboy still serves HTTP" do
    test "Plug.Cowboy.http/3 starts a listener that answers GET" do
      {:ok, socket} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true
        ])

      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      ref = :"cowboy_upgrade_#{port}_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Plug.Cowboy.http(Ysc.CowboyUpgradeEchoPlug, [],
                 port: port,
                 ref: ref
               )

      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
      assert response.body == "cowboy-upgrade-ok"
    end
  end
end
