defmodule QueryConsole.LazyHtmlUpgradeTest do
  @moduledoc """
  Guards the lazy_html 0.1.12 → 0.1.13 upgrade.

  0.1.13 is a patch: `to_html/2` escapes `<style>` / `<script>` text
  inside SVG and MathML (EEF-CVE-2026-92106) so a parse/serialize
  round-trip cannot turn encoded markup into live tags. Query Console
  uses lazy_html only as a test dependency for LiveViewTest
  (`from_fragment`, `from_document`, `query`, `to_html`). Public query
  APIs are unchanged. `css_path/1` is unused.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @nif_src Path.expand("../../deps/lazy_html/c_src/lazy_html.cpp", __DIR__)
  @changelog Path.expand("../../deps/lazy_html/CHANGELOG.md", __DIR__)
  @dom_src Path.expand(
             "../../deps/phoenix_live_view/lib/phoenix_live_view/test/dom.ex",
             __DIR__
           )

  @svg_style_breakout ~S|<svg><style>&lt;/style&gt;&lt;img src=x onerror=alert(1)&gt;</style></svg>|

  setup_all do
    {:ok, _} = Application.ensure_all_started(:lazy_html)
    {:module, LazyHTML} = Code.ensure_loaded(LazyHTML)
    {:module, LazyHTML.Tree} = Code.ensure_loaded(LazyHTML.Tree)
    :ok
  end

  describe "0.1.13 Hex lock and public APIs" do
    test "locks the Hex package to 0.1.13" do
      assert to_string(Application.spec(:lazy_html, :vsn)) == "0.1.13"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:lazy_html, "~> 0.1.13", only: :test})
    end

    test "LiveViewTest APIs still exist" do
      assert function_exported?(LazyHTML, :from_fragment, 1)
      assert function_exported?(LazyHTML, :from_document, 1)
      assert function_exported?(LazyHTML, :to_html, 1)
      assert function_exported?(LazyHTML, :to_html, 2)
      assert function_exported?(LazyHTML, :to_tree, 1)
      assert function_exported?(LazyHTML, :query, 2)
      assert function_exported?(LazyHTML, :query_by_id, 2)
      assert function_exported?(LazyHTML, :text, 1)
      assert function_exported?(LazyHTML.Tree, :to_html, 1)
    end
  end

  describe "0.1.13 SVG style escaping (EEF-CVE-2026-92106)" do
    test "NIF source only treats HTML style/script as raw text" do
      source = File.read!(@nif_src)

      assert source =~ "Only HTML elements have raw text content"
      assert source =~ "node->parent->ns == LXB_NS_HTML"
    end

    test "changelog documents the SVG/MathML serialize fix" do
      changelog = File.read!(@changelog)

      assert changelog =~ "CVE-2026-92106"
      assert changelog =~ "SVG and MathML"
    end

    test "LiveViewTest still serializes with LazyHTML.to_html/2" do
      assert File.read!(@dom_src) =~
               "LazyHTML.to_html(lazy, skip_whitespace_nodes: true)"
    end

    test "SVG style encoded breakout stays text after to_html round-trip" do
      serialized = @svg_style_breakout |> LazyHTML.from_fragment() |> LazyHTML.to_html()
      reparsed = LazyHTML.from_fragment(serialized)

      assert Enum.empty?(LazyHTML.query(reparsed, "img"))
      refute serialized =~ ~S|<img src=x|
    end
  end
end
