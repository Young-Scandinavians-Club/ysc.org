defmodule QueryConsole.MintUpgradeTest do
  @moduledoc """
  Guards the mint 1.10.1 → 1.11.0 upgrade.

  1.11.0 is a minor with no documented breaking changes. It patches:

  * EEF-CVE-2026-91043 — `Mint.HTTP2` now measures the decoded header list
    against `max_header_list_size` (HPACK-indexed `cookie` fields previously
    bypassed the compressed-size check).
  * EEF-CVE-2026-92103 — `Mint.HTTP2.Frame.decode_next/2` rejects a frame
    whose declared length exceeds `max_frame_size` before buffering the
    payload.
  * EEF-CVE-2026-94194 — `Mint.HTTP1` uses chunked framing only when
    `chunked` is the final transfer coding.

  Query Console reaches mint through Finch and Req (`Req.post/2` for SSO
  token exchange). Public connect / stream APIs are unchanged. Finch still
  lists mint `~> 1.8`, so mix.exs keeps an override pin. mint 1.11.0
  requires hpax `~> 1.1`; we do not call HPAX.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @http1 Path.expand("../../deps/mint/lib/mint/http1.ex", __DIR__)
  @http2 Path.expand("../../deps/mint/lib/mint/http2.ex", __DIR__)
  @frame Path.expand("../../deps/mint/lib/mint/http2/frame.ex", __DIR__)
  @changelog Path.expand("../../deps/mint/CHANGELOG.md", __DIR__)
  @sso_src Path.expand("../../lib/query_console/sso.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:mint)
    {:module, Mint.HTTP} = Code.ensure_loaded(Mint.HTTP)
    {:module, Mint.HTTP1} = Code.ensure_loaded(Mint.HTTP1)
    {:module, Mint.HTTP2} = Code.ensure_loaded(Mint.HTTP2)
    {:module, Mint.HTTP2.Frame} = Code.ensure_loaded(Mint.HTTP2.Frame)
    {:module, Req} = Code.ensure_loaded(Req)
    :ok
  end

  describe "1.11.0 Hex lock and public APIs" do
    test "locks the Hex package to 1.11.0" do
      assert to_string(Application.spec(:mint, :vsn)) == "1.11.0"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:mint, "~> 1.11.0", override: true})
    end

    test "companion hpax lock is 1.1.0 as required by mint 1.11" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"mint": {:hex, :mint, "1.11.0"|
      assert lock =~ ~s|"hpax": {:hex, :hpax, "1.1.0"|
    end

    test "connect and stream APIs Finch and Req use still exist" do
      assert function_exported?(Mint.HTTP, :connect, 3)
      assert function_exported?(Mint.HTTP, :connect, 4)
      assert function_exported?(Mint.HTTP, :request, 5)
      assert function_exported?(Mint.HTTP, :stream, 2)
      assert function_exported?(Mint.HTTP, :stream_request_body, 3)
      assert function_exported?(Mint.HTTP, :close, 1)
      assert function_exported?(Mint.HTTP1, :connect, 3)
      assert function_exported?(Mint.HTTP2, :connect, 3)
      assert function_exported?(Req, :post, 2)
    end

    test "SSO still exchanges tokens with Req.post, not Mint" do
      sso = File.read!(@sso_src)
      assert sso =~ "Req.post(conf.token_url, json: body)"
      refute sso =~ "Mint."
    end
  end

  describe "1.11.0 changelog" do
    test "documents the three 2026-09-28 CVEs and no breaking changes" do
      changelog = File.read!(@changelog)
      assert changelog =~ "no breaking changes"
      assert changelog =~ "CVE-2026-91043"
      assert changelog =~ "CVE-2026-92103"
      assert changelog =~ "CVE-2026-94194"
    end
  end

  describe "EEF-CVE-2026-92103 HTTP/2 frame length before buffering" do
    test "decode_next rejects an oversized declared length with no payload" do
      # 24-bit length 1_000_000, DATA, flags 0, stream 1 — header only.
      header = <<1_000_000::24, 0x00, 0x00, 0::1, 1::31>>

      assert {:error, :payload_too_big} =
               Mint.HTTP2.Frame.decode_next(header, 16_384)
    end

    test "frame decoder checks length against max_frame_size before matching payload" do
      source = File.read!(@frame)

      assert source =~
               "def decode_next(<<length::24, _header::binary-size(6), _rest::binary>>, max_frame_size)"

      assert source =~ "when length > max_frame_size do"
      assert source =~ "{:error, :payload_too_big}"
    end
  end

  describe "EEF-CVE-2026-91043 decoded header list size" do
    test "HTTP/2 checks decoded headers against client max_header_list_size" do
      source = File.read!(@http2)
      assert source =~ "error = header_list_size_error(conn, headers) ->"
      assert source =~ "defp header_list_size_error(conn, headers) do"
      assert source =~ "case conn.client_settings.max_header_list_size do"
    end
  end

  describe "EEF-CVE-2026-94194 chunked as final transfer coding" do
    test "HTTP/1 uses chunked framing only when chunked is last" do
      source = File.read!(@http1)
      assert source =~ ~s|"chunked" == List.last(request.transfer_encoding) ->|
      assert source =~ "{:ok, {:chunked, nil}}"
      assert source =~ "request.transfer_encoding != [] ->"
      assert source =~ "{:ok, :until_closed}"
    end
  end
end
