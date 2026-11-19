defmodule Ysc.RanchUpgradeTest do
  @moduledoc """
  Guards the ranch 2.3.0 → 2.4.0 upgrade.

  Ranch 2.4 is a maintenance release tested with OTP 27+. It adds the
  `trusted_proxies` transport option (opt-in; absent means any peer may
  send a PROXY header), `ranch:trace_acceptors/1,2`, optional
  `peercert/1` and `negotiated_protocol/1` on `ranch_ssl`, and PROXY v2
  SSL TLV subtypes `group`, `sig_scheme`, and `client_cert`. It also
  rejects PROXY v1 lines longer than 107 bytes, raises from
  `child_spec/5` on invalid transport options, and only deletes a
  `{local, Path}` file when it is a socket or FIFO.

  We serve HTTP via `Phoenix.Endpoint.Cowboy2Adapter` and `Plug.Cowboy`.
  Sandbox idle shutdown uses `:ranch.procs/2`. We do not enable PROXY
  protocol (Fly client IP is HTTP headers via `YscWeb.ClientIP`). We do
  not pass `trusted_proxies`, Unix sockets, or call `recv_proxy_header/2`.
  cowboy 2.21 still allows ranch `>= 1.8`; we pin 2.4.0. extras: none.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @endpoint Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @client_ip Path.expand("../../lib/ysc_web/client_ip.ex", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @dev Path.expand("../../config/dev.exs", __DIR__)
  @test_config Path.expand("../../config/test.exs", __DIR__)
  @ranch_erl Path.expand("../../deps/ranch/src/ranch.erl", __DIR__)
  @ranch_tcp Path.expand("../../deps/ranch/src/ranch_tcp.erl", __DIR__)
  @ranch_ssl Path.expand("../../deps/ranch/src/ranch_ssl.erl", __DIR__)
  @ranch_proxy Path.expand(
                 "../../deps/ranch/src/ranch_proxy_header.erl",
                 __DIR__
               )
  @ranch_transport Path.expand(
                     "../../deps/ranch/src/ranch_transport.erl",
                     __DIR__
                   )
  @readme Path.expand("../../deps/ranch/README.asciidoc", __DIR__)

  # PROXY v1 spec cap is 107 bytes including CRLF (PP 2.1).
  @proxy_v1_107 ~S"PROXY UNKNOWN ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff 65535 65535" <>
                  "\r\n"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ranch)
    {:ok, _} = Application.ensure_all_started(:cowboy)
    {:module, :ranch} = Code.ensure_loaded(:ranch)
    {:module, :ranch_tcp} = Code.ensure_loaded(:ranch_tcp)
    {:module, :ranch_ssl} = Code.ensure_loaded(:ranch_ssl)
    {:module, :ranch_proxy_header} = Code.ensure_loaded(:ranch_proxy_header)
    :ok
  end

  describe "2.4.0 Hex lock and public APIs" do
    test "locks the Hex package to 2.4.0" do
      assert to_string(Application.spec(:ranch, :vsn)) == "2.4.0"
    end

    test "mix.exs pins the 2.4.0 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:ranch, "~> 2.4.0", override: true}|
      refute mix_exs =~ ~s|Ranch stays 2.3.0|
    end

    test "companion extras stay on cowboy 2.21.0, cowlib 2.22.0, phoenix_template 1.0.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.4.0"|
      refute lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
      assert lock =~ ~s|"cowboy": {:hex, :cowboy, "2.21.0"|
      assert lock =~ ~s|"cowlib": {:hex, :cowlib, "2.22.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      assert lock =~ ~s|"websock_adapter": {:hex, :websock_adapter, "0.6.0"|
      assert lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.2"|
      assert lock =~ ~s|"plug": {:hex, :plug, "1.20.4"|
    end

    test "OTP 27 floor is satisfied" do
      otp =
        :erlang.system_info(:otp_release)
        |> List.to_string()
        |> String.to_integer()

      assert otp >= 27
    end

    test "APIs we invoke still exist" do
      assert function_exported?(:ranch, :procs, 2)
      assert function_exported?(:ranch, :info, 0)
      assert function_exported?(:ranch, :get_status, 1)
      assert function_exported?(:ranch, :get_max_connections, 1)
      assert function_exported?(:ranch, :set_transport_options, 2)
      assert function_exported?(:ranch, :child_spec, 5)
      assert function_exported?(:ranch, :stop_listener, 1)
      assert function_exported?(:ranch, :remove_connection, 2)
      assert function_exported?(:ranch, :trace_acceptors, 1)
      assert function_exported?(:ranch, :trace_acceptors, 2)
      assert function_exported?(:ranch_proxy_header, :parse, 1)
      assert function_exported?(:ranch_proxy_header, :header, 1)
    end

    test "guide documents 2.4" do
      readme = File.read!(@readme)
      assert readme =~ "https://ninenines.eu/docs/en/ranch/2.4/guide"
      assert readme =~ "https://ninenines.eu/docs/en/ranch/2.4/manual"
    end

    test "hex.audit ignores the blocked idna punycode advisory and keeps cloak IDs" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|"EEF-CVE-2026-117678"|
      assert mix_exs =~ ~s|"EEF-CVE-2026-95105"|
      assert mix_exs =~ ~s|"EEF-CVE-2026-94206"|
    end
  end

  describe "sandbox idle shutdown still uses ranch.procs/2" do
    test "application.ex still counts HTTP connections via ranch.procs/2" do
      source = File.read!(@application)
      assert source =~ ":ranch.procs(YscWeb.Endpoint.HTTP, :connections)"
    end

    test "endpoint still uses the Cowboy2 adapter" do
      assert YscWeb.Endpoint.config(:adapter) == Phoenix.Endpoint.Cowboy2Adapter
    end
  end

  describe "we do not enable PROXY protocol" do
    test "endpoint and config do not pass proxy_header or trusted_proxies" do
      files = [
        File.read!(@endpoint),
        File.read!(@runtime),
        File.read!(@dev),
        File.read!(@test_config)
      ]

      Enum.each(files, fn source ->
        refute source =~ ~r/\bproxy_header\b/
        refute source =~ "trusted_proxies"
        refute source =~ "recv_proxy_header"
        refute source =~ "{local,"
      end)
    end

    test "Fly client IP is HTTP headers, not a Ranch PROXY header" do
      source = File.read!(@client_ip)
      assert source =~ "Fly-Client-IP"
      assert source =~ "trust_proxy_headers"
      refute source =~ "recv_proxy_header"
      refute source =~ "trusted_proxies"
      refute source =~ "ranch_proxy_header"
    end
  end

  describe "2.4 trusted_proxies is opt-in" do
    test "child_spec/5 accepts a valid IPv4 prefix" do
      spec =
        :ranch.child_spec(
          :ysc_ranch_trusted_ok,
          :ranch_tcp,
          %{trusted_proxies: [{{10, 0, 0, 1}, 32}]},
          :cowboy_clear,
          %{}
        )

      assert spec.id == {:ranch_embedded_sup, :ysc_ranch_trusted_ok}
      assert spec.type == :supervisor
    end

    test "child_spec/5 accepts an empty list (reject every peer)" do
      spec =
        :ranch.child_spec(
          :ysc_ranch_trusted_empty,
          :ranch_tcp,
          %{trusted_proxies: []},
          :cowboy_clear,
          %{}
        )

      assert spec.id == {:ranch_embedded_sup, :ysc_ranch_trusted_empty}
    end

    test "child_spec/5 raises on a non-list trusted_proxies value" do
      error =
        assert_raise ArgumentError, fn ->
          :ranch.child_spec(
            :ysc_ranch_trusted_bad,
            :ranch_tcp,
            %{trusted_proxies: "nope"},
            :cowboy_clear,
            %{}
          )
        end

      assert error.message == "argument error: {:bad_option, :trusted_proxies}"
    end

    test "child_spec/5 rejects IPv4-mapped IPv6 trusted_proxies" do
      error =
        assert_raise ArgumentError, fn ->
          :ranch.child_spec(
            :ysc_ranch_trusted_mapped,
            :ranch_tcp,
            %{trusted_proxies: [{{0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}, 128}]},
            :cowboy_clear,
            %{}
          )
        end

      assert error.message == "argument error: {:bad_option, :trusted_proxies}"
    end

    test "recv_proxy_header allows any peer when trusted_proxies is absent" do
      source = File.read!(@ranch_erl)
      assert source =~ "trusted_proxies => [trusted_proxy()]"
      assert source =~ ~S"#{trusted_proxies := Trusted} = TransOpts ->"
      assert source =~ "Ranch rejected a PROXY protocol connection"
      assert source =~ ~S|_ ->|
      assert source =~ ~S|ok|
    end
  end

  describe "2.4 PROXY header parsing" do
    test "version 1 line of 107 bytes still parses" do
      assert byte_size(@proxy_v1_107) == 107

      assert {:ok, info, ""} = :ranch_proxy_header.parse(@proxy_v1_107)
      assert info.version == 1
      assert info.command == :proxy
    end

    test "version 1 line longer than 107 bytes is rejected before decode" do
      <<prefix::binary-size(105), "\r\n">> = @proxy_v1_107
      too_long = prefix <> "x\r\n"
      assert byte_size(too_long) == 108

      assert {:error, reason} = :ranch_proxy_header.parse(too_long)

      assert reason ==
               :"The PROXY protocol header line exceeds 107 bytes. (PP 2.1)"
    end

    test "TCP4 version 1 header still round-trips addresses" do
      assert {:ok, info, "GET / HTTP/1.1\r"} =
               :ranch_proxy_header.parse(
                 "PROXY TCP4 192.168.0.1 192.168.0.11 56324 443\r\nGET / HTTP/1.1\r"
               )

      assert info.version == 1
      assert info.src_address == {192, 168, 0, 1}
      assert info.dest_address == {192, 168, 0, 11}
      assert info.src_port == 56324
      assert info.dest_port == 443
    end

    test "version 2 SSL TLV subtypes group, sig_scheme, and client_cert round-trip" do
      info = %{
        version: 2,
        command: :proxy,
        transport_family: :ipv4,
        transport_protocol: :stream,
        src_address: {127, 0, 0, 1},
        src_port: 1234,
        dest_address: {10, 11, 12, 13},
        dest_port: 23456,
        ssl: %{
          client: [:ssl, :cert_conn, :cert_sess],
          verified: true,
          version: "TLSv1.3",
          cipher: "ECDHE-RSA-AES128-GCM-SHA256",
          sig_alg: "SHA256",
          key_alg: "RSA2048",
          group: "secp256r1",
          sig_scheme: "rsa_pss_rsae_sha256",
          client_cert: <<0x30, 0x03, 1, 2, 3>>,
          cn: "example.com"
        }
      }

      assert {:ok, parsed, ""} =
               :ranch_proxy_header.parse(
                 :ranch_proxy_header.header(info)
                 |> IO.iodata_to_binary()
               )

      assert parsed.ssl.group == "secp256r1"
      assert parsed.ssl.sig_scheme == "rsa_pss_rsae_sha256"
      assert parsed.ssl.client_cert == <<0x30, 0x03, 1, 2, 3>>
    end

    test "source recognizes the new SSL TLV subtypes" do
      source = File.read!(@ranch_proxy)
      assert source =~ "ssl_subtype(16#26) -> group;"
      assert source =~ "ssl_subtype(16#27) -> sig_scheme;"
      assert source =~ "ssl_subtype(16#28) -> client_cert;"

      assert source =~
               "The PROXY protocol header line exceeds 107 bytes. (PP 2.1)"
    end
  end

  describe "2.4 transport callbacks and local-socket cleanup" do
    test "ranch_ssl implements peercert/1 and negotiated_protocol/1" do
      assert function_exported?(:ranch_ssl, :peercert, 1)
      assert function_exported?(:ranch_ssl, :negotiated_protocol, 1)
      refute function_exported?(:ranch_tcp, :peercert, 1)
      refute function_exported?(:ranch_tcp, :negotiated_protocol, 1)

      transport = File.read!(@ranch_transport)

      assert transport =~
               "-optional_callbacks([negotiated_protocol/1, peercert/1])."
    end

    test "cleanup only deletes a {local, Path} file when it is a socket or FIFO" do
      tcp = File.read!(@ranch_tcp)
      ssl = File.read!(@ranch_ssl)

      assert tcp =~
               "{ok, #file_info{type = other}} ?= file:read_link_info(SockFile)"

      assert ssl =~
               "{ok, #file_info{type = other}} ?= file:read_link_info(SockFile)"

      assert tcp =~ "Only a socket (or FIFO) has type other."
    end
  end

  describe "Plug.Cowboy still serves HTTP through ranch 2.4" do
    test "procs/2 lists acceptors and an empty connections pool answers GET" do
      {:ok, socket} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true
        ])

      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      ref = :"ranch_upgrade_#{port}_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Plug.Cowboy.http(Ysc.CowboyUpgradeEchoPlug, [],
                 port: port,
                 ref: ref
               )

      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      acceptors = :ranch.procs(ref, :acceptors)
      assert is_list(acceptors)
      assert acceptors != []
      assert :ranch.procs(ref, :connections) == []
      assert :ranch.get_status(ref) == :running

      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
      assert response.body == "cowboy-upgrade-ok"
    end

    test "set_transport_options/2 updates stored max_connections" do
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
        :"ranch_upgrade_max_#{port}_#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               Plug.Cowboy.http(Ysc.CowboyUpgradeEchoPlug, [],
                 port: port,
                 ref: ref
               )

      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

      before = :ranch.get_max_connections(ref)
      assert before == 16_384 or before == 1024

      assert :ok = :ranch.set_transport_options(ref, %{max_connections: 50})
      assert :ranch.get_max_connections(ref) == 50

      response = Req.get!("http://127.0.0.1:#{port}/")
      assert response.status == 200
    end
  end
end
