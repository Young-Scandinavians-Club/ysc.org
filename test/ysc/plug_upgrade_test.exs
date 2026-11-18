defmodule Ysc.PlugUpgradeTest do
  @moduledoc """
  Guards the plug 1.20.3 → 1.20.4 upgrade.

  1.20.4 patches EEF-CVE-2026-120287 (MEDIUM / GHSA-qj4r-jh2r-rw3f):
  `Plug.Parsers.MULTIPART` now charges part framing and empty headers
  against `:length`. 1.20.3 charged only header name/value and body
  bytes, so parts without headers (or `:`-only header lines) could
  accumulate unbounded parser memory. The public parser API is
  unchanged. Phoenix still lists `plug ~> 1.14`, and 1.20.0/1.20.1
  remain retired, so mix.exs keeps an override pin.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @multipart_src Path.expand(
                   "../../deps/plug/lib/plug/parsers/multipart.ex",
                   __DIR__
                 )
  @changelog Path.expand("../../deps/plug/CHANGELOG.md", __DIR__)
  @endpoint Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)

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
      refute mix_exs =~ ~s({:plug, "~> 1.20.2", override: true})
      refute mix_exs =~ ~s({:plug, "~> 1.20.3", override: true})
    end

    test "companion lock is 1.20.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"plug": {:hex, :plug, "1.20.4"|
      refute lock =~ ~s|"plug": {:hex, :plug, "1.20.3"|
    end

    test "does not ignore the patched advisory" do
      mix_exs = File.read!(@mix_exs)

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      refute ignore =~ "EEF-CVE-2026-120287"
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
      # 1.20.3 charged 0 for each headerless part, so this body parsed as
      # {:ok, %{}, conn}. 1.20.4 charges ~36 bytes of framing per part.
      opts = Plug.Parsers.MULTIPART.init(length: 100)
      body = headerless_multipart(20)

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

    test "empty-name header lines charge toward :length" do
      # A `:` header is {\"\", \"\"}; 1.20.3 charged 0 bytes per line.
      opts = Plug.Parsers.MULTIPART.init(length: 100)
      empty_headers = String.duplicate(":\r\n", 20)
      body = "--b\r\n#{empty_headers}\r\n\r\n--b--\r\n"

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

  defp headerless_multipart(part_count) when part_count > 0 do
    rest = List.duplicate("\r\n--b\r\n\r\n", part_count - 1)
    IO.iodata_to_binary(["--b\r\n\r\n", rest, "\r\n--b--\r\n"])
  end
end
