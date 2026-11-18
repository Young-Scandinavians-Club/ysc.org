defmodule QueryConsole.PlugUpgradeTest do
  @moduledoc """
  Guards the plug 1.20.3 → 1.20.4 upgrade.

  1.20.4 patches EEF-CVE-2026-120287 (MEDIUM / GHSA-qj4r-jh2r-rw3f):
  `Plug.Parsers.MULTIPART` now charges part framing and empty headers
  against `:length`. Query Console reaches Plug through Phoenix and
  enables the `:multipart` parser. Phoenix still lists `plug ~> 1.14`,
  so mix.exs keeps an override pin.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @multipart_src Path.expand(
                   "../../deps/plug/lib/plug/parsers/multipart.ex",
                   __DIR__
                 )
  @changelog Path.expand("../../deps/plug/CHANGELOG.md", __DIR__)
  @endpoint Path.expand("../../lib/query_console_web/endpoint.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:plug)

    {:module, Plug.Parsers.MULTIPART} =
      Code.ensure_loaded(Plug.Parsers.MULTIPART)

    :ok
  end

  describe "1.20.4 Hex lock and public APIs" do
    test "locks the Hex package to 1.20.4" do
      assert to_string(Application.spec(:plug, :vsn)) == "1.20.4"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:plug, "~> 1.20.4", override: true})
    end

    test "companion lock is 1.20.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"plug": {:hex, :plug, "1.20.4"|
      refute lock =~ ~s|"plug": {:hex, :plug, "1.20.3"|
    end

    test "init/1 and parse/5 still exist" do
      assert function_exported?(Plug.Parsers.MULTIPART, :init, 1)
      assert function_exported?(Plug.Parsers.MULTIPART, :parse, 5)
    end

    test "endpoint still enables the multipart parser" do
      assert File.read!(@endpoint) =~
               "parsers: [:urlencoded, :multipart, :json]"
    end
  end

  describe "1.20.4 changelog" do
    test "documents CVE-2026-120287" do
      changelog = File.read!(@changelog)
      assert changelog =~ "CVE-2026-120287"
      assert changelog =~ "Count empty headers towards the length limit"
    end
  end

  describe "EEF-CVE-2026-120287 empty-header parts" do
    test "headers_size charges framing even when headers are empty" do
      source = File.read!(@multipart_src)
      assert source =~ "Charge the framing too, otherwise parts without headers"
      assert source =~ "Enum.reduce(headers, 6 + 30, fn {key, value}, acc ->"
    end

    test "headerless parts charge framing and hit :length" do
      opts = Plug.Parsers.MULTIPART.init(length: 100)
      rest = List.duplicate("\r\n--b\r\n\r\n", 19)
      body = IO.iodata_to_binary(["--b\r\n\r\n", rest, "\r\n--b--\r\n"])

      conn =
        :post
        |> Plug.Test.conn("/", body)
        |> Plug.Conn.put_req_header(
          "content-type",
          "multipart/form-data; boundary=b"
        )

      assert {:error, :too_large, %Plug.Conn{}} =
               Plug.Parsers.MULTIPART.parse(
                 conn,
                 "multipart",
                 "form-data",
                 [],
                 opts
               )
    end

    test "a named part under the limit still parses" do
      opts = Plug.Parsers.MULTIPART.init(length: 8_000_000)

      body =
        "--b\r\ncontent-disposition: form-data; name=\"x\"\r\n\r\nhello\r\n--b--\r\n"

      conn =
        :post
        |> Plug.Test.conn("/", body)
        |> Plug.Conn.put_req_header(
          "content-type",
          "multipart/form-data; boundary=b"
        )

      assert {:ok, %{"x" => "hello"}, %Plug.Conn{}} =
               Plug.Parsers.MULTIPART.parse(
                 conn,
                 "multipart",
                 "form-data",
                 [],
                 opts
               )
    end
  end
end
