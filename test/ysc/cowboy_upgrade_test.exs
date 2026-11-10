defmodule Ysc.CowboyUpgradeTest do
  @moduledoc """
  Guards the cowboy 2.20.0 → 2.21.0 and cowlib 2.21.0 → 2.22.0 upgrade.

  Cowboy 2.21 requires cowlib 2.22 and OTP 27+ (we run OTP 27/28). It is a
  maintenance/security release: HTTP/2 `max_header_list_size` defaults to
  32768 (EEF-CVE-2026-113431), HTTP/1.1 stops reading pipelined bytes until
  the current stream finishes (EEF-CVE-2026-115701), structured-field
  strings reject non-VCHAR (EEF-CVE-2026-43966), and `cowboy_static` no
  longer reads code archives. We serve HTTP via
  `Phoenix.Endpoint.Cowboy2Adapter` and `Plug.Cowboy` in tests; we do not
  call Cowboy or Cowlib APIs, `cowboy_static`, Unix sockets, or structured
  field encoders. Ranch stays 2.3.0.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @user_auth Path.expand("../../lib/ysc_web/user_auth.ex", __DIR__)
  @endpoint Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @cowboy_http Path.expand("../../deps/cowboy/src/cowboy_http.erl", __DIR__)
  @cowboy_http2 Path.expand("../../deps/cowboy/src/cowboy_http2.erl", __DIR__)
  @cowboy_static Path.expand("../../deps/cowboy/src/cowboy_static.erl", __DIR__)
  @cowboy_ws Path.expand("../../deps/cowboy/src/cowboy_websocket.erl", __DIR__)
  @cow_hpack Path.expand("../../deps/cowlib/src/cow_hpack.erl", __DIR__)
  @cow_http2_machine Path.expand(
                       "../../deps/cowlib/src/cow_http2_machine.erl",
                       __DIR__
                     )
  @cow_http_hd Path.expand("../../deps/cowlib/src/cow_http_hd.erl", __DIR__)
  @cow_http_struct_hd Path.expand(
                        "../../deps/cowlib/src/cow_http_struct_hd.erl",
                        __DIR__
                      )
  @cow_cookie Path.expand("../../deps/cowlib/src/cow_cookie.erl", __DIR__)
  @cow_ws Path.expand("../../deps/cowlib/src/cow_ws.erl", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:cowboy)
    {:ok, _} = Application.ensure_all_started(:cowlib)
    {:module, :cowboy} = Code.ensure_loaded(:cowboy)
    {:module, :cow_cookie} = Code.ensure_loaded(:cow_cookie)
    {:module, :cow_ws} = Code.ensure_loaded(:cow_ws)
    {:module, :cow_http_struct_hd} = Code.ensure_loaded(:cow_http_struct_hd)
    {:module, :cow_http2_machine} = Code.ensure_loaded(:cow_http2_machine)
    {:module, :cow_hpack} = Code.ensure_loaded(:cow_hpack)
    :ok
  end

  describe "2.21 / 2.22 Hex lock and public APIs" do
    test "locks cowboy to 2.21.0 and cowlib to 2.22.0" do
      assert to_string(Application.spec(:cowboy, :vsn)) == "2.21.0"
      assert to_string(Application.spec(:cowlib, :vsn)) == "2.22.0"
    end

    test "companion lock is 2.21.0 / 2.22.0 and ranch stays 2.3.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"cowboy": {:hex, :cowboy, "2.21.0"|
      refute lock =~ ~s|"cowboy": {:hex, :cowboy, "2.20.0"|
      assert lock =~ ~s|"cowlib": {:hex, :cowlib, "2.22.0"|
      refute lock =~ ~s|"cowlib": {:hex, :cowlib, "2.21.0"|
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
      refute lock =~ ~s|"ranch": {:hex, :ranch, "2.4.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "mix.exs pins cowboy 2.21 and cowlib 2.22 floors" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:cowboy, "~> 2.21", override: true}|
      assert mix_exs =~ ~s|{:cowlib, "~> 2.22", override: true}|
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

  describe "hex.audit ignores after 2.22" do
    test "drops the patched cowboy/cowlib ignores and keeps cloak IDs" do
      mix_exs = File.read!(@mix_exs)
      refute mix_exs =~ ~s|"EEF-CVE-2026-43966"|
      refute mix_exs =~ ~s|"EEF-CVE-2026-115701"|
      refute mix_exs =~ ~s|"EEF-CVE-2026-113431"|
      refute mix_exs =~ ~s|"EEF-CVE-2026-43969"|
      assert mix_exs =~ ~s|"EEF-CVE-2026-95105"|
      assert mix_exs =~ ~s|"EEF-CVE-2026-94206"|
    end
  end

  describe "2.21 HTTP/2 max_header_list_size (EEF-CVE-2026-113431)" do
    test "cow_http2_machine defaults max_header_list_size to 32768" do
      source = File.read!(@cow_http2_machine)

      assert source =~
               "%% We use a default of 32768 even though the protocol"

      assert source =~ "S4 = setting_from_opt(S3, Opts, max_header_list_size,"
      assert source =~ "max_header_list_size, infinity, 32768),"

      assert source =~
               "The header list size is larger than the configured limit. (RFC9113 6.5.2)"
    end

    test "cowboy_http2 still forwards protocol opts to cow_http2_machine" do
      http2 = File.read!(@cowboy_http2)
      assert http2 =~ "max_header_list_size => 0..16#ffffffff | infinity,"

      assert http2 =~
               "{ok, Preface, HTTP2Machine} = cow_http2_machine:init(server, Opts),"
    end

    test "HPACK-indexed oversized header list is a stream error" do
      {:ok, _preface, s00} =
        :cow_http2_machine.init(:server, %{
          preface_timeout: :infinity,
          settings_timeout: :infinity
        })

      {:ok, s0} = :cow_http2_machine.frame({:settings, %{}}, s00)

      value = :binary.copy("a", 4000)

      headers =
        [
          {":method", "GET"},
          {":scheme", "http"},
          {":path", "/"}
        ] ++ List.duplicate({"user-agent", value}, 9)

      {block0, _state} =
        :cow_hpack.encode(headers, :cow_hpack.init(), %{huffman: false})

      block = IO.iodata_to_binary(block0)

      assert {:error, {:stream_error, 1, :enhance_your_calm, _reason}, _state} =
               :cow_http2_machine.frame(
                 {:headers, 1, :fin, :head_fin, block},
                 s0
               )
    end
  end

  describe "2.21 HTTP/1.1 pipelined buffering (EEF-CVE-2026-115701)" do
    test "cowboy_http stops reading until the current stream finishes" do
      http = File.read!(@cowboy_http)

      assert http =~
               "Delay parsing pipelined requests until current stream stops."

      assert http =~
               "parse(Buffer, State=#state{in_state=ps_next_request, stream=#stream{}}) ->"

      assert http =~ "before_loop(passive(State#state{buffer=Buffer}))"
    end
  end

  describe "2.22 structured-field strings (EEF-CVE-2026-43966)" do
    test "item/1 still builds a quoted string" do
      header =
        {:item, {:string, "hello"}, []}
        |> :cow_http_struct_hd.item()
        |> IO.iodata_to_binary()

      assert header == ~s|"hello"|
    end

    test "item/1 rejects CR/LF in structured-field strings" do
      source = File.read!(@cow_http_struct_hd)
      assert source =~ "escape_string(<<C,R/bits>>, Acc)"
      assert source =~ "when C >= 16#20, C =< 16#7e ->"

      assert_raise FunctionClauseError, fn ->
        :cow_http_struct_hd.item({:item, {:string, "hello\r\nX: y"}, []})
      end
    end
  end

  describe "2.21 cowboy_static no longer reads code archives" do
    test "priv_file and priv_dir resolve via code:priv_dir on the filesystem" do
      static = File.read!(@cowboy_static)
      assert static =~ "case code:priv_dir(App) of"
      refute static =~ "erl_prim_loader"
      refute static =~ "archive"
      refute File.read!(@endpoint) =~ "cowboy_static"
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

    test "HTTP/1.1 pipelined requests still complete in order" do
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
        :"cowboy_upgrade_pipeline_#{port}_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Plug.Cowboy.http(Ysc.CowboyUpgradeEchoPlug, [],
                 port: port,
                 ref: ref
               )

      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      {:ok, client} =
        :gen_tcp.connect(~c"127.0.0.1", port, [
          :binary,
          packet: :raw,
          active: false
        ])

      :ok =
        :gen_tcp.send(
          client,
          "GET /cookie HTTP/1.1\r\nHost: localhost\r\n\r\nGET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        )

      body = recv_until(client, "cowboy-upgrade-ok", 2000)
      :gen_tcp.close(client)

      assert body =~ "cookie-ok"
      assert body =~ "cowboy-upgrade-ok"

      [cookie_at, next_at] =
        Enum.map(["cookie-ok", "cowboy-upgrade-ok"], &:binary.match(body, &1))

      assert elem(cookie_at, 0) < elem(next_at, 0)
    end
  end

  defp recv_until(socket, needle, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    recv_until(socket, needle, deadline, "")
  end

  defp recv_until(socket, needle, deadline, acc) do
    cond do
      String.contains?(acc, needle) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        acc

      true ->
        wait = max(deadline - System.monotonic_time(:millisecond), 1)

        case :gen_tcp.recv(socket, 0, wait) do
          {:ok, data} -> recv_until(socket, needle, deadline, acc <> data)
          {:error, _} -> acc
        end
    end
  end
end
