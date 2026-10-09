defmodule Ysc.CowboyUpgradeTest do
  @moduledoc """
  Guards the cowboy 2.19.0 → 2.20.0 and cowlib 2.20.0 → 2.21.0 upgrade.

  Cowboy 2.20 requires cowlib 2.21 and OTP 27+ (we run OTP 27/28). It is a
  maintenance release: cookie encoding validates Cookie names/values
  (EEF-CVE-2026-43969), RFC6265bis cookies, no obsolete Set-Cookie Expires,
  ignore of `x-webkit-deflate-frame` (`permessage-deflate` is unchanged),
  HPACK decode after RST_STREAM, and stricter HTTP dates. We serve HTTP via
  `Phoenix.Endpoint.Cowboy2Adapter` and `Plug.Cowboy` in tests; we do not
  call Cowboy or Cowlib APIs directly. Hex still reports EEF-CVE-2026-43966
  on cowlib 2.21.0 (ignored in mix.exs).
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @user_auth Path.expand("../../lib/ysc_web/user_auth.ex", __DIR__)
  @endpoint Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @cowboy_http Path.expand("../../deps/cowboy/src/cowboy_http.erl", __DIR__)
  @cowboy_ws Path.expand("../../deps/cowboy/src/cowboy_websocket.erl", __DIR__)
  @cow_hpack Path.expand("../../deps/cowlib/src/cow_hpack.erl", __DIR__)
  @cow_http_hd Path.expand("../../deps/cowlib/src/cow_http_hd.erl", __DIR__)
  @cow_cookie Path.expand("../../deps/cowlib/src/cow_cookie.erl", __DIR__)
  @cow_ws Path.expand("../../deps/cowlib/src/cow_ws.erl", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:cowboy)
    {:ok, _} = Application.ensure_all_started(:cowlib)
    {:module, :cowboy} = Code.ensure_loaded(:cowboy)
    {:module, :cow_cookie} = Code.ensure_loaded(:cow_cookie)
    {:module, :cow_ws} = Code.ensure_loaded(:cow_ws)
    :ok
  end

  describe "2.20 / 2.21 Hex lock and public APIs" do
    test "locks cowboy to 2.20.0 and cowlib to 2.21.0" do
      assert to_string(Application.spec(:cowboy, :vsn)) == "2.20.0"
      assert to_string(Application.spec(:cowlib, :vsn)) == "2.21.0"
    end

    test "companion lock is 2.20.0 / 2.21.0 and ranch stays 2.3.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"cowboy": {:hex, :cowboy, "2.20.0"|
      refute lock =~ ~s|"cowboy": {:hex, :cowboy, "2.19.0"|
      assert lock =~ ~s|"cowlib": {:hex, :cowlib, "2.21.0"|
      refute lock =~ ~s|"cowlib": {:hex, :cowlib, "2.20.0"|
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
    end

    test "mix.exs pins cowboy 2.20 and cowlib 2.21 floors" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:cowboy, "~> 2.20", override: true}|
      assert mix_exs =~ ~s|{:cowlib, "~> 2.21", override: true}|
    end

    test "OTP 27 floor is satisfied" do
      otp =
        :erlang.system_info(:otp_release)
        |> List.to_string()
        |> String.to_integer()

      assert otp >= 27
    end

    test "Plug.Cowboy APIs we call still exist" do
      assert {:module, _} = Code.ensure_loaded(Plug.Cowboy)
      assert function_exported?(Plug.Cowboy, :http, 3)
      assert function_exported?(Plug.Cowboy, :shutdown, 1)
    end

    test "endpoint still uses the Cowboy2 adapter" do
      assert YscWeb.Endpoint.config(:adapter) == Phoenix.Endpoint.Cowboy2Adapter
    end

    test "app code still does not call Cowboy or Cowlib APIs" do
      auth = File.read!(@user_auth)
      endpoint = File.read!(@endpoint)
      refute auth =~ "cowboy_req"
      refute auth =~ "cow_cookie"
      refute endpoint =~ "cowboy_req"
      refute endpoint =~ "cow_cookie"
    end
  end

  describe "2.19 process labels and HPACK indexing still hold" do
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

  describe "2.20 x-webkit-deflate-frame is ignored" do
    test "cow_ws negotiate_x_webkit_deflate_frame always returns ignore" do
      ws = File.read!(@cow_ws)
      assert ws =~ "negotiate_x_webkit_deflate_frame(_, _, _) ->"
      assert ws =~ "ignore."

      {:module, :cow_ws} = Code.ensure_loaded(:cow_ws)
      assert function_exported?(:cow_ws, :negotiate_x_webkit_deflate_frame, 3)
      assert :cow_ws.negotiate_x_webkit_deflate_frame([], %{}, %{}) == :ignore
    end

    test "cowboy websocket still negotiates permessage-deflate only" do
      websocket = File.read!(@cowboy_ws)
      assert websocket =~ ~s'[{<<"permessage-deflate">>, Params}|Tail]'
      refute websocket =~ "x-webkit-deflate-frame"

      assert websocket =~
               "websocket_extensions(State, Req, [_|Tail], RespHeader)"
    end
  end

  describe "2.21 cookie encoder (EEF-CVE-2026-43969)" do
    test "cookie/1 still builds a valid Cookie header" do
      header =
        [{<<"a">>, <<"b">>}, {<<"c">>, <<"d">>}]
        |> :cow_cookie.cookie()
        |> IO.iodata_to_binary()

      assert header == "a=b; c=d"
    end

    test "cookie/1 rejects CRLF and semicolon injection" do
      assert_raise ArgumentError, fn ->
        :cow_cookie.cookie([{<<"a">>, <<"b\r\nX: y">>}])
      end

      assert_raise ArgumentError, fn ->
        :cow_cookie.cookie([{<<"a">>, <<"b; admin=1">>}])
      end
    end

    test "setcookie/3 emits Max-Age and SameSite without Expires" do
      header =
        :cow_cookie.setcookie("upgrade", "ok", %{
          max_age: 60,
          same_site: :lax,
          http_only: true
        })
        |> IO.iodata_to_binary()

      assert header =~ "upgrade=ok"
      assert header =~ "Max-Age=60"
      assert header =~ "SameSite=Lax"
      assert header =~ "HttpOnly"
      refute header =~ "Expires"
    end

    test "cookie source validates names and values before serializing" do
      source = File.read!(@cow_cookie)
      assert source =~ "validate_cookie_chars(Bin, Kind)"
      assert source =~ "C =:= $;"
      refute source =~ ~s|attributes([{expires,|
    end
  end

  describe "hex.audit ignores after 2.21" do
    test "drops the patched 43969 ignore and keeps 43966" do
      mix_exs = File.read!(@mix_exs)
      refute mix_exs =~ ~s|"EEF-CVE-2026-43969"|
      assert mix_exs =~ ~s|"EEF-CVE-2026-43966"|
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

    test "Plug.Conn cookies still round-trip through Cowboy" do
      {:ok, socket} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true
        ])

      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      ref =
        :"cowboy_upgrade_cookie_#{port}_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Plug.Cowboy.http(Ysc.CowboyUpgradeEchoPlug, [],
                 port: port,
                 ref: ref
               )

      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      response = Req.get!("http://127.0.0.1:#{port}/cookie")
      assert response.status == 200
      assert response.body == "cookie-ok"

      set_cookie =
        response.headers
        |> Map.get("set-cookie", [])
        |> List.wrap()
        |> Enum.join("; ")

      assert set_cookie =~ "upgrade="
      assert String.contains?(String.downcase(set_cookie), "max-age=60")
      assert String.contains?(String.downcase(set_cookie), "samesite=lax")
    end
  end
end
