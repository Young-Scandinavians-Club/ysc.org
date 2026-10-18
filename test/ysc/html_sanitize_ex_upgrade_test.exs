defmodule Ysc.HtmlSanitizeExUpgradeTest do
  @moduledoc """
  Guards the html_sanitize_ex 1.5.5 → 1.5.6 upgrade.

  1.5.6 is a patch with no documented breaking changes. It:

  * Decodes invalid CSS escapes (UTF-16 surrogates and code points past
    U+10FFFF) as U+FFFD in `HtmlSanitizeEx.Scrubber.CSS.scrub/1` instead of
    crashing on `<<code::utf8>>`.
  * Tightens HTML5 `object data=` so `http:` / `https:` URLs are dropped
    (changelog: CVE to be published). We scrub with BasicHTML, TrixScrubber,
    and `strip_tags/1`, not HTML5, and we do not call `CSS.scrub/1` in app
    code. Public APIs are unchanged.
  """
  use ExUnit.Case, async: true

  alias HtmlSanitizeEx.Scrubber

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/html_sanitize_ex/CHANGELOG.md", __DIR__)
  @css_src Path.expand(
             "../../deps/html_sanitize_ex/lib/html_sanitize_ex/scrubber/css.ex",
             __DIR__
           )
  @html5_src Path.expand(
               "../../deps/html_sanitize_ex/lib/html_sanitize_ex/scrubber/html5.ex",
               __DIR__
             )
  @trix Path.expand("../../lib/ysc/trix_scrubber.ex", __DIR__)
  @post Path.expand("../../lib/ysc/posts/post.ex", __DIR__)
  @plain_text Path.expand("../../lib/ysc_web/plain_text.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:html_sanitize_ex)
    {:module, HtmlSanitizeEx} = Code.ensure_loaded(HtmlSanitizeEx)
    {:module, Scrubber} = Code.ensure_loaded(Scrubber)
    {:module, Scrubber.CSS} = Code.ensure_loaded(Scrubber.CSS)
    {:module, Scrubber.BasicHTML} = Code.ensure_loaded(Scrubber.BasicHTML)
    {:module, Scrubber.HTML5} = Code.ensure_loaded(Scrubber.HTML5)
    {:module, Ysc.TrixScrubber} = Code.ensure_loaded(Ysc.TrixScrubber)
    :ok
  end

  describe "1.5.6 Hex lock and public APIs" do
    test "locks html_sanitize_ex to 1.5.6" do
      assert to_string(Application.spec(:html_sanitize_ex, :vsn)) == "1.5.6"
    end

    test "mix.exs pins the 1.5.6 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:html_sanitize_ex, "~> 1.5.6"}|
    end

    test "companion lock is 1.5.6" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"html_sanitize_ex": {:hex, :html_sanitize_ex, "1.5.6"|
      refute lock =~ ~s|"html_sanitize_ex": {:hex, :html_sanitize_ex, "1.5.5"|
    end

    test "public sanitize APIs still load" do
      assert {:module, _} = Code.ensure_loaded(HtmlSanitizeEx)
      assert function_exported?(HtmlSanitizeEx, :strip_tags, 1)
      assert function_exported?(HtmlSanitizeEx, :basic_html, 1)
      assert function_exported?(HtmlSanitizeEx, :html5, 1)
      assert function_exported?(Scrubber, :scrub, 2)
      assert function_exported?(Scrubber.CSS, :scrub, 1)
    end
  end

  describe "1.5.6 changelog" do
    test "documents invalid CSS escapes and object data tightening" do
      changelog = File.read!(@changelog)

      v156 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "1.5.6"))

      assert v156
      assert v156 =~ "Handling invalid CSS escapes"

      assert v156 =~
               "CVE to be published (handling of malicious data attribute in <meta> tags)"

      refute v156 =~ "Breaking"
    end
  end

  describe "1.5.6 source" do
    test "CSS.scrub maps surrogates and > U+10FFFF to U+FFFD" do
      source = File.read!(@css_src)

      assert source =~
               "hex |> String.to_integer(16) |> escaped_code_point()"

      assert source =~
               "defp escaped_code_point(code) when code in 0xD800..0xDFFF or code > 0x10FFFF, do: \"\\uFFFD\""

      refute source =~ "<<String.to_integer(hex, 16)::utf8>>"
    end

    test "HTML5 object data= rejects http(s) URLs" do
      source = File.read!(@html5_src)
      assert source =~ ~S|value =~ ~r/^https?:/i -> nil|
    end
  end

  describe "app still uses BasicHTML / Trix / strip_tags, not HTML5" do
    test "TrixScrubber, BasicHTML, and strip_tags remain the production scrubbers" do
      trix = File.read!(@trix)
      post = File.read!(@post)
      plain_text = File.read!(@plain_text)

      assert trix =~ "HtmlSanitizeEx.ScrubberCompiler"
      assert post =~ "HtmlSanitizeEx.Scrubber.BasicHTML"
      assert plain_text =~ "HtmlSanitizeEx.strip_tags()"
      refute post =~ "HtmlSanitizeEx.html5"
      refute trix =~ "HtmlSanitizeEx.Scrubber.HTML5"
    end
  end
end
