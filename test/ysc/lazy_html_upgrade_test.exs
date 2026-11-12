defmodule Ysc.LazyHtmlUpgradeTest do
  @moduledoc """
  Guards the lazy_html 0.1.13 → 0.1.14 upgrade.

  0.1.14 is additive: `from_document/2` and `from_fragment/2` accept
  optional `:max_depth`, `:max_memory`, `:max_attributes`, and
  `:timeout` (default unlimited). Limits raise `RuntimeError`. extras:
  fine 0.1.6 → 0.2.0 (`~> 0.2.0`) and elixir_make 0.10.0 → 0.10.1.
  We query HTML in tests via LiveViewTest (`from_fragment`,
  `from_document`, `query`, `query_by_id`, `filter`, `text`,
  `attribute`, `to_html`) without passing limits, and do not sanitize
  untrusted HTML with lazy_html (that is `html_sanitize_ex`).
  `css_path/1` is unused. Public query APIs are unchanged.

  0.1.13 still applies: `to_html/2` and `LazyHTML.Tree.to_html/2`
  escape `<style>` / `<script>` text inside SVG and MathML
  (EEF-CVE-2026-92106).
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @nif_src Path.expand("../../deps/lazy_html/c_src/lazy_html.cpp", __DIR__)
  @lazy_src Path.expand("../../deps/lazy_html/lib/lazy_html.ex", __DIR__)
  @tree_src Path.expand("../../deps/lazy_html/lib/lazy_html/tree.ex", __DIR__)
  @changelog Path.expand("../../deps/lazy_html/CHANGELOG.md", __DIR__)
  @dom_src Path.expand(
             "../../deps/phoenix_live_view/lib/phoenix_live_view/test/dom.ex",
             __DIR__
           )
  @tree_dom_src Path.expand(
                  "../../deps/phoenix_live_view/lib/phoenix_live_view/test/tree_dom.ex",
                  __DIR__
                )

  @svg_style_breakout ~S|<svg><style>&lt;/style&gt;&lt;img src=x onerror=alert(1)&gt;</style></svg>|
  @svg_script_breakout ~S|<svg><script>&lt;/script&gt;&lt;img src=x onerror=alert(1)&gt;</script></svg>|
  @math_style_breakout ~S|<math><style>&lt;/style&gt;&lt;img src=x onerror=alert(1)&gt;</style></math>|

  setup_all do
    {:ok, _} = Application.ensure_all_started(:lazy_html)
    {:module, LazyHTML} = Code.ensure_loaded(LazyHTML)
    {:module, LazyHTML.Tree} = Code.ensure_loaded(LazyHTML.Tree)
    :ok
  end

  describe "0.1.14 Hex lock and public APIs" do
    test "locks the Hex package to 0.1.14" do
      assert to_string(Application.spec(:lazy_html, :vsn)) == "0.1.14"
    end

    test "mix.exs pins the 0.1.14 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:lazy_html, "~> 0.1.14", only: :test})
    end

    test "companion lock is 0.1.14 with fine 0.2.0 and elixir_make 0.10.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"lazy_html": {:hex, :lazy_html, "0.1.14"|
      refute lock =~ ~s|"lazy_html": {:hex, :lazy_html, "0.1.13"|
      assert lock =~ ~s|"fine": {:hex, :fine, "0.2.0"|
      refute lock =~ ~s|"fine": {:hex, :fine, "0.1.6"|
      assert lock =~ ~s|"elixir_make": {:hex, :elixir_make, "0.10.1"|
    end

    test "query APIs tests and LiveViewTest use still exist" do
      assert {:module, _} = Code.ensure_loaded(LazyHTML)
      assert function_exported?(LazyHTML, :from_fragment, 1)
      assert function_exported?(LazyHTML, :from_fragment, 2)
      assert function_exported?(LazyHTML, :from_document, 1)
      assert function_exported?(LazyHTML, :from_document, 2)
      assert function_exported?(LazyHTML, :from_tree, 1)
      assert function_exported?(LazyHTML, :to_html, 1)
      assert function_exported?(LazyHTML, :to_html, 2)
      assert function_exported?(LazyHTML, :to_tree, 1)
      assert function_exported?(LazyHTML, :to_tree, 2)
      assert function_exported?(LazyHTML, :query, 2)
      assert function_exported?(LazyHTML, :query_by_id, 2)
      assert function_exported?(LazyHTML, :filter, 2)
      assert function_exported?(LazyHTML, :text, 1)
      assert function_exported?(LazyHTML, :text, 2)
      assert function_exported?(LazyHTML, :attribute, 2)
      assert function_exported?(LazyHTML, :tag, 1)
      assert function_exported?(LazyHTML, :child_nodes, 1)
      assert function_exported?(LazyHTML.Tree, :to_html, 1)
      assert function_exported?(LazyHTML.Tree, :to_html, 2)
    end

    test "css_path/1 is exported and unused in app code" do
      assert function_exported?(LazyHTML, :css_path, 1)
    end
  end

  describe "0.1.14 parse limits" do
    test "changelog documents the additive parse-limit options" do
      changelog = File.read!(@changelog)

      assert changelog =~ "[v0.1.14]"
      assert changelog =~ ":max_depth"
      assert changelog =~ ":max_memory"
      assert changelog =~ ":max_attributes"
      assert changelog =~ ":timeout"
      assert changelog =~ "from_document/2"
      assert changelog =~ "from_fragment/2"
    end

    test "from_document/2 and from_fragment/2 validate the new option names" do
      source = File.read!(@lazy_src)

      assert source =~
               "opts = Keyword.validate!(opts, [:max_depth, :max_memory, :max_attributes, :timeout])"

      assert source =~ "def from_document(html, opts \\\\ [])"
      assert source =~ "def from_fragment(html, opts \\\\ [])"
    end

    test "NIF source raises RuntimeError messages for each exceeded limit" do
      source = File.read!(@nif_src)

      assert source =~ "elements nest deeper than "
      assert source =~ ":max_depth ("
      assert source =~ "the document takes more "
      assert source =~ "memory than :max_memory ("
      assert source =~ "a tag has more attributes "
      assert source =~ "than :max_attributes ("
      assert source =~ "parsing took longer than "
      assert source =~ ":timeout ("
    end

    test "LiveViewTest still parses without passing limits" do
      dom = File.read!(@dom_src)

      assert dom =~ "lazydoc = LazyHTML.from_document(html)"
      assert dom =~ "lazydoc = LazyHTML.from_fragment(html)"
      refute dom =~ "max_depth"
      refute dom =~ "max_memory"
      refute dom =~ "max_attributes"
      refute dom =~ "timeout:"
    end

    test "unlimited defaults still parse nested markup" do
      html = ~S|<div id="root" class="wrap"><span>hello</span></div>|
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.query(doc, "span") |> LazyHTML.text() == "hello"
      assert LazyHTML.query_by_id(doc, "root") |> Enum.any?()
      assert LazyHTML.filter(doc, "div") |> Enum.any?()
      assert LazyHTML.attribute(doc, "class") == ["wrap"]
    end

    test "from_fragment max_depth: 1 parses a single-level tag" do
      doc = LazyHTML.from_fragment("<div>hello</div>", max_depth: 1)
      assert LazyHTML.text(doc) == "hello"
    end

    test "from_fragment raises RuntimeError when nesting exceeds max_depth" do
      html = ~S|<div><span>x</span></div>|

      assert_raise RuntimeError,
                   "failed to parse html, elements nest deeper than :max_depth (1)",
                   fn ->
                     LazyHTML.from_fragment(html, max_depth: 1)
                   end
    end

    test "from_document raises RuntimeError when wrapping exceeds max_depth" do
      assert_raise RuntimeError,
                   "failed to parse html, elements nest deeper than :max_depth (1)",
                   fn ->
                     LazyHTML.from_document("<div>x</div>", max_depth: 1)
                   end
    end

    test "from_fragment raises RuntimeError when a tag exceeds max_attributes" do
      html = ~s|<div a="1" b="2" c="3">x</div>|

      assert_raise RuntimeError,
                   "failed to parse html, a tag has more attributes than :max_attributes (2)",
                   fn ->
                     LazyHTML.from_fragment(html, max_attributes: 2)
                   end
    end

    test "from_fragment raises RuntimeError when the tree exceeds max_memory" do
      html = String.duplicate("<p>x</p>", 50)

      assert_raise RuntimeError,
                   "failed to parse html, the document takes more memory than :max_memory (64 bytes)",
                   fn ->
                     LazyHTML.from_fragment(html, max_memory: 64)
                   end
    end

    test "from_fragment with a generous timeout still parses" do
      doc = LazyHTML.from_fragment("<div>hello</div>", timeout: 5_000)
      assert LazyHTML.text(doc) == "hello"
    end

    test "unknown parse option is rejected" do
      assert_raise ArgumentError, fn ->
        LazyHTML.from_fragment("<div>x</div>", unknown: true)
      end
    end
  end

  describe "0.1.13 SVG/MathML style and script escaping (EEF-CVE-2026-92106)" do
    test "NIF source only treats HTML style/script as raw text" do
      source = File.read!(@nif_src)

      assert source =~ "Only HTML elements have raw text content"
      assert source =~ "node->parent->ns == LXB_NS_HTML"
      assert source =~ "case LXB_TAG_STYLE:"
      assert source =~ "case LXB_TAG_SCRIPT:"
    end

    test "Tree.to_html infers SVG/MathML namespaces before skipping escape" do
      tree = File.read!(@tree_src)

      assert tree =~
               "escape_children = ns != :html or tag not in @no_escape_tags"

      assert tree =~
               ~s|defp element_ns("svg", ns) when ns in [:html, :math_text], do: :svg|

      assert tree =~
               ~s|defp element_ns("math", ns) when ns in [:html, :math_text], do: :math|
    end

    test "changelog still documents the SVG/MathML serialize fix" do
      changelog = File.read!(@changelog)

      assert changelog =~ "CVE-2026-92106"
      assert changelog =~ "GHSA-8rqp-v692-v82q"
      assert changelog =~ "SVG and MathML"
      assert changelog =~ "css_path/1"
    end

    test "LiveViewTest still serializes with LazyHTML.to_html/2" do
      dom = File.read!(@dom_src)
      tree_dom = File.read!(@tree_dom_src)

      assert dom =~ "lazydoc = LazyHTML.from_document(html)"
      assert dom =~ "lazydoc = LazyHTML.from_fragment(html)"
      assert dom =~ "LazyHTML.to_html(lazy, skip_whitespace_nodes: true)"

      assert tree_dom =~
               "LazyHTML.Tree.to_html(List.wrap(html), skip_whitespace_nodes: true)"
    end

    test "SVG style encoded breakout stays text after to_html round-trip" do
      serialized =
        @svg_style_breakout |> LazyHTML.from_fragment() |> LazyHTML.to_html()

      reparsed = LazyHTML.from_fragment(serialized)

      assert Enum.empty?(LazyHTML.query(reparsed, "img"))
      refute serialized =~ ~S|<img src=x|
      assert serialized =~ "&lt;/style&gt;" or serialized =~ "&lt;img"
    end

    test "SVG script encoded breakout stays text after to_html round-trip" do
      serialized =
        @svg_script_breakout |> LazyHTML.from_fragment() |> LazyHTML.to_html()

      reparsed = LazyHTML.from_fragment(serialized)

      assert Enum.empty?(LazyHTML.query(reparsed, "img"))
      refute serialized =~ ~S|<img src=x|
    end

    test "MathML style encoded breakout stays text after to_html round-trip" do
      serialized =
        @math_style_breakout |> LazyHTML.from_fragment() |> LazyHTML.to_html()

      reparsed = LazyHTML.from_fragment(serialized)

      assert Enum.empty?(LazyHTML.query(reparsed, "img"))
      refute serialized =~ ~S|<img src=x|
    end

    test "Tree.to_html escapes style text inside SVG" do
      tree = [
        {"svg", [],
         [
           {"style", [], ["</style><img src=x onerror=alert(1)>"]}
         ]}
      ]

      serialized = LazyHTML.Tree.to_html(tree)
      reparsed = LazyHTML.from_fragment(serialized)

      assert Enum.empty?(LazyHTML.query(reparsed, "img"))
      refute serialized =~ ~S|<img src=x|
      assert serialized =~ "&lt;/style&gt;" or serialized =~ "&lt;img"
    end

    test "HTML style still serializes as raw text" do
      html = ~S|<style>body { color: red }</style>|
      serialized = html |> LazyHTML.from_fragment() |> LazyHTML.to_html()

      assert serialized =~ "color: red"
    end

    test "query helpers used in tests still find nodes after serialize" do
      html = ~S|<div id="root" class="wrap"><span>hello</span></div>|
      doc = LazyHTML.from_fragment(html)

      assert LazyHTML.query(doc, "span") |> LazyHTML.text() == "hello"
      assert LazyHTML.query_by_id(doc, "root") |> Enum.any?()
      assert LazyHTML.filter(doc, "div") |> Enum.any?()
      assert LazyHTML.attribute(doc, "class") == ["wrap"]

      round_trip = doc |> LazyHTML.to_html() |> LazyHTML.from_fragment()
      assert LazyHTML.query(round_trip, "span") |> LazyHTML.text() == "hello"
    end
  end
end
